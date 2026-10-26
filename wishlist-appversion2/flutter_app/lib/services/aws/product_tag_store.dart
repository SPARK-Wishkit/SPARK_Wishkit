import 'dart:convert';
import 'dart:typed_data';

import '../../models/models.dart';
import 'gql_documents.dart';
import 'gql_runner.dart';

/// 태그 사진으로 상품 페이지 찾기 — 서버 함수(parsing-proxy → 엔진 POST /identify-tag).
///
/// 로그인 사용자만 부를 수 있다. 사진은 base64로 보내므로, 부르기 전에 작게 줄여서 보낸다
/// (화면에서 ImagePicker maxWidth 1280 · JPEG 75%).
class AwsProductTagStore {
  AwsProductTagStore({GqlRunner? runner})
    : _gql = runner ?? const AmplifyGqlRunner();

  final GqlRunner _gql;

  /// 서버가 받는 최대 크기(엔진 IDENTIFY_MAX_IMAGE_BYTES와 같음).
  static const maxImageBytes = 4 * 1024 * 1024;

  Future<TagIdentifyResult> identify(Uint8List image, String mimeType) async {
    if (image.isEmpty) {
      throw ArgumentError('사진이 비어 있어요');
    }
    if (image.length > maxImageBytes) {
      throw ArgumentError('사진이 너무 커요');
    }
    final data = await _gql.query(
      Gql.identifyProductTag,
      variables: {'imageBase64': base64Encode(image), 'mimeType': mimeType},
    );
    final raw = data['identifyProductTag'];
    if (raw is! Map) {
      return const TagIdentifyResult(status: TagIdentifyStatus.notFound);
    }
    return TagIdentifyResult.fromJson(raw.cast<String, dynamic>());
  }
}
