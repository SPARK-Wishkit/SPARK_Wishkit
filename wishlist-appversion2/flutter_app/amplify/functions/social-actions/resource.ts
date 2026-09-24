import { defineFunction } from '@aws-amplify/backend';

// 살까말까 보내기 · 댓글 · 알림처럼 "남의 공간에 쓰는" 일을 대신 하는 서버 함수.
// resourceGroupName: 'data' → 데이터 스택과 같은 곳에 둬서 순환 의존을 막는다.
export const socialActions = defineFunction({
  name: 'social-actions',
  entry: './handler.ts',
  resourceGroupName: 'data',
  timeoutSeconds: 15,
  memoryMB: 256,
});
