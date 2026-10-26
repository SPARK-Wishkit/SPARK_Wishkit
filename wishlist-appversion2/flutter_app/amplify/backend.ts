import { defineBackend } from '@aws-amplify/backend';
import { Duration, Stack } from 'aws-cdk-lib';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import { auth } from './auth/resource';
import { engineEnv } from './engine-env';
import { data } from './data/resource';
import { parsingProxy } from './functions/parsing-proxy/resource';
import { publicWishlist } from './functions/public-wishlist/resource';
import { socialActions } from './functions/social-actions/resource';
import { storage } from './storage/resource';

const backend = defineBackend({
  auth,
  data,
  publicWishlist,
  socialActions,
  storage,
  parsingProxy,
});

// ─────────────────────────────────────────────────────────────
// 서버 함수 권한: 함수별로 "어떤 표를, 읽기만/읽고 쓰기, 어떤 환경변수 이름으로" 줄지 표로 정리
// ─────────────────────────────────────────────────────────────
type TableName = keyof typeof backend.data.resources.tables;
type TableGrant = { table: TableName; env: string; write?: boolean };

type FunctionHandle = {
  resources: { lambda: lambda.IFunction };
  addEnvironment(key: string, value: string): void;
};

function grantTables(fn: FunctionHandle, grants: TableGrant[]) {
  const tables = backend.data.resources.tables;
  for (const { table, env, write } of grants) {
    const t = tables[table];
    if (write) t.grantReadWriteData(fn.resources.lambda);
    else t.grantReadData(fn.resources.lambda);
    fn.addEnvironment(env, t.tableName);
  }
}

// 공개 위시리스트 함수: 탭·상품 표를 "읽기만" 한다.
grantTables(backend.publicWishlist, [
  { table: 'WishTab', env: 'WISH_TAB_TABLE' },
  { table: 'WishProduct', env: 'WISH_PRODUCT_TABLE' },
]);

// 살까말까·댓글·알림 함수: 프로필·팔로우는 읽기만, 댓글방·댓글·받은함·알림은 읽고 쓰기.
grantTables(backend.socialActions, [
  { table: 'Profile', env: 'PROFILE_TABLE' },
  { table: 'Follow', env: 'FOLLOW_TABLE' },
  { table: 'BasketThread', env: 'THREAD_TABLE', write: true },
  { table: 'BasketComment', env: 'COMMENT_TABLE', write: true },
  { table: 'ReceivedBasket', env: 'RECEIVED_TABLE', write: true },
  { table: 'Notification', env: 'NOTIFICATION_TABLE', write: true },
]);

