import 'package:go_router/go_router.dart';

import '../screens/auth/account_recovery_screen.dart';
import '../screens/auth/email_verification_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_welcome_screen.dart';
import 'auth_controller.dart';
import 'auth_models.dart';

/// 로그인 관련 화면 경로. main.dart 의 GoRouter 에 그대로 끼워 넣는다.
///
/// ```dart
/// GoRouter(
///   initialLocation: authInitialLocation(auth),
///   refreshListenable: Listenable.merge([auth, store]),
///   redirect: (context, state) => authRedirect(auth, state),
///   routes: [...authRoutes, ...앱 기능 routes],
/// );
/// ```
abstract final class AuthPaths {
  static const login = '/login';
  static const verifyEmail = '/verify-email';
  static const recovery = '/account-recovery';
  static const welcome = '/welcome';
  static const home = '/';
}

final List<RouteBase> authRoutes = [
  GoRoute(path: AuthPaths.login, builder: (_, __) => const LoginScreen()),
  GoRoute(
    path: AuthPaths.verifyEmail,
    builder: (_, __) => const EmailVerificationScreen(),
  ),
  GoRoute(
    path: AuthPaths.recovery,
    builder: (_, __) => const AccountRecoveryScreen(),
  ),
  GoRoute(
    path: AuthPaths.welcome,
    builder: (_, __) => const SignupWelcomeScreen(),
  ),
];

String authInitialLocation(AuthController auth) => switch (auth.status) {
      AuthStatus.signedIn =>
        auth.showSignupWelcome ? AuthPaths.welcome : AuthPaths.home,
      AuthStatus.awaitingVerification => AuthPaths.verifyEmail,
      AuthStatus.signedOut || AuthStatus.unknown => AuthPaths.login,
    };

/// 로그인 상태에 맞지 않는 화면이면 알맞은 화면으로 돌려보낸다. 괜찮으면 null.
String? authRedirect(AuthController auth, GoRouterState state) {
  final loc = state.matchedLocation;
  final onLogin = loc == AuthPaths.login;
  final onVerify = loc == AuthPaths.verifyEmail;
  final onRecovery = loc == AuthPaths.recovery;
  final onWelcome = loc == AuthPaths.welcome;

  switch (auth.status) {
    case AuthStatus.unknown:
      return null;
    case AuthStatus.awaitingVerification:
      return onVerify ? null : AuthPaths.verifyEmail;
    case AuthStatus.signedOut:
      return (onLogin || onRecovery) ? null : AuthPaths.login;
    case AuthStatus.signedIn:
      if (auth.showSignupWelcome) return onWelcome ? null : AuthPaths.welcome;
      if (onLogin || onVerify || onRecovery || onWelcome) return AuthPaths.home;
      return null;
  }
}
