/// AppSync 에 보내는 GraphQL 문서 모음.
///
/// ⚠️ amplify/data/resource.ts 를 바꾸면 여기 필드도 같이 맞춘다.
///    (배포된 스키마와 대조 검증: README 참고)
library;

const _profileFields = 'ownerId handle handleLower name avatarUrl followers following';
const _privateFields = 'ownerId email fcmTokens hiddenFeedBaskets';
const _handleFields = 'handleLower ownerId maskedEmail';
const _tabFields = 'ownerId tabId name isPublic colorHex sortOrder';
const _productFields =
    'ownerId productId listId name price image platform originalPrice '
    'discount productUrl memo isPublic';
const _reviewFields = 'ownerId reviewId productId data';

abstract final class Gql {
  // ── Profile ──
  static const getProfile = '''
query GetProfile(\$ownerId: ID!) {
  getProfile(ownerId: \$ownerId) { $_profileFields }
}''';
  static const createProfile = '''
mutation CreateProfile(\$input: CreateProfileInput!) {
  createProfile(input: \$input) { ownerId }
}''';
  static const updateProfile = '''
mutation UpdateProfile(\$input: UpdateProfileInput!) {
  updateProfile(input: \$input) { ownerId }
}''';
  static const deleteProfile = '''
mutation DeleteProfile(\$input: DeleteProfileInput!) {
  deleteProfile(input: \$input) { ownerId }
}''';

  // ── PrivateProfile ──
  static const getPrivateProfile = '''
query GetPrivateProfile(\$ownerId: ID!) {
  getPrivateProfile(ownerId: \$ownerId) { $_privateFields }
}''';
  static const createPrivateProfile = '''
mutation CreatePrivateProfile(\$input: CreatePrivateProfileInput!) {
  createPrivateProfile(input: \$input) { ownerId }
}''';
  static const updatePrivateProfile = '''
mutation UpdatePrivateProfile(\$input: UpdatePrivateProfileInput!) {
  updatePrivateProfile(input: \$input) { ownerId }
}''';
  static const deletePrivateProfile = '''
mutation DeletePrivateProfile(\$input: DeletePrivateProfileInput!) {
  deletePrivateProfile(input: \$input) { ownerId }
}''';

  // ── Handle ──
  static const getHandle = '''
query GetHandle(\$handleLower: String!) {
  getHandle(handleLower: \$handleLower) { $_handleFields }
}''';
  static const createHandle = '''
mutation CreateHandle(\$input: CreateHandleInput!) {
  createHandle(input: \$input) { handleLower }
}''';
  static const deleteHandle = '''
mutation DeleteHandle(\$input: DeleteHandleInput!) {
  deleteHandle(input: \$input) { handleLower }
}''';

  // ── WishTab ──
  static const listTabs = '''
query ListWishTabs(\$ownerId: ID!, \$limit: Int, \$nextToken: String) {
  listWishTabs(ownerId: \$ownerId, limit: \$limit, nextToken: \$nextToken) {
    items { $_tabFields }
    nextToken
  }
}''';
  static const createTab = '''
mutation CreateWishTab(\$input: CreateWishTabInput!) {
  createWishTab(input: \$input) { ownerId tabId }
}''';
  static const updateTab = '''
mutation UpdateWishTab(\$input: UpdateWishTabInput!) {
  updateWishTab(input: \$input) { ownerId tabId }
}''';
  static const deleteTab = '''
mutation DeleteWishTab(\$input: DeleteWishTabInput!) {
  deleteWishTab(input: \$input) { ownerId tabId }
}''';

