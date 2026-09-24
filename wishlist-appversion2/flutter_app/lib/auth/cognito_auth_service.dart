import 'dart:async';

import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

import 'auth_error_messages.dart';
import 'auth_models.dart';
import 'auth_service.dart';
import 'auth_validators.dart';

/// [AuthService] 의 AWS Cognito(Amplify) 구현.
///
/// - 로그인 username 은 항상 "정규화된 이메일"(소문자, 공백 제거)을 쓴다.
/// - Amplify 예외는 전부 [AuthFailure] 로 바꿔서 던진다.
/// - 비밀번호/토큰/이메일은 절대 로그에 남기지 않는다.
class CognitoAuthService implements AuthService {
  CognitoAuthService() {
    // signedIn/signedOut 은 우리가 직접 호출한 결과라 여기서 다루지 않는다.
    // (비동기로 늦게 도착한 signedOut 이 방금 한 로그인을 지우는 경쟁 상태를 막기 위함)
    _hubSub = Amplify.Hub.listen(HubChannel.Auth, (AuthHubEvent event) {
      switch (event.type) {
        case AuthHubEventType.sessionExpired:
        case AuthHubEventType.userDeleted:
          _sessionEnded.add(null);
        case AuthHubEventType.signedIn:
        case AuthHubEventType.signedOut:
          break;
      }
    });
  }

  final _sessionEnded = StreamController<void>.broadcast();
  StreamSubscription<AuthHubEvent>? _hubSub;

  @override
  Stream<void> get sessionEnded => _sessionEnded.stream;

  /// 테스트나 핫 리스타트 시 정리용.
  Future<void> dispose() async {
    await _hubSub?.cancel();
    await _sessionEnded.close();
  }

  // ── 세션 ─────────────────────────────────────────────────────

  @override
  Future<AuthUserInfo?> currentUser() => _guard(() async {
        final session =
            await Amplify.Auth.fetchAuthSession() as CognitoAuthSession;
        if (!session.isSignedIn) return null;

        final tokensResult = session.userPoolTokensResult;
        final idToken = tokensResult.valueOrNull?.idToken;
        if (idToken != null) {
          return AuthUserInfo(
            uid: idToken.userId,
            email: AuthValidators.normalizeEmail(idToken.email ?? ''),
            signupName: _nonEmpty(idToken.name),
            signupHandle: _nonEmpty(idToken.preferredUsername),
          );
        }

        // 토큰을 새로 받지 못한 경우.
        // 세션 만료 → 로그아웃 처리. 그 외(주로 오프라인) → 저장된 정보로 로그인 유지.
        final error = tokensResult.exception;
        if (error is SessionExpiredException || error is SignedOutException) {
          return null;
        }
        final user = await Amplify.Auth.getCurrentUser();
        final details = user.signInDetails;
        return AuthUserInfo(
          uid: user.userId,
          email: details is CognitoSignInDetailsApiBased
              ? AuthValidators.normalizeEmail(details.username)
              : '',
        );
      });

