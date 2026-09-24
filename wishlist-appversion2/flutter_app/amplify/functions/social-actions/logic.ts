/**
 * 살까말까 · 댓글 · 알림 서버 로직 (DynamoDB 는 밖에서 넣어 준다 → 테스트 가능).
 *
 * 원칙
 * - 호출한 사람(caller)은 Cognito 토큰에서 온 sub 만 믿는다. 앱이 보낸 "보낸 사람 정보"는 쓰지 않는다.
 * - 이름·아이디·사진은 DB 의 Profile 에서 가져온다 → 남을 사칭할 수 없다.
 * - AppSync 모델로 읽힐 행이므로 __typename · createdAt · updatedAt 을 반드시 채운다.
 */
import { randomUUID } from 'node:crypto';

export type Row = Record<string, unknown>;
export type Table =
  | 'Profile'
  | 'Follow'
  | 'BasketThread'
  | 'BasketComment'
  | 'ReceivedBasket'
  | 'Notification';

export interface Db {
  get(table: Table, key: Row): Promise<Row | undefined>;
  put(table: Table, item: Row): Promise<void>;
  del(table: Table, key: Row): Promise<void>;
  /** 파티션 키 하나로 조회 */
  query(table: Table, keyName: string, keyValue: string): Promise<Row[]>;
}

export const LIMITS = {
  recipients: 50,
  items: 100,
  text: 1000,
  memo: 500,
};

const THREAD_ID = /^[A-Za-z0-9_.:-]{1,100}$/;

/** 앱에 돌려주는 오류 코드. 앱이 한국어 문구로 바꿔 보여 준다. */
export class ActionError extends Error {
  constructor(public readonly code: string) {
    super(code);
  }
}
const fail = (code: string): never => {
  throw new ActionError(code);
};

export interface Env {
  db: Db;
  now?: () => Date;
  newId?: () => string;
}

interface Author {
  uid: string;
  name: string;
  handle: string;
  avatar: string;
}

// ── 공통 ──────────────────────────────────────────────────────

async function authorOf(env: Env, uid: string): Promise<Author> {
  const p = await env.db.get('Profile', { ownerId: uid });
  if (!p) fail('PROFILE_MISSING');
  return {
    uid,
    name: String(p!.name ?? '사용자'),
    handle: String(p!.handle ?? '@user'),
    avatar: String(p!.avatarUrl ?? ''),
  };
}

function stamp(typename: string, item: Row, now: string, existing?: Row): Row {
  return {
    ...item,
    __typename: typename,
    createdAt: (existing?.createdAt as string | undefined) ?? now,
    updatedAt: now,
  };
}

function asJson(v: unknown): unknown {
  return typeof v === 'string' ? JSON.parse(v) : v;
}

function cleanText(raw: unknown, max: number, { required }: { required: boolean }): string {
  const t = typeof raw === 'string' ? raw.trim() : '';
  if (required && t.length === 0) fail('INVALID_INPUT');
  if (t.length > max) fail('TOO_LONG');
  return t;
}

async function notify(
  env: Env,
  recipientId: string,
  from: Author,
  type: string,
  message: string,
  relatedId: string,
  now: string,
  notificationId?: string,
) {
  if (recipientId === from.uid) return;
  const id = notificationId ?? env.newId!();
  const existing = notificationId
    ? await env.db.get('Notification', { recipientId, notificationId: id })
    : undefined;
  await env.db.put(
    'Notification',
    stamp(
      'Notification',
      {
        recipientId,
        notificationId: id,
        type,
        read: false,
        data: {
          id,
          type,
          fromUid: from.uid,
          fromName: from.name,
          fromHandle: from.handle,
          fromAvatar: from.avatar,
          message,
          relatedId,
          read: false,
          createdAt: now,
        },
      },
      now,
      existing,
    ),
  );
}

