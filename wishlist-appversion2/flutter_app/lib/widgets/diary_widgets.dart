import 'package:flutter/material.dart';

import '../theme/diary_theme.dart';

class DiaryGridPaper extends StatelessWidget {
  const DiaryGridPaper({
    super.key,
    required this.child,
    this.color = DiaryColors.paper,
    this.padding = const EdgeInsets.all(12),
    this.borderRadius = 16,
    this.border,
  });

  final Widget child;
  final Color color;
  final EdgeInsets padding;
  final double borderRadius;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
      ),
      child: CustomPaint(
        painter: _GridPainter(color: DiaryColors.grid.withValues(alpha: 0.45)),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 18.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class SpiralNotebook extends StatelessWidget {
  const SpiralNotebook({
    super.key,
    required this.child,
    this.folderColor = DiaryColors.folderBlue,
    this.border,
  });

  final Widget child;
  final Color folderColor;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: folderColor,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: DiaryGridPaper(
          borderRadius: 12,
          padding: EdgeInsets.zero,
          border: border,
          child: child,
        ),
      ),
    );
  }
}

class MineBadge extends StatelessWidget {
  const MineBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: DiaryColors.ink,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '나',
        style: DiaryTheme.body(10, weight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}

class WhiteProductCard extends StatelessWidget {
  const WhiteProductCard({
    super.key,
    required this.child,
    this.indexColor,
    this.onTap,
    this.margin = const EdgeInsets.only(bottom: 10),
    this.backgroundColor = DiaryColors.white,
  });

  final Widget child;
  final Color? indexColor;
  final VoidCallback? onTap;
  final EdgeInsets margin;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            if (indexColor != null)
              Container(
                width: 10,
                height: 42,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: indexColor,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: DiaryColors.ink.withValues(alpha: 0.08)),
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar + name + handle row shared by friend / follower / following lists.
class PersonRow extends StatelessWidget {
  const PersonRow({
    super.key,
    required this.name,
    required this.handle,
    required this.avatarUrl,
    this.onTap,
    this.subtitle,
    this.trailing,
  });

  final String name;
  final String handle;
  final String avatarUrl;
  final VoidCallback? onTap;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return WhiteProductCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(radius: 24, backgroundImage: NetworkImage(avatarUrl)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DiaryTheme.body(14, weight: FontWeight.w700),
                ),
                Text(
                  handle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DiaryTheme.body(12, color: DiaryColors.inkMuted),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DiaryTheme.body(11, color: DiaryColors.accent),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class DiaryButton extends StatelessWidget {
  const DiaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = false,
    this.color = DiaryColors.folderBlue,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;
  final Color color;
  final IconData? icon;

  bool get _disabled => onPressed == null;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _disabled ? 0.45 : 1,
      child: Material(
        color: filled ? color : DiaryColors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: DiaryColors.ink.withValues(alpha: 0.7), width: 1.2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: DiaryColors.ink),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: OneLineText(
                    label,
                    textAlign: TextAlign.center,
                    style: DiaryTheme.body(13, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Password field with a small trailing eye to show/hide the value.
class PasswordTextField extends StatefulWidget {
  const PasswordTextField({
    super.key,
    required this.controller,
    this.decoration = const InputDecoration(),
    this.onSubmitted,
    this.textInputAction,
    this.autofillHints,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: hidden,
      onSubmitted: widget.onSubmitted,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      decoration: widget.decoration.copyWith(
        suffixIcon: IconButton(
          tooltip: hidden ? '비밀번호 보기' : '비밀번호 숨기기',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => setState(() => hidden = !hidden),
          icon: Icon(
            hidden
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 20,
            color: DiaryColors.inkMuted,
          ),
        ),
      ),
    );
  }
}

/// Label that must stay on one line: shrinks to fit instead of wrapping.
class OneLineText extends StatelessWidget {
  const OneLineText(
    this.text, {
    super.key,
    required this.style,
    this.textAlign,
  });

  final String text;
  final TextStyle style;
  final TextAlign? textAlign;

  Alignment get _alignment => switch (textAlign) {
        TextAlign.center => Alignment.center,
        TextAlign.right || TextAlign.end => Alignment.centerRight,
        _ => Alignment.centerLeft,
      };

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: _alignment,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        textAlign: textAlign,
        style: style,
      ),
    );
  }
}

String formatWon(int price) {
  final s = price.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final reverse = s.length - i;
    buf.write(s[i]);
    if (reverse > 1 && reverse % 3 == 1) buf.write(',');
  }
  return '${buf.toString()}원';
}
