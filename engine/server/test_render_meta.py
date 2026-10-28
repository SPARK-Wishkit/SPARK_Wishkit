"""render._meta_text — 본문에 없고 메타 태그에만 있는 품번을 읽는지."""
from render import _meta_text

MUSINSA_HEAD = """<html><head>
<title>1993스튜디오(1993STUDIO) 베이직 우먼 롱슬리브 (8colors) - 사이즈 &amp; 후기 | 무신사</title>
<meta name="description" content="브랜드 : 1993스튜디오(1993STUDIO) 제품번호 : 93251TTL1202 제품 : 베이직 우먼 롱슬리브">
<meta property="og:description" content="브랜드 : 1993스튜디오(1993STUDIO) 제품번호 : 93251TTL1202 제품 : 베이직 우먼 롱슬리브">
<meta property="product:price:normal_price" content="29900">
<meta name="viewport" content="width=device-width">
</head><body><div>베이직 우먼 롱슬리브 29,900원</div><meta name="description" content="본문 메타"></body></html>"""


def test_meta_text_reads_code_from_description():
    text = _meta_text(MUSINSA_HEAD)
    assert "93251TTL1202" in text
    assert "29900" in text            # product: 메타도 포함
    assert "width=device-width" not in text  # 관계없는 메타는 뺀다
    assert text.count("제품번호") == 1  # description·og:description 같은 문장은 한 번만


def test_meta_text_empty_when_no_meta():
    assert _meta_text("<html><body>본문만</body></html>") == ""
