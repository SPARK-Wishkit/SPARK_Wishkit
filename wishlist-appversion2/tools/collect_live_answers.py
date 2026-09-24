#!/usr/bin/env python3
"""Open mall pages and collect 3 live answer keys (name, sale price, image).

Live price is the on-page sale price, not first-purchase / card / app coupons.
This does not use the Flutter extract JS.
"""

from __future__ import annotations

import json
import re
import ssl
import time
import urllib.error
import urllib.request
from html import unescape
from pathlib import Path
from urllib.parse import urljoin, urlparse

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
)
CTX = ssl.create_default_context()
OUT = Path(__file__).resolve().parents[1] / "audit-logs" / "live-answers-2026-08-18.json"

SITE_TITLE_HINTS = (
    "공식",
    "스토어",
    "store",
    "online",
    "쇼핑몰",
    "w concept",
    "[w concept]",
    "muji",
    "무인양품",
)

OLD_URLS = {
    "https://www.11st.co.kr/products/5932454122",
    "https://www.musinsa.com/products/6558705",
    "https://www.musinsa.com/products/3348384",
    "https://www.musinsa.com/products/6152461",
    "https://www.wconcept.co.kr/Product/307615241",
    "https://www.wconcept.co.kr/Product/305573391",
    "https://www.wconcept.co.kr/Product/305914779",
    "https://www.29cm.co.kr/products/4058252",
    "https://www.29cm.co.kr/products/1577769",
    "https://www.29cm.co.kr/products/3503849",
    "https://www.fila.co.kr/products/1100fs262rs11m001490",
    "https://www.hago.kr/goods/detail/750307",
    "https://www.lookpin.co.kr/products/3083865",
    "https://www.lookpin.co.kr/products/2724519",
    "https://topten10.goodwearmall.com/product/MSG2UL2205NVP/detail",
    "https://mujikorea.co.kr/products/view/1005531",
    "https://mujikorea.co.kr/products/view/1005528",
    "https://www.hmall.com/md/pda/itemPtc?slitmCd=2060464676",
    "https://www.lotteon.com/p/product/LO2724337622",
    "https://mixxo.com/product/detail.html?product_no=12455",
    "https://mixxo.com/product/detail.html?product_no=9813",
    "https://mixxo.com/product/detail.html?product_no=12454",
    "https://dailyjou.com/product/detail.html?product_no=22794",
    "https://dailyjou.com/product/detail.html?product_no=23688",
    "https://dailyjou.com/product/detail.html?product_no=23726",
    "https://leekorea.co.kr/product/detail.html?product_no=14252",
    "https://filluminate.com/product/detail.html?product_no=11735",
    "https://filluminate.com/product/detail.html?product_no=11734",
    "https://filluminate.com/product/detail.html?product_no=11736",
    "https://urbanstoff.com/product/detail.html?product_no=507",
    "https://urbanstoff.com/product/detail.html?product_no=506",
    "https://urbanstoff.com/product/detail.html?product_no=505",
    "https://not4u.kr/product/detail.html?product_no=261",
    "https://not4u.kr/product/detail.html?product_no=262",
    "https://insilence.co.kr/product/detail.html?product_no=7481",
    "https://insilence.co.kr/product/detail.html?product_no=7303",
    "https://insilence.co.kr/product/detail.html?product_no=7483",
    "https://fabregat.kr/product/detail.html?product_no=1038",
    "https://hotping.co.kr/product/detail.html?product_no=29570",
    "https://hotping.co.kr/product/detail.html?product_no=36728",
    "https://hotping.co.kr/product/detail.html?product_no=37586",
    "https://www.uniqlo.com/kr/ko/products/E486612-000/00?colorDisplayCode=65&sizeDisplayCode=005",
    "https://www.ssg.com/item/itemView.ssg?itemId=1000571660298",
    "https://www.ssg.com/item/itemView.ssg?itemId=1000277700787",
    "https://hi.thehyundai.com/product/40B1406274?sectId=1031",
    "https://mobile.a-bly.com/goods/74156532",
    "https://zigzag.kr/catalog/products/144255443",
    "https://kream.co.kr/products/1012767",
    "https://kream.co.kr/products/748804",
    "https://www.guesskorea.com/product/detail.html?product_no=45471",
    "https://www.guesskorea.com/product/detail.html?product_no=45470",
    "https://www.guesskorea.com/product/detail.html?product_no=45472",
    "https://www.vans.co.kr/PRODUCT/VN000D6WBOM",
    "https://www.vans.co.kr/PRODUCT/VN000D9NBLK",
    "https://www.vans.co.kr/PRODUCT/VN000VB2HO8",
    "https://covernat.co.kr/product/detail.html?product_no=5996",
    "https://covernat.co.kr/product/detail.html?product_no=18025",
    "https://covernat.co.kr/product/detail.html?product_no=8581",
    "https://code-graphy.com/product/detail.html?product_no=6388",
    "https://whoau.com/product/detail.html?product_no=4852",
    "https://whoau.com/product/detail.html?product_no=4847",
    "https://whoau.com/product/detail.html?product_no=4853",
    "https://www.aritzia.com/intl/en/product/airbutter%E2%84%A2-repose-longsleeve/133550.html?color=35023",
    "https://www.aritzia.com/intl/en/product/technique-dress/124784.html",
    "https://noirer.com/product/detail.html?product_no=2141",
    "https://noirer.com/product/detail.html?product_no=2140",
    "https://noirer.com/product/detail.html?product_no=2142",
    "https://liphop.com/product/detail.html?product_no=17849",
    "https://mahagrid.com/product/detail.html?product_no=3854",
    "https://vivastudio.co.kr/product/detail.html?product_no=5485",
    "https://amomento.co/product/button-neck-knit-2colors/1642/",
    "https://amomento.co/product/detail.html?product_no=1643",
    "https://www.anderssonbell.com/product/detail.html?product_no=10605",
    "https://yaleapparel.co.kr/product/detail.html?product_no=18179",
    "https://yaleapparel.co.kr/product/detail.html?product_no=18180",
    "https://yaleapparel.co.kr/product/detail.html?product_no=18178",
    "https://withyoon.com/product/detail.html?product_no=19342",
    "https://withyoon.com/product/detail.html?product_no=19341",
    "https://withyoon.com/product/detail.html?product_no=19343",
    "https://www.fashionplus.co.kr/goods/detail/418168398",
    "https://frombeginning.co.kr/product/detail.html?product_no=22025",
    "https://frombeginning.co.kr/product/detail.html?product_no=22026",
    "https://www.nike.com/kr/t/나이키-에어-포스-1-07-남성-신발-qdjlTENZ/IH1698-100",
    "https://www.oliveyoung.co.kr/store/goods/getGoodsDetail.do?goodsNo=A000000260600",
    "https://www.oliveyoung.co.kr/store/goods/getGoodsDetail.do?goodsNo=A000000210792",
    "https://www.oliveyoung.co.kr/store/goods/getGoodsDetail.do?goodsNo=A000000171427",
    "https://web.queenit.kr/product/421b849e05731238976b9f01d96c7e31",
    "https://www.brandi.co.kr/products/158997563",
    "https://display.cjonstyle.com/p/item/2078847097",
    "https://4910.kr/desktop/goods/64333542",
    "https://www.ssfshop.com/GOOD-ON/GPCX25041604994/good",
    "https://www.elandmall.co.kr/i/item?itemNo=2607498077&lowerVendNo=LV25019098",
}


