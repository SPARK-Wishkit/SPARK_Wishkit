import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../../auth/auth_routes.dart';
import '../../auth/auth_validators.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import 'auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailCtrl = TextEditingController();
  final passwordCtrl = TextEditingController();
  final nameCtrl = TextEditingController();
  final handleCtrl = TextEditingController();
  bool isRegister = false;
  String? error;
  String? notice;

  @override
  void initState() {
    super.initState();
    notice = context.read<AuthController>().takeNotice();
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    passwordCtrl.dispose();
    nameCtrl.dispose();
    handleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    if (auth.busy) return;
    setState(() {
      error = null;
      notice = null;
    });
    try {
      if (isRegister) {
        await auth.register(
          email: emailCtrl.text,
          password: passwordCtrl.text,
          name: nameCtrl.text,
          handle: handleCtrl.text,
        );
      } else {
        await auth.login(email: emailCtrl.text, password: passwordCtrl.text);
      }
      // 성공하면 라우터가 알아서 인증 화면이나 홈으로 보낸다.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  void _toggleMode() {
    setState(() {
      isRegister = !isRegister;
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final loading = auth.busy;
    final blocked = auth.startupError != null;

    return AuthPage(
      children: [
        Text('wishkit', style: DiaryTheme.display(42)),
        const SizedBox(height: 4),
        Container(
          height: 6,
          width: 90,
          decoration: BoxDecoration(
            color: DiaryColors.folderBlue,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          isRegister
              ? '이메일 인증 후 계정이 만들어져요'
              : '계정으로 로그인하고 위시리스트를 이어가요',
          style: DiaryTheme.body(13, color: DiaryColors.inkMuted),
        ),
        if (blocked) ...[
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DiaryColors.folderYellow.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(auth.startupError!, style: DiaryTheme.body(12)),
          ),
        ],
        const SizedBox(height: 24),
        if (isRegister) ...[
          TextField(
            controller: nameCtrl,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.name],
            maxLength: AuthValidators.nameMaxLength,
            decoration: authInput('이름 (선택)'),
          ),
          const SizedBox(height: 4),
          TextField(
            controller: handleCtrl,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            autofillHints: const [AutofillHints.newUsername],
            decoration: authInput(
              '아이디',
              helper: '영문 소문자·숫자·마침표·밑줄, 3~20자',
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          decoration: authInput('이메일'),
        ),
        const SizedBox(height: 12),
        PasswordTextField(
          controller: passwordCtrl,
          decoration: authInput(
            '비밀번호',
            helper: isRegister
                ? '${AuthValidators.passwordMinLength}자 이상, 숫자 포함'
                : null,
          ),
          textInputAction: TextInputAction.done,
          autofillHints: [
            isRegister ? AutofillHints.newPassword : AutofillHints.password,
          ],
          onSubmitted: (_) => _submit(),
        ),
        AuthNotice(message: notice, error: error),
        const SizedBox(height: 20),
        DiaryButton(
          label: loading
              ? (isRegister ? '가입 중...' : '로그인 중...')
              : (isRegister ? '회원가입' : '로그인'),
          filled: true,
          color: DiaryColors.folderBlue,
          onPressed: loading || blocked ? null : _submit,
        ),
        if (!isRegister)
          Align(
            alignment: Alignment.centerRight,
            child: AuthTextLink(
              label: '이메일 / 비밀번호 찾기',
              onPressed: loading ? null : () => context.push(AuthPaths.recovery),
            ),
          ),
        const SizedBox(height: 8),
        AuthTextLink(
          label: isRegister ? '이미 계정이 있나요? 로그인' : '계정이 없나요? 회원가입',
          onPressed: loading ? null : _toggleMode,
        ),
      ],
    );
  }
}
