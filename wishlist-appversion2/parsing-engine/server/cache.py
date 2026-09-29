"""
캐시 인터페이스 (요구사항 5 — 실제 캐시 저장소는 아직 구현하지 않는다).

AWS DB 이관 트랙이 아직 정해지지 않았으므로, 여기서는 "나중에 실제 캐시(Redis/DynamoDB
등)를 붙일 자리"만 Protocol로 열어두고, 지금은 아무것도 저장하지 않는 `NoOpCache`만
기본으로 꽂아둔다. main.py는 `RenderCache` 타입에만 의존하므로, 나중에 실제 구현체로
바꿔 끼워도 main.py를 고칠 필요가 없다.
"""
from __future__ import annotations

import urllib.parse
from dataclasses import dataclass
from typing import Protocol

# 캐시 무효화에 영향 없는 트래킹/세션성 쿼리 파라미터. 실제 운영 전에 몰별로 더 늘려야 할
# 수 있다 — 지금은 흔한 패턴(utm_*, 광고/추천 트래킹용 파라미터)만 우선 넣어뒀다.
_IGNORED_QUERY_PREFIXES = ("utm_", "gclid", "fbclid", "igshid", "ref", "referrer")


def normalize_cache_key(url: str) -> str:
    """같은 상품인데 트래킹 파라미터만 다른 URL이 서로 다른 캐시 키가 되는 걸 방지한다.
    호스트는 소문자로, 쿼리 파라미터는 트래킹성 파라미터를 제외하고 이름순으로 정렬한다.
    fragment(#...)는 항상 버린다(서버 렌더링 결과에 영향을 주지 않으므로)."""
    parsed = urllib.parse.urlsplit(url)
    host = parsed.netloc.lower()
    path = parsed.path.rstrip("/") or "/"

    kept_params = [
        (k, v)
        for k, v in urllib.parse.parse_qsl(parsed.query, keep_blank_values=True)
        if not any(k.lower().startswith(p) for p in _IGNORED_QUERY_PREFIXES)
    ]
    kept_params.sort()
    query = urllib.parse.urlencode(kept_params)

    normalized = urllib.parse.urlunsplit((parsed.scheme.lower(), host, path, query, ""))
    return normalized


@dataclass
class CachedExtraction:
    """캐시에 저장/조회할 값의 모양 — 실제 추출 결과 전체를 담는다."""
    data: dict
    cached_at_ms: int


class RenderCache(Protocol):
    async def get(self, key: str) -> CachedExtraction | None: ...

    async def set(self, key: str, value: CachedExtraction, ttl_seconds: int) -> None: ...


class NoOpCache:
    """지금 당장 쓰는 기본 구현 — 아무것도 저장하지 않고 항상 캐시 미스로 취급한다.
    DB/캐시 백엔드가 정해지면 이 클래스를 실제 구현체로 교체한다(main.py는 안 고쳐도 됨)."""

    async def get(self, key: str) -> CachedExtraction | None:
        return None

    async def set(self, key: str, value: CachedExtraction, ttl_seconds: int) -> None:
        return None
