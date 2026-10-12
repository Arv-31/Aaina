// Checks that cards never overlap each other, never cover another face, and
// stay between the top bar and the bottom dock (Milestone 6).

import 'dart:ui';

import 'package:aaina/features/camera_ar/card_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const phone = Size(360, 760);
  const w = 138.0;

  bool overlaps(List<CardPlacement> p) {
    for (var i = 0; i < p.length; i++) {
      for (var j = i + 1; j < p.length; j++) {
        if (p[i].card.overlaps(p[j].card)) return true;
      }
    }
    return false;
  }

  test('one face with room on the right: card goes right', () {
    final p = placeCards(
      faces: [const Rect.fromLTWH(40, 300, 110, 140)],
      heights: [150],
      screen: phone,
      width: 168,
    );
    expect(p.single.side, CardSide.right);
    expect(p.single.card.left, greaterThan(150));
  });

  test('two faces side by side: cards do not overlap', () {
    final p = placeCards(
      faces: [const Rect.fromLTWH(30, 330, 100, 130), const Rect.fromLTWH(210, 360, 80, 100)],
      heights: [140, 140],
      screen: phone,
      width: w,
    );
    expect(overlaps(p), isFalse);
  });

  test('three faces: no overlaps, no card covers a face, all inside the safe area', () {
    final faces = [
      const Rect.fromLTWH(20, 320, 90, 115),
      const Rect.fromLTWH(140, 300, 80, 100),
      const Rect.fromLTWH(250, 340, 75, 95),
    ];
    final p = placeCards(
      faces: faces,
      heights: [130, 130, 130],
      screen: phone,
      width: w,
    );
    expect(overlaps(p), isFalse);
    for (final c in p) {
      expect(c.card.top, greaterThanOrEqualTo(96));
      expect(c.card.bottom, lessThanOrEqualTo(phone.height - 170 + 0.01));
      expect(c.card.left, greaterThanOrEqualTo(0));
      expect(c.card.right, lessThanOrEqualTo(phone.width));
    }
    for (var i = 0; i < p.length; i++) {
      for (var j = 0; j < faces.length; j++) {
        if (i != j) expect(p[i].card.overlaps(faces[j]), isFalse);
      }
    }
  });

  test('leader line starts at the face and ends on the card edge', () {
    final face = const Rect.fromLTWH(40, 300, 110, 140);
    final p = placeCards(faces: [face], heights: [150], screen: phone, width: 168).single;
    expect(p.lineFrom.dx, greaterThan(face.right)); // just outside the face frame
    expect(p.lineTo.dx, p.card.left);
  });
}
