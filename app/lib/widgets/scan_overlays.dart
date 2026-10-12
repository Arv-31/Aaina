// scan_overlays.dart: extra layers on the camera for Milestone 6. UI only.
//
//   QrViewfinder  - dark shade with a square window, lock-on corners and a
//                   sweeping line ("Scan an Aaina code")
//   ModeSwitch    - "Faces | QR" segmented switch above the dock
//   MirrorBanner  - "Mirror · this is you" note when the front camera sees you
//   MirrorStats   - two small tiles: visible/hidden and how much you share
//   GlassPill     - small tappable glass pill ("Show my code")

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Square scanning window in the middle of the screen.
class QrViewfinder extends StatefulWidget {
  final bool busy; // true while the laptop looks up a found code
  const QrViewfinder({super.key, this.busy = false});

  @override
  State<QrViewfinder> createState() => _QrViewfinderState();
}

class _QrViewfinderState extends State<QrViewfinder> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, box) {
          final side = (box.maxWidth * 0.66).clamp(180.0, 300.0);
          final window = Rect.fromCenter(
            center: Offset(box.maxWidth / 2, box.maxHeight * 0.45),
            width: side,
            height: side,
          );
          return AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _ShadePainter(window, Curves.easeInOut.transform(_c.value), widget.busy),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: window.top - 66,
                  child: Column(
                    children: [
                      Text(widget.busy ? 'Opening card…' : 'Scan an Aaina code',
                          style: AppText.arName.copyWith(fontSize: 19)),
                      const SizedBox(height: 4),
                      Text("For when a face can't be recognised",
                          style: AppText.small.copyWith(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ShadePainter extends CustomPainter {
  final Rect window;
  final double t; // 0..1 position of the sweeping line
  final bool busy;
  _ShadePainter(this.window, this.t, this.busy);

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(window, const Radius.circular(18));
    // Dark everywhere except the window.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRRect(hole),
      Paint()..color = const Color(0xA6040508),
    );

    // Lock-on corners (thicker, with a glow).
    const arm = 26.0;
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = busy ? AppColors.ok : AppColors.accent
      ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3);
    final r = window;
    canvas
      ..drawPath(Path()..moveTo(r.left, r.top + arm)..lineTo(r.left, r.top + 10)
          ..arcToPoint(Offset(r.left + 10, r.top), radius: const Radius.circular(10))
          ..lineTo(r.left + arm, r.top), corner)
      ..drawPath(Path()..moveTo(r.right - arm, r.top)..lineTo(r.right - 10, r.top)
          ..arcToPoint(Offset(r.right, r.top + 10), radius: const Radius.circular(10))
          ..lineTo(r.right, r.top + arm), corner)
      ..drawPath(Path()..moveTo(r.left, r.bottom - arm)..lineTo(r.left, r.bottom - 10)
          ..arcToPoint(Offset(r.left + 10, r.bottom), radius: const Radius.circular(10), clockwise: false)
          ..lineTo(r.left + arm, r.bottom), corner)
      ..drawPath(Path()..moveTo(r.right - arm, r.bottom)..lineTo(r.right - 10, r.bottom)
          ..arcToPoint(Offset(r.right, r.bottom - 10), radius: const Radius.circular(10), clockwise: false)
          ..lineTo(r.right, r.bottom - arm), corner);

    // Sweeping line inside the window.
    if (!busy) {
      final y = r.top + 12 + (r.height - 24) * t;
      final line = Rect.fromLTWH(r.left + 14, y - 1, r.width - 28, 2);
      canvas.drawRect(
        line,
        Paint()
          ..shader = LinearGradient(colors: [
            AppColors.accent.withValues(alpha: 0),
            AppColors.accent,
            AppColors.accent.withValues(alpha: 0),
          ]).createShader(line)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(_ShadePainter old) => old.t != t || old.window != window || old.busy != busy;
}

/// "Faces | QR" switch.
class ModeSwitch extends StatelessWidget {
  final bool qr;
  final ValueChanged<bool> onChanged;

  const ModeSwitch({super.key, required this.qr, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget seg(String text, bool on, bool value) => GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            decoration: BoxDecoration(
              color: on ? AppColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              text,
              style: AppText.pill.copyWith(color: on ? AppColors.accentInk : AppColors.mute),
            ),
          ),
        );
    return _glass(
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg('Faces', !qr, false), seg('QR', qr, true)],
      ),
    );
  }
}

/// Tappable glass pill with an icon, e.g. "Show my code".
class GlassPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;

  const GlassPill({super.key, required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _glass(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: AppColors.fg),
            const SizedBox(width: 7),
            Text(text, style: AppText.pill),
          ],
        ),
      ),
    );
  }
}

/// Note at the top in mirror mode.
class MirrorBanner extends StatelessWidget {
  final String title;
  final String text;
  final bool warn; // amber look, e.g. "You're hidden"

  const MirrorBanner({super.key, required this.title, required this.text, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final color = warn ? AppColors.warn : AppColors.accent;
    return _glass(
      radius: AppRadius.md,
      border: color.withValues(alpha: 0.4),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Icon(warn ? Icons.visibility_off_rounded : Icons.flip_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.arName.copyWith(fontSize: 13.5, color: warn ? color : null)),
                const SizedBox(height: 1),
                Text(text, style: AppText.arSub),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Two small tiles in mirror mode: status + sharing.
class MirrorStats extends StatelessWidget {
  final bool visible;
  final int sharedCount;

  const MirrorStats({super.key, required this.visible, required this.sharedCount});

  @override
  Widget build(BuildContext context) {
    Widget tile(String label, String value, Color color) => Expanded(
          child: _glass(
            radius: AppRadius.md,
            padding: const EdgeInsets.fromLTRB(11, 8, 11, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppText.linkKind),
                const SizedBox(height: 2),
                Text(value, style: AppText.bodyStrong.copyWith(fontSize: 12.5, color: color)),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile('STATUS', visible ? '● Visible' : '● Hidden', visible ? AppColors.ok : AppColors.warn),
        const SizedBox(width: 8),
        tile('SHARING', '$sharedCount details', AppColors.fg),
      ],
    );
  }
}

/// Shared blurred-glass box used by the widgets above.
Widget _glass({
  required Widget child,
  EdgeInsets padding = EdgeInsets.zero,
  double radius = AppRadius.pill,
  Color border = AppColors.line2,
}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppColors.glass,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border),
        ),
        child: child,
      ),
    ),
  );
}
