import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:figmadesign/auth/auth_controller.dart';
import 'package:figmadesign/auth/auth_models.dart';
import 'package:figmadesign/auth/auth_service.dart';

/// AWS 없이 AuthController 흐름만 검증하는 가짜 서비스.
class FakeAuthService implements AuthService {
  final users = <String, ({String password, bool confirmed, String uid})>{};
  AuthUserInfo? signedIn;
  final calls = <String>[];
  final _ended = StreamController<void>.broadcast();
  static const goodCode = '123456';

  void endSession() => _ended.add(null);

  @override
  Stream<void> get sessionEnded => _ended.stream;

  @override
  Future<AuthUserInfo?> currentUser() async => signedIn;

  @override
  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    required String handle,
  }) async {
    calls.add('signUp:$handle');
    if (users.containsKey(email)) {
      throw const AuthFailure(AuthFailureCode.emailAlreadyUsed, 'exists');
    }
    users[email] = (password: password, confirmed: false, uid: 'sub-$email');
  }

  @override
  Future<void> confirmSignUp({
    required String email,
    required String code,
  }) async {
    if (code != goodCode) {
      throw const AuthFailure(AuthFailureCode.codeMismatch, 'mismatch');
    }
    final u = users[email]!;
    users[email] = (password: u.password, confirmed: true, uid: u.uid);
  }

  @override
  Future<void> resendSignUpCode({required String email}) async =>
      calls.add('resend');

  @override
  Future<SignInOutcome> signIn({
    required String email,
    required String password,
  }) async {
    final u = users[email];
    if (u == null || u.password != password) {
      throw const AuthFailure(AuthFailureCode.wrongCredentials, 'wrong');
    }
    if (!u.confirmed) return SignInOutcome.needsVerification;
    signedIn = AuthUserInfo(uid: u.uid, email: email);
    return SignInOutcome.signedIn;
  }

  @override
  Future<void> signOut() async => signedIn = null;

  @override
  Future<String?> requestPasswordReset({required String email}) async =>
      'k***@x.com';

  @override
  Future<void> confirmPasswordReset({
    required String email,
    required String code,
    required String newPassword,
  }) async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> verifyPassword(String password) async {
    final u = users[signedIn!.email]!;
    if (u.password != password) {
      throw const AuthFailure(AuthFailureCode.wrongCredentials, 'wrong');
    }
  }

  @override
  Future<void> deleteCurrentUser() async {
    calls.add('deleteUser');
    users.remove(signedIn!.email);
    signedIn = null;
  }
}

