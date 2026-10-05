import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/services/aws/engine_store.dart';
import 'package:figmadesign/services/aws/gql_documents.dart';
import 'package:figmadesign/services/aws/gql_runner.dart';
import 'package:figmadesign/services/webview_scraper.dart';
import 'package:figmadesign/services/parsing_bridge.dart';

/// extractProduct 쿼리만 응답하는 가짜 AppSync. 다른 쿼리/뮤테이션은 이 테스트
/// 범위 밖이라 일부러 안 다룬다(test/aws/fake_appsync.dart는 DynamoDB 표 흉내용이라
/// 이 엔진 호출 경로와는 무관해서 재사용하지 않음).
class _FakeEngineAppSync implements GqlRunner {
  _FakeEngineAppSync(this._respond);

  final Future<Map<String, dynamic>> Function(
    String document,
    Map<String, dynamic> variables,
    GqlAuth auth,
  )
  _respond;

  String? lastDocument;
  Map<String, dynamic>? lastVariables;
  GqlAuth? lastAuth;

  @override
  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, dynamic> variables = const {},
    GqlAuth auth = GqlAuth.user,
  }) {
    lastDocument = document;
    lastVariables = variables;
    lastAuth = auth;
    return _respond(document, variables, auth);
  }

  @override
  Future<Map<String, dynamic>> mutate(
    String document, {
    Map<String, dynamic> variables = const {},
  }) => throw UnimplementedError('이 테스트에서는 쓰지 않음');
}

