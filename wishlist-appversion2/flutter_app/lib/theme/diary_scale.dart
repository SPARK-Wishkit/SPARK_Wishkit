import 'package:flutter/material.dart';

/// Lays the app out at a 390pt design width (iPhone 14), then scales the
/// whole tree to the real phone width.
///
/// Flutter does not preserve design ratios by default: font sizes and paddings
/// are logical pixels, so a label that fits on 390pt wraps on 320pt. Scaling
/// the full layout (not just text) keeps spacing, type, and chrome in the
/// same proportion on every phone.
class DiaryScale {
  static const designWidth = 390.0;

  /// Smallest phone we still shrink to match (iPhone SE).
  static const minFactor = 0.80;

  /// Largest scale before wide phones / tablets stop stretching.
  static const maxFactor = 1.15;

  static const maxUserTextScale = 1.2;

  static double factorForWidth(double width) {
    if (width <= 0) return 1;
    return (width / designWidth).clamp(minFactor, maxFactor);
  }

  static double of(BuildContext context) =>
      factorForWidth(MediaQuery.sizeOf(context).width);

  static EdgeInsets scaleInsets(EdgeInsets insets, double factor) {
    if (factor == 0) return insets;
    return EdgeInsets.fromLTRB(
      insets.left / factor,
      insets.top / factor,
      insets.right / factor,
      insets.bottom / factor,
    );
  }

  static Widget wrap(BuildContext context, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mq = MediaQuery.of(context);
        final maxW = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : mq.size.width;
        final maxH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : mq.size.height;
        if (maxW <= 0 || maxH <= 0) return child;

        final factor = factorForWidth(maxW);
        final virtualHeight = maxH / factor;
        final userScale =
            mq.textScaler.scale(1).clamp(1.0, maxUserTextScale);

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: designWidth * factor,
            height: maxH,
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: designWidth,
                height: virtualHeight,
                child: MediaQuery(
                  data: mq.copyWith(
                    size: Size(designWidth, virtualHeight),
                    padding: scaleInsets(mq.padding, factor),
                    viewPadding: scaleInsets(mq.viewPadding, factor),
                    viewInsets: scaleInsets(mq.viewInsets, factor),
                    systemGestureInsets:
                        scaleInsets(mq.systemGestureInsets, factor),
                    textScaler: TextScaler.linear(userScale),
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
