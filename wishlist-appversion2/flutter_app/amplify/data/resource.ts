import { type ClientSchema, a, defineData } from '@aws-amplify/backend';
import { publicWishlist } from '../functions/public-wishlist/resource';
import { socialActions } from '../functions/social-actions/resource';

/**
 * wishkit 데이터 설계도 (AWS AppSync + DynamoDB)
 *
 * 공통 규칙
 * - ownerId 에는 항상 Cognito `sub` 를 저장한다. (= 앱의 store.uid / AuthUserInfo.uid)
 * - 권한 "본인"은 ownerId == 로그인한 사람의 sub 일 때만 통과한다.
 *
 * 2단계: 프로필 · 아이디 · 탭 · 상품 · 리뷰 (내가 쓰는 데이터)
 * 3-1단계: 팔로우 · 친구 위시리스트(공개만, 서버 함수) · 친구 리뷰
 * 3-2단계: 살까말까 · 댓글 · 알림
 *   → 남의 받은함·알림함·댓글방에 쓰는 일은 앱이 직접 못 하고, 서버 함수(socialActions)만 한다.
 *     서버는 보낸 사람 이름·사진을 DB의 진짜 프로필에서 가져온다(사칭 불가).
 *
 * 권한은 필요한 만큼만 연다.
 * - 이메일·푸시 토큰은 PrivateProfile 로 분리해서 본인만 읽는다. (예전엔 누구나 읽기 가능)
 * - 탭·상품은 본인만 읽는다. 친구에게는 서버 함수(publicWishlist)가 "공개(isPublic)인 것만",
 *   그리고 메모(memo)는 빼고 돌려준다. (예전엔 로그인만 하면 비공개·메모까지 읽기 가능)
 */
