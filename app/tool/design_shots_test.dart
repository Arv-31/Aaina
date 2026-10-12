// design_shots_test.dart: renders the Milestone 6 cards to PNG pictures so the
// design can be checked without a phone. Not part of the normal test run.
//
// Run from app/:
//   flutter test tool/design_shots_test.dart --update-goldens
// Pictures are written to tool/shots/.

import 'package:aaina/core/theme.dart';
import 'package:aaina/features/camera_ar/card_view.dart';
import 'package:aaina/widgets/ar_card.dart';
import 'package:aaina/widgets/my_code_sheet.dart';
import 'package:aaina/widgets/profile_sheet.dart';
import 'package:aaina/widgets/scan_overlays.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _aravind = {
  'user_id': 'u1',
  'name': 'Aravind K',
  'linkedin_url': 'https://www.linkedin.com/in/aravind-k/',
  'student_status': 'student',
  'course_year': 'BCA, 3rd year',
  'college': 'Christ University',
  'skills': ['Flutter', 'Python', 'FastAPI', 'UI design', 'OpenCV'],
  'github_url': 'https://github.com/aravindk',
  'instagram_url': 'https://instagram.com/aravind.k',
  'portfolio_url': 'https://aravind.dev',
};

const _meera = {
  'user_id': 'u2',
  'name': 'Meera Subramanian',
  'linkedin_url': 'https://www.linkedin.com/in/meera-s/',
  'student_status': 'professional',
  'job_title': 'Android Developer',
  'company': 'Nimbus Labs',
};

Future<void> _loadFonts() async {
  for (final (family, file) in [
    ('BricolageGrotesque', 'BricolageGrotesque.ttf'),
    ('Geist', 'Geist.ttf'),
    ('GeistMono', 'GeistMono.ttf'),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load('assets/fonts/$file'))).load();
  }
  // Material icons.
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

/// A stand-in "camera picture": dark room, two blurry people.
class _FakeCamera extends StatelessWidget {
  const _FakeCamera();
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.3, -0.4),
            radius: 1.2,
            colors: [Color(0xFF4A4F5C), Color(0xFF1E2128), Color(0xFF0E1014)],
          ),
        ),
      ),
      for (final (x, y, r, c) in [
        (70.0, 420.0, 48.0, const Color(0xFFA98370)),
        (270.0, 470.0, 38.0, const Color(0xFF8E6C5C)),
      ]) ...[
        Positioned(left: x - r, top: y - r * 1.25, child: Container(
          width: r * 2, height: r * 2.5,
          decoration: BoxDecoration(color: c, borderRadius: BorderRadius.all(Radius.elliptical(r, r * 1.25))),
        )),
        Positioned(left: x - r * 1.9, top: y + r * 1.3, child: Container(
          width: r * 3.8, height: 400,
          decoration: BoxDecoration(color: const Color(0xFF2F3B52), borderRadius: BorderRadius.circular(r * 1.5)),
        )),
      ],
    ]);
  }
}

Widget _phone(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    );

void main() {
  setUpAll(_loadFonts);

  testWidgets('ar cards', (t) async {
    t.view.physicalSize = const Size(1170, 2400);
    t.view.devicePixelRatio = 3;
    await t.pumpWidget(_phone(Stack(children: [
      const Positioned.fill(child: _FakeCamera()),
      // One person: full-size card.
      Positioned(left: 150, top: 120, child: ArCard(data: cardToView(_aravind))),
      // Two people: compact cards.
      Positioned(left: 14, top: 330, child: ArCard(data: cardToView(_aravind), width: 138, compact: true)),
      Positioned(left: 200, top: 560, child: ArCard(data: cardToView(_meera), width: 138, compact: true, unfoldFromRight: true)),
      // Mirror mode.
      Positioned(left: 14, top: 600, child: ArCard(data: cardToView(_meera), width: 168, isYou: true)),
    ])));
    await t.pump(const Duration(milliseconds: 1400)); // intro finished
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/ar_cards.png'));
  });

  testWidgets('ar card mid-animation', (t) async {
    t.view.physicalSize = const Size(600, 500);
    t.view.devicePixelRatio = 2;
    await t.pumpWidget(_phone(Stack(children: [
      const Positioned.fill(child: _FakeCamera()),
      Positioned(left: 40, top: 40, child: ArCard(data: cardToView(_aravind))),
    ])));
    await t.pump(const Duration(milliseconds: 520));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/ar_card_intro.png'));
  });

  testWidgets('profile sheet', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    await t.pumpWidget(_phone(Stack(children: [
      const Positioned.fill(child: _FakeCamera()),
      const Positioned.fill(child: ColoredBox(color: AppColors.scrim)),
      Align(
        alignment: Alignment.bottomCenter,
        child: ProfileSheet(
          data: cardToProfile(_aravind),
          source: 'In view now',
          onOpenLink: (_) {},
          onSaveContact: () {},
        ),
      ),
    ])));
    await t.pump(const Duration(milliseconds: 1200));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/profile_sheet.png'));
  });

  testWidgets('profile sheet minimal', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    await t.pumpWidget(_phone(Stack(children: [
      const Positioned.fill(child: _FakeCamera()),
      const Positioned.fill(child: ColoredBox(color: AppColors.scrim)),
      Align(
        alignment: Alignment.bottomCenter,
        child: ProfileSheet(
          data: cardToProfile(_meera),
          source: 'From their Aaina code',
          onOpenLink: (_) {},
          onSaveContact: () {},
        ),
      ),
    ])));
    await t.pump(const Duration(milliseconds: 1200));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/profile_sheet_min.png'));
  });

  testWidgets('qr mode + my code', (t) async {
    t.view.physicalSize = const Size(1170, 2532);
    t.view.devicePixelRatio = 3;
    await t.pumpWidget(_phone(Stack(children: [
      const Positioned.fill(child: _FakeCamera()),
      const Positioned.fill(child: QrViewfinder()),
      Positioned(left: 0, right: 0, bottom: 90, child: Center(child: ModeSwitch(qr: true, onChanged: (_) {}))),
      Positioned(left: 0, right: 0, top: 560, child: Center(child: GlassPill(icon: Icons.qr_code_2_rounded, text: 'Show my code', onTap: () {}))),
      const Positioned(left: 12, right: 12, top: 60, child: MirrorBanner(title: 'Mirror · this is you', text: 'Exactly the card other people see when they point Aaina at you.')),
      const Positioned(left: 12, right: 12, top: 680, child: MirrorStats(visible: true, sharedCount: 9)),
    ])));
    await t.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/qr_mode.png'));

    final ctx = t.element(find.byType(Scaffold));
    showMyCodeSheet(ctx, name: 'Aravind K', loadCode: () async => 'aaina:3f9c2b7d1e', newCode: () async => null);
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('shots/my_code.png'));
  });
}