def fetch(url: str, timeout: int = 20) -> tuple[int | str, str]:
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
            "Accept-Language": "ko-KR,ko;q=0.9,en;q=0.8",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=CTX) as res:
            raw = res.read()
            charset = res.headers.get_content_charset() or "utf-8"
            return res.status, raw.decode(charset, errors="replace")
    except urllib.error.HTTPError as err:
        raw = err.read() if err.fp else b""
        return err.code, raw.decode("utf-8", errors="replace")
    except Exception as err:  # noqa: BLE001
        return "ERR", str(err)


def meta(html: str, *keys: str) -> str | None:
    for key in keys:
        patterns = [
            rf'<meta[^>]+(?:property|name|itemprop)=["\']{re.escape(key)}["\'][^>]+content=["\']([^"\']+)["\']',
            rf'<meta[^>]+content=["\']([^"\']+)["\'][^>]+(?:property|name|itemprop)=["\']{re.escape(key)}["\']',
        ]
        for pat in patterns:
            match = re.search(pat, html, re.I)
            if match:
                value = unescape(match.group(1)).strip()
                if value:
                    return value
    return None


def to_price(raw: str | None) -> int | None:
    if not raw:
        return None
    digits = re.sub(r"[^\d]", "", raw)
    if not digits:
        return None
    value = int(digits)
    if 100 <= value <= 50_000_000:
        return value
    return None


