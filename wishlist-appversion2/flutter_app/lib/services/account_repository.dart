import 'dart:io';

import '../models/models.dart';
import 'aws/basket_store.dart';
import 'aws/file_store.dart';
import 'aws/social_store.dart';
import 'aws/user_data_store.dart';

/// 앱 데이터의 유일한 출입구. 화면·AppStore 는 이 클래스의 함수만 부른다.
///
/// 저장 위치 (모두 AWS):
///   로그인            Cognito
///   데이터            AppSync + DynamoDB   (aws/*_store.dart)
///   파일              S3 + CloudFront       (aws/file_store.dart)
///   남의 공간에 쓰기   서버 함수(Lambda)     (amplify/functions/)
class AccountRepository {
  AccountRepository({
    AwsUserDataStore? userData,
    AwsSocialStore? social,
    AwsBasketStore? baskets,
    AwsFileStore? files,
  })  : _aws = userData ?? AwsUserDataStore(),
        _social = social ?? AwsSocialStore(),
        _baskets = baskets ?? AwsBasketStore(),
        _files = files ?? AwsFileStore();

  /// 2단계: 내 데이터 (프로필 · 아이디 · 탭 · 상품 · 리뷰).
  final AwsUserDataStore _aws;

  /// 3-1단계: 팔로우 · 친구 목록 · 친구 공개 위시리스트.
  final AwsSocialStore _social;

  /// 3-2단계: 살까말까 · 댓글 · 알림.
  final AwsBasketStore _baskets;

  /// 4단계: 프로필 사진 · 리뷰 사진 · 공유 페이지 (S3 + CloudFront).
  final AwsFileStore _files;

  /// 회원 탈퇴용: [uid] 의 앱 데이터와 파일을 모두 지운다.
  /// AuthController.deleteAccount → AuthDataHooks.deleteMyData 에서 호출된다.
  /// 아직 로그인된 상태에서 불리므로, 내 파일 폴더에 접근할 수 있다.
  Future<void> deleteUserData(String uid) async {
    await _files.deleteAll();
    await _baskets.deleteAll(uid);
    await _social.deleteAllFollows(uid);
    await _aws.deleteAll(uid);
  }

  /// 가입 전 아이디 미리 확인용. 사용 가능하면 true.
  Future<bool> isHandleAvailable(String handle) =>
      _aws.isHandleAvailable(handle);

  /// 아이디로 가입 이메일(가려진 형태)을 찾는다.
  Future<String?> findMaskedEmailByHandle(String handle) =>
      _aws.findMaskedEmailByHandle(handle);

  Future<void> assertHandleAvailable(
    String handle, {
    String? exceptUid,
    String? email,
  }) =>
      _aws.assertHandleAvailable(handle, exceptUid: exceptUid);

  Future<AppUser?> loadProfile(String uid) => _aws.loadProfile(uid);

  Future<void> saveFcmToken(String uid, String token) =>
      _aws.saveFcmToken(uid, token);

  /// 내 친구 탭 살까말까 피드에서 숨긴 바구니 id. 계정에 저장돼 다른 기기에서도 유지된다.
  Future<Set<String>> loadHiddenFeedBaskets(String uid) =>
      _aws.loadHiddenFeedBaskets(uid);

  Future<void> hideFeedBaskets(String uid, Iterable<String> basketIds) =>
      _aws.hideFeedBaskets(uid, basketIds);

  Future<void> unhideFeedBaskets(String uid, Iterable<String> basketIds) =>
      _aws.unhideFeedBaskets(uid, basketIds);

  Future<void> removeFcmToken(String uid, String token) =>
      _aws.removeFcmToken(uid, token);

  /// 로그인 직후 호출. 프로필이 없으면 가입 초안(name, handle)으로 만든다.
  Future<void> ensureProfile({
    required String uid,
    required String email,
    String? name,
    String? handle,
  }) =>
      _aws.ensureProfile(uid: uid, email: email, name: name, handle: handle);

  Future<void> updateProfile(
    String uid,
    AppUser user, {
    String? previousHandle,
  }) =>
      _aws.updateProfile(uid, user, previousHandle: previousHandle);

  /// 프로필 사진을 올리고 영구 주소를 돌려준다. (옛 사진은 정리한다)
  Future<String> uploadAvatarFile(String uid, File file) =>
      _files.uploadAvatar(file);

  Future<String> uploadReviewPhoto({
    required String uid,
    required String reviewId,
    required File file,
    required int index,
  }) =>
      _files.uploadReviewPhoto(reviewId: reviewId, file: file, index: index);

  /// 살까말까 공유 페이지(HTML)를 올리고, 로그인 없이 열리는 주소를 돌려준다.
  /// 28일 뒤 자동 삭제는 S3 규칙이 한다. 같은 [pageId] 로 다시 올리면 같은 주소에 덮어쓴다.
  /// [basketId] · [expiresAt] 은 호환용으로 받지만 쓰지 않는다.
  Future<String> uploadSharePage({
    required String uid,
    required String pageId,
    required String basketId,
    required String html,
    required DateTime expiresAt,
  }) =>
      _files.uploadSharePage(pageId: pageId, html: html);

  Future<List<WishlistTab>> loadTabs(String uid) => _aws.loadTabs(uid);

  Future<void> saveTabs(String uid, List<WishlistTab> tabs) =>
      _aws.saveTabs(uid, tabs);

