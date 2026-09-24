import { defineBackend } from '@aws-amplify/backend';
import { Duration, Stack } from 'aws-cdk-lib';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import { auth } from './auth/resource';
import { data } from './data/resource';
import { publicWishlist } from './functions/public-wishlist/resource';
import { socialActions } from './functions/social-actions/resource';
import { storage } from './storage/resource';

const backend = defineBackend({
  auth,
  data,
  publicWishlist,
  socialActions,
  storage,
});

// ─────────────────────────────────────────────────────────────
// 서버 함수 권한: 공개 위시리스트 함수는 탭·상품 표를 "읽기만" 할 수 있다.
// ─────────────────────────────────────────────────────────────
{
  const tables = backend.data.resources.tables;
  const fn = backend.publicWishlist;
  tables['WishTab'].grantReadData(fn.resources.lambda);
  tables['WishProduct'].grantReadData(fn.resources.lambda);
  fn.addEnvironment('WISH_TAB_TABLE', tables['WishTab'].tableName);
  fn.addEnvironment('WISH_PRODUCT_TABLE', tables['WishProduct'].tableName);
}

// 살까말까·댓글·알림 함수: 프로필·팔로우는 읽기만, 댓글방·댓글·받은함·알림은 읽고 쓰기.
{
  const tables = backend.data.resources.tables;
  const fn = backend.socialActions;
  const lambda = fn.resources.lambda;
  tables['Profile'].grantReadData(lambda);
  tables['Follow'].grantReadData(lambda);
  tables['BasketThread'].grantReadWriteData(lambda);
  tables['BasketComment'].grantReadWriteData(lambda);
  tables['ReceivedBasket'].grantReadWriteData(lambda);
  tables['Notification'].grantReadWriteData(lambda);
  fn.addEnvironment('PROFILE_TABLE', tables['Profile'].tableName);
  fn.addEnvironment('FOLLOW_TABLE', tables['Follow'].tableName);
  fn.addEnvironment('THREAD_TABLE', tables['BasketThread'].tableName);
  fn.addEnvironment('COMMENT_TABLE', tables['BasketComment'].tableName);
  fn.addEnvironment('RECEIVED_TABLE', tables['ReceivedBasket'].tableName);
  fn.addEnvironment('NOTIFICATION_TABLE', tables['Notification'].tableName);
}

// ─────────────────────────────────────────────────────────────
// 로그인: Cognito 세부 설정
// ─────────────────────────────────────────────────────────────
const { cfnUserPool, cfnUserPoolClient } = backend.auth.resources.cfnResources;

// 비밀번호: 8자 이상 + 숫자 포함. (앱 auth_validators.dart 와 같은 규칙)
cfnUserPool.policies = {
  passwordPolicy: {
    minimumLength: 8,
    requireNumbers: true,
    requireLowercase: false,
    requireUppercase: false,
    requireSymbols: false,
    temporaryPasswordValidityDays: 3,
  },
};

// "없는 이메일"과 "틀린 비밀번호"를 구분해 알려 주지 않는다 (계정 존재 여부 노출 방지).
cfnUserPoolClient.preventUserExistenceErrors = 'ENABLED';

// 토큰 수명: 로그인 유지 30일, 접근/ID 토큰 1시간(자동 갱신됨).
cfnUserPoolClient.refreshTokenValidity = 30;
cfnUserPoolClient.accessTokenValidity = 60;
cfnUserPoolClient.idTokenValidity = 60;
cfnUserPoolClient.tokenValidityUnits = {
  refreshToken: 'days',
  accessToken: 'minutes',
  idToken: 'minutes',
};

// ─────────────────────────────────────────────────────────────
// 4단계: 파일 배달망(CloudFront) + 공유 페이지 28일 자동 삭제
// ─────────────────────────────────────────────────────────────
{
  const bucket = backend.storage.resources.bucket;
  // 버킷과 같은 스택에 만들어야 순환 의존이 생기지 않는다.
  const stack = Stack.of(bucket);

  // S3 는 공개하지 않고, CloudFront 만 읽을 수 있게 한다 (Origin Access Control).
  // 앱에 저장되는 사진 주소는 https://<배달망 주소>/avatars/... 형태의 영구 주소가 된다.
  const cdn = new cloudfront.Distribution(stack, 'FilesCdn', {
    comment: 'wishkit files (avatars, review photos, share pages)',
    defaultBehavior: {
      origin: origins.S3BucketOrigin.withOriginAccessControl(bucket),
      viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
      cachePolicy: new cloudfront.CachePolicy(stack, 'FilesCachePolicy', {
        comment: 'wishkit files: 5분 기본, 파일 이름이 매번 달라서 오래 캐시해도 안전',
        defaultTtl: Duration.minutes(5),
        minTtl: Duration.seconds(0),
        maxTtl: Duration.days(7),
        enableAcceptEncodingGzip: true,
        enableAcceptEncodingBrotli: true,
      }),
      responseHeadersPolicy: cloudfront.ResponseHeadersPolicy.SECURITY_HEADERS,
    },
    priceClass: cloudfront.PriceClass.PRICE_CLASS_200, // 한국 포함, 가장 비싼 지역 제외
    // 한국에서만 열린다. 해외 접속은 403(거부).
    // ⚠️ 해외 여행 중에는 사진이 안 보이고, 해외 친구에게 보낸 공유 링크도 안 열린다.
    //    풀려면 이 줄을 지우거나 allowlist('KR', 'JP', ...) 처럼 나라를 추가한다.
    geoRestriction: cloudfront.GeoRestriction.allowlist('KR'),
  });

  // 공유 페이지(살까말까 링크)는 올린 지 28일 뒤 S3 가 알아서 지운다.
  // (별도 정리 함수가 필요 없다. 다시 공유하면 새로 올라가서 28일이 다시 시작)
  backend.storage.resources.cfnResources.cfnBucket.lifecycleConfiguration = {
    rules: [
      {
        id: 'expire-share-pages-28d',
        status: 'Enabled',
        prefix: 'share-pages/',
        expirationInDays: 28,
      },
    ],
  };

  // 앱이 파일 주소를 만들 때 쓰는 배달망 주소 → amplify_outputs.dart 의 custom 에 들어간다.
  backend.addOutput({
    custom: { filesBaseUrl: `https://${cdn.distributionDomainName}` },
  });
}