def looks_like_site_title(name: str | None) -> bool:
    if not name:
        return True
    lowered = name.lower()
    if len(name) < 3:
        return True
    return any(hint in lowered for hint in SITE_TITLE_HINTS)


def first_match(html: str, *patterns: str) -> str | None:
    for pat in patterns:
        match = re.search(pat, html, re.I | re.S)
        if match:
            value = unescape(re.sub(r"<[^>]+>", " ", match.group(1)))
            value = re.sub(r"\s+", " ", value).strip()
            if value:
                return value
    return None


def json_ld_products(html: str) -> list[dict]:
    out: list[dict] = []
    for match in re.finditer(
        r'<script[^>]+type=["\']application/ld\+json["\'][^>]*>(.*?)</script>',
        html,
        re.I | re.S,
    ):
        raw = match.group(1).strip()
        try:
            data = json.loads(raw)
        except json.JSONDecodeError:
            continue
        stack = data if isinstance(data, list) else [data]
        while stack:
            item = stack.pop()
            if isinstance(item, list):
                stack.extend(item)
                continue
            if not isinstance(item, dict):
                continue
            if "@graph" in item and isinstance(item["@graph"], list):
                stack.extend(item["@graph"])
            types = item.get("@type")
            type_list = types if isinstance(types, list) else [types]
            if any(str(t).lower() == "product" for t in type_list):
                out.append(item)
    return out


def _json_string(raw: str) -> str | None:
    try:
        value = json.loads(f'"{raw}"')
    except json.JSONDecodeError:
        value = unescape(raw)
    value = re.sub(r"<[^>]+>", " ", value)
    value = re.sub(r"\s+", " ", value).strip()
    if not value or value.startswith("@") or re.fullmatch(r"[¥￥*$·]+", value):
        return None
    return value


def pick_name(html: str, mall: str) -> str | None:
    if mall == "무신사":
        goods = re.search(r'"goodsNm"\s*:\s*"((?:\\.|[^"\\])*)"', html)
        if goods:
            parsed = _json_string(goods.group(1))
            if parsed:
                return parsed
    if mall == "29CM":
        item = re.search(r'"itemName"\s*:\s*"((?:\\.|[^"\\])*)"', html)
        if item:
            parsed = _json_string(item.group(1))
            if parsed:
                return parsed
    ld = json_ld_products(html)
    for product in ld:
        name = product.get("name")
        parsed = _json_string(name) if isinstance(name, str) else None
        if parsed and not looks_like_site_title(parsed):
            return parsed
    candidates = [
        first_match(html, r'id=["\']span_product_name["\'][^>]*>(.*?)</'),
        first_match(html, r'class=["\'][^"\']*heading[^"\']*["\'][^>]*>(.*?)</h[12]'),
        first_match(html, r"<h1[^>]*>(.*?)</h1>"),
        first_match(html, r"<h2[^>]*>(.*?)</h2>"),
        meta(html, "og:title", "twitter:title"),
    ]
    cleaned = []
    for name in candidates:
        parsed = _json_string(name) if name else None
        if parsed:
            cleaned.append(parsed)
    for name in cleaned:
        if not looks_like_site_title(name):
            return name
    return cleaned[0] if cleaned else None


def pick_price(html: str, mall: str) -> int | None:
    if mall == "무신사":
        match = re.search(
            r'"goodsPrice"\s*:\s*\{[^}]*?"salePrice"\s*:\s*(\d+)', html
        )
        if match:
            return int(match.group(1))
    if mall == "29CM":
        match = re.search(r'"sellPrice"\s*:\s*(\d+)\s*,\s*"consumerPrice"', html)
        if match:
            return int(match.group(1))
    if mall == "하고":
        match = re.search(r"\bsellPrice\s*:\s*(\d+)", html)
        if match:
            return int(match.group(1))
    if mall == "W컨셉":
        found = [
            to_price(match.group(1))
            for match in re.finditer(r"([1-9]\d{0,2}(?:,\d{3})+)\s*원", html)
        ]
        found = [value for value in found if value]
        if found:
            return max(set(found), key=found.count)

    displayed = to_price(
        first_match(
            html,
            r'id=["\']span_product_price_text["\'][^>]*>(.*?)</',
            r'id=["\']span_product_price_custom["\'][^>]*>(.*?)</',
        )
    )
    price_amount = to_price(meta(html, "product:price:amount", "og:price:amount"))
    sale_amount = to_price(
        meta(html, "product:sale_price:amount", "og:sale_price:amount")
    )
    ld_prices: list[int] = []
    for product in json_ld_products(html):
        offers = product.get("offers")
        offer_list = offers if isinstance(offers, list) else [offers] if offers else []
        for offer in offer_list:
            if isinstance(offer, dict):
                value = to_price(str(offer.get("price") or ""))
                if value:
                    ld_prices.append(value)
    # Displayed sale, not member-only sale_price and not coupon.
    for value in (displayed, price_amount, ld_prices[0] if ld_prices else None):
        if value:
            return value
    return sale_amount


