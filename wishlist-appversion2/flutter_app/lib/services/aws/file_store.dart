import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';

/// 파일 배달망(CloudFront) 주소. 앱 시작 때 amplify_setup.dart 가 채운다.
/// 예: https://d1234abcd.cloudfront.net
class FilesConfig {
  FilesConfig._();
  static String baseUrl = '';
}

/// 파일 올리기·지우기의 실제 수단. 테스트에서는 가짜로 바꿔 끼운다.
abstract interface class FileTransport {
  /// [relativePath] 는 "내 폴더" 아래 경로 (예: '1727...jpg').
  /// [folder] 는 'avatars' · 'reviews' · 'share-pages' 중 하나.
  /// 올라간 전체 경로(S3 키)를 돌려준다.
  Future<String> upload({
    required String folder,
    required String relativePath,
    required File? file,
    required List<int>? bytes,
    required String contentType,
  });

  /// [folder] 안의 내 파일 경로 목록 (하위 폴더 포함).
  Future<List<String>> list(String folder);

  Future<void> removeAll(List<String> paths);
}

/// Amplify Storage(S3) 로 올리는 실제 구현.
/// 경로는 항상 `<folder>/<내 Identity ID>/...` → 남의 폴더에는 서버 규칙상 쓸 수 없다.
class AmplifyFileTransport implements FileTransport {
  const AmplifyFileTransport();

  StoragePath _mine(String folder, String rest) =>
      StoragePath.fromIdentityId((id) => '$folder/$id/$rest');

  @override
  Future<String> upload({
    required String folder,
    required String relativePath,
    required File? file,
    required List<int>? bytes,
    required String contentType,
  }) async {
    final path = _mine(folder, relativePath);
    if (file != null) {
      final r = await Amplify.Storage.uploadFile(
        localFile: AWSFile.fromPath(file.path, contentType: contentType),
        path: path,
      ).result;
      return r.uploadedItem.path;
    }
    final r = await Amplify.Storage.uploadData(
      data: StorageDataPayload.bytes(bytes!, contentType: contentType),
      path: path,
    ).result;
    return r.uploadedItem.path;
  }

  @override
  Future<List<String>> list(String folder) async {
    final r = await Amplify.Storage.list(
      path: _mine(folder, ''),
      options: StorageListOptions(
        pluginOptions: const S3ListPluginOptions.listAll(),
      ),
    ).result;
    return r.items.map((i) => i.path).toList();
  }

  @override
  Future<void> removeAll(List<String> paths) async {
    for (var i = 0; i < paths.length; i += 900) {
      final chunk = paths.sublist(i, min(i + 900, paths.length));
      await Amplify.Storage.removeMany(
        paths: [for (final p in chunk) StoragePath.fromString(p)],
      ).result;
    }
  }
}

/// 4단계: 프로필 사진 · 리뷰 사진 · 살까말까 공유 페이지.
///
/// - 올린 파일의 주소는 `https://<배달망>/<경로>` 영구 주소다. (DB 에 저장해도 깨지지 않음)
/// - 파일 이름에 시각을 붙여 매번 새 이름으로 올린다 → 사진을 바꾸면 캐시 때문에
///   옛 사진이 보이는 일이 없다. 옛 프로필 사진은 새로 올린 뒤 지운다.
/// - 공유 페이지는 S3 가 28일 뒤 자동으로 지운다 (backend.ts).
class AwsFileStore {
  AwsFileStore({FileTransport? transport, String? baseUrl, DateTime Function()? now})
      : _t = transport ?? const AmplifyFileTransport(),
        _baseUrl = baseUrl,
        _now = now ?? DateTime.now;

  final FileTransport _t;
  final String? _baseUrl;
  final DateTime Function() _now;

  static const avatarMaxBytes = 5 * 1024 * 1024;
  static const reviewMaxBytes = 8 * 1024 * 1024;
  static const sharePageMaxBytes = 1 * 1024 * 1024;

  String get baseUrl {
    final b = (_baseUrl ?? FilesConfig.baseUrl).trim();
    if (b.isEmpty) {
      throw Exception('파일 저장소 설정이 아직 없어요. sandbox 를 다시 실행해 주세요.');
    }
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  /// S3 경로 → 영구 주소. 경로의 각 부분을 안전하게 인코딩한다.
  String urlFor(String path) =>
      '$baseUrl/${path.split('/').map(Uri.encodeComponent).join('/')}';

  Future<String> uploadAvatar(File file) async {
    final (ext, type) = imageType(file.path);
    await _checkSize(file, avatarMaxBytes, '프로필 사진은 5MB 이하만 올릴 수 있어요.');
    final previous = await _safeList('avatars');
    final path = await _t.upload(
      folder: 'avatars',
      relativePath: '${_stamp()}.$ext',
      file: file,
      bytes: null,
      contentType: type,
    );
    // 옛 프로필 사진 정리 (실패해도 새 사진은 이미 올라감)
    try {
      await _t.removeAll(previous.where((p) => p != path).toList());
    } catch (_) {}
    return urlFor(path);
  }

  Future<String> uploadReviewPhoto({
    required String reviewId,
    required File file,
    required int index,
  }) async {
    final (ext, type) = imageType(file.path);
    await _checkSize(file, reviewMaxBytes, '리뷰 사진은 8MB 이하만 올릴 수 있어요.');
    final path = await _t.upload(
      folder: 'reviews',
      relativePath: '${_safeSegment(reviewId)}/$index-${_stamp()}.$ext',
      file: file,
      bytes: null,
      contentType: type,
    );
    return urlFor(path);
  }

  /// 같은 [pageId] 로 다시 올리면 같은 주소에 덮어쓴다 (보낸 링크가 그대로 유효).
  Future<String> uploadSharePage({
    required String pageId,
    required String html,
  }) async {
    final bytes = _utf8(html);
    if (bytes.length > sharePageMaxBytes) {
      throw Exception('공유 페이지가 너무 커요. 상품 수를 줄여 주세요.');
    }
    final path = await _t.upload(
      folder: 'share-pages',
      relativePath: '${_safeSegment(pageId)}.html',
      file: null,
      bytes: bytes,
      contentType: 'text/html; charset=utf-8',
    );
    return urlFor(path);
  }

  /// 회원 탈퇴: 내 폴더의 파일을 모두 지운다.
  Future<void> deleteAll() async {
    final all = <String>[
      for (final folder in const ['avatars', 'reviews', 'share-pages'])
        ...await _safeList(folder),
    ];
    if (all.isNotEmpty) await _t.removeAll(all);
  }

  // ── 도우미 ─────────────────────────────────────────────────

  /// 파일 확장자 → (저장할 확장자, Content-Type). 이미지가 아니면 jpg 로 본다 (기존 동작).
  static (String, String) imageType(String filePath) {
    final ext = filePath.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => ('png', 'image/png'),
      'webp' => ('webp', 'image/webp'),
      _ => ('jpg', 'image/jpeg'),
    };
  }

  static String _safeSegment(String raw) {
    final s = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return s.isEmpty ? 'x' : s;
  }

  String _stamp() => '${_now().millisecondsSinceEpoch}';

  Future<List<String>> _safeList(String folder) async {
    try {
      return await _t.list(folder);
    } catch (_) {
      return const [];
    }
  }

  static Future<void> _checkSize(File file, int max, String message) async {
    if (await file.length() > max) throw Exception(message);
  }

  static List<int> _utf8(String s) => utf8.encode(s);
}
