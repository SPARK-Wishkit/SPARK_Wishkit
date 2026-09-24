import 'dart:convert';

import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:amplify_storage_s3/amplify_storage_s3.dart';

import '../services/aws/file_store.dart';

// `npx ampx sandbox --outputs-format dart --outputs-out-dir lib` 가 만들어 주는 파일.
// 사람마다(샌드박스마다) 내용이 달라서 깃에 올리지 않는다(.gitignore).
import '../amplify_outputs.dart';

/// Amplify 를 앱 시작 때 한 번 설정한다. 성공하면 null, 실패하면 오류 문구.
///
/// Amplify.configure 는 앱 전체에서 딱 한 번만 부를 수 있다.
/// 로그인(Auth) · 데이터(API) · 파일(Storage)을 넣는다. 그 밖의 플러그인은 [extraPlugins] 로.
Future<String?> configureAmplify({
  List<AmplifyPluginInterface> extraPlugins = const [],
}) async {
  if (Amplify.isConfigured) return null;
  try {
    await Amplify.addPlugins([
      AmplifyAuthCognito(),
      AmplifyAPI(),
      AmplifyStorageS3(),
      ...extraPlugins,
    ]);
    await Amplify.configure(amplifyConfig);
    FilesConfig.baseUrl = _customValue('filesBaseUrl');
    return null;
  } on AmplifyAlreadyConfiguredException {
    return null;
  } on AmplifyException catch (e) {
    return 'AWS 설정에 실패했어요: ${e.message}';
  }
}

/// amplify_outputs 의 custom 값 (backend.ts 의 addOutput). 없으면 빈 문자열.
String _customValue(String key) {
  try {
    final config = jsonDecode(amplifyConfig);
    final custom = config is Map ? config['custom'] : null;
    final value = custom is Map ? custom[key] : null;
    return value is String ? value : '';
  } catch (_) {
    return '';
  }
}
