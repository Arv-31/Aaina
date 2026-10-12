// face_detector_service.dart: camera frames in, face boxes out. No UI here.
//
// Uses Google ML Kit face detection, which runs fully on the phone (free,
// offline). It gives each face a box and a "tracking ID" that stays the same
// while the face is in view. Milestone 5 will use that ID to ask the laptop
// "who is this?" only once per face instead of every frame.

import 'dart:ui' show Rect, Size;

import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// One face found in one camera frame.
class DetectedFace {
  /// Box in "upright image" pixels (already rotated to portrait).
  final Rect box;

  /// Stays the same for the same person while they stay in view (can be null).
  final int? trackingId;

  /// Head turn left/right in degrees (used later for the enrollment head-turn check).
  final double? headTurn;

  const DetectedFace({required this.box, this.trackingId, this.headTurn});
}

/// Result of one processed frame.
class FaceFrame {
  final List<DetectedFace> faces;

  /// Size of the upright image the boxes refer to (width < height in portrait).
  final Size imageSize;

  /// How long finding the faces took, in milliseconds.
  final int detectMs;

  /// Who found the faces: "ML Kit" (phone) or "Laptop" (browser on the laptop).
  final String source;

  const FaceFrame(
    this.faces,
    this.imageSize,
    this.detectMs, {
    this.source = 'ML Kit',
  });
}

class FaceDetectorService {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast, // speed over tiny details
      enableTracking: true, // gives us trackingId
      minFaceSize: 0.1, // ignore faces smaller than 10% of the image width
    ),
  );

  bool _busy = false; // true while ML Kit is working on a frame

  /// Runs detection on one camera frame.
  ///
  /// Returns null if the previous frame is still being processed. Dropping
  /// frames like this keeps the preview smooth on slower phones.
  Future<FaceFrame?> process(
    CameraImage image,
    CameraDescription camera,
  ) async {
    if (_busy) return null;
    _busy = true;
    try {
      final input = _toInputImage(image, camera);
      if (input == null) return null;

      final watch = Stopwatch()..start();
      final faces = await _detector.processImage(input);
      watch.stop();

      // The camera sensor is mounted sideways on most phones (90 or 270
      // degrees). ML Kit returns boxes for the upright picture, so width and
      // height swap in that case.
      final sideways = camera.sensorOrientation % 180 != 0;
      final upright = sideways
          ? Size(image.height.toDouble(), image.width.toDouble())
          : Size(image.width.toDouble(), image.height.toDouble());

      return FaceFrame(
        [
          for (final f in faces)
            DetectedFace(
              box: f.boundingBox,
              trackingId: f.trackingId,
              headTurn: f.headEulerAngleY,
            ),
        ],
        upright,
        watch.elapsedMilliseconds,
      );
    } catch (_) {
      return null; // a bad frame is not worth crashing for; the next one comes soon
    } finally {
      _busy = false;
    }
  }

  /// Wraps the raw camera bytes in the format ML Kit expects.
  InputImage? _toInputImage(CameraImage image, CameraDescription camera) {
    // The app is locked to portrait, so the needed rotation is simply the
    // angle the sensor is mounted at.
    final rotation = InputImageRotationValue.fromRawValue(
      camera.sensorOrientation,
    );
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    // We ask the camera for NV21 frames, which arrive as a single plane.
    if (rotation == null ||
        format != InputImageFormat.nv21 ||
        image.planes.length != 1) {
      return null;
    }
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  Future<void> dispose() => _detector.close();
}

/// Converts a box from upright-image pixels to screen pixels.
///
/// The preview fills the screen like BoxFit.cover (scaled up, edges cut off),
/// so boxes get the same scale and offset. The front camera preview is shown
/// mirrored, so its boxes are mirrored too.
Rect imageRectToScreen(
  Rect r,
  Size image,
  Size screen, {
  required bool mirror,
}) {
  final scale = (screen.width / image.width) > (screen.height / image.height)
      ? screen.width / image.width
      : screen.height / image.height;
  final dx = (screen.width - image.width * scale) / 2;
  final dy = (screen.height - image.height * scale) / 2;

  final left = mirror ? image.width - r.right : r.left;
  return Rect.fromLTWH(
    left * scale + dx,
    r.top * scale + dy,
    r.width * scale,
    r.height * scale,
  );
}
