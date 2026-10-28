import type { AppSyncIdentity } from 'aws-lambda';

/**
 * Amplify Gen 2 가 `a.handler.function(...)` 으로 Lambda 를 부를 때 넘기는 값.
 *
 * AppSync 의 "직접 Lambda 리졸버" 이벤트(`event.info.fieldName`)와 모양이 다르다 — Amplify 는 파이프라인
 * 리졸버로 감싸서 `{ typeName, fieldName, arguments, identity, source, request, prev }` 를 넘긴다
 * (@aws-amplify/graphql-function-transformer). 2026-10-24 까지 세 함수 모두 `event.info.fieldName` 을 읽어서
 * 호출될 때마다 "Cannot read properties of undefined (reading 'fieldName')" 로 실패했다.
 */
export interface AmplifyFunctionEvent<A> {
  typeName?: string;
  fieldName?: string;
  arguments: A;
  identity?: AppSyncIdentity | null;
  /** 직접 Lambda 리졸버로 붙일 때만 있다. 둘 다 받아 두면 어느 쪽으로 연결돼도 동작한다. */
  info?: { fieldName?: string; parentTypeName?: string };
}

/** 이번 요청이 어떤 GraphQL 필드(예: 'extractProduct')인지. */
export function fieldNameOf(event: Pick<AmplifyFunctionEvent<unknown>, 'fieldName' | 'info'>): string {
  return event.fieldName ?? event.info?.fieldName ?? '';
}
