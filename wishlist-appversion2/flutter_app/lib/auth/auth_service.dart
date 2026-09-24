import 'auth_models.dart';

/// 로그인 서비스가 해야 하는 일의 목록.
///
/// 실제 구현은 [CognitoAuthService] (cognito_auth_service.dart).
/// 테스트에서는 가짜 구현을 넣어 AWS 없이도 [AuthController] 를 검증한다.
///
/// 모든 메서드는 실패하면 [AuthFailure] 만 던진다.
abstract interface class AuthService {
  /// 저장된 세션이 있으면 사용자 정보를, 없으면 null.
  Future<AuthUserInfo?> currentUser();

  /// 세션이 밖에서 끝났을 때(만료, 다른 곳에서 삭제 등) 알려 준다.
  Stream<void> get sessionEnded;

  /// 가입 요청. 성공하면 이메일로 인증 코드가 간다.
  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    required String handle,
  });

  /// 인증 코드 확인.
  Future<void> confirmSignUp({required String email, required String code});

  Future<void> resendSignUpCode({required String email});

  /// 로그인. 이메일 인증이 안 된 계정이면 [SignInOutcome.needsVerification].
  Future<SignInOutcome> signIn({
    required String email,
    required String password,
  });

  Future<void> signOut();

  /// 비밀번호 재설정 코드 발송. 성공 시 코드를 보낸 곳(가려진 이메일)을 돌려준다.
  Future<String?> requestPasswordReset({required String email});

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  });

  /// 로그인 상태에서 비밀번호 변경. 현재 비밀번호가 틀리면 실패한다.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// 로그인 상태에서 현재 비밀번호가 맞는지 확인한다 (탈퇴 등 민감한 작업 전).
  Future<void> verifyPassword(String password);

  /// 로그인한 본인 계정을 Cognito에서 삭제한다.
  Future<void> deleteCurrentUser();
}

enum SignInOutcome { signedIn, needsVerification }
