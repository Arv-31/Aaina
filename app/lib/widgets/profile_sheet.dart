// profile_sheet.dart: the expanded profile card ("Aaina ID"). UI only.
//
// Opens when you tap a card on the camera or scan someone's Aaina QR code.
// Shows everything the person chose to share: status, skills and links.
// Empty or hidden fields are simply not there (never "not found").
//
// Look: an animated "ID" banner (drifting accent glow, dot grid, a big faint
// Aaina mark), the avatar with its turning ring overlapping the banner, then
// the sections slide up one after another.
//
// Takes a simple data object (ProfileData) and callbacks, so it has no network
// or database code (rule 6).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'aaina_logo.dart';
import 'ar_card.dart' show BrandBadge, RingAvatar;

enum LinkKind { linkedIn, github, instagram, portfolio }

class ProfileLink {
  final LinkKind kind;
  final String label; // short text, e.g. "@aravind.k"
  final Uri uri;
  const ProfileLink(this.kind, this.label, this.uri);
}

/// Everything the expanded card shows.
class ProfileData {
  final String initials;
  final String name;
  final String? status;
  final String? statusSub;
  final bool isStudent;
  final List<String> skills;
  final List<ProfileLink> links;

  const ProfileData({
    required this.initials,
    required this.name,
    this.status,
    this.statusSub,
    this.isStudent = false,
    this.skills = const [],
    this.links = const [],
  });
}

/// Opens the sheet over the current screen.
///
/// [source] is a short line under the name, e.g. "In view now" or
/// "From their Aaina code". [onSaveContact] null = no Save button (web, or
/// your own card).
Future<void> showProfileSheet(
  BuildContext context, {
  required ProfileData data,
  required String source,
  required void Function(Uri) onOpenLink,
  VoidCallback? onSaveContact,
  bool isYou = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: AppColors.scrim,
    builder: (_) => ProfileSheet(
      data: data,
      source: source,
      onOpenLink: onOpenLink,
      onSaveContact: onSaveContact,
      isYou: isYou,
    ),
  );
}

class ProfileSheet extends StatefulWidget {
  final ProfileData data;
  final String source;
  final void Function(Uri) onOpenLink;
  final VoidCallback? onSaveContact;
  final bool isYou;

  const ProfileSheet({
    super.key,
    required this.data,
    required this.source,
    required this.onOpenLink,
    this.onSaveContact,
    this.isYou = false,
  });

