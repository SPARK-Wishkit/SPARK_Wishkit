import type { AppSyncResolverHandler } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, QueryCommand } from '@aws-sdk/lib-dynamodb';
import { loadCounts, loadPublicWishlist, type QueryPublic, type Row } from './logic';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

// backend.ts 에서 넣어 주는 표 이름
const TABLES = {
  tab: process.env.WISH_TAB_TABLE ?? '',
  product: process.env.WISH_PRODUCT_TABLE ?? '',
};

/** ownerId 파티션만 조회(Query)한다. 전체 표 훑기(Scan)는 하지 않는다. */
const queryPublic: QueryPublic = async (table, ownerId) => {
  const rows: Row[] = [];
  let startKey: Record<string, unknown> | undefined;
  let pages = 0;
  do {
    const res = await ddb.send(
      new QueryCommand({
        TableName: TABLES[table],
        KeyConditionExpression: '#o = :o',
        FilterExpression: '#p = :t',
        ExpressionAttributeNames: { '#o': 'ownerId', '#p': 'isPublic' },
        ExpressionAttributeValues: { ':o': ownerId, ':t': true },
        ExclusiveStartKey: startKey,
      }),
    );
    rows.push(...((res.Items ?? []) as Row[]));
    startKey = res.LastEvaluatedKey as Record<string, unknown> | undefined;
    pages++;
  } while (startKey && pages < 20);
  return rows;
};

type Args = { ownerId?: string; ownerIds?: string[] };

export const handler: AppSyncResolverHandler<Args, unknown> = async (event) => {
  switch (event.info.fieldName) {
    case 'publicWishlist': {
      const ownerId = event.arguments.ownerId;
      if (!ownerId) throw new Error('ownerId is required');
      return loadPublicWishlist(queryPublic, ownerId);
    }
    case 'publicWishlistCounts':
      return loadCounts(queryPublic, event.arguments.ownerIds ?? []);
    default:
      throw new Error(`Unknown field: ${event.info.fieldName}`);
  }
};
