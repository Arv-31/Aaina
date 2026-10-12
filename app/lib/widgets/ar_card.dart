// ar_card.dart: the glass card that floats beside a recognised face. UI only.
//
// Shows only what matters in the moment: name, current status, LinkedIn.
// Takes a simple data object, so a new card design can be dropped in later
// without touching the camera or network code (synopsis section 12).
//
// Look (Milestone 6): HUD corner ticks like the face lock-on, a
// "VERIFIED · AAINA" header, a slowly turning ring around the initials, and a
// short "materialise" animation when the card first appears:
//   1. the card unfolds from the face side,
//   2. a band of light sweeps across the glass,
//   3. the text fades in.
// The light band comes back every few seconds so the card feels alive.

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../core/theme.dart';

/// Everything the card shows. Empty optional fields are simply not drawn.
class ArCardData {
  final String initials; // e.g. "AK"
  final String name;
  final String? status; // e.g. "Student · BCA, 3rd year"
  final String? statusSub; // e.g. "Christ University"
  final String? linkedInLabel; // e.g. "in/aravind-k"
  final bool isStudent; // picks the cap or briefcase icon

  const ArCardData({
    required this.initials,
    required this.name,
    this.status,
    this.statusSub,
    this.linkedInLabel,
    this.isStudent = false,
  });
}

class ArCard extends StatefulWidget {
  final ArCardData data;
  final double width;

  /// Smaller text and avatar, used when 2+ people are in view.
  final bool compact;

  /// True when the card sits LEFT of the face, so it unfolds from its right edge.
  final bool unfoldFromRight;

  /// Mirror mode: this card is the person holding the phone ("YOU" tag).
  final bool isYou;

  final VoidCallback? onTap;
  final VoidCallback? onLinkedIn;

  const ArCard({
    super.key,
    required this.data,
    this.width = 168,
    this.compact = false,
    this.unfoldFromRight = false,
    this.isYou = false,
    this.onTap,
    this.onLinkedIn,
  });

  /// Rough heights, used to keep cards from overlapping before they are drawn.
  static double heightFor(ArCardData d, {required bool compact}) {
    var h = compact ? 68.0 : 80.0; // padding + header + avatar row
    if (d.status != null) h += compact ? 20 : 24;
    if (d.statusSub != null) h += compact ? 13 : 14;
    if (d.linkedInLabel != null) h += compact ? 31 : 38;
    return h;
  }

  @override
  State<ArCard> createState() => _ArCardState();
}

class _ArCardState extends State<ArCard> with TickerProviderStateMixin {
  // Plays once when the card appears.
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..forward();

