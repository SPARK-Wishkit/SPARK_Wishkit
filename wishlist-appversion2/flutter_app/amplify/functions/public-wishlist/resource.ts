import { defineFunction } from '@aws-amplify/backend';

// resourceGroupName: 'data' → 데이터 스택과 같은 곳에 둬서 순환 의존을 막는다.
// (이 함수는 데이터의 표를 읽고, 데이터 API는 이 함수를 부른다)
export const publicWishlist = defineFunction({
  name: 'public-wishlist',
  entry: './handler.ts',
  resourceGroupName: 'data',
  timeoutSeconds: 10,
  memoryMB: 256,
});
