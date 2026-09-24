import type { AppSyncIdentityCognito, AppSyncResolverHandler } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DeleteCommand,
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  QueryCommand,
} from '@aws-sdk/lib-dynamodb';
import {
  ActionError,
  addComment,
  deleteComment,
  notifyFollow,
  sendBasket,
  updateComment,
  type Db,
  type Row,
  type Table,
} from './logic';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}), {
  marshallOptions: { removeUndefinedValues: true },
});

// backend.ts 에서 넣어 주는 표 이름
const TABLES: Record<Table, string> = {
  Profile: process.env.PROFILE_TABLE ?? '',
  Follow: process.env.FOLLOW_TABLE ?? '',
  BasketThread: process.env.THREAD_TABLE ?? '',
  BasketComment: process.env.COMMENT_TABLE ?? '',
  ReceivedBasket: process.env.RECEIVED_TABLE ?? '',
  Notification: process.env.NOTIFICATION_TABLE ?? '',
};

const db: Db = {
  async get(table, key) {
    const res = await ddb.send(new GetCommand({ TableName: TABLES[table], Key: key }));
    return res.Item as Row | undefined;
  },
  async put(table, item) {
    await ddb.send(new PutCommand({ TableName: TABLES[table], Item: item }));
  },
  async del(table, key) {
    await ddb.send(new DeleteCommand({ TableName: TABLES[table], Key: key }));
  },
  async query(table, keyName, keyValue) {
    const rows: Row[] = [];
    let startKey: Record<string, unknown> | undefined;
    let pages = 0;
    do {
      const res = await ddb.send(
        new QueryCommand({
          TableName: TABLES[table],
          KeyConditionExpression: '#k = :v',
          ExpressionAttributeNames: { '#k': keyName },
          ExpressionAttributeValues: { ':v': keyValue },
          ExclusiveStartKey: startKey,
        }),
      );
      rows.push(...((res.Items ?? []) as Row[]));
      startKey = res.LastEvaluatedKey as Record<string, unknown> | undefined;
      pages++;
    } while (startKey && pages < 20);
    return rows;
  },
};

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Args = Record<string, any>;

export const handler: AppSyncResolverHandler<Args, unknown> = async (event) => {
  // 호출한 사람은 토큰에서만 가져온다. (앱이 보낸 값은 믿지 않는다)
  const caller = (event.identity as AppSyncIdentityCognito | null)?.sub;
  if (!caller) throw new Error('UNAUTHENTICATED');
  const env = { db };
  const a = event.arguments;

  try {
    switch (event.info.fieldName) {
      case 'sendBasket':
        return await sendBasket(env, caller, {
          threadId: a.threadId,
          recipientIds: a.recipientIds,
          items: a.items,
          memo: a.memo,
        });
      case 'addBasketComment':
        return await addComment(env, caller, {
          threadId: a.threadId,
          text: a.text,
          parentId: a.parentId,
          participantIds: a.participantIds,
          memo: a.memo,
        });
      case 'editBasketComment':
        return await updateComment(env, caller, {
          threadId: a.threadId,
          commentId: a.commentId,
          text: a.text,
        });
      case 'removeBasketComment':
        return await deleteComment(env, caller, {
          threadId: a.threadId,
          commentId: a.commentId,
        });
      case 'notifyFollow':
        return await notifyFollow(env, caller, { targetId: a.targetId });
      default:
        throw new Error(`Unknown field: ${event.info.fieldName}`);
    }
  } catch (e) {
    // 약속된 오류 코드는 그대로, 그 밖의 오류는 내부 내용을 숨긴다.
    if (e instanceof ActionError) throw new Error(e.code);
    console.error('social-actions failed', event.info.fieldName, e);
    throw new Error('INTERNAL');
  }
};
