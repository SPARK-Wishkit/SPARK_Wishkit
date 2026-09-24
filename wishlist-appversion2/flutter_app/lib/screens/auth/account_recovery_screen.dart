import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../../auth/auth_routes.dart';
import '../../auth/auth_validators.dart';
import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';
import 'auth_widgets.dart';

enum _RecoveryMode { password, email }

/// 비밀번호 재설정(코드 방식) + 아이디로 이메일 찾기.
///
/// 비밀번호 재설정은 2단계:
///   1) 이메일 입력 → 재설정 코드 발송
///   2) 코드 + 새 비밀번호 입력
class AccountRecoveryScreen extends StatefulWidget {
  const AccountRecoveryScreen({super.key});

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  final emailCtrl = TextEditingController();
  final handleCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  final newPasswordCtrl = TextEditingController();

  _RecoveryMode mode = _RecoveryMode.password;
  bool codeSent = false;
  bool resetDone = false;
  String? message;
  String? error;

  @override
  void dispose() {
    emailCtrl.dispose();
    handleCtrl.dispose();
    codeCtrl.dispose();
    newPasswordCtrl.dispose();
    super.dispose();
  }

  void _clearNotice() {
    error = null;
    message = null;
  }

  Future<void> _submit() async {
    final auth = context.read<AuthController>();
    if (auth.busy) return;
    setState(_clearNotice);
    try {
      if (mode == _RecoveryMode.email) {
        final masked = await auth.findMaskedEmailByHandle(handleCtrl.text);
        if (!mounted) return;
        setState(() {
          if (masked == null) {
            error = '해당 아이디로 가입된 계정을 찾지 못했어요.';
          } else {
            message = '가입 이메일: $masked';
          }
        });
      } else if (!codeSent) {
        final destination = await auth.requestPasswordReset(emailCtrl.text);
        if (!mounted) return;
        setState(() {
          codeSent = true;
          // 가입 여부와 상관없이 같은 문구 (계정 존재 여부를 노출하지 않음)
          message = '${destination ?? '입력한 이메일'}(으)로 재설정 코드를 보냈어요. '
              '가입된 이메일이라면 곧 도착해요.';
        });
      } else {
        await auth.confirmPasswordReset(
          email: emailCtrl.text,
          code: codeCtrl.text,
          newPassword: newPasswordCtrl.text,
        );
        if (!mounted) return;
        setState(() {
          resetDone = true;
          message = '비밀번호를 바꿨어요. 새 비밀번호로 로그인해 주세요.';
        });
      }
    } on AuthFailure catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  void _restartReset() {
    setState(() {
      codeSent = false;
      resetDone = false;
      codeCtrl.clear();
      newPasswordCtrl.clear();
      _clearNotice();
    });
  }

  String get _buttonLabel {
    if (mode == _RecoveryMode.email) return '이메일 찾기';
    if (resetDone) return '로그인하러 가기';
    return codeSent ? '비밀번호 바꾸기' : '재설정 코드 보내기';
  }

  String get _guide {
    if (mode == _RecoveryMode.email) {
      return '가입할 때 만든 아이디를 입력하면 이메일을 알려드려요.';
    }
    return codeSent
        ? '메일로 받은 숫자 ${AuthValidators.codeLength}자리 코드와 새 비밀번호를 입력해 주세요.'
        : '가입한 이메일을 입력하면 재설정 코드를 보내드려요.';
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final loading = auth.busy;
    final showEmailTab = auth.canFindEmailByHandle;
    if (!showEmailTab) mode = _RecoveryMode.password;

    return AuthPage(
      children: [
        Text('wishkit', style: DiaryTheme.display(36)),
        const SizedBox(height: 8),
        Text('계정 찾기', style: DiaryTheme.body(18, weight: FontWeight.w700)),
        const SizedBox(height: 16),
        if (showEmailTab) ...[
          SegmentedButton<_RecoveryMode>(
            segments: const [
              ButtonSegment(value: _RecoveryMode.password, label: Text('비밀번호')),
              ButtonSegment(value: _RecoveryMode.email, label: Text('이메일')),
            ],
            selected: {mode},
            onSelectionChanged: loading
                ? null
                : (value) => setState(() {
                      mode = value.first;
                      _clearNotice();
                    }),
          ),
          const SizedBox(height: 16),
        ],
        Text(_guide, style: DiaryTheme.body(13, color: DiaryColors.inkMuted)),
        const SizedBox(height: 16),
        if (mode == _RecoveryMode.email)
          TextField(
            controller: handleCtrl,
            autocorrect: false,
            decoration: authInput('아이디 (@없이 입력 가능)'),
            onSubmitted: (_) => _submit(),
          )
        else ...[
          TextField(
            controller: emailCtrl,
            enabled: !codeSent,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: authInput('이메일'),
            onSubmitted: (_) => _submit(),
          ),
          if (codeSent && !resetDone) ...[
            const SizedBox(height: 12),
            TextField(
              controller: codeCtrl,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: AuthValidators.codeLength,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: authInput('재설정 코드'),
            ),
            const SizedBox(height: 4),
            PasswordTextField(
              controller: newPasswordCtrl,
              decoration: authInput(
                '새 비밀번호',
                helper: '${AuthValidators.passwordMinLength}자 이상, 숫자 포함',
              ),
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onSubmitted: (_) => _submit(),
            ),
          ],
        ],
        AuthNotice(message: message, error: error),
        const SizedBox(height: 20),
        DiaryButton(
          label: loading ? '처리 중...' : _buttonLabel,
          filled: true,
          color: DiaryColors.folderBlue,
          onPressed: loading
              ? null
              : (resetDone && mode == _RecoveryMode.password)
                  ? () => context.go(AuthPaths.login)
                  : _submit,
        ),
        if (mode == _RecoveryMode.password && codeSent && !resetDone)
          AuthTextLink(
            label: '이메일 다시 입력하기',
            onPressed: loading ? null : _restartReset,
          ),
        const SizedBox(height: 8),
        AuthTextLink(
          label: '돌아가기',
          onPressed: loading ? null : () => context.go(AuthPaths.login),
        ),
      ],
    );
  }
}
