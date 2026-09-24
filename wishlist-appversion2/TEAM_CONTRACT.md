# 백엔드(AWS) ↔ 앱 기능 약속

**역할**
- 백엔드 담당(로그인 포함 Firebase → AWS 이전 전체): `lib/auth/`, `lib/services/account_repository.dart`, `amplify/`, 푸시·서버 함수
- 앱 기능 담당: 화면(`lib/screens/`, auth 제외), `lib/data/app_store.dart`의 앱 로직, 위젯·테마
- 엔진 담당: 파싱 엔진. 백엔드와 겹치는 부분 없음

---

## 약속 1. 앱 기능 코드는 AWS/Firebase를 직접 부르지 않는다

화면과 `AppStore`는 **`AccountRepository`의 함수만** 부릅니다.
백엔드 담당은 함수의 **이름, 인자, 반환값을 유지한 채 속만** Firebase → AWS로 바꿉니다.
그러면 앱 기능 코드는 이전 작업과 상관없이 그대로 동작합니다.

- 새 데이터 기능이 필요하면 → `AccountRepository`에 함수를 **추가해 달라고 요청** (직접 Firestore/AWS 코드 작성 X)
- 기존 함수의 모양을 바꿔야 하면 → 백엔드 담당이 미리 공지

## 약속 2. 로그인 상태

| 필요한 것 | 쓰는 곳 |
|---|---|
| 내 사용자 ID | `store.uid` (= Cognito `sub`, 절대 안 바뀜) |
| 앱 데이터 준비 여부 | `store.isLoggedIn` |
| 로그아웃 / 비밀번호 변경 / 탈퇴 | `store.logout()`, `store.changePassword(...)`, `store.deleteAccount(...)` (이름 그대로) |
| 로그인·가입·인증 화면 | `lib/screens/auth/` — 백엔드 담당 소유 |

오류는 예외로 오고, `e.toString()`이 바로 한국어 문구입니다 (기존과 같음).

## 약속 3. 1단계에서 바뀐 파일 (2026-09-25)

`app_store.dart`는 **로그인 부분만** 바뀌었습니다. 데이터 코드는 그대로입니다.

**`lib/data/app_store.dart`**
- 삭제: `awaitingEmailVerification`, `showSignupWelcome`, `pendingVerificationEmail`, 가입 초안(`_pendingName`/`_pendingHandle`) 저장 코드,
  `register`, `login`, `resendVerificationEmail`, `confirmEmailVerified`, `cancelEmailVerification`, `dismissSignupWelcome`,
  `sendPasswordResetEmail`, `findMaskedEmailByHandle` → 전부 `AuthController`로 이동
- 변경: `init()`은 `AuthController.userChanges`를 구독해서 로그인/로그아웃 때 데이터를 불러오거나 비움
- 유지(이름 그대로, 속만 전달): `logout`, `changePassword`, `deleteAccount`, `uid`, `isLoggedIn`
- 추가: 생성자 인자 `auth`, `authHooks`, `dispose()`

**`lib/main.dart`**
- Amplify 설정 → `AuthController` 생성·복구 → `AppStore(auth: auth)` 순서로 시작
- 라우터: 로그인 이동 규칙은 `authRedirect`, 로그인 화면 경로는 `authRoutes` 사용
- Provider: `AuthController`와 `AppStore` 둘 다 제공

**`lib/services/account_repository.dart`**
- Firebase Auth 코드 전부 삭제, `ensureProfile`이 `uid`/`email`을 직접 받도록 변경
- 추가: `deleteUserData(uid)`, `isHandleAvailable(handle)`

⚠️ 이 시점에는 데이터가 아직 Firestore에 있는데 로그인은 Cognito라서, **로그인은 되지만 데이터 화면은 비어 있거나 오류가 납니다.** 2단계(데이터 이전)에서 해결됩니다.

## 약속 3-2. 2단계에서 바뀐 것 (데이터 일부 AWS 이전)

**AWS로 옮긴 것:** 프로필, 아이디, 탭, 상품, 리뷰, 푸시 토큰, 숨긴 피드
**아직 Firestore:** 팔로우, 친구 위시리스트, 살까말까, 댓글, 알림 (3단계), 사진·공유 페이지 파일 (4단계)

- `AccountRepository`의 함수 이름·인자·반환값은 **하나도 바뀌지 않았습니다.** 화면·AppStore 코드는 그대로 쓰면 됩니다.
- **동작이 바뀐 점 1:** 탭 순서가 저장됩니다. 예전에는 다시 켜면 이름순으로 돌아갔습니다. (`'전체'` 탭은 항상 맨 앞)
- **동작이 바뀐 점 2:** 탭·상품·리뷰는 **본인만** 읽을 수 있습니다. 친구에게 보이는 공개 항목은 3단계에서 서버 함수로 제공합니다.
  3단계 전까지 친구 위시리스트·친구 리뷰 화면은 비어 보일 수 있습니다.
- `AppStore._hydrateSession`: 친구 정보 불러오기가 실패해도 내 데이터는 뜨도록 감쌌습니다.

## 약속 3-3. 3-1단계에서 바뀐 것 (팔로우 · 친구 목록 · 친구 위시리스트)