  // Loops forever: turns the avatar ring and brings the light band back.
  late final _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// Maps the intro's 0..1 onto a smaller window, e.g. 0.3..0.7 -> 0..1.
  double _phase(double from, double to, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((_intro.value - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_intro, _loop]),
        builder: (context, _) {
          final unfold = _phase(0, 0.42);
          final content = _phase(0.3, 0.75);
          // Light band: once in the intro, then once every loop.
          final sweep = _intro.isCompleted
              ? (_loop.value * 6 / 1.2) // first 1.2 s of every 6 s
              : _phase(0.25, 0.95, Curves.easeInOut);

          return SizedBox(
            width: widget.width,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The card unfolds sideways out of the leader line. The clip is
                // removed once it is open, so the soft shadow isn't cut off.
                if (unfold < 1)
                  ClipRect(
                    child: Align(
                      alignment: widget.unfoldFromRight
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      widthFactor: 0.08 + 0.92 * unfold,
                      child: Opacity(
                        opacity: (0.4 + unfold).clamp(0.0, 1.0),
                        child: _glass(content, sweep),
                      ),
                    ),
                  )
                else
                  _glass(content, sweep),
                // HUD corner ticks, drawn just outside the card.
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: content,
                      child: CustomPaint(painter: _CornerTicks()),
                    ),
                  ),
                ),
                if (widget.isYou)
                  Positioned(
                    top: -9,
                    right: 12,
                    child: Opacity(opacity: content, child: const _YouTag()),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _glass(double content, double sweep) {
    final c = widget.compact;
    const radius = 15.0;
    // Outer container = 1 px gradient border; inner = blurred dark glass.
    return Container(
      width: widget.width,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + 1),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.accent,
            AppColors.accent.withValues(alpha: 0.12),
            Colors.white.withValues(alpha: 0.22),
          ],
          stops: const [0, 0.5, 1],
        ),
        boxShadow: [
          const BoxShadow(
            color: Color(0x8C000000),
            blurRadius: 26,
            offset: Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.22),
            blurRadius: 24,
            spreadRadius: -6,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Stack(
            children: [
              Container(
                padding: EdgeInsets.fromLTRB(c ? 9 : 11, c ? 8 : 9, c ? 9 : 11, c ? 9 : 11),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.glassTop, AppColors.glass],
                  ),
                ),
                child: Opacity(opacity: content, child: _content()),
              ),
              // The moving band of light (only while it is crossing).
              if (sweep > 0 && sweep < 1)
                Positioned.fill(child: IgnorePointer(child: _Sheen(sweep))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    final d = widget.data;
    final c = widget.compact;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header: "● VERIFIED · AAINA" ............ expand icon
        Row(
          children: [
            Container(
              width: 5,
              height: 5,
              decoration: const BoxDecoration(
                color: AppColors.ok,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.ok, blurRadius: 5)],
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                c ? 'VERIFIED' : 'VERIFIED · AAINA',
                style: AppText.arMeta.copyWith(color: AppColors.ok),
                maxLines: 1,
              ),
            ),
            Icon(Icons.open_in_full_rounded,
                size: c ? 10 : 11, color: AppColors.mute),
          ],
        ),
        SizedBox(height: c ? 7 : 8),
        Row(
          children: [
            RingAvatar(
              initials: d.initials,
              size: c ? 30 : 38,
              turn: _loop.value,
            ),
            SizedBox(width: c ? 7 : 9),
            Expanded(
              child: Text(
                d.name,
                style: AppText.arName.copyWith(fontSize: c ? 13 : 15.5),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        if (d.status != null) ...[
          SizedBox(height: c ? 6 : 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  d.isStudent ? Icons.school_rounded : Icons.work_rounded,
                  size: c ? 11 : 12,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.status!,
                      style: AppText.arStatus.copyWith(fontSize: c ? 10.5 : 11.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (d.statusSub != null)
                      Text(
                        d.statusSub!,
                        style: AppText.arSub.copyWith(fontSize: c ? 10 : 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
        if (d.linkedInLabel != null) ...[
          SizedBox(height: c ? 7 : 9),
          _linkedIn(),
        ],
      ],
    );
  }

  Widget _linkedIn() {
    final c = widget.compact;
    return GestureDetector(
      onTap: widget.onLinkedIn,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: c ? 6 : 7, vertical: c ? 4 : 6),
        decoration: BoxDecoration(
          color: AppColors.linkedIn.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: AppColors.linkedIn.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            BrandBadge.linkedIn(size: c ? 15 : 17),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.data.linkedInLabel!,
                style: AppText.arSub.copyWith(
                  color: AppColors.fg,
                  fontSize: c ? 9.5 : 10.5,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.north_east_rounded, size: c ? 10 : 11, color: AppColors.mute),
          ],
        ),
      ),
    );
  }
}

/// Diagonal band of light that crosses the card. [t] goes 0 -> 1.
class _Sheen extends StatelessWidget {
  final double t;
  const _Sheen(this.t);

  @override
  Widget build(BuildContext context) {
    final x = -1.6 + 3.2 * t; // from off the left edge to off the right edge
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(x - 0.5, -1),
          end: Alignment(x + 0.5, 1),
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.10),
            AppColors.accent.withValues(alpha: 0.18),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.3, 0.48, 0.55, 0.7],
        ),
      ),
    );
  }
}

/// Initials inside a slowly turning accent ring.
class RingAvatar extends StatelessWidget {
  final String initials;
  final double size;
  final double turn; // 0..1 = one full turn

