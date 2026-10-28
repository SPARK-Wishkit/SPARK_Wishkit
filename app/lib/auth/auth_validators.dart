/// 입력값 검사. 서버(amplify/auth/pre-sign-up/handler.ts, backend.ts의
/// 비밀번호 규칙)와 같은 규칙을 앱에서도 먼저 검사해 빠르게 안내한다.
///
/// ⚠️ 규칙을 바꾸면 서버 쪽도 같이 바꿀 것.
library;

class AuthValidators {
  AuthValidators._();

  static const passwordMinLength = 8;
  static const nameMaxLength = 30;
  static const codeLength = 6;

  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final _handle = RegExp(r'^[a-z0-9][a-z0-9._]{1,18}[a-z0-9]$');
  static final _digit = RegExp(r'\d');
  static final _code = RegExp(r'^\d{6}$');

  /// 이메일을 비교·저장용 형태로 맞춘다.
  static String normalizeEmail(String raw) => raw.trim().toLowerCase();

  /// 아이디를 `@소문자` 형태로 맞춘다. 빈 값이면 빈 문자열.
  static String normalizeHandle(String raw) {
    final h = raw.trim().replaceAll(RegExp(r'\s+'), '').replaceFirst(
          RegExp(r'^@+'),
          '',
        );
    return h.isEmpty ? '' : '@${h.toLowerCase()}';
  }

  /// 문제가 없으면 null, 있으면 한국어 안내 문구.
  static String? email(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '이메일을 입력해 주세요.';
    if (!_email.hasMatch(v)) return '이메일 형식이 올바르지 않아요.';
    return null;
  }

  static String? password(String raw) {
    if (raw.isEmpty) return '비밀번호를 입력해 주세요.';
    if (raw.length < passwordMinLength) {
      return '비밀번호는 $passwordMinLength자 이상이어야 해요.';
    }
    if (!_digit.hasMatch(raw)) return '비밀번호에 숫자를 하나 이상 넣어 주세요.';
    if (raw.trim() != raw) return '비밀번호 앞뒤에는 공백을 넣을 수 없어요.';
    return null;
  }

  static String? handle(String raw) {
    final h = normalizeHandle(raw);
    if (h.isEmpty) return '아이디를 입력해 주세요.';
    final body = h.substring(1);
    if (!_handle.hasMatch(body) || body.contains('..')) {
      return '아이디는 영문 소문자·숫자·마침표(.)·밑줄(_)로 3~20자, '
          '처음과 끝은 영문이나 숫자여야 해요.';
    }
    return null;
  }

  static String? name(String raw) {
    if (raw.trim().length > nameMaxLength) {
      return '이름은 $nameMaxLength자 이하로 입력해 주세요.';
    }
    return null;
  }

  static String? code(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '인증 코드를 입력해 주세요.';
    if (!_code.hasMatch(v)) return '인증 코드는 숫자 $codeLength자리예요.';
    return null;
  }

  /// 로그인한 사용자 본인에게 보여 줄 가려진 이메일. 예: k***n@gmail.com
  static String maskEmail(String email) {
    final parts = email.split('@');
    if (parts.length != 2) return '***';
    final local = parts[0];
    final domain = parts[1];
    if (local.isEmpty) return '***@$domain';
    if (local.length == 1) return '*@$domain';
    if (local.length == 2) return '${local[0]}*@$domain';
    return '${local[0]}***${local[local.length - 1]}@$domain';
  }
}
