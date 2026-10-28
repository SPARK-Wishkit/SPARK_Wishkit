"""
tag_identify.py 단위 테스트. Gemini·브라우저는 가짜로 바꿔 끼운다(실제 호출 없음).
실제 태그 사진으로 정확도를 재는 건 tools/tag_identify_check.py로 한다.
"""
import asyncio

import pytest

from providers import ProviderResult
from tag_identify import (
    IdentifyError,
    PageView,
    classify_host,
    identify,
    normalize_code,
    page_matches,
    parse_search_output,
)

NIKE_TAG = {
    "is_product_tag": True,
    "brand": "NIKE",
    "product_code": "DV1234-100",
    "barcode": None,
    "product_name": "에어 포스 1 '07",
    "color": "WHITE",
    "size": "270",
    "tag_price": 139000,
    "confidence": "high",
}

REDIRECT = "https://vertexaisearch.cloud.google.com/grounding-api-redirect/abc"


def _ok(data):
    return ProviderResult("fake", "fake", True, data, 1)


def _run(coro):
    return asyncio.run(coro)


# ── 순수 로직 ──

def test_normalize_code_ignores_separators_and_case():
    assert normalize_code("DV1234-100") == normalize_code("dv1234 100") == "dv1234100"


def test_classify_host():
    assert classify_host("nike.com", "nike.com") == "official"
    assert classify_host("m.nike.com", "nike.com") == "official"
    assert classify_host("musinsa.com", "nike.com") == "mall"
    assert classify_host("blog.naver.com", "nike.com") == "other"
    assert classify_host("random-shop.kr", "nike.com") == "other"
    assert classify_host("notnike.com", "nike.com") == "other"  # 접미사만 같은 다른 도메인


def test_parse_search_output_puts_official_first_and_drops_blogs():
    text = """OFFICIAL_DOMAIN: nike.com
URL: https://www.musinsa.com/products/123
URL: https://blog.naver.com/someone/1
URL: https://www.nike.com/kr/t/air-force-1/DV1234-100
"""
    sources = [{"uri": REDIRECT, "title": "kream.co.kr"}]
    official, cands = parse_search_output(text, sources)
    assert official == "nike.com"
    assert [c.source for c in cands] == ["official", "mall", "mall"]
    assert cands[0].url == "https://www.nike.com/kr/t/air-force-1/DV1234-100"
    assert cands[2].url == REDIRECT and cands[2].hint_host == "kream.co.kr"


def test_parse_search_output_rejects_mall_as_official_domain():
    official, cands = parse_search_output("OFFICIAL_DOMAIN: musinsa.com\nURL: https://www.musinsa.com/products/1", [])
    assert official is None
    assert cands[0].source == "mall"


def test_page_matches_by_code_even_with_different_separators():
    assert page_matches(NIKE_TAG, "스타일: DV1234 100 · 화이트", "https://x") == "product_code"
    assert page_matches(NIKE_TAG, "아무 글자", "https://www.nike.com/kr/t/af1/DV1234-100") == "product_code"


def test_page_matches_rejects_similar_name_when_code_missing_on_page():
    # 품번이 있는데 페이지에 없으면 — 이름이 같아도 다른 색상/모델일 수 있으니 인정하지 않는다.
    assert page_matches(NIKE_TAG, "NIKE 에어 포스 1 '07 블랙 DV0000-001", "https://x") is None


def test_page_matches_by_name_only_when_tag_has_no_code():
    tag = {**NIKE_TAG, "product_code": None, "barcode": None, "product_name": "소프트 헨리넥 반팔 티셔츠"}
    assert page_matches(tag, "NIKE 소프트 헨리넥 반팔 티셔츠 브라운", "https://x") == "name"
    assert page_matches(tag, "ADIDAS 소프트 헨리넥 반팔 티셔츠", "https://x") is None  # 브랜드 불일치


# ── 오케스트레이션 ──

def _fakes(search_text, pages, sources=None):
    calls = {"render": []}

    async def read_tag(img, mime):
        return _ok(dict(NIKE_TAG))

    async def search(tag):
        return _ok({"text": search_text, "sources": sources or []})

    async def render_page(url):
        calls["render"].append(url)
        return pages.get(url, PageView(ok=False, final_url=url, raw_text="", error="없음"))

    return read_tag, search, render_page, calls