void main() {
  late FakeAuthService service;
  late AuthController auth;

  setUp(() async {
    service = FakeAuthService();
    auth = AuthController(service: service);
    await auth.init();
  });

  tearDown(() => auth.dispose());

  test('처음에는 로그아웃 상태', () {
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.uid, isNull);
  });

  test('가입 → 코드 인증 → 자동 로그인 → 환영 화면', () async {
    final changes = <AuthUserInfo?>[];
    auth.userChanges.listen(changes.add);

    await auth.register(
      email: 'Kim@X.com',
      password: 'wishkit1',
      name: '지은',
      handle: 'Kim.Ji',
    );
    expect(auth.status, AuthStatus.awaitingVerification);
    expect(auth.pendingEmail, 'kim@x.com');
    expect(service.calls, contains('signUp:@kim.ji'));

    await expectLater(
      auth.confirmVerificationCode('000000'),
      throwsA(isA<AuthFailure>()),
    );
    expect(auth.status, AuthStatus.awaitingVerification);

    await auth.confirmVerificationCode(FakeAuthService.goodCode);
    expect(auth.status, AuthStatus.signedIn);
    expect(auth.uid, 'sub-kim@x.com');
    expect(auth.showSignupWelcome, isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(changes.single?.uid, 'sub-kim@x.com');
  });

  test('입력 검사에 걸리면 서버를 부르지 않는다', () async {
    await expectLater(
      auth.register(email: 'a@b.co', password: 'short', name: '', handle: 'ok1'),
      throwsA(isA<AuthFailure>()),
    );
    expect(service.calls, isEmpty);
  });

  test('아이디 중복이면 가입 요청을 보내지 않는다', () async {
    auth.hooks = AuthDataHooks(isHandleAvailable: (_) async => false);
    await expectLater(
      auth.register(
        email: 'a@b.co',
        password: 'wishkit1',
        name: '',
        handle: 'taken',
      ),
      throwsA(
        isA<AuthFailure>().having((e) => e.code, 'code', AuthFailureCode.handleTaken),
      ),
    );
    expect(service.calls, isEmpty);
  });

  test('인증 안 끝낸 계정으로 로그인하면 코드 재발송 후 인증 화면', () async {
    service.users['a@b.co'] = (password: 'wishkit1', confirmed: false, uid: 'u1');
    await auth.login(email: 'a@b.co', password: 'wishkit1');
    expect(auth.status, AuthStatus.awaitingVerification);
    expect(service.calls, contains('resend'));
  });

  test('앱 재시작으로 비밀번호가 없으면 인증 후 로그인 화면 + 안내', () async {
    service.users['a@b.co'] = (password: 'wishkit1', confirmed: false, uid: 'u1');
    await auth.login(email: 'a@b.co', password: 'wishkit1');
    // 로그인 실패를 흉내 내기 위해 비밀번호를 바꿔 둔다.
    service.users['a@b.co'] = (password: 'changed1', confirmed: false, uid: 'u1');
    await auth.confirmVerificationCode(FakeAuthService.goodCode);
    expect(auth.status, AuthStatus.signedOut);
    expect(auth.takeNotice(), contains('인증이 완료'));
    expect(auth.takeNotice(), isNull);
  });

  test('틀린 비밀번호', () async {
    service.users['a@b.co'] = (password: 'wishkit1', confirmed: true, uid: 'u1');
    await expectLater(
      auth.login(email: 'a@b.co', password: 'nope1234'),
      throwsA(isA<AuthFailure>()),
    );
    expect(auth.status, AuthStatus.signedOut);
  });

  test('세션이 밖에서 끝나면 로그아웃된다', () async {
    service.users['a@b.co'] = (password: 'wishkit1', confirmed: true, uid: 'u1');
    await auth.login(email: 'a@b.co', password: 'wishkit1');
    service.endSession();
    await Future<void>.delayed(Duration.zero);
    expect(auth.status, AuthStatus.signedOut);
  });

  group('회원 탈퇴', () {
    setUp(() async {
      service.users['a@b.co'] = (password: 'wishkit1', confirmed: true, uid: 'u1');
      await auth.login(email: 'a@b.co', password: 'wishkit1');
    });

    test('비밀번호 틀리면 아무것도 지우지 않는다', () async {
      var dataDeleted = false;
      auth.hooks = AuthDataHooks(deleteMyData: (_) async => dataDeleted = true);
      await expectLater(
        auth.deleteAccount(password: 'wrong123'),
        throwsA(isA<AuthFailure>()),
      );
      expect(dataDeleted, isFalse);
      expect(service.calls, isNot(contains('deleteUser')));
    });

    test('데이터 삭제가 실패하면 계정은 남긴다', () async {
      auth.hooks = AuthDataHooks(
        deleteMyData: (_) async => throw Exception('db down'),
      );
      await expectLater(
        auth.deleteAccount(password: 'wishkit1'),
        throwsA(isA<AuthFailure>()),
      );
      expect(service.calls, isNot(contains('deleteUser')));
      expect(auth.isSignedIn, isTrue);
    });

    test('정상: 데이터 먼저, 계정 나중', () async {
      final order = <String>[];
      auth.hooks = AuthDataHooks(deleteMyData: (uid) async => order.add('data:$uid'));
      await auth.deleteAccount(password: 'wishkit1');
      order.addAll(service.calls.where((c) => c == 'deleteUser'));
      expect(order, ['data:u1', 'deleteUser']);
      expect(auth.status, AuthStatus.signedOut);
    });
  });
}
