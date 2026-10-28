import 'package:flutter/material.dart';

import '../../theme/diary_theme.dart';
import '../../widgets/diary_widgets.dart';

/// 로그인 관련 화면 4개가 같이 쓰는 틀. (기존에는 화면마다 같은 코드가 복사돼 있었다)
class AuthPage extends StatelessWidget {
  const AuthPage({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.fromLTRB(22, 28, 22, 24),
    this.crossAxisAlignment = CrossAxisAlignment.stretch,
  });

  final List<Widget> children;
  final EdgeInsets padding;
  final CrossAxisAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DiaryColors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: DiaryGridPaper(
                padding: padding,
                child: SingleChildScrollView(
                  child: AutofillGroup(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: crossAxisAlignment,
                      children: children,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

InputDecoration authInput(String label, {String? helper}) {
  return InputDecoration(
    labelText: label,
    helperText: helper,
    helperMaxLines: 2,
    filled: true,
    fillColor: DiaryColors.white,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: DiaryColors.ink.withValues(alpha: 0.2)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: DiaryColors.ink.withValues(alpha: 0.15)),
    ),
  );
}

/// 안내(초록/기본) 또는 오류(빨강) 한 줄.
class AuthNotice extends StatelessWidget {
  const AuthNotice({super.key, this.message, this.error});

  final String? message;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final text = error ?? message;
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        text,
        style: DiaryTheme.body(
          12,
          color: error != null ? DiaryColors.pin : null,
        ),
      ),
    );
  }
}

/// 화면 아래쪽 작은 텍스트 버튼.
class AuthTextLink extends StatelessWidget {
  const AuthTextLink({super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
      ),
    );
  }
}
