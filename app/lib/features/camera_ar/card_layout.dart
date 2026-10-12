// card_layout.dart: where each face's card goes on the screen. No UI here.
//
// Rules, in order:
//   1. Closest person (biggest face) chooses first.
//   2. Try beside the face (right, then left), then above, then below.
//   3. A spot is only taken if it doesn't overlap a card already placed and
//      doesn't cover someone else's face.
//   4. If none of those is free (crowded screen), search the whole safe area
//      for the free spot nearest the face. As a last resort, slide the card
//      up or down until it at least doesn't cover another card.
// Cards stay inside the "safe" area between the top bar and the bottom dock.

import 'dart:ui' show Offset, Rect, Size;

enum CardSide { right, left, above, below }

/// Where one card goes, and where its leader line starts (face) and ends (card).
class CardPlacement {
  final Rect card;
  final CardSide side;
  final Offset lineFrom;
  final Offset lineTo;
  const CardPlacement(this.card, this.side, this.lineFrom, this.lineTo);
}

/// Places one card per face. [faces] and [heights] have the same order;
/// the result does too.
List<CardPlacement> placeCards({
  required List<Rect> faces,
  required List<double> heights,
  required Size screen,
  required double width,
  double facePad = 16, // the lock-on frame is drawn this far outside the face
  double topLimit = 96, // below the top bar
  double bottomLimit = 170, // above the "in view" strip and dock
  double gap = 18, // face frame -> card (room for the leader line's bend)
  double margin = 8, // screen edge -> card
}) {
  final result = List<CardPlacement?>.filled(faces.length, null);
  final placed = <Rect>[];

  // 1. Biggest face first.
  final order = List.generate(faces.length, (i) => i)
    ..sort((a, b) => faces[b].width.compareTo(faces[a].width));

  for (final i in order) {
    final face = faces[i];
    final h = heights[i];
    final others = [
      for (var j = 0; j < faces.length; j++)
        if (j != i) faces[j].inflate(facePad * 0.5),
    ];
    final minTop = topLimit;
    final maxTop = (screen.height - bottomLimit - h).clamp(minTop, double.infinity);

    double clampTop(double t) => t.clamp(minTop, maxTop);
    double clampLeft(double l) =>
        l.clamp(margin, (screen.width - width - margin).clamp(margin, double.infinity));

    // 2. Candidate spots.
    final besideTop = clampTop(face.top - h * 0.3);
    final candidates = <(Rect, CardSide)>[
      if (face.right + facePad + gap + width <= screen.width - margin)
        (Rect.fromLTWH(face.right + facePad + gap, besideTop, width, h), CardSide.right),
      if (face.left - facePad - gap - width >= margin)
        (Rect.fromLTWH(face.left - facePad - gap - width, besideTop, width, h), CardSide.left),
      if (face.top - facePad - 14 - h >= minTop)
        (Rect.fromLTWH(clampLeft(face.center.dx - width / 2), face.top - facePad - 14 - h, width, h),
            CardSide.above),
      if (face.bottom + facePad + 14 + h <= screen.height - bottomLimit)
        (Rect.fromLTWH(clampLeft(face.center.dx - width / 2), face.bottom + facePad + 14, width, h),
            CardSide.below),
    ];
    // Nothing fits cleanly (face fills the screen): centred above, squeezed in.
    if (candidates.isEmpty) {
      candidates.add((
        Rect.fromLTWH(clampLeft(face.center.dx - width / 2), clampTop(face.top - facePad - 14 - h), width, h),
        CardSide.above,
      ));
    }

    bool free(Rect r) =>
        !placed.any((p) => p.inflate(6).overlaps(r)) && !others.any((f) => f.overlaps(r));

    // 3. First free candidate.
    (Rect, CardSide)? pick;
    for (final c in candidates) {
      if (free(c.$1)) {
        pick = c;
        break;
      }
    }

    // 4a. Crowded: nearest free spot anywhere in the safe area (12 px grid).
    if (pick == null) {
      final target = face.center;
      var best = double.infinity;
      for (var t = minTop; t <= maxTop; t += 12) {
        for (var l = margin; l + width <= screen.width - margin; l += 12) {
          final r = Rect.fromLTWH(l, t, width, h);
          if (r.overlaps(face.inflate(facePad)) || !free(r)) continue;
          final d = (r.center - target).distanceSquared;
          if (d < best) {
            best = d;
            pick = (r, _sideOf(r, face));
          }
        }
      }
    }

    // 4b. No free spot at all: slide until it doesn't cover another card.
    if (pick == null) {
      final base = candidates.first;
      for (var step = 1; step <= 30 && pick == null; step++) {
        for (final dir in [1, -1]) {
          final t = base.$1.top + dir * step * 12;
          if (t < minTop || t > maxTop) continue;
          final r = Rect.fromLTWH(base.$1.left, t, width, h);
          if (!placed.any((p) => p.inflate(6).overlaps(r))) {
            pick = (r, base.$2);
            break;
          }
        }
      }
      pick ??= base;
    }

    placed.add(pick.$1);
    result[i] = _withLine(pick.$1, pick.$2, face, facePad);
  }
  return result.cast<CardPlacement>();
}

/// Which side of the face a freely placed card ended up on.
CardSide _sideOf(Rect card, Rect face) {
  if (card.left >= face.right) return CardSide.right;
  if (card.right <= face.left) return CardSide.left;
  return card.center.dy < face.center.dy ? CardSide.above : CardSide.below;
}

/// Leader line: from the edge of the face frame to the nearest edge of the card.
CardPlacement _withLine(Rect card, CardSide side, Rect face, double pad) {
  double alongCard(double x) => x.clamp(card.left + 14, card.right - 14);
  double alongCardY(double y) => y.clamp(card.top + 16, card.bottom - 16);
  switch (side) {
    case CardSide.right:
      return CardPlacement(card, side, Offset(face.right + pad - 4, face.center.dy),
          Offset(card.left, alongCardY(face.center.dy)));
    case CardSide.left:
      return CardPlacement(card, side, Offset(face.left - pad + 4, face.center.dy),
          Offset(card.right, alongCardY(face.center.dy)));
    case CardSide.above:
      return CardPlacement(card, side, Offset(face.center.dx, face.top - pad + 4),
          Offset(alongCard(face.center.dx), card.bottom));
    case CardSide.below:
      return CardPlacement(card, side, Offset(face.center.dx, face.bottom + pad - 4),
          Offset(alongCard(face.center.dx), card.top));
  }
}