def pick_image(html: str, base: str) -> str | None:
    big = first_match(
        html,
        r'(https?://[^"\']+/web/product/big/[^"\']+)',
        r'(//[^"\']+/web/product/big/[^"\']+)',
    )
    if big:
        if big.startswith("//"):
            big = "https:" + big
        if "seo_og" not in big and "og_tag" not in big:
            return big.split("?")[0]
    image = meta(html, "og:image", "twitter:image")
    if image:
        if image.startswith("//"):
            image = "https:" + image
        elif image.startswith("/"):
            image = urljoin(base, image)
        if "seo_og" in image or "og_tag_lookpin" in image:
            image = None
    if image:
        return image.split("?")[0]
    for product in json_ld_products(html):
        raw = product.get("image")
        if isinstance(raw, list) and raw:
            raw = raw[0]
        if isinstance(raw, dict):
            raw = raw.get("url")
        if isinstance(raw, str) and raw.startswith("http"):
            return raw.split("?")[0]
    return None


def extract_product(url: str, mall: str) -> dict:
    status, html = fetch(url)
    if status != 200 or len(html) < 400:
        return {
            "url": url,
            "ok": False,
            "status": status,
            "error": html[:200] if isinstance(status, str) else f"http {status}",
        }
    name = pick_name(html, mall)
    price = pick_price(html, mall)
    image = pick_image(html, url)
    if price == 99999:
        price = None
    if name:
        name = _json_string(name) or None
    if name and re.search(r"^(reviews?|md'?s pick|관련상품|best)$", name, re.I):
        name = None
    if price and price >= 1_000_000 and mall in {
        "코드그라피",
        "탑텐",
        "후아유",
        "미쏘",
        "핫핑",
        "위드윤",
        "데일리쥬",
    }:
        price = None
    return {
        "url": url,
        "ok": bool(name and price and image),
        "status": status,
        "name": name,
        "price": price,
        "image": image,
        "ogTitle": meta(html, "og:title"),
        "htmlBytes": len(html),
    }


def find_urls(html: str, patterns: list[str], limit: int = 30) -> list[str]:
    found: list[str] = []
    seen: set[str] = set()
    for pat in patterns:
        for match in re.finditer(pat, html, re.I):
            url = unescape(match.group(1) if match.lastindex else match.group(0))
            if url.startswith("//"):
                url = "https:" + url
            if url in seen:
                continue
            seen.add(url)
            found.append(url)
            if len(found) >= limit:
                return found
    return found


_DATE_FOLDER = re.compile(r"^20(2[0-6])(0[1-9]|1[0-2])$")
_CAFE24_SKIP_SLUG = (
    "list",
    "search",
    "detail",
    "big",
    "medium",
    "tiny",
    "small",
    "extra",
    "image",
)


def _usable_cafe24_id(pid: str) -> bool:
    if not pid.isdigit():
        return False
    if pid in {"0", "1"} or int(pid) < 10:
        return False
    if _DATE_FOLDER.match(pid):
        return False
    return True


def cafe24_ids(html: str) -> list[str]:
    ids: list[str] = []
    seen: set[str] = set()

    def add(pid: str) -> None:
        if pid in seen or not _usable_cafe24_id(pid):
            return
        seen.add(pid)
        ids.append(pid)

    for match in re.finditer(r"product_no=(\d+)", html):
        add(match.group(1))
    for match in re.finditer(
        r"/product/([^/\"'?]+)/(\d{2,7})(?:/|\"|'|\?)", html
    ):
        slug, pid = match.group(1), match.group(2)
        if slug.lower() in _CAFE24_SKIP_SLUG:
            continue
        add(pid)
    for match in re.finditer(
        r"data-(?:product-no|product_no)=[\"'](\d+)[\"']", html, re.I
    ):
        add(match.group(1))
    return ids


