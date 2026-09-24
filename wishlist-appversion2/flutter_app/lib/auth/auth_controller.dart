import 'dart:async';

import 'package:flutter/foundation.dart';

import 'auth_models.dart';
import 'auth_service.dart';
import 'auth_validators.dart';

/// 로그인 상태를 들고 있는 단 하나의 객체. 화면과 라우터는 이것만 본다.
///
/// 기존 AppStore 안에 섞여 있던 인증 상태(isLoggedIn, awaitingEmailVerification,
/// showSignupWelcome, pendingVerificationEmail …)를 전부 여기로 옮겼다.
///
/// 앱 데이터 쪽(AppStore)은 [userChanges] 를 구독해서
///  - 사용자 정보가 들어오면 → 프로필 확인/생성 후 데이터 불러오기
///  - null 이 들어오면     → 기기 안의 데이터 비우기
/// 만 하면 된다. → TEAM_CONTRACT.md
class AuthController extends ChangeNotifier {
  AuthController({
    required AuthService service,
    AuthDataHooks hooks = const AuthDataHooks(),
  })  : _service = service,
        _hooks = hooks {
    _sessionSub = _service.sessionEnded.listen((_) => _setSignedOut());
  }

  final AuthService _service;
  AuthDataHooks _hooks;
  StreamSubscription<void>? _sessionSub;
  final _userChanges = StreamController<AuthUserInfo?>.broadcast();

  AuthStatus _status = AuthStatus.unknown;
  AuthUserInfo? _user;
  String? _pendingEmail;
  bool _showSignupWelcome = false;
  bool _busy = false;
  String? _startupError;
  String? _notice;

  /// 인증 코드 확인 직후 자동 로그인에만 쓰는 비밀번호.
  /// 메모리에만 잠깐 두고, 쓰거나 취소하면 바로 지운다. 절대 저장하지 않는다.
  String? _pendingPassword;

  // ── 읽기 전용 상태 ────────────────────────────────────────────

  AuthStatus get status => _status;
  bool get isSignedIn => _status == AuthStatus.signedIn;
  AuthUserInfo? get user => _user;

  /// 앱 전체에서 쓰는 사용자 ID (Cognito sub). 로그인 전이면 null.
  String? get uid => _user?.uid;

  /// 인증 코드를 보낸 이메일 (인증 화면 표시용).
  String? get pendingEmail => _pendingEmail;
  bool get showSignupWelcome => _showSignupWelcome;

  /// 버튼 연타 방지용. 진행 중이면 true.
  bool get busy => _busy;

  /// 앱 시작 때 세션 확인이 실패한 이유 (보통 서버 설정 문제).
  String? get startupError => _startupError;

  /// 다음 화면에서 한 번만 보여 줄 안내 문구를 꺼낸다 (꺼내면 지워짐).
  String? takeNotice() {
    final n = _notice;
    _notice = null;
    return n;
  }

  /// "아이디로 이메일 찾기" 기능을 쓸 수 있는지.
  bool get canFindEmailByHandle => _hooks.findMaskedEmailByHandle != null;

  /// 로그인 사용자 변화 알림. 로그인 → 사용자 정보, 로그아웃 → null.
  Stream<AuthUserInfo?> get userChanges => _userChanges.stream;

  /// 앱 데이터 쪽 준비가 끝난 뒤 연결 지점을 넣는다 (main.dart 에서 한 번).
  set hooks(AuthDataHooks value) => _hooks = value;

  // ── 시작 ─────────────────────────────────────────────────────

  /// 앱 시작 시 한 번. 저장된 로그인 세션을 복구한다.
  Future<void> init() async {
    try {
      final user = await _service.currentUser();
      if (user != null) {
        _setSignedIn(user);
        return;
      }
    } on AuthFailure catch (e) {
      _startupError = e.code == AuthFailureCode.notConfigured ? e.message : null;
    }
    _setSignedOut();
  }

  // ── 가입 ─────────────────────────────────────────────────────

  Future<void> register({
    required String email,
    required String password,
    required String name,
    required String handle,
  }) =>
      _run(() async {
        _require(AuthValidators.email(email));
        _require(AuthValidators.password(password));
        _require(AuthValidators.handle(handle));
        _require(AuthValidators.name(name));

        final normalizedHandle = AuthValidators.normalizeHandle(handle);
        final check = _hooks.isHandleAvailable;
        if (check != null && !await check(normalizedHandle)) {
          throw const AuthFailure(
            AuthFailureCode.handleTaken,
            '이미 사용 중인 아이디예요.',
          );
        }

        final normalizedEmail = AuthValidators.normalizeEmail(email);
        await _service.signUp(
          email: normalizedEmail,
          password: password,
          name: name,
          handle: normalizedHandle,
        );
        _enterVerification(normalizedEmail, password);
      });