  // ── WishProduct ──
  static const listProducts = '''
query ListWishProducts(\$ownerId: ID!, \$limit: Int, \$nextToken: String) {
  listWishProducts(ownerId: \$ownerId, limit: \$limit, nextToken: \$nextToken) {
    items { $_productFields }
    nextToken
  }
}''';
  static const createProduct = '''
mutation CreateWishProduct(\$input: CreateWishProductInput!) {
  createWishProduct(input: \$input) { ownerId productId }
}''';
  static const updateProduct = '''
mutation UpdateWishProduct(\$input: UpdateWishProductInput!) {
  updateWishProduct(input: \$input) { ownerId productId }
}''';
  static const deleteProduct = '''
mutation DeleteWishProduct(\$input: DeleteWishProductInput!) {
  deleteWishProduct(input: \$input) { ownerId productId }
}''';

  // ── Review ──
  static const listReviews = '''
query ListReviews(\$ownerId: ID!, \$limit: Int, \$nextToken: String) {
  listReviews(ownerId: \$ownerId, limit: \$limit, nextToken: \$nextToken) {
    items { $_reviewFields }
    nextToken
  }
}''';
  static const createReview = '''
mutation CreateReview(\$input: CreateReviewInput!) {
  createReview(input: \$input) { ownerId reviewId }
}''';
  static const updateReview = '''
mutation UpdateReview(\$input: UpdateReviewInput!) {
  updateReview(input: \$input) { ownerId reviewId }
}''';
  static const deleteReview = '''
mutation DeleteReview(\$input: DeleteReviewInput!) {
  deleteReview(input: \$input) { ownerId reviewId }
}''';

  // ── 3-1: 친구 목록 ──
  static const listProfiles = '''
query ListProfiles(\$limit: Int, \$nextToken: String) {
  listProfiles(limit: \$limit, nextToken: \$nextToken) {
    items { $_profileFields }
    nextToken
  }
}''';

  // ── 3-1: Follow ──
  static const listFollowing = '''
query ListFollows(\$ownerId: ID!, \$limit: Int, \$nextToken: String) {
  listFollows(followerId: \$ownerId, limit: \$limit, nextToken: \$nextToken) {
    items { followerId followeeId }
    nextToken
  }
}''';
  static const listFollowers = '''
query ListFollowsByFollowee(\$ownerId: ID!, \$limit: Int, \$nextToken: String) {
  listFollowsByFollowee(followeeId: \$ownerId, limit: \$limit, nextToken: \$nextToken) {
    items { followerId followeeId }
    nextToken
  }
}''';
  static const createFollow = '''
mutation CreateFollow(\$input: CreateFollowInput!) {
  createFollow(input: \$input) { followerId followeeId }
}''';
  static const deleteFollow = '''
mutation DeleteFollow(\$input: DeleteFollowInput!) {
  deleteFollow(input: \$input) { followerId followeeId }
}''';

  // ── 3-1: 공개 위시리스트 (서버 함수) ──
  static const publicWishlist = '''
query PublicWishlist(\$ownerId: ID!) {
  publicWishlist(ownerId: \$ownerId) {
    ownerId
    tabs { tabId name colorHex sortOrder }
    products { productId listId name price image platform originalPrice discount productUrl }
  }
}''';
  static const publicWishlistCounts = '''
query PublicWishlistCounts(\$ownerIds: [ID!]!) {
  publicWishlistCounts(ownerIds: \$ownerIds) { ownerId listCount itemCount }
}''';

