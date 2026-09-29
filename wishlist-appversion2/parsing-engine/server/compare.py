"""
사실검증(그라운딩) + 골든셋 비교 로직.

`engine-ai-prototype/compare.py`를 그대로 포팅했다(2026-09-18 재현성 실측으로 다듬은
최종 버전 — 19절 name_match 포함관계 규칙, 26-2절 계산값 그라운딩 인정 포함). 서버에서는
`grounding_check()`를 매 요청의 응답에 포함시켜 "이 답을 얼마나 믿을 수 있는지"를 클라이언트
에 같이 전달하는 용도로 쓴다. `compare_to_golden()`은 서버 자체 로직에서는 안 쓰이고,
`tools/golden_regression_check.py`가 골든셋 회귀 검사를 할 때만 가져다 쓴다.
"""
from __future__ import annotations

import difflib
import re


def normalize_price_text(text: str) -> set[int]:
    """텍스트 안의 숫자 시퀀스(콤마 포함)를 정수 집합으로 뽑는다."""
    nums = set()
    for m in re.finditer(r"\d{1,3}(?:,\d{3})+|\d{4,}", text):
        try:
            nums.add(int(m.group(0).replace(",", "")))
        except ValueError:
            pass
    return nums


def _extract_percents(text: str) -> set[int]:
    """원문 안의 "N%" 할인율만 따로 뽑는다. normalize_price_text의 숫자 패턴(콤마 포함 또는
    4자리 이상)은 1~2자리 할인율(예: "32%")을 못 잡기 때문에 별도 함수로 분리."""
    return {int(m.group(1)) for m in re.finditer(r"(\d{1,2})\s*%", text)}


def _price_grounded(price, regular_price, text_numbers: set[int], percents: set[int]) -> bool:
    """가격이 원문에 리터럴로 있거나(직접 그라운딩), "정상가 − 즉시할인액"처럼 원문에 있는
    두 숫자의 차/비율로 정확히 재현되면(계산 그라운딩) 그라운딩된 것으로 인정한다."""
    if price is None:
        return False
    price = int(price)
    if price in text_numbers:
        return True
    if regular_price is None or int(regular_price) not in text_numbers:
        return False
    regular_price = int(regular_price)
    diff = regular_price - price
    if diff <= 0:
        return False
    # (a) 할인액이 원문에 그대로 있는 경우: 정상가 99,000 − 기본할인 64,200원 = 34,800
    if diff in text_numbers:
        return True
    # (b) 할인율(%)이 원문에 있고 그 비율로 정상가를 깎으면 반올림 오차(±1원) 안에서 price와
    #     일치하는 경우: 정상가 225,500 × (1−32%) = 153,340
    for pct in percents:
        if abs(round(regular_price * (100 - pct) / 100) - price) <= 1:
            return True
    return False


def grounding_check(extracted: dict, raw_text: str, image_candidates: list[str]) -> dict:
    """AI가 뽑은 값이 실제 페이지 원문에 등장하는지 확인 (환각 방지 안전판)."""
    price = (extracted.get("price") or {}).get("unconditional_price")
    regular_price = (extracted.get("price") or {}).get("regular_price")
    name = extracted.get("product_name")
    image = extracted.get("image_url")

    text_numbers = normalize_price_text(raw_text)
    price_grounded = _price_grounded(price, regular_price, text_numbers, _extract_percents(raw_text))

    name_grounded = bool(name) and _normalize_name(name)[:15] in _normalize_name(raw_text)

    image_grounded = bool(image) and (
        image in image_candidates or _basename(image) in {_basename(u) for u in image_candidates}
    )

    return {
        "price_grounded": price_grounded,
        "name_grounded": name_grounded,
        "image_grounded": image_grounded,
        "all_grounded": price_grounded and name_grounded and image_grounded,
    }


def _normalize_name(s: str) -> str:
    return re.sub(r"\s+", "", s or "").lower()


def _basename(url: str) -> str:
    return url.rstrip("/").split("/")[-1].split("?")[0] if url else ""


def _numeric_tokens(s: str) -> set[str]:
    """URL 안에서 5자리 이상 숫자열(상품ID·타임스탬프 등)을 뽑는다."""
    return set(re.findall(r"\d{5,}", s or ""))


def _image_core_match(a: str, b: str) -> bool:
    """같은 이미지의 다른 해상도/썸네일 변형을 같은 이미지로 취급한다."""
    if _basename(a) == _basename(b):
        return True
    return bool(_numeric_tokens(a) & _numeric_tokens(b))


def _name_containment_match(a: str, b: str, min_len: int = 6) -> bool:
    """짧은 쪽 이름이 긴 쪽 이름에 연속 부분문자열로 포함되면 같은 상품으로 간주."""
    shorter, longer = (a, b) if len(a) <= len(b) else (b, a)
    return len(shorter) >= min_len and shorter in longer


def compare_to_golden(extracted: dict, golden: dict) -> dict:
    """골든셋(실제 확인된 값)과 AI 추출 결과를 비교. 정확 일치가 아니라 유사도 기반."""
    price = (extracted.get("price") or {}).get("unconditional_price")
    name = extracted.get("product_name") or ""
    image = extracted.get("image_url") or ""

    price_match = price is not None and int(price) == int(golden["price"])

    norm_name, norm_golden_name = _normalize_name(name), _normalize_name(golden["name"])
    name_ratio = difflib.SequenceMatcher(None, norm_name, norm_golden_name).ratio()
    name_match = name_ratio >= 0.8 or _name_containment_match(norm_name, norm_golden_name)

    image_match = bool(image) and _image_core_match(image, golden["image"])

    full_match = price_match and name_match and image_match

    return {
        "price_match": price_match,
        "name_match": name_match,
        "name_similarity": round(name_ratio, 3),
        "image_match": image_match,
        "full_match": full_match,
    }