/** 보낸 상품에서 앱이 쓰는 칸만 남긴다. 개인 메모(memo)는 친구에게 보내지 않는다. */
function sanitizeItems(raw: unknown): Row[] {
  const list = asJson(raw);
  if (!Array.isArray(list) || list.length === 0) fail('INVALID_INPUT');
  if ((list as unknown[]).length > LIMITS.items) fail('TOO_MANY_ITEMS');
  return (list as unknown[]).map((it) => {
    if (typeof it !== 'object' || it === null) fail('INVALID_INPUT');
    const p = it as Row;
    const id = typeof p.id === 'number' ? p.id : Number(p.id);
    if (!Number.isFinite(id)) fail('INVALID_INPUT');
    return {
      id,
      listId: String(p.listId ?? 'all'),
      name: String(p.name ?? '').slice(0, 300),
      price: typeof p.price === 'number' ? p.price : 0,
      image: String(p.image ?? ''),
      platform: String(p.platform ?? ''),
      originalPrice: typeof p.originalPrice === 'number' ? p.originalPrice : null,
      discount: typeof p.discount === 'number' ? p.discount : null,
      productUrl: typeof p.productUrl === 'string' ? p.productUrl : null,
      isPublic: p.isPublic === true,
    };
  });
}

function withDefaults(env: Env): Required<Env> {
  return {
    db: env.db,
    now: env.now ?? (() => new Date()),
    newId: env.newId ?? (() => randomUUID()),
  };
}

// ── 살까말까 보내기 ────────────────────────────────────────────

export async function sendBasket(
  envIn: Env,
  caller: string,
  args: { threadId: string; recipientIds: string[]; items: unknown; memo?: string | null },
): Promise<number> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  if (!THREAD_ID.test(args.threadId ?? '')) fail('INVALID_INPUT');
  const memo = cleanText(args.memo, LIMITS.memo, { required: false });
  const items = sanitizeItems(args.items);

  const wanted = [...new Set(args.recipientIds ?? [])].filter((id) => id && id !== caller);
  if (wanted.length === 0) fail('NO_RECIPIENTS');
  if (wanted.length > LIMITS.recipients) fail('TOO_MANY_RECIPIENTS');

  const from = await authorOf(env, caller);
  // 탈퇴했거나 없는 사람에게는 보내지 않는다.
  const recipients: string[] = [];
  for (const id of wanted) {
    if (await env.db.get('Profile', { ownerId: id })) recipients.push(id);
  }
  if (recipients.length === 0) fail('NO_RECIPIENTS');

  // 댓글방: 남의 댓글방에 끼어들 수 없다.
  const thread = await env.db.get('BasketThread', { threadId: args.threadId });
  if (thread && thread.ownerId !== caller) fail('THREAD_CONFLICT');
  const before = new Set((thread?.participantIds as string[] | undefined) ?? []);
  const participants = [...new Set([...before, caller, ...recipients])];
  await env.db.put(
    'BasketThread',
    stamp(
      'BasketThread',
      { threadId: args.threadId, ownerId: caller, participantIds: participants, memo },
      now,
      thread,
    ),
  );

  // 참여자가 늘었으면, 새 참여자도 기존 댓글을 볼 수 있게 목록을 고친다.
  if (thread && participants.length !== before.size) {
    const comments = await env.db.query('BasketComment', 'threadId', args.threadId);
    for (const c of comments) {
      await env.db.put('BasketComment', { ...c, participantIds: participants, updatedAt: now });
    }
  }

  for (const recipientId of recipients) {
    const basketId = env.newId();
    await env.db.put(
      'ReceivedBasket',
      stamp(
        'ReceivedBasket',
        {
          recipientId,
          basketId,
          fromUid: caller,
          data: {
            id: basketId,
            title: `${from.name}의 살까말까`,
            ownerName: from.name,
            fromUid: caller,
            fromHandle: from.handle,
            fromAvatar: from.avatar,
            items,
            createdAt: now,
            channels: ['friends'],
            memo,
            threadId: args.threadId,
          },
        },
        now,
      ),
    );
    await notify(
      env,
      recipientId,
      from,
      'basket',
      `${from.name} 님이 살까말까 장바구니를 보냈어요`,
      args.threadId,
      now,
    );
  }
  return recipients.length;
}

// ── 댓글 ──────────────────────────────────────────────────────

/** 답글의 답글은 가장 위 댓글에 붙인다 (앱의 flattenCommentParentId 와 같은 규칙). */
function flattenParent(parentId: string, comments: Row[]): string {
  if (!parentId) return '';
  const parent = comments.find((c) => c.commentId === parentId);
  if (!parent || !parent.parentId) return parentId;
  return String(parent.parentId);
}