  // ── 3-2: 보낸 · 받은 살까말까 ──
  static const listSentBaskets = '''
query ListSentBaskets(\$ownerId: ID!, \$limit: Int, \$nextToken: String) {
  listSentBaskets(ownerId: \$ownerId, limit: \$limit, nextToken: \$nextToken) {
    items { ownerId basketId data }
    nextToken
  }
}''';
  static const createSentBasket = '''
mutation CreateSentBasket(\$input: CreateSentBasketInput!) {
  createSentBasket(input: \$input) { ownerId basketId }
}''';
  static const updateSentBasket = '''
mutation UpdateSentBasket(\$input: UpdateSentBasketInput!) {
  updateSentBasket(input: \$input) { ownerId basketId }
}''';
  static const deleteSentBasket = '''
mutation DeleteSentBasket(\$input: DeleteSentBasketInput!) {
  deleteSentBasket(input: \$input) { ownerId basketId }
}''';
  static const listReceivedBaskets = '''
query ListReceivedBaskets(\$ownerId: ID!, \$limit: Int, \$nextToken: String) {
  listReceivedBaskets(recipientId: \$ownerId, limit: \$limit, nextToken: \$nextToken) {
    items { recipientId basketId fromUid data }
    nextToken
  }
}''';
  static const deleteReceivedBasket = '''
mutation DeleteReceivedBasket(\$input: DeleteReceivedBasketInput!) {
  deleteReceivedBasket(input: \$input) { recipientId basketId }
}''';
  static const sendBasket = '''
mutation SendBasket(\$threadId: String!, \$recipientIds: [ID!]!, \$items: AWSJSON!, \$memo: String) {
  sendBasket(threadId: \$threadId, recipientIds: \$recipientIds, items: \$items, memo: \$memo)
}''';

  // ── 3-2: 댓글 ──
  static const listBasketComments = '''
query ListBasketComments(\$ownerId: String!, \$limit: Int, \$nextToken: String) {
  listBasketComments(threadId: \$ownerId, limit: \$limit, nextToken: \$nextToken) {
    items { threadId commentId authorId parentId data }
    nextToken
  }
}''';
  static const addBasketComment = '''
mutation AddBasketComment(\$threadId: String!, \$text: String!, \$parentId: String, \$participantIds: [ID], \$memo: String) {
  addBasketComment(threadId: \$threadId, text: \$text, parentId: \$parentId, participantIds: \$participantIds, memo: \$memo)
}''';
  static const editBasketComment = '''
mutation EditBasketComment(\$threadId: String!, \$commentId: String!, \$text: String!) {
  editBasketComment(threadId: \$threadId, commentId: \$commentId, text: \$text)
}''';
  static const removeBasketComment = '''
mutation RemoveBasketComment(\$threadId: String!, \$commentId: String!) {
  removeBasketComment(threadId: \$threadId, commentId: \$commentId)
}''';

  // ── 3-2: 알림 ──
  static const listNotifications = '''
query ListNotifications(\$ownerId: ID!, \$limit: Int, \$nextToken: String) {
  listNotifications(recipientId: \$ownerId, limit: \$limit, nextToken: \$nextToken) {
    items { recipientId notificationId type read data }
    nextToken
  }
}''';
  static const markNotificationRead = '''
mutation MarkNotificationRead(\$input: UpdateNotificationInput!) {
  updateNotification(input: \$input) { recipientId notificationId }
}''';
  static const deleteNotification = '''
mutation DeleteNotification(\$input: DeleteNotificationInput!) {
  deleteNotification(input: \$input) { recipientId notificationId }
}''';
  static const notifyFollow = '''
mutation NotifyFollow(\$targetId: ID!) {
  notifyFollow(targetId: \$targetId)
}''';

  /// 검증 스크립트가 전부 훑어볼 수 있도록 한곳에 모은 목록.
  static const all = <String>[
    getProfile, createProfile, updateProfile, deleteProfile,
    getPrivateProfile, createPrivateProfile, updatePrivateProfile,
    deletePrivateProfile,
    getHandle, createHandle, deleteHandle,
    listTabs, createTab, updateTab, deleteTab,
    listProducts, createProduct, updateProduct, deleteProduct,
    listReviews, createReview, updateReview, deleteReview,
    listProfiles, listFollowing, listFollowers, createFollow, deleteFollow,
    publicWishlist, publicWishlistCounts,
    listSentBaskets, createSentBasket, updateSentBasket, deleteSentBasket,
    listReceivedBaskets, deleteReceivedBasket, sendBasket,
    listBasketComments, addBasketComment, editBasketComment,
    removeBasketComment,
    listNotifications, markNotificationRead, deleteNotification, notifyFollow,
  ];
}
