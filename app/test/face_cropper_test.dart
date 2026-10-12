// Checks that the face cropper turns the sideways camera frame upright the
// same way ML Kit does. If this is wrong, the laptop gets a rotated face and
// never recognises anyone.

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:aaina/features/camera_ar/face_cropper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A tiny 4x2 grey NV21 frame where every pixel's brightness = 10 * index.
Uint8List frame() {
  const w = 4, h = 2;
  final data = Uint8List(w * h + w * h ~/ 2);
  for (var i = 0; i < w * h; i++) {
    data[i] = 10 * (i + 1);
  }
  data.fillRange(w * h, data.length, 128); // no colour = grey
  return data;
}

/// Brightness of sensor pixel (x, y) in frame().
int sensor(int x, int y) => 10 * (y * 4 + x + 1);

int grey(Uint8List jpeg, int x, int y) =>
    img.decodeJpg(jpeg)!.getPixel(x, y).r.toInt();

CropJob job(int rotation, Rect box) => CropJob(
  nv21: frame(),
  width: 4,
  height: 2,
  bytesPerRow: 4,
  rotation: rotation,
  box: box,
);

void main() {
  test('90 degree sensor: upright image is 2 wide, 4 tall', () {
    final jpeg = cropFaceToJpeg(job(90, const Rect.fromLTWH(0, 0, 2, 4)))!;
    final out = img.decodeJpg(jpeg)!;
    expect([out.width, out.height], [2, 4]);
    // Rotating 90 deg clockwise puts sensor (0, 1) at the upright top-left
    // and sensor (3, 0) at the bottom-right. JPEG is lossy, so allow +-12.
    expect(grey(jpeg, 0, 0), closeTo(sensor(0, 1), 12));
    expect(grey(jpeg, 1, 3), closeTo(sensor(3, 0), 12));
  });

  test('270 degree sensor (front camera) rotates the other way', () {
    final jpeg = cropFaceToJpeg(job(270, const Rect.fromLTWH(0, 0, 2, 4)))!;
    expect(grey(jpeg, 0, 0), closeTo(sensor(3, 0), 12));
    expect(grey(jpeg, 1, 3), closeTo(sensor(0, 1), 12));
  });

  test('box outside the frame gives no crop', () {
    expect(cropFaceToJpeg(job(90, const Rect.fromLTWH(50, 50, 2, 2))), isNull);
  });
}
