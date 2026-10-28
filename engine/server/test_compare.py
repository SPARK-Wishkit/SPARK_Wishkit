"""engine-ai-prototype에서 이미 실측으로 검증된 두 가지 고침(26-2절 계산값 그라운딩,
19절 이름 포함관계)이 서버로 포팅한 뒤에도 그대로 동작하는지 확인하는 회귀 테스트."""
from compare import compare_to_golden, grounding_check


def test_price_grounded_accepts_computed_discount_amount():
    raw_text = "그루브스텝 티셔츠 쿠폰 할인가 99,000원 73% 26,100원 기본 할인 64% -64,200원"
    extracted = {
        "product_name": "그루브스텝 티셔츠",
        "price": {"unconditional_price": 34800, "regular_price": 99000, "currency": "KRW"},
        "image_url": None,
    }
    g = grounding_check(extracted, raw_text, [])
    assert g["price_grounded"] is True  # 99000 - 64200 = 34800 (계산 그라운딩)


def test_price_grounded_rejects_pure_hallucination():
    raw_text = "정상가 52,000원 상품할인 15% - 7,800원"
    extracted = {
        "product_name": "x",
        "price": {"unconditional_price": 99999, "regular_price": 52000, "currency": "KRW"},
        "image_url": None,
    }
    g = grounding_check(extracted, raw_text, [])
    assert g["price_grounded"] is False  # 99999는 원문에도 없고 계산으로도 안 나옴


def test_name_match_accepts_containment_with_promo_prefix():
    # 실제 재현 사례(design-doc-snapshot 19절): AI가 짧게 뽑은 이름이 SequenceMatcher
    # 유사도 임계값(0.8)에는 못 미치지만, 골든 이름에 연속 부분문자열로 포함되는 경우.
    extracted = {"product_name": "나이키 페가수스 42"}
    golden = {"name": "나이키 페가수스 42 여성 로드 러닝화", "price": 0, "image": ""}
    cmp = compare_to_golden({**extracted, "price": {"unconditional_price": 0}, "image_url": ""}, golden)
    assert cmp["name_similarity"] < 0.8  # 비율 기준으로는 원래 실패하던 케이스
    assert cmp["name_match"] is True  # 포함관계 규칙으로 구제됨


def test_name_match_still_rejects_unrelated_short_overlap():
    extracted = {"product_name": "나이키 반팔"}
    golden = {"name": "나이키 운동화 에어맥스 97", "price": 0, "image": ""}
    cmp = compare_to_golden({**extracted, "price": {"unconditional_price": 0}, "image_url": ""}, golden)
    assert cmp["name_match"] is False  # 짧은 공통 접두어("나이키")만으로 매치되면 안 됨
