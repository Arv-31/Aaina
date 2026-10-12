// server_face_detector.dart: face boxes from the laptop backend. No UI here.
//
// Used when the camera screen runs in a browser on the laptop (laptop webcam).
// ML Kit only runs on phones, so here the browser sends a camera frame to
// POST /detect and gets the face boxes back. Nothing is stored on the server:
// the frame is discarded right after the boxes are found.

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:http/http.dart' as http;

import '../../core/config.dart';
import 'face_detector_service.dart' show DetectedFace, FaceFrame;

class ServerFaceDetector {
  final _client = http.Client();

  /// Sends one JPEG frame and returns the faces found in it.
  /// Throws if the server is off or answers with an error.
  Future<FaceFrame> detect(Uint8List jpeg) async {
    final watch = Stopwatch()..start();
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('${AppConfig.laptopServerUrl}/detect'),
          )
          ..files.add(
            http.MultipartFile.fromBytes('photo', jpeg, filename: 'frame.jpg'),
          );
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 5)),
    );
    watch.stop();
    if (response.statusCode != 200) {
      throw Exception(
        'Server answered ${response.statusCode}: ${response.body}',
      );
    }

    // Answer looks like: {"image_size": [640, 480], "boxes": [[x1, y1, x2, y2], ...]}
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final size = data['image_size'] as List;
    final boxes = data['boxes'] as List;
    return FaceFrame(
      [
        for (final b in boxes)
          DetectedFace(
            box: Rect.fromLTRB(
              (b[0] as num).toDouble(),
              (b[1] as num).toDouble(),
              (b[2] as num).toDouble(),
              (b[3] as num).toDouble(),
            ),
          ),
      ],
      Size((size[0] as num).toDouble(), (size[1] as num).toDouble()),
      watch.elapsedMilliseconds,
      source: 'Laptop',
    );
  }

  void dispose() => _client.close();
}
