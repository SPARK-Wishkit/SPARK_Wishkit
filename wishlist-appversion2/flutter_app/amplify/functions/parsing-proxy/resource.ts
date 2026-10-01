import { defineFunction } from '@aws-amplify/backend';

// AI 추출 엔진 서버(parsing-engine, Fargate)를 대신 호출하는 서버 함수.
// 앱은 이 함수만 부르고, 엔진 서버 자체는 VPC 프라이빗 서브넷에 있어 외부에서 직접
// 두드릴 수 없다 — API 키/남용 방지 로직 없이도 Cognito 로그인 사용자만 호출 가능.
//
// resourceGroupName: 'data' → 데이터 스택과 같은 곳에 둬서 순환 의존을 막는다(기존
// public-wishlist/social-actions와 동일한 이유).
//
// VPC 연결(엔진 서버와 같은 VPC의 프라이빗 서브넷에 배치)은 defineFunction이 vpc 옵션을
// 지원하지 않아서 amplify/backend.ts에서 CDK 이스케이프 해치로 처리한다 — 그 파일의
// 주석 참고.
export const parsingProxy = defineFunction({
  name: 'parsing-proxy',
  entry: './handler.ts',
  resourceGroupName: 'data',
  // 엔진 서버 자체 타임아웃(EXTRACT_TIMEOUT_S=45초)보다 여유 있게 60초.
  timeoutSeconds: 60,
  memoryMB: 256,
});
