import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Shared Trailblazer decorative background.
/// The full canvas is explicitly filled with the active scaffold color so
/// transparent areas cannot reveal a light system/default background in dark mode.
class DecorativeBackground extends StatelessWidget {
  const DecorativeBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final background = theme.scaffoldBackgroundColor;
    final isDark = theme.brightness == Brightness.dark;

    return ColoredBox(
      color: background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: CustomPaint(
              painter: TopWavePainter(isDark, background),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 120,
            child: CustomPaint(
              painter: BottomWavePainter(isDark, background),
            ),
          ),
        ],
      ),
    );
  }
}

class TopWavePainter extends CustomPainter {
  const TopWavePainter(this._isDark, this._background);

  final bool _isDark;
  final Color _background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(size.width, size.height);
    canvas.scale(-1, -1);
    BottomWavePainter(_isDark, _background).paint(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TopWavePainter oldDelegate) {
    return oldDelegate._isDark != _isDark ||
        oldDelegate._background != _background;
  }
}

class BottomWavePainter extends CustomPainter {
  const BottomWavePainter(this._isDark, this._background);

  final bool _isDark;
  final Color _background;

  @override
  void paint(Canvas canvas, Size size) {
    final navy = Paint()..color = AppColors.navigationNavy;
    final orange = Paint()..color = AppColors.trailblazerOrange;
    // Use the exact page background for the pale wave. This avoids a separate
    // gray/blue patch appearing behind the form in either theme.
    final pale = Paint()..color = _background;

    final palePath = Path()
      ..moveTo(size.width, 0)
      ..cubicTo(
        size.width * .82, 80,
        size.width * .72, 140,
        size.width * .55, size.height,
      )
      ..lineTo(0, size.height)
      ..lineTo(size.width, 0)
      ..close();

    final navyPath = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width * .55, size.height)
      ..cubicTo(
        size.width * .72, 140,
        size.width * .82, 80,
        size.width, 0,
      )
      ..close();

    final orangePath = Path()
      ..moveTo(size.width, size.height * .38)
      ..cubicTo(
        size.width * .91, 115,
        size.width * .80, 155,
        size.width * .68, size.height,
      )
      ..lineTo(size.width * .55, size.height)
      ..cubicTo(
        size.width * .76, 140,
        size.width * .89, 90,
        size.width, size.height * .38,
      )
      ..close();

    canvas.drawPath(palePath, pale);
    canvas.drawPath(navyPath, navy);
    canvas.drawPath(orangePath, orange);
  }

  @override
  bool shouldRepaint(covariant BottomWavePainter oldDelegate) {
    return oldDelegate._isDark != _isDark ||
        oldDelegate._background != _background;
  }
}
