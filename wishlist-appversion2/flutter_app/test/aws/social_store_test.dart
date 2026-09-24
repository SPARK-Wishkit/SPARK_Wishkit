import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/models/models.dart';
import 'package:figmadesign/services/aws/gql_runner.dart';
import 'package:figmadesign/services/aws/social_store.dart';
import 'package:figmadesign/services/aws/user_data_store.dart';

import 'fake_appsync.dart';

void main() {
  late FakeAppSync appsync;
  late AwsUserDataStore data;
  late AwsSocialStore social;

  /// [uid] 로 로그인해서 프로필을 만든다.
  Future<void> signUp(String uid, String handle, String name) async {
    appsync.caller = uid;
    await data.ensureProfile(
      uid: uid,
      email: '$handle@x.com',
      name: name,
      handle: handle,
    );
  }

  setUp(() async {
    appsync = FakeAppSync('');
    data = AwsUserDataStore(runner: appsync);
    social = AwsSocialStore(runner: appsync);
    await signUp('amy', 'amy', '에이미');
    await signUp('bob', 'bob', '밥');
    await signUp('cho', 'cho', '초');
    appsync.caller = 'amy';
  });

  group('팔로우', () {
    test('팔로우하면 양쪽 목록에 보이고, 언팔로우하면 사라진다', () async {
      await social.setFollowing(myUid: 'amy', targetUid: 'bob', follow: true);
      expect(await social.followingIds('amy'), ['bob']);
      expect(await social.followerIds('bob'), ['amy']);

      await social.setFollowing(myUid: 'amy', targetUid: 'bob', follow: false);
      expect(await social.followingIds('amy'), isEmpty);
      expect(await social.followerIds('bob'), isEmpty);
    });

    test('버튼 연타(같은 요청 두 번)에도 오류가 나지 않는다', () async {
      await social.setFollowing(myUid: 'amy', targetUid: 'bob', follow: true);
      await social.setFollowing(myUid: 'amy', targetUid: 'bob', follow: true);
      expect(await social.followingIds('amy'), ['bob']);
      await social.setFollowing(myUid: 'amy', targetUid: 'bob', follow: false);
      await social.setFollowing(myUid: 'amy', targetUid: 'bob', follow: false);
    });

    test('나 자신은 팔로우하지 않는다', () async {
      await social.setFollowing(myUid: 'amy', targetUid: 'amy', follow: true);
      expect(await social.followingIds('amy'), isEmpty);
    });

    test('팔로워 삭제: 나를 팔로우한 사람의 관계를 내가 지울 수 있다', () async {
      appsync.caller = 'bob';
      await social.setFollowing(myUid: 'bob', targetUid: 'amy', follow: true);
      appsync.caller = 'amy';
      await social.removeFollower(myUid: 'amy', followerUid: 'bob');
      expect(await social.followerIds('amy'), isEmpty);
    });

    test('남의 팔로우를 대신 만들 수는 없다 (서버 권한)', () async {
      // amy 로 로그인한 채 "bob 이 cho 를 팔로우"를 만들려고 시도
      await expectLater(
        social.setFollowing(myUid: 'bob', targetUid: 'cho', follow: true),
        throwsA(isA<AwsDataException>()),
      );
    });
  });

  group('친구 목록', () {
    test('나를 뺀 사람들 + 팔로우 여부 + 공개 개수', () async {
      appsync.caller = 'bob';
      await data.saveTabs('bob', [
        WishlistTab(id: 'all', name: '전체', isPublic: true),
        WishlistTab(id: 't1', name: '옷', isPublic: true),
        WishlistTab(id: 't2', name: '비밀', isPublic: false),
      ]);
      for (final (id, tab) in [(1, 't1'), (2, 't1'), (3, 't2')]) {
        await data.upsertProduct(
          'bob',
          Product(id: id, listId: tab, name: 'p$id', price: 1, image: '', platform: ''),
        );
      }
      await data.loadProducts('bob'); // 탭 공개 여부에 맞춰 상품 공개 여부 정리

      appsync.caller = 'amy';
      final list = await social.loadDirectory(myUid: 'amy', following: {'bob'});
      expect(list.map((f) => f.id), containsAll(['bob', 'cho']));
      expect(list.map((f) => f.id), isNot(contains('amy')));

      final bob = list.firstWhere((f) => f.id == 'bob');
      expect(bob.isFollowing, isTrue);
      expect(bob.name, '밥');
      expect(bob.wishlistCount, 1); // '전체'·비공개 탭 제외
      expect(bob.itemCount, 2); // 비공개 탭 상품 제외
    });

    test('uid 로 프로필 여러 개 불러오기 (없는 사람은 빠짐)', () async {
      final users = await social.loadUsers(['cho', 'bob', 'ghost']);
      expect(users.map((u) => u.uid), ['bob', 'cho']); // 이름순: 밥, 초
    });
  });

  group('친구 공개 위시리스트', () {
    setUp(() async {
      appsync.caller = 'bob';
      await data.saveTabs('bob', [
        WishlistTab(id: 'all', name: '전체', isPublic: true),
        WishlistTab(id: 'shoes', name: '신발', isPublic: true),
        WishlistTab(id: 'secret', name: '선물', isPublic: false),
      ]);
      await data.upsertProduct(
        'bob',
        Product(
          id: 10,
          listId: 'shoes',
          name: '운동화',
          price: 99000,
          image: 'i',
          platform: '나이키',
          memo: '월급날 사기',
        ),
      );
      await data.upsertProduct(
        'bob',
        Product(id: 11, listId: 'secret', name: '반지', price: 1, image: '', platform: ''),
      );
      await data.loadProducts('bob');
      appsync.caller = 'amy';
    });

    Friend friend(bool following) => Friend(
          id: 'bob',
          name: '밥',
          username: '@bob',
          avatar: '',
          isFollowing: following,
          wishlistCount: 0,
          itemCount: 0,
        );

    test('공개 탭과 그 안의 공개 상품만 보인다', () async {
      final lists = await social.loadFriendWishlists([friend(true)]);
      expect(lists.map((l) => l.listName), ['신발']);
      expect(lists.single.items.single.name, '운동화');
      expect(lists.single.id, 'bob_shoes');
    });

    test('메모는 친구에게 보이지 않는다', () async {
      final lists = await social.loadFriendWishlists([friend(true)]);
      expect(lists.single.items.single.memo, isNull);
    });

    test('팔로우하지 않는 사람은 불러오지 않는다', () async {
      expect(await social.loadFriendWishlists([friend(false)]), isEmpty);
    });

    test('친구의 탭·상품 표는 직접 읽을 수 없다 (서버 함수로만)', () async {
      await expectLater(
        data.loadTabs('bob'),
        throwsA(isA<AwsDataException>()),
      );
    });
  });

  test('친구 리뷰는 로그인한 사람이 읽을 수 있다', () async {
    appsync.caller = 'bob';
    await data.upsertReview(
      'bob',
      ProductReview(
        id: 'r1',
        authorUid: 'bob',
        authorName: '밥',
        authorHandle: '@bob',
        authorAvatar: '',
        productId: 10,
        productName: '운동화',
        productImage: '',
        productPlatform: '',
        productPrice: 1,
        title: '편해요',
        body: '',
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      ),
    );
    appsync.caller = 'amy';
    final reviews = await data.loadReviews('bob');
    expect(reviews.single.title, '편해요');
  });

  test('회원 탈퇴: 내가 한 팔로우와 나를 향한 팔로우가 모두 지워진다', () async {
    await social.setFollowing(myUid: 'amy', targetUid: 'bob', follow: true);
    appsync.caller = 'cho';
    await social.setFollowing(myUid: 'cho', targetUid: 'amy', follow: true);

    appsync.caller = 'amy';
    await social.deleteAllFollows('amy');
    expect(appsync.table('Follow'), isEmpty);
  });
}
