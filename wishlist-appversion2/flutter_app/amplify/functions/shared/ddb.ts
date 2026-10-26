import { type DynamoDBDocumentClient, QueryCommand, type QueryCommandInput } from '@aws-sdk/lib-dynamodb';

export type Row = Record<string, unknown>;

/** 한 번에 읽을 최대 페이지 수. 파티션 하나가 비정상적으로 커도 함수가 끝없이 돌지 않게 막는다. */
export const MAX_QUERY_PAGES = 20;

/**
 * DynamoDB Query 를 LastEvaluatedKey 가 없어질 때까지(최대 maxPages 페이지) 이어서 읽는다.
 * public-wishlist · social-actions 함수가 똑같이 쓰던 페이지 반복문을 한 곳으로 모은 것.
 */
export async function queryAll(
  ddb: DynamoDBDocumentClient,
  input: Omit<QueryCommandInput, 'ExclusiveStartKey'>,
  maxPages = MAX_QUERY_PAGES,
): Promise<Row[]> {
  const rows: Row[] = [];
  let startKey: Record<string, unknown> | undefined;
  let pages = 0;
  do {
    const res = await ddb.send(new QueryCommand({ ...input, ExclusiveStartKey: startKey }));
    rows.push(...((res.Items ?? []) as Row[]));
    startKey = res.LastEvaluatedKey;
    pages++;
  } while (startKey && pages < maxPages);
  return rows;
}
