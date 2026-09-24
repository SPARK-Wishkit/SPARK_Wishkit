import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/services/aws/file_store.dart';

/// S3 를 흉내 내는 가짜. 내 폴더(<folder>/me-id/...)만 다룬다.
class FakeTransport implements FileTransport {
  static const identity = 'ap-northeast-2:me-id';
  final files = <String, (List<int>?, String)>{}; // path → (bytes, contentType)

  @override
  Future<String> upload({
    required String folder,
    required String relativePath,
    required File? file,
    required List<int>? bytes,
    required String contentType,
  }) async {
    final path = '$folder/$identity/$relativePath';
    files[path] = (bytes ?? await file!.readAsBytes(), contentType);
    return path;
  }

  @override
  Future<List<String>> list(String folder) async =>
      files.keys.where((p) => p.startsWith('$folder/$identity/')).toList();

  @override
  Future<void> removeAll(List<String> paths) async {
    for (final p in paths) {
      files.remove(p);
    }
  }
}

void main() {
  late FakeTransport s3;
  late AwsFileStore store;
  late Directory tmp;
  var clock = 1000;

  Future<File> fileOf(String name, int size) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(List.filled(size, 7));
    return f;
  }

  setUp(() async {
    s3 = FakeTransport();
    clock = 1000;
    store = AwsFileStore(
      transport: s3,
      baseUrl: 'https://cdn.example.net/',
      now: () => DateTime.fromMillisecondsSinceEpoch(clock++),
    );
    tmp = await Directory.systemTemp.createTemp('files_test');
  });

  tearDown(() => tmp.delete(recursive: true));

  test('영구 주소: 배달망 주소 + 경로, 특수문자는 안전하게 인코딩', () {
    expect(
      store.urlFor('avatars/ap-northeast-2:abc/1.jpg'),
      'https://cdn.example.net/avatars/ap-northeast-2%3Aabc/1.jpg',
    );
  });

  test('확장자별 형식 (이미지가 아니면 jpg — 기존 동작)', () {
    expect(AwsFileStore.imageType('a.PNG'), ('png', 'image/png'));
    expect(AwsFileStore.imageType('a.webp'), ('webp', 'image/webp'));
    expect(AwsFileStore.imageType('a.jpeg'), ('jpg', 'image/jpeg'));
    expect(AwsFileStore.imageType('a.heic'), ('jpg', 'image/jpeg'));
  });

  test('프로필 사진: 매번 새 이름으로 올리고, 옛 사진은 지운다', () async {
    final first = await store.uploadAvatar(await fileOf('a.png', 10));
    final second = await store.uploadAvatar(await fileOf('b.png', 10));
    expect(first, isNot(second), reason: '같은 주소면 캐시 때문에 옛 사진이 보인다');
    expect(s3.files.keys.where((p) => p.startsWith('avatars/')).length, 1);
    expect(second, contains('/avatars/'));
    expect(s3.files.values.single.$2, 'image/png');
  });

  test('프로필 사진 5MB 넘으면 거절', () async {
    await expectLater(
      store.uploadAvatar(await fileOf('big.jpg', 5 * 1024 * 1024 + 1)),
      throwsA(predicate((e) => e.toString().contains('5MB'))),
    );
    expect(s3.files, isEmpty);
  });

  test('리뷰 사진: 리뷰별 폴더, 8MB 제한', () async {
    final url = await store.uploadReviewPhoto(
      reviewId: 'r/1',
      file: await fileOf('p.jpg', 10),
      index: 0,
    );
    expect(url, contains('/reviews/'));
    expect(s3.files.keys.single, contains('/r_1/0-')); // 경로에 쓸 수 없는 글자는 바꾼다
    await expectLater(
      store.uploadReviewPhoto(
        reviewId: 'r1',
        file: await fileOf('big.jpg', 8 * 1024 * 1024 + 1),
        index: 1,
      ),
      throwsA(predicate((e) => e.toString().contains('8MB'))),
    );
  });

  test('공유 페이지: 같은 id 로 다시 올리면 같은 주소에 덮어쓴다', () async {
    final a = await store.uploadSharePage(pageId: 'page1', html: '<p>하나</p>');
    final b = await store.uploadSharePage(pageId: 'page1', html: '<p>둘</p>');
    expect(a, b, reason: '친구에게 보낸 링크가 계속 유효해야 한다');
    expect(s3.files.length, 1);
    expect(s3.files.values.single.$2, 'text/html; charset=utf-8');
  });

  test('공유 페이지 1MB 넘으면 거절', () async {
    await expectLater(
      store.uploadSharePage(pageId: 'p', html: 'x' * (1024 * 1024 + 1)),
      throwsA(predicate((e) => e.toString().contains('너무 커요'))),
    );
  });

  test('회원 탈퇴: 세 폴더의 내 파일을 모두 지운다', () async {
    await store.uploadAvatar(await fileOf('a.jpg', 1));
    await store.uploadReviewPhoto(reviewId: 'r', file: await fileOf('b.jpg', 1), index: 0);
    await store.uploadSharePage(pageId: 'p', html: 'x');
    await store.deleteAll();
    expect(s3.files, isEmpty);
  });

  test('배달망 주소가 없으면 알기 쉬운 안내', () {
    final noCdn = AwsFileStore(transport: s3, baseUrl: '');
    expect(
      () => noCdn.urlFor('x'),
      throwsA(predicate((e) => e.toString().contains('sandbox'))),
    );
  });
}
