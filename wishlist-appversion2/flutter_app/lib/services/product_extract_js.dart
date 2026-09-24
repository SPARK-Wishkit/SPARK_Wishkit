/// WebView(안 보이는 브라우저) 안에서 실행되는 상품정보 추출 스크립트.
///
/// 서버 엔진(Tier 2)이 못 얻는 것을 단말에서 얻기 위한 것이라, 페이지의 JS가
/// JSON-LD/가격을 채운 "뒤"의 렌더된 DOM에서 뽑는다. 데스크톱 프로토타입에서
/// 검증한 로직을 그대로 옮겼다:
///   1) JSON-LD(Product / ProductGroup+hasVariant) — 서버 파서가 놓치는 ProductGroup 포함
///   2) Open Graph 메타
///   3) 범용 DOM (h1 상품명, 첫 가격 "12,345원" 또는 "₩12,345")
///   4) 쇼핑몰 전용 가격 의미 규칙(확인 실패 시 관리 도메인은 안전하게 기권)
///
/// 결과는 JSON 문자열로 반환한다(플랫폼 간 evaluateJavascript 반환형 차이를 흡수).
const String productExtractJs = r'''
(function () {
  function asArray(v){ return v==null ? [] : (Array.isArray(v)?v:[v]); }
  function firstStr(v){
    if(v==null) return null;
    if(typeof v==='string') return v.trim()||null;
    if(Array.isArray(v)){ for(var i=0;i<v.length;i++){ var s=firstStr(v[i]); if(s) return s; } return null; }
    if(typeof v==='object') return firstStr(v.name)||firstStr(v.url)||null;
    return String(v);
  }
  function toPrice(x){
    if(x==null) return null;
    if(typeof x==='number') return x>0?Math.round(x):null;
    var s=String(x).replace(/[^0-9.]/g,'');
    if(!s) return null;
    var n=Math.round(parseFloat(s));
    return (isFinite(n)&&n>0)?n:null;
  }
  function normalizeUrl(value){
    var s=firstStr(value); if(!s) return null;
    s=s.replace(/&amp;/gi,'&').trim();
    // 일부 Cafe24 JSON-LD가 절대 URL 앞에 현재 프로토콜을 한 번 더 붙인다.
    s=s.replace(/^https?:https?:\/\//i,'https://');
    if(/^\/\//.test(s)) s=location.protocol+s;
    // HTTPS 상품 페이지의 HTTP 대표 이미지는 Android mixed-content에 막히므로
    // 동일 리소스의 HTTPS 주소를 우선 사용한다.
    if(location.protocol==='https:'&&/^http:\/\//i.test(s))s='https://'+s.slice(7);
    try{
      var u=new URL(s,location.href);
      return /^https?:$/.test(u.protocol)?u.href:null;
    }catch(e){return null;}
  }

  // ---- JSON-LD ----
  var nodes=[];
  var scripts=document.querySelectorAll('script[type="application/ld+json"]');
  for(var i=0;i<scripts.length;i++){
    var txt=scripts[i].textContent; if(!txt) continue;
    try{
      var stack=[JSON.parse(txt)];
      while(stack.length){
        var node=stack.pop();
        if(Array.isArray(node)){ for(var j=0;j<node.length;j++) stack.push(node[j]); }
        else if(node && typeof node==='object'){
          nodes.push(node);
          if(Array.isArray(node['@graph'])) for(var k=0;k<node['@graph'].length;k++) stack.push(node['@graph'][k]);
        }
      }
    }catch(e){}
  }
  function isProduct(node){
    var t=node['@type']; var ts=Array.isArray(t)?t:[t];
    for(var i=0;i<ts.length;i++){ if(typeof ts[i]==='string' && /product/i.test(ts[i])) return true; }
    return false;
  }
  function priceTypeText(value){
    return asArray(value).map(function(v){ return String(v||'').toLowerCase().replace(/[ _]/g,''); }).join(' ');
  }
  function isListPrice(value){ return /listprice|strikethroughprice|regularprice|msrp/.test(priceTypeText(value)); }
  function isConditional(value){ return /coupon|member|membership|loyalty|subscription|voucher|promo/.test(priceTypeText(value)); }
  function offerIsConditional(o){
    return !!(o && (isConditional(o.priceType) || o.validForMemberTier || o.membershipPointsEarned));
  }
  function collectPrices(node){
    var offers=[].concat(asArray(node.offers));
    asArray(node.hasVariant).forEach(function(v){ offers=offers.concat(asArray(v.offers)); });
    var salePrices=[], listPrices=[], currency=null;
    offers.forEach(function(o){
      if(!o||typeof o!=='object'||offerIsConditional(o)) return;
      if(!currency) currency=firstStr(o.priceCurrency);
      [o.price,o.lowPrice].forEach(function(p){ var n=toPrice(p); if(n) salePrices.push(n); });
      [o.listPrice,o.originalPrice,o.priceBeforeDiscount].forEach(function(p){ var n=toPrice(p); if(n) listPrices.push(n); });
      asArray(o.priceSpecification).forEach(function(s){
        if(!s || isConditional(s.priceType) || offerIsConditional(s)) return;
        var n=toPrice(s.price||s.priceAmount); if(!n) return;
        (isListPrice(s.priceType)?listPrices:salePrices).push(n);
      });
    });
    var sale=salePrices.length?Math.min.apply(null,salePrices):null;
    var originals=listPrices.filter(function(n){ return sale==null || n>sale; });
    return {sale:sale, original:originals.length?Math.min.apply(null,originals):null, currency:currency};
  }
  var ld=null;
  for(var i=0;i<nodes.length;i++){
    if(!isProduct(nodes[i])) continue;
    var nm=firstStr(nodes[i].name); if(!nm) continue;
    var cp=collectPrices(nodes[i]);
    ld={ name:nm, brand:firstStr(nodes[i].brand), image:firstStr(nodes[i].image),
         price:cp.sale, originalPrice:cp.original, currency:cp.currency };
    break;
  }

  // ---- Open Graph ----
  function meta(keys){
    var ms=document.querySelectorAll('meta');
    for(var i=0;i<ms.length;i++){
      var key=(ms[i].getAttribute('property')||ms[i].getAttribute('name')||'').toLowerCase();
      if(keys.indexOf(key)>=0){ var c=ms[i].getAttribute('content'); if(c && c.trim()) return c.trim(); }
    }
    return null;
  }
  var ogTitle=meta(['og:title','twitter:title']);
  var ogImage=normalizeUrl(meta(['og:image','og:image:url','twitter:image']));
  var ogBasePrice=toPrice(meta(['product:price:amount','og:price:amount']));
  var ogSalePrice=toPrice(meta(['product:sale_price:amount','og:sale_price:amount']));
  var ogNormalPrice=toPrice(meta(['product:original_price:amount','og:original_price:amount','product:price:normal_price']));
  var ogPrice=ogSalePrice||ogBasePrice;
  var ogOriginalPrice=ogNormalPrice;
  if(ogSalePrice && ogBasePrice && ogBasePrice>ogSalePrice) ogOriginalPrice=ogBasePrice;
  if(ogOriginalPrice && ogPrice && ogOriginalPrice<=ogPrice) ogOriginalPrice=null;
  var ogSite=meta(['og:site_name']);
  var ogType=(meta(['og:type'])||'').toLowerCase();

  function looksLikeProductDetail(){
    if(ld || ogType==='product' || ogType.indexOf('product.')===0) return true;
    var target=decodeURIComponent(location.pathname+location.search);
    if(/(^|\.)hm\.com$/i.test(location.hostname)) return /\/productpage\.\d+\.html$/i.test(location.pathname);
    if(/(^|\.)hmall\.com$/i.test(location.hostname)) return /itemPtc|slitmCd=/i.test(target);
    if(/(^|\.)elandmall\.co\.kr$/i.test(location.hostname)) return /\/i\/item|itemNo=/i.test(target);
    if(/(^|\.)vans\.co\.kr$/i.test(location.hostname)) return /\/PRODUCT\//i.test(location.pathname);
    if(/(^|\.)nike\.com$/i.test(location.hostname)) return /\/t\/[^/?#]+/i.test(location.pathname);
    if(/\/(search|category|categories|collections?|login|member|customer|account|board|event(_list)?|archive|project(_list)?|features|recent_view_product|image_zoom\d*|lookbook([-_]detail|_list)?|magazine_list|editorial|flashsale|ranking_daily|group-mall|sale-zone|new|collection\d*|men(_all)?|women(_all|_fit)?|item-shop|shop|journal|index|best)(\.|\/|\?|$)|products?\/(list|search)|gift_card|returnUrl=|['"]?%?20?\s*\+\s*link/i.test(target)) return false;
    return /\/products?\/[^/?#]+|\/goods?\/(detail\/)?[^/?#]+|\/productpage\.\d+\.html|\/product\/detail\.html|\/product\/[^/?#]+\/\d+|\/p\/product\/[^/?#]+|\/items?\/itemview|(?:product_no|itemId|goods_id|pid|PROD_CD)=/i.test(target);
  }
  var productDetail=looksLikeProductDetail();

  // ---- 범용 DOM (JSON-LD/OG가 없을 때) ----
  function domName(){
    var h=document.querySelector('h1');
    if(h){ var t=(h.textContent||'').replace(/\s+/g,' ').trim(); if(t.length>=2 && t.length<=140) return t; }
    return null;
  }
  function domPricePair(){
    var sales=[], originals=[], seen={};
    var elements=document.body?document.body.querySelectorAll('*'):[];
    for(var i=0;i<elements.length;i++){
      var el=elements[i];
      if(/SCRIPT|STYLE|NOSCRIPT|SVG/.test(el.tagName)) continue;
      var style=getComputedStyle(el);
      if(style.display==='none'||style.visibility==='hidden'||Number(style.opacity)===0) continue;
      var text=(el.textContent||'').replace(/\s+/g,' ').trim();
      if(!text||text.length>160) continue;
      var re=/([0-9]{1,3}(?:,[0-9]{3})+)\s*원|₩\s?([0-9]{1,3}(?:,[0-9]{3})+)/g,m;
      while((m=re.exec(text))){
        var val=toPrice(m[1]||m[2]); if(val==null||val<1000) continue;
        var local=text.slice(Math.max(0,m.index-24),m.index+m[0].length+24);
        var nearby=((el.previousElementSibling&&el.previousElementSibling.textContent)||'')+' '+local;
        if(/쿠폰|회원|멤버|등급|로그인|첫\s*구매|신규|카드|적립|포인트|앱\s*전용|구독|최대\s*혜택/i.test(nearby)) continue;
        if(/배송|무료배송|이상\s*구매|최소\s*주문|사은품/i.test(nearby)) continue;
        var cls=(el.className&&typeof el.className==='string')?el.className:'';
        var struck=(style.textDecorationLine||'').indexOf('line-through')>=0;
        var original=struck||/정가|정상가|소비자가|기존가|할인\s*전/i.test(nearby);
        var score=(/판매가|할인가|세일가|즉시\s*할인|현재가/i.test(nearby)?50:0)
          +(/price|sale|discount/i.test(cls)?15:0)+(el.tagName==='STRONG'?5:0)-i/100000;
        var key=(original?'o':'s')+val;
        if(seen[key]!=null&&seen[key]>=score) continue;
        seen[key]=score;
        (original?originals:sales).push({value:val,score:score});
      }
    }
    sales.sort(function(a,b){return b.score-a.score;});
    var sale=sales.length?sales[0].value:null;
    var validOriginals=originals.filter(function(x){return sale==null||x.value>sale;});
    validOriginals.sort(function(a,b){return b.score-a.score||a.value-b.value;});
    var original=validOriginals.length?validOriginals[0].value:null;
    if(sale==null&&original!=null){sale=original;original=null;}
    return {price:sale,originalPrice:original};
  }
  // (주의) 데이터레이어의 "price":NNNNN 를 범용으로 긁는 건 위험하다 — 상품 페이지엔
  // 추천/관련 상품 가격이 여러 개라 엉뚱한 값을 고르게 된다. 그런 몰(아디다스 등)은
  // 몰별 전용 규칙이 필요하며, 규칙 전까지는 Tier 3(사용자 입력)으로 안전하게 폴백한다.

  // ---- 조립 ----
  var host=location.hostname;

  // ---- Python 가격 의미 어댑터와 동기화된 1차 쇼핑몰 규칙 ----
  function hostIs(domain){ return host===domain || host.slice(-(domain.length+1))==='.'+domain; }
  function uniqueRows(rows){
    var seen={}, out=[];
    rows.forEach(function(row){ var key=JSON.stringify(row); if(!seen[key]){seen[key]=1;out.push(row);} });
    return out;
  }
  function result(adapter,sale,regular,field,regularField,extra){
    if(!sale||sale<=0||(regular&&regular<sale)) return null;
    var r={adapter:adapter,price:sale,originalPrice:regular||null,
      purchasePriceStatus:'confirmed',priceConfidence:'high',availability:'available',
      optionDependent:null,optionPriceMin:null,optionPriceMax:null,
      purchaseField:field,regularField:regularField||null};
    if(extra) Object.keys(extra).forEach(function(k){r[k]=extra[k];});
    return r;
  }
  function objectAt(text,start){
    var open=text.indexOf('{',start); if(open<0) return null;
    var depth=0, quote=false, esc=false;
    for(var i=open;i<Math.min(text.length,open+8000);i++){
      var c=text[i];
      if(quote){ if(esc)esc=false; else if(c==='\\')esc=true; else if(c==='"')quote=false; continue; }
      if(c==='"')quote=true; else if(c==='{')depth++; else if(c==='}'&&--depth===0)return text.slice(open,i+1);
    }
    return null;
  }
  function pageText(){return (document.body?document.body.innerText:'').replace(/\s+/g,' ').trim();}
  function won(n){return Number(n).toLocaleString('en-US')+'원';}
  function metaOne(name){
    var values=[];document.querySelectorAll('meta[property="'+name+'"]')
      .forEach(function(x){var v=(x.content||'').trim();if(v)values.push(v);});
    values=uniqueRows(values);return values.length===1?values[0]:null;
  }
  function exactType(node,type){
    var values=asArray(node&&node['@type']);return values.indexOf(type)>=0;
  }
  function topJsonLd(){
    var out=[];document.querySelectorAll('script[type="application/ld+json"]').forEach(function(x){
      try{var v=JSON.parse(x.textContent);asArray(v).forEach(function(n){if(n&&typeof n==='object')out.push(n);});}catch(e){}
    });return out;
  }
  function products(){return topJsonLd().filter(function(x){return exactType(x,'Product');});}
  function productOffers(product){return asArray(product&&product.offers).filter(function(x){return x&&typeof x==='object';});}
  function availability(value){return String(value||'').toLowerCase().replace(/[^a-z]/g,'');}
  function liveOfferPrices(offers,requireKrw){
    var values=[];offers.forEach(function(o){
      if(!availability(o.availability).endsWith('instock'))return;
      if(requireKrw&&o.priceCurrency!=='KRW')return;
      if(!requireKrw&&o.priceCurrency&&o.priceCurrency!=='KRW')return;
      var p=toPrice(o.price);if(p)values.push(p);
    });return uniqueRows(values);
  }
  function scriptPrice(name,raw){
    var re=new RegExp('(?:var\\s+)?'+name+'\\s*=\\s*[\\\'\"]?(\\d+(?:\\.\\d+)?)');
    var m=re.exec(raw);return m?toPrice(m[1]):null;
  }
  function liveSelectOptions(){return Array.from(document.querySelectorAll('select[id^="product_option_id"] option')).filter(function(x){return !['','*','**'].includes(String(x.value||''))&&!/품절/.test(x.textContent||'');});}
  function cafe24Offer(adapter,confidence,requireScript){
    var ps=products(), candidates=[];
    ps.forEach(function(p){var os=productOffers(p);if(!firstStr(p.name)||!os.length)return;
      var states=uniqueRows(os.map(function(o){return o.availability;}));
      if(states.some(function(s){return s!=='InStock'&&s!=='OutOfStock';}))return;
      var live=liveOfferPrices(os,false);var liveCount=os.filter(function(o){return o.availability==='InStock';}).length;
      if(live.length&&liveCount===os.filter(function(o){return o.availability==='InStock'&&toPrice(o.price)&&(o.priceCurrency==null||o.priceCurrency==='KRW');}).length)candidates.push(live);
    });
    candidates=uniqueRows(candidates);if(candidates.length!==1)return null;
    var lo=Math.min.apply(null,candidates[0]),hi=Math.max.apply(null,candidates[0]);
    if(requireScript&&scriptPrice('product_price',document.documentElement.innerHTML)!==lo)return null;
    return result(adapter,lo,null,'Product.offers[InStock].price',null,{priceConfidence:confidence||'high',purchasePriceStatus:lo===hi?'confirmed':'option_dependent',optionDependent:lo!==hi,optionPriceMin:lo!==hi?lo:null,optionPriceMax:lo!==hi?hi:null});
  }
  function stripHtmlName(value){
    return String(value||'')
      .replace(/\\u003c/gi,'<')
      .replace(/\\u003e/gi,'>')
      .replace(/<[^>]*>/g,' ')
      .replace(/&amp;/gi,'&')
      .replace(/&nbsp;/gi,' ')
      .replace(/\s+/g,' ')
      .trim();
  }
  function cafe24MetaSale(adapter,label){
    var id=metaOne('product:retailer_item_id'),baseCur=metaOne('product:price:currency'),saleCur=metaOne('product:sale_price:currency');
    var base=toPrice(metaOne('product:price:amount')),sale=toPrice(metaOne('product:sale_price:amount'));
    if(!/^\d+$/.test(id||'')||baseCur!=='KRW'||saleCur!=='KRW'||!base||!sale||base<sale)return null;
    var ps=products(),names=[],sets=[];
    ps.forEach(function(p){
      var n=stripHtmlName(firstStr(p.name));if(n)names.push(n);
      var os=productOffers(p),live=liveOfferPrices(os,true);
      // 노이아고처럼 availability가 비어 있어도 KRW price만 있는 Offer는 meta와 교차검증에 쓴다.
      if(!live.length){
        live=uniqueRows(os.map(function(o){
          if(!o||(o.priceCurrency&&o.priceCurrency!=='KRW'))return null;
          var av=availability(o.availability);
          if(av&&!av.endsWith('instock'))return null;
          return toPrice(o.price);
        }).filter(Boolean));
      }
      if(live.length)sets.push(live.sort(function(a,b){return a-b;}));
    });
    sets=uniqueRows(sets);names=uniqueRows(names);
    var shown=uniqueRows(Array.from(document.querySelectorAll('#span_product_price_text')).map(function(x){return toPrice(x.textContent);}).filter(Boolean));
    var custom=uniqueRows(Array.from(document.querySelectorAll('#span_product_price_custom')).map(function(x){return toPrice(x.textContent);}).filter(Boolean));
    var scriptP=scriptPrice('product_price',document.documentElement?document.documentElement.innerHTML:'');
    var fromLd=false;
    if(sets.length===1){
      if(base!==sale && !sets[0].includes(sale)) return null;
      if(base===sale && !sets[0].includes(base)) return null;
      if(sets[0].length>2) return null;
      fromLd=true;
    }else if(!sets.length){
      // 화면가가 text 또는 custom 한쪽에만 있어도 meta/script와 같으면 확정.
      var display=shown.length===1?shown[0]:(custom.length===1?custom[0]:null);
      if(display==null||display!==sale||(scriptP!=null&&scriptP!==sale))return null;
    }else return null;
    if(!names.length && !shown.length && !custom.length)return null;
    var longest=names.length?names.slice().sort(function(a,b){return b.length-a.length;})[0]:null;
    if(names.length&&names.some(function(n){return longest.indexOf(n)<0;}))return null;
    if(custom.length>1)return null;
    var regular=base>sale?base:(custom.length&&custom[0]>sale?custom[0]:null),text=pageText();
    if(longest){var visibleName=longest.replace(/_/g,' ').replace(/\s+/g,' ').trim();if(text.indexOf(longest)<0&&text.indexOf(visibleName)<0)return null;}
    var saleStr=String(Number(sale));
    var saleStrComma=Number(sale).toLocaleString('en-US');
    var hasSaleText=text.indexOf(saleStrComma)>=0||text.indexOf(saleStr)>=0;
    if(!hasSaleText && !(label&&text.indexOf(label)>=0))return null;
    return result(adapter,sale,regular,fromLd?'product:sale_price:amount + Product.offers[KRW]':'product:sale_price:amount + displayed price',regular===base?'product:price:amount':(regular?'#span_product_price_custom':null),{priceConfidence:'medium',optionDependent:false});
  }
  // 회원가(sale) 대신 정가(product:price / product_price)를 채택. 리·비바 등 회원할인 몰용.
  function cafe24MetaList(adapter,label){
    var id=metaOne('product:retailer_item_id'),baseCur=metaOne('product:price:currency'),saleCur=metaOne('product:sale_price:currency');
    var base=toPrice(metaOne('product:price:amount')),sale=toPrice(metaOne('product:sale_price:amount'));
    if(!/^\d+$/.test(id||'')||baseCur!=='KRW'||!base)return null;
    if(sale!=null&&(saleCur!=='KRW'||base<sale))return null;
    var ps=products(),names=[],sets=[];
    ps.forEach(function(p){
      var n=stripHtmlName(firstStr(p.name));if(n)names.push(n);
      var os=productOffers(p),live=liveOfferPrices(os,true);
      if(!live.length){
        live=uniqueRows(os.map(function(o){
          if(!o||(o.priceCurrency&&o.priceCurrency!=='KRW'))return null;
          var av=availability(o.availability);
          if(av&&!av.endsWith('instock'))return null;
          return toPrice(o.price);
        }).filter(Boolean));
      }
      if(live.length)sets.push(live.sort(function(a,b){return a-b;}));
    });
    sets=uniqueRows(sets);names=uniqueRows(names);
    var shown=uniqueRows(Array.from(document.querySelectorAll('#span_product_price_text')).map(function(x){return toPrice(x.textContent);}).filter(Boolean));
    var custom=uniqueRows(Array.from(document.querySelectorAll('#span_product_price_custom')).map(function(x){return toPrice(x.textContent);}).filter(Boolean));
    var scriptP=scriptPrice('product_price',document.documentElement?document.documentElement.innerHTML:'');
    if(scriptP!=null&&scriptP!==base)return null;
    var fromLd=false;
    var shownOrCustomHasBase=(shown.indexOf(base)>=0)||(custom.indexOf(base)>=0);
    if(sets.length===1){
      if(sets[0].includes(base)){
        if(sets[0].length>2)return null;
        fromLd=true;
      }else if(scriptP===base||shownOrCustomHasBase){
        // LD가 옵션가(하프/롱 등)만 있어도 meta/화면 정가로 확정
        if(sets[0].length>2)return null;
      }else return null;
    }else if(!sets.length){
      var display=shown.length===1?shown[0]:(custom.length===1?custom[0]:null);
      if(display!=null&&display!==base&&(sale==null||display!==sale))return null;
    }else return null;
    if(!names.length&&!shown.length&&!custom.length)return null;
    var longest=names.length?names.slice().sort(function(a,b){return b.length-a.length;})[0]:null;
    if(names.length&&names.some(function(n){return longest.indexOf(n)<0;}))return null;
    if(custom.length>1)return null;
    var text=pageText();
    if(longest){var visibleName=longest.replace(/_/g,' ').replace(/\s+/g,' ').trim();if(text.indexOf(longest)<0&&text.indexOf(visibleName)<0)return null;}
    var baseStr=String(Number(base)),baseComma=Number(base).toLocaleString('en-US');
    var hasBaseText=text.indexOf(baseComma)>=0||text.indexOf(baseStr)>=0;
    if(!hasBaseText&&!(label&&text.indexOf(label)>=0))return null;
    return result(adapter,base,null,fromLd?'product:price:amount + Product.offers[KRW]':'product:price:amount + product_price',null,{priceConfidence:'medium',optionDependent:false});
  }
  function productOfferRule(adapter,guard){
    var ps=products();if(ps.length!==1)return null;var p=ps[0],os=productOffers(p);if(guard&&!guard(p,os))return null;
    var live=liveOfferPrices(os,true);if(!live.length)return null;var lo=Math.min.apply(null,live),hi=Math.max.apply(null,live);
    return result(adapter,lo,null,'Product.offers[InStock, KRW].price',null,{purchasePriceStatus:lo===hi?'confirmed':'option_dependent',optionDependent:lo!==hi,optionPriceMin:lo!==hi?lo:null,optionPriceMax:lo!==hi?hi:null});
  }
  function extractVerifiedSitePricing(){
    var raw=document.documentElement?document.documentElement.innerHTML:'';
    var rows=[], i, state, sale, regular;

    if(hostIs('musinsa.com')){
      var reMus=/"goodsPrice"\s*:\s*\{/g,mMus;
      while((mMus=reMus.exec(raw))){
        try{ state=JSON.parse(objectAt(raw,mMus.index+12)); }catch(e){continue;}
        sale=toPrice(state.salePrice); regular=toPrice(state.normalPrice);
        if(sale&&(!regular||regular>=sale)&&(state.currency==null||state.currency==='KRW')&&(state.type==null||state.type==='DEFAULT')) rows.push([sale,regular]);
      }
      rows=uniqueRows(rows); return rows.length===1?result('musinsa',rows[0][0],rows[0][1],'goodsPrice.salePrice','goodsPrice.normalPrice'):null;
    }

    if(hostIs('wconcept.co.kr')){
      var hs=uniqueRows(Array.from(document.querySelectorAll('input[name="saleprice"]')).map(function(x){return toPrice(x.value);}).filter(Boolean));
      var hr=uniqueRows(Array.from(document.querySelectorAll('input[name="originalPrice"]')).map(function(x){return toPrice(x.value);}).filter(Boolean));
      document.querySelectorAll('input[name^="GA4ItemObj_"]').forEach(function(x){
        try{ state=JSON.parse(x.value); }catch(e){return;}
        sale=toPrice(state.SalePrice); regular=toPrice(state.CustomerPrice);
        var inputCode=(x.name||'').replace(/^GA4ItemObj_/,'');
        if(sale&&(!regular||regular>=sale)&&(state.Currency==null||state.Currency==='KRW')&&(!state.ItemCd||!inputCode||String(state.ItemCd)===inputCode)) rows.push([sale,regular]);
      });
      rows=uniqueRows(rows); return rows.length===1&&hs.length===1&&hs[0]===rows[0][0]&&(!rows[0][1]||(hr.length===1&&hr[0]===rows[0][1]))?result('wconcept',rows[0][0],rows[0][1],'GA4ItemObj.SalePrice','GA4ItemObj.CustomerPrice'):null;
    }

    if(hostIs('29cm.co.kr')){
      var norm=raw; for(i=0;i<4;i++) norm=norm.replace(/\\"/g,'"');
      var re29=/"sellPrice"\s*:\s*(\d+)\s*,\s*"consumerPrice"\s*:\s*(\d+)/g,m29;
      while((m29=re29.exec(norm))){sale=toPrice(m29[1]);regular=toPrice(m29[2]);if(sale&&regular>=sale)rows.push([sale,regular]);}
      rows=uniqueRows(rows); if(rows.length!==1)return null;
      var opts=[],reOpt=/"visibleMaxExtraPrice"\s*:\s*(-?\d+)\s*,\s*"visibleMinExtraPrice"\s*:\s*(-?\d+)\s*,\s*"hasVisibleOptionExtraPrice"\s*:\s*(true|false)/g,mo;
      while((mo=reOpt.exec(norm)))opts.push([Number(mo[1]),Number(mo[2]),mo[3]==='true']); opts=uniqueRows(opts); if(opts.length>1)return null;
      var ex={}; if(opts.length&&opts[0][2]){ex.purchasePriceStatus='option_dependent';ex.optionDependent=true;ex.optionPriceMin=rows[0][0]+opts[0][1];ex.optionPriceMax=rows[0][0]+opts[0][0];if(ex.optionPriceMin<=0||ex.optionPriceMax<ex.optionPriceMin)return null;} else if(opts.length)ex.optionDependent=false;
      return result('29cm',rows[0][0],rows[0][1],'item.sellPrice','item.consumerPrice',ex);
    }

    if(hostIs('fila.co.kr')){
      var selected=Array.from(document.querySelectorAll('script[type="application/json"][data-selected-variant]')).map(function(x){try{return JSON.parse(x.textContent);}catch(e){return null;}}).filter(function(x){return x&&typeof x==='object';});
      if(selected.length!==1)return null; var cents=toPrice(selected[0].price); if(!cents||cents%100)return null; sale=cents/100;
      var compare=toPrice(selected[0].compare_at_price); regular=compare?(compare%100?null:compare/100):null; if(compare&&compare%100)return null;
      var offers=[]; nodes.forEach(function(n){if(n&&n['@type']==='ProductGroup')asArray(n.hasVariant).forEach(function(v){var o=v&&v.offers;if(o&&(o.priceCurrency==null||o.priceCurrency==='KRW')){var p=toPrice(o.price);if(p)offers.push(p);}});}); offers=uniqueRows(offers);
      if(!offers.length||offers.indexOf(sale)<0)return null; var lo=Math.min.apply(null,offers),hi=Math.max.apply(null,offers),dep=lo!==hi;
      return result('fila',lo,regular,'ProductGroup.hasVariant.offers.price','selectedVariant.compare_at_price',{purchasePriceStatus:dep?'option_dependent':'confirmed',optionDependent:dep,optionPriceMin:dep?lo:null,optionPriceMax:dep?hi:null});
    }

    if(hostIs('hago.kr')){
      var reHago=/var\s+goodsInfo\s*=\s*\{([\s\S]*?)\n\s*\};/g,mh;
      while((mh=reHago.exec(raw))){var b=mh[1],a=/\bprice\s*:\s*(\d+)/.exec(b),d=/\bdcPrice\s*:\s*(\d+)/.exec(b),s=/\bsellPrice\s*:\s*(\d+)/.exec(b),so=/\bsoldout\s*:\s*['"]([YN])['"]/.exec(b);if(a&&d&&s&&so&&Number(d[1])===Number(s[1])&&Number(a[1])>=Number(s[1]))rows.push([Number(s[1]),Number(a[1]),so[1]]);}
      rows=uniqueRows(rows); return rows.length===1&&rows[0][2]==='N'?result('hago',rows[0][0],rows[0][1],'goodsInfo.sellPrice','goodsInfo.price'):null;
    }

    if(hostIs('lookpin.co.kr')){
      var lookActions=Array.from(document.querySelectorAll('button,a')).filter(function(x){var t=(x.textContent||'').trim();return /장바구니 담기|구매하기/.test(t)&&!x.disabled&&x.getAttribute('aria-disabled')!=='true';});
      var lookSoldOut=Array.from(document.querySelectorAll('button')).some(function(x){return /품절/.test((x.textContent||'').trim())&&(x.disabled||x.getAttribute('aria-disabled')==='true');});
      if(!lookActions.length||lookSoldOut)return null;
      document.querySelectorAll('span.text-h2-lg.text-black.font-bold').forEach(function(x){var del=x.parentElement&&x.parentElement.querySelector('del');sale=toPrice(x.textContent);regular=del?toPrice(del.textContent):null;if(sale&&regular&&regular>=sale)rows.push([sale,regular]);}); rows=uniqueRows(rows);
      return rows.length===1?result('lookpin',rows[0][0],rows[0][1],'product-price.sale','product-price.del'):null;
    }

    if(hostIs('topten10.goodwearmall.com')){
      nodes.forEach(function(n){if(!n||n['@type']!=='Product'||!firstStr(n.name)||!firstStr(n.sku)||!n.offers)return;var o=n.offers;if(o.availability==='https://schema.org/OutOfStock'||(o.priceCurrency&&o.priceCurrency!=='KRW'))return;sale=toPrice(o.price);regular=null;asArray(n.additionalProperty).forEach(function(p){if(p&&p.name==='정가')regular=toPrice(p.value);});if(sale&&(!regular||regular>=sale))rows.push([sale,regular]);});rows=uniqueRows(rows);
      return rows.length===1?result('topten',rows[0][0],rows[0][1],'Product.offers.price','Product.additionalProperty[정가]'):null;
    }

    if(hostIs('mujikorea.co.kr')){
      var nm=raw;for(i=0;i<4;i++)nm=nm.replace(/\\"/g,'"');var rx=/"row"\s*:\s*\{\s*"product"\s*:\s*\{[\s\S]{0,1200}?"product_id"\s*:\s*(\d+)\s*,\s*"sale_state"\s*:\s*"([A-Z_]+)"\s*,[\s\S]{0,1000}?"retail_price"\s*:\s*(\d+)\s*,\s*"discount_price"\s*:\s*\d+\s*,\s*"discount_rate"\s*:\s*\d+\s*,\s*"sell_price"\s*:\s*(\d+)\s*,\s*"last_price"\s*:\s*(\d+)/g,mm;while((mm=rx.exec(nm)))rows.push([Number(mm[4]),Number(mm[3]),mm[2],Number(mm[5])]);rows=uniqueRows(rows);
      return rows.length===1&&rows[0][2]==='ON'&&rows[0][0]===rows[0][3]?result('muji',rows[0][0],rows[0][1],'product.sell_price','product.retail_price'):null;
    }

    if(hostIs('hmall.com')){
      var next=document.querySelector('script#__NEXT_DATA__');if(!next)return null;try{state=JSON.parse(next.textContent);state=state.props.pageProps.respData.itemPtc;}catch(e){return null;}if(!state||state.soldout!==false)return null;sale=toPrice(state.bbprc);regular=toPrice(state.sellPrc);return result('hmall',sale,regular,'itemPtc.bbprc','itemPtc.sellPrc');
    }

    if(hostIs('lotteon.com')){
      // SPA 초기 HTML에는 화면가 문구가 없을 수 있어 LD Offer KRW 가격만으로 확정.
      if(pageText().indexOf('품절된 상품입니다')>=0)return null;var ps=products();
      ps.forEach(function(p){var os=productOffers(p);if(!firstStr(p.name)||!firstStr(p.sku)||os.length!==1)return;var o=os[0],p0=toPrice(o.price),av=availability(o.availability);if(av&&!av.endsWith('instock'))return;if((!o.priceCurrency||o.priceCurrency==='KRW')&&p0)rows.push(p0);});
      rows=uniqueRows(rows);return rows.length===1?result('lotteon',rows[0],null,'Product.offers.price',null,{priceConfidence:'medium'}):null;
    }

    var metaSaleSites={
      'noirer.com':['noirer','BUY NOW'],
      'marithe-official.com':['marithe','장바구니 담기'],
      'amomento.co':['amomento','Add To Bag'],'anderssonbell.com':['anderssonbell','ADD TO BAG'],
      'yaleapparel.co.kr':['yale','구매하기'],'withyoon.com':['withyoon','Buy It Now'],
      '66girls.co.kr':['66girls','바로 구매하기'],'partimento.com':['partimento','Add to Cart']
    };
    for(var metaDomain in metaSaleSites)if(hostIs(metaDomain))return cafe24MetaSale(metaSaleSites[metaDomain][0],metaSaleSites[metaDomain][1]);
    // 회원가 몰: 정가(list) 채택
    var metaListSites={
      'leekorea.co.kr':['lee','바로 구매하기'],
      'vivastudio.co.kr':['vivastudio',null],
      'frombeginning.co.kr':['frombeginning','바로구매'],
      'mixxo.com':['mixxo','구매하기'],
      'liphop.com':['liphop','BUY IT NOW'],
      'dailyjou.com':['dailyjou','구매하기'],
      'covernat.co.kr':['covernat','CART'],
      'code-graphy.com':['codegraphy','구매하기']
    };
    for(var listDomain in metaListSites)if(hostIs(listDomain))return cafe24MetaList(metaListSites[listDomain][0],metaListSites[listDomain][1]);
    if(hostIs('hotping.co.kr')){
      var hpid=metaOne('product:retailer_item_id'),hcur=metaOne('product:sale_price:currency'),hmeta=toPrice(metaOne('product:sale_price:amount')),hps=products();
      if(!/^\d+$/.test(hpid||'')||hcur!=='KRW'||!hmeta||hps.length!==1||!firstStr(hps[0].name))return null;
      var hos=productOffers(hps[0]),hstates=uniqueRows(hos.map(function(o){return o.availability;}));if(!hos.length||hstates.some(function(s){return s!=='InStock'&&s!=='OutOfStock';}))return null;
      var hlive=liveOfferPrices(hos,false),hvalid=hos.filter(function(o){return o.availability==='InStock'&&toPrice(o.price)&&(!o.priceCurrency||o.priceCurrency==='KRW');});if(!hlive.length||hvalid.length!==hos.filter(function(o){return o.availability==='InStock';}).length)return null;
      var hlo=Math.min.apply(null,hlive),hhi=Math.max.apply(null,hlive),ht=pageText();if(hmeta!==hlo||scriptPrice('product_price',raw)!==hlo||ht.indexOf('판매가')<0||ht.indexOf('장바구니')<0||ht.indexOf('구매하기')<0)return null;var hdep=hlo!==hhi;
      return result('hotping',hlo,null,'Product.offers[InStock].price + product:sale_price:amount',null,{purchasePriceStatus:hdep?'option_dependent':'confirmed',optionDependent:hdep,optionPriceMin:hdep?hlo:null,optionPriceMax:hdep?hhi:null});
    }

    if(hostIs('filluminate.com')){
      var psF=products();if(psF.length!==1)return null;var osF=productOffers(psF[0]),liveF=osF.filter(function(o){return o.availability==='InStock';}),pricesF=liveOfferPrices(osF,false);
      if(!liveF.length||pricesF.length!==1||liveF.length!==liveF.filter(function(o){return toPrice(o.price)&&(!o.priceCurrency||o.priceCurrency==='KRW');}).length)return null;
      regular=pricesF[0];if(scriptPrice('product_price',raw)!==regular)return null;sale=scriptPrice('product_sale_price',raw)||regular;
      // 회원 sale 대신 정가(product_price / LD offers)
      return sale<=regular?result('filluminate',regular,null,'product_price + Product.offers.price',null,{optionDependent:false}):null;
    }

    if(hostIs('urbanstoff.com')){
      var psU=products();if(psU.length!==1)return null;var osU=productOffers(psU[0]),pU=uniqueRows(osU.map(function(o){return (!o.priceCurrency||o.priceCurrency==='KRW')?toPrice(o.price):null;}).filter(Boolean));if(pU.length!==1)return null;regular=pU[0];
      var statesU=uniqueRows(osU.map(function(o){return o.availability;})),explicit=statesU.indexOf('InStock')>=0&&statesU.every(function(x){return x==='InStock'||x==='OutOfStock';});
      if(!explicit&&!(liveSelectOptions().length&&pageText().indexOf('ADD TO CART')>=0&&pageText().indexOf('품절')<0))return null;
      var sr=scriptPrice('product_price',raw);if(sr&&sr!==regular)return null;sale=scriptPrice('product_sale_price',raw)||toPrice((Array.from(document.querySelectorAll('tr')).find(function(r){var c=r.querySelectorAll(':scope > th, :scope > td');return c.length>1&&c[0].textContent.trim()==='판매가';})||{}).textContent);
      // 회원 자동할인 대신 정가(LD/product_price)
      return sale&&sale<=regular?result('urbanstoff',regular,null,'Product.offers.price + product_price',null,{optionDependent:false}):null;
    }

    if(hostIs('not4u.kr')){
      var h=document.querySelector('h1,h2'),title=h?(h.textContent||'').trim():'';if(title&&/테스트|이벤트/.test(title))return null;
      return cafe24MetaList('not4u','구매하기');
    }

    if(hostIs('insilence.co.kr')){
      var pi=products();if(pi.length===1&&firstStr(pi[0].name)&&firstStr(pi[0].name).indexOf('¥')>=0)return null;
      return cafe24MetaList('insilence','구매하기');
    }

    if(hostIs('fabregat.kr')){
      if(!liveSelectOptions().length)return null;var pf=products();if(pf.length!==1)return null;var af=uniqueRows(productOffers(pf[0]).map(function(o){return (!o.priceCurrency||o.priceCurrency==='KRW')?toPrice(o.price):null;}).filter(Boolean));if(af.length!==1)return null;regular=af[0];sale=scriptPrice('product_sale_price',raw);
      if(!sale){var el=document.querySelector('#span_product_price_sale');sale=el?toPrice(el.textContent):null;}var rr=scriptPrice('product_price',raw);if(rr&&rr!==regular)return null;
      // 회원 자동할인 대신 정가(LD/product_price)
      return sale&&sale<=regular?result('fabregat',regular,null,'Product.offers.price + product_price',null,{priceConfidence:'medium',optionDependent:false}):null;
    }

    if(hostIs('uniqlo.com')){
      var groups=nodes.filter(function(n){return exactType(n,'ProductGroup');});if(groups.length!==1||!firstStr(groups[0].productGroupID)||!firstStr(groups[0].name))return null;
      var up=[];asArray(groups[0].hasVariant).forEach(function(v){var o=v&&v.offers;if(firstStr(v&&v.sku)&&o&&o.priceCurrency==='KRW'&&o.availability==='https://schema.org/InStock'){var p=toPrice(o.price);if(p)up.push(p);}});up=uniqueRows(up);if(!up.length||!up.some(function(p){return pageText().indexOf(won(p))>=0;}))return null;var ulo=Math.min.apply(null,up),uhi=Math.max.apply(null,up);
      return result('uniqlo',ulo,null,'ProductGroup.hasVariant[].offers.price',null,{priceConfidence:'medium',purchasePriceStatus:ulo===uhi?'confirmed':'option_dependent',optionDependent:ulo!==uhi,optionPriceMin:ulo!==uhi?ulo:null,optionPriceMax:ulo!==uhi?uhi:null});
    }

    if(hostIs('ssg.com')){
      // deal 페이지 resultItemObj는 bestAmt:'N' 문자열·상태필드 생략.
      // itemView는 bestAmt:parseInt('N') + sellStat/cpnYn 등. 비탐욕 정규식은 script_timeout.
      var textS=pageText();
      if(textS.indexOf('행사 기간이 아닙니다')>=0)return null;
      var rowsS=[], from=0, marker='resultItemObj';
      function ssgBlob(at){
        var open=raw.indexOf('{', at); if(open<0)return null;
        var depth=0;
        for(var i=open;i<Math.min(raw.length,open+20000);i++){
          var c=raw[i];
          if(c==='{')depth++;
          else if(c==='}'){ if(--depth===0)return raw.slice(open,i+1); }
        }
        return null;
      }
      while(true){
        var at=raw.indexOf(marker, from); if(at<0)break;
        var blob=ssgBlob(at); if(!blob){from=at+marker.length;continue;}
        function fv(re){var z=re.exec(blob);return z&&z[1];}
        var id=fv(/itemId\s*:\s*'([^']+)'/);
        var buy=toPrice((/bestAmt\s*:\s*parseInt\('(\d+)'/.exec(blob)||/bestAmt\s*:\s*'(\d+)'/.exec(blob)||[])[1]);
        var reg=toPrice(fv(/sellprc\s*:\s*'(\d+)'/));
        var pre=toPrice(fv(/preCpnDcPrc\s*:\s*'(\d+)'/));
        var sellStat=fv(/sellStatCd\s*:\s*'([^']+)'/);
        if(!/^\d+$/.test(id||'')||!buy||(reg&&reg<buy)){from=at+marker.length;continue;}
        if(textS.indexOf('최적가')<0||textS.indexOf(Number(buy).toLocaleString('en-US'))<0){from=at+marker.length;continue;}
        if(sellStat!=null){
          if(sellStat!=='20'||fv(/soldOut\s*:\s*'([^']+)'/)!=='N'||fv(/soldOutPass\s*:\s*'([^']+)'/)!=='N'||fv(/uitemSamePrcYn\s*:\s*'([^']+)'/)!=='Y'||fv(/cpnYn\s*:\s*'([^']+)'/)!=='N'||(pre!=null&&buy!==pre)){from=at+marker.length;continue;}
        }
        rowsS.push([buy,reg&&reg>buy?reg:null]);
        from=at+marker.length;
      }
      rowsS=uniqueRows(rowsS);return rowsS.length===1?result('ssg',rowsS[0][0],rowsS[0][1],'resultItemObj.bestAmt','resultItemObj.sellprc',{optionDependent:false}):null;
    }

    if(hostIs('hi.thehyundai.com')){
      var nh=raw;for(i=0;i<4;i++)nh=nh.replace(/\\"/g,'"');var reHy=/"slitmCd"\s*:\s*"([A-Za-z0-9]+)"\s*,\s*"slitmNm"\s*:\s*"([^"]+)"/g,mhy,textH=pageText();while((mhy=reHy.exec(nh))){var frag=nh.slice(mhy.index,mhy.index+30000);if(frag.slice(0,1500).indexOf('"itemGbcd"')<0)continue;function hf(n){var q=new RegExp('"'+n+'"\\s*:\\s*"([^"]+)"').exec(frag);return q&&q[1];}var qty=/"sellPossQty"\s*:\s*(\d+)/.exec(frag),pr=/"prcInfo"\s*:\s*\{[^}]*?"sellPrc"\s*:\s*(\d+)[^}]*?"dcPrc"\s*:\s*(\d+)[^}]*?"maxDcPrc"\s*:\s*(\d+)/.exec(frag);if(!qty||Number(qty[1])<=0||!pr)continue;var sellPrc=Number(pr[1]),dcPrc=Number(pr[2]),maxDc=Number(pr[3]);
        // sellPrc=정상가, dcPrc/maxDcPrc=할인가(실제 구매가). sellMdaPossYn 누락 시에도 Hi 몰은 통과.
        if(maxDc!==dcPrc||dcPrc<=0||sellPrc<dcPrc)continue;sale=dcPrc;regular=sellPrc;var mda=hf('sellMdaPossYn');if(mda!=null&&mda!=='1')continue;if(['empBuyLimtYn','empDcYn','clsrMallItemYn','ostkYn'].some(function(n){return hf(n)!=='0';})||mhy[2].indexOf('임직원')>=0)continue;if(textH.indexOf(mhy[2])>=0&&textH.indexOf(won(regular))>=0&&textH.indexOf(won(sale))>=0)rows.push([sale,regular]);}rows=uniqueRows(rows);return rows.length===1?result('thehyundai',rows[0][0],rows[0][1],'prcInfo.dcPrc','prcInfo.sellPrc',{priceConfidence:'medium'}):null;
    }

    if(hostIs('a-bly.com')){
      var aid=metaOne('product:retailer_item_id'),ac=metaOne('product:price:currency'),aa=metaOne('product:availability');sale=toPrice(metaOne('product:price:amount'));var at=pageText();
      return /^\d+$/.test(aid||'')&&ac==='KRW'&&String(aa||'').toLowerCase()==='in stock'&&sale&&at.indexOf('구매하기')>=0&&at.indexOf(won(sale))>=0&&at.indexOf('나의 예상 구매가')>=0&&at.indexOf('즉시 할인')>=0?result('ably',sale,null,'meta[product:price:amount] / 즉시 할인',null,{priceConfidence:'medium'}):null;
    }

    if(hostIs('zigzag.kr')){
      var zn=document.querySelector('script#__NEXT_DATA__');if(!zn)return null;try{state=JSON.parse(zn.textContent);var qs=state.props.pageProps.dehydratedState.queries;}catch(e){return null;}var zt=pageText();
      asArray(qs).forEach(function(q){try{var p=q.state.data.product,pr=p.product_price;if(!/^\d+$/.test(String(p.id||''))||p.is_purchasable!==true||p.sales_status!=='ON_SALE'||p.display_status!=='VISIBLE')return;sale=toPrice(pr.display_final_price.final_price.price);regular=toPrice(pr.max_price_info.price);var n=firstStr(p.name);if(sale&&(!regular||regular>=sale)&&n&&zt.indexOf(n)>=0&&zt.indexOf('구매하기')>=0&&zt.indexOf(Number(sale).toLocaleString('en-US'))>=0)rows.push([sale,regular===sale?null:regular]);}catch(e){}});rows=uniqueRows(rows);return rows.length===1?result('zigzag',rows[0][0],rows[0][1],'product.product_price.display_final_price.final_price.price','product.product_price.max_price_info.price',{priceConfidence:'medium'}):null;
    }

    if(hostIs('kream.co.kr')){
      var kt=pageText();if(kt.indexOf('브랜드배송')<0||/판매 입찰|구매 입찰|옵션 선택/.test(kt))return null;var kp=products();if(kp.length!==1)return null;var ko=productOffers(kp[0]);if(ko.length!==1||(ko[0].priceCurrency&&ko[0].priceCurrency!=='KRW'))return null;var kav=availability(ko[0].availability);if(kav&&!kav.endsWith('instock'))return null;if(!/^\d+$/.test(String(kp[0].productID||'')))return null;sale=toPrice(ko[0].price);var kn=firstStr(kp[0].name);
      return sale&&kn&&kt.indexOf(kn)>=0&&kt.indexOf('구매하기')>=0&&(kt.indexOf(won(sale))>=0||kt.indexOf(Number(sale).toLocaleString('en-US'))>=0)?result('kream',sale,null,'Product.offers.price / 브랜드배송',null,{priceConfidence:'medium'}):null;
    }

    if(hostIs('guesskorea.com')){
      var gp=products();if(gp.length!==1)return null;var gl=liveOfferPrices(productOffers(gp[0]),true);if(gl.length!==1)return null;sale=gl[0];var gs=document.querySelector('.price_box #span_product_price_text'),gr=document.querySelector('.price_box .custom.through');regular=gr?toPrice(gr.textContent):null;if(!gs||toPrice(gs.textContent)!==sale||(regular&&regular<sale)||scriptPrice('product_price',raw)!==sale||pageText().indexOf('장바구니 담기')<0||pageText().indexOf('바로 구매하기')<0)return null;
      return result('guess',sale,regular===sale?null:regular,'Product.offers[].price / product_price','.price_box .custom.through',{priceConfidence:'medium',optionDependent:false});
    }

    if(hostIs('levi.co.kr')){
      var lm=/window\.hulkappsWishlist\.productJSON\s*=\s*\{/.exec(raw);if(!lm)return null;try{state=JSON.parse(objectAt(raw,lm.index));}catch(e){return null;}if(state.available!==true||!/^\d+$/.test(String(state.id||''))||!Array.isArray(state.variants))return null;var lv=state.variants.filter(function(v){return v&&v.available===true;}),lps=uniqueRows(lv.map(function(v){return toPrice(v.price);}).filter(Boolean)),lcs=uniqueRows(lv.map(function(v){return toPrice(v.compare_at_price);}).filter(Boolean));if(lps.length!==1||lcs.length>1||lps[0]%100)return null;sale=lps[0]/100;regular=lcs.length?(lcs[0]%100?null:lcs[0]/100):null;if(lcs.length&&lcs[0]%100)return null;var lt=pageText();
      return (!regular||regular>=sale)&&lt.indexOf(firstStr(state.title)||'\u0000')>=0&&lt.indexOf('₩'+Number(sale).toLocaleString('en-US'))>=0&&lt.indexOf('장바구니 담기')>=0&&lt.indexOf('지금 구매')>=0?result('levis',sale,regular===sale?null:regular,'hulkappsWishlist.productJSON.variants[].price / 100','variants[].compare_at_price / 100',{priceConfidence:'medium',optionDependent:false}):null;
    }

    if(hostIs('vans.co.kr')){
      var vt=metaOne('recopick:title'),vc=metaOne('recopick:price:currency');regular=toPrice(metaOne('recopick:price'));var saleNodes=document.querySelectorAll('meta[property="recopick:sale_price"]'),vs=metaOne('recopick:sale_price');if(saleNodes.length&&vs==null)return null;sale=toPrice(vs)||regular;var sizes=Array.from(document.querySelectorAll('label.variation-size.selectable')).filter(function(x){return !x.classList.contains('nonActive');}),vtext=pageText();
      return vt&&vc==='KRW'&&sale&&(!regular||regular>=sale)&&sizes.length&&vtext.indexOf(vt)>=0&&vtext.indexOf(Number(sale).toLocaleString('en-US')+' 원')>=0&&vtext.indexOf('장바구니에 담기')>=0&&vtext.indexOf('바로구매')>=0?result('vans',sale,vs&&regular!==sale?regular:null,vs?'meta[recopick:sale_price]':'meta[recopick:price]','meta[recopick:price]',{priceConfidence:'medium',optionDependent:false}):null;
    }

    var verifiedCafe={'whoau.com':['whoau','구매하기']};
    for(var cafeDomain in verifiedCafe)if(hostIs(cafeDomain)){
      var cfg=verifiedCafe[cafeDomain],cid=metaOne('product:retailer_item_id'),cc=metaOne('product:sale_price:currency'),cms=toPrice(metaOne('product:sale_price:amount'));if(!/^\d+$/.test(cid||'')||cc!=='KRW'||!cms)return null;
      var cps=products(),csets=[],cnames=[];cps.forEach(function(p){var n=firstStr(p.name);if(n)cnames.push(n);var lp=liveOfferPrices(productOffers(p),false);if(lp.length)csets.push(lp.sort(function(a,b){return a-b;}));});csets=uniqueRows(csets);cnames=uniqueRows(cnames);
      var shown=uniqueRows(Array.from(document.querySelectorAll('#span_product_price_text')).map(function(x){return toPrice(x.textContent);}).filter(Boolean)),creg=uniqueRows(Array.from(document.querySelectorAll('#span_product_price_custom')).map(function(x){return toPrice(x.textContent);}).filter(Boolean));
      var scriptP=scriptPrice('product_price',raw),pt=pageText();
      // 코드그라피처럼 JSON-LD offers에 price/InStock이 비어 있어도
      // meta sale_price + 화면가 + product_price 스크립트가 일치하면 확정한다.
      var clo,chi,cdep,fromLd=false;
      if(csets.length===1){
        clo=Math.min.apply(null,csets[0]);chi=Math.max.apply(null,csets[0]);
        if(cms!==clo)return null;
        fromLd=true;cdep=clo!==chi;
      }else if(!csets.length){
        if(shown.length!==1||shown[0]!==cms||(scriptP!=null&&scriptP!==cms))return null;
        clo=cms;chi=cms;cdep=false;
      }else return null;
      if(shown.length&&!(shown.length===1&&shown[0]===clo))return null;
      if(creg.length>1||(creg.length&&creg[0]<chi))return null;
      if(cnames.length===1&&pt.indexOf(cnames[0])<0)return null;
      if(pt.indexOf(cfg[1])<0)return null;
      if(pt.indexOf(Number(clo).toLocaleString('en-US'))<0&&pt.indexOf(String(clo))<0)return null;
      return result(cfg[0],clo,creg.length&&creg[0]!==clo?creg[0]:null,fromLd?'Product.offers[InStock].price / product:sale_price:amount':'product:sale_price:amount + #span_product_price_text','#span_product_price_custom',{priceConfidence:'medium',purchasePriceStatus:cdep?'option_dependent':'confirmed',optionDependent:cdep,optionPriceMin:cdep?clo:null,optionPriceMax:cdep?chi:null});
    }

    if(hostIs('hm.com')){
      var ids=[];document.querySelectorAll('link[rel="canonical"]').forEach(function(x){var m=/\/productpage\.(\d+)\.html/.exec(x.href||'');if(m)ids.push(m[1]);});ids=uniqueRows(ids);var hg=nodes.filter(function(n){return exactType(n,'ProductGroup');});if(ids.length!==1||hg.length!==1||!/^\d+$/.test(String(hg[0].productGroupID||'')))return null;var hp=[];asArray(hg[0].hasVariant).forEach(function(v){asArray(v&&v.offers).forEach(function(o){if(!o||String(o.url||'').indexOf(ids[0])<0||!availability(o.availability).endsWith('instock'))return;if(o.priceCurrency!=='KRW'){hp=['bad'];return;}var p=toPrice(o.price);if(p)hp.push(p);});});if(hp.indexOf('bad')>=0)return null;hp=uniqueRows(hp);if(!hp.length||pageText().indexOf('쇼핑백에 추가하기')<0||!hp.some(function(p){return pageText().indexOf('₩'+Number(p).toLocaleString('en-US'))>=0||pageText().indexOf('₩ '+Number(p).toLocaleString('en-US'))>=0;}))return null;var hlo=Math.min.apply(null,hp),hhi=Math.max.apply(null,hp);
      return result('hm',hlo,null,'ProductGroup.hasVariant[].offers[current article, InStock].price',null,{priceConfidence:'medium',purchasePriceStatus:hlo===hhi?'confirmed':'option_dependent',optionDependent:hlo!==hhi,optionPriceMin:hlo!==hhi?hlo:null,optionPriceMax:hlo!==hhi?hhi:null});
    }

    if(hostIs('gap.com'))return null;

    if(hostIs('aritzia.com')){
      // Mobify는 GBP·CAD. Global-e KRW만 확정(₩만, ≥10000).
      // 복수 testid 값이 있으면 Add to Bag 버튼 금액을 우선한다.
      var mob=document.querySelectorAll('#mobify-data');if(mob.length!==1)return null;try{var ar=JSON.parse(mob[0].textContent),pre=ar.__PRELOADED_STATE__,pp=pre.pageProps.structuredDataProps,seo=pp.seoProduct,store=pre.__STATE_MANAGEMENT_LIBRARY.store.productStore,by=store.productsById;}catch(e){return null;}var pid=String(seo&&seo.id||''),an=firstStr(seo&&seo.displayName);if(!/^\d+$/.test(pid)||!an||!by||!by[pid])return null;var colors=[];asArray(pp&&pp.structuredData).forEach(function(p){if(exactType(p,'Product')&&String(p.sku||'')===pid){var m=/[?&]color=(\d+)/.exec(String(p['@id']||p.url||''));if(m)colors.push(m[1]);}});var cm=/[?&]color=(\d+)/.exec(location.href||'');if(cm)colors=[cm[1]];else colors=uniqueRows(colors);if(colors.length!==1)return null;function stripMark(s){return String(s||'').replace(/[\u2122\u00ae\u00a9]/g,'').replace(/\s+/g,' ').trim();}function wonUi(sel){var es=document.querySelectorAll(sel);if(!es.length)return null;var vals=[];for(var i=0;i<es.length;i++){var t=(es[i].textContent||'').trim().replace(/\u00a0/g,' '),m=/₩\s*([\d,]+)/.exec(t),p=m?toPrice(m[1]):null;if(p&&p>=10000)vals.push(p);}vals=uniqueRows(vals);return vals.length===1?vals[0]:null;}function bagWon(){var vals=[];Array.from(document.querySelectorAll('button')).forEach(function(b){var t=(b.textContent||'').trim().replace(/\u00a0/g,' ');if(!/Add to Bag|Bag|장바구니/.test(t))return;var m=/₩\s*([\d,]+)/.exec(t),p=m?toPrice(m[1]):null;if(p&&p>=10000)vals.push(p);});vals=uniqueRows(vals);return vals.length===1?vals[0]:null;}regular=wonUi('[data-testid="product-list-price-text"]')||wonUi('[data-testid="product-price-text"]');var saleUi=wonUi('[data-testid="product-list-sale-text"]');sale=bagWon()||saleUi||regular;if(!sale||sale<10000)return null;var areg=saleUi&&regular&&regular>sale?regular:(regular&&regular>sale?regular:null);var at=pageText();if(stripMark(at).indexOf(stripMark(an))<0)return null;if(!(/Add to Bag|Bag|장바구니/.test(at)))return null;if(!(at.indexOf('₩'+Number(sale).toLocaleString('en-US'))>=0||at.indexOf('₩ '+Number(sale).toLocaleString('en-US'))>=0||at.indexOf(won(sale))>=0))return null;
      return result('aritzia',sale,areg,'localized KRW Add to Bag / product-price UI',areg?'product-list-price-text':null,{optionDependent:false,priceConfidence:'medium'});
    }

    if(hostIs('mahagrid.com')){
      // 옵션 일부 품절 문구·Offer availability 누락이 있어도 meta 정가로 확정.
      var mt=pageText();if(mt.indexOf('장바구니')<0||mt.indexOf('구매하기')<0)return null;
      var mid=metaOne('product:retailer_item_id');regular=toPrice(metaOne('product:price:amount'));sale=toPrice(metaOne('product:sale_price:amount'))||regular;
      if(!/^\d+$/.test(mid||'')||!regular||regular<sale)return null;
      var mp=products();
      if(mp.length===1){
        var nm=firstStr(mp[0].name);if(nm&&mt.indexOf(nm)<0)return null;
        var prices=uniqueRows(productOffers(mp[0]).map(function(o){return (!o.priceCurrency||o.priceCurrency==='KRW')?toPrice(o.price):null;}).filter(Boolean));
        if(prices.length&&prices.indexOf(regular)<0)return null;
      }else if(mp.length>1)return null;
      if(mt.indexOf(won(regular))<0&&mt.indexOf(Number(regular).toLocaleString('en-US'))<0)return null;
      return result('mahagrid',regular,null,'product:price:amount',null,{priceConfidence:'medium',optionDependent:false});
    }

    if(hostIs('ohora.kr')){
      var ot=pageText(),oa=Array.from(document.querySelectorAll('button,a')).filter(function(x){var visible=x.offsetParent!==null,t=(x.textContent||'').trim();return visible&&!x.disabled&&x.getAttribute('aria-disabled')!=='true'&&(/바로 구매/.test(t)||t==='장바구니');});if(!oa.some(function(x){return /바로 구매/.test(x.textContent||'');})||!oa.some(function(x){return (x.textContent||'').trim()==='장바구니';}))return null;var oid=metaOne('product:retailer_item_id');regular=toPrice(metaOne('product:price:amount'));sale=toPrice(metaOne('product:sale_price:amount'));var op=products();if(!/^\d+$/.test(oid||'')||!regular||!sale||regular<sale||op.length!==1)return null;var oo=productOffers(op[0]),on=firstStr(op[0].name);if(oo.length!==1||oo[0].priceCurrency!=='KRW'||toPrice(oo[0].price)!==regular||!on||ot.indexOf(on)<0||ot.indexOf('총 상품금액 '+won(sale))<0)return null;
      return result('ohora',sale,regular===sale?null:regular,'product:sale_price:amount / selected main-product total','product:price:amount',{priceConfidence:'medium',optionDependent:false});
    }

    if(hostIs('fashionplus.co.kr')){
      var fp=products();if(fp.length!==1)return null;var fprod=fp[0],fname=firstStr(fprod.name),fid=String(fprod.mpn||fprod.productID||''),fo=productOffers(fprod);if(!fname||!/^\d+$/.test(fid)||fo.length!==1||!availability(fo[0].availability).endsWith('instock')||fo[0].priceCurrency!=='KRW')return null;regular=toPrice(fo[0].price);sale=toPrice(fo[0].sale_price);if(!sale)return null;var fops=[];document.querySelectorAll('button.btn_option').forEach(function(x){if(x.disabled||x.classList.contains('disabled')||x.classList.contains('soldout'))return;var m=/([\d,]+)\s*원?\s*$/.exec(x.textContent.trim());if(m){var p=toPrice(m[1]);if(p)fops.push(p);}});fops=uniqueRows(fops);var ft=pageText();
      // 옵션 버튼이 SPA로만 채워지는 상품은 LD sale_price를 단일 후보로 쓴다.
      if(!fops.length) fops=[sale];
      if(fops.indexOf(sale)<0||ft.indexOf(fname)<0||ft.indexOf('장바구니')<0||ft.indexOf('구매')<0)return null;var flo=Math.min.apply(null,fops),fhi=Math.max.apply(null,fops),fdep=flo!==fhi,freg=regular&&regular>sale&&regular>=fhi?regular:null;
      return result('fashionplus',flo,freg,'Product.offers.sale_price + button.btn_option[enabled]',freg?'Product.offers.price':null,{priceConfidence:'medium',purchasePriceStatus:fdep?'option_dependent':'confirmed',optionDependent:fdep,optionPriceMin:fdep?flo:null,optionPriceMax:fdep?fhi:null});
    }

    if(hostIs('lfmall.co.kr'))return null;

    if(hostIs('thereformation.com')){
      var rp=products();if(rp.length!==1)return null;var rn=firstStr(rp[0].name),rl=liveOfferPrices(productOffers(rp[0]),true),rt=pageText();if(!rn||rt.indexOf(rn)<0||!rl.length||rt.indexOf('Add to bag')<0||!rl.some(function(p){return rt.indexOf('₩'+Number(p).toLocaleString('en-US'))>=0||rt.indexOf('₩ '+Number(p).toLocaleString('en-US'))>=0;}))return null;var rlo=Math.min.apply(null,rl),rhi=Math.max.apply(null,rl),rdep=rlo!==rhi;
      return result('reformation',rlo,null,'Product.offers[InStock, KRW].price',null,{purchasePriceStatus:rdep?'option_dependent':'confirmed',optionDependent:rdep,optionPriceMin:rdep?rlo:null,optionPriceMax:rdep?rhi:null});
    }

    if(hostIs('nike.com')){
      var nn=document.querySelector('script#__NEXT_DATA__');if(!nn)return null;try{state=JSON.parse(nn.textContent);var ng=state.props.pageProps.productGroups;}catch(e){return null;}if(!Array.isArray(ng)||ng.length!==1||!ng[0]||!ng[0].products)return null;var byStyle={},bad=false;Object.keys(ng[0].products).forEach(function(k){var p=ng[0].products[k];if(!p||!firstStr(p.styleColor)||byStyle[p.styleColor])bad=true;else byStyle[p.styleColor]=p;});if(bad)return null;var ogu=metaOne('og:url')||'',styles=Object.keys(byStyle).filter(function(s){return ogu.indexOf(s)>=0;});if(styles.length!==1)return null;var np=byStyle[styles[0]],npr=np.prices;if(np.statusModifier!=='BUYABLE_BUY'||!npr||npr.currency!=='KRW')return null;sale=toPrice(npr.currentPrice);regular=toPrice(npr.initialPrice);if(!sale||!regular||regular<sale||!Array.isArray(np.sizes)||!np.sizes.length)return null;var selected=[],live=[],hasAvail=false;nodes.filter(function(n){return exactType(n,'ProductGroup');}).forEach(function(g){asArray(g.hasVariant).forEach(function(v){if(!v||v.mpn!==styles[0])return;var o=v.offers;if(!o||o.priceCurrency!=='KRW')return;var p=toPrice(o.price);if(p)selected.push(p);var av=availability(o.availability);if(av)hasAvail=true;if(av.endsWith('instock')&&p)live.push(p);});});selected=uniqueRows(selected);live=uniqueRows(live);if(selected.length!==1||selected[0]!==sale||(hasAvail&&(live.length!==1||live[0]!==sale)))return null;var nt=pageText(),ntitle=firstStr(np.productInfo&&np.productInfo.title);if(!ntitle||nt.indexOf(ntitle)<0||!(nt.indexOf(Number(sale).toLocaleString('en-US')+' 원')>=0||nt.indexOf(won(sale))>=0))return null;
      return result('nike',sale,regular>sale?regular:null,'__NEXT_DATA__.productGroups[].products[styleColor].prices.currentPrice',regular>sale?'prices.initialPrice':null,{priceConfidence:'medium',optionDependent:false});
    }

    if(hostIs('oliveyoung.co.kr')){
      // 정가=options[].salePrice. RSC 우선. 없으면 async goods API(폴링).
      // 주의: sitePricing null일 때 바깥에서 name/image만 채우면 scraper가
      // price_ambiguous로 조기종료하므로, 아래 managed early-empty와 함께 쓴다.
      var ostates={};function oscore(g){return (g&&g.options?g.options.length:0)+(g&&g.saleableFlag===true?10:0);}function takeOlive(state,src,loose){if(!state||!Array.isArray(state.options))return null;if(!loose&&(state.saleableFlag!==true||state.displayableFlag!==true||state.soldOutFlag===true||String(state.status||'')!=='20'))return null;if(loose&&state.soldOutFlag===true)return null;var ol=state.options.filter(function(o){return o&&o.soldOutFlag!==true;});if(!ol.length)return null;var sales=uniqueRows(ol.map(function(o){return toPrice(o.salePrice);}).filter(Boolean));if(!sales.length)return null;var olo=Math.min.apply(null,sales),ohi=Math.max.apply(null,sales),odep=olo!==ohi;var oyname=firstStr(state.goodsName),oyt=pageText(),ogt=metaOne('og:title')||'';if(!oyname)return null;if(oyt.indexOf(oyname)<0&&ogt.indexOf(oyname)<0)return null;if(!loose&&oyt.indexOf('장바구니')<0&&oyt.indexOf('바로구매')<0&&oyt.indexOf('구매하기')<0)return null;return result('oliveyoung',olo,null,src,null,{priceConfidence:'medium',purchasePriceStatus:odep?'option_dependent':'confirmed',optionDependent:odep,optionPriceMin:odep?olo:null,optionPriceMax:odep?ohi:null});}document.querySelectorAll('script').forEach(function(x){var txt=x.textContent||'',m=/^\s*self\.__next_f\.push\((\[.*\])\)\s*$/s.exec(txt);if(!m)return;var payload;try{payload=JSON.parse(m[1]);}catch(e){return;}if(!Array.isArray(payload)||typeof payload[1]!=='string')return;var dec=payload[1],rx=/"data"\s*:\s*\{\s*"data"\s*:\s*\{/g,dm;while((dm=rx.exec(dec))){var obj=objectAt(dec,dm.index+dm[0].length-1),cand;try{cand=JSON.parse(obj);}catch(e){continue;}var gn=String(cand&&cand.goodsNumber||'');if(!gn||!Array.isArray(cand.options))continue;if(!ostates[gn]||oscore(cand)>oscore(ostates[gn]))ostates[gn]=cand;}});var owant=(/goodsNo=([A-Z0-9]+)/i.exec(location.href)||[])[1];if(!owant)return null;var fromRsc=takeOlive(ostates[owant],'goods.options[].salePrice',false);if(fromRsc)return fromRsc;try{var cache=window.__oyGoodsApi;if(cache&&cache.id===owant&&cache.status==='done'){var apiHit=takeOlive(cache.data,'goods/api/v1/detail.options[].salePrice',true);if(apiHit)return apiHit;return null;}if(!(cache&&cache.id===owant&&(cache.status==='loading'||cache.status==='done'))){window.__oyGoodsApi={id:owant,status:'loading',data:null};fetch((location.origin||'')+'/goods/api/v1/detail?goodsNo='+encodeURIComponent(owant),{credentials:'include',headers:{'Accept':'application/json'}}).then(function(r){return r.json();}).then(function(body){var payload=body&&body.data?body.data:body;if(payload&&payload.data&&Array.isArray(payload.data.options))payload=payload.data;window.__oyGoodsApi={id:owant,status:'done',data:payload};}).catch(function(){window.__oyGoodsApi={id:owant,status:'done',data:null};});}}catch(e){}
      return null;
    }

    if(hostIs('queenit.kr')){
      var qn=document.querySelector('script#__NEXT_DATA__');if(!qn)return null;try{state=JSON.parse(qn.textContent);var qq=state.props.pageProps.dehydratedState.queries;}catch(e){return null;}var qr=[];asArray(qq).forEach(function(q){var p=q&&q.state&&q.state.data&&q.state.data.product;if(!p||!p.productId||!p.name||p.display!==true||['ARCHIVED','SOLD_OUT','STOPPED'].indexOf(String(p.salesStatus||'').toUpperCase())>=0)return;sale=toPrice(p.finalPrice);regular=toPrice(p.originalPrice);if(sale&&regular>=sale)qr.push([String(p.productId),p.name,sale,regular]);});qr=uniqueRows(qr);if(qr.length!==1||pageText().indexOf(qr[0][1])<0||pageText().indexOf(Number(qr[0][2]).toLocaleString('en-US'))<0||pageText().indexOf('구매하기')<0)return null;
      return result('queenit',qr[0][2],qr[0][3]>qr[0][2]?qr[0][3]:null,'product.finalPrice','product.originalPrice',{priceConfidence:'medium',optionDependent:false});
    }

    if(hostIs('brandi.co.kr')){
      var bs=document.querySelectorAll('script#prefetch-data');if(bs.length!==1)return null;try{var bd=JSON.parse(bs[0].textContent).data;}catch(e){return null;}sale=toPrice(bd&&bd.sale_price);regular=toPrice(bd&&bd.price);if(!bd||!/^\d+$/.test(String(bd.id||''))||bd.is_sell!==true||bd.is_sold_out!==false||bd.is_temporary_sold_out!==false||!sale||!regular||regular<sale||toPrice(bd.original_sale_price)!==sale||toPrice(bd.original_price_info&&bd.original_price_info.sale_price)!==sale)return null;
      return result('brandi',sale,regular>sale?regular:null,'prefetch-data.data.sale_price','prefetch-data.data.price',{priceConfidence:'medium',optionDependent:false});
    }

    if(hostIs('4910.kr')){
      var sno=(location.pathname.match(/\/goods\/(\d+)/)||[])[1];
      var fr=[];
      var fs=document.querySelector('script#__NEXT_DATA__');
      if(fs){
        try{
          state=JSON.parse(fs.textContent);
          var fq=state.props&&state.props.serverQueryClient&&state.props.serverQueryClient.queries;
          asArray(fq).forEach(function(q){
            var d=q&&q.state&&q.state.data,g=d&&d.goods,f=g&&g.first_page_rendering,l=g&&g.linked_option;
            if(!g||!f)return;if(sno&&String(g.sno)!==String(sno))return;
            sale=toPrice(g.price);regular=toPrice(f.original_price);
            // boolean/string 모두 허용
            if(sale&&toPrice(f.price)===sale&&(!l||toPrice(l.price)===sale)&&g.is_soldout!==true&&g.is_soldout!=='true'&&(!l||(l.is_soldout!==true&&l.is_soldout!=='true'))&&(!regular||regular>=sale))
              fr.push([firstStr(f.goods_name)||firstStr(g.name),sale,regular||sale]);
          });
        }catch(e){}
        // JSON 전체 파싱이 실패하거나 queries가 비면 sno 주변 price를 직접 읽는다.
        if(!fr.length&&sno){
          var rawNext=fs.textContent||'';
          var reSno=new RegExp('"sno"\\s*:\\s*'+sno+'([\\s\\S]{0,1800}?)(?="sno"\\s*:|$)');
          var block=reSno.exec(rawNext);
          if(block){
            var pGoods=/"price"\s*:\s*(\d+)/.exec(block[1]);
            var pOrig=/"original_price"\s*:\s*(\d+)/.exec(block[1]);
            sale=pGoods?toPrice(pGoods[1]):null;regular=pOrig?toPrice(pOrig[1]):null;
            if(sale&&(!regular||regular>=sale))fr.push([null,sale,regular||sale]);
          }
        }
      }
      fr=uniqueRows(fr);if(fr.length<1)return null;var pt=pageText();var saleVals=uniqueRows(fr.map(function(x){return x[1];}));if(saleVals.length!==1)return null;sale=saleVals[0];if(!sale)return null;var regVals=uniqueRows(fr.map(function(x){return x[2];}).filter(function(x){return x!=null;}));regular=regVals.length?Math.max.apply(null,regVals):null;if(regular!=null&&regular<sale)regular=null;var saleStrEn=Number(sale).toLocaleString('en-US');var saleStr=String(Number(sale));
      // 4910은 SSR 시 판매가가 __NEXT_DATA__에만 있고 body.innerText에는 없는 경우가 많다.
      var htmlAll=document.documentElement?document.documentElement.innerHTML:'';
      if(pt.indexOf(saleStrEn)<0&&pt.indexOf(saleStr)<0&&htmlAll.indexOf(saleStr)<0)return null;
      return result('4910',sale,regular&&regular>sale?regular:null,'goods.price','goods.first_page_rendering.original_price',{priceConfidence:'medium',optionDependent:false});
    }

    if(hostIs('ssfshop.com')){
      var sp=products(),sh=document.querySelectorAll('#lastSalePrc');if(sp.length!==1||sh.length!==1)return null;var so=productOffers(sp[0]);if(so.length!==1||so[0].priceCurrency!=='KRW'||!availability(so[0].availability).endsWith('instock'))return null;sale=toPrice(so[0].price);if(!sale||toPrice(sh[0].value)!==sale||pageText().indexOf(Number(sale).toLocaleString('en-US'))<0||pageText().indexOf('장바구니')<0||pageText().indexOf('바로구매')<0)return null;var sc=document.querySelector('.price-info .cost del,.price-info del');regular=toPrice(sc&&sc.textContent);if(regular&&regular<sale)return null;
      return result('ssfshop',sale,regular>sale?regular:null,'Product.offers.price + #lastSalePrc',regular>sale?'.price-info .cost del':null,{priceConfidence:'medium',optionDependent:false});
    }

    if(hostIs('cjonstyle.com')){
      // 일부 SKU는 바로구매 없이 장바구니만, Offer가 ListPrice/SalePrice로 여러 줄일 수 있다.
      var cjList=products().filter(function(p){return productOffers(p).some(function(o){return toPrice(o.price);});});
      if(cjList.length!==1)return null;
      var cj=cjList[0],prices=uniqueRows(productOffers(cj).map(function(o){
        if(o.priceCurrency&&o.priceCurrency!=='KRW')return null;
        var av=availability(o.availability);
        if(av&&!av.endsWith('instock'))return null;
        return toPrice(o.price);
      }).filter(Boolean));
      if(prices.length!==1)return null;
      sale=prices[0];
      var ccode=String(cj.sku||cj.productID||''),ct=pageText();
      if(!sale||ct.indexOf(Number(sale).toLocaleString('en-US'))<0||ct.indexOf('판매가격')<0||(ct.indexOf('장바구니')<0&&ct.indexOf('바로구매')<0)||(ccode&&ct.indexOf(ccode)<0))return null;
      return result('cjonstyle',sale,null,'Product.offers.price',null,{priceConfidence:'medium',optionDependent:false});
    }

    if(hostIs('elandmall.co.kr')){
      sale=scriptPrice('s_price',raw);regular=scriptPrice('regular_price',raw);var es=scriptPrice('item_stock_qty',raw),em=/soldout_yn\s*=\s*['"]([^'"]+)/.exec(raw),en=/s_item_name\s*=\s*['"]([^'"]+)/.exec(raw);if(!sale||!regular||regular<sale||!es||!em||em[1]!=='N'||!en||pageText().indexOf(en[1])<0||pageText().indexOf(Number(sale).toLocaleString('en-US'))<0||!/(바로구매|구매하기)/.test(pageText()))return null;
      return result('elandmall',sale,regular>sale?regular:null,'s_price','regular_price',{priceConfidence:'medium',optionDependent:false});
    }

    if(hostIs('zara.com')){
      var za=window.zara&&window.zara.analyticsData,zg=topJsonLd().filter(function(x){return exactType(x,'ProductGroup');});if(!za||za.pageType!=='PRODUCT_DETAILS'||!za.page||za.page.currency!=='KRW'||zg.length!==1)return null;sale=toPrice(za.mainPrice);var zp=[];asArray(zg[0].hasVariant).forEach(function(v){var o=v&&v.offers;if(o&&o.priceCurrency==='KRW'&&availability(o.availability).endsWith('instock')){var p=toPrice(o.price);if(p)zp.push(p*100);}});zp=uniqueRows(zp);var zref=String(za.productRef||'').split('-')[0],zt=pageText();if(!sale||zp.length!==1||zp[0]!==sale||zref!==String(zg[0].productGroupID||'')||zt.indexOf(firstStr(zg[0].name)||'\u0000')<0||zt.indexOf(Number(sale).toLocaleString('en-US'))<0||zt.indexOf('장바구니에 담기')<0)return null;
      return result('zara',sale,null,'zara.analyticsData.mainPrice (ProductGroup offer ×100 cross-check)',null,{priceConfidence:'medium',optionDependent:false});
    }

    if(hostIs('nugu.jp')||hostIs('shein.com'))return null;
    return null;
  }
  var managedDomains=['musinsa.com','wconcept.co.kr','29cm.co.kr','fila.co.kr','hago.kr','lookpin.co.kr','topten10.goodwearmall.com','mujikorea.co.kr','hmall.com','lotteon.com','mixxo.com','dailyjou.com','leekorea.co.kr','filluminate.com','urbanstoff.com','not4u.kr','insilence.co.kr','fabregat.kr','hotping.co.kr','uniqlo.com','ssg.com','hi.thehyundai.com','a-bly.com','zigzag.kr','kream.co.kr','guesskorea.com','levi.co.kr','vans.co.kr','covernat.co.kr','code-graphy.com','whoau.com','hm.com','gap.com','aritzia.com','noirer.com','liphop.com','marithe-official.com','mahagrid.com','vivastudio.co.kr','amomento.co','anderssonbell.com','yaleapparel.co.kr','ohora.kr','withyoon.com','66girls.co.kr','partimento.com','fashionplus.co.kr','frombeginning.co.kr','lfmall.co.kr','thereformation.com','nike.com','oliveyoung.co.kr','queenit.kr','brandi.co.kr','nugu.jp','cjonstyle.com','4910.kr','ssfshop.com','zara.com','shein.com','elandmall.co.kr'];
  var managedSite=managedDomains.some(hostIs);
  var sitePricing=extractVerifiedSitePricing();
  // 올리브영: API/RSC 대기 중 name·image만 반환하면 scraper가 non-retryable로
  // 조기종료한다. 빈 응답으로 폴링을 유지한다.
  if(hostIs('oliveyoung.co.kr') && !sitePricing){
    return JSON.stringify({
      name:null, price:null, originalPrice:null, brand:null, image:null,
      siteName:null, hasJsonLd:false, looksLikeProductPage:false, blocked:false,
      source:{}, finalUrl:location.href,
      purchasePriceStatus:'unknown', priceConfidence:'unknown',
      availability:'unknown', optionDependent:null,
      optionPriceMin:null, optionPriceMax:null, priceEvidence:[]
    });
  }
  var dn = domName();
  var structuredPrice=sitePricing?sitePricing.price:(managedSite?null:((ld&&ld.price)||ogPrice));
  var structuredOriginal=sitePricing?sitePricing.originalPrice:(managedSite?null:((ld&&ld.originalPrice)||ogOriginalPrice));
  var domPrices=!productDetail ? {price:null,originalPrice:null} : (structuredPrice&&structuredOriginal)
    ? {price:null,originalPrice:null}
    : domPricePair();

  // 무인양품처럼 og:title 이 모든 페이지 공용("MUJI 무인양품 공식 온라인스토어")인 곳이
  // 있다. og:title 이 화면 h1 과 전혀 안 겹치면 사이트 공용 제목으로 보고 h1 을 쓴다.
  function overlaps(a,b){
    if(!a||!b) return false;
    return a.indexOf(b.slice(0,8))>=0 || b.indexOf(a.slice(0,8))>=0;
  }
  var useDomName = !!(dn && ogTitle && !overlaps(ogTitle, dn));

  var vansTitle = hostIs('vans.co.kr') ? metaOne('recopick:title') : null;
  var name;
  if(vansTitle) name = vansTitle;
  else if(ld && ld.name) name = ld.name;
  else if(useDomName) name = dn;
  else name = ogTitle || dn;

  // W컨셉 og:title/h1 은 사이트명("[W CONCEPT]" / "W CONCEPT")만 온다.
  // 상품명은 주문 폼 GA4ItemObj.ItemName 을 쓴다.
  if(hostIs('wconcept.co.kr')){
    var wNames=[];
    document.querySelectorAll('input[name^="GA4ItemObj_"]').forEach(function(x){
      try{ var st=JSON.parse(x.value); }catch(e){return;}
      var n=(st&&st.ItemName)?String(st.ItemName).replace(/\s+/g,' ').trim():'';
      if(n) wNames.push(n);
    });
    wNames=uniqueRows(wNames);
    if(wNames.length===1) name=wNames[0];
  }
  if(hostIs('hotping.co.kr')||hostIs('withyoon.com')){
    // og/JSON-LD 이름에 HTML 마크업이 그대로 들어오는 경우가 있어 name 불일치가 발생한다.
    name=stripHtmlName(name);
  }
  if(hostIs('hotping.co.kr') && ld && ld.name){
    var hotName=stripHtmlName(ld.name);
    if(hotName) name=hotName;
  }

  // URL만으로 확정할 수 있는 구조화된 기본 판매가를 우선한다. 화면의 쿠폰
  // 예상가나 옵션 선택 후 추가금은 사용자 상태에 따라 달라지므로 저장하지 않는다.
  var price = structuredPrice||(managedSite?null:domPrices.price);
  var originalPrice = structuredOriginal||domPrices.originalPrice;
  if(originalPrice&&price&&originalPrice<=price) originalPrice=null;
  var brand = (ld&&ld.brand) || null;
  var imageSource = (ld&&ld.image) ? 'json-ld' : 'og';
  var image = normalizeUrl((ld&&ld.image) || ogImage) || null;

  // 대표 이미지가 JSON-LD 또는 og:image에서 서로 다른 해상도/프록시로 섞이는 몰들이 있다.
  // 대조(카탈로그) 기준은 host별로 다음 우선순위를 따른다.
  if(hostIs('hago.kr')||hostIs('ssg.com')||hostIs('11st.co.kr')){
    // 11번가 JSON-LD는 792 리사이즈, og는 600 — 카탈로그/화면 대표는 og.
    if(ogImage){
      image = normalizeUrl(ogImage) || image;
      imageSource = 'og';
    }
  }
  if(hostIs('elandmall.co.kr')){
    // LD가 비거나 날짜 경로가 갈리면 og:image를 대표로 쓴다.
    if(ogImage){
      image = normalizeUrl(ogImage) || image;
      imageSource = 'og';
    }
  }
  if(hostIs('fashionplus.co.kr') && image && /og_200x200|dev_test/i.test(image)){
    // og:image는 고정 플레이스홀더라 JSON-LD/DOM 상품 이미지를 쓴다.
    var fpLdImg = (ld&&ld.image) ? normalizeUrl(ld.image) : null;
    if(fpLdImg && !/og_200x200|dev_test/i.test(fpLdImg)){
      image = fpLdImg;
      imageSource = 'json-ld';
    }else{
      var fpImgs = Array.from(document.querySelectorAll('img')).map(function(img){
        return (img.getAttribute('src')||img.getAttribute('data-src')||img.getAttribute('data-original')||'').trim();
      }).filter(function(u){return !!u;}).map(function(u){return normalizeUrl(u);});
      var fpPreferred = fpImgs.filter(function(u){
        return u && /product_img|mall\/assets/i.test(u) && !/og_200x200|dev_test/i.test(u);
      });
      if(fpPreferred.length){
        image = fpPreferred[0];
        imageSource = 'dom';
      }
    }
  }
  if(hostIs('hago.kr') && image){
    // view_1.jpg?... 형태를 1.jpg로 표준화
    image = image.replace(/\/view_1\.jpg(?:\?.*)?$/i,'/1.jpg');
  }
  if(hostIs('lookpin.co.kr') && image && /og_tag_lookpin_web\.jpg/i.test(image)){
    // og:image는 placeholder인 경우가 있어 static lookpin 이미지로 교체
    var imgs = Array.from(document.querySelectorAll('img')).map(function(img){
      return (img.getAttribute('src')||img.getAttribute('data-src')||img.getAttribute('data-original')||'').trim();
    }).filter(function(u){return !!u;}).map(function(u){return normalizeUrl(u);});
    var preferred = imgs.filter(function(u){
      return /static\.lookpin\.co\.kr/i.test(u) && /\.jpg/i.test(u) && !/og_tag_lookpin_web/i.test(u);
    });
    if(preferred.length){
      image = preferred[0];
      imageSource = 'dom';
    }
  }

  var source={
    name: vansTitle?'site-adapter':(hostIs('wconcept.co.kr')&&name&&name!==ogTitle&&name!==dn?'site-adapter':((ld&&ld.name)?'json-ld':(useDomName?'dom':(ogTitle?'og':(name?'dom':null))))),
    price:(ld&&ld.price)?'json-ld':(ogPrice?'og':(price?'dom':null)),
    image:imageSource,
    brand:(ld&&ld.brand)?'json-ld':null
  };
  if(sitePricing){source.price='site-adapter';source.adapter=sitePricing.adapter;source.field=sitePricing.purchaseField;}

  // 봇 검사/차단 페이지 감지 (홈 웜업 재시도 신호)
  var bodyText=document.body?document.body.innerText:'';
  var blocked=/Access Denied|잠시만 기다리십시오|잠시만 기다려 주세요|접속이 잠시 제한되었습니다|Just a moment|Checking your browser|에러페이지/i.test(bodyText) && bodyText.length<1500;

  return JSON.stringify({
    name:name||null, price:(price||null), originalPrice:(originalPrice||null), brand:brand, image:image,
    siteName:ogSite||null, hasJsonLd:!!ld, looksLikeProductPage:productDetail, blocked:blocked,
    source:source, finalUrl:location.href,
    purchasePriceStatus:sitePricing?sitePricing.purchasePriceStatus:(price?'provisional':'unknown'),
    priceConfidence:sitePricing?sitePricing.priceConfidence:(price?'low':'unknown'),
    availability:sitePricing?sitePricing.availability:'unknown',
    optionDependent:sitePricing?sitePricing.optionDependent:null,
    optionPriceMin:sitePricing?sitePricing.optionPriceMin:null,
    optionPriceMax:sitePricing?sitePricing.optionPriceMax:null,
    priceEvidence:sitePricing?[{price_role:'purchase_price',source:'rendered-webview',adapter:sitePricing.adapter,field:sitePricing.purchaseField}]:[]
  });
})();
''';