  const RingAvatar({super.key, required this.initials, required this.size, required this.turn});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(
            angle: turn * 2 * math.pi,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    AppColors.accent,
                    AppColors.accent.withValues(alpha: 0),
                    AppColors.accentSoft.withValues(alpha: 0.6),
                    AppColors.accent.withValues(alpha: 0),
                    AppColors.accent,
                  ],
                  stops: const [0, 0.3, 0.55, 0.8, 1],
                ),
              ),
            ),
          ),
          // Dark gap between the ring and the badge.
          Container(
            width: size - 4,
            height: size - 4,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.bg,
            ),
          ),
          InitialsBadge(initials, size: size - 7, round: true),
        ],
      ),
    );
  }
}

/// Small L-shaped accent marks just outside each corner of the card.
class _CornerTicks extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = AppColors.accent.withValues(alpha: 0.9);
    const o = 4.0; // distance outside the card
    const a = 9.0; // arm length
    canvas
      ..drawPath(Path()..moveTo(-o, a - o)..lineTo(-o, -o)..lineTo(a - o, -o), p)
      ..drawPath(
          Path()..moveTo(s.width - a + o, -o)..lineTo(s.width + o, -o)..lineTo(s.width + o, a - o), p)
      ..drawPath(
          Path()..moveTo(-o, s.height - a + o)..lineTo(-o, s.height + o)..lineTo(a - o, s.height + o), p)
      ..drawPath(
          Path()
            ..moveTo(s.width - a + o, s.height + o)
            ..lineTo(s.width + o, s.height + o)
            ..lineTo(s.width + o, s.height - a + o),
          p);
  }

  @override
  bool shouldRepaint(_CornerTicks old) => false;
}

/// "YOU" tag on the card in mirror mode.
class _YouTag extends StatelessWidget {
  const _YouTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(color: AppColors.accent.withValues(alpha: 0.6), blurRadius: 10),
        ],
      ),
      child: Text('YOU', style: AppText.arMeta.copyWith(color: AppColors.accentInk, fontSize: 8.5)),
    );
  }
}

/// Small square brand badge ("in", "gh", "ig", portfolio arrow).
class BrandBadge extends StatelessWidget {
  final String text;
  final double size;
  final Color? color;
  final Gradient? gradient;
  final Color textColor;

  const BrandBadge({
    super.key,
    required this.text,
    this.size = 20,
    this.color,
    this.gradient,
    this.textColor = Colors.white,
  });

  factory BrandBadge.linkedIn({double size = 20}) =>
      BrandBadge(text: 'in', size: size, color: AppColors.linkedIn);

  factory BrandBadge.github({double size = 20}) =>
      BrandBadge(text: 'gh', size: size, color: AppColors.github);

  factory BrandBadge.instagram({double size = 20}) => BrandBadge(
        text: 'ig',
        size: size,
        gradient: const LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: [AppColors.instagramFrom, AppColors.instagramMid, AppColors.instagramTo],
        ),
      );

  factory BrandBadge.portfolio({double size = 20}) => BrandBadge(
        text: '↗',
        size: size,
        color: AppColors.avatarUnknown,
        textColor: AppColors.accent,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        gradient: gradient,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Text(
        text,
        style: AppText.bodyStrong.copyWith(color: textColor, fontSize: size * 0.48, height: 1),
      ),
    );
  }
}

/// Rounded square (or circle) with someone's initials. "?" = unknown person.
class InitialsBadge extends StatelessWidget {
  final String text;
  final double size;
  final bool round;

  const InitialsBadge(this.text, {super.key, this.size = 30, this.round = false});

  @override
  Widget build(BuildContext context) {
    final unknown = text == '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: round ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: round ? null : BorderRadius.circular(size * 0.3),
        color: unknown ? AppColors.avatarUnknown : null,
        gradient: unknown
            ? null
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.avatarFrom, AppColors.avatarTo],
              ),
      ),
      child: Text(
        text,
        style: AppText.initials.copyWith(
          fontSize: size * 0.38,
          color: unknown ? AppColors.mute : AppColors.accentInk,
        ),
      ),
    );
  }
}
