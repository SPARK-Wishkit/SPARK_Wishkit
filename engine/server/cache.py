"""
캐시 인터페이스 + 인메모리 구현.

AWS DB 이관 트랙(Redis/DynamoDB 등 여러 태스크가 공유하는 백엔드)은 아직 정해지지
않아서, 당장은 "나중에 그 백엔드를 붙일 자리"만 Protocol로 열어둔다. 대신 그 결정을
기다리는 동안 추출 결과를 전혀 안 재사용하는 손해를 줄이려고, 태스크 프로세스 하나
안에서만 유효한 `InProcessCache`를 기본값으로 둔다 — 인프라 추가 없이 바로 쓸 수 있고,
나중에 공유 백엔드로 바꿔도 main.py는 `RenderCache` 타입에만 의존하므로 안 고쳐도 된다.

⚠️ 한계(알고 쓸 것): 태스크가 여러 개로 늘어나면(현재는 engine.sh가 `desired-count`
1개로만 운영) 각 태스크가 서로 다른 캐시를 가진다 — 태스크 간에 캐시가 공유되지
않는다. 그 땐 공유 백엔드가 필요하다.
"""
from __future__ import annotations

import time
import urllib.parse
from collections import OrderedDict
from dataclasses import dataclass
from typing import Protocol

# 캐시 키에서 제외할 트래킹성 쿼리 파라미터의 접두어(대소문자 무시). 실제 운영 전에 몰별로 더
# 늘려야 할 수 있다. 주의: 접두어 매칭이라 "ref"는 "referrer"뿐 아니라 "refId"처럼 상품을
# 구분하는 파라미터까지 지울 수 있다 — 그런 몰이 발견되면 정확 일치 목록으로 바꿀 것.
_IGNORED_QUERY_PREFIXES = ("utm_", "gclid", "fbclid", "igshid", "ref")


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
    query = urllib.parse.urlencode(sorted(kept_params))
    return urllib.parse.urlunsplit((parsed.scheme.lower(), host, path, query, ""))


@dataclass
class CachedExtraction:
    """캐시에 저장/조회할 값의 모양 — 실제 추출 결과 전체를 담는다."""
    data: dict
    cached_at_ms: int


class RenderCache(Protocol):
    async def get(self, key: str) -> CachedExtraction | None: ...

    async def set(self, key: str, value: CachedExtraction, ttl_seconds: int) -> None: ...


class NoOpCache:
    """아무것도 저장하지 않고 항상 캐시 미스로 취급한다. 테스트나 "캐시를 끄고 싶을 때"용 —
    평소 기본값은 아래 InProcessCache."""

    async def get(self, key: str) -> CachedExtraction | None:
        return None

    async def set(self, key: str, value: CachedExtraction, ttl_seconds: int) -> None:
        return None


# 엔트리 수 상한 — 메모리를 무제한으로 늘리지 않기 위함(TTL이 지나기 전에 트래픽이 몰려도
# 한도 이상 쌓이지 않게). 캐시된 응답 하나는 보통 1~2KB(스크린샷은 캐시에 안 들어감) 수준.
DEFAULT_MAX_ENTRIES = 1000


class InProcessCache:
    """태스크 프로세스 메모리 안에서만 유효한 캐시. TTL이 지났거나 엔트리 수가 상한을 넘으면
    (가장 오래전에 쓰인 것부터, LRU) 치운다. asyncio는 단일 스레드라 await 사이에 다른
    코루틴이 끼어들 순 있어도 get/set 각각은 원자적으로 끝나 별도 락이 필요 없다."""

    def __init__(self, max_entries: int = DEFAULT_MAX_ENTRIES):
        self._max_entries = max_entries
        self._store: OrderedDict[str, tuple[CachedExtraction, float]] = OrderedDict()

    async def get(self, key: str) -> CachedExtraction | None:
        entry = self._store.get(key)
        if entry is None:
            return None
        value, expires_at = entry
        if time.monotonic() >= expires_at:
            del self._store[key]
            return None
        self._store.move_to_end(key)  # 최근 사용으로 표시 (LRU)
        return value

    async def set(self, key: str, value: CachedExtraction, ttl_seconds: int) -> None:
        self._store[key] = (value, time.monotonic() + ttl_seconds)
        self._store.move_to_end(key)
        while len(self._store) > self._max_entries:
            self._store.popitem(last=False)  # 가장 오래전에 쓰인 것부터 제거
