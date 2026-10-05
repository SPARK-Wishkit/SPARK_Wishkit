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
  // AppSync는 요청당 30초 고정 한도(조정 불가)라서 그 안에서 전부 끝나야 한다.
  // 체인: 엔진 EXTRACT_TIMEOUT_S 22초(배포 시 env로 지정, 코드 기본값 45는 안 건드림)
  //     < Lambda fetch 중단 25초(handler.ts FETCH_TIMEOUT_MS)
  //     < 이 timeoutSeconds 28초 < AppSync 30초 < 앱 엔진 대기 27초.
  timeoutSeconds: 28,
  memoryMB: 256,
});
