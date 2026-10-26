"""
tag_identify.py 단위 테스트. Gemini·브라우저는 가짜로 바꿔 끼운다(실제 호출 없음).
실제 태그 사진으로 정확도를 재는 건 tools/tag_identify_check.py로 한다.
"""
import asyncio

import pytest

import tag_identify
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


@pytest.fixture(autouse=True)
def _no_mall_search(monkeypatch):
    """기존 테스트는 구글 검색 경로를 시험한다 — 쇼핑몰 직접 검색은 끈다(아래 무신사 테스트는 malls 를 직접 넘긴다)."""
    monkeypatch.setattr(tag_identify, "MALL_SEARCHES", ())


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


# ── 쇼핑몰(무신사) 직접 검색 → 못 찾으면 구글 검색 (2026-10-26) ──

from mall_search import MUSINSA, search_query

TAG_1993 = {**NIKE_TAG, "brand": "1993STUDIO", "product_code": "93251TTL1202", "barcode": None,
            "other_codes": ["93251TTL120202M"], "product_name": None, "tag_price": 29900}
SEARCH_URL = MUSINSA.search_urls_for("93251TTL1202")[0]
P1, P2 = "https://www.musinsa.com/products/5551111", "https://www.musinsa.com/products/5552222"


def _mall_run(pages: dict, *, search_result=None):
    calls = {"render": [], "search": 0}

    async def render_page(url):
        calls["render"].append(url)
        return pages.get(url) or PageView(False, url, "", "없는 페이지")

    async def search(tag):
        calls["search"] += 1
        return search_result or _ok({"text": "", "sources": []})

    out = _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(TAG_1993), search=search,
                        render_page=render_page, time_left=lambda: 40, malls=(MUSINSA,)))
    return out, calls


def test_search_query_prefers_code_alone():
    assert search_query(TAG_1993) == "93251TTL1202"
    assert search_query({"brand": "NIKE", "product_name": "에어 포스 1"}) == "NIKE 에어 포스 1"
    assert search_query({"brand": "NIKE"}) is None


def test_product_links_are_collected_in_order_without_duplicates():
    html = '<a href="/products/5551111">a</a><a href="https://www.musinsa.com/products/5552222">b</a>' \
           '<a href="/products/5551111">dup</a><a href="/products/123">짧은 번호</a>'
    assert MUSINSA.product_urls_in(html, 3) == [P1, P2]


def test_found_on_musinsa_search_skips_google_search():
    search_page = PageView(True, SEARCH_URL, "검색 결과", html=f'<a href="/products/5551111"></a><a href="{P2}"></a>')
    pages = {SEARCH_URL: search_page,
             P1: PageView(True, P1, "다른 상품 99251XXX0001"),
             P2: PageView(True, P2, "1993STUDIO 티셔츠 품번 93251TTL1202 29,900원")}
    out, calls = _mall_run(pages)
    assert out.status == "found" and out.match["url"] == P2 and out.match["source"] == "mall"
    assert out.match["verified_by"] == "product_code" and out.match["tag_price_seen"] is True
    assert calls["search"] == 0  # 구글 검색(유료 한도)을 안 썼다
    assert calls["render"] == [SEARCH_URL, P1, P2]


def test_falls_back_to_second_search_url_then_google_when_not_on_musinsa():
    second = MUSINSA.search_urls_for("93251TTL1202")[1]
    pages = {SEARCH_URL: PageView(True, SEARCH_URL, "검색 결과 없음", html="<div>없어요</div>"),
             second: PageView(True, second, "검색 결과 없음", html="")}
    official = "https://www.1993studio.com/product/detail.html?product_no=77"
    pages[official] = PageView(True, official, "93251TTL1202 화이트")
    out, calls = _mall_run(pages, search_result=_ok({"text": f"OFFICIAL_DOMAIN: 1993studio.com\nURL: {official}",
                                                     "sources": []}))
    assert calls["render"][:2] == [SEARCH_URL, second]
    assert calls["search"] == 1
    assert out.status == "found" and out.match["source"] == "official"


def test_musinsa_pages_without_code_then_google_failure_reports_checked_pages():
    pages = {SEARCH_URL: PageView(True, SEARCH_URL, "", html=f'<a href="{P1}"></a>'),
             P1: PageView(True, P1, "비슷한 다른 상품")}
    out, calls = _mall_run(pages, search_result=ProviderResult("s", "m", False, None, 1, "429"))
    assert out.status == "not_found"
    assert out.checked == [{"url": P1, "source": "mall", "verified": False, "reason": None}]
    assert calls["search"] == 1


