/**
 * 친구에게 보여 줄 "공개" 위시리스트만 골라내는 순수 로직.
 * DynamoDB 조회는 밖에서 넣어 준다(테스트에서 가짜로 바꿔 끼우기 위함).
 */

export type Row = Record<string, unknown>;

/** ownerId 파티션을 읽어 isPublic=true 인 행만 돌려주는 함수. */
export type QueryPublic = (table: 'tab' | 'product', ownerId: string) => Promise<Row[]>;

export const ALL_TAB_ID = 'all';
export const MAX_OWNERS = 100;

export interface PublicWishlist {
  ownerId: string;
  tabs: Array<{ tabId: string; name: string; colorHex: string | null; sortOrder: number | null }>;
  products: Array<{
    productId: string;
    listId: string;
    name: string;
    price: number;
    image: string | null;
    platform: string | null;
    originalPrice: number | null;
    discount: number | null;
    productUrl: string | null;
  }>;
}

const str = (v: unknown): string | null => (typeof v === 'string' ? v : null);
const num = (v: unknown): number | null => (typeof v === 'number' ? v : null);

export async function loadPublicWishlist(query: QueryPublic, ownerId: string): Promise<PublicWishlist> {
  const [tabRows, productRows] = await Promise.all([
    query('tab', ownerId),
    query('product', ownerId),
  ]);

  const tabs = tabRows
    .filter((r) => r.isPublic === true && r.tabId !== ALL_TAB_ID && typeof r.tabId === 'string')
    .map((r) => ({
      tabId: r.tabId as string,
      name: str(r.name) ?? '',
      colorHex: str(r.colorHex),
      sortOrder: num(r.sortOrder),
    }))
    .sort((a, b) => (a.sortOrder ?? 0) - (b.sortOrder ?? 0));

  // 메모(memo)는 의도적으로 뺀다. 본인만 보는 정보.
  const products = productRows
    .filter((r) => r.isPublic === true && typeof r.productId === 'string')
    .map((r) => ({
      productId: r.productId as string,
      listId: str(r.listId) ?? ALL_TAB_ID,
      name: str(r.name) ?? '',
      price: num(r.price) ?? 0,
      image: str(r.image),
      platform: str(r.platform),
      originalPrice: num(r.originalPrice),
      discount: num(r.discount),
      productUrl: str(r.productUrl),
    }));

  return { ownerId, tabs, products };
}

export async function loadCounts(query: QueryPublic, ownerIds: string[]) {
  const unique = [...new Set(ownerIds)].slice(0, MAX_OWNERS);
  const out: Array<{ ownerId: string; listCount: number; itemCount: number }> = [];
  // 한 번에 10명씩 — DynamoDB 요청이 몰리지 않게.
  for (let i = 0; i < unique.length; i += 10) {
    const chunk = unique.slice(i, i + 10);
    const results = await Promise.all(
      chunk.map(async (ownerId) => {
        const w = await loadPublicWishlist(query, ownerId);
        return { ownerId, listCount: w.tabs.length, itemCount: w.products.length };
      }),
    );
    out.push(...results);
  }
  return out;
}