  /// 인증 코드 확인 → 성공하면 바로 로그인까지 한다.
  Future<void> confirmVerificationCode(String code) => _run(() async {
        final email = _pendingEmail;
        if (email == null) {
          throw const AuthFailure(
            AuthFailureCode.notSignedIn,
            '인증 정보가 사라졌어요. 다시 로그인해 주세요.',
          );
        }
        _require(AuthValidators.code(code));
        await _service.confirmSignUp(email: email, code: code);

        final password = _pendingPassword;
        _pendingPassword = null;
        AuthUserInfo? user;
        if (password != null) {
          try {
            await _service.signIn(email: email, password: password);
            user = await _service.currentUser();
          } on AuthFailure {
            user = null; // 인증은 끝났으니, 로그인만 다시 하면 된다.
          }
        }
        if (user == null) {
          // 앱 재시작 등으로 비밀번호가 없으면 로그인 화면에서 다시 입력받는다.
          _notice = '인증이 완료됐어요! 이제 로그인해 주세요.';
          _setSignedOut();
          return;
        }
        _showSignupWelcome = true;
        _setSignedIn(user);
      });

  Future<void> resendVerificationCode() => _run(() async {
        final email = _pendingEmail;
        if (email == null) return;
        await _service.resendSignUpCode(email: email);
      });

  /// 인증 화면에서 "돌아가기".
  void cancelVerification() {
    _pendingPassword = null;
    _setSignedOut();
  }

  void dismissSignupWelcome() {
    if (!_showSignupWelcome) return;
    _showSignupWelcome = false;
    notifyListeners();
  }

  // ── 로그인 / 로그아웃 ──────────────────────────────────────────

  Future<void> login({required String email, required String password}) =>
      _run(() async {
        _require(AuthValidators.email(email));
        if (password.isEmpty) {
          throw const AuthFailure(
            AuthFailureCode.invalidInput,
            '비밀번호를 입력해 주세요.',
          );
        }
        final normalizedEmail = AuthValidators.normalizeEmail(email);
        final outcome =
            await _service.signIn(email: normalizedEmail, password: password);
        if (outcome == SignInOutcome.needsVerification) {
          // 가입만 하고 인증을 안 끝낸 계정 → 새 코드를 보내고 인증 화면으로.
          await _service.resendSignUpCode(email: normalizedEmail);
          _enterVerification(normalizedEmail, password);
          return;
        }
        final user = await _service.currentUser();
        if (user == null) {
          throw const AuthFailure(
            AuthFailureCode.unknown,
            '로그인 정보를 불러오지 못했어요. 다시 시도해 주세요.',
          );
        }
        _setSignedIn(user);
      });

  Future<void> logout() => _run(() async {
        try {
          await _service.signOut();
        } finally {
          // 서버 쪽 정리가 실패해도 기기에서는 로그아웃 상태로 만든다.
          _setSignedOut();
        }
      });

  // ── 비밀번호 ─────────────────────────────────────────────────

