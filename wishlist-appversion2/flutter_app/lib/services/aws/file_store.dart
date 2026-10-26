import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';

/// 파일 배달망(CloudFront) 주소. 앱 시작 때 amplify_setup.dart 가 채운다.
/// 예: https://d1234abcd.cloudfront.net
class FilesConfig {
  FilesConfig._();

  /// 앱용 배달망(한국에서만 열림). 프로필 사진·태그 사진.
  static String baseUrl = '';

  /// 공유 페이지 전용 배달망(나라 제한 없음, share-pages/ 폴더만 연결). backend.ts 참고.
  /// 비어 있으면(옛 백엔드) 앱용 배달망 주소로 공유 링크를 만든다.
  static String sharePagesBaseUrl = '';
}

/// 파일 올리기·지우기의 실제 수단. 테스트에서는 가짜로 바꿔 끼운다.
abstract interface class FileTransport {
  /// [relativePath] 는 "내 폴더" 아래 경로 (예: '1727...jpg').
  /// [folder] 는 'avatars' · 'share-pages' · 'tag-photos' 중 하나.
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

/// 4단계: 프로필 사진 · 살까말까 공유 페이지.
///
/// - 올린 파일의 주소는 `https://<배달망>/<경로>` 영구 주소다. (DB 에 저장해도 깨지지 않음)
/// - 파일 이름에 시각을 붙여 매번 새 이름으로 올린다 → 사진을 바꾸면 캐시 때문에
///   옛 사진이 보이는 일이 없다. 옛 프로필 사진은 새로 올린 뒤 지운다.
/// - 공유 페이지는 S3 가 28일 뒤 자동으로 지운다 (backend.ts).
class AwsFileStore {
  AwsFileStore({
    FileTransport? transport,
    String? baseUrl,
    String? sharePagesBaseUrl,
    DateTime Function()? now,
  })  : _t = transport ?? const AmplifyFileTransport(),
        _baseUrl = baseUrl,
        _sharePagesBaseUrl = sharePagesBaseUrl,
        _now = now ?? DateTime.now;

  final FileTransport _t;
  final String? _baseUrl;
  final String? _sharePagesBaseUrl;
  final DateTime Function() _now;

  static const avatarMaxBytes = 5 * 1024 * 1024;
  static const sharePageMaxBytes = 1 * 1024 * 1024;
  static const tagPhotoMaxBytes = 5 * 1024 * 1024;
  static const _myFolders = ['avatars', 'share-pages', 'tag-photos'];

  String get baseUrl {
    final b = _trimSlash((_baseUrl ?? FilesConfig.baseUrl).trim());
    if (b.isEmpty) {
      throw Exception('파일 저장소 설정이 아직 없어요. sandbox 를 다시 실행해 주세요.');
    }
    return b;
  }

  /// S3 경로 → 영구 주소. 경로의 각 부분을 안전하게 인코딩한다.
  String urlFor(String path) => '$baseUrl/${_encodePath(path)}';

  static const _sharePagesFolder = 'share-pages/';

  /// 공유 페이지 S3 경로 → SNS로 보낼 주소.
  /// 공유 배달망은 share-pages/ 폴더에 바로 연결돼 있어서, 주소에서는 'share-pages/' 를 뺀다.
  /// 공유 배달망 주소가 없으면(옛 백엔드) 앱용 배달망 주소를 쓴다 — 이 경우 해외에서는 안 열린다.
  String sharePageUrlFor(String path) {
    final shareBase = _trimSlash((_sharePagesBaseUrl ?? FilesConfig.sharePagesBaseUrl).trim());
    if (shareBase.isEmpty || !path.startsWith(_sharePagesFolder)) return urlFor(path);
    return '$shareBase/${_encodePath(path.substring(_sharePagesFolder.length))}';
  }

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
    return sharePageUrlFor(path);
  }

  /// 태그 사진으로 담은 상품의 태그 사진을 올리고 영구 주소를 돌려준다.
  ///
  /// 파일 이름은 추측할 수 없는 무작위 값이다 — 주소는 주인의 상품 기록에만 저장되고,
  /// 친구에게 보이는 공개 목록에는 들어가지 않는다.
  Future<String> uploadTagPhoto(List<int> bytes, {required String mimeType}) async {
    if (bytes.isEmpty) throw Exception('태그 사진이 비어 있어요.');
    if (bytes.length > tagPhotoMaxBytes) {
      throw Exception('태그 사진은 5MB 이하만 저장할 수 있어요.');
    }
    final (ext, type) = switch (mimeType) {
      'image/png' => ('png', 'image/png'),
      'image/webp' => ('webp', 'image/webp'),
      'image/heic' || 'image/heif' => ('heic', 'image/heic'),
      _ => ('jpg', 'image/jpeg'),
    };
    final path = await _t.upload(
      folder: 'tag-photos',
      relativePath: '${_randomName()}.$ext',
      file: null,
      bytes: bytes,
      contentType: type,
    );
    return urlFor(path);
  }

  /// [url] 이 내 태그 사진 주소면 그 파일을 지운다. 아니면 아무것도 안 한다.
  /// (상품을 지울 때 함께 부른다 — 실패해도 상품 삭제는 막지 않게 호출하는 쪽에서 감싼다)
  Future<void> removeTagPhoto(String url) async {
    final prefix = '$baseUrl/';
    if (!url.startsWith(prefix)) return;
    final path = url.substring(prefix.length).split('/').map(Uri.decodeComponent).join('/');
    if (!path.startsWith('tag-photos/')) return;
    await _t.removeAll([path]);
  }

  /// 회원 탈퇴: 내 폴더의 파일을 모두 지운다.
  Future<void> deleteAll() async {
    final all = <String>[
      for (final folder in _myFolders) ...await _safeList(folder),
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

  static String _encodePath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  static String _trimSlash(String url) =>
      url.endsWith('/') ? url.substring(0, url.length - 1) : url;

  static String _safeSegment(String raw) {
    final s = raw.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return s.isEmpty ? 'x' : s;
  }

  String _stamp() => '${_now().millisecondsSinceEpoch}';

  static final _rng = Random.secure();

  /// 128비트 무작위 이름(32자리 16진수). 주소를 추측할 수 없게 한다.
  static String _randomName() =>
      List.generate(16, (_) => _rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

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
