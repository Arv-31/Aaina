// recognition_service.dart: "who is this face?" with a memory. No UI here.
//
// ML Kit gives every face a tracking ID that stays the same while the face is
// in view. We ask the laptop about each ID once, remember the answer, and only
// ask again now and then (in case the first answer was wrong). This keeps the
// hotspot quiet and the screen fast, even with several faces.
//
// Only one question is in flight at a time, which suits slower phones.

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../../core/api_client.dart';
import 'face_cropper.dart';
import 'face_detector_service.dart';

enum IdentityStatus { checking, known, unknown, tooFar }

/// What we currently believe about one tracked face.
class FaceIdentity {
  final IdentityStatus status;
  final Map<String, dynamic>? card; // the profile card when known
  final double? score;
  final DateTime checkedAt;
  final int misses; // answers in a row that did not confirm the current result

  FaceIdentity(
    this.status, {
    this.card,
    this.score,
    DateTime? checkedAt,
    this.misses = 0,
  }) : checkedAt = checkedAt ?? DateTime.now();

  String? get name => card?['name'] as String?;
}

/// How long to trust each kind of answer before asking again.
const _recheckKnown = Duration(seconds: 20);
const _recheckUnknown = Duration(seconds: 4);
const _retryChecking = Duration(milliseconds: 800);
const _forgetAfter = Duration(seconds: 3); // face gone this long = forget it

class RecognitionService extends ChangeNotifier {
  AainaApi? _api; // null = not signed in, so nothing is sent
  final Map<int, FaceIdentity> _ids = {};
  final Map<int, DateTime> _lastSeen = {};
  bool _inFlight = false;

  /// True when the last request could not reach the laptop.
  bool serverDown = false;

  /// True when the server said our login is no longer valid.
  bool signedOut = false;

  set api(AainaApi? value) {
    _api = value;
    _ids.clear();
    signedOut = false;
    serverDown = false;
    notifyListeners();
  }

  bool get active => _api != null;

  FaceIdentity? identityOf(int? trackingId) =>
      trackingId == null ? null : _ids[trackingId];

  /// Call for every processed phone frame (after ML Kit).
  void onFrame(CameraImage image, CameraDescription camera, FaceFrame frame) {
    final now = DateTime.now();
    for (final f in frame.faces) {
      if (f.trackingId != null) _lastSeen[f.trackingId!] = now;
    }
    // Forget faces that left the picture.
    _lastSeen.removeWhere((id, seen) {
      final gone = now.difference(seen) > _forgetAfter;
      if (gone) _ids.remove(id);
      return gone;
    });

    if (_api == null || _inFlight) return;

    // Pick the biggest face that needs a (new) answer: big = closest person.
    DetectedFace? next;
    for (final f in frame.faces) {
      if (f.trackingId == null || !_due(_ids[f.trackingId!], now)) continue;
      if (next == null || f.box.width > next.box.width) next = f;
    }
    if (next == null) return;

    // Copy the bytes now: the camera reuses this buffer for the next frame.
    final plane = image.planes.first;
    final job = CropJob(
      nv21: Uint8List.fromList(plane.bytes),
      width: image.width,
      height: image.height,
      bytesPerRow: plane.bytesPerRow,
      rotation: camera.sensorOrientation,
      box: next.box,
    );
    final id = next.trackingId!;
    _ids.putIfAbsent(id, () => FaceIdentity(IdentityStatus.checking));
    _check(id, job);
  }

  bool _due(FaceIdentity? cur, DateTime now) {
    if (cur == null) return true;
    final age = now.difference(cur.checkedAt);
    return switch (cur.status) {
      IdentityStatus.known => age > _recheckKnown,
      IdentityStatus.checking => age > _retryChecking,
      _ => age > _recheckUnknown,
    };
  }

  Future<void> _check(int id, CropJob job) async {
    _inFlight = true;
    try {
      final jpeg = await compute(cropFaceToJpeg, job);
      if (jpeg == null) return;
      final result = await _api!.recognize(jpeg);
      serverDown = false;
      _apply(id, result);
    } on NotSignedIn {
      signedOut = true;
      _api = null;
      _ids.clear();
    } on ServerUnreachable {
      serverDown = true;
      _ids[id] = FaceIdentity(IdentityStatus.checking); // try again soon
    } catch (_) {
      _ids[id] = FaceIdentity(IdentityStatus.checking);
    } finally {
      _inFlight = false;
      notifyListeners();
    }
  }

  /// Turns the server's answer for one crop into a FaceIdentity.
  void _apply(int id, RecognizeResult result) {
    final cur = _ids[id];
    if (cur == null) return; // the face left while we were asking

    // The crop is centred on our face, so the biggest face found is ours.
    RecognizedFace? face;
    for (final f in result.faces) {
      if (face == null || f.box.width > face.box.width) face = f;
    }

    if (face == null) {
      // Laptop saw no face (blur, turned head). Retry a few times, then give up.
      _ids[id] = cur.misses >= 2
          ? FaceIdentity(IdentityStatus.unknown)
          : FaceIdentity(cur.status,
              card: cur.card, score: cur.score, misses: cur.misses + 1,
              checkedAt: DateTime.now().subtract(_recheckKnown));
      return;
    }
    if (face.status == 'too_small') {
      _ids[id] = FaceIdentity(IdentityStatus.tooFar);
    } else if (face.isMatch) {
      _ids[id] = FaceIdentity(IdentityStatus.known,
          card: face.card, score: face.score);
    } else if (cur.status == IdentityStatus.known && cur.misses < 1) {
      // A known person got one "unknown" (bad angle). Keep the name, ask again soon.
      _ids[id] = FaceIdentity(IdentityStatus.known,
          card: cur.card, score: cur.score, misses: cur.misses + 1,
          checkedAt: DateTime.now().subtract(_recheckKnown - _recheckUnknown));
    } else {
      _ids[id] = FaceIdentity(IdentityStatus.unknown);
    }
  }

  /// Web (laptop webcam): the whole frame was recognised in one go, so faces
  /// are numbered by position in that answer instead of tracking IDs.
  void setWebResults(List<RecognizedFace> faces) {
    _ids
      ..clear()
      ..addAll({
        for (var i = 0; i < faces.length; i++)
          i: switch (faces[i].status) {
            'match' => FaceIdentity(IdentityStatus.known,
                card: faces[i].card, score: faces[i].score),
            'too_small' => FaceIdentity(IdentityStatus.tooFar),
            _ => FaceIdentity(IdentityStatus.unknown),
          },
      });
    serverDown = false;
    notifyListeners();
  }

  void markServerDown() {
    serverDown = true;
    notifyListeners();
  }

  void markSignedOut() {
    signedOut = true;
    _api = null;
    _ids.clear();
    notifyListeners();
  }
}
