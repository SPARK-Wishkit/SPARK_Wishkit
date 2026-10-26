"""
쇼핑몰 자체 검색으로 상품 후보 찾기 — AI·구글 검색을 쓰지 않는다(무료, 한도 없음).

태그 찾기(tag_identify.identify)는 먼저 여기서 품번으로 쇼핑몰을 직접 검색하고, 거기서 품번이 확인된
상품 페이지를 못 찾았을 때만 Gemini + 구글 검색(유료 한도)을 쓴다.

사람이 하는 것과 같다: 쇼핑몰 검색창에 품번을 넣고 → 결과의 상품 링크를 모은다. 어느 링크가 맞는지는
여기서 판단하지 않는다 — tag_identify 가 상품 페이지를 열어 품번이 실제로 적혀 있는지 확인한다.

쇼핑몰마다 필요한 것은 두 가지뿐: 검색 주소 모양, 상품 링크 모양.
검색 주소가 바뀌면 코드 수정 없이 환경변수(예: MUSINSA_SEARCH_URLS)로 바꿀 수 있다.
"""
from __future__ import annotations

import os
import re
import urllib.parse
from dataclasses import dataclass


@dataclass(frozen=True)
class MallSearch:
    name: str
    domain: str
    # {q} 자리에 검색어가 들어간다. 앞에서부터 시도하고, 상품 링크가 나오면 거기서 멈춘다.
    search_urls: tuple[str, ...]
    # 검색 결과 HTML 에서 상품 번호를 꺼내는 정규식(그룹 1 = 상품 번호)
    product_link: re.Pattern
    # 상품 번호 → 상품 페이지 주소
    product_url: str

    def search_urls_for(self, query: str) -> list[str]:
        q = urllib.parse.quote(query)
        return [template.replace("{q}", q) for template in self.search_urls]

    def product_urls_in(self, html: str, limit: int) -> list[str]:
        """검색 결과에 나온 순서대로, 중복 없이 상품 페이지 주소."""
        seen: dict[str, None] = {}
        for product_id in self.product_link.findall(html):
            seen.setdefault(self.product_url.format(id=product_id), None)
            if len(seen) >= limit:
                break
        return list(seen)


def _templates(env_name: str, default: tuple[str, ...]) -> tuple[str, ...]:
    """환경변수에 쉼표로 적은 주소들이 있으면 그걸 쓴다(쇼핑몰이 검색 주소를 바꿨을 때)."""
    raw = os.environ.get(env_name, "").strip()
    return tuple(t.strip() for t in raw.split(",") if "{q}" in t) or default


MUSINSA = MallSearch(
    name="무신사",
    domain="musinsa.com",
    search_urls=_templates(
        "MUSINSA_SEARCH_URLS",
        (
            "https://www.musinsa.com/search/goods?keyword={q}",
            "https://www.musinsa.com/search/musinsa/goods?q={q}",
        ),
    ),
    # 상품 링크: https://www.musinsa.com/products/4341120 또는 /products/4341120 (상대 경로)
    product_link=re.compile(r"(?:musinsa\.com)?/products/(\d{4,})"),
    product_url="https://www.musinsa.com/products/{id}",
)

# 먼저 직접 검색해 볼 쇼핑몰. 늘리려면 MallSearch 를 하나 더 만들어 여기에 넣는다.
MALL_SEARCHES: tuple[MallSearch, ...] = (MUSINSA,)


def search_query(tag: dict) -> str | None:
    """쇼핑몰 검색어. 품번이 있으면 품번만(쇼핑몰 검색은 브랜드를 섞으면 오히려 안 나오는 경우가 많다),
    없으면 브랜드 + 상품명. 둘 다 없으면 None(검색 안 함)."""
    code = (tag.get("product_code") or "").strip()
    if code:
        return code
    brand = (tag.get("brand") or "").strip()
    name = (tag.get("product_name") or "").strip()
    return f"{brand} {name}".strip() if brand and name else None