  Future<void> deleteTabDoc(String uid, String tabId) =>
      _aws.deleteTab(uid, tabId);

  Future<List<Product>> loadProducts(String uid) => _aws.loadProducts(uid);

  Future<void> upsertProduct(String uid, Product product) =>
      _aws.upsertProduct(uid, product);

  Future<void> deleteProduct(String uid, int productId) =>
      _aws.deleteProduct(uid, productId);

  Future<List<String>> followingIds(String uid) => _social.followingIds(uid);

  Future<List<String>> followerIds(String uid) => _social.followerIds(uid);

  Future<List<AppUser>> loadUsers(List<String> uids) => _social.loadUsers(uids);

  Future<List<Friend>> loadDirectory({
    required String myUid,
    required Set<String> following,
  }) =>
      _social.loadDirectory(myUid: myUid, following: following);

  Future<void> setFollowing({
    required String myUid,
    required String targetUid,
    required bool follow,
    AppUser? actor,
  }) async {
    if (myUid == targetUid) return;
    await _social.setFollowing(
      myUid: myUid,
      targetUid: targetUid,
      follow: follow,
    );
    // 팔로우 알림: 서버가 실제 팔로우 여부와 보낸 사람 정보를 확인해서 만든다.
    if (follow) await _baskets.notifyFollow(targetUid);
  }

  /// 내 팔로워 목록에서 [followerUid] 를 뺀다.
  Future<void> removeFollower({
    required String myUid,
    required String followerUid,
  }) =>
      _social.removeFollower(myUid: myUid, followerUid: followerUid);

  Future<List<FriendWishlist>> loadFriendWishlists(
    List<Friend> followingFriends,
  ) =>
      _social.loadFriendWishlists(followingFriends);

  Future<List<AppNotification>> loadNotifications(String uid) =>
      _baskets.loadNotifications(uid);

  /// 20초마다 새로고침 + 읽음 처리 직후 바로 새로고침.
  Stream<List<AppNotification>> watchNotifications(String uid) =>
      _baskets.watchNotifications(uid);

  Future<void> markNotificationsRead(String uid, List<String> ids) =>
      _baskets.markNotificationsRead(uid, ids);

  Future<List<ProductReview>> loadReviews(String uid) =>
      _aws.loadReviews(uid);

  Future<void> upsertReview(String uid, ProductReview review) =>
      _aws.upsertReview(uid, review);

  Future<void> deleteReview(String uid, String reviewId) =>
      _aws.deleteReview(uid, reviewId);

  Future<List<ProductReview>> loadFriendReviews(
    List<Friend> followingFriends,
  ) async {
    final out = <ProductReview>[];
    for (final friend in followingFriends.where((f) => f.isFollowing)) {
      try {
        out.addAll(await loadReviews(friend.id));
      } catch (_) {}
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  Future<List<SharedBasket>> loadSentBaskets(String uid) =>
      _baskets.loadSentBaskets(uid);

  Future<void> upsertSentBasket(String uid, SharedBasket basket) =>
      _baskets.upsertSentBasket(uid, basket);

  Future<List<SharedBasket>> loadReceivedBaskets(String uid) =>
      _baskets.loadReceivedBaskets(uid);

  /// 20초마다 새로고침.
  Stream<List<SharedBasket>> watchReceivedBaskets(String uid) =>
      _baskets.watchReceivedBaskets(uid);

  /// 살까말까 보내기. 받은함 · 알림 · 댓글방은 서버가 만든다.
  /// [from] 은 호환용으로 받지만 쓰지 않는다 — 보낸 사람 정보는 서버가 DB 에서 가져온다.
  Future<void> sendBasketToFriends({
    required AppUser from,
    required List<String> recipientUids,
    required List<Product> items,
    required String threadId,
    String memo = '',
  }) async {
    if (recipientUids.isEmpty || items.isEmpty || threadId.isEmpty) return;
    await _baskets.sendBasket(
      recipientUids: recipientUids,
      items: items,
      threadId: threadId,
      memo: memo,
    );
  }

  /// 5초마다 새로고침 + 댓글을 쓰거나 고친 직후 바로 새로고침.
  Stream<List<BasketComment>> watchBasketComments(String threadId) =>
      _baskets.watchComments(threadId);

  /// 댓글·답글. 작성자 정보와 알림 대상은 서버가 정한다.
  Future<void> addBasketComment({
    required String threadId,
    required AppUser from,
    required String text,
    String parentId = '',
    String ownerUid = '',
    List<String> participantUids = const [],
    String memo = '',
  }) =>
      _baskets.addComment(
        threadId: threadId,
        text: text,
        parentId: parentId,
        participantIds: participantUids,
        memo: memo,
      );

  /// 내 댓글 고치기. 작성자 확인은 서버가 한다.
  Future<void> updateBasketComment({
    required String threadId,
    required String commentId,
    required String authorUid,
    required String text,
  }) async {
    if (threadId.isEmpty || commentId.isEmpty) return;
    await _baskets.editComment(
      threadId: threadId,
      commentId: commentId,
      text: text,
    );
  }

  /// 내 댓글 지우기. 작성자 확인은 서버가 한다.
  Future<void> deleteBasketComment({
    required String threadId,
    required String commentId,
    required String authorUid,
  }) async {
    if (threadId.isEmpty || commentId.isEmpty) return;
    await _baskets.removeComment(threadId: threadId, commentId: commentId);
  }

}
