// hud.dart: the small heads-up-display pieces over the camera. UI only.
//
//   HudFrame     - faint grid + lens corner marks + tiny readouts
//   HudLabel     - small uppercase mono label above a face ("IDENTIFYING")
//   LeaderLine   - dashed elbow line from a face to its card
//   InViewStrip  - "IN VIEW" row of people chips
//   ScanLine     - glowing line sweeping up and down when no face is found
//   SignalBars   - three tiny bars for "connected"

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'ar_card.dart' show InitialsBadge;

/// Faint grid and lens corners so the camera feels like an instrument.
class HudFrame extends StatelessWidget {
  final String leftReadout;
  final String rightReadout;
  final EdgeInsets inset; // where the lens corners sit

  const HudFrame({
    super.key,
    required this.leftReadout,
    required this.rightReadout,
    this.inset = const EdgeInsets.fromLTRB(12, 64, 12, 132),
  });

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          CustomPaint(painter: _GridPainter()),
          Padding(
            padding: inset,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Positioned.fill(child: CustomPaint(painter: _LensPainter())),
                Positioned(
                  left: 0,
                  bottom: -16,
                  child: Text(leftReadout, style: AppText.hudReadout),
                ),
                Positioned(
                  right: 0,
                  bottom: -16,
                  child: Text(rightReadout, style: AppText.hudReadout),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Lines fade out towards the edges (strongest in the middle).
    final center = size.center(Offset.zero);
    final maxD = size.shortestSide * 0.8;
    const step = 28.0;
    final paint = Paint()..strokeWidth = 1;
    for (var x = step; x < size.width; x += step) {
      final a = (1 - ((x - center.dx).abs() / maxD)).clamp(0.0, 1.0);
      paint.color = AppColors.hudLine.withValues(alpha: AppColors.hudLine.a * a);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = step; y < size.height; y += step) {
      final a = (1 - ((y - center.dy).abs() / maxD)).clamp(0.0, 1.0);
      paint.color = AppColors.hudLine.withValues(alpha: AppColors.hudLine.a * a);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) => false;
}

class _LensPainter extends CustomPainter {
  const _LensPainter();

  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.25);
    const a = 14.0;
    canvas
      ..drawPath(Path()..moveTo(0, a)..lineTo(0, 0)..lineTo(a, 0), p)
      ..drawPath(Path()..moveTo(s.width - a, 0)..lineTo(s.width, 0)..lineTo(s.width, a), p)
      ..drawPath(Path()..moveTo(0, s.height - a)..lineTo(0, s.height)..lineTo(a, s.height), p)
      ..drawPath(
        Path()
          ..moveTo(s.width - a, s.height)
          ..lineTo(s.width, s.height)
          ..lineTo(s.width, s.height - a),
        p,
      );
  }

  @override
  bool shouldRepaint(_LensPainter old) => false;
}

/// Small glassy uppercase label, e.g. "IDENTIFYING" or "NOT ON AAINA".
class HudLabel extends StatelessWidget {
  final String text;
  final bool accent;

  const HudLabel(this.text, {super.key, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: accent
                  ? AppColors.accent.withValues(alpha: 0.4)
                  : AppColors.line2,
            ),
          ),
          child: Text(
            text.toUpperCase(),
            style: AppText.hudLabel.copyWith(
              color: accent ? AppColors.accent : AppColors.mute,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed elbow line from [from] (the face) to [to] (the card), plus a dot.
/// [vertical] = the card is above or below the face, so the elbow bends
/// up/down instead of sideways.
class LeaderLine extends StatelessWidget {
  final Offset from;
  final Offset to;
  final bool vertical;

  const LeaderLine({super.key, required this.from, required this.to, this.vertical = false});

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(child: CustomPaint(painter: _LeaderPainter(from, to, vertical)));
}

class _LeaderPainter extends CustomPainter {
  final Offset a, b;
  final bool vertical;
  _LeaderPainter(this.a, this.b, this.vertical);

  @override
  void paint(Canvas canvas, Size size) {
    final List<Offset> points;
    if (vertical) {
      final dir = b.dy >= a.dy ? 1.0 : -1.0;
      points = [a, Offset(a.dx, a.dy + dir * 6), Offset(b.dx, b.dy - dir * 6), b];
    } else {
      final dir = b.dx >= a.dx ? 1.0 : -1.0;
      points = [a, Offset(a.dx + dir * 10, a.dy), Offset(b.dx - dir * 8, b.dy), b];
    }
    final paint = Paint()
      ..strokeWidth = 1.2
      ..color = AppColors.accent.withValues(alpha: 0.75);
    // Dashes: 3 px on, 3 px off along each segment.
    for (var i = 0; i < points.length - 1; i++) {
      final p = points[i], q = points[i + 1];
      final len = (q - p).distance;
      if (len == 0) continue;
      final unit = (q - p) / len;
      for (var d = 0.0; d < len; d += 6) {
        final end = (d + 3).clamp(0.0, len);
        canvas.drawLine(p + unit * d, p + unit * end, paint);
      }
    }
    canvas.drawCircle(a, 2.5, Paint()..color = AppColors.accent);
  }

  @override
  bool shouldRepaint(_LeaderPainter old) =>
      old.a != a || old.b != b || old.vertical != vertical;
}

/// One person in the "In view" strip.
class InViewPerson {
  final String initials; // "?" for unknown
  final String label;
  final bool known;
  const InViewPerson(this.initials, this.label, {this.known = false});
}

class InViewStrip extends StatelessWidget {
  final List<InViewPerson> people;
  const InViewStrip({super.key, required this.people});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text('IN VIEW', style: AppText.hudReadout.copyWith(color: AppColors.mute)),
          const SizedBox(width: 8),
          for (final p in people) ...[
            _chip(p),
            const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }

  Widget _chip(InViewPerson p) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 30,
          padding: const EdgeInsets.fromLTRB(3, 3, 10, 3),
          decoration: BoxDecoration(
            color: AppColors.glass,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: p.known
                  ? AppColors.accent.withValues(alpha: 0.55)
                  : AppColors.line2,
            ),
          ),
          child: Row(
            children: [
              InitialsBadge(p.initials, size: 24, round: true),
              const SizedBox(width: 6),
              Text(p.label, style: AppText.pill.copyWith(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Glowing line that sweeps up and down while no face is in view.
class ScanLine extends StatefulWidget {
  const ScanLine({super.key});
  @override
  State<ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<ScanLine>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Align(
          alignment: Alignment(0, -0.55 + 0.9 * Curves.easeInOut.transform(_c.value)),
          child: FractionallySizedBox(
            widthFactor: 0.72,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.accent.withValues(alpha: 0),
                    AppColors.accent.withValues(alpha: 0.85),
                    AppColors.accent.withValues(alpha: 0),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.5),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three tiny green bars: "connected to the laptop".
class SignalBars extends StatelessWidget {
  final Color color;
  const SignalBars({super.key, this.color = AppColors.ok});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final h in [3.0, 6.0, 9.0]) ...[
          Container(
            width: 2,
            height: h,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(width: 1.5),
        ],
      ],
    );
  }
}
