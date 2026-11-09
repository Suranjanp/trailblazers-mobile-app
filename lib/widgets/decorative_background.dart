import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class DecorativeBackground extends StatelessWidget {
  const DecorativeBackground({super.key});

  @override
  Widget build(BuildContext context) {

    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 120,
          child: const CustomPaint(
            painter: TopWavePainter(),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 120,
          child: const CustomPaint(
            painter: BottomWavePainter(),
          ),
        ),
      ],
    );
  }
}




class TopWavePainter extends CustomPainter {
  const TopWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Save the original canvas state.
    canvas.save();

    // Flip the canvas across both the X and Y axes.
    canvas.translate(size.width, size.height);
    canvas.scale(-1, -1);

    // Reuse the exact bottom-right design.
    const BottomWavePainter().paint(canvas, size);

    // Restore the original canvas state.
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TopWavePainter oldDelegate) => false;
}



class BottomWavePainter extends CustomPainter {
  const BottomWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final navy = Paint()..color = AppColors.navigationNavy;
    final orange = Paint()..color = AppColors.trailblazerOrange;
    final pale = Paint()..color = const Color(0xFFF0F3FA);

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
  bool shouldRepaint(covariant BottomWavePainter oldDelegate) => false;
}