"""
태그에서 읽은 코드(품번·바코드)를 다루는 순수 함수들. 네트워크·AI 호출 없음 — tag_identify.py가 쓴다.

- 바코드 검증: EAN/UPC 마지막 자리는 앞자리로 계산되는 검증 숫자라서, AI가 숫자를 잘못 읽으면 대부분
  계산이 안 맞는다. 안 맞는 바코드는 버린다("틀린 값보다 빈 값이 안전하다").
- 품번 나누기: 태그 품번에는 색상 코드가 붙어 있는 경우가 많다(나이키 DV1234-100, 유니클로
  485454-26). 상품 페이지에는 색상을 뺀 기본 번호만 적혀 있는 경우가 흔해서, 기본 번호로도 확인한다.
- 페이지 확인: 짧은 숫자 품번은 페이지의 다른 숫자(가격·상품번호)와 우연히 겹칠 수 있어서, 기본
  번호·보조 코드는 앞뒤가 다른 글자로 끊긴 "한 덩어리"로 있을 때만 인정한다.
"""
from __future__ import annotations

import re
import urllib.parse

_NON_ALNUM_RE = re.compile(r"[^0-9a-z가-힣]+")
_SEPARATOR_RE = re.compile(r"[\s\-_/.]+")

MIN_CODE_LEN = 5  # 이보다 짧은 품번은 우연히 겹칠 수 있어 근거로 쓰지 않는다
MAX_COLOR_SUFFIX_LEN = 3  # 품번 끝의 이 길이 이하 덩어리는 색상 코드로 본다(나이키 3자리, 유니클로 2자리)
GTIN_LENGTHS = (8, 12, 13, 14)  # EAN-8, UPC-A, EAN-13, GTIN-14


def normalize_code(s: str | None) -> str:
    """'DV1234-100', 'dv1234 100', 'DV1234_100' → 'dv1234100'."""
    return _NON_ALNUM_RE.sub("", (s or "").lower())


# ── 바코드 ──────────────────────────────────────────────────

def is_valid_gtin(raw: str | None) -> bool:
    """EAN-8 / UPC-A / EAN-13 / GTIN-14 검증 숫자(mod 10)가 맞는지.

    오른쪽 끝(검증 숫자 바로 앞)부터 3, 1, 3, 1… 가중치를 곱해 더하고, 10의 배수가 되도록 하는 숫자가
    검증 숫자다. 자리 수가 위 네 가지가 아니거나 숫자 아닌 글자가 섞이면 False."""
    digits = re.sub(r"[\s\-]", "", raw or "")
    if not digits.isdigit() or len(digits) not in GTIN_LENGTHS:
        return False
    body, check = digits[:-1], int(digits[-1])
    total = sum(int(d) * (3 if i % 2 == 0 else 1) for i, d in enumerate(reversed(body)))
    return (10 - total % 10) % 10 == check


def clean_barcode(raw: str | None) -> tuple[str | None, str | None]:
    """(쓸 바코드, 버린 원본). 검증 숫자가 맞으면 숫자만 남긴 값을, 안 맞으면 (None, 원본)을 준다."""
    if not raw or not str(raw).strip():
        return None, None
    digits = re.sub(r"[\s\-]", "", str(raw))
    return (digits, None) if is_valid_gtin(digits) else (None, str(raw))


# ── 품번 ────────────────────────────────────────────────────

def base_code(code: str | None) -> str | None:
    """색상 코드를 뗀 기본 번호(정규화된 값). 'DV1234-100' → 'dv1234', '485454-26' → '485454'.

    구분자(-, _, /, 공백, .)로 나뉘고 마지막 덩어리가 MAX_COLOR_SUFFIX_LEN 이하일 때만 뗀다.
    구분자가 없으면 어디까지가 색상인지 알 수 없으므로 None(예: '801474YB2FT1000')."""
    parts = [p for p in _SEPARATOR_RE.split((code or "").strip()) if p]
    if len(parts) < 2 or len(parts[-1]) > MAX_COLOR_SUFFIX_LEN:
        return None
    base = normalize_code("".join(parts[:-1]))
    return base if len(base) >= MIN_CODE_LEN else None


def color_suffix(code: str | None) -> str | None:
    """base_code()가 떼어낸 색상 코드. 'DV1234-100' → '100'. 없으면 None."""
    if base_code(code) is None:
        return None
    return normalize_code(_SEPARATOR_RE.split(code.strip())[-1]) or None


def _standalone_re(norm: str) -> re.Pattern:
    """norm이 앞뒤가 끊긴 한 덩어리로 있을 때만 맞는 정규식(대소문자 무시).

    숫자로 시작하면 바로 앞에 숫자만 없으면 된다 — 유니클로 URL의 'E486612-000'처럼 앞에 영문 접두어가
    붙는 경우를 받기 위해서다. 영문으로 시작하면 앞에 영문·숫자가 없어야 한다. 끝도 같은 규칙."""
    before = r"(?<![0-9])" if norm[0].isdigit() else r"(?<![0-9a-z])"
    after = r"(?![0-9])" if norm[-1].isdigit() else r"(?![0-9a-z])"
    return re.compile(before + re.escape(norm) + after, re.IGNORECASE)


def _standalone_in(norm: str, *texts: str) -> bool:
    pattern = _standalone_re(norm)
    return any(pattern.search(t) for t in texts if t)


def code_evidence(tag: dict, raw_text: str, final_url: str) -> str | None:
    """페이지에 태그의 코드가 있는지. 강한 근거부터:

    'product_code'      — 태그 품번 전체(색상 포함)가 페이지/URL에 있음
    'barcode'           — 검증된 바코드가 있음
    'product_code_base' — 색상을 뗀 기본 번호, 또는 태그에 같이 적힌 다른 코드가 한 덩어리로 있음
    None                — 코드로는 확인 못 함

    품번 전체는 구분자를 무시하고(정규화한 뒤) 찾는다 — 'DV1234-100'과 'dv1234 100'을 같게 본다.
    기본 번호·보조 코드는 짧아서 우연히 겹치기 쉬우므로 한 덩어리일 때만 인정한다."""
    url_text = urllib.parse.unquote(final_url or "")
    haystack = normalize_code(raw_text) + " " + normalize_code(url_text)

    code = normalize_code(tag.get("product_code"))
    if len(code) >= MIN_CODE_LEN and code in haystack:
        return "product_code"

    barcode = normalize_code(tag.get("barcode"))
    if len(barcode) >= min(GTIN_LENGTHS) and barcode in haystack:
        return "barcode"

    weaker = [base_code(tag.get("product_code"))]
    weaker += [normalize_code(c) for c in tag.get("other_codes") or []]
    if any(len(c or "") >= MIN_CODE_LEN and _standalone_in(c, raw_text, url_text) for c in weaker):
        return "product_code_base"
    return None


def has_code(tag: dict) -> bool:
    """확인에 쓸 만한 코드가 하나라도 있는지(품번·바코드·보조 코드)."""
    candidates = [tag.get("product_code"), tag.get("barcode"), *(tag.get("other_codes") or [])]
    return any(len(normalize_code(c)) >= MIN_CODE_LEN for c in candidates)