export async function addComment(
  envIn: Env,
  caller: string,
  args: {
    threadId: string;
    text: string;
    parentId?: string | null;
    participantIds?: string[] | null;
    memo?: string | null;
  },
): Promise<Row> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  if (!THREAD_ID.test(args.threadId ?? '')) fail('INVALID_INPUT');
  const text = cleanText(args.text, LIMITS.text, { required: true });

  let thread = await env.db.get('BasketThread', { threadId: args.threadId });
  if (!thread) {
    // 댓글방이 없으면: 호출한 사람을 방장으로 새로 만든다 (보낸 사람의 첫 댓글).
    const extra = [...new Set(args.participantIds ?? [])]
      .filter((id) => id && id !== caller)
      .slice(0, LIMITS.recipients);
    thread = stamp(
      'BasketThread',
      {
        threadId: args.threadId,
        ownerId: caller,
        participantIds: [caller, ...extra],
        memo: cleanText(args.memo, LIMITS.memo, { required: false }),
      },
      now,
    );
    await env.db.put('BasketThread', thread);
  }
  const participants = (thread.participantIds as string[]) ?? [];
  if (!participants.includes(caller)) fail('NOT_PARTICIPANT');

  const existing = await env.db.query('BasketComment', 'threadId', args.threadId);
  const parentId = flattenParent(String(args.parentId ?? ''), existing);
  const from = await authorOf(env, caller);
  const commentId = env.newId();
  const comment = {
    id: commentId,
    threadId: args.threadId,
    parentId,
    authorUid: caller,
    authorName: from.name,
    authorHandle: from.handle,
    authorAvatar: from.avatar,
    text,
    createdAt: now,
    updatedAt: null,
  };
  await env.db.put(
    'BasketComment',
    stamp(
      'BasketComment',
      {
        threadId: args.threadId,
        commentId,
        authorId: caller,
        parentId,
        participantIds: participants,
        data: comment,
      },
      now,
    ),
  );

  // 알림 대상 (원래 앱 규칙 그대로)
  const owner = String(thread.ownerId);
  const targets = new Set<string>();
  if (owner && owner !== caller) targets.add(owner);
  if (parentId) {
    const parent = existing.find((c) => c.commentId === parentId);
    const parentAuthor = parent ? String(parent.authorId ?? '') : '';
    if (parentAuthor && parentAuthor !== caller) targets.add(parentAuthor);
  } else if (caller === owner) {
    participants.filter((id) => id !== caller).forEach((id) => targets.add(id));
  }
  const message = parentId
    ? `${from.name} 님이 살까말까 댓글에 답글을 남겼어요`
    : `${from.name} 님이 살까말까에 댓글을 남겼어요`;
  for (const t of targets) {
    await notify(env, t, from, 'comment', message, args.threadId, now);
  }
  return comment;
}

async function ownComment(env: Env, caller: string, threadId: string, commentId: string) {
  const row = await env.db.get('BasketComment', { threadId, commentId });
  if (!row) return undefined;
  if (row.authorId !== caller) fail('NOT_AUTHOR');
  return row;
}

export async function updateComment(
  envIn: Env,
  caller: string,
  args: { threadId: string; commentId: string; text: string },
): Promise<boolean> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  const text = cleanText(args.text, LIMITS.text, { required: true });
  const row = await ownComment(env, caller, args.threadId, args.commentId);
  if (!row) fail('COMMENT_NOT_FOUND');
  const data = { ...(asJson(row!.data) as Row), text, updatedAt: now };
  await env.db.put('BasketComment', { ...row, data, updatedAt: now });
  return true;
}

export async function deleteComment(
  envIn: Env,
  caller: string,
  args: { threadId: string; commentId: string },
): Promise<boolean> {
  const env = withDefaults(envIn);
  const row = await ownComment(env, caller, args.threadId, args.commentId);
  if (row) await env.db.del('BasketComment', { threadId: args.threadId, commentId: args.commentId });
  return true;
}

// ── 팔로우 알림 ────────────────────────────────────────────────

export async function notifyFollow(
  envIn: Env,
  caller: string,
  args: { targetId: string },
): Promise<boolean> {
  const env = withDefaults(envIn);
  const now = env.now().toISOString();
  if (!args.targetId || args.targetId === caller) return false;
  const edge = await env.db.get('Follow', { followerId: caller, followeeId: args.targetId });
  if (!edge) fail('NOT_FOLLOWING');
  const from = await authorOf(env, caller);
  // 알림 id 를 고정 → 팔로우를 껐다 켜도 알림은 하나만 (최신으로 갱신)
  await notify(
    env,
    args.targetId,
    from,
    'follow',
    `${from.name} 님이 회원님을 팔로우하기 시작했어요`,
    '',
    now,
    `follow-${caller}`,
  );
  return true;
}
