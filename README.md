# wishkit

쇼핑몰 상품을 공유 한 번으로 담는 위시리스트 앱. 친구와 위시리스트를 보고, "살까말까"로 의견을 묻는다.

- **앱:** Flutter (`wishlist-appversion2/flutter_app/`)
- **백엔드:** AWS Amplify Gen 2 — 서울 리전 (`wishlist-appversion2/flutter_app/amplify/`)

| 기능 | AWS 서비스 |
|---|---|
| 회원가입 · 로그인 (이메일 6자리 코드) | Cognito |
| 데이터 (프로필 · 위시리스트 · 친구 · 살까말까 · 댓글 · 알림) | AppSync + DynamoDB |
| 남의 받은함·알림함에 쓰는 일, 친구 공개 위시리스트 | Lambda (서버 함수 2개) |
| 사진 · 공유 페이지 | S3 + CloudFront (한국에서만 접속) |

팀 약속과 역할별 규칙은 **[`wishlist-appversion2/TEAM_CONTRACT.md`](wishlist-appversion2/TEAM_CONTRACT.md)** 를 먼저 읽어 주세요.

---

## 처음 받았을 때

필요한 것: [Flutter](https://docs.flutter.dev/get-started/install), [Node.js](https://nodejs.org) 20 이상

```bash
git clone <이 레포 주소>
cd <레포 폴더>
cp scripts/check_secrets.sh .git/hooks/pre-commit    # 비밀 정보 커밋 방지 검사 켜기
cd wishlist-appversion2/flutter_app
flutter pub get
npm install
```

### 앱에 AWS 주소록 넣기 — 둘 중 하나

`lib/amplify_outputs.dart` 는 레포에 없어요. (사람마다 다르고, 깃에 올리지 않는 파일)

**A. 앱 화면만 만든다면 (대부분의 팀원)**
백엔드 담당에게 `amplify_outputs.dart` 파일을 **개인 메시지로** 받아서 `lib/` 에 넣으세요.
모두 같은 AWS 에 붙어서, 서로 가입한 계정으로 친구 기능을 같이 테스트할 수 있어요.

**B. 백엔드(`amplify/` 폴더)를 고친다면**
본인 AWS 계정으로 개인 테스트 환경(sandbox)을 만드세요. 데이터가 A 와 따로 놀아요.
```bash
npx ampx configure profile          # 본인 IAM 액세스 키 입력 (처음 한 번)
npx ampx sandbox --outputs-format dart --outputs-out-dir lib
```
`Deployment completed` 와 `File written: lib/amplify_outputs.dart` 가 나오면 준비 끝. sandbox 창은 켜 둔 채로 작업해요.

### 실행 · 테스트
```bash
flutter run
flutter test
```

---

## 규칙

- 🔒 **`amplify_outputs.dart`, AWS 액세스 키(.csv), 서명 키는 절대 커밋하지 않기.**
  `.gitignore` 가 막고, 커밋할 때 `scripts/check_secrets.sh` 가 한 번 더 검사해요.
- 화면 · AppStore 에서 데이터가 필요하면 **`AccountRepository` 의 함수만** 부르기. AWS 를 직접 부르지 않기.
- sandbox 는 **한 창에서만** 켜기. `amplify/` 파일을 여러 개 바꿀 땐 sandbox 를 잠깐 끄고 바꾼 뒤 다시 켜기.

## 폴더 안내

```
scripts/                  커밋 전 비밀 정보 검사 · 레포 준비
wishlist-appversion2/
├── flutter_app/
│   ├── amplify/          백엔드 설계 (로그인 · 데이터 · 서버 함수 · 파일)
│   ├── lib/
│   │   ├── auth/         로그인
│   │   ├── services/aws/ AWS 저장소 (AccountRepository 가 사용)
│   │   └── screens/      화면
│   └── test/aws/         백엔드 테스트 (가짜 AWS 로 돌아감 — 인터넷 불필요)
├── TEAM_CONTRACT.md      팀 약속 · 단계별 변경 기록
└── (엔진 담당 문서 · 도구 · 테스트 기록)
```

## 남은 일

- **푸시 알림** (앱이 꺼져 있을 때): 아직 없음. 앱이 켜져 있을 땐 20초마다 새로고침 + 배너.
  안드로이드는 구글 FCM, 아이폰은 애플 개발자 계정의 APNs 키가 필요.
- **공용 백엔드 환경:** 지금은 백엔드 담당의 sandbox 를 함께 씀. 출시 전에는 Amplify 콘솔에서
  이 레포의 `main` 브랜치를 연결해 공용 환경을 따로 만들 것.
