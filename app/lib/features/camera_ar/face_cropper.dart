// face_cropper.dart: cut one face out of a raw camera frame as a small JPEG.
// No UI here.
//
// Why crop on the phone: sending only the face (about 20-40 KB) instead of the
// whole frame keeps the hotspot fast. The crop is sent once, the laptop turns
// it into numbers (an embedding) and throws the picture away (rule 3).
//
// The camera gives NV21 frames: first every pixel's brightness (Y), then the
// colour (V and U) for each 2x2 block. The sensor is mounted sideways, so we
// also rotate while copying, which gives an upright face like ML Kit's box.

import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

/// Everything the background isolate needs (plain data, so it can be copied).
class CropJob {
  final Uint8List nv21; // raw frame bytes
  final int width; // sensor frame size (landscape, e.g. 640 x 480)
  final int height;
  final int bytesPerRow;
  final int rotation; // sensor mounting angle: 0, 90, 180 or 270
  final Rect box; // the face, in upright-image pixels (from ML Kit)

  const CropJob({
    required this.nv21,
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.rotation,
    required this.box,
  });
}

/// Extra space around the face on each side (40% of its size). The laptop
/// finds the face again inside the crop, so it needs a bit of context.
const double cropMargin = 0.4;

/// The longest side of the JPEG we send. Plenty for recognition.
const int maxCropSide = 320;

/// Runs in a background isolate (via compute). Returns JPEG bytes or null if
/// the box is outside the frame.
Uint8List? cropFaceToJpeg(CropJob job) {
  final sideways = job.rotation % 180 != 0;
  final uprightW = sideways ? job.height : job.width;
  final uprightH = sideways ? job.width : job.height;

  // Grow the box by the margin, then keep it inside the frame.
  final b = job.box;
  final crop = Rect.fromLTRB(
    (b.left - b.width * cropMargin).clamp(0, uprightW - 1).toDouble(),
    (b.top - b.height * cropMargin).clamp(0, uprightH - 1).toDouble(),
    (b.right + b.width * cropMargin).clamp(1, uprightW).toDouble(),
    (b.bottom + b.height * cropMargin).clamp(1, uprightH).toDouble(),
  );
  if (crop.width < 2 || crop.height < 2) return null;

  // Shrink big crops; never enlarge small ones.
  final longest = crop.width > crop.height ? crop.width : crop.height;
  final scale = longest > maxCropSide ? maxCropSide / longest : 1.0;
  final outW = (crop.width * scale).round();
  final outH = (crop.height * scale).round();
  final out = img.Image(width: outW, height: outH);

  final uvStart = job.bytesPerRow * job.height; // colour data starts here
  final data = job.nv21;
  for (var oy = 0; oy < outH; oy++) {
    final v = (crop.top + oy / scale).floor(); // upright row
    for (var ox = 0; ox < outW; ox++) {
      final u = (crop.left + ox / scale).floor(); // upright column

      // Upright (u, v) -> sensor (x, y), undoing the sideways mounting.
      int x, y;
      switch (job.rotation) {
        case 90:
          x = v;
          y = job.height - 1 - u;
        case 180:
          x = job.width - 1 - u;
          y = job.height - 1 - v;
        case 270:
          x = job.width - 1 - v;
          y = u;
        default:
          x = u;
          y = v;
      }

      // NV21 -> RGB (standard BT.601 formula).
      final yy = data[y * job.bytesPerRow + x];
      final uvIndex = uvStart + (y >> 1) * job.bytesPerRow + (x & ~1);
      final vv = data[uvIndex] - 128;
      final uu = data[uvIndex + 1] - 128;
      out.setPixelRgb(
        ox,
        oy,
        (yy + 1.402 * vv).round().clamp(0, 255),
        (yy - 0.344 * uu - 0.714 * vv).round().clamp(0, 255),
        (yy + 1.772 * uu).round().clamp(0, 255),
      );
    }
  }
  return img.encodeJpg(out, quality: 85);
}
