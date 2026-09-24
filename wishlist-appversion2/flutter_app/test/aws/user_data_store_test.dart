import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/models/models.dart';
import 'package:figmadesign/services/aws/gql_runner.dart';
import 'package:figmadesign/services/aws/user_data_store.dart';

import 'fake_appsync.dart';

void main() {
  late FakeAppSync appsync;
  late AwsUserDataStore store;

  setUp(() {
    appsync = FakeAppSync('uid-a');
    store = AwsUserDataStore(runner: appsync, random: Random(1));
  });

  group('프로필 만들기 (ensureProfile)', () {
    test('아이디·비공개정보·공개프로필·전체탭을 만든다', () async {
      await store.ensureProfile(
        uid: 'uid-a',
        email: 'kim@x.com',
        name: '지은',
        handle: '@kim.ji',
      );
      expect(appsync.tables['Handle']!['@kim.ji']!['ownerId'], 'uid-a');
      expect(appsync.tables['Handle']!['@kim.ji']!['maskedEmail'], 'k***m@x.com');
      expect(appsync.tables['PrivateProfile']!['uid-a']!['email'], 'kim@x.com');

      final me = await store.loadProfile('uid-a');
      expect(me!.name, '지은');
      expect(me.handle, '@kim.ji');
      expect(me.email, 'kim@x.com');

      final tabs = await store.loadTabs('uid-a');
      expect(tabs.map((t) => t.id), ['all']);
    });

    test('두 번 불러도 안전하다 (중간에 앱이 꺼졌다 다시 켜진 경우)', () async {
      await store.ensureProfile(uid: 'uid-a', email: 'a@x.com', handle: 'aaa');
      final before = appsync.mutationCount;
      await store.ensureProfile(uid: 'uid-a', email: 'a@x.com', handle: 'aaa');
      // 두 번째에는 비공개정보 확인(이미 있음) 1번만 시도한다.
      expect(appsync.mutationCount - before, 1);
      expect(appsync.tables['Profile']!.length, 1);
    });

    test('아이디를 동시에 뺏기면 숫자를 붙인 아이디로 만든다', () async {
      appsync.caller = 'uid-b';
      await store.ensureProfile(uid: 'uid-b', email: 'b@x.com', handle: 'same');
      appsync.caller = 'uid-a';
      await store.ensureProfile(uid: 'uid-a', email: 'a@x.com', handle: 'same');

      final me = await store.loadProfile('uid-a');
      expect(me!.handle, startsWith('@same_'));
      expect(appsync.tables['Handle']!['@same']!['ownerId'], 'uid-b');
    });
  });

  group('아이디', () {
    setUp(() async {
      appsync.caller = 'uid-b';
      await store.ensureProfile(uid: 'uid-b', email: 'bob@x.com', handle: 'bob');
      appsync.caller = 'uid-a';
      await store.ensureProfile(uid: 'uid-a', email: 'amy@x.com', handle: 'amy');
    });

    test('중복 확인', () async {
      expect(await store.isHandleAvailable('bob'), isFalse);
      expect(await store.isHandleAvailable('@BOB'), isFalse); // 대소문자·@ 무시
      expect(await store.isHandleAvailable('newbie'), isTrue);
      expect(await store.isHandleAvailable('amy', exceptUid: 'uid-a'), isTrue);
    });

    test('가려진 이메일 찾기', () async {
      expect(await store.findMaskedEmailByHandle('bob'), 'b***b@x.com');
      expect(await store.findMaskedEmailByHandle('nobody'), isNull);
    });

    test('아이디 변경: 남의 아이디로는 못 바꾼다', () async {
      final me = (await store.loadProfile('uid-a'))!;
      await expectLater(
        store.updateProfile('uid-a', me.copyWith(handle: '@bob'),
            previousHandle: '@amy'),
        throwsA(isA<Exception>()),
      );
      expect(appsync.tables['Handle']!.containsKey('@amy'), isTrue);
    });

    test('아이디 변경: 새 아이디를 잡고 옛 아이디를 푼다', () async {
      final me = (await store.loadProfile('uid-a'))!;
      await store.updateProfile('uid-a', me.copyWith(handle: '@amy2'),
          previousHandle: '@amy');
      expect(appsync.tables['Handle']!.containsKey('@amy2'), isTrue);
      expect(appsync.tables['Handle']!.containsKey('@amy'), isFalse);
      expect((await store.loadProfile('uid-a'))!.handle, '@amy2');
    });

    test('아이디 변경: 형식이 틀리면 거절', () async {
      final me = (await store.loadProfile('uid-a'))!;
      await expectLater(
        store.updateProfile('uid-a', me.copyWith(handle: '@a'),
            previousHandle: '@amy'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('탭과 상품', () {
    setUp(() async {
      await store.ensureProfile(uid: 'uid-a', email: 'a@x.com', handle: 'aaa');
    });

    test('탭 순서가 저장된다 (전체 탭은 항상 맨 앞)', () async {
      await store.saveTabs('uid-a', [
        WishlistTab(id: 'all', name: '전체', isPublic: true),
        WishlistTab(id: 't2', name: '하', isPublic: false),
        WishlistTab(id: 't1', name: '가', isPublic: true),
      ]);
      final tabs = await store.loadTabs('uid-a');
      expect(tabs.map((t) => t.id), ['all', 't2', 't1']);
    });

    test('상품 저장·수정·삭제', () async {
      final p = Product(
        id: 7,
        listId: 'all',
        name: '니트',
        price: 30000,
        image: 'https://x/y.jpg',
        platform: '무신사',
      );
      await store.upsertProduct('uid-a', p);
      await store.upsertProduct('uid-a', p.copyWith(memo: '살까?'));
      var list = await store.loadProducts('uid-a');
      expect(list.single.memo, '살까?');
      expect(list.single.isPublic, isTrue); // '전체' 탭이 공개라 맞춰진다

      await store.deleteProduct('uid-a', 7);
      list = await store.loadProducts('uid-a');
      expect(list, isEmpty);
    });

    test('탭을 비공개로 바꾸면 그 탭 상품도 비공개가 된다', () async {
      await store.saveTabs('uid-a', [
        WishlistTab(id: 'all', name: '전체', isPublic: true),
        WishlistTab(id: 't1', name: '옷', isPublic: true),
      ]);
      await store.upsertProduct(
        'uid-a',
        Product(
          id: 1,
          listId: 't1',
          name: 'a',
          price: 1,
          image: '',
          platform: '',
          isPublic: true,
        ),
      );
      await store.saveTabs('uid-a', [
        WishlistTab(id: 'all', name: '전체', isPublic: true),
        WishlistTab(id: 't1', name: '옷', isPublic: false),
      ]);
      expect(
        appsync.tables['WishProduct']!['uid-a#1']!['isPublic'],
        isFalse,
      );
    });

    test('남의 탭은 읽을 수 없다', () async {
      appsync.caller = 'uid-b';
      await expectLater(
        store.loadTabs('uid-a'),
        throwsA(isA<AwsDataException>()),
      );
    });
  });

  group('리뷰', () {
    test('JSON 으로 저장했다가 그대로 복원된다', () async {
      final r = ProductReview(
        id: 'r1',
        authorUid: 'uid-a',
        authorName: '지은',
        authorHandle: '@kim',
        authorAvatar: '',
        productId: 7,
        productName: '니트',
        productImage: '',
        productPlatform: '무신사',
        productPrice: 30000,
        title: '좋아요',
        body: '따뜻해요',
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
        imageUrls: const ['https://x/1.jpg'],
      );
      await store.upsertReview('uid-a', r);
      final stored = appsync.tables['Review']!['uid-a#r1']!['data'];
      expect(stored, isA<String>()); // AWSJSON 은 문자열로 보낸다
      expect(jsonDecode(stored as String)['title'], '좋아요');

      final back = (await store.loadReviews('uid-a')).single;
      expect(back.body, '따뜻해요');
      expect(back.imageUrls, ['https://x/1.jpg']);
    });
  });

  test('회원 탈퇴: 내 데이터가 전부 지워진다', () async {
    await store.ensureProfile(uid: 'uid-a', email: 'a@x.com', handle: 'gone');
    await store.upsertProduct(
      'uid-a',
      Product(id: 1, listId: 'all', name: 'x', price: 1, image: '', platform: ''),
    );
    await store.deleteAll('uid-a');
    for (final t in appsync.tables.values) {
      expect(t.values.where((r) => r['ownerId'] == 'uid-a'), isEmpty);
    }
    expect(await store.isHandleAvailable('gone'), isTrue);
  });
}
