/// 로그인 영역에서 앱 전체로 내보내는 값들.
///
/// 앱 기능 코드는 Amplify/Cognito 타입을 직접 쓰지 말고 이 파일의 타입만 쓴다.
/// 그래야 로그인 구현이 바뀌어도 앱 기능 코드는 그대로 둘 수 있다.
library;

/// 현재 로그인 상태.
enum AuthStatus {
  /// 앱 시작 직후, 저장된 세션을 확인하는 중.
  unknown,

  /// 로그인 안 됨.
  signedOut,

  /// 가입(또는 로그인 시도)은 했지만 이메일 코드 인증이 남아 있음.
  awaitingVerification,

  /// 로그인 완료.
  signedIn,
}

/// 로그인한 사용자 정보.
///
/// [uid] 는 Cognito `sub` 이다. 앱 데이터의 모든 사용자 ID(uid, fromUid,
/// authorUid, ownerUid …)는 이 값을 쓴다. 절대 바뀌지 않는 값이다.
class AuthUserInfo {
  const AuthUserInfo({
    required this.uid,
    required this.email,
    this.signupName,
    this.signupHandle,
  });

  final String uid;
  final String email;

  /// 가입 때 입력한 이름 (가입 초안). 프로필을 처음 만들 때만 참고한다.
  final String? signupName;

  /// 가입 때 입력한 아이디, `@` 포함 (가입 초안). 프로필을 처음 만들 때만 참고한다.
  /// 아이디의 최종 원본은 앱 데이터의 프로필이다.
  final String? signupHandle;

  @override
  bool operator ==(Object other) =>
      other is AuthUserInfo &&
      other.uid == uid &&
      other.email == email &&
      other.signupName == signupName &&
      other.signupHandle == signupHandle;

  @override
  int get hashCode => Object.hash(uid, email, signupName, signupHandle);

  @override
  String toString() => 'AuthUserInfo(uid: $uid)'; // 이메일은 로그에 남기지 않는다.
}

/// 로그인 영역에서 나는 모든 오류. [message] 는 화면에 그대로 보여 줘도 되는 한국어 문구.
class AuthFailure implements Exception {
  const AuthFailure(this.code, this.message);

  final AuthFailureCode code;
  final String message;

  @override
  String toString() => message;
}

enum AuthFailureCode {
  invalidInput,
  emailAlreadyUsed,
  wrongCredentials,
  notConfirmed,
  codeMismatch,
  codeExpired,
  weakPassword,
  handleTaken,
  tooManyRequests,
  network,
  notSignedIn,
  notConfigured,
  unknown,
}

/// 앱 데이터 쪽(앱 기능 담당)이 채워 주는 연결 지점.
///
/// 로그인 코드는 데이터베이스를 직접 모른다. 필요한 일은 이 함수들로 부탁한다.
/// 넘겨주지 않으면(null) 해당 기능은 조용히 건너뛰거나 화면에서 숨긴다.
class AuthDataHooks {
  const AuthDataHooks({
    this.isHandleAvailable,
    this.findMaskedEmailByHandle,
    this.deleteMyData,
  });

  /// 가입 전에 아이디 중복을 미리 확인한다. true = 사용 가능.
  final Future<bool> Function(String handle)? isHandleAvailable;

  /// 아이디로 가입 이메일(가려진 형태, 예: k***n@gmail.com)을 찾는다. 없으면 null.
  final Future<String?> Function(String handle)? findMaskedEmailByHandle;

  /// 회원 탈퇴 직전, 로그인된 상태에서 내 데이터를 모두 지운다.
  /// 이게 성공해야만 Cognito 계정을 지운다.
  final Future<void> Function(String uid)? deleteMyData;
}
