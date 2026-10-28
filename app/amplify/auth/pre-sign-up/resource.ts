import { defineFunction } from '@aws-amplify/backend';

// resourceGroupName: 'auth' → auth 스택과 순환 의존이 생기지 않도록 같은 스택에 둔다.
export const preSignUp = defineFunction({
  name: 'pre-sign-up',
  resourceGroupName: 'auth',
  timeoutSeconds: 5,
});
