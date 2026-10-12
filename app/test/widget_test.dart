// Small checks that run on the laptop (no phone needed): `flutter test`.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aaina/features/camera_ar/face_detector_service.dart';

void main() {
  // The camera image is 480x640 (portrait) and the screen is 400x800.
  // Cover-fit scales by 1.25 (800/640): 480 px becomes 600 px, so 100 px is cut off each side.
  const image = Size(480, 640);
  const screen = Size(400, 800);

  test('box is scaled and shifted like the preview', () {
    final r = imageRectToScreen(
      const Rect.fromLTWH(100, 100, 80, 80),
      image,
      screen,
      mirror: false,
    );
    expect(r, const Rect.fromLTWH(25, 125, 100, 100));
  });

  test('front camera box is mirrored left-right', () {
    final r = imageRectToScreen(
      const Rect.fromLTWH(100, 100, 80, 80),
      image,
      screen,
      mirror: true,
    );
    // Mirrored left edge = 480 - 180 = 300 -> 300*1.25 - 100 = 275
    expect(r, const Rect.fromLTWH(275, 125, 100, 100));
  });
}