  /// 재설정 코드 발송. 코드를 보낸 곳(가려진 이메일)을 돌려준다.
  ///
  /// 보안상, 가입되지 않은 이메일이어도 "보냈어요"라고 똑같이 답한다.
  Future<String?> requestPasswordReset(String email) => _run(() async {
        _require(AuthValidators.email(email));
        return _service.requestPasswordReset(
          email: AuthValidators.normalizeEmail(email),
        );
      });

  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) =>
      _run(() async {
        _require(AuthValidators.email(email));
        _require(AuthValidators.code(code));
        _require(AuthValidators.password(newPassword));
        await _service.confirmPasswordReset(
          email: AuthValidators.normalizeEmail(email),
          code: code,
          newPassword: newPassword,
        );
      });

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      _run(() async {
        _requireSignedIn();
        if (currentPassword.isEmpty) {
          throw const AuthFailure(
            AuthFailureCode.invalidInput,
            '현재 비밀번호를 입력해 주세요.',
          );
        }
        _require(AuthValidators.password(newPassword));
        if (currentPassword == newPassword) {
          throw const AuthFailure(
            AuthFailureCode.invalidInput,
            '새 비밀번호는 현재 비밀번호와 달라야 해요.',
          );
        }
        try {
          await _service.changePassword(
            currentPassword: currentPassword,
            newPassword: newPassword,
          );
        } on AuthFailure catch (e) {
          if (e.code == AuthFailureCode.wrongCredentials) {
            throw const AuthFailure(
              AuthFailureCode.wrongCredentials,
              '현재 비밀번호가 맞지 않아요.',
            );
          }
          rethrow;
        }
      });

  /// 이메일/비밀번호 찾기 화면의 "아이디로 이메일 찾기".
  Future<String?> findMaskedEmailByHandle(String handle) => _run(() async {
        final lookup = _hooks.findMaskedEmailByHandle;
        if (lookup == null) {
          throw const AuthFailure(
            AuthFailureCode.unknown,
            '지금은 이 기능을 쓸 수 없어요.',
          );
        }
        _require(AuthValidators.handle(handle));
        return lookup(AuthValidators.normalizeHandle(handle));
      });

  // ── 회원 탈퇴 ─────────────────────────────────────────────────

  /// 순서: 비밀번호 확인 → 내 데이터 삭제(앱 데이터 쪽) → Cognito 계정 삭제.
  /// 데이터 삭제가 실패하면 계정은 지우지 않는다 (주인 없는 데이터가 남지 않게).
  Future<void> deleteAccount({required String password}) => _run(() async {
        final user = _requireSignedIn();
        if (password.isEmpty) {
          throw const AuthFailure(
            AuthFailureCode.invalidInput,
            '비밀번호를 입력해 주세요.',
          );
        }
        try {
          await _service.verifyPassword(password);
        } on AuthFailure catch (e) {
          if (e.code == AuthFailureCode.wrongCredentials) {
            throw const AuthFailure(
              AuthFailureCode.wrongCredentials,
              '비밀번호가 맞지 않아요.',
            );
          }
          rethrow;
        }
        final deleteData = _hooks.deleteMyData;
        if (deleteData != null) await deleteData(user.uid);
        await _service.deleteCurrentUser();
        _setSignedOut();
      });

  // ── 내부 ─────────────────────────────────────────────────────

  Future<T> _run<T>(Future<T> Function() body) async {
    if (_busy) {
      throw const AuthFailure(
        AuthFailureCode.tooManyRequests,
        '처리 중이에요. 잠시만 기다려 주세요.',
      );
    }
    _busy = true;
    notifyListeners();
    try {
      return await body();
    } on AuthFailure {
      rethrow;
    } catch (e) {
      // 앱 데이터 쪽 hook 에서 난 오류 등. 원문은 개발 로그에만.
      debugPrint('AuthController: ${e.runtimeType}');
      throw const AuthFailure(
        AuthFailureCode.unknown,
        '요청에 실패했어요. 잠시 후 다시 시도해 주세요.',
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _require(String? validationMessage) {
    if (validationMessage != null) {
      throw AuthFailure(AuthFailureCode.invalidInput, validationMessage);
    }
  }

  AuthUserInfo _requireSignedIn() {
    final user = _user;
    if (!isSignedIn || user == null) {
      throw const AuthFailure(
        AuthFailureCode.notSignedIn,
        '로그인이 풀렸어요. 다시 로그인해 주세요.',
      );
    }
    return user;
  }

  void _enterVerification(String email, String password) {
    _pendingEmail = AuthValidators.normalizeEmail(email);
    _pendingPassword = password;
    _status = AuthStatus.awaitingVerification;
    notifyListeners();
  }

  void _setSignedIn(AuthUserInfo user) {
    final changed = _user != user || _status != AuthStatus.signedIn;
    _user = user;
    _status = AuthStatus.signedIn;
    _pendingEmail = null;
    _pendingPassword = null;
    _startupError = null;
    notifyListeners();
    if (changed) _userChanges.add(user);
  }

  void _setSignedOut() {
    final wasSignedIn = _user != null;
    _user = null;
    _status = AuthStatus.signedOut;
    _pendingEmail = null;
    _pendingPassword = null;
    _showSignupWelcome = false;
    notifyListeners();
    if (wasSignedIn) _userChanges.add(null);
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _userChanges.close();
    super.dispose();
  }
}
