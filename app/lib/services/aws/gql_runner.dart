import 'dart:convert';

import 'package:amplify_api/amplify_api.dart';
import 'package:amplify_flutter/amplify_flutter.dart';
import 'package:flutter/foundation.dart';

/// AWS(AppSync) 데이터 요청이 실패했을 때 던지는 예외.
///
/// [toString] 은 화면에 그대로 보여 줘도 되는 한국어 문구다.
/// 개발용 원문은 [debugDetail] 에만 담고, 로그에도 이메일 같은 개인정보는 남기지 않는다.
class AwsDataException implements Exception {
  AwsDataException(this.debugDetail, {this.errorType});

  final String debugDetail;
  final String? errorType;

  /// "이미 있는 키로 만들기" 또는 "없는 항목 수정"처럼 조건이 맞지 않아 거절된 경우.
  bool get isConditionalCheckFailed =>
      (errorType ?? '').contains('ConditionalCheckFailed') ||
      debugDetail.contains('conditional request failed');

  bool get isUnauthorized =>
      (errorType ?? '').contains('Unauthorized') ||
      debugDetail.contains('Not Authorized');

  bool get isNetwork => errorType == 'Network';

  /// 서버 함수가 돌려준 약속된 오류 코드 (예: 'NOT_AUTHOR'). 없으면 null.
  String? get serverCode {
    final m = RegExp(r'^[A-Z][A-Z_]+$').firstMatch(debugDetail.trim());
    return m?.group(0);
  }

  @override
  String toString() => isNetwork
      ? '네트워크 연결을 확인해 주세요.'
      : '데이터 요청에 실패했어요. 잠시 후 다시 시도해 주세요.';
}

/// 요청을 누구 권한으로 보낼지.
enum GqlAuth {
  /// 로그인한 사용자 (Cognito User Pool 토큰)
  user,

  /// 비로그인 게스트 (Identity Pool 임시 권한).
  guest,

  /// 로그인돼 있으면 [user], 아니면 [guest]. 로그인 전후 모두 쓰는 조회(아이디 확인 등)용.
  auto,
}

/// GraphQL 요청을 보내는 쪽. 테스트에서는 가짜로 바꿔 끼운다.
abstract interface class GqlRunner {
  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, dynamic> variables,
    GqlAuth auth,
  });

  Future<Map<String, dynamic>> mutate(
    String document, {
    Map<String, dynamic> variables,
  });
}

/// 실제 AWS AppSync 로 요청을 보내는 구현.
class AmplifyGqlRunner implements GqlRunner {
  const AmplifyGqlRunner();

  @override
  Future<Map<String, dynamic>> query(
    String document, {
    Map<String, dynamic> variables = const {},
    GqlAuth auth = GqlAuth.user,
  }) =>
      _run(document, variables, auth, mutation: false);

  @override
  Future<Map<String, dynamic>> mutate(
    String document, {
    Map<String, dynamic> variables = const {},
  }) =>
      _run(document, variables, GqlAuth.user, mutation: true);

  Future<Map<String, dynamic>> _run(
    String document,
    Map<String, dynamic> variables,
    GqlAuth auth, {
    required bool mutation,
  }) async {
    final GraphQLResponse<String> response;
    try {
      final request = GraphQLRequest<String>(
        document: document,
        variables: variables,
        authorizationMode: await _modeFor(auth),
      );
      final operation = mutation
          ? Amplify.API.mutate(request: request)
          : Amplify.API.query(request: request);
      response = await operation.response;
    } on NetworkException catch (e) {
      throw AwsDataException(e.message, errorType: 'Network');
    } on AmplifyException catch (e) {
      debugPrint('AWS 요청 실패: ${e.runtimeType}');
      throw AwsDataException(e.message, errorType: 'Client');
    }

    if (response.hasErrors) {
      final first = response.errors.first;
      debugPrint('AWS 응답 오류: ${first.errorType}');
      throw AwsDataException(first.message, errorType: first.errorType);
    }

    final raw = response.data;
    if (raw == null || raw.isEmpty) return const {};
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, dynamic>() : const {};
  }

  /// 게스트 권한은 "로그인 안 한 사람"에게만 허용돼 있다.
  /// 로그인한 사람이 IAM 으로 보내면 게스트가 아니라 "로그인 사용자" 권한이 붙어 거절되므로,
  /// 로그인 여부를 보고 고른다.
  Future<APIAuthorizationType> _modeFor(GqlAuth auth) async {
    switch (auth) {
      case GqlAuth.user:
        return APIAuthorizationType.userPools;
      case GqlAuth.guest:
        return APIAuthorizationType.iam;
      case GqlAuth.auto:
        final session = await Amplify.Auth.fetchAuthSession();
        return session.isSignedIn
            ? APIAuthorizationType.userPools
            : APIAuthorizationType.iam;
    }
  }
}

/// AWSJSON 값 → Map. AppSync 는 JSON 을 문자열로 돌려주므로 풀어 준다.
/// (저장 경로에 따라 문자열이 한 번 더 감싸져 올 수도 있어 두 번까지 푼다)
Map<String, dynamic>? decodeAwsJson(Object? raw) {
  Object? v = raw;
  for (var i = 0; i < 2 && v is String; i++) {
    if (v.isEmpty) return null;
    v = jsonDecode(v);
  }
  return v is Map ? v.cast<String, dynamic>() : null;
}
