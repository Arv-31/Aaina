// qr_scanner_service.dart: camera frames in, QR code text out. No UI here.
//
// QR fallback (extra A). Uses Google ML Kit barcode scanning, which runs on
// the phone (free, offline). It reads the SAME camera frames as face
// detection, so QR mode needs no second camera or app: the camera screen just
// sends frames here instead of to the face detector.

import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';

class QrScannerService {
  final BarcodeScanner _scanner = BarcodeScanner(formats: [BarcodeFormat.qrCode]);
  bool _busy = false;

  /// Returns the text of the first QR code in the frame, or null.
  /// Frames that arrive while the previous one is still being read are skipped.
  Future<String?> process(CameraImage image, CameraDescription camera) async {
    if (_busy) return null;
    _busy = true;
    try {
      final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
      if (rotation == null || image.planes.length != 1) return null;
      final plane = image.planes.first;
      final input = InputImage.fromBytes(
        bytes: plane.bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21, // the camera is set to NV21
          bytesPerRow: plane.bytesPerRow,
        ),
      );
      final codes = await _scanner.processImage(input);
      for (final c in codes) {
        final text = c.rawValue?.trim();
        if (text != null && text.isNotEmpty) return text;
      }
      return null;
    } catch (_) {
      return null; // a bad frame; the next one comes soon
    } finally {
      _busy = false;
    }
  }

  /// True for codes made by Aaina ("aaina:" + a random token).
  static bool isAainaCode(String text) =>
      text.startsWith('aaina:') && text.length > 'aaina:'.length;

  Future<void> dispose() => _scanner.close();
}