  @override
  State<ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<ProfileSheet> with TickerProviderStateMixin {
  // Sections appear one after another.
  late final _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  // Banner glow drift + avatar ring.
  late final _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  /// Fades and slides section number [i] in, a little after the one before.
  Widget _stagger(int i, Widget child) {
    final start = (0.12 * i).clamp(0.0, 0.6);
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, (start + 0.4).clamp(0.0, 1.0), curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(offset: Offset(0, 14 * (1 - anim.value)), child: c),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final maxH = MediaQuery.sizeOf(context).height * 0.88;
    var i = 0; // section counter for the stagger

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.sheetTop, AppColors.sheetBottom],
          ),
          border: Border(
            top: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x59000000), blurRadius: 30, offset: Offset(0, -6)),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Grab handle.
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.line2,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _stagger(i++, _bannerWithAvatar()),
                const SizedBox(height: 10),
                _stagger(i++, _nameBlock()),
                if (d.status != null) ...[
                  const SizedBox(height: 14),
                  _stagger(i++, _statusBlock()),
                ],
                if (d.skills.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _stagger(i++, _skills()),
                ],
                if (d.links.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _stagger(i++, _links()),
                ],
                const SizedBox(height: 18),
                _stagger(i++, _actions()),
                const SizedBox(height: 12),
                _stagger(
                  i++,
                  Text(
                    widget.isYou
                        ? 'THIS IS EXACTLY WHAT OTHERS SEE'
                        : 'ONLY WHAT ${_first(d.name).toUpperCase()} CHOSE TO SHARE',
                    style: AppText.fine,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _first(String name) => name.split(' ').first;

  // ---------------------------------------------------------------- banner

  Widget _bannerWithAvatar() {
    const bannerH = 112.0;
    const avatar = 78.0;
    return SizedBox(
      height: bannerH + avatar / 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: bannerH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AnimatedBuilder(
                animation: _loop,
                builder: (context, _) => CustomPaint(
                  painter: _BannerPainter(_loop.value),
                  child: _bannerLabels(),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            top: bannerH - avatar / 2,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.sheetTop,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.45),
                    blurRadius: 24,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: AnimatedBuilder(
                animation: _loop,
                builder: (context, _) => RingAvatar(
                  initials: widget.data.initials,
                  size: avatar - 8,
                  turn: _loop.value * 2,
                ),
              ),
            ),
          ),
          if (widget.isYou)
            Positioned(
              right: 4,
              top: bannerH + 8,
              child: _pill('YOU', AppColors.accent, filled: true),
            ),
        ],
      ),
    );
  }

  Widget _bannerLabels() {
    return Stack(
      children: [
        Positioned(
          left: 14,
          top: 12,
          child: Row(
            children: [
              const AainaMark(height: 10),
              const SizedBox(width: 7),
              Text('AAINA ID', style: AppText.arMeta.copyWith(color: AppColors.fg, fontSize: 9)),
            ],
          ),
        ),
        Positioned(
          right: 12,
          top: 9,
          child: _pill('VERIFIED · OPTED IN', AppColors.ok, icon: Icons.verified_rounded),
        ),
        // Big faint mark in the corner.
        const Positioned(
          right: -18,
          bottom: -22,
          child: AainaMark(height: 96, opacity: 0.07),
        ),
      ],
    );
  }

  Widget _pill(String text, Color color, {bool filled = false, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: filled ? 1 : 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: AppText.arMeta.copyWith(
              color: filled ? AppColors.accentInk : color,
              fontSize: 8.5,
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- sections

  Widget _nameBlock() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.data.name, style: AppText.heroName),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: AppColors.accent, blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 7),
              Text(widget.source.toUpperCase(),
                  style: AppText.arMeta.copyWith(fontSize: 9.5)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusBlock() {
    final d = widget.data;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
            ),
            child: Icon(
              d.isStudent ? Icons.school_rounded : Icons.work_rounded,
              color: AppColors.accent,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.isStudent ? 'STUDYING' : 'WORKING', style: AppText.linkKind),
                const SizedBox(height: 2),
                Text(d.status!, style: AppText.heroStatus),
                if (d.statusSub != null)
                  Text(d.statusSub!, style: AppText.small.copyWith(fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 8),
        child: Text(text, style: AppText.sectionLabel),
      );

  Widget _skills() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('SKILLS'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final s in widget.data.skills)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
                ),
                child: Text(s, style: AppText.chip),
              ),
          ],
        ),
      ],
    );
  }

  Widget _links() {
    final links = widget.data.links;
    // Two tiles per row; an odd last one takes the full width.
    final rows = <Widget>[];
    for (var k = 0; k < links.length; k += 2) {
      final pair = links.skip(k).take(2).toList();
      rows.add(Row(
        children: [
          Expanded(child: _linkTile(pair[0])),
          if (pair.length == 2) ...[
            const SizedBox(width: 8),
            Expanded(child: _linkTile(pair[1])),
          ],
        ],
      ));
      if (k + 2 < links.length) rows.add(const SizedBox(height: 8));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_label('LINKS'), ...rows],
    );
  }

  Widget _linkTile(ProfileLink l) {
    final (badge, kind) = switch (l.kind) {
      LinkKind.linkedIn => (BrandBadge.linkedIn(size: 26), 'LINKEDIN'),
      LinkKind.github => (BrandBadge.github(size: 26), 'GITHUB'),
      LinkKind.instagram => (BrandBadge.instagram(size: 26), 'INSTAGRAM'),
      LinkKind.portfolio => (BrandBadge.portfolio(size: 26), 'PORTFOLIO'),
    };
    return Material(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.onOpenLink(l.uri),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 9, 8, 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.line2),
          ),
          child: Row(
            children: [
              badge,
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(kind, style: AppText.linkKind),
                    const SizedBox(height: 1),
                    Text(l.label,
                        style: AppText.linkValue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const Icon(Icons.north_east_rounded, size: 13, color: AppColors.mute),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions() {
    final close = OutlinedButton(
      onPressed: () => Navigator.of(context).pop(),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: AppColors.line2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
      child: Text('Close', style: AppText.bodyStrong.copyWith(fontSize: 13.5)),
    );
    if (widget.onSaveContact == null) return close;
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: widget.onSaveContact,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18, color: AppColors.accentInk),
            label: Text('Save contact', style: AppText.button),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(width: 92, child: close),
      ],
    );
  }
}

/// Banner background: dark base, two accent glows drifting in slow circles,
/// and a faint dot grid. [t] goes 0 -> 1 over one loop.
class _BannerPainter extends CustomPainter {
  final double t;
  _BannerPainter(this.t);

  @override
  void paint(Canvas canvas, Size s) {
    final rect = Offset.zero & s;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0C1020));

    final a = t * 2 * math.pi;
    void glow(Offset c, double r, Color color) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color, color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(Offset(s.width * (0.25 + 0.08 * math.cos(a)), s.height * (0.2 + 0.15 * math.sin(a))),
        s.width * 0.55, AppColors.accent.withValues(alpha: 0.55));
    glow(Offset(s.width * (0.85 + 0.06 * math.sin(a)), s.height * (0.9 + 0.12 * math.cos(a))),
        s.width * 0.45, const Color(0xFF7B5BFF).withValues(alpha: 0.35));

    // Dot grid, brighter towards the top-left.
    const step = 12.0;
    final dot = Paint();
    for (var x = step / 2; x < s.width; x += step) {
      for (var y = step / 2; y < s.height; y += step) {
        final fade = 1 - (x / s.width) * 0.7;
        dot.color = Colors.white.withValues(alpha: 0.10 * fade);
        canvas.drawCircle(Offset(x, y), 0.8, dot);
      }
    }

    // Thin highlight along the top edge.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, 1),
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );
  }

  @override
  bool shouldRepaint(_BannerPainter old) => old.t != t;
}