CAFE24 = [
    ("미쏘", "https://mixxo.com", "https://mixxo.com/product/detail.html?product_no=12455"),
    ("데일리쥬", "https://dailyjou.com", "https://dailyjou.com/product/detail.html?product_no=22794"),
    ("리", "https://leekorea.co.kr", "https://leekorea.co.kr/product/detail.html?product_no=14252"),
    ("필루미네이트", "https://filluminate.com", "https://filluminate.com/product/detail.html?product_no=11735"),
    ("어반스터프", "https://urbanstoff.com", "https://urbanstoff.com/product/detail.html?product_no=507"),
    ("낫포유", "https://not4u.kr", "https://not4u.kr/product/detail.html?product_no=261"),
    ("인사일런스", "https://insilence.co.kr", "https://insilence.co.kr/product/detail.html?product_no=7481"),
    ("파브레가", "https://fabregat.kr", "https://fabregat.kr/product/detail.html?product_no=1038"),
    ("핫핑", "https://hotping.co.kr", "https://hotping.co.kr/product/detail.html?product_no=29570"),
    ("게스", "https://www.guesskorea.com", "https://www.guesskorea.com/product/detail.html?product_no=45471"),
    ("커버낫", "https://covernat.co.kr", "https://covernat.co.kr/product/detail.html?product_no=5996"),
    ("코드그라피", "https://code-graphy.com", "https://code-graphy.com/product/detail.html?product_no=6388"),
    ("후아유", "https://whoau.com", "https://whoau.com/product/detail.html?product_no=4852"),
    ("노이아고", "https://noirer.com", "https://noirer.com/product/detail.html?product_no=2141"),
    ("립합", "https://liphop.com", "https://liphop.com/product/detail.html?product_no=17849"),
    ("마하그리드", "https://mahagrid.com", "https://mahagrid.com/product/detail.html?product_no=3854"),
    ("비바스튜디오", "https://vivastudio.co.kr", "https://vivastudio.co.kr/product/detail.html?product_no=5485"),
    ("아모멘토", "https://amomento.co", "https://amomento.co/product/detail.html?product_no=1642"),
    ("앤더슨벨", "https://www.anderssonbell.com", "https://www.anderssonbell.com/product/detail.html?product_no=10605"),
    ("예일", "https://yaleapparel.co.kr", "https://yaleapparel.co.kr/product/detail.html?product_no=18179"),
    ("위드윤", "https://withyoon.com", "https://withyoon.com/product/detail.html?product_no=19342"),
    ("프롬비기닝", "https://frombeginning.co.kr", "https://frombeginning.co.kr/product/detail.html?product_no=22025"),
]


