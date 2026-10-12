// face_box.dart: the lock-on frame drawn around a face. UI only.
//
// Looks (see docs/design/m5-recognition-preview.html):
//   unknown  - faint white corner brackets with small tick marks
//   checking - brighter brackets, a dot mesh sweeping over the face and a
//              spinning ring while the laptop is asked "who is this?"
//   known    - blue glowing brackets with a soft blue fill
// The frame "snaps in" (shrinks from 135%) when it appears or becomes known.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';

enum FaceLook { unknown, checking, known }

class FaceBox extends StatefulWidget {
  final Rect rect; // the face, in screen pixels
  final FaceLook look;

  const FaceBox({super.key, required this.rect, this.look = FaceLook.unknown});

  /// Extra room around the face for the ticks and the ring.
  static const pad = 16.0;

  @override
  State<FaceBox> createState() => _FaceBoxState();
}

class _FaceBoxState extends State<FaceBox> with TickerProviderStateMixin {
  // Spins the ring and moves the mesh band while checking.
  late final _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );
  // The snap-in when the box appears or turns blue.
  late final _lock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();

  @override
  void initState() {
    super.initState();
    if (widget.look == FaceLook.checking) _spin.repeat();
  }

  @override
  void didUpdateWidget(FaceBox old) {
    super.didUpdateWidget(old);
    if (widget.look == FaceLook.checking && !_spin.isAnimating) _spin.repeat();
    if (widget.look != FaceLook.checking) _spin.stop();
    if (widget.look == FaceLook.known && old.look != FaceLook.known) {
      _lock.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _lock.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rect.inflate(FaceBox.pad);
    // AnimatedPositioned glides the frame between detections, so it looks
    // smooth even when faces are only found ~10 times per second.
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: Listenable.merge([_spin, _lock]),
          builder: (context, _) {
            final t = Curves.easeOutBack.transform(_lock.value);
            return Opacity(
              opacity: _lock.value.clamp(0, 1),
              child: Transform.scale(
                scale: 1.35 - 0.35 * t,
                child: CustomPaint(
                  painter: _ReticlePainter(widget.look, _spin.value),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReticlePainter extends CustomPainter {
  final FaceLook look;
  final double spin; // 0..1, repeats while checking

  _ReticlePainter(this.look, this.spin);

  @override
  void paint(Canvas canvas, Size size) {
    final face = (Offset.zero & size).deflate(FaceBox.pad);
    final color = switch (look) {
      FaceLook.known => AppColors.accent,
      FaceLook.checking => Colors.white.withValues(alpha: 0.75),
      FaceLook.unknown => Colors.white.withValues(alpha: 0.38),
    };

    if (look == FaceLook.known) {
      // Soft blue fill and a thin full outline behind the brackets.
      final rr = RRect.fromRectAndRadius(face, const Radius.circular(12));
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = RadialGradient(
            colors: [
              AppColors.accent.withValues(alpha: 0.12),
              AppColors.accent.withValues(alpha: 0),
            ],
          ).createShader(face),
      );
      canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.accent.withValues(alpha: 0.28),
      );
    }

    if (look == FaceLook.checking) {
      _mesh(canvas, face);
      _ring(canvas, face);
    }

    final corners = _corners(face);
    if (look == FaceLook.known) {
      // Glow: the same brackets, blurred, underneath.
      canvas.drawPath(
        corners,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = AppColors.accent.withValues(alpha: 0.7)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
    canvas.drawPath(
      corners,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );

    // Small tick marks in the middle of each side, pointing outwards.
    final tick = Paint()
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: color.a * 0.7);
    const len = 6.0;
    final c = face.center;
    canvas
      ..drawLine(Offset(c.dx, face.top), Offset(c.dx, face.top - len), tick)
      ..drawLine(Offset(c.dx, face.bottom), Offset(c.dx, face.bottom + len), tick)
      ..drawLine(Offset(face.left, c.dy), Offset(face.left - len, c.dy), tick)
      ..drawLine(Offset(face.right, c.dy), Offset(face.right + len, c.dy), tick);
  }

  /// Four rounded "L" corners as one path.
  Path _corners(Rect f) {
    final arm = (f.shortestSide * 0.22).clamp(8.0, 16.0);
    const r = 9.0;
    return Path()
      // top-left
      ..moveTo(f.left, f.top + arm)
      ..lineTo(f.left, f.top + r)
      ..quadraticBezierTo(f.left, f.top, f.left + r, f.top)
      ..lineTo(f.left + arm, f.top)
      // top-right
      ..moveTo(f.right - arm, f.top)
      ..lineTo(f.right - r, f.top)
      ..quadraticBezierTo(f.right, f.top, f.right, f.top + r)
      ..lineTo(f.right, f.top + arm)
      // bottom-right
      ..moveTo(f.right, f.bottom - arm)
      ..lineTo(f.right, f.bottom - r)
      ..quadraticBezierTo(f.right, f.bottom, f.right - r, f.bottom)
      ..lineTo(f.right - arm, f.bottom)
      // bottom-left
      ..moveTo(f.left + arm, f.bottom)
      ..lineTo(f.left + r, f.bottom)
      ..quadraticBezierTo(f.left, f.bottom, f.left, f.bottom - r)
      ..lineTo(f.left, f.bottom - arm);
  }

  /// Grid of dots inside the face oval, lit by a band sweeping downwards.
  void _mesh(Canvas canvas, Rect f) {
    final oval = f.deflate(4);
    final bandY = oval.top + (spin * 1.6 - 0.3) * oval.height;
    final paint = Paint();
    const step = 9.0;
    for (var y = oval.top + step / 2; y < oval.bottom; y += step) {
      final light = 1 - ((y - bandY).abs() / (oval.height * 0.3));
      if (light <= 0) continue;
      for (var x = oval.left + step / 2; x < oval.right; x += step) {
        // Only dots inside the oval: ((x-cx)/rx)^2 + ((y-cy)/ry)^2 <= 1
        final nx = (x - oval.center.dx) / (oval.width / 2);
        final ny = (y - oval.center.dy) / (oval.height / 2);
        if (nx * nx + ny * ny > 1) continue;
        paint.color = AppColors.hudDot.withValues(alpha: 0.8 * light);
        canvas.drawCircle(Offset(x, y), 1, paint);
      }
    }
  }

  /// A faint oval with a bright arc running around it.
  void _ring(Canvas canvas, Rect f) {
    final oval = f.inflate(9);
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withValues(alpha: 0.12),
    );
    canvas.drawArc(
      oval,
      spin * 2 * math.pi,
      0.9,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = AppColors.accent,
    );
  }

  @override
  bool shouldRepaint(_ReticlePainter old) =>
      old.look != look || old.spin != spin;
}
