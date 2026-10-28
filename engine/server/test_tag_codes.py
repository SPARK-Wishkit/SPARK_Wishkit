"""tag_codes.py — 바코드 검증 숫자, 품번 나누기, 페이지에서 코드 찾기."""
import pytest

from tag_codes import (
    base_code,
    clean_barcode,
    code_evidence,
    color_suffix,
    has_code,
    is_valid_gtin,
)


@pytest.mark.parametrize("code", ["4006381333931", "036000291452", "73513537", "8801234567893"])
def test_valid_gtin(code):
    assert is_valid_gtin(code)


@pytest.mark.parametrize("code", [
    "4006381333932",   # 마지막(검증) 자리 하나 틀림
    "4006381333391",   # 두 자리 순서 바뀜
    "88012345678",     # 11자리 — 바코드 길이가 아님
    "8801234S67893",   # 숫자 아닌 글자(S↔5 오독)
    "",
])
def test_invalid_gtin(code):
    assert not is_valid_gtin(code)


def test_clean_barcode_keeps_digits_only_and_reports_rejected():
    assert clean_barcode("880 1234 5678 93") == ("8801234567893", None)
    assert clean_barcode("8801234567890") == (None, "8801234567890")
    assert clean_barcode(None) == (None, None)


@pytest.mark.parametrize("code,base,color", [
    ("DV1234-100", "dv1234", "100"),          # 나이키 6+3
    ("485454-26", "485454", "26"),            # 유니클로 6+2
    ("MMFPL2C02-BK", "mmfpl2c02", "bk"),
    ("801474YB2FT1000", None, None),          # 구분자 없음 — 어디까지가 색상인지 모름
    ("AB-12", None, None),                    # 기본 번호가 너무 짧음
    ("CP9644", None, None),
])
def test_base_code_and_color(code, base, color):
    assert base_code(code) == base
    assert color_suffix(code) == color


TAG = {"product_code": "485454-26", "barcode": None, "other_codes": []}


def test_full_code_match_ignores_separators():
    assert code_evidence(TAG, "품번 485454 26", "") == "product_code"


def test_base_code_matches_page_without_color():
    assert code_evidence(TAG, "제품 번호: 485454 · 오렌지", "") == "product_code_base"


def test_base_code_matches_url_with_letter_prefix():
    url = "https://www.uniqlo.com/kr/ko/products/E485454-000/00?colorDisplayCode=26"
    assert code_evidence(TAG, "에어리즘 코튼 티셔츠", url) == "product_code_base"


@pytest.mark.parametrize("text", [
    "판매가 485,454원",       # 가격 숫자와 우연히 같은 모양
    "상품번호 4854541",       # 더 긴 숫자의 일부
    "코드 1485454",
])
def test_base_code_is_not_matched_inside_other_numbers(text):
    assert code_evidence(TAG, text, "") is None


def test_other_codes_can_confirm_when_primary_code_is_a_store_sticker():
    tag = {"product_code": "20261023001", "barcode": None, "other_codes": ["CP9644"]}
    assert code_evidence(tag, "adidas 슈퍼스타 CP9644", "") == "product_code_base"
    assert code_evidence(tag, "adidas 슈퍼스타", "") is None


def test_has_code():
    assert has_code({"product_code": "DV1234-100"})
    assert has_code({"product_code": None, "other_codes": ["CP9644"]})
    assert not has_code({"product_code": "A1", "barcode": None, "other_codes": ["12"]})