OTHER = [
    (
        "11번가",
        [
            "https://www.11st.co.kr/browsing/BestSeller.tmall?method=getBestSellerMain",
            "https://www.11st.co.kr/",
        ],
        [r"https?://www\.11st\.co\.kr/products/\d+"],
    ),
    (
        "무신사",
        [
            "https://www.musinsa.com/category/001",
            "https://www.musinsa.com/main/musinsa/recommend",
        ],
        [r"https?://www\.musinsa\.com/products/\d+", r"/products/(\d+)"],
    ),
    (
        "W컨셉",
        ["https://www.wconcept.co.kr/Women", "https://www.wconcept.co.kr/"],
        [r"https?://www\.wconcept\.co\.kr/Product/\d+"],
    ),
    (
        "29CM",
        ["https://www.29cm.co.kr/shop/best-items", "https://shop.29cm.co.kr/best-items"],
        [r"https?://(?:www\.)?29cm\.co\.kr/products/\d+"],
    ),
    (
        "FILA",
        ["https://www.fila.co.kr/category/clothes", "https://www.fila.co.kr/"],
        [r"https?://www\.fila\.co\.kr/products/[A-Za-z0-9]+"],
    ),
    (
        "하고",
        ["https://www.hago.kr/", "https://www.hago.kr/goods/list"],
        [r"https?://www\.hago\.kr/goods/detail/\d+"],
    ),
    (
        "룩핀",
        ["https://www.lookpin.co.kr/", "https://www.lookpin.co.kr/best"],
        [r"https?://www\.lookpin\.co\.kr/products/\d+"],
    ),
    (
        "탑텐",
        ["https://topten10.goodwearmall.com/", "https://topten10.goodwearmall.com/product/list"],
        [r"https?://topten10\.goodwearmall\.com/product/[A-Za-z0-9]+/detail"],
    ),
    (
        "무인양품",
        ["https://www.mujikorea.net/", "https://mujikorea.co.kr/"],
        [r"https?://mujikorea\.co\.kr/products/view/\d+", r"https?://www\.mujikorea\.net/goods/detail\?goodsNo=\d+"],
    ),
    (
        "현대Hmall",
        ["https://www.hmall.com/", "https://www.hmall.com/p/dpa/searchSectItem.do?sectId=2737071"],
        [r"slitmCd=(\d+)", r"https?://www\.hmall\.com/p/pda/itemPtc\.do\?slitmCd=\d+"],
    ),
    (
        "롯데온",
        ["https://www.lotteon.com/", "https://www.lotteon.com/display/shop/seltDpShop?shopNo=1"],
        [r"https?://www\.lotteon\.com/p/product/[A-Z0-9]+"],
    ),
    (
        "유니클로",
        ["https://www.uniqlo.com/kr/ko/feature/new/lifewear", "https://www.uniqlo.com/kr/ko/"],
        [r"https?://www\.uniqlo\.com/kr/ko/products/E\d+-[0-9]+/00"],
    ),
    (
        "SSG",
        ["https://www.ssg.com/", "https://www.ssg.com/page/best.ssg"],
        [r"itemId=(\d+)", r"https?://www\.ssg\.com/item/itemView\.ssg\?itemId=\d+"],
    ),
    (
        "더현대Hi",
        ["https://hi.thehyundai.com/", "https://hi.thehyundai.com/front/dpa/best.thd"],
        [r"https?://hi\.thehyundai\.com/product/[A-Z0-9]+"],
    ),
    (
        "에이블리",
        ["https://m.a-bly.com/", "https://www.a-bly.com/"],
        [r"https?://(?:m|mobile|www)\.a-bly\.com/goods/\d+"],
    ),
    (
        "지그재그",
        ["https://zigzag.kr/", "https://zigzag.kr/categories/1"],
        [r"https?://zigzag\.kr/catalog/products/\d+"],
    ),
    (
        "KREAM",
        ["https://kream.co.kr/", "https://kream.co.kr/search?keyword=nike"],
        [r"https?://kream\.co\.kr/products/\d+"],
    ),
    (
        "반스",
        ["https://www.vans.co.kr/SHOP", "https://www.vans.co.kr/"],
        [r"https?://www\.vans\.co\.kr/PRODUCT/[A-Z0-9]+"],
    ),
    (
        "Aritzia",
        ["https://www.aritzia.com/intl/en/clothing", "https://www.aritzia.com/intl/en/"],
        [r"https?://www\.aritzia\.com/intl/en/product/[^\"'\s]+/\d+\.html"],
    ),
    (
        "패션플러스",
        ["https://www.fashionplus.co.kr/", "https://www.fashionplus.co.kr/display/best"],
        [r"https?://www\.fashionplus\.co\.kr/goods/detail/\d+"],
    ),
    (
        "나이키",
        ["https://www.nike.com/kr/w/new-3n82y", "https://www.nike.com/kr/w/mens-shoes-nik1zy7ok"],
        [r"https?://www\.nike\.com/kr/t/[^\"'\s]+/[A-Z0-9\-]+"],
    ),
    (
        "올리브영",
        [
            "https://www.oliveyoung.co.kr/store/main/getBestList.do",
            "https://www.oliveyoung.co.kr/store/main/main.do",
        ],
        [r"goodsNo=(A\d+)", r"getGoodsDetail\.do\?goodsNo=A\d+"],
    ),
    (
        "퀸잇",
        ["https://web.queenit.kr/", "https://web.queenit.kr/exhibition"],
        [r"https?://web\.queenit\.kr/product/[a-f0-9]+"],
    ),
    (
        "브랜디",
        ["https://www.brandi.co.kr/", "https://www.brandi.co.kr/best"],
        [r"https?://www\.brandi\.co\.kr/products/\d+"],
    ),
    (
        "CJ온스타일",
        ["https://display.cjonstyle.com/", "https://display.cjonstyle.com/p/home"],
        [r"https?://display\.cjonstyle\.com/p/item/\d+"],
    ),
    (
        "4910",
        ["https://4910.kr/", "https://4910.kr/desktop/goods"],
        [r"https?://4910\.kr/desktop/goods/\d+"],
    ),
    (
        "SSF샵",
        ["https://www.ssfshop.com/", "https://www.ssfshop.com/special/best"],
        [r"https?://www\.ssfshop\.com/[^\"'\s]+/GP[A-Z0-9]+/good"],
    ),
    (
        "이랜드몰",
        ["https://www.elandmall.co.kr/", "https://www.elandmall.co.kr/dispctg/initBest100.action"],
        [r"itemNo=(\d+)", r"https?://www\.elandmall\.co\.kr/i/item\?itemNo=\d+"],
    ),
]