def test_blocked_musinsa_search_goes_straight_to_google_and_keeps_time_for_it():
    clock = {"left": 18.0}
    calls = {"render": [], "search": 0}

    async def render_page(url):
        calls["render"].append(url)
        clock["left"] -= 7  # 느리고 막힘
        return PageView(False, url, "", "시간 초과")

    async def search(tag):
        calls["search"] += 1
        return _ok({"text": "", "sources": []})

    _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(TAG_1993), search=search,
                  render_page=render_page, time_left=lambda: clock["left"], malls=(MUSINSA,)))
    assert calls["render"] == [SEARCH_URL]  # 두 번째 검색 주소는 시도하지 않음
    assert calls["search"] == 1


def test_mall_phase_is_skipped_when_only_google_reserve_is_left():
    calls = {"render": [], "search": 0}

    async def render_page(url):
        calls["render"].append(url)
        return PageView(False, url, "", "x")

    async def search(tag):
        calls["search"] += 1
        return _ok({"text": "", "sources": []})

    _run(identify(b"img", "image/jpeg", read_tag=_tag_reader(TAG_1993), search=search,
                  render_page=render_page, time_left=lambda: 14.0, malls=(MUSINSA,)))
    assert calls["render"] == []  # 14초 - 구글 몫 10초 < 6초 → 쇼핑몰 검색 생략
    assert calls["search"] == 1


# ── 무신사 품번 검색 결과가 1~2개면, 페이지에 품번이 없어도 브랜드·가격으로 "검색 일치" (2026-10-26) ──

def _one_result(product_text: str, n_results: int = 1):
    links = "".join(f'<a href="/products/{5046318 + i}"></a>' for i in range(n_results))
    p = "https://www.musinsa.com/products/5046318"
    pages = {SEARCH_URL: PageView(True, SEARCH_URL, "", html=links), p: PageView(True, p, product_text)}
    for i in range(1, n_results):
        q = f"https://www.musinsa.com/products/{5046318 + i}"
        pages[q] = PageView(True, q, "다른 상품")
    return pages, p


def test_single_musinsa_code_result_with_brand_is_a_search_match_even_after_google_429():
    pages, p = _one_result("1993STUDIO 오버핏 반팔 티셔츠 화이트 정가 29,900원")
    out, calls = _mall_run(pages, search_result=ProviderResult("s", "m", False, None, 1, "429"))
    assert out.status == "found" and out.match["url"] == p
    assert out.match["verified_by"] == "search_match" and out.match["tag_price_seen"] is True
    assert calls["search"] == 1  # 품번 확인이 아니라서 구글 검색도 시도는 한다(유료 키면 더 확실한 페이지를 찾을 수 있게)


def test_single_result_with_only_tag_price_is_also_a_search_match():
    pages, _ = _one_result("오버핏 반팔 티셔츠 29,900원")
    out, _ = _mall_run(pages, search_result=ProviderResult("s", "m", False, None, 1, "429"))
    assert out.status == "found" and out.match["verified_by"] == "search_match"


def test_single_result_without_brand_or_price_is_not_accepted():
    pages, _ = _one_result("전혀 다른 브랜드 상품 15,000원")
    out, _ = _mall_run(pages, search_result=ProviderResult("s", "m", False, None, 1, "429"))
    assert out.status == "not_found"


def test_many_results_are_not_trusted_without_the_code_on_the_page():
    pages, _ = _one_result("1993STUDIO 반팔 29,900원", n_results=3)
    out, _ = _mall_run(pages, search_result=ProviderResult("s", "m", False, None, 1, "429"))
    assert out.status == "not_found"


def test_code_verified_google_page_beats_musinsa_search_match():
    pages, _ = _one_result("1993STUDIO 반팔 29,900원")
    official = "https://www.1993studio.com/product/77"
    pages[official] = PageView(True, official, "STYLE 93251TTL1202")
    out, _ = _mall_run(pages, search_result=_ok({"text": f"OFFICIAL_DOMAIN: 1993studio.com\nURL: {official}", "sources": []}))
    assert out.match["url"] == official and out.match["verified_by"] == "product_code"