  // ── 가입 ─────────────────────────────────────────────────────

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    required String handle,
  }) =>
      _guard(() async {
        final normalizedEmail = AuthValidators.normalizeEmail(email);
        await Amplify.Auth.signUp(
          username: normalizedEmail,
          password: password,
          options: SignUpOptions(
            userAttributes: {
              AuthUserAttributeKey.email: normalizedEmail,
              if (name.trim().isNotEmpty)
                AuthUserAttributeKey.name: name.trim(),
              AuthUserAttributeKey.preferredUsername:
                  AuthValidators.normalizeHandle(handle),
            },
          ),
        );
      });

  @override
  Future<void> confirmSignUp({required String email, required String code}) =>
      _guard(() async {
        await Amplify.Auth.confirmSignUp(
          username: AuthValidators.normalizeEmail(email),
          confirmationCode: code.trim(),
        );
      });

  @override
  Future<void> resendSignUpCode({required String email}) => _guard(() async {
        await Amplify.Auth.resendSignUpCode(
          username: AuthValidators.normalizeEmail(email),
        );
      });

  // ── 로그인 / 로그아웃 ──────────────────────────────────────────

  @override
  Future<SignInOutcome> signIn({
    required String email,
    required String password,
  }) =>
      _guard(() async {
        final username = AuthValidators.normalizeEmail(email);
        SignInResult result;
        try {
          result = await Amplify.Auth.signIn(
            username: username,
            password: password,
          );
        } on InvalidStateException {
          // 이전 세션이 남아 있으면 정리하고 한 번만 다시 시도한다.
          await Amplify.Auth.signOut();
          result = await Amplify.Auth.signIn(
            username: username,
            password: password,
          );
        }

        switch (result.nextStep.signInStep) {
          case AuthSignInStep.done:
            return SignInOutcome.signedIn;
          case AuthSignInStep.confirmSignUp:
            return SignInOutcome.needsVerification;
          case AuthSignInStep.resetPassword:
            throw const AuthFailure(
              AuthFailureCode.wrongCredentials,
              '비밀번호 재설정이 필요해요. "비밀번호 찾기"로 새 비밀번호를 만들어 주세요.',
            );
          default:
            // MFA 등 이 앱이 쓰지 않는 단계. 설정 실수이므로 세션을 남기지 않는다.
            await Amplify.Auth.signOut();
            throw const AuthFailure(
              AuthFailureCode.unknown,
              '지원하지 않는 로그인 단계예요. 관리자에게 알려 주세요.',
            );
        }
      });

  @override
  Future<void> signOut() => _guard(() async {
        final result = await Amplify.Auth.signOut();
        if (result is CognitoFailedSignOut) {
          // 기기 안의 세션은 이미 지워졌을 수 있지만, 실패를 알려 다시 시도하게 한다.
          throw mapAuthException(result.exception);
        }
        // CognitoPartialSignOut: 기기 세션은 지워짐. 서버 토큰 폐기만 실패 → 로그아웃으로 본다.
      });

  // ── 비밀번호 ─────────────────────────────────────────────────

  @override
  Future<String?> requestPasswordReset({required String email}) =>
      _guard(() async {
        final result = await Amplify.Auth.resetPassword(
          username: AuthValidators.normalizeEmail(email),
        );
        return result.nextStep.codeDeliveryDetails?.destination;
      });

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) =>
      _guard(() async {
        await Amplify.Auth.confirmResetPassword(
          username: AuthValidators.normalizeEmail(email),
          newPassword: newPassword,
          confirmationCode: code.trim(),
        );
      });

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _guard(() async {
        await Amplify.Auth.updatePassword(
          oldPassword: currentPassword,
          newPassword: newPassword,
        );
      });

  @override
  Future<void> verifyPassword(String password) => _guard(() async {
        // Cognito에는 "비밀번호만 확인"하는 API가 없다.
        // 같은 비밀번호로 변경을 요청하면, 비밀번호가 맞을 때만 성공한다.
        // ⚠️ 나중에 User Pool에 "비밀번호 재사용 금지" 정책을 켜면 이 방법은 쓸 수 없다.
        await Amplify.Auth.updatePassword(
          oldPassword: password,
          newPassword: password,
        );
      });

  @override
  Future<void> deleteCurrentUser() => _guard(() async {
        await Amplify.Auth.deleteUser();
      });

  // ── 공통 ─────────────────────────────────────────────────────

  Future<T> _guard<T>(Future<T> Function() body) async {
    if (!Amplify.isConfigured) {
      throw const AuthFailure(
        AuthFailureCode.notConfigured,
        '로그인 서버 설정이 아직 안 됐어요. amplify_outputs.dart 를 확인해 주세요.',
      );
    }
    try {
      return await body();
    } on AuthFailure {
      rethrow;
    } on AmplifyException catch (e) {
      throw mapAuthException(e);
    }
  }

  static String? _nonEmpty(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();
}
