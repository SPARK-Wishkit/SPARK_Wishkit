import 'package:amplify_auth_cognito/amplify_auth_cognito.dart';
import 'package:amplify_flutter/amplify_flutter.dart';

import 'auth_models.dart';
import 'auth_validators.dart';

/// Amplify/Cognito 예외 → 화면에 보여 줄 한국어 [AuthFailure].
///
/// 화면 코드는 이 함수를 직접 부를 일이 없다. 서비스가 이미 변환해서 던진다.
AuthFailure mapAuthException(AmplifyException e) {
  AuthFailure f(AuthFailureCode code, String message) =>
      AuthFailure(code, message);

  return switch (e) {
    NetworkException() =>
      f(AuthFailureCode.network, '네트워크 연결을 확인해 주세요.'),
    UsernameExistsException() || AliasExistsException() => f(
        AuthFailureCode.emailAlreadyUsed,
        '이미 가입된 이메일이에요. 인증을 끝내지 않았다면 로그인하면 인증 단계로 이어져요.',
      ),
    NotAuthorizedServiceException(:final message)
        when message.toLowerCase().contains('attempts exceeded') =>
      f(
        AuthFailureCode.tooManyRequests,
        '로그인 시도가 너무 많아요. 잠시 후 다시 시도해 주세요.',
      ),
    NotAuthorizedServiceException() || UserNotFoundException() => f(
        AuthFailureCode.wrongCredentials,
        '이메일 또는 비밀번호가 맞지 않아요.',
      ),
    UserNotConfirmedException() => f(
        AuthFailureCode.notConfirmed,
        '이메일 인증이 아직 끝나지 않았어요.',
      ),
    CodeMismatchException() => f(
        AuthFailureCode.codeMismatch,
        '인증 코드가 맞지 않아요. 메일의 숫자 6자리를 다시 확인해 주세요.',
      ),
    ExpiredCodeException() => f(
        AuthFailureCode.codeExpired,
        '인증 코드가 만료됐어요. 코드를 다시 받아 주세요.',
      ),
    InvalidPasswordException() => f(
        AuthFailureCode.weakPassword,
        '비밀번호는 ${AuthValidators.passwordMinLength}자 이상, 숫자를 포함해야 해요.',
      ),
    LimitExceededException() ||
    TooManyRequestsException() ||
    TooManyFailedAttemptsException() =>
      f(
        AuthFailureCode.tooManyRequests,
        '요청이 너무 많아요. 잠시 후 다시 시도해 주세요.',
      ),
    CodeDeliveryFailureException() => f(
        AuthFailureCode.unknown,
        '인증 메일을 보내지 못했어요. 이메일 주소를 확인하고 다시 시도해 주세요.',
      ),
    UserLambdaValidationException(:final message) => _fromPreSignUp(message),
    InvalidParameterException() || AuthValidationException() => f(
        AuthFailureCode.invalidInput,
        '입력한 내용을 다시 확인해 주세요.',
      ),
    SignedOutException() || SessionExpiredException() => f(
        AuthFailureCode.notSignedIn,
        '로그인이 풀렸어요. 다시 로그인해 주세요.',
      ),
    _ => f(AuthFailureCode.unknown, '요청에 실패했어요. 잠시 후 다시 시도해 주세요.'),
  };
}

/// amplify/auth/pre-sign-up/handler.ts 가 던지는 PSU_ 코드.
AuthFailure _fromPreSignUp(String message) {
  const invalid = AuthFailureCode.invalidInput;
  if (message.contains('PSU_HANDLE_FORMAT')) {
    return AuthFailure(invalid, AuthValidators.handle('!')!);
  }
  if (message.contains('PSU_HANDLE_REQUIRED')) {
    return const AuthFailure(invalid, '아이디를 입력해 주세요.');
  }
  if (message.contains('PSU_NAME_TOO_LONG')) {
    return AuthFailure(invalid, AuthValidators.name('x' * 999)!);
  }
  if (message.contains('PSU_EMAIL_REQUIRED')) {
    return const AuthFailure(invalid, '이메일을 입력해 주세요.');
  }
  return const AuthFailure(invalid, '입력한 내용을 다시 확인해 주세요.');
}
