import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../theme/diary_theme.dart';
import 'auth_widgets.dart';

class SignupWelcomeScreen extends StatefulWidget {
  const SignupWelcomeScreen({super.key});

  @override
  State<SignupWelcomeScreen> createState() => _SignupWelcomeScreenState();
}

class _SignupWelcomeScreenState extends State<SignupWelcomeScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      context.read<AuthController>().dismissSignupWelcome();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthPage(
      padding: const EdgeInsets.fromLTRB(22, 36, 22, 32),
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('wishkit', style: DiaryTheme.display(40)),
        const SizedBox(height: 20),
        Text(
          '회원가입을 축하합니다',
          textAlign: TextAlign.center,
          style: DiaryTheme.body(20, weight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          '잠시 후 위시리스트로 이동해요',
          textAlign: TextAlign.center,
          style: DiaryTheme.body(13, color: DiaryColors.inkMuted),
        ),
      ],
    );
  }
}