void main() {
  group('ExtractedProductDto.fromJson', () {
    test('모든 필드가 있는 정상 응답을 파싱한다', () {
      final dto = ExtractedProductDto.fromJson({
        'productName': '상품A',
        'unconditionalPrice': 10000,
        'regularPrice': 12000,
        'currency': 'KRW',
        'imageUrl': 'https://img.example/a.jpg',
        'ambiguous': false,
        'ambiguityReason': null,
        'confidence': 'high',
      });

      expect(dto.productName, '상품A');
      expect(dto.unconditionalPrice, 10000);
      expect(dto.regularPrice, 12000);
      expect(dto.currency, 'KRW');
      expect(dto.imageUrl, 'https://img.example/a.jpg');
      expect(dto.ambiguous, isFalse);
      expect(dto.confidence, 'high');
    });

    test('가격 필드가 전부 null이어도 예외 없이 파싱한다', () {
      final dto = ExtractedProductDto.fromJson({
        'productName': null,
        'unconditionalPrice': null,
        'regularPrice': null,
        'currency': null,
        'imageUrl': null,
        'ambiguous': true,
        'ambiguityReason': '가격을 찾지 못함',
        'confidence': 'low',
      });

      expect(dto.productName, isNull);
      expect(dto.unconditionalPrice, isNull);
      expect(dto.ambiguous, isTrue);
      expect(dto.ambiguityReason, '가격을 찾지 못함');
    });

    test('ambiguous가 응답에 없으면 true로 안전하게 기본값 처리한다', () {
      final dto = ExtractedProductDto.fromJson(const {});
      expect(dto.ambiguous, isTrue);
    });
  });

  group('engineResultToOnDeviceExtract', () {
    test('정상 응답(KRW, 확정 가격)을 올바르게 매핑한다', () {
      final extract = engineResultToOnDeviceExtract(
        const ExtractedProductDto(
          productName: '상품A',
          unconditionalPrice: 10000,
          regularPrice: 12000,
          currency: 'KRW',
          imageUrl: 'https://img.example/a.jpg',
          ambiguous: false,
          confidence: 'high',
        ),
      );

      expect(extract.name, '상품A');
      expect(extract.price, 10000);
      expect(extract.originalPrice, 12000);
      expect(extract.image, 'https://img.example/a.jpg');
      expect(extract.purchasePriceStatus, 'confirmed');
      expect(extract.priceConfidence, 'high');
      expect(extract.failureReason, isNull);
    });

    test('currency가 없어도(null) KRW로 간주해 가격을 쓴다', () {
      final extract = engineResultToOnDeviceExtract(
        const ExtractedProductDto(
          productName: '상품B',
          unconditionalPrice: 5000,
          ambiguous: false,
          confidence: 'medium',
        ),
      );
      expect(extract.price, 5000);
      expect(extract.failureReason, isNull);
    });

    test('ambiguous면 가격을 비우고 priceAmbiguous를 남긴다', () {
      final extract = engineResultToOnDeviceExtract(
        const ExtractedProductDto(
          productName: null,
          unconditionalPrice: null,
          regularPrice: null,
          currency: null,
          imageUrl: null,
          ambiguous: true,
          confidence: 'low',
        ),
      );

      expect(extract.price, isNull);
      expect(extract.purchasePriceStatus, 'unknown');
      expect(extract.priceConfidence, 'unknown');
      expect(extract.failureReason, ExtractFailureReason.priceAmbiguous);
    });

    test('모든 필드가 기본값(null/ambiguous=true)이어도 예외 없이 처리한다', () {
      final extract = engineResultToOnDeviceExtract(
        const ExtractedProductDto(),
      );
      expect(extract.name, isNull);
      expect(extract.price, isNull);
      expect(extract.image, isNull);
      expect(extract.failureReason, ExtractFailureReason.priceAmbiguous);
    });

    test('통화가 KRW가 아니면 가격을 비우고 unsupportedCurrency를 남긴다', () {
      final extract = engineResultToOnDeviceExtract(
        const ExtractedProductDto(
          productName: '해외 상품',
          unconditionalPrice: 100,
          regularPrice: 120,
          currency: 'USD',
          imageUrl: 'https://img.example/b.jpg',
          ambiguous: false,
          confidence: 'high',
        ),
      );

      expect(extract.price, isNull);
      expect(extract.originalPrice, isNull);
      // 통화 문제와 무관한 정보(이름·사진)는 그대로 남긴다.
      expect(extract.name, '해외 상품');
      expect(extract.image, 'https://img.example/b.jpg');
      expect(extract.failureReason, ExtractFailureReason.unsupportedCurrency);
    });

    test('unconditionalPrice가 0이면 null과 동일하게 취급한다', () {
      final extract = engineResultToOnDeviceExtract(
        const ExtractedProductDto(
          productName: '상품C',
          unconditionalPrice: 0,
          currency: 'KRW',
          ambiguous: false,
          confidence: 'high',
        ),
      );
      expect(extract.price, isNull);
      expect(extract.failureReason, ExtractFailureReason.priceAmbiguous);
    });
  });

  group('AppSyncEngineClient', () {
    test(
      '기본 timeout은 27초다(AppSync 30초 하드 리밋보다 짧게 먼저 포기)',
      () {
        final client = AppSyncEngineClient(
          _FakeEngineAppSync((_, __, ___) async => const {}),
        );
        expect(client.timeout, const Duration(seconds: 27));
      },
    );

    test('extractProduct 쿼리를 로그인 권한으로, url 변수와 함께 보낸다', () async {
      final fake = _FakeEngineAppSync((document, variables, auth) async {
        return {
          'extractProduct': {
            'productName': '무신사 반소매',
            'unconditionalPrice': 29000,
            'regularPrice': 39000,
            'currency': 'KRW',
            'imageUrl': 'https://img.example/x.jpg',
            'ambiguous': false,
            'ambiguityReason': null,
            'confidence': 'high',
          },
        };
      });
      final client = AppSyncEngineClient(fake);

      final dto = await client.extract('https://www.musinsa.com/products/1');

      expect(fake.lastDocument, Gql.extractProduct);
      expect(fake.lastVariables, {'url': 'https://www.musinsa.com/products/1'});
      expect(fake.lastAuth, GqlAuth.user);
      expect(dto.productName, '무신사 반소매');
      expect(dto.unconditionalPrice, 29000);
    });

    test('응답에 extractProduct가 없으면 예외를 던진다', () async {
      final fake = _FakeEngineAppSync((document, variables, auth) async {
        return <String, dynamic>{};
      });
      final client = AppSyncEngineClient(fake);

      expect(
        () => client.extract('https://shop.example/p'),
        throwsA(isA<FormatException>()),
      );
    });

    test('타임아웃을 넘기면 TimeoutException을 던진다', () async {
      final fake = _FakeEngineAppSync((document, variables, auth) async {
        return Future.delayed(
          const Duration(milliseconds: 50),
          () => {
            'extractProduct': {'ambiguous': true},
          },
        );
      });
      final client = AppSyncEngineClient(
        fake,
        timeout: const Duration(milliseconds: 5),
      );

      expect(
        () => client.extract('https://shop.example/p'),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}
