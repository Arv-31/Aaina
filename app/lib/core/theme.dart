// theme.dart: the ONE place for colors, fonts, spacing and corner radius.
//
// Every screen and widget reads its look from here. To restyle the app,
// edit this file only (rule 6). Values match docs/design/aaina-design-preview.html.

import 'package:flutter/material.dart';

/// Colors (dark only).
class AppColors {
  static const bg = Color(0xFF07080B); // page background
  static const surface1 = Color(0xFF0E1015); // raised surface (cards, sheets)
  static const surface2 = Color(0xFF151821); // inputs, chips
  static const line = Color(0x12FFFFFF); // thin borders (7% white)
  static const line2 = Color(0x1FFFFFFF); // stronger borders (12% white)
  static const fg = Color(0xFFECEDF1); // main text
  static const mute = Color(0xFF8A8E99); // secondary text
  static const dim = Color(0xFF5A5E69); // hints, disabled
  static const accent = Color(0xFF5B8CFF); // brand blue
  static const accentInk = Color(0xFF050814); // text on top of accent
  static const ok = Color(0xFF3DDC97);
  static const warn = Color(0xFFFFB547);
  static const bad = Color(0xFFFF6B6B);

  /// Glassy dark used for pills and cards floating over the camera.
  static const glass = Color(0xB8101218); // ~72% opaque
  /// Corner color for a face we have not identified (yet).
  static const unknownBox = Color(0x73FFFFFF); // 45% white

  /// LinkedIn brand blue, only for the little "in" badge.
  static const linkedIn = Color(0xFF0A66C2);

  /// Faint blue for the HUD grid and dot mesh on the camera.
  static const hudLine = Color(0x0D8CA5FF); // 5%
  static const hudDot = Color(0xE68CAFFF); // 90%

  /// Top of the AR card's glass (a bit lighter than [glass]).
  static const glassTop = Color(0xD1161A26);

  /// Avatar gradient (initials badge).
  static const avatarFrom = Color(0xFF7FA5FF);
  static const avatarTo = Color(0xFF3B5FC0);
  static const avatarUnknown = Color(0xFF2A2E3A);

  // ---- Milestone 6: profile cards ----
  /// Other brand colors, only for the small link badges.
  static const github = Color(0xFF24292F);
  static const instagramFrom = Color(0xFFF58529);
  static const instagramMid = Color(0xFFDD2A7B);
  static const instagramTo = Color(0xFF8134AF);

  /// Light accent text on dark (skill chips, small highlights).
  static const accentSoft = Color(0xFFBFD0FF);

  /// Expanded card sheet: top and bottom of its background.
  static const sheetTop = Color(0xFF131722);
  static const sheetBottom = Color(0xFF0B0D12);

  /// Dark see-through layer behind sheets.
  static const scrim = Color(0x8C040508);
}

/// Font family names (the files live in assets/fonts, declared in pubspec.yaml).
class AppFonts {
  static const display = 'BricolageGrotesque'; // titles
  static const body = 'Geist'; // normal text
  static const mono = 'GeistMono'; // numbers, scores, data
}

/// Spacing scale, in logical pixels.
class AppSpace {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
}

/// Corner radius scale.
class AppRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 22.0;
  static const pill = 99.0;
}

/// Text styles. The font files are "variable" fonts, so the weight is also
/// passed as a font variation to make sure it is actually applied.
class AppText {
  static TextStyle _style(
    String family,
    double size,
    int weight, {
    Color color = AppColors.fg,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    color: color,
    fontWeight: FontWeight.values[(weight ~/ 100) - 1],
    fontVariations: [FontVariation('wght', weight.toDouble())],
  );

  static final title = _style(AppFonts.display, 26, 700);
  static final cardName = _style(AppFonts.display, 17, 700);
  static final body = _style(AppFonts.body, 14, 400);
  static final bodyStrong = _style(AppFonts.body, 14, 600);
  static final small = _style(AppFonts.body, 12, 500, color: AppColors.mute);
  static final pill = _style(AppFonts.body, 12, 500);
  static final mono = _style(AppFonts.mono, 12, 500);

  // Camera HUD and AR card.
  static final hudLabel = _style(AppFonts.mono, 10, 500, color: AppColors.mute)
      .copyWith(letterSpacing: 0.8);
  static final hudReadout = _style(AppFonts.mono, 8.5, 500,
      color: const Color(0x59FFFFFF)).copyWith(letterSpacing: 1.1);
  static final arName = _style(AppFonts.display, 15, 700)
      .copyWith(letterSpacing: -0.3, height: 1.1);
  static final arStatus = _style(AppFonts.body, 11.5, 500).copyWith(height: 1.3);
  static final arSub = _style(AppFonts.body, 11, 400, color: AppColors.mute);
  static final arOk = _style(AppFonts.body, 9.5, 500, color: AppColors.ok);
  static final initials = _style(AppFonts.display, 12, 700,
      color: AppColors.accentInk);
  static final sheetTitle = _style(AppFonts.display, 22, 700)
      .copyWith(letterSpacing: -0.6);
  static final fieldLabel = _style(AppFonts.body, 11.5, 500, color: AppColors.mute);
  static final input = _style(AppFonts.body, 14, 400);
  // Milestone 6: AR card micro text and the expanded card.
  static final arMeta = _style(AppFonts.mono, 7.5, 500,
      color: AppColors.accent).copyWith(letterSpacing: 1.2);
  static final heroName = _style(AppFonts.display, 28, 800)
      .copyWith(letterSpacing: -1.0, height: 1.0);
  static final heroStatus = _style(AppFonts.body, 14, 500).copyWith(height: 1.3);
  static final sectionLabel = _style(AppFonts.mono, 9.5, 500,
      color: AppColors.mute).copyWith(letterSpacing: 1.6);
  static final chip = _style(AppFonts.mono, 11, 500, color: AppColors.accentSoft);
  static final linkKind = _style(AppFonts.mono, 8.5, 500,
      color: AppColors.mute).copyWith(letterSpacing: 1.0);
  static final linkValue = _style(AppFonts.body, 12.5, 500);
  static final fine = _style(AppFonts.mono, 9.5, 500, color: AppColors.dim)
      .copyWith(letterSpacing: 0.4);

  static final button = _style(
    AppFonts.body,
    13.5,
    600,
    color: AppColors.accentInk,
  );
}

/// The Material theme built from the tokens above.
ThemeData buildAppTheme() {
  return ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: AppFonts.body,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.accent,
      onPrimary: AppColors.accentInk,
      surface: AppColors.surface1,
      onSurface: AppColors.fg,
      error: AppColors.bad,
    ),
  );
}