// ─────────────────────────────────────────────────────────────
// AI 추출 엔진(parsing-engine, Fargate) 연동: parsing-proxy를 엔진과 같은 VPC에 붙인다
// ─────────────────────────────────────────────────────────────
// 타입 체크(tsc --noEmit)는 통과 확인됨. 실제 배포(`npx ampx sandbox`)는 아직 미검증.
//
// parsing-proxy는 엔진 서버(Fargate)의 프라이빗 IP로만 호출해야 하므로, defineFunction이
// 지원하지 않는 vpc 설정을 CDK 이스케이프 해치로 넣는다(Amplify Gen2가 아직
// FunctionProps에 vpc를 노출하지 않음 — aws-amplify/amplify-backend#1112).
//
// ⚠️ 이 네 값을 채우기 전에는 일부러 배포가 실패하게 해뒀다(잘못된 값으로 조용히
//    배포되는 것보다 안전) — 엔진 서버가 실제로 어느 AWS 계정/VPC에 뜨는지부터
//    (이 Amplify 백엔드와 같은 계정인지) 확인한 뒤 채울 것:
//    ENGINE_VPC_ID              엔진 Fargate 태스크가 있는 VPC ID
//    ENGINE_PRIVATE_SUBNET_IDS  이 함수를 붙일 프라이빗 서브넷 ID들(콤마로 구분)
//    ENGINE_LAMBDA_SG_ID        이 함수에 붙일 보안그룹 ID
//                               (엔진 태스크의 보안그룹이 "이 SG에서 8000번 포트 허용"
//                               규칙을 갖고 있어야 함 — 반대 방향 아님)
//    ENGINE_BASE_URL            엔진 서버 내부 주소(예: 내부 ALB의 http://<DNS>)
//
// 엔진 서버 없이 개인 sandbox를 띄우고 싶으면(로그인·데이터·광고·가격 새로고침 테스트용)
// ENGINE_DISABLED=1 을 명시적으로 켠다. 그러면 VPC 연결을 건너뛰고, parsing-proxy는 배포되지만
// 부르면 "엔진 서버 주소가 설정되지 않았습니다" 오류를 돌려준다(태그 사진·URL 추출만 안 됨).
//   ENGINE_DISABLED=1 npx ampx sandbox --outputs-format dart --outputs-out-dir lib
// 기본값(안 켬)은 위 네 값이 없으면 그대로 배포 실패 — 실수로 엔진 없이 공용 환경에 배포되지 않게.
if (engineEnv('ENGINE_DISABLED') === '1') {
  console.warn('[backend.ts] ENGINE_DISABLED=1 — parsing-proxy를 엔진 없이 배포합니다(VPC 연결 생략).');
} else {
  const vpcId = engineEnv('ENGINE_VPC_ID');
  const subnetIds = engineEnv('ENGINE_PRIVATE_SUBNET_IDS')?.split(',').map((s) => s.trim()).filter(Boolean);
  const lambdaSgId = engineEnv('ENGINE_LAMBDA_SG_ID');
  const engineBaseUrl = engineEnv('ENGINE_BASE_URL');

  if (!vpcId || !subnetIds?.length || !lambdaSgId || !engineBaseUrl) {
    throw new Error(
      'parsing-proxy를 배포하려면 ENGINE_VPC_ID, ENGINE_PRIVATE_SUBNET_IDS, ' +
        'ENGINE_LAMBDA_SG_ID, ENGINE_BASE_URL 환경변수를 먼저 설정해야 합니다 ' +
        '(엔진 서버 Fargate 배포 후 그 값으로 채울 것 — backend.ts 위 주석 참고).',
    );
  }

  const fn = backend.parsingProxy;
  const cfnFunction = fn.resources.lambda.node.defaultChild as lambda.CfnFunction;
  cfnFunction.vpcConfig = {
    subnetIds,
    securityGroupIds: [lambdaSgId],
  };
  // VPC에 붙은 Lambda는 ENI 생성·관리 권한(AWSLambdaVPCAccessExecutionRole)이 필요하다 —
  // defineFunction 기본 역할에는 없어서 직접 붙인다.
  (fn.resources.lambda.role as iam.Role | undefined)?.addManagedPolicy(
    iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaVPCAccessExecutionRole'),
  );
  fn.addEnvironment('ENGINE_BASE_URL', engineBaseUrl);
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
// 4단계: 파일 배달망(CloudFront) 두 개 + 공유 페이지 28일 자동 삭제
// ─────────────────────────────────────────────────────────────
{
  const bucket = backend.storage.resources.bucket;
  // 버킷과 같은 스택에 만들어야 순환 의존이 생기지 않는다.
  const stack = Stack.of(bucket);

  // S3 는 공개하지 않고, CloudFront 만 읽을 수 있게 한다 (Origin Access Control).
  // 앱에 저장되는 사진 주소는 https://<배달망 주소>/avatars/... 형태의 영구 주소가 된다.
  const cachePolicy = new cloudfront.CachePolicy(stack, 'FilesCachePolicy', {
    comment: 'wishkit files: 5분 기본, 파일 이름이 매번 달라서 오래 캐시해도 안전',
    defaultTtl: Duration.minutes(5),
    minTtl: Duration.seconds(0),
    maxTtl: Duration.days(7),
    enableAcceptEncodingGzip: true,
    enableAcceptEncodingBrotli: true,
  });
  const behavior = (origin: cloudfront.IOrigin): cloudfront.BehaviorOptions => ({
    origin,
    viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
    allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD,
    cachePolicy,
    responseHeadersPolicy: cloudfront.ResponseHeadersPolicy.SECURITY_HEADERS,
  });

  // ① 앱용 배달망: 프로필 사진·태그 사진 등. 한국에서만 열린다(해외 접속은 403).
  //    ⚠️ 해외 여행 중에는 사진이 안 보인다. 풀려면 이 줄을 지우거나 allowlist('KR', 'JP', ...) 처럼 나라를 추가한다.
  const cdn = new cloudfront.Distribution(stack, 'FilesCdn', {
    comment: 'wishkit files (avatars, tag photos)',
    defaultBehavior: behavior(origins.S3BucketOrigin.withOriginAccessControl(bucket)),
    priceClass: cloudfront.PriceClass.PRICE_CLASS_200, // 한국 포함, 가장 비싼 지역 제외
    geoRestriction: cloudfront.GeoRestriction.allowlist('KR'),
  });

  // ② 공유 페이지 전용 배달망: 앱이 없는 사람에게 SNS로 보내는 살까말까 링크. 나라 제한 없음.
  //    CloudFront 의 나라 제한은 배달망 단위라서, 공유 페이지만 열려면 배달망을 따로 둬야 한다.
  //    originPath 로 share-pages/ 폴더만 연결한다 → 이 주소로는 프로필 사진 등 다른 폴더를 읽을 수 없다.
  //    해외 SNS(인스타그램·페이스북·X 등)의 미리보기 서버도 이 페이지를 읽을 수 있게 된다.
  const shareCdn = new cloudfront.Distribution(stack, 'SharePagesCdn', {
    comment: 'wishkit public share pages (share-pages/ only, worldwide)',
    defaultBehavior: behavior(
      origins.S3BucketOrigin.withOriginAccessControl(bucket, { originPath: '/share-pages' }),
    ),
    priceClass: cloudfront.PriceClass.PRICE_CLASS_200,
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
    custom: {
      filesBaseUrl: `https://${cdn.distributionDomainName}`,
      // 공유 페이지 주소: https://<공유 배달망>/<주인 폴더>/<페이지>.html (share-pages/ 는 주소에 안 붙음)
      sharePagesBaseUrl: `https://${shareCdn.distributionDomainName}`,
    },
  });
}