def test_identify_prefers_official_site_with_code():
    official = "https://www.nike.com/kr/t/af1/DV1234-100"
    mall = "https://www.musinsa.com/products/1"
    read_tag, search, render_page, calls = _fakes(
        f"OFFICIAL_DOMAIN: nike.com\nURL: {mall}\nURL: {official}",
        {
            official: PageView(True, official, "에어 포스 1 DV1234-100"),
            mall: PageView(True, mall, "나이키 에어포스 DV1234-100"),
        },
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "found"
    assert out.match["source"] == "official"
    assert out.match["url"] == official
    assert calls["render"] == [official]  # 공식몰에서 바로 확인됐으니 쇼핑몰은 안 열어 봄


def test_identify_falls_back_to_mall_when_official_page_lacks_code():
    official = "https://www.nike.com/kr/t/af1/other"
    mall = "https://www.musinsa.com/products/1"
    read_tag, search, render_page, _ = _fakes(
        f"OFFICIAL_DOMAIN: nike.com\nURL: {official}\nURL: {mall}",
        {
            official: PageView(True, official, "다른 상품 DV9999-001"),
            mall: PageView(True, mall, "나이키 에어포스 DV1234-100"),
        },
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "found"
    assert out.match["source"] == "mall"
    assert out.match["verified_by"] == "product_code"


def test_identify_uses_final_url_after_grounding_redirect():
    final = "https://www.nike.com/kr/t/af1/DV1234-100"
    read_tag, search, render_page, _ = _fakes(
        "OFFICIAL_DOMAIN: nike.com",
        {REDIRECT: PageView(True, final, "DV1234-100")},
        sources=[{"uri": REDIRECT, "title": "nike.com"}],
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "found"
    assert out.match["url"] == final
    assert out.match["source"] == "official"


def test_identify_not_found_when_nothing_verifies():
    url = "https://www.musinsa.com/products/1"
    read_tag, search, render_page, _ = _fakes(
        f"OFFICIAL_DOMAIN: 없음\nURL: {url}", {url: PageView(True, url, "전혀 다른 상품")}
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "not_found"
    assert out.match is None
    assert out.tag["product_code"] == "DV1234-100"  # 앱이 이름이라도 채울 수 있게 태그는 돌려준다


def test_identify_skips_renders_when_out_of_time():
    url = "https://www.musinsa.com/products/1"
    read_tag, search, render_page, calls = _fakes(
        f"URL: {url}", {url: PageView(True, url, "DV1234-100")}
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 3))
    assert out.status == "not_found"
    assert calls["render"] == []


def test_identify_not_a_tag():
    async def read_tag(img, mime):
        return _ok({**NIKE_TAG, "is_product_tag": False})

    async def never(*_):
        raise AssertionError("검색하면 안 됨")

    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=never,
                        render_page=never, time_left=lambda: 40))
    assert out.status == "not_a_tag"


def test_identify_raises_when_tag_reading_fails():
    async def read_tag(img, mime):
        return ProviderResult("fake", "fake", False, None, 1, error="boom")

    with pytest.raises(IdentifyError):
        _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=None,
                      render_page=None, time_left=lambda: 40))


# ── 바코드 검증 · 태그 가격 · 후보 순위 (2026-10-23 추가) ──

def _tag_reader(tag):
    async def read_tag(img, mime):
        return _ok(dict(tag))
    return read_tag


def test_identify_drops_barcode_with_wrong_check_digit():
    seen = {}

    async def search(tag):
        seen["tag"] = tag
        return _ok({"text": "", "sources": []})

    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader({**NIKE_TAG, "barcode": "8801234567890"}),
                        search=search, render_page=None, time_left=lambda: 40))
    assert seen["tag"]["barcode"] is None
    assert out.tag["barcode_rejected"] == "8801234567890"


def test_identify_prefers_page_showing_tag_price_among_equal_matches():
    a, b = "https://www.musinsa.com/products/1", "https://www.29cm.co.kr/products/2"
    read_tag, search, render_page, _ = _fakes(
        f"OFFICIAL_DOMAIN: 없음\nURL: {a}\nURL: {b}",
        {a: PageView(True, a, "DV1234-100 99,000원"), b: PageView(True, b, "DV1234-100 정가 139,000원")},
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.match["url"] == b and out.match["tag_price_seen"] is True


def test_official_base_code_match_beats_mall_full_code_match():
    official, mall = "https://www.nike.com/kr/t/af1/x", "https://www.musinsa.com/products/1"
    read_tag, search, render_page, _ = _fakes(
        f"OFFICIAL_DOMAIN: nike.com\nURL: {mall}\nURL: {official}",
        {mall: PageView(True, mall, "나이키 DV1234-100"), official: PageView(True, official, "스타일: DV1234")},
    )
    out = _run(identify(b"img", "image/jpeg", read_tag=read_tag, search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.match["url"] == official and out.match["verified_by"] == "product_code_base"


def test_mall_code_match_still_beats_official_name_only_match():
    tag = {**NIKE_TAG, "product_code": None, "barcode": None, "product_name": "소프트 헨리넥 반팔 티셔츠"}
    official, mall = "https://www.nike.com/kr/t/x", "https://www.musinsa.com/products/1"

    async def search(t):
        return _ok({"text": f"OFFICIAL_DOMAIN: nike.com\nURL: {official}\nURL: {mall}", "sources": []})

    pages = {official: PageView(True, official, "NIKE 소프트 헨리넥 반팔 티셔츠"),
             mall: PageView(True, mall, "NIKE 소프트 헨리넥 반팔 티셔츠")}

    async def render_page(url):
        return pages[url]

    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(tag), search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.match["url"] == official and out.match["verified_by"] == "name"  # 둘 다 이름 → 공식몰


# ── 무신사 검색 단계를 뺀 뒤 (2026-10-28) ──

TAG_1993 = {**NIKE_TAG, "brand": "1993STUDIO", "product_code": "93251TTL1202", "barcode": None,
            "other_codes": [], "product_name": None, "tag_price": 29900}


def test_google_search_finds_official_site_without_musinsa_step():
    official = "https://1993studio.com/product/detail.html?product_no=1"
    rendered = []

    async def search(tag):
        return _ok({"text": f"OFFICIAL_DOMAIN: 1993studio.com\nURL: {official}", "sources": []})

    async def render_page(url):
        rendered.append(url)
        return PageView(True, url, "1993STUDIO 베이직 우먼 롱슬리브 93251TTL1202 29,900원")

    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(TAG_1993), search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "found" and out.match["source"] == "official"
    assert rendered == [official]  # 무신사 검색 페이지를 열지 않는다


def test_google_search_429_gives_quota_note():
    async def search(tag):
        return ProviderResult("s", "m", False, None, 1, "ClientError: 429 RESOURCE_EXHAUSTED")

    async def render_page(url):
        raise AssertionError("검색이 실패하면 페이지를 열지 않는다")

    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(TAG_1993), search=search,
                        render_page=render_page, time_left=lambda: 40))
    assert out.status == "not_found" and "한도" in out.note
