#!/usr/bin/env python3
"""Write live_field_compare_catalog.dart from collected live answers."""

from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "audit-logs" / "live-answers-2026-08-18.json"
DEST = ROOT / "flutter_app" / "integration_test" / "live_field_compare_catalog.dart"

ORDER = [
    "11번가",
    "무신사",
    "W컨셉",
    "29CM",
    "FILA",
    "하고",
    "룩핀",
    "탑텐",
    "무인양품",
    "현대Hmall",
    "롯데온",
    "미쏘",
    "데일리쥬",
    "리",
    "필루미네이트",
    "어반스터프",
    "낫포유",
    "인사일런스",
    "파브레가",
    "핫핑",
    "유니클로",
    "SSG",
    "더현대Hi",
    "에이블리",
    "지그재그",
    "KREAM",
    "게스",
    "반스",
    "커버낫",
    "코드그라피",
    "후아유",
    "Aritzia",
    "노이아고",
    "립합",
    "마하그리드",
    "비바스튜디오",
    "아모멘토",
    "앤더슨벨",
    "예일",
    "위드윤",
    "패션플러스",
    "프롬비기닝",
    "나이키",
    "올리브영",
    "퀸잇",
    "브랜디",
    "CJ온스타일",
    "4910",
    "SSF샵",
    "이랜드몰",
]

BAD_NAME = re.compile(
    r"^(상품명|brandi|이랜드몰|w concept|\[w concept\]|muji|무인양품|@codegraphy)$",
    re.I,
)


def dart_str(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def clean_name(name: str) -> str:
    name = re.sub(r"<[^>]+>", " ", name)
    name = re.sub(r"\s+", " ", name).strip()
    name = re.sub(r"^\[15%쿠폰\]", "", name).strip()
    return name


def good(item: dict) -> bool:
    name = clean_name(item.get("name") or "")
    price = item.get("price")
    image = item.get("image") or ""
    if not name or not price or not image:
        return False
    if BAD_NAME.match(name):
        return False
    if name.startswith("@") or len(name) < 3:
        return False
    if price == 5000 and "wconcept" in (item.get("url") or ""):
        return False
    if "seo_og" in image or "og_tag_lookpin" in image:
        return False
    return True


def main() -> None:
    data = json.loads(SRC.read_text(encoding="utf-8"))
    # Listing-confirmed W컨셉 answers (og:title is site-wide).
    data["W컨셉"] = [
        {
            "url": "https://www.wconcept.co.kr/Product/308678703",
            "ok": True,
            "name": "멀티 유즈 슬리브리스 탑 브라운 OU2006",
            "price": 29120,
            "image": "https://product-image.wconcept.co.kr/productimg/image/img9/03/308678703_UI25679.jpg",
            "brand": "ouie",
        },
        {
            "url": "https://www.wconcept.co.kr/Product/308589275",
            "ok": True,
            "name": "Soft Drape T-shirt_3Color",
            "price": 88000,
            "image": "https://product-image.wconcept.co.kr/productimg/image/img9/75/308589275_EP72624.jpg",
            "brand": "FLOWOOM",
        },
        {
            "url": "https://www.wconcept.co.kr/Product/308629259",
            "ok": True,
            "name": "[단독][SET] Wrap Detail T-Shirt & V-Neck Sleeveless Top",
            "price": 86700,
            "image": "https://product-image.wconcept.co.kr/productimg/image/img9/59/308629259_VW44687.jpg",
            "brand": "THE RYE",
        },
    ]
    SRC.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")

    blocks = []
    complete = 0
    missing = []
    for mall in ORDER:
        items = [i for i in data.get(mall, []) if good(i)][:3]
        if len(items) >= 3:
            complete += 1
        else:
            missing.append(f"{mall}:{len(items)}")
        products = []
        for item in items:
            name = clean_name(item["name"])
            og = item.get("ogTitle") or ""
            if "무신사" in og and " - 사이즈" in og:
                name = og.split(" - 사이즈")[0]
                name = re.sub(r"^[^)]+\)\s*", "", name).strip() or name
            brand = item.get("brand")
            brand_line = f",\n          brand: {dart_str(brand)}," if brand else ","
            products.append(
                f"""    LiveCompareProduct(
      {dart_str(item["url"])},
      live: LiveCompareExpected(
        name: {dart_str(name)},
        price: {int(item["price"])},
        image:
            {dart_str(item["image"])}{brand_line}
      ),
    )"""
            )
        inner = ",\n".join(products) + ("," if products else "")
        blocks.append(f"  LiveCompareMall({dart_str(mall)}, [\n{inner}\n  ])")

    dest = f"""class LiveCompareProduct {{
  const LiveCompareProduct(this.url, {{this.live}});

  final String url;
  final LiveCompareExpected? live;
}}

class LiveCompareExpected {{
  const LiveCompareExpected({{
    required this.name,
    required this.price,
    required this.image,
    this.brand,
  }});

  final String name;
  final int price;
  final String image;
  final String? brand;
}}

class LiveCompareMall {{
  const LiveCompareMall(this.mall, this.products);

  final String mall;
  final List<LiveCompareProduct> products;
}}

/// 2026-08-18 새로 연 상품 페이지에서 확인한 판매가(첫구매·카드 쿠폰 제외).
/// 엔진 상품명에는 브랜드가 붙을 수 있으므로 live.name 은 화면에 보이는 상품명이다.
const liveCompareMalls = <LiveCompareMall>[
{',\n'.join(blocks)},
];
"""
    DEST.write_text(dest, encoding="utf-8")
    print(f"wrote {DEST}")
    print(f"complete={complete}/50 missing={missing}")


if __name__ == "__main__":
    main()
