import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../../auth/auth_validators.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import 'auth_widgets.dart';

/// 이메일로 받은 6자리 코드를 입력하는 화면.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  static const _resendCooldown = Duration(seconds: 60);

  final codeCtrl = TextEditingController();
  String? message;
  String? error;
  DateTime? _lastResendAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 방금 코드를 보냈으니 바로 재전송은 막는다.
    _lastResendAt = DateTime.now();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _secondsLeft > 0) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    codeCtrl.dispose();
    super.dispose();
  }

  int get _secondsLeft {
    final last = _lastResendAt;
    if (last == null) return 0;
    final left = _resendCooldown - DateTime.now().difference(last);
    return left.isNegative ? 0 : left.inSeconds + 1;
  }

  Future<void> _confirm() async {
    final auth = context.read<AuthController>();
    if (auth.busy) return;
    setState(() {
      error = null;
      message = null;
    });
    try {
      await auth.confirmVerificationCode(codeCtrl.text);
      // 성공하면 라우터가 환영 화면(또는 로그인 화면)으로 보낸다.
    } on AuthFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _resend() async {
    final auth = context.read<AuthController>();
    if (auth.busy || _secondsLeft > 0) return;
    setState(() {
      error = null;
      message = null;
    });
    try {
      await auth.resendVerificationCode();
      if (!mounted) return;
      setState(() {
        _lastResendAt = DateTime.now();
        message = '인증 코드를 다시 보냈어요. 메일함을 확인해 주세요.';
      });
    } on AuthFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final email = auth.pendingEmail ?? '이메일';
    final busy = auth.busy;
    final wait = _secondsLeft;

    return AuthPage(
      children: [
        Text('wishkit', style: DiaryTheme.display(36)),
        const SizedBox(height: 8),
        Text('이메일 인증', style: DiaryTheme.body(18, weight: FontWeight.w700)),
        const SizedBox(height: 12),
        Text(
          '$email 으로 숫자 ${AuthValidators.codeLength}자리 인증 코드를 보냈어요.',
          style: DiaryTheme.body(13, color: DiaryColors.inkMuted),
        ),
        const SizedBox(height: 6),
        Text(
          '메일이 보이지 않으면 스팸함을 확인해 주세요.',
          style: DiaryTheme.body(12, color: DiaryColors.inkSoft),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: codeCtrl,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.oneTimeCode],
          maxLength: AuthValidators.codeLength,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: DiaryTheme.body(22, weight: FontWeight.w700),
          decoration: authInput('인증 코드'),
          onSubmitted: (_) => _confirm(),
        ),
        AuthNotice(message: message, error: error),
        const SizedBox(height: 20),
        DiaryButton(
          label: busy ? '확인 중...' : '인증하기',
          filled: true,
          color: DiaryColors.folderBlue,
          onPressed: busy ? null : _confirm,
        ),
        const SizedBox(height: 10),
        DiaryButton(
          label: wait > 0 ? '코드 다시 보내기 ($wait초)' : '코드 다시 보내기',
          filled: false,
          color: DiaryColors.folderBlue,
          onPressed: busy || wait > 0 ? null : _resend,
        ),
        const SizedBox(height: 8),
        AuthTextLink(
          label: '돌아가기',
          onPressed: busy ? null : auth.cancelVerification,
        ),
      ],
    );
  }
}