**AWS로 옮긴 것:** 팔로우, 팔로워 삭제, 친구 찾기 목록, 친구 공개 위시리스트, 친구 리뷰
**아직 Firestore:** 살까말까, 댓글, 알림 (3-2단계)

- `AccountRepository` 함수 이름·인자·반환값은 **그대로**입니다.
- **친구에게 메모가 보이지 않습니다.** 예전에는 친구 상품의 메모까지 읽을 수 있었는데, 이제 서버가 메모를 빼고 줍니다.
- **친구의 비공개 탭·상품은 보이지 않습니다.** 공개(isPublic)인 것만 서버가 골라서 줍니다.
- 팔로워·팔로잉 **수는 저장하지 않고 팔로우 목록에서 셉니다.** 숫자가 실제와 어긋날 일이 없습니다.
- 팔로우 알림은 3-2단계 전까지 가지 않습니다.

## 약속 3-4. 3-2단계에서 바뀐 것 (살까말까 · 댓글 · 알림)

**AWS로 옮긴 것:** 보낸·받은 살까말까, 댓글, 알림, 팔로우 알림
**아직 Firebase:** 프로필 사진·리뷰 사진·공유 페이지 파일 (4단계), 푸시 알림 (5단계)

- `AccountRepository` 함수 이름·인자·반환값은 **그대로**입니다. (44개 함수 전부 자동 대조 완료)
- **남의 받은함·알림함·댓글방에 쓰는 일은 서버만 합니다.** 앱이 보낸 "보낸 사람 정보"는 쓰지 않고,
  서버가 DB의 진짜 프로필로 채웁니다. → 사칭 불가
- **보낸 상품의 개인 메모는 친구에게 가지 않습니다.** (살까말까의 공유 메시지 `memo` 는 그대로 갑니다)
- **댓글은 작성자 본인만** 고치고 지울 수 있고, 참여자가 아니면 읽을 수도 없습니다.
- **팔로우 알림:** 실제로 팔로우 중일 때만 가고, 껐다 켜도 알림은 1개입니다.
- **실시간 → 주기적 새로고침:** 알림·받은 살까말까는 20초, 댓글 화면은 5초마다 새로고침합니다.
  내가 댓글을 쓰거나 알림을 읽으면 **즉시** 새로고침합니다. (5단계 푸시 알림으로 보완)

## 약속 3-5. 4단계에서 바뀐 것 (파일)

**AWS로 옮긴 것:** 프로필 사진, 리뷰 사진, 살까말까 공유 페이지 → S3 + CloudFront
**남은 Firebase:** 푸시 알림(FCM)만 (5단계)

- `AccountRepository` 함수 이름·인자·반환값은 **그대로**입니다. 이제 이 파일에 Firebase 코드가 **하나도 없습니다.**
- 사진 주소는 `https://<배달망>.cloudfront.net/...` **영구 주소**입니다. DB에 저장해도 깨지지 않습니다.
- 프로필 사진을 바꾸면 **옛 사진 파일은 지워집니다.**
- 사진·공유 페이지는 **한국에서만** 열립니다. (CloudFront 국가 제한 — 해외에서는 403)
- 공유 페이지는 **28일 뒤 S3가 자동 삭제**합니다. (매일 돌던 Firebase 정리 함수 대신)
- 패키지: `cloud_firestore`, `firebase_storage` **삭제**, `amplify_storage_s3` **추가**

## 약속 3-6. 6단계: Firebase 완전 제거 (2026-09-25)

**앱에 Firebase가 하나도 남지 않았습니다.** 패키지·설정 파일·서버 규칙·Cloud Functions 모두 삭제.

- `AppStore` 이름 변경: `firebaseReady` → **`backendReady`**, `firebaseError` → **`backendError`**,
  생성자 `firebaseConfigured:` → **`backendConfigured:`** (테스트에서 `AppStore(backendConfigured: false)`)
- `friends_screen.dart` 1줄, `widget_test.dart` 생성자 13곳, 주석 몇 줄을 이에 맞춰 고쳤습니다. 동작은 같습니다.
- 알림: **앱이 켜져 있을 때의 배너는 그대로**, 앱이 꺼져 있을 때의 푸시는 5단계에서 다시 붙입니다.
  `PushNotificationService` 의 함수 이름·인자는 그대로 두었습니다.
- 새 코드에 Firebase 패키지를 다시 추가하지 말아 주세요. (푸시 단계에서 백엔드 담당이 필요한 것만 추가)

## 약속 4. 같이 쓰는 파일은 먼저 말하고 고친다

| 파일 | 규칙 |
|---|---|
| `lib/main.dart` | 수정 전 서로 공지 |
| `lib/data/app_store.dart` | 로그인 부분(`init`, `_onAuthUserChanged`, `_hydrateSession*`, `logout`/`changePassword`/`deleteAccount`)은 백엔드 담당. 나머지는 앱 기능 담당 |
| `pubspec.yaml` | 패키지 추가·삭제 전 공지 |

## 약속 5. 개발 환경

- 백엔드 담당이 공용 개발 환경의 `lib/amplify_outputs.dart`를 공유합니다. 이 파일에는 서버 주소 같은 설정만 있고 비밀 키는 없습니다.
  **팀원은 AWS 계정이나 키 없이** 이 파일만 넣고 앱을 실행하면 됩니다.
- AWS 액세스 키는 절대 공유·커밋하지 않습니다.
