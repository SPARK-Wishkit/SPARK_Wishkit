from cache import normalize_cache_key


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
