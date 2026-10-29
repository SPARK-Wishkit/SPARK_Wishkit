import asyncio

from cache import CachedExtraction, InProcessCache, normalize_cache_key


def _run(coro):
    return asyncio.run(coro)


def test_in_process_cache_roundtrip():
    cache = InProcessCache()
    _run(cache.set("k", CachedExtraction(data={"v": 1}, cached_at_ms=0), ttl_seconds=60))
    assert _run(cache.get("k")).data == {"v": 1}


def test_in_process_cache_misses_unknown_key():
    assert _run(InProcessCache().get("missing")) is None


def test_in_process_cache_expires_after_ttl(monkeypatch):
    import cache as cache_module

    clock = {"t": 1000.0}
    monkeypatch.setattr(cache_module.time, "monotonic", lambda: clock["t"])
    cache = InProcessCache()
    _run(cache.set("k", CachedExtraction(data={"v": 1}, cached_at_ms=0), ttl_seconds=10))
    clock["t"] += 9.9
    assert _run(cache.get("k")) is not None
    clock["t"] += 0.2
    assert _run(cache.get("k")) is None  # 10초 지남 — 미스


def test_in_process_cache_evicts_least_recently_used_when_full():
    cache = InProcessCache(max_entries=2)
    _run(cache.set("a", CachedExtraction(data={"v": "a"}, cached_at_ms=0), ttl_seconds=60))
    _run(cache.set("b", CachedExtraction(data={"v": "b"}, cached_at_ms=0), ttl_seconds=60))
    _run(cache.get("a"))  # a를 다시 사용 — b가 더 "오래된" 것으로 밀림
    _run(cache.set("c", CachedExtraction(data={"v": "c"}, cached_at_ms=0), ttl_seconds=60))  # b가 밀려남
    assert _run(cache.get("a")) is not None
    assert _run(cache.get("b")) is None
    assert _run(cache.get("c")) is not None


def test_strips_tracking_params():
    a = normalize_cache_key("https://example.com/goods/1?utm_source=insta&gclid=abc")
    b = normalize_cache_key("https://example.com/goods/1")
    assert a == b


def test_keeps_meaningful_query_params():
    a = normalize_cache_key("https://example.com/goods/1?color=red&size=M")
    b = normalize_cache_key("https://example.com/goods/1?size=M&color=red")
    assert a == b  # 순서 무관하게 정렬됨
    c = normalize_cache_key("https://example.com/goods/1?color=blue&size=M")
    assert a != c  # 실제로 다른 값은 다른 키


def test_lowercases_host_and_drops_fragment():
    a = normalize_cache_key("https://Example.COM/goods/1#reviews")
    b = normalize_cache_key("https://example.com/goods/1")
    assert a == b


def test_strips_trailing_slash():
    a = normalize_cache_key("https://example.com/goods/1/")
    b = normalize_cache_key("https://example.com/goods/1")
    assert a == b
