import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:figmadesign/models/models.dart';
import 'package:figmadesign/services/aws/gql_documents.dart';
import 'package:figmadesign/services/aws/gql_runner.dart';
import 'package:figmadesign/services/aws/product_tag_store.dart';

class _FakeRunner implements GqlRunner {
  _FakeRunner(this.response);

  final Map<String, dynamic> response;
  String? lastDocument;
  Map<String, dynamic>? lastVariables;

  @override
  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, dynamic> variables = const {},
    GqlAuth auth = GqlAuth.user,
  }) async {
    lastDocument = document;
    lastVariables = variables;
    return response;
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String document, {
    Map<String, dynamic> variables = const {},
  }) => throw UnimplementedError();
}

void main() {
  final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0]);

  test('공식몰에서 찾은 결과를 읽고, 사진은 base64로 보낸다', () async {
    final runner = _FakeRunner({
      'identifyProductTag': {
        'status': 'found',
        'brand': 'NIKE',
        'productCode': 'DV1234-100',
        'productName': "에어 포스 1 '07",
        'color': 'WHITE',
        'tagPrice': 139000,
        'officialDomain': 'nike.com',
        'matchUrl': 'https://www.nike.com/kr/t/af1/DV1234-100',
        'matchHost': 'nike.com',
        'matchSource': 'official',
        'verifiedBy': 'product_code',
        'note': null,
      },
    });
    final store = AwsProductTagStore(runner: runner);

    final r = await store.identify(jpeg, 'image/jpeg');

    expect(runner.lastDocument, Gql.identifyProductTag);
    expect(runner.lastVariables, {
      'imageBase64': base64Encode(jpeg),
      'mimeType': 'image/jpeg',
    });
    expect(r.status, TagIdentifyStatus.found);
    expect(r.foundOnOfficialSite, isTrue);
    expect(r.needsUserCheck, isFalse);
    expect(r.matchUrl, 'https://www.nike.com/kr/t/af1/DV1234-100');
    expect(r.suggestedName, "NIKE 에어 포스 1 '07 (WHITE)");
    expect(r.tagPrice, 139000);
  });

  test('found인데 URL이 없으면 못 찾은 것으로 본다', () {
    final r = TagIdentifyResult.fromJson({'status': 'found', 'matchUrl': ''});
    expect(r.status, TagIdentifyStatus.notFound);
  });

  test('태그가 아닌 사진', () {
    final r = TagIdentifyResult.fromJson({'status': 'not_a_tag'});
    expect(r.status, TagIdentifyStatus.notATag);
    expect(r.suggestedName, '');
  });

  test('이름으로만 찾은 경우 사용자 확인이 필요하다', () {
    final r = TagIdentifyResult.fromJson({
      'status': 'found',
      'matchUrl': 'https://www.musinsa.com/products/1',
      'matchSource': 'mall',
      'verifiedBy': 'name',
    });
    expect(r.foundOnOfficialSite, isFalse);
    expect(r.needsUserCheck, isTrue);
  });

  test('빈 사진은 서버로 보내지 않는다', () async {
    final runner = _FakeRunner({});
    final store = AwsProductTagStore(runner: runner);
    expect(
      () => store.identify(Uint8List(0), 'image/jpeg'),
      throwsArgumentError,
    );
    expect(runner.lastDocument, isNull);
  });

  test('태그 사진 주소는 친구에게 보내는 JSON(살까말까)에 들어가지 않는다', () {
    final p = Product(
      id: 1,
      listId: 'a',
      name: '니트',
      price: 1000,
      image: '',
      platform: '',
      tagImageUrl: 'https://cdn/tag-photos/me/x.jpg',
    );
    expect(p.toJson().containsKey('tagImageUrl'), isFalse);
    expect(p.copyWith(price: 2000).tagImageUrl, 'https://cdn/tag-photos/me/x.jpg');
  });
}
