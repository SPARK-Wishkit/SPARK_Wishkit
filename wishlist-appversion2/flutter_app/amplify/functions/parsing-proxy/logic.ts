/**
 * parsing-engine 서버(POST /extract) 응답을 앱이 쓰기 편한 모양으로 바꾸는 순수 로직.
 * 실제 HTTP 호출은 handler.ts에서 한다(테스트에서 가짜로 바꿔 끼우기 위함).
 *
 * 엔진 서버의 실제 응답 스키마는
 * 2026-softstudio-project(이관 전 저장소)의 parsing-engine/server/main.py `_extract()` 참고.
 */

/** 엔진 서버(POST /extract)가 실제로 돌려주는 응답 모양. */
export interface EngineExtractResponse {
  product_name: string | null;
  price: {
    unconditional_price: number | null;
    regular_price: number | null;
    currency: string;
  } | null;
  image_url: string | null;
  ambiguous: boolean;
  ambiguity_reason: string | null;
  confidence: string;
}

/** 이 함수가 앱에 돌려주는 모양(GraphQL ExtractedProduct와 1:1로 맞춤). */
export interface ExtractedProduct {
  productName: string | null;
  unconditionalPrice: number | null;
  regularPrice: number | null;
  currency: string | null;
  imageUrl: string | null;
  ambiguous: boolean;
  ambiguityReason: string | null;
  confidence: string | null;
}

/** http(s) URL인지만 확인한다 — 몰별 상세 검증은 엔진 서버가 한다. */
export function isValidHttpUrl(value: string): boolean {
  try {
    const parsed = new URL(value);
    return parsed.protocol === 'http:' || parsed.protocol === 'https:';
  } catch {
    return false;
  }
}

export function toExtractedProduct(res: EngineExtractResponse): ExtractedProduct {
  return {
    productName: res.product_name,
    unconditionalPrice: res.price?.unconditional_price ?? null,
    regularPrice: res.price?.regular_price ?? null,
    currency: res.price?.currency ?? null,
    imageUrl: res.image_url,
    ambiguous: res.ambiguous,
    ambiguityReason: res.ambiguity_reason,
    confidence: res.confidence,
  };
}