def normalize_found(mall: str, raw: str) -> str | None:
    if raw.startswith("http"):
        return raw.split("&amp;")[0]
    if mall == "무신사" and raw.isdigit():
        return f"https://www.musinsa.com/products/{raw}"
    if mall == "현대Hmall" and raw.isdigit():
        return f"https://www.hmall.com/md/pda/itemPtc?slitmCd={raw}"
    if mall == "SSG" and raw.isdigit():
        return f"https://www.ssg.com/item/itemView.ssg?itemId={raw}"
    if mall == "올리브영" and raw.startswith("A"):
        return f"https://www.oliveyoung.co.kr/store/goods/getGoodsDetail.do?goodsNo={raw}"
    if mall == "이랜드몰" and raw.isdigit():
        return f"https://www.elandmall.co.kr/i/item?itemNo={raw}"
    return None


def collect_cafe24(mall: str, origin: str, seed: str) -> list[dict]:
    pages = [
        seed,
        origin + "/",
        origin + "/product/list.html?cate_no=24",
        origin + "/product/list.html?cate_no=42",
        origin + "/product/list.html?cate_no=48",
        origin + "/product/search.html?keyword=%ED%8B%B0%EC%85%94%EC%B8%A0",
    ]
    ids: list[str] = []
    seen = set()
    for page in pages:
        _, html = fetch(page)
        for pid in cafe24_ids(html):
            if pid in seen:
                continue
            seen.add(pid)
            ids.append(pid)
        time.sleep(0.15)
    products = []
    for pid in ids:
        url = f"{origin}/product/detail.html?product_no={pid}"
        if url in OLD_URLS:
            continue
        item = extract_product(url, mall)
        if item.get("ok"):
            products.append(item)
        if len(products) >= 3:
            break
        time.sleep(0.25)
    return products


def collect_other(mall: str, lists: list[str], patterns: list[str]) -> list[dict]:
    urls: list[str] = []
    seen = set()
    for page in lists:
        _, html = fetch(page)
        for raw in find_urls(html, patterns, limit=40):
            url = normalize_found(mall, raw) or (raw if raw.startswith("http") else None)
            if not url or url in seen or url in OLD_URLS:
                continue
            seen.add(url)
            urls.append(url)
        time.sleep(0.2)
    products = []
    for url in urls:
        item = extract_product(url, mall)
        if item.get("ok"):
            products.append(item)
        if len(products) >= 3:
            break
        time.sleep(0.25)
    return products


def main() -> None:
    import sys

    args = set(sys.argv[1:])
    cafe24_only = "--cafe24" in args
    only = {a for a in args if not a.startswith("--")}
    previous = {}
    if OUT.exists():
        previous = json.loads(OUT.read_text(encoding="utf-8"))
    results: dict[str, list[dict]] = dict(previous)
    for mall, origin, seed in CAFE24:
        if only and mall not in only:
            continue
        print(f"COLLECT {mall}", flush=True)
        results[mall] = collect_cafe24(mall, origin, seed)
        print(f"  got {len(results[mall])}", flush=True)
    for mall, lists, patterns in OTHER:
        if cafe24_only:
            continue
        if only and mall not in only:
            continue
        if not only and mall in results and len(results[mall]) >= 3:
            print(f"SKIP {mall} already {len(results[mall])}", flush=True)
            continue
        print(f"COLLECT {mall}", flush=True)
        results[mall] = collect_other(mall, lists, patterns)
        print(f"  got {len(results[mall])}", flush=True)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    complete = sum(1 for items in results.values() if len(items) >= 3)
    print(f"WROTE {OUT} complete_malls={complete}/{len(results)}")


if __name__ == "__main__":
    main()
