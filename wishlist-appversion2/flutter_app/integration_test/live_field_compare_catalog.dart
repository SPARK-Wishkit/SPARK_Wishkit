class LiveCompareProduct {
  const LiveCompareProduct(this.url, {this.live});

  final String url;
  final LiveCompareExpected? live;
}

class LiveCompareExpected {
  const LiveCompareExpected({
    required this.name,
    required this.price,
    required this.image,
    this.brand,
  });

  final String name;
  final int price;
  final String image;
  final String? brand;
}

class LiveCompareMall {
  const LiveCompareMall(this.mall, this.products);

  final String mall;
  final List<LiveCompareProduct> products;
}

/// 2026-08-18 새로 연 상품 페이지에서 확인한 판매가(첫구매·카드 쿠폰 제외).
/// 엔진 상품명에는 브랜드가 붙을 수 있으므로 live.name 은 화면에 보이는 상품명이다.
const liveCompareMalls = <LiveCompareMall>[
  LiveCompareMall("11번가", [
    LiveCompareProduct(
      "https://www.11st.co.kr/products/2046037563",
      live: LiveCompareExpected(
        name: "[35%쿠폰+T11%] 비너스외 본사 신상브라.팬티,드로즈,홈웨어 BEST모음",
        price: 10000,
        image:
            "https://cdn.011st.com/11dims/resize/600x600/quality/75/11src/dl/v2/0/3/7/5/6/3/uhTkW/2046037563_237337664.webp",
      ),
    ),
    LiveCompareProduct(
      "https://www.11st.co.kr/products/9255708792",
      live: LiveCompareExpected(
        name: "남양 경기미 10kg 상등급 쌀",
        price: 26900,
        image:
            "https://cdn.011st.com/11dims/resize/600x600/quality/75/11src/product/9255708792/B.webp",
      ),
    ),
    LiveCompareProduct(
      "https://www.11st.co.kr/products/8716610739",
      live: LiveCompareExpected(
        name: "세스코 마이랩 배수구클리너 5개+5개 악취제거",
        price: 15000,
        image:
            "https://cdn.011st.com/11dims/resize/600x600/quality/75/11src/dl/v2/6/1/0/7/3/9/ZIZWq/8716610739_235640427.webp",
      ),
    ),
  ]),
  LiveCompareMall("무신사", [
    LiveCompareProduct(
      "https://www.musinsa.com/products/4341120",
      live: LiveCompareExpected(
        name: "클래식 반소매 티셔츠 - 블랙 / 801474YB2FT1000",
        price: 105990,
        image:
            "https://image.msscdn.net/images/goods_img/20240819/4341120/4341120_17254134643550_500.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.musinsa.com/products/6797005",
      live: LiveCompareExpected(
        name: "Days Comfort Fit Shirt_White",
        price: 84550,
        image:
            "https://image.msscdn.net/images/goods_img/20260707/6797005/6797005_17852305721496_500.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.musinsa.com/products/6677115",
      live: LiveCompareExpected(
        name: "소프트 헨리넥 반팔 티셔츠 [브라운]",
        price: 24900,
        image:
            "https://image.msscdn.net/images/goods_img/20260616/6677115/6677115_17852914703616_500.jpg",
      ),
    ),
  ]),
  LiveCompareMall("W컨셉", [
    LiveCompareProduct(
      "https://www.wconcept.co.kr/Product/308678703",
      live: LiveCompareExpected(
        name: "멀티 유즈 슬리브리스 탑 브라운 OU2006",
        price: 39000,
        image:
            "https://product-image.wconcept.co.kr/productimg/image/img9/03/308678703_UI25679.jpg",
        brand: "ouie",
      ),
    ),
    LiveCompareProduct(
      "https://www.wconcept.co.kr/Product/308589275",
      live: LiveCompareExpected(
        name: "Soft Drape T-shirt_3Color",
        price: 88000,
        image:
            "https://product-image.wconcept.co.kr/productimg/image/img9/75/308589275_EP72624.jpg",
        brand: "FLOWOOM",
      ),
    ),
    LiveCompareProduct(
      "https://www.wconcept.co.kr/Product/308629259",
      live: LiveCompareExpected(
        name: "[단독][SET] Wrap Detail T-Shirt & V-Neck Sleeveless Top",
        price: 86700,
        image:
            "https://product-image.wconcept.co.kr/productimg/image/img9/59/308629259_VW44687.jpg",
        brand: "THE RYE",
      ),
    ),
  ]),
  LiveCompareMall("29CM", [
    LiveCompareProduct(
      "https://www.29cm.co.kr/products/3769341",
      live: LiveCompareExpected(
        name: "[꼬민지PICK/29CM 단독] SIOT4182 하이 넥 버튼 블루종_Navy",
        price: 141950,
        image:
            "https://img.29cm.co.kr/item/202608/11f199d6377ee51285e175537dd844cc.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.29cm.co.kr/products/3423314",
      live: LiveCompareExpected(
        name:
            "[Atelier Edition] W/Two Way Vegan Leather Jacket_2COLOR(WC25-OT09)",
        price: 117260,
        image:
            "https://img.29cm.co.kr/item/202509/11f093803023ba4494a2b7e59c753ef1.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.29cm.co.kr/products/3765311",
      live: LiveCompareExpected(
        name: "[꼬민지 PICK][10th] faux leather half coat_black",
        price: 197100,
        image:
            "https://img.29cm.co.kr/item/202608/11f199cc75fcdd8885e1f77211683ab4.jpg",
      ),
    ),
  ]),
  LiveCompareMall("FILA", [
    LiveCompareProduct(
      "https://www.fila.co.kr/products/1100fs263ru02x098260",
      live: LiveCompareExpected(
        name: "휠라 스피드템포 플러스",
        price: 179000,
        image:
            "http://www.fila.co.kr/cdn/shop/files/01_ec774e94-3176-464e-9139-cab54dec4b8c.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.fila.co.kr/products/1100fs263ft01u003071",
      live: LiveCompareExpected(
        name: "[한소희 착용] 1911 니트트랙 집업",
        price: 129000,
        image:
            "http://www.fila.co.kr/cdn/shop/files/01_a69acc45-14e8-4890-b5e6-4f582042e578.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.fila.co.kr/products/1100fs263ft01u003330",
      live: LiveCompareExpected(
        name: "[김나영 착용] 1911 여성 니트트랙 집업",
        price: 129000,
        image:
            "http://www.fila.co.kr/cdn/shop/files/01_a478ca37-674d-4e87-b4d0-b1e97e4182a3.jpg",
      ),
    ),
  ]),
  LiveCompareMall("하고", [
    LiveCompareProduct(
      "https://www.hago.kr/goods/detail/468261",
      live: LiveCompareExpected(
        name: "Hey Double Pocket Backpack M (헤이 더블 포켓 백팩 미듐) Black",
        price: 215000,
        image: "https://image.hago.kr/mall/goods/000/000/468/261/1.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.hago.kr/goods/detail/545988",
      live: LiveCompareExpected(
        name: "Toque Hermit Cross S (토크 헐밋 크로스 스몰)_5colors",
        price: 215000,
        image: "https://image.hago.kr/mall/goods/000/000/545/988/1.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.hago.kr/goods/detail/456508",
      live: LiveCompareExpected(
        name: "Perfec Button Up Soft Hobo S (퍼펙 버튼 업 소프트 호보 스몰) Black",
        price: 345000,
        image: "https://image.hago.kr/mall/goods/000/000/456/508/1.jpg",
      ),
    ),
  ]),
  LiveCompareMall("룩핀", [
    LiveCompareProduct(
      "https://www.lookpin.co.kr/products/3176309",
      live: LiveCompareExpected(
        name: "아미 스몰로고 반팔티 2종 택1",
        price: 29900,
        image:
            "https://static.lookpin.co.kr/20260629051610-a5df/2aeed68c47ae4fbcab74d57fe9e1e2c9.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.lookpin.co.kr/products/3183252",
      live: LiveCompareExpected(
        name: "[1+1할인] 세미와이드 쿨 여름 밴딩 팬츠 4COLOR",
        price: 19800,
        image:
            "https://static.lookpin.co.kr/20260721045352-9e2d/7322353cfda84075a25511f9563c7ec0.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.lookpin.co.kr/products/3149308",
      live: LiveCompareExpected(
        name: "[1+1할인] 리브드 에센셜 하프 니트 - 2Type",
        price: 22900,
        image:
            "https://static.lookpin.co.kr/20260623081643-2b32/112e1f9c2a794bc2a311b8ef53f4f32b.jpg",
      ),
    ),
  ]),
  LiveCompareMall("탑텐", [
    LiveCompareProduct(
      "https://topten10.goodwearmall.com/product/MSG2TS3002WT/detail",
      live: LiveCompareExpected(
        name: "공용) [카카오프렌즈] COOL Air 코튼 반팔 T",
        price: 9900,
        image: "https://img.goodwearmall.com/goods/MSG2TS/MSG2TS3002WT_M.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://topten10.goodwearmall.com/product/MSG2PP2001BK/detail",
      live: LiveCompareExpected(
        name: "여성) COOL 와이드 크롭 이지 팬츠",
        price: 19900,
        image: "https://img.goodwearmall.com/goods/MSG2PP/MSG2PP2001BK_M.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://topten10.goodwearmall.com/product/MBG2PH2701BK/detail",
      live: LiveCompareExpected(
        name: "여성) 워터 쇼츠",
        price: 12900,
        image: "https://img.goodwearmall.com/goods/MBG2PH/MBG2PH2701BK_M.jpg",
      ),
    ),
  ]),
  LiveCompareMall("무인양품", [
    LiveCompareProduct(
      "https://mujikorea.co.kr/products/view/1005557",
      live: LiveCompareExpected(
        name: "워싱 브로드 레귤러 칼라 긴소매 셔츠",
        price: 29900,
        image:
            "https://public.mujikorea.co.kr/metas/nsGaFaLffindyVDC5BACub7Tog0evl5XZ4h1LNYD.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://mujikorea.co.kr/products/view/1005389",
      live: LiveCompareExpected(
        name: "워싱 브로드 레귤러 칼라 긴소매 셔츠",
        price: 29900,
        image:
            "https://public.mujikorea.co.kr/metas/nsGaFaLffindyVDC5BACub7Tog0evl5XZ4h1LNYD.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://mujikorea.co.kr/products/view/1005367",
      live: LiveCompareExpected(
        name: "슬러브 치노 와이드 팬츠",
        price: 49900,
        image:
            "https://public.mujikorea.co.kr/metas/nsGaFaLffindyVDC5BACub7Tog0evl5XZ4h1LNYD.jpg",
      ),
    ),
  ]),
  LiveCompareMall("현대Hmall", [
    LiveCompareProduct(
      "https://www.hmall.com/md/pda/itemPtc?slitmCd=2247033660&dispTrtyNmCd=home_onair&dispOrdg=1",
      live: LiveCompareExpected(
        name: "[충격특가 울100 가디건 4만원대] 디아루체 26SS 울 100 워셔블 가디건 1종",
        price: 49900,
        image: "https://image.hmall.com/static/6/3/03/47/2247033660_0.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.hmall.com/md/pda/itemPtc?slitmCd=2247721571&dispTrtyNmCd=home_tvplus&dispOrdg=1",
      live: LiveCompareExpected(
        name: "인터쿡 토마호크 로스돔 3종 세트",
        price: 99000,
        image: "https://image.hmall.com/static/5/1/72/47/2247721571_0.png",
      ),
    ),
    LiveCompareProduct(
      "https://www.hmall.com/md/pda/itemPtc?slitmCd=2077436192",
      live: LiveCompareExpected(
        name: "리락쿠마 사각밀폐 2단 도시락",
        price: 6650,
        image: "https://image.hmall.com/static/1/6/43/77/2077436192_0.jpg",
      ),
    ),
  ]),
  LiveCompareMall("롯데온", [
    LiveCompareProduct(
      "https://www.lotteon.com/p/product/LO2724337623",
      live: LiveCompareExpected(
        name: "[모로엠] 남성 밴딩 헬스 데일리 반바지 ON-PTH-QWFOQWRF",
        price: 26400,
        image:
            "https://contents.lotteon.com/itemimage/20260715172126/LO/27/24/33/76/23/_2/72/43/37/62/4/LO2724337623_2724337624_1.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.lotteon.com/p/product/LO2724337620",
      live: LiveCompareExpected(
        name: "어린이물총 실내외놀이 여름 전동물총 아기 육아 물놀이 퀵샷",
        price: 172440,
        image:
            "https://contents.lotteon.com/itemimage/20260715172126/LO/27/24/33/76/20/_2/72/43/37/62/1/LO2724337620_2724337621_1.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.lotteon.com/p/product/LO2724337630",
      live: LiveCompareExpected(
        name: "노런 바퀴트랩 5매입 -H/노런바퀴트랩5매입/바퀴/바퀴벌레/끈끈이/바퀴벌레약/바퀴약/에프킬라/애프킬라/바",
        price: 2600,
        image:
            "https://contents.lotteon.com/itemimage/20260715172125/LO/27/24/33/76/30/_2/72/43/37/63/1/LO2724337630_2724337631_1.jpg",
      ),
    ),
  ]),
  LiveCompareMall("미쏘", [
    LiveCompareProduct(
      "https://mixxo.com/product/detail.html?product_no=11934",
      live: LiveCompareExpected(
        name: "크롭탑 나시 티셔츠_MIWHNG310A",
        price: 7900,
        image:
            "https://cafe24img.poxo.com/mixxo/web/product/big/202608/bd5b90689a7a83c2c465cf0e43ddfefd.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://mixxo.com/product/detail.html?product_no=12038",
      live: LiveCompareExpected(
        name: "버뮤다 데님_MIWTHG410J",
        price: 49900,
        image:
            "https://cafe24img.poxo.com/mixxo/web/product/big/202604/6f35c8987ae4e3431a8b2966adc18ef9.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://mixxo.com/product/detail.html?product_no=12243",
      live: LiveCompareExpected(
        name: "크롭탑 나시 티셔츠_MIWHNG310A_MIWHNG3B01",
        price: 7900,
        image:
            "https://cafe24img.poxo.com/mixxo/web/product/big/202603/fe376dcef698cdb59d6c245beb293978.jpg",
      ),
    ),
  ]),
  LiveCompareMall("데일리쥬", [
    LiveCompareProduct(
      "https://dailyjou.com/product/detail.html?product_no=22793",
      live: LiveCompareExpected(
        name: "[MADE] 마르델 스탠다드 셔링 체크 셔츠",
        price: 39000,
        image:
            "https://cafe24.poxo.com/ec01/cocomimi93/Kcc0fQ0DsTHpcxHYW7fqLaBIC/o2a/jM6bRPEprGgUE2Ahi38o9n6QY5e//FBcVGbltRbal2kV5zxlu1744asA==/_/web/product/big/202509/f265e64893c6df9bdba535e494a67199.webp",
      ),
    ),
    LiveCompareProduct(
      "https://dailyjou.com/product/detail.html?product_no=19572",
      live: LiveCompareExpected(
        name: "올렌 볼드 펜던트 목걸이",
        price: 17000,
        image:
            "https://cafe24.poxo.com/ec01/cocomimi93/Kcc0fQ0DsTHpcxHYW7fqLaBIC/o2a/jM6bRPEprGgUE2Ahi38o9n6QY5e//FBcVGbltRbal2kV5zxlu1744asA==/_/web/product/big/202509/be762689d061aafd1be55dd46cf74fee.webp",
      ),
    ),
    LiveCompareProduct(
      "https://dailyjou.com/product/detail.html?product_no=19245",
      live: LiveCompareExpected(
        name: "[MADE] 비셔스 핸드메이드 후드 코트 (하프/롱)",
        price: 152000,
        image:
            "https://cafe24.poxo.com/ec01/cocomimi93/Kcc0fQ0DsTHpcxHYW7fqLaBIC/o2a/jM6bRPEprGgUE2Ahi38o9n6QY5e//FBcVGbltRbal2kV5zxlu1744asA==/_/web/product/big/202510/9c488cee2f3d2785af72057cad82172a.webp",
      ),
    ),
  ]),
  LiveCompareMall("리", [
    LiveCompareProduct(
      "https://leekorea.co.kr/product/detail.html?product_no=14251",
      live: LiveCompareExpected(
        name: "로코 포켓 데님 셔츠 인디고 미듐",
        price: 99000,
        image:
            "https://leekorea.co.kr/web/product/big/202606/8c3d1b8cd0176a62188526a5280c1f58.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://leekorea.co.kr/product/detail.html?product_no=15434",
      live: LiveCompareExpected(
        name: "우먼 후드 긴팔 티셔츠 베이지",
        price: 75000,
        image:
            "https://leekorea.co.kr/web/product/big/202605/8785bfaa63e64defbbc1c811f533f90c.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://leekorea.co.kr/product/detail.html?product_no=15291",
      live: LiveCompareExpected(
        name: "우먼 홀리데이 체크 셔츠 브라운",
        price: 89000,
        image:
            "https://leekorea.co.kr/web/product/big/202605/7ae0122ed3a8f4a85967e1bb3d030099.jpg",
      ),
    ),
  ]),
  LiveCompareMall("필루미네이트", [
    LiveCompareProduct(
      "https://filluminate.com/product/detail.html?product_no=11744",
      live: LiveCompareExpected(
        name: "데일리 레귤러 크롭 머슬 티셔츠-3Color",
        price: 32000,
        image:
            "https://filluminate.com/web/product/big/202605/d9ea9d12e98dd435a79dcc276b54001b.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://filluminate.com/product/detail.html?product_no=11567",
      live: LiveCompareExpected(
        name: "키체인 그래픽 티셔츠-멜란지그레이",
        price: 39000,
        image:
            "https://filluminate.com/web/product/big/202603/ca71f0deb27571e45d61b208f79ce5b1.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://filluminate.com/product/detail.html?product_no=11639",
      live: LiveCompareExpected(
        name: "카고 버뮤다 스웨트 쇼츠-멜란지그레이",
        price: 54000,
        image:
            "https://filluminate.com/web/product/big/202603/a82069ac5973e12c93ede3ae1829a0ca.jpg",
      ),
    ),
  ]),
  LiveCompareMall("어반스터프", [
    LiveCompareProduct(
      "https://urbanstoff.com/product/detail.html?product_no=518",
      live: LiveCompareExpected(
        name: "밀키 웨이 엠브로이더리 티 (화이트)",
        price: 45000,
        image:
            "https://ecimg.cafe24img.com/pg1589b23882635070/urbanstoff001/web/product/big/20260814/4b5545c94d305a76f71243c745419284.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://urbanstoff.com/product/detail.html?product_no=517",
      live: LiveCompareExpected(
        name: "밀키 웨이 엠브로이더리 티 (챠콜)",
        price: 45000,
        image:
            "https://ecimg.cafe24img.com/pg1589b23882635070/urbanstoff001/web/product/big/20260814/944ed7927b8c6d748296347104236706.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://urbanstoff.com/product/detail.html?product_no=516",
      live: LiveCompareExpected(
        name: "체크 도트 아플리케 티 (화이트)",
        price: 45000,
        image:
            "https://ecimg.cafe24img.com/pg1589b23882635070/urbanstoff001/web/product/big/20260814/161715ce5b8944fa95a0c9ce55bb84e5.jpg",
      ),
    ),
  ]),
  LiveCompareMall("낫포유", [
    LiveCompareProduct(
      "https://not4u.kr/product/detail.html?product_no=548",
      live: LiveCompareExpected(
        name: "[1+1/리뉴얼] 클리어 PDRN NAD+ 장벽 강화 바디워시 500ml",
        price: 17800,
        image:
            "https://not4u.kr/web/product/big/202608/fbd24b58532fff8dc474e69050f18461.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://not4u.kr/product/detail.html?product_no=497",
      live: LiveCompareExpected(
        name: "[리뉴얼] 등드름/가드름 클리어 PDRN NAD+ 장벽 강화 바디워시500ml 기획(본품+리필 50ml)",
        price: 16900,
        image:
            "https://not4u.kr/web/product/big/202608/508767dc7a6b8b4edac928dbd2537552.jpg",
      ),
    ),
  ]),
  LiveCompareMall("인사일런스", [
    LiveCompareProduct(
      "https://insilence.co.kr/product/detail.html?product_no=7482",
      live: LiveCompareExpected(
        name: "스탠실 그래픽 티셔츠 MELANGE GREY",
        price: 59000,
        image:
            "https://insilence.co.kr/web/product/big/202604/4a5eec3507b656d37f41be5694312c5b.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://insilence.co.kr/product/detail.html?product_no=7400",
      live: LiveCompareExpected(
        name: "와플 크루넥 롱슬리브 MELANGE GREY",
        price: 49000,
        image:
            "https://insilence.co.kr/web/product/big/202608/903f9f151097e13333f517b6ee693454.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://insilence.co.kr/product/detail.html?product_no=7180",
      live: LiveCompareExpected(
        name: "엔지니어핏 데님 팬츠 RINSED INDIGO",
        price: 149000,
        image:
            "https://insilence.co.kr/web/product/big/202608/9e07ab598aac3edecdde96e5348916c2.jpg",
      ),
    ),
  ]),
  LiveCompareMall("파브레가", [
    LiveCompareProduct(
      "https://fabregat.kr/product/detail.html?product_no=1033",
      live: LiveCompareExpected(
        name: "Brom Carabiner Leather Keyring (Dark Brown)",
        price: 44000,
        image:
            "https://fabregat.kr/web/product/big/202605/8033f6a93c8f90ce25de57f9e515d602.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://fabregat.kr/product/detail.html?product_no=1030",
      live: LiveCompareExpected(
        name: "Bone Pig-Dyeing Check Half Shirt (Indi Pink)",
        price: 77000,
        image:
            "https://fabregat.kr/web/product/big/202605/1052ddd7d76a3a204b71d6cceebbea51.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://fabregat.kr/product/detail.html?product_no=1029",
      live: LiveCompareExpected(
        name: "Bone Pig-Dyeing Check Half Shirt (Black)",
        price: 77000,
        image:
            "https://fabregat.kr/web/product/big/202605/3a7808547d17f7a1f9d6bd9d06e36d30.jpg",
      ),
    ),
  ]),
  LiveCompareMall("핫핑", [
    LiveCompareProduct(
      "https://hotping.co.kr/product/detail.html?product_no=39923",
      live: LiveCompareExpected(
        name:
            "[컬러추가💗][2기장][데일리필수][MADE] 에디션 기본&숏 슬리브리스 이너티 (44~110) (빅사이즈나시-이너나시-데일리나시-베이직나시-무지나시-크롭나시-데일리-랍빠-꾸안꾸룩-흠뻑쇼-페스티벌)",
        price: 14800,
        image:
            "https://hotping.co.kr/web/product/big/202505/77a0f965457d5d0e63d00de2f3880ecc.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://hotping.co.kr/product/detail.html?product_no=43640",
      live: LiveCompareExpected(
        name:
            "[🌈11컬러] 르나스 라운드넥 베이직 반팔티셔츠 (44~99) (간절기신상-루즈핏티셔츠-봄코디-베이직-박시핏-빅사이즈티-데일리룩-캐주얼룩-일상룩-꾸안꾸룩-레몬코어)",
        price: 8280,
        image:
            "https://hotping.co.kr/web/product/big/202607/70b2810e89c885e7502a2e0ddb703fbe.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://hotping.co.kr/product/detail.html?product_no=48324",
      live: LiveCompareExpected(
        name:
            "[여리슬림핏/-3kg/팔뚝살커버][MADE] 라플린 카라 딥브이넥 랩 반팔 니트가디건 (44~110) (빅사이즈니트-쿨링니트-카라니트-브이넥니트-랩니트-체형커버-캐주얼-데일리-출근룩-오피스룩-하객룩-페미닌-일체형-스판니트)",
        price: 32800,
        image:
            "https://hotping.co.kr/web/product/big/202608/6e25bd612ee674c28d19c19afc5edd51.jpg",
      ),
    ),
  ]),
  LiveCompareMall("유니클로", [
    LiveCompareProduct(
      "https://www.uniqlo.com/kr/ko/products/E488796-000/00?colorDisplayCode=00&sizeDisplayCode=005",
      live: LiveCompareExpected(
        name: "옥스포드오버사이즈셔츠",
        price: 49900,
        image:
            "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/488796/sub/krgoods_488796_sub14_3x4.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.uniqlo.com/kr/ko/products/E488798-000/00?colorDisplayCode=32&sizeDisplayCode=005",
      live: LiveCompareExpected(
        name: "옥스포드오버사이즈셔츠(스트라이프)B",
        price: 49900,
        image:
            "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/488798/sub/krgoods_488798_sub3_3x4.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.uniqlo.com/kr/ko/products/E488797-000/00?colorDisplayCode=54&sizeDisplayCode=005",
      live: LiveCompareExpected(
        name: "옥스포드오버사이즈셔츠(스트라이프)A",
        price: 49900,
        image:
            "https://image.uniqlo.com/UQ/ST3/kr/imagesgoods/488797/sub/krgoods_488797_sub3_3x4.jpg",
      ),
    ),
  ]),
  LiveCompareMall("SSG", [
    LiveCompareProduct(
      "https://www.ssg.com/item/dealItemView.ssg?itemId=1000641326300&siteNo=7009&salestrNo=2551",
      live: LiveCompareExpected(
        name: "(~50%) 한우 구이,국거리,불고기 등",
        price: 10890,
        image:
            "https://sitem.ssgcdn.com/00/63/32/item/1000641326300_i1_250.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.ssg.com/item/dealItemView.ssg?itemId=1000534782697&siteNo=6001&salestrNo=2037",
      live: LiveCompareExpected(
        name: "26년 가을 서해 햇꽃게 ~45%할인",
        price: 35880,
        image:
            "https://sitem.ssgcdn.com/97/26/78/item/1000534782697_i1_250.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.ssg.com/item/dealItemView.ssg?itemId=1000860886017&siteNo=6001&salestrNo=2037",
      live: LiveCompareExpected(
        name: "메가파인트/파인트/멀티바 (상품상세 배너클릭/응모필수)",
        price: 22900,
        image:
            "https://sitem.ssgcdn.com/17/60/88/item/1000860886017_i1_250.jpg",
      ),
    ),
  ]),
  LiveCompareMall("더현대Hi", [
    LiveCompareProduct(
      "https://hi.thehyundai.com/product/60B1084782?sectId=1031",
      live: LiveCompareExpected(
        name: "소가죽 오픈토 뮬 BE26S3FSP0251",
        price: 301680,
        image: "https://image.thehyundai.com/8/7/4/08/B1/60B1084782_0.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://hi.thehyundai.com/product/40B1406274?sectId=1031",
      live: LiveCompareExpected(
        name: "스티치 백 리본 블라우스 Z262MSC031",
        price: 130300,
        image: "https://image.thehyundai.com/7/2/6/40/B1/40B1406274_0.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://hi.thehyundai.com/product/2229774639?sectId=1031",
      live: LiveCompareExpected(
        name: "VW-5074-001",
        price: 175320,
        image: "https://image.thehyundai.com/3/6/4/77/29/2229774639_0.jpg",
      ),
    ),
  ]),
  LiveCompareMall("에이블리", [
    LiveCompareProduct(
      "https://mobile.a-bly.com/goods/75432976",
      live: LiveCompareExpected(
        name: "[하이넥/간절기필수🍂] 톤텔 루즈 사선 지퍼 후드집업",
        price: 26500,
        image:
            "https://imgb.a-bly.com/data/goods/7b7beef563b76b4fa88149111c73b23f.gif",
      ),
    ),
    LiveCompareProduct(
      "https://mobile.a-bly.com/goods/75506878",
      live: LiveCompareExpected(
        name: "[여리코어🪡] made 소피 여리 펀칭 니트 - 4color",
        price: 23270,
        image:
            "https://imgb.a-bly.com/data/goods/1ae2f183f57bb3474c726cf53f09e5e0.gif",
      ),
    ),
    LiveCompareProduct(
      "https://mobile.a-bly.com/goods/28244036",
      live: LiveCompareExpected(
        name: "🏆1위🏆 스킨 레이어 핏 파운데이션",
        price: 20000,
        image:
            "https://imgb.a-bly.com/data/goods/f7995d70c943e5ca270f9f07ca8d10e2.gif",
      ),
    ),
  ]),
  LiveCompareMall("지그재그", [
    LiveCompareProduct(
      "https://zigzag.kr/catalog/products/159126270",
      live: LiveCompareExpected(
        name: "[MADE] [4만장/컬러추가] 캡내장 로브닝 레이스 슬리브리스",
        price: 17000,
        image:
            "https://cf.product-image.s.zigzag.kr/original/c/15/912/627/159126270-7158693702236622361.jpeg",
      ),
    ),
    LiveCompareProduct(
      "https://zigzag.kr/catalog/products/168362278",
      live: LiveCompareExpected(
        name: "화이트랩스 치아미백기 LED 셀프 자가 치아미백기계 &amp; 치아미백젤 세트 (1인용)",
        price: 179000,
        image:
            "https://cf.product-image.s.zigzag.kr/original/d/2026/2/3/59382_202602031710060884_61349.jpeg",
      ),
    ),
    LiveCompareProduct(
      "https://zigzag.kr/catalog/products/161980550",
      live: LiveCompareExpected(
        name: "🌹뷰티페스타 특가🌹 [조말론] 블랙베리 앤 베이 코롱 100ml (블랙베리향) (+선물포장)",
        price: 185580,
        image:
            "https://cf.product-image.s.zigzag.kr/original/d/2026/7/16/40976_202607161436522871_71643.jpeg",
      ),
    ),
  ]),
  LiveCompareMall("KREAM", [
    LiveCompareProduct(
      "https://kream.co.kr/products/1012767",
      live: LiveCompareExpected(
        name:
            "[KREAM 단독] Thevinylhouse x Bocchi the Rock! Kessoku Star Layered Ls Tee Black",
        price: 75000,
        image:
            "https://kream-phinf.pstatic.net/MjAyNjA3MjFfMTg4/MDAxNzg0NjI1NjU1NjM1.2BI9VXVbcdapWUmRh0WlEwr_hv_5W7N9xFYqHb05Pycg.GPpdMDscTfgzG9PM3uOktT3yV5TjyOibgMklxlCgfnsg.PNG/p_d155324f3a38439dbbfd707b2d447f5f.png",
      ),
    ),
    LiveCompareProduct(
      "https://kream.co.kr/products/1012757",
      live: LiveCompareExpected(
        name:
            "[KREAM 단독] Thevinylhouse x Bocchi the Rock! Kessoku Acrylic Key Ring Pink",
        price: 19000,
        image:
            "https://kream-phinf.pstatic.net/MjAyNjA3MjFfOTUg/MDAxNzg0NjE1NTMwMjk2.BAmLftkmc4G7A3xzGvewt3OmPuR_sRzpIjmUn7hExxYg.8IxWY5b80ELy9K0tNXYS15aisYfYNbEuPg5k6ibXFQAg.PNG/p_b2b51d61d9264fc68948da832b0c0906.png",
      ),
    ),
    LiveCompareProduct(
      "https://kream.co.kr/products/1012784",
      live: LiveCompareExpected(
        name:
            "[KREAM 단독] Thevinylhouse x Bocchi the Rock! Kessoku Friends Tee Black",
        price: 59000,
        image:
            "https://kream-phinf.pstatic.net/MjAyNjA3MjFfMjI3/MDAxNzg0NjE3ODY4Mzg1.UDEeWJY1fUchthKDAaTpRFlDedLp0QZPloakINgb3oAg.XJv6aiPlKmv1s-z6TL5OOoBvQpD_URRpaU45gZYk0mYg.PNG/p_aef519f6b61f43fabb7eda41dac1a1bd.png",
      ),
    ),
  ]),
  LiveCompareMall("게스", [
    LiveCompareProduct(
      "https://www.guesskorea.com/product/detail.html?product_no=49568",
      live: LiveCompareExpected(
        name: "여성 인디고 플레어 부츠컷_DARK BLUE",
        price: 259000,
        image:
            "https://www.guesskorea.com/web/product/big/202608/93f2a25aae82f56dda87640e8aaf7cd5.png",
      ),
    ),
    LiveCompareProduct(
      "https://www.guesskorea.com/product/detail.html?product_no=51217",
      live: LiveCompareExpected(
        name: "여성 체인장식 와이드_MEDIUM BLUE",
        price: 239000,
        image:
            "https://www.guesskorea.com/web/product/big/202608/acadd420d4df47952048ec429df05445.png",
      ),
    ),
    LiveCompareProduct(
      "https://www.guesskorea.com/product/detail.html?product_no=52432",
      live: LiveCompareExpected(
        name: "여성 헨리넥 반팔 카라티_WHITE",
        price: 79000,
        image:
            "https://www.guesskorea.com/web/product/big/202607/4fc0b81c840da87713777140bc8b62c9.png",
      ),
    ),
  ]),
  LiveCompareMall("반스", [
    LiveCompareProduct(
      "https://www.vans.co.kr/PRODUCT/VN00114ABLK",
      live: LiveCompareExpected(
        name: "OTW 에라 95 빈티지 렐릭",
        price: 155000,
        image: "https://img.vans.com/image/upload/VN00114ABLK-ALT20.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.vans.co.kr/PRODUCT/VN000V74BRD",
      live: LiveCompareExpected(
        name: "스케이트 로완 Z3 검솔",
        price: 125000,
        image: "https://img.vans.com/image/upload/VN000V74BRD-ALT20.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.vans.co.kr/PRODUCT/VN000EJ8FST",
      live: LiveCompareExpected(
        name: "울트라레인지 네오 2.0",
        price: 149000,
        image: "https://img.vans.com/image/upload/VN000EJ8FST-ALT20.jpg",
      ),
    ),
  ]),
  LiveCompareMall("커버낫", [
    LiveCompareProduct(
      "https://covernat.co.kr/product/detail.html?product_no=8300",
      live: LiveCompareExpected(
        name: "우먼 스몰 클로버하트 티셔츠 Lime",
        price: 29000,
        image:
            "https://covernat.co.kr/web/product/big/202503/ddafdfdcb5f89b8d6cacf141a35d77c2.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://covernat.co.kr/product/detail.html?product_no=8113",
      live: LiveCompareExpected(
        name: "[2PACK] 엑티브 티셔츠 Black+White",
        price: 39000,
        image:
            "https://covernat.co.kr/web/product/big/202605/0c6ea70b2a072b9cf502b9340129f48a.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://covernat.co.kr/product/detail.html?product_no=7686",
      live: LiveCompareExpected(
        name: "[2PACK] 우먼 쿨 코튼 에센셜 티셔츠 Ecru+Surf Green",
        price: 29000,
        image:
            "https://covernat.co.kr/web/product/big/202605/eaefad3ae7fa8516abd5a17fbe4ef815.jpg",
      ),
    ),
  ]),
  LiveCompareMall("코드그라피", [
    LiveCompareProduct(
      "https://code-graphy.com/product/detail.html?product_no=8265",
      live: LiveCompareExpected(
        name: "(우먼) CGP 체크 토마토 링거 반소매 티셔츠-화이트",
        price: 44100,
        image:
            "https://cafe24.poxo.com/ec01/cgraphy/nDa3+VeoMR5vyddRVokF8ltOczmmZefMqiQFCv903NO3uqDUY03GsJUYRdWtWSXw916shfsw86QFrSvagfRRrA==/_/web/product/big/202604/2cdc55d7272c36306f3a873133bf9185.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://code-graphy.com/product/detail.html?product_no=8260",
      live: LiveCompareExpected(
        name: "BERRY CUTE 반소매 티셔츠-버건디",
        price: 44100,
        image:
            "https://cafe24.poxo.com/ec01/cgraphy/nDa3+VeoMR5vyddRVokF8ltOczmmZefMqiQFCv903NO3uqDUY03GsJUYRdWtWSXw916shfsw86QFrSvagfRRrA==/_/web/product/big/202603/b98209ef5e0450e18d3567aa7fee5e93.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://code-graphy.com/product/detail.html?product_no=8261",
      live: LiveCompareExpected(
        name: "8부 버뮤다 트레이닝 쇼츠-다크 그레이",
        price: 62100,
        image:
            "https://cafe24.poxo.com/ec01/cgraphy/nDa3+VeoMR5vyddRVokF8ltOczmmZefMqiQFCv903NO3uqDUY03GsJUYRdWtWSXw916shfsw86QFrSvagfRRrA==/_/web/product/big/202603/a612c6a05a5aa4b99b2b67adbba685a2.jpg",
      ),
    ),
  ]),
  LiveCompareMall("후아유", [
    LiveCompareProduct(
      "https://whoau.com/product/detail.html?product_no=4457",
      live: LiveCompareExpected(
        name: "Signature Patch Hood Zip-up",
        price: 34950,
        image:
            "https://cafe24.poxo.com/ec01/whoaukr/3JPAsJn/jGkesyYvH/tEacJ//FpiOmI0G0IBVoMAo1XCOUL3mT6Caj09FWLKVeGQ1kJx/IhRfpWw9NNnns5vjA==/_/web/product/big/202605/b3b8d13d2af1478d442cf875d9ac2ea9.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://whoau.com/product/detail.html?product_no=4466",
      live: LiveCompareExpected(
        name: "Steve Cable Cardigan",
        price: 29950,
        image:
            "https://cafe24.poxo.com/ec01/whoaukr/3JPAsJn/jGkesyYvH/tEacJ//FpiOmI0G0IBVoMAo1XCOUL3mT6Caj09FWLKVeGQ1kJx/IhRfpWw9NNnns5vjA==/_/web/product/big/202602/f70fa54424b38b17fd8938dfc078dc1c.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://whoau.com/product/detail.html?product_no=4527",
      live: LiveCompareExpected(
        name: "Campus Patch Sweatshirt",
        price: 34900,
        image:
            "https://cafe24.poxo.com/ec01/whoaukr/3JPAsJn/jGkesyYvH/tEacJ//FpiOmI0G0IBVoMAo1XCOUL3mT6Caj09FWLKVeGQ1kJx/IhRfpWw9NNnns5vjA==/_/web/product/big/202602/6a7e86bb7eb5dd2784faed793c87c80a.jpg",
      ),
    ),
  ]),
  LiveCompareMall("Aritzia", [
    LiveCompareProduct(
      "https://www.aritzia.com/intl/en/product/cinch-jacket/130882.html?color=28150",
      live: LiveCompareExpected(
        name: "Cinch Jacket - City Twill",
        price: 360100,
        image:
            "https://assets.aritzia.com/image/upload/c_crop,ar_1920:2623,g_south/q_auto,f_auto,dpr_auto,w_1800/f26_a04_130882_28150_on_a",
      ),
    ),
    LiveCompareProduct(
      "https://www.aritzia.com/intl/en/product/the-lodge-pant/118495.html?color=11420",
      live: LiveCompareExpected(
        name: "The Lodge Pant™ - Crepette™",
        price: 211500,
        image:
            "https://assets.aritzia.com/image/upload/c_crop,ar_1920:2623,g_south/q_auto,f_auto,dpr_auto,w_1800/f26_a06_118495_11420_on_a",
      ),
    ),
    LiveCompareProduct(
      "https://www.aritzia.com/intl/en/product/ensemble-pant/132922.html?color=37627",
      live: LiveCompareExpected(
        name: "Ensemble Pant - Crepette™",
        price: 226800,
        image:
            "https://assets.aritzia.com/image/upload/c_crop,ar_1920:2623,g_south/q_auto,f_auto,dpr_auto,w_1800/f26_a06_132922_37627_on_a",
      ),
    ),
  ]),
  LiveCompareMall("노이아고", [
    LiveCompareProduct(
      "https://noirer.com/product/detail.html?product_no=2497",
      live: LiveCompareExpected(
        name: "코튼 롱 슬리브리스 티셔츠 (차콜)",
        price: 65000,
        image:
            "https://noirer.com/web/product/big/202608/094b8074ab4cdc63466a77a92e2b227b.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://noirer.com/product/detail.html?product_no=2496",
      live: LiveCompareExpected(
        name: "코튼 롱 슬리브리스 티셔츠 (아이보리)",
        price: 65000,
        image:
            "https://noirer.com/web/product/big/202608/8603d67bd5ee124e83e36c2ef5c6ef78.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://noirer.com/product/detail.html?product_no=2495",
      live: LiveCompareExpected(
        name: "코튼 롱 슬리브리스 티셔츠 (멜란지그레이)",
        price: 65000,
        image:
            "https://noirer.com/web/product/big/202608/85b4975a54e03a70f7554f8e9d796640.jpg",
      ),
    ),
  ]),
  LiveCompareMall("립합", [
    LiveCompareProduct(
      "https://liphop.com/product/detail.html?product_no=17844",
      live: LiveCompareExpected(
        name: "KIM BAG Shoulder Silver",
        price: 385000,
        image:
            "https://liphop.com/web/product/big/202404/43c0297f7308640505e6eaa364c2f4a4.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://liphop.com/product/detail.html?product_no=17843",
      live: LiveCompareExpected(
        name: "KIM BAG Shoulder Black",
        price: 385000,
        image:
            "https://liphop.com/web/product/big/202404/303f5edb1a769af549b58e160c40bdcd.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://liphop.com/product/detail.html?product_no=17827",
      live: LiveCompareExpected(
        name: "BIG RIBBON SWEATSHIRT Cream",
        price: 115000,
        image:
            "https://liphop.com/web/product/big/202404/d5e52403a289802dbedd1ce2b0b2a44d.jpg",
      ),
    ),
  ]),
  LiveCompareMall("마하그리드", [
    LiveCompareProduct(
      "https://mahagrid.com/product/detail.html?product_no=3853",
      live: LiveCompareExpected(
        name: "TWO POCKET BACKPACK[BLACK]",
        price: 99000,
        image:
            "https://mahagrid.com/web/product/big/202302/e1a99120e5e831f2c8797bce813c1a06.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://mahagrid.com/product/detail.html?product_no=3854",
      live: LiveCompareExpected(
        name: "THIRD LOGO BACKPACK[BLACK]",
        price: 109000,
        image:
            "https://mahagrid.com/web/product/big/202602/c9908ec067fc6dd75124f9ed69c164a7.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://mahagrid.com/product/detail.html?product_no=3909",
      live: LiveCompareExpected(
        name: "CORP TEE[BLACK]",
        price: 39000,
        image:
            "https://mahagrid.com/web/product/big/202404/31ecada2304b90e5db954a98e12d2eb5.jpg",
      ),
    ),
  ]),
  LiveCompareMall("비바스튜디오", [
    LiveCompareProduct(
      "https://vivastudio.co.kr/product/detail.html?product_no=5476",
      live: LiveCompareExpected(
        name: "BARRIO LEATHER STADIUM JACKET [BLACK]",
        price: 179000,
        image:
            "https://vivastudio.co.kr/web/product/big/202502/3d6153bdd40066d2c23d5c273ab0619c.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://vivastudio.co.kr/product/detail.html?product_no=5478",
      live: LiveCompareExpected(
        name: "BARRIO SINGLE RIDER JACKET [BLACK]",
        price: 179000,
        image:
            "https://vivastudio.co.kr/web/product/big/202502/62fbf2039cbba4140b8db521b7f22e5c.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://vivastudio.co.kr/product/detail.html?product_no=5546",
      live: LiveCompareExpected(
        name: "WOMAN BARRIO SINGLE RIDER JACKET [BLACK]",
        price: 179000,
        image:
            "https://vivastudio.co.kr/web/product/big/202502/77fc82420411ae80ad09462a809f7654.jpg",
      ),
    ),
  ]),
  LiveCompareMall("아모멘토", [
    LiveCompareProduct(
      "https://amomento.co/product/detail.html?product_no=1642",
      live: LiveCompareExpected(
        name: "BUTTON NECK KNIT (2COLORS)",
        price: 249000,
        image:
            "https://cafe24.poxo.com/ec01/amomentoweb/S6XixLXKQIBS6XUNf2tKGojORIH3PPuABxGbuJPvDdnCZ/1q6lF/ulSM9K1X+EnNoFwo9ozOPtj4s2Rf+txSew==/_/web/product/big/202501/1652618da0b72a1a986b47a538eb7666.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://amomento.co/product/detail.html?product_no=1863",
      live: LiveCompareExpected(
        name: "HOODED DOWN PUFFER (2COLORS)",
        price: 529000,
        image:
            "https://cafe24.poxo.com/ec01/amomentoweb/S6XixLXKQIBS6XUNf2tKGojORIH3PPuABxGbuJPvDdnCZ/1q6lF/ulSM9K1X+EnNoFwo9ozOPtj4s2Rf+txSew==/_/web/product/big/202501/217c11f29b2adb120f10ca04b9dfb6f3.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://amomento.co/product/detail.html?product_no=1866",
      live: LiveCompareExpected(
        name: "[EXCLUSIVE] CROPPED DOWN PUFFER (2COLORS)",
        price: 479000,
        image:
            "https://cafe24.poxo.com/ec01/amomentoweb/S6XixLXKQIBS6XUNf2tKGojORIH3PPuABxGbuJPvDdnCZ/1q6lF/ulSM9K1X+EnNoFwo9ozOPtj4s2Rf+txSew==/_/web/product/big/202501/84463cf683cb2fc45c116d9838c45968.jpg",
      ),
    ),
  ]),
  LiveCompareMall("앤더슨벨", [
    LiveCompareProduct(
      "https://www.anderssonbell.com/product/detail.html?product_no=10279",
      live: LiveCompareExpected(
        name: "DENIM TROMPE L`OEIL PLEATS LONG SKIRT apa766w(BLUE)",
        price: 548000,
        image:
            "https://www.anderssonbell.com/web/product/big/202508/706e61a33cb004e663baac606c0f21a6.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.anderssonbell.com/product/detail.html?product_no=10280",
      live: LiveCompareExpected(
        name: "DENIM TROMPE L`OEIL LAYERED TYING PANTS apa768w(WASHED BLUE)",
        price: 450000,
        image:
            "https://www.anderssonbell.com/web/product/big/202409/84874fa56159bb7dd761a7d003174c8e.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.anderssonbell.com/product/detail.html?product_no=10018",
      live: LiveCompareExpected(
        name: "DENIM COMBO RACING LEATHER SKIRTS apa704w(BROWN)",
        price: 395000,
        image:
            "https://www.anderssonbell.com/web/product/big/202508/e1261775cac1a1bdf36e2725fab8a6c9.jpg",
      ),
    ),
  ]),
  LiveCompareMall("예일", [
    LiveCompareProduct(
      "https://yaleapparel.co.kr/product/detail.html?product_no=18328",
      live: LiveCompareExpected(
        name: "체크 투톤아치 티셔츠_라이트 그레이",
        price: 25900,
        image:
            "https://yaleapparel.co.kr/web/product/big/202604/e15657e2c7d81d50d15d5d9b1a6c5220.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://yaleapparel.co.kr/product/detail.html?product_no=18538",
      live: LiveCompareExpected(
        name: "[SET] 우먼즈 크롭 아플리케 반팔티셔츠 + 우먼즈 아플리케 숏팬츠",
        price: 88000,
        image:
            "https://yaleapparel.co.kr/web/product/big/202606/6793a7cfb36ae9579c1dcc11c2c52e59.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://yaleapparel.co.kr/product/detail.html?product_no=18534",
      live: LiveCompareExpected(
        name: "[1+1] 체크 투톤아치 티셔츠 + 우먼즈 시어서커 체크 투톤 아치 티셔츠",
        price: 99800,
        image:
            "https://yaleapparel.co.kr/web/product/big/202606/31db2eb67a4e1f3165f0e9879df9ca11.jpg",
      ),
    ),
  ]),
  LiveCompareMall("위드윤", [
    LiveCompareProduct(
      "https://withyoon.com/product/detail.html?product_no=19325",
      live: LiveCompareExpected(
        name: "오닉 코튼 보트넥 나시",
        price: 23900,
        image:
            "https://cafe24img.poxo.com/choiwjddbs/web/product/big/202607/8c49c33503f5da4d7ff0787df0857231.webp",
      ),
    ),
    LiveCompareProduct(
      "https://withyoon.com/product/detail.html?product_no=19333",
      live: LiveCompareExpected(
        name: "[💛여름데일리추천] 홀터 캡내장 나시",
        price: 19800,
        image:
            "https://cafe24img.poxo.com/choiwjddbs/web/product/big/202607/ed806c10535ebc5a4f29b59e83ceba2c.webp",
      ),
    ),
    LiveCompareProduct(
      "https://withyoon.com/product/detail.html?product_no=19251",
      live: LiveCompareExpected(
        name: "[🚚오늘출고] [🏆BestSelling][자체제작] 썸머 핀턱 와이드 슬랙스",
        price: 52000,
        image:
            "https://cafe24img.poxo.com/choiwjddbs/web/product/big/202605/c1601edebbec34fb4b84df715df98daf.webp",
      ),
    ),
  ]),
  LiveCompareMall("패션플러스", [
    LiveCompareProduct(
      "https://www.fashionplus.co.kr/goods/detail/423666368",
      live: LiveCompareExpected(
        name: "[아울렛] 케어 면혼방 패턴 드레스 반팔셔츠_DMP2SHDL161G1",
        price: 69000,
        image:
            "https://img.fashionplus.co.kr/mall/assets/product_img/41710/plg41710_DMP2SHDL161G167.jpg?RS=400x536&AR=0",
      ),
    ),
    LiveCompareProduct(
      "https://www.fashionplus.co.kr/goods/detail/424922346",
      live: LiveCompareExpected(
        name: "[아울렛] 케어 면혼방 스몰체크 캐주얼 반팔셔츠 레귤러핏_DMS2SHCS104R1",
        price: 69000,
        image:
            "https://img.fashionplus.co.kr/mall/assets/product_img/41710/plg41710_DMS2SHCS104R167.jpg?RS=400x536&AR=0",
      ),
    ),
    LiveCompareProduct(
      "https://www.fashionplus.co.kr/goods/detail/424878197",
      live: LiveCompareExpected(
        name: "트렌치 크롭 자켓 MYCAWY8070_ESC",
        price: 169150,
        image:
            "https://img.fashionplus.co.kr/mall/assets/product_img/721893/plg721893_MYCAWY8070.jpg?RS=400x536&AR=0",
      ),
    ),
  ]),
  LiveCompareMall("프롬비기닝", [
    LiveCompareProduct(
      "https://frombeginning.co.kr/product/detail.html?product_no=22012",
      live: LiveCompareExpected(
        name: "[MADE]페이퍼 후드 바람막이 점퍼",
        price: 80000,
        image:
            "https://ecimg.cafe24img.com/pg1985b57457872046/frombegining/web/product/big/20260810/c7afff9b16e97d72afc2a73b2e1198a6.gif",
      ),
    ),
    LiveCompareProduct(
      "https://frombeginning.co.kr/product/detail.html?product_no=22023",
      live: LiveCompareExpected(
        name: "보트넥 셔링 롱슬리브 티셔츠",
        price: 39000,
        image:
            "https://ecimg.cafe24img.com/pg1985b57457872046/frombegining/web/product/big/20260807/a5d68111d7ff6a08ed006a54e4dad302.gif",
      ),
    ),
    LiveCompareProduct(
      "https://frombeginning.co.kr/product/detail.html?product_no=21574",
      live: LiveCompareExpected(
        name: "[긴팔/반팔]레이어 버튼 브이 니트",
        price: 45000,
        image:
            "https://ecimg.cafe24img.com/pg1985b57457872046/frombegining/web/product/big/20260819/5fb915baa5bac76b2ad8e0312d7fb993.gif",
      ),
    ),
  ]),
  LiveCompareMall("나이키", [
    LiveCompareProduct(
      "https://www.nike.com/kr/t/acg-%EB%8F%8C%EB%A1%9C%EB%AF%B8%ED%8B%B0-%EC%BD%94%EB%93%80%EB%A1%9C%EC%9D%B4-%EC%9E%AC%ED%82%B7-6afaYkrC/IM4254-104",
      live: LiveCompareExpected(
        name: "ACG '돌로미티' 코듀로이 재킷",
        price: 189000,
        image:
            "https://static.nike.com/a/images/t_default/u_9ddf04c7-2a9a-4d76-add1-d15af8f0263d,c_scale,fl_relative,w_1.0,h_1.0,fl_layer_apply/02416b55-9304-42b2-95fc-12ff75aada31/AS+U+ACG+DOLOMITI+YUNNAN+CORD.png",
      ),
    ),
    LiveCompareProduct(
      "https://www.nike.com/kr/t/acg-%EB%8F%8C%EB%A1%9C%EB%AF%B8%ED%8B%B0-%EC%BD%94%EB%93%80%EB%A1%9C%EC%9D%B4-%EC%87%BC%EC%B8%A0-wqfRDNM2/IM4222-104",
      live: LiveCompareExpected(
        name: "ACG '돌로미티' 코듀로이 쇼츠",
        price: 115000,
        image:
            "https://static.nike.com/a/images/t_default/u_9ddf04c7-2a9a-4d76-add1-d15af8f0263d,c_scale,fl_relative,w_1.0,h_1.0,fl_layer_apply/1ca8ce9e-fa71-4dd0-a7ec-722906e781da/AS+U+ACG+DOLOMITI+YUNNAN+CRD+S.png",
      ),
    ),
    LiveCompareProduct(
      "https://www.nike.com/kr/t/%EB%82%98%EC%9D%B4%ED%82%A4-%ED%8E%98%EA%B0%80%EC%88%98%EC%8A%A4-42-%EC%97%AC%EC%84%B1-%EB%A1%9C%EB%93%9C-%EB%9F%AC%EB%8B%9D%ED%99%94-J3FQiYIc/IB1881-106",
      live: LiveCompareExpected(
        name: "나이키 페가수스 42 여성 로드 러닝화",
        price: 169000,
        image:
            "https://static.nike.com/a/images/t_default/u_9ddf04c7-2a9a-4d76-add1-d15af8f0263d,c_scale,fl_relative,w_1.0,h_1.0,fl_layer_apply/522aebea-2c93-411d-a8ef-cad78715368a/W+NIKE+AIR+ZOOM+PEGASUS+42.png",
      ),
    ),
  ]),
  LiveCompareMall("올리브영", [
    LiveCompareProduct(
      "https://www.oliveyoung.co.kr/store/goods/getGoodsDetail.do?goodsNo=A000000260600",
      live: LiveCompareExpected(
        name: "[리뷰이벤트/트러블1등] 셀라딕스 세범 리밸런싱 131 앰플 30ml 기획 (+미니언즈 키링) (미니언즈 콜라보)",
        price: 28900,
        image:
            "https://image.oliveyoung.co.kr/cfimages/cf-goods/uploads/images/thumbnails/10/0000/0026/A00000026060006ko.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.oliveyoung.co.kr/store/goods/getGoodsDetail.do?goodsNo=A000000262781",
      live: LiveCompareExpected(
        name: "프로티원 단백질쉐이크 파우치형 40g 7입 6종",
        price: 25900,
        image:
            "https://image.oliveyoung.co.kr/cfimages/cf-goods/uploads/images/thumbnails/10/0000/0026/A00000026278108ko.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.oliveyoung.co.kr/store/goods/getGoodsDetail.do?goodsNo=A000000250742",
      live: LiveCompareExpected(
        name: "[긴장완화] 대원제약 대원헬스 스트레스샷 20g x 12포 (+2포 증정) (14일분)",
        price: 23900,
        image:
            "https://image.oliveyoung.co.kr/cfimages/cf-goods/uploads/images/thumbnails/10/0000/0025/A00000025074205ko.jpg",
      ),
    ),
  ]),
  LiveCompareMall("퀸잇", [
    LiveCompareProduct(
      "https://web.queenit.kr/product/421b849e05731238976b9f01d96c7e31",
      live: LiveCompareExpected(
        name: "[M,L 사이즈/벨트세트]반팔 데님 원피스(하객룩, 하객원피스)",
        price: 32900,
        image:
            "https://image.queenit.kr/product/asset/v1/upload/04120430d08047c38524a66065b43ca2.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://web.queenit.kr/product/360e9e7089a6346d2e9b5de2b2d8e121",
      live: LiveCompareExpected(
        name: "[비버리힐스폴로클럽]여성 케이블 라운드 니트 폴로 가디건 TK001 _A",
        price: 33900,
        image:
            "https://imgs.kshop.co.kr/d2/emc/goods/openmarket/queenit/5250535/5250535_20250421165441.png",
      ),
    ),
    LiveCompareProduct(
      "https://web.queenit.kr/product/b52c66c75291c8ef4d9f136282cac90c",
      live: LiveCompareExpected(
        name: "모에나 레이어 가디건",
        price: 35900,
        image:
            "https://irisccc.cafe24.com/web/upload/NNEditor/20260316/8f6ebe26042b013dbd95d700f5d3abfe.jpg",
      ),
    ),
  ]),
  LiveCompareMall("브랜디", [
    LiveCompareProduct(
      "https://www.brandi.co.kr/products/183024247",
      live: LiveCompareExpected(
        name: "스투시 베이직 반팔티셔츠",
        price: 28860,
        image:
            "https://image.brandi.co.kr/cproduct/BRANDI/2026/05/30/201de78f-3983-4de6-ae6a-b5d95e741d96/SB000000000178449059_1780141951_image1_S.webp",
      ),
    ),
    LiveCompareProduct(
      "https://www.brandi.co.kr/products/179256288",
      live: LiveCompareExpected(
        name: "[갓성비/감성색감]에어컨 바람막기, 감성 잔줄 스트라이프 빈티지 오버핏 셔츠 남방",
        price: 22900,
        image:
            "https://image.brandi.co.kr/cproduct/BRANDI/2025/06/18/3bf427ba-f0d8-47f1-ae4f-b636054f3027/SB000000000174538297_1750239057_image1_S.webp",
      ),
    ),
    LiveCompareProduct(
      "https://www.brandi.co.kr/products/106329458",
      live: LiveCompareExpected(
        name:
            "(당일출고/하객룩) 반팔 오프숄더 스퀘어넥 블랙 퍼프 셔링 A라인 페플럼 플레어 크롭 면접 블라우스 여름 썸머 셔츠 휴가룩 바캉스룩 휴양지룩 페스티벌룩 4color_8926",
        price: 19920,
        image:
            "https://image.brandi.co.kr/cproduct/2023/05/25/SB000000000099464494_1684995009_image1_S.webp",
      ),
    ),
  ]),
  LiveCompareMall("CJ온스타일", [
    LiveCompareProduct(
      "https://display.cjonstyle.com/p/item/2082445074?channelCode=30002002",
      live: LiveCompareExpected(
        name: "[론칭] PRE-FALL 실크100 쉬머 레이어드 스카프",
        price: 169000,
        image:
            "http://itemimage.cjonstyle.net/goods_images/20/074/2082445074L.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://display.cjonstyle.com/p/item/2070029628?channelCode=30002002",
      live: LiveCompareExpected(
        name: "최신상 배종옥 레몬꿀팩 레몬허니워시오프팩 6통+타올1매",
        price: 99000,
        image:
            "http://itemimage.cjonstyle.net/goods_images/20/628/2070029628L.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://display.cjonstyle.com/p/item/2018074756?channelCode=30002002",
      live: LiveCompareExpected(
        name: "신라명과 호밀빵 430g 3봉",
        price: 15500,
        image:
            "http://itemimage.cjonstyle.net/goods_images/20/756/2018074756L.jpg",
      ),
    ),
  ]),
  LiveCompareMall("4910", [
    LiveCompareProduct(
      "https://4910.kr/goods/44678113",
      live: LiveCompareExpected(
        name: "그루브스텝 [2PACK] 1+1 랩스타미니 라운드 반팔 티셔츠 S0217 - 4910 | 사고 싶은 스타일의 발견",
        price: 34800,
        image:
            "https://d3ha2047wt6x28.cloudfront.net/FA45r5mdpZY/pr:GOODS_DETAIL/czM6Ly9hYmx5LWltYWdlLWxlZ2FjeS9kYXRhL2dvb2RzLzIwMjYwNTIyXzE3Nzk0NTI1Mjg0MTgwOTdtLnBuZw",
      ),
    ),
    LiveCompareProduct(
      "https://4910.kr/goods/71195041",
      live: LiveCompareExpected(
        name: "모즈모즈 [단독1+1] 무지 배색 롤업 반팔티셔츠 - 4910 | 사고 싶은 스타일의 발견",
        price: 47200,
        image:
            "https://d3ha2047wt6x28.cloudfront.net/YL2tLW-EPb0/pr:GOODS_DETAIL/czM6Ly9hYmx5LWltYWdlLWxlZ2FjeS9kYXRhL2dvb2RzLzIwMjYwNjE4XzE3ODE3NjU3OTQ1MzAyMDJtLmpwZw",
      ),
    ),
    LiveCompareProduct(
      "https://4910.kr/goods/3954236",
      live: LiveCompareExpected(
        name: "플루크 캠퍼밴 투어 피그먼트 반팔티셔츠 FST710 / 4color W - 4910 | 사고 싶은 스타일의 발견",
        price: 20800,
        image:
            "https://d3ha2047wt6x28.cloudfront.net/z6T_-U60HFk/pr:GOODS_DETAIL/czM6Ly9hYmx5LWltYWdlLWxlZ2FjeS9kYXRhL2dvb2RzLzIwMjMwODA5XzE2OTE1NjQwMDAwMzI1MTZtLmpwZw",
      ),
    ),
  ]),
  LiveCompareMall("SSF샵", [
    LiveCompareProduct(
      "https://www.ssfshop.com/GOOD-ON/GPCX21040888339/good",
      live: LiveCompareExpected(
        name: "굿온 피그먼트 다잉 베이스볼 티셔츠 - 네츄럴",
        price: 63360,
        image:
            "https://img.ssfshop.com/cmd/LB_750x1000/src/https://img.ssfshop.com/goods/ORBR/21/04/08/GPCX21040888339_0_THNAIL_ORGINL_20240503185548877.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.ssfshop.com/GOOD-ON/GPCX21031513266/good",
      live: LiveCompareExpected(
        name: "굿온 피그먼트 다잉 베이스볼 티셔츠 - 바나나",
        price: 63360,
        image:
            "https://img.ssfshop.com/cmd/LB_750x1000/src/https://img.ssfshop.com/goods/ORBR/21/03/15/GPCX21031513266_0_ORGINL_20220708125043755.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.ssfshop.com/GOOD-ON/GPCX22072270530/good",
      live: LiveCompareExpected(
        name: "굿온 피그먼트 다잉 베이스볼 티셔츠 - 세이지",
        price: 63360,
        image:
            "https://img.ssfshop.com/cmd/LB_750x1000/src/https://img.ssfshop.com/goods/ORBR/22/07/22/GPCX22072270530_0_ORGINL_20230428144836311.jpg",
      ),
    ),
  ]),
  LiveCompareMall("이랜드몰", [
    LiveCompareProduct(
      "https://www.elandmall.co.kr/i/item?itemNo=2602298723&lowerVendNo=LV16003579",
      live: LiveCompareExpected(
        name: "[UV차단] 라이트 후드 윈드브레이커_SPJJG25G01",
        price: 19900,
        image:
            "https://item.elandrs.com/r/image/item/2026-04-22/f1577af4-cab8-4724-9c5e-667913640b55.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.elandmall.co.kr/i/item?itemNo=2603331622&lowerVendNo=LV16003579",
      live: LiveCompareExpected(
        name: "[ACTIVE] 라이트 시어 후드 크롭 윈드브레이커_SPJJG37G02",
        price: 19900,
        image:
            "https://item.elandrs.com/r/image/item/2026-08-18/63f4c858-7d4b-4345-a5d1-6e891a03b526.jpg",
      ),
    ),
    LiveCompareProduct(
      "https://www.elandmall.co.kr/i/item?itemNo=2602306879&lowerVendNo=LV16003579",
      live: LiveCompareExpected(
        name: "[UV차단] 라이트 패커블 윈드브레이커_SPJJG25C09",
        price: 19900,
        image:
            "https://item.elandrs.com/r/image/item/2026-02-27/e9a8ccfd-8a4d-4dbe-aae8-e0070ca47149.jpg",
      ),
    ),
  ]),
];
