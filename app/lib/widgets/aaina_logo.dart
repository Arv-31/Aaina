// aaina_logo.dart: the Aaina mark + wordmark. UI only.
//
// Mark: two lowercase "a" bowls mirrored around one shared accent bar.
// Wordmark: "aaina" with the "i" in the accent colour (locked design).

import 'package:flutter/material.dart';

import '../core/theme.dart';

class AainaLogo extends StatelessWidget {
  final double height; // height of the mark; the text scales with it

  const AainaLogo({super.key, this.height = 14});

  @override
  Widget build(BuildContext context) {
    final word = AppText.title.copyWith(
      fontSize: height * 1.15,
      letterSpacing: -0.5,
      height: 1,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: height * 44 / 26,
          height: height,
          child: const CustomPaint(painter: _MarkPainter()),
        ),
        SizedBox(width: height * 0.45),
        Text.rich(
          TextSpan(
            style: word,
            children: [
              const TextSpan(text: 'aa'),
              TextSpan(text: 'i', style: word.copyWith(color: AppColors.accent)),
              const TextSpan(text: 'na'),
            ],
          ),
        ),
      ],
    );
  }
}

class _MarkPainter extends CustomPainter {
  const _MarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on the design's 44 x 26 grid, then scaled to fit.
    final s = size.height / 26;
    canvas.scale(s);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..color = AppColors.fg;
    canvas
      ..drawCircle(const Offset(11, 15), 8, ring)
      ..drawCircle(const Offset(33, 15), 8, ring)
      ..drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(20, 2, 4, 22),
          const Radius.circular(2),
        ),
        Paint()..color = AppColors.accent,
      );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => false;
}

/// Just the mark (no wordmark), e.g. as a big faint watermark on cards.
class AainaMark extends StatelessWidget {
  final double height;
  final double opacity;

  const AainaMark({super.key, this.height = 26, this.opacity = 1});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: SizedBox(
        width: height * 44 / 26,
        height: height,
        child: const CustomPaint(painter: _MarkPainter()),
      ),
    );
  }
}
