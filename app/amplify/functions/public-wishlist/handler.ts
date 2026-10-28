import { type AmplifyFunctionEvent, fieldNameOf } from '../shared/appsync-event';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { queryAll } from '../shared/ddb';
import { loadCounts, loadPublicWishlist, type QueryPublic } from './logic';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

// backend.ts 에서 넣어 주는 표 이름
const TABLES = {
  tab: process.env.WISH_TAB_TABLE ?? '',
  product: process.env.WISH_PRODUCT_TABLE ?? '',
};

/** ownerId 파티션만 조회(Query)한다. 전체 표 훑기(Scan)는 하지 않는다. */
const queryPublic: QueryPublic = (table, ownerId) =>
  queryAll(ddb, {
    TableName: TABLES[table],
    KeyConditionExpression: '#o = :o',
    FilterExpression: '#p = :t',
    ExpressionAttributeNames: { '#o': 'ownerId', '#p': 'isPublic' },
    ExpressionAttributeValues: { ':o': ownerId, ':t': true },
  });

type Args = { ownerId?: string; ownerIds?: string[] };

export const handler = async (event: AmplifyFunctionEvent<Args>): Promise<unknown> => {
  const fieldName = fieldNameOf(event);
  switch (fieldName) {
    case 'publicWishlist': {
      const ownerId = event.arguments.ownerId;
      if (!ownerId) throw new Error('ownerId is required');
      return loadPublicWishlist(queryPublic, ownerId);
    }
    case 'publicWishlistCounts':
      return loadCounts(queryPublic, event.arguments.ownerIds ?? []);
    default:
      throw new Error(`Unknown field: ${fieldName}`);
  }
};
