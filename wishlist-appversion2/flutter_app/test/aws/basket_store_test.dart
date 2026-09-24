import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/models/models.dart';
import 'package:figmadesign/services/aws/basket_store.dart';
import 'package:figmadesign/services/aws/gql_runner.dart';
import 'package:figmadesign/services/aws/polling.dart';
import 'package:figmadesign/services/aws/social_store.dart';
import 'package:figmadesign/services/aws/user_data_store.dart';

import 'fake_appsync.dart';

/// 비동기 작업들이 끝날 때까지 이벤트 루프를 몇 번 돌린다.
Future<void> pump() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeAppSync appsync;
  late RefreshHub hub;
  late AwsUserDataStore data;
  late AwsSocialStore social;
  late AwsBasketStore baskets;

  Future<void> signUp(String uid, String name) async {
    appsync.caller = uid;
    await data.ensureProfile(uid: uid, email: '$uid@x.com', name: name, handle: uid);
  }

  Product product(int id, {String? memo}) => Product(
        id: id,
        listId: 'all',
        name: '상품$id',
        price: 1000 * id,
        image: '',
        platform: '무신사',
        memo: memo,
      );

  /// 스트림을 듣기 시작하고, 받은 값을 모으는 리스트를 돌려준다.
  Future<(List<T>, StreamSubscription<T>)> listen<T>(Stream<T> s) async {
    final got = <T>[];
    final sub = s.listen(got.add);
    await pump();
    return (got, sub);
  }

  setUp(() async {
    appsync = FakeAppSync('');
    data = AwsUserDataStore(runner: appsync);
    social = AwsSocialStore(runner: appsync);
    hub = RefreshHub();
    baskets = AwsBasketStore(
      runner: appsync,
      hub: hub,
      // 테스트에서는 타이머 대신 "행동 직후 새로고침"만 확인한다
      inboxInterval: const Duration(hours: 1),
      commentsInterval: const Duration(hours: 1),
    );
    await signUp('amy', '에이미');
    await signUp('bob', '밥');
    await signUp('cho', '초');
    appsync.caller = 'amy';
  });

  group('살까말까 보내기', () {
    test('받은 사람의 받은함과 알림에 들어간다. 보낸 사람 정보는 서버가 채운다', () async {
      final n = await baskets.sendBasket(
        recipientUids: ['bob', 'cho'],
        items: [product(1, memo: '내 비밀 메모')],
        threadId: 'sb-1',
        memo: '뭐 살까',
      );
      expect(n, 2);

      appsync.caller = 'bob';
      final got = await baskets.loadReceivedBaskets('bob');
      expect(got.single.ownerName, '에이미');
      expect(got.single.fromUid, 'amy');
      expect(got.single.items.single.name, '상품1');
      expect(got.single.items.single.memo, isNull, reason: '개인 메모는 친구에게 가지 않는다');
      expect(got.single.threadId, 'sb-1');

      final notes = await baskets.loadNotifications('bob');
      expect(notes.single.type, AppNotificationType.basket);
      expect(notes.single.fromName, '에이미');
      expect(notes.single.read, isFalse);
    });

    test('남의 받은함·알림함에는 앱이 직접 쓸 수 없다', () async {
      await expectLater(
        appsync.mutate(
          'mutation { createNotification(input: \$input) { recipientId } }',
          variables: {
            'input': {'recipientId': 'bob', 'notificationId': 'fake', 'type': 'x', 'read': false, 'data': '{}'},
          },
        ),
        throwsA(isA<AwsDataException>()),
      );
    });

    test('남의 받은함은 읽을 수 없다', () async {
      await expectLater(
        baskets.loadReceivedBaskets('bob'),
        throwsA(isA<AwsDataException>()),
      );
    });

    test('남의 댓글방 번호로는 보낼 수 없다 (한국어 안내)', () async {
      await baskets.sendBasket(recipientUids: ['bob'], items: [product(1)], threadId: 'sb-x');
      appsync.caller = 'cho';
      await expectLater(
        baskets.sendBasket(recipientUids: ['bob'], items: [product(1)], threadId: 'sb-x'),
        throwsA(predicate((e) => e.toString().contains('공유 번호가 겹쳤어요'))),
      );
    });

    test('보낸 기록 저장·다시 저장·불러오기', () async {
      final basket = SharedBasket(
        id: 'b1',
        title: '에이미의 살까말까',
        ownerName: '에이미',
        items: [product(1)],
        createdAt: DateTime.utc(2026, 9, 1),
        recipientUids: const ['bob'],
      );
      await baskets.upsertSentBasket('amy', basket);
      await baskets.upsertSentBasket('amy', basket); // 두 번째는 수정
      final sent = await baskets.loadSentBaskets('amy');
      expect(sent.single.id, 'b1');
      expect(sent.single.recipientUids, ['bob']);
    });
  });

  group('댓글', () {
    setUp(() async {
      await baskets.sendBasket(recipientUids: ['bob'], items: [product(1)], threadId: 'sb-2');
    });

    test('참여자는 댓글을 쓰고, 글쓴이 정보는 서버가 채운다', () async {
      appsync.caller = 'bob';
      await baskets.addComment(threadId: 'sb-2', text: '  좋아 보여  ');
      final list = await baskets.loadComments('sb-2');
      expect(list.single.text, '좋아 보여');
      expect(list.single.authorName, '밥');
    });

    test('참여자가 아니면 읽지도 쓰지도 못한다', () async {
      appsync.caller = 'cho';
      expect(await baskets.loadComments('sb-2'), isEmpty);
      await expectLater(
        baskets.addComment(threadId: 'sb-2', text: '끼어들기'),
        throwsA(predicate((e) => e.toString().contains('참여한 사람만'))),
      );
    });

    test('나중에 초대된 사람도 이전 댓글을 본다', () async {
      appsync.caller = 'bob';
      await baskets.addComment(threadId: 'sb-2', text: '먼저 쓴 댓글');
      appsync.caller = 'amy';
      await baskets.sendBasket(recipientUids: ['cho'], items: [product(1)], threadId: 'sb-2');
      appsync.caller = 'cho';
      expect((await baskets.loadComments('sb-2')).single.text, '먼저 쓴 댓글');
    });

    test('답글의 답글은 원댓글에 붙는다', () async {
      appsync.caller = 'bob';
      await baskets.addComment(threadId: 'sb-2', text: '원댓글');
      final root = (await baskets.loadComments('sb-2')).single;
      appsync.caller = 'amy';
      await baskets.addComment(threadId: 'sb-2', text: '답글', parentId: root.id);
      final reply = (await baskets.loadComments('sb-2')).last;
      appsync.caller = 'bob';
      await baskets.addComment(threadId: 'sb-2', text: '답답글', parentId: reply.id);
      final last = (await baskets.loadComments('sb-2')).last;
      expect(last.parentId, root.id);
    });

    test('내 댓글만 고치고 지울 수 있다', () async {
      appsync.caller = 'bob';
      await baskets.addComment(threadId: 'sb-2', text: '원래 글');
      final c = (await baskets.loadComments('sb-2')).single;

      appsync.caller = 'amy';
      await expectLater(
        baskets.editComment(threadId: 'sb-2', commentId: c.id, text: '조작'),
        throwsA(predicate((e) => e.toString().contains('내 댓글만'))),
      );
      await expectLater(
        baskets.removeComment(threadId: 'sb-2', commentId: c.id),
        throwsA(predicate((e) => e.toString().contains('내 댓글만'))),
      );

      appsync.caller = 'bob';
      await baskets.editComment(threadId: 'sb-2', commentId: c.id, text: '고친 글');
      final edited = (await baskets.loadComments('sb-2')).single;
      expect(edited.text, '고친 글');
      expect(edited.isEdited, isTrue);
      await baskets.removeComment(threadId: 'sb-2', commentId: c.id);
      expect(await baskets.loadComments('sb-2'), isEmpty);
    });

    test('댓글 화면: 내가 쓰면 기다리지 않고 바로 새로 보인다', () async {
      appsync.caller = 'bob';
      final (got, sub) = await listen(baskets.watchComments('sb-2'));
      expect(got.single, isEmpty);

      await baskets.addComment(threadId: 'sb-2', text: '실시간?');
      await pump();
      expect(got.last.single.text, '실시간?');

      // 새로고침했는데 내용이 같으면 다시 내보내지 않는다 (화면 깜빡임 방지)
      final before = got.length;
      hub.refresh('comments:sb-2');
      await pump();
      expect(got.length, before);
      await sub.cancel();
    });
  });

  group('알림', () {
    test('읽음 표시하면 알림 화면이 바로 갱신된다', () async {
      await baskets.sendBasket(recipientUids: ['bob'], items: [product(1)], threadId: 'sb-3');
      appsync.caller = 'bob';
      final (got, sub) = await listen(baskets.watchNotifications('bob'));
      expect(got.last.single.read, isFalse);

      await baskets.markNotificationsRead('bob', [got.last.single.id]);
      await pump();
      expect(got.last.single.read, isTrue);
      await sub.cancel();
    });

    test('팔로우 알림: 실제로 팔로우해야 가고, 다시 팔로우해도 1개', () async {
      await baskets.notifyFollow('bob'); // 팔로우 안 한 상태 → 조용히 무시
      await social.setFollowing(myUid: 'amy', targetUid: 'bob', follow: true);
      await baskets.notifyFollow('bob');
      await social.setFollowing(myUid: 'amy', targetUid: 'bob', follow: false);
      await social.setFollowing(myUid: 'amy', targetUid: 'bob', follow: true);
      await baskets.notifyFollow('bob');

      appsync.caller = 'bob';
      final notes = await baskets.loadNotifications('bob');
      expect(notes.where((n) => n.type == AppNotificationType.follow).length, 1);
    });
  });

  test('회원 탈퇴: 내 알림·받은함·보낸 기록이 지워진다', () async {
    appsync.caller = 'bob';
    await baskets.sendBasket(recipientUids: ['amy'], items: [product(1)], threadId: 'sb-4');
    appsync.caller = 'amy';
    await baskets.upsertSentBasket(
      'amy',
      SharedBasket(id: 's1', title: 't', ownerName: '에이미', items: [product(1)], createdAt: DateTime.utc(2026)),
    );
    await baskets.deleteAll('amy');
    for (final t in ['Notification', 'ReceivedBasket']) {
      expect(appsync.table(t).values.where((r) => r['recipientId'] == 'amy'), isEmpty);
    }
    expect(appsync.table('SentBasket'), isEmpty);
  });
}