const schema = a.schema({
  /** 친구 목록·검색에 보이는 공개 프로필. */
  Profile: a
    .model({
      ownerId: a.id().required(),
      handle: a.string().required(), // '@kim.ji'
      handleLower: a.string().required(),
      name: a.string().required(),
      avatarUrl: a.string(),
      followers: a.integer(),
      following: a.integer(),
    })
    .identifier(['ownerId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('ownerId').identityClaim('sub'),
      allow.authenticated().to(['read']),
    ]),

  /** 본인만 볼 수 있는 계정 정보. */
  PrivateProfile: a
    .model({
      ownerId: a.id().required(),
      email: a.string().required(),
      fcmTokens: a.string().array(),
      hiddenFeedBaskets: a.string().array(),
    })
    .identifier(['ownerId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('ownerId').identityClaim('sub'),
    ]),

  /**
   * 아이디 중복 방지표. 아이디(소문자)가 곧 키라서 같은 아이디는 두 번 만들어지지 않는다.
   * 비로그인(가입 전 중복 확인, 이메일 찾기)은 정확한 아이디 1건 조회(get)만 가능하다.
   */
  Handle: a
    .model({
      handleLower: a.string().required(),
      ownerId: a.id().required(),
      maskedEmail: a.string(), // 'k***n@gmail.com' — 이메일 찾기 화면용
    })
    .identifier(['handleLower'])
    .authorization((allow) => [
      // 수정(update)은 막는다: 아이디를 남에게 넘기는 일을 원천 차단. 바꿀 땐 새로 만들고 옛것을 지운다.
      allow.ownerDefinedIn('ownerId').identityClaim('sub').to(['create', 'read', 'delete']),
      allow.authenticated().to(['get']),
      allow.guest().to(['get']),
    ]),

  WishTab: a
    .model({
      ownerId: a.id().required(),
      tabId: a.string().required(),
      name: a.string().required(),
      isPublic: a.boolean().required(),
      colorHex: a.string(),
      sortOrder: a.integer().required(),
    })
    .identifier(['ownerId', 'tabId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('ownerId').identityClaim('sub'),
    ]),

  WishProduct: a
    .model({
      ownerId: a.id().required(),
      productId: a.string().required(), // 앱의 Product.id(int) 를 문자열로 저장
      listId: a.string().required(),
      name: a.string().required(),
      price: a.integer().required(),
      image: a.string(),
      platform: a.string(),
      originalPrice: a.integer(),
      discount: a.integer(),
      productUrl: a.string(),
      memo: a.string(),
      isPublic: a.boolean().required(),
    })
    .identifier(['ownerId', 'productId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('ownerId').identityClaim('sub'),
    ]),

  /**
   * 리뷰는 항목이 많아 본문을 data(JSON)로 통째로 저장한다. (ProductReview.toJson)
   * 친구 리뷰 화면을 위해 로그인한 사람은 읽을 수 있다. (예전과 같은 범위)
   */
  Review: a
    .model({
      ownerId: a.id().required(),
      reviewId: a.string().required(),
      productId: a.integer(),
      data: a.json().required(),
    })
    .identifier(['ownerId', 'reviewId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('ownerId').identityClaim('sub'),
      allow.authenticated().to(['read']),
    ]),

  /**
   * 팔로우 관계 한 줄 = "followerId 가 followeeId 를 팔로우한다".
   * - 팔로우/언팔로우: 팔로우하는 사람(followerId)만 만들고 지운다.
   * - 팔로워 삭제: 팔로우 당하는 사람(followeeId)도 지울 수 있다.
   * - 수정은 없다. (남의 팔로우를 조작할 방법 자체가 없음)
   * 팔로워·팔로잉 수는 따로 저장하지 않고 이 표에서 센다. (숫자가 어긋날 일이 없음)
   */
  Follow: a
    .model({
      followerId: a.id().required(),
      followeeId: a.id().required(),
    })
    .identifier(['followerId', 'followeeId'])
    .secondaryIndexes((index) => [
      index('followeeId').queryField('listFollowsByFollowee'),
    ])
    .authorization((allow) => [
      allow.ownerDefinedIn('followerId').identityClaim('sub').to(['create', 'read', 'delete']),
      allow.ownerDefinedIn('followeeId').identityClaim('sub').to(['read', 'delete']),
      allow.authenticated().to(['read']),
    ]),

  // ── 친구에게 보여 주는 공개 위시리스트 (서버 함수가 공개 항목만 골라 돌려줌) ──
  PublicTab: a.customType({
    tabId: a.string().required(),
    name: a.string().required(),
    colorHex: a.string(),
    sortOrder: a.integer(),
  }),
  PublicProduct: a.customType({
    productId: a.string().required(),
    listId: a.string().required(),
    name: a.string().required(),
    price: a.integer().required(),
    image: a.string(),
    platform: a.string(),
    originalPrice: a.integer(),
    discount: a.integer(),
    productUrl: a.string(),
  }),
  PublicWishlist: a.customType({
    ownerId: a.id().required(),
    tabs: a.ref('PublicTab').required().array().required(),
    products: a.ref('PublicProduct').required().array().required(),
  }),
  WishlistCount: a.customType({
    ownerId: a.id().required(),
    listCount: a.integer().required(),
    itemCount: a.integer().required(),
  }),

  // ── 3-2: 살까말까 · 댓글 · 알림 ────────────────────────────

  /** 내가 보낸 살까말까 기록. 본인만. (SharedBasket.toJson) */
  SentBasket: a
    .model({
      ownerId: a.id().required(),
      basketId: a.string().required(),
      data: a.json().required(),
    })
    .identifier(['ownerId', 'basketId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('ownerId').identityClaim('sub'),
    ]),

  /** 친구에게 받은 살까말까. 서버만 만들고, 받은 사람은 읽기·지우기만. */
  ReceivedBasket: a
    .model({
      recipientId: a.id().required(),
      basketId: a.string().required(),
      fromUid: a.id().required(),
      data: a.json().required(),
    })
    .identifier(['recipientId', 'basketId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('recipientId').identityClaim('sub').to(['read', 'delete']),
    ]),

  /** 살까말까 댓글방. 참여자(보낸 사람 + 받은 사람들)만 읽는다. 쓰기는 서버만. */
  BasketThread: a
    .model({
      threadId: a.string().required(),
      ownerId: a.id().required(),
      participantIds: a.id().required().array().required(),
      memo: a.string(),
    })
    .identifier(['threadId'])
    .authorization((allow) => [
      allow.ownersDefinedIn('participantIds').identityClaim('sub').to(['read']),
    ]),

  /**
   * 댓글 한 개. 댓글방 참여자 목록을 같이 저장해서 참여자만 읽게 한다.
   * (참여자가 늘면 서버가 기존 댓글의 목록도 함께 고친다)
   * 쓰기·수정·삭제는 서버만 한다. 서버가 "작성자 본인인지" 확인한다.
   */
  BasketComment: a
    .model({
      threadId: a.string().required(),
      commentId: a.string().required(),
      authorId: a.id().required(),
      parentId: a.string(),
      participantIds: a.id().required().array().required(),
      data: a.json().required(),
    })
    .identifier(['threadId', 'commentId'])
    .authorization((allow) => [
      allow.ownersDefinedIn('participantIds').identityClaim('sub').to(['read']),
    ]),

  /** 알림함. 서버만 만들고, 받은 사람은 읽기·읽음 표시·지우기만. */
  Notification: a
    .model({
      recipientId: a.id().required(),
      notificationId: a.string().required(),
      type: a.string().required(),
      read: a.boolean().required(),
      data: a.json().required(),
    })
    .identifier(['recipientId', 'notificationId'])
    .authorization((allow) => [
      allow.ownerDefinedIn('recipientId').identityClaim('sub').to(['read', 'update', 'delete']),
    ]),

  /** 살까말까 보내기: 댓글방 준비 → 받은 사람마다 받은함 + 알림. 받은 사람 수를 돌려준다. */
  sendBasket: a
    .mutation()
    .arguments({
      threadId: a.string().required(),
      recipientIds: a.id().required().array().required(),
      items: a.json().required(), // Product.toJson() 목록
      memo: a.string(),
    })
    .returns(a.integer().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  /** 댓글·답글 달기. 만든 댓글(BasketComment.toJson)을 돌려준다. */
  addBasketComment: a
    .mutation()
    .arguments({
      threadId: a.string().required(),
      text: a.string().required(),
      parentId: a.string(),
      // 댓글방이 아직 없을 때(보낸 사람이 첫 댓글) 만들 정보
      participantIds: a.id().array(),
      memo: a.string(),
    })
    .returns(a.json().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  editBasketComment: a
    .mutation()
    .arguments({
      threadId: a.string().required(),
      commentId: a.string().required(),
      text: a.string().required(),
    })
    .returns(a.boolean().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  removeBasketComment: a
    .mutation()
    .arguments({
      threadId: a.string().required(),
      commentId: a.string().required(),
    })
    .returns(a.boolean().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  /** 팔로우 알림. 서버가 실제로 팔로우 중인지 확인하고 보낸다. 다시 팔로우해도 알림은 1개. */
  notifyFollow: a
    .mutation()
    .arguments({ targetId: a.id().required() })
    .returns(a.boolean().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(socialActions)),

  /** 한 사람의 공개 탭('전체' 제외)과 공개 상품. 메모는 포함하지 않는다. */
  publicWishlist: a
    .query()
    .arguments({ ownerId: a.id().required() })
    .returns(a.ref('PublicWishlist'))
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(publicWishlist)),

  /** 친구 목록에 보이는 "위시리스트 N · 아이템 M" 숫자를 여러 명 한 번에. (최대 100명) */
  publicWishlistCounts: a
    .query()
    .arguments({ ownerIds: a.id().required().array().required() })
    .returns(a.ref('WishlistCount').required().array().required())
    .authorization((allow) => [allow.authenticated()])
    .handler(a.handler.function(publicWishlist)),
});

export type Schema = ClientSchema<typeof schema>;

export const data = defineData({
  schema,
  authorizationModes: {
    defaultAuthorizationMode: 'userPool',
  },
});
