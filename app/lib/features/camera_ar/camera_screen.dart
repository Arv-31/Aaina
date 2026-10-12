// camera_screen.dart: the main "AR" screen. Live camera, lock-on frames on
// faces, and a glass card beside everyone the laptop recognises.
//
// Works in two places:
//   - Android phone: ML Kit finds faces on the phone, every camera frame.
//     Each NEW face is cropped and sent once to the laptop: "who is this?"
//     (recognition_service.dart remembers the answers).
//   - Browser on the stall laptop (its webcam): the browser sends a frame
//     about every half second to the backend, which finds AND recognises
//     faces in one go. Wide screens get a side panel ("In view" + sign-up).
//
// Milestone 5: names, status and LinkedIn on the camera.
// Milestone 6: cards never overlap (card_layout.dart), tap a card for the full
// profile + Save contact, QR mode (same camera, ML Kit barcodes), "Show my
// code", and mirror mode (front camera recognises you: "this is you").

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/session_store.dart';
import '../../core/theme.dart';
import '../../widgets/aaina_logo.dart';
import '../../widgets/ar_card.dart';
import '../../widgets/face_box.dart';
import '../../widgets/hud.dart';
import '../../widgets/hud_pill.dart';
import '../../widgets/my_code_sheet.dart';
import '../../widgets/profile_sheet.dart';
import '../../widgets/scan_overlays.dart';
import 'card_layout.dart';
import 'card_view.dart';
import 'connect_sheet.dart';
import 'contact_saver.dart';
import 'face_detector_service.dart';
import 'qr_scanner_service.dart';
import 'recognition_service.dart';
import 'server_face_detector.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

// WidgetsBindingObserver lets us release the camera when the app goes to the
// background and take it back when the user returns.
class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  final _faceService = FaceDetectorService(); // phone (ML Kit)
  final _serverDetector = ServerFaceDetector(); // browser, not signed in
  final _recog = RecognitionService(); // "who is this?" + memory
  final _qr = QrScannerService(); // QR mode (phone only)

  Session? _session; // server address + login token
  AainaApi? _api; // null = not signed in

  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  bool _useFront = false; // back camera by default: you point it at others
  FaceFrame? _lastFrame; // the latest detection result
  String? _error; // shown instead of the camera if something went wrong
  bool _detectDown = false; // web, signed out: the backend did not answer

  Map<String, dynamic>? _me; // my own profile (for mirror mode + my code)
  bool _qrMode = false; // true = frames go to the QR reader instead of faces
  bool _qrBusy = false; // a found code is being looked up
  String? _lastQr; // ignore the same code for a moment after reading it
  DateTime _lastQrAt = DateTime(2000);
  bool _sheetOpen = false; // pause QR reading while a card sheet is open
  final Set<String> _knownInView = {}; // for a small buzz when someone new is recognised

  // Camera health.
  Timer? _watchdog; // restarts the camera if frames stop coming
  DateTime _lastImageAt = DateTime.now();
  int _watchdogRestarts = 0;
  bool _permissionBlocked = false; // "Don't ask again" was chosen: only Settings helps
  String? _cameraLog; // technical error text, shown small on the error screen

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recog.addListener(_onRecognition);
    _loadSession();
    _queue(_startCamera);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recog.removeListener(_onRecognition);
    _queue(_stopCamera);
    _faceService.dispose();
    _serverDetector.dispose();
    _qr.dispose();
    _api?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // In a browser "inactive" just means another window has focus, so keep
    // the webcam running there.
    if (kIsWeb) return;
    // Only "paused" (really in the background) releases the camera. "inactive"
    // also fires while the app is opening or the permission pop-up is shown;
    // stopping then broke the camera on first open.
    if (state == AppLifecycleState.paused) {
      _queue(_stopCamera);
    } else if (state == AppLifecycleState.resumed) {
      _queue(() async {
        if (_controller == null) await _startCamera();
      });
    }
  }

  // ---------------------------------------------------------------- session

  Future<void> _loadSession() async => _useSession(await SessionStore.load());

  void _useSession(Session s) {
    _api?.close();
    _api = s.signedIn ? AainaApi(s.serverUrl, token: s.token) : null;
    _recog.api = _api;
    _me = null;
    if (mounted) setState(() => _session = s);
    _loadMe();
  }

  /// Fetches my own profile in the background (mirror mode, my code).
  Future<void> _loadMe() async {
    final api = _api;
    if (api == null) return;
    try {
      final me = await api.me();
      if (mounted && _api == api) setState(() => _me = me);
    } catch (_) {
      // Not important enough to show an error; mirror mode just stays off.
    }
  }

  void _onRecognition() {
    // A small buzz when a new person is recognised.
    final now = <String>{
      for (final (_, id) in _people)
        if (id?.status == IdentityStatus.known) '${id!.card?['user_id']}',
    };
    if (now.difference(_knownInView).isNotEmpty && !kIsWeb) {
      HapticFeedback.lightImpact();
    }
    _knownInView
      ..clear()
      ..addAll(now);

    // The server no longer accepts our token (expired or signed out elsewhere).
    if (_recog.signedOut && _session?.signedIn == true) {
      final s = Session(serverUrl: _session!.serverUrl);
      SessionStore.save(s);
      _useSession(s);
      _toast('Signed out. Connect again to see names.');
    }
    if (mounted) setState(() {});
  }

  Future<void> _openConnect() async {
    final current = _session ?? Session(serverUrl: SessionStore.defaultServer);
    final s = await showConnectSheet(context, current);
    if (s != null) _useSession(s);
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, style: AppText.body),
          backgroundColor: AppColors.surface2,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      );
  }

  Future<void> _openLink(Uri? uri) async {
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) _toast("Couldn't open that link.");
  }

  /// Is this card the signed-in person? (mirror mode)
  bool _isMe(Map<String, dynamic>? card) =>
      card != null && _me != null && card['user_id'] == _me!['user_id'];

  /// Opens the expanded card (tap on a card, or a scanned QR code).
  Future<void> _openProfile(Map<String, dynamic> card, {required String source}) async {
    final isYou = _isMe(card);
    _sheetOpen = true;
    await showProfileSheet(
      context,
      data: cardToProfile(card),
      source: isYou ? 'This is you' : source,
      isYou: isYou,
      onOpenLink: _openLink,
      onSaveContact: (kIsWeb || isYou) ? null : () => _saveContact(card),
    );
    _sheetOpen = false;
  }

  Future<void> _saveContact(Map<String, dynamic> card) async {
    try {
      if (await saveContact(card) && mounted) _toast('Saved to your contacts.');
    } catch (_) {
      if (mounted) _toast("Couldn't open your contacts app.");
    }
  }

  // ------------------------------------------------------------- QR mode

  void _setQrMode(bool on) {
    if (on && kIsWeb) {
      _toast('QR scanning works in the Android app.');
      return;
    }
    setState(() {
      _qrMode = on;
      _lastFrame = null; // hide old face frames
    });
  }

  /// A QR code was read from the camera.
  Future<void> _onQr(String text) async {
    if (_sheetOpen || _qrBusy || !mounted) return;
    final now = DateTime.now();
    if (text == _lastQr && now.difference(_lastQrAt) < const Duration(seconds: 3)) return;
    _lastQr = text;
    _lastQrAt = now;

    if (!QrScannerService.isAainaCode(text)) {
      _toast("That QR code isn't an Aaina code.");
      return;
    }
    final api = _api;
    if (api == null) {
      _toast('Connect to Aaina first to open cards.');
      return;
    }
    setState(() => _qrBusy = true);
    HapticFeedback.mediumImpact();
    try {
      final card = await api.qrLookup(text);
      if (mounted) {
        setState(() => _qrBusy = false);
        await _openProfile(card, source: 'From their Aaina code');
        _lastQrAt = DateTime.now(); // don't reopen right after closing
      }
    } on ServerMessage {
      _toast('This code no longer works. Ask them to show it again.');
    } on NotSignedIn {
      _recog.markSignedOut();
    } on ServerUnreachable {
      _recog.markServerDown();
    } finally {
      if (mounted && _qrBusy) setState(() => _qrBusy = false);
    }
  }

  void _openMyCode() {
    final api = _api;
    if (api == null) {
      _openConnect();
      return;
    }
    _sheetOpen = true;
    showMyCodeSheet(
      context,
      name: (_me?['name'] as String?) ?? (_session?.username ?? ''),
      loadCode: () async {
        try {
          final me = await api.me();
          if (mounted) setState(() => _me = me);
          return me['qr_value'] as String?;
        } catch (_) {
          return null;
        }
      },
      newCode: () async {
        try {
          return await api.newQr();
        } catch (_) {
          return null;
        }
      },
    ).whenComplete(() => _sheetOpen = false);
  }

  // ----------------------------------------------------------------- camera

  CameraDescription? get _currentCamera {
    final wanted = _useFront
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    for (final c in _cameras) {
      if (c.lensDirection == wanted) return c;
    }
    return _cameras.isEmpty ? null : _cameras.first;
  }

  // Start, stop and flip must never overlap: stopping a camera that is still
  // starting leaves it broken. Each job waits for the one before it.
  Future<void> _cameraJob = Future.value();
  void _queue(Future<void> Function() job) {
    _cameraJob = _cameraJob.then((_) => job()).catchError((Object _) {});
  }

  /// Starts the camera, trying a few times before showing an error.
  ///
  /// Why retries: right after the app opens, Android may still be releasing
  /// the camera from the last time (or the permission pop-up has only just
  /// closed). The first try can fail even though a second later everything
  /// works, which is why "switch camera" used to fix it. A new visitor should
  /// never see that, so we quietly wait a little longer each time.
  Future<void> _startCamera() async {
    if (!mounted) return;
    setState(() => _error = null);

    // Phone: ask for the camera permission FIRST, with nothing else running.
    // (Letting the camera plugin ask in the middle of starting the camera is
    // what broke the very first start on some phones.)
    if (!kIsWeb) {
      final status = await Permission.camera.request();
      if (!mounted) return;
      if (!status.isGranted) {
        setState(() {
          _permissionBlocked = status.isPermanentlyDenied;
          _error = 'Aaina needs the camera to see who you are meeting. '
              'Nothing is recorded, and unknown faces are never stored.';
        });
        return;
      }
    }

    const waits = [0, 400, 900, 1600, 2500]; // ms before each try
    Object? lastError;
    for (final wait in waits) {
      if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
      if (!mounted) return;
      try {
        await _openCamera();
        _cameraLog = null;
        return; // working
      } catch (e) {
        lastError = e;
        await _releaseController();
        if (e is CameraException && _isPermissionError(e)) break; // retrying won't help
        _cameras = []; // look the cameras up again next try
      }
    }
    if (!mounted) return;
    _cameraLog = '$lastError';
    setState(() => _error = lastError is CameraException
        ? _cameraProblem(lastError)
        : "The camera didn't start.");
  }

  /// One attempt: find the camera, open it, start the frame stream.
  Future<void> _openCamera() async {
    if (_cameras.isEmpty) _cameras = await availableCameras();
    final camera = _currentCamera;
    if (camera == null) throw CameraException('none', 'No camera found on this device.');

    final controller = CameraController(
      camera,
      // "medium" (about 640x480) is plenty for finding faces and keeps
      // ML Kit fast. Preview and frames share the same 4:3 shape.
      ResolutionPreset.medium,
      enableAudio: false, // we never use the microphone
      imageFormatGroup: ImageFormatGroup.nv21, // the format ML Kit wants on Android
    );
    _controller = controller;
    await controller.initialize();

    if (kIsWeb) {
      // Browsers can't stream raw frames, so take small pictures in a loop.
      unawaited(_laptopLoop(controller));
    } else {
      // Every camera frame goes to ML Kit (busy frames are skipped inside),
      // then new faces go to the laptop.
      _lastImageAt = DateTime.now();
      await controller.startImageStream((image) async {
        _lastImageAt = DateTime.now(); // the watchdog checks this
        if (_qrMode) {
          // QR mode: the same frames go to the QR reader instead.
          if (_sheetOpen || _qrBusy) return;
          final code = await _qr.process(image, camera);
          if (code != null && mounted) _onQr(code);
          return;
        }
        final frame = await _faceService.process(image, camera);
        if (_qrMode) return; // switched while ML Kit was working
        if (frame == null || !mounted) return;
        setState(() => _lastFrame = frame);
        _recog.onFrame(image, camera, frame);
      });
      _startWatchdog(controller);
    }
    if (mounted) setState(() {});
  }

  /// Safety net: if the camera "started" but no frames arrive (black
  /// preview), restart it by itself, at most twice in a row.
  void _startWatchdog(CameraController c) {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _controller != c) {
        t.cancel();
        return;
      }
      final silent = DateTime.now().difference(_lastImageAt) > const Duration(seconds: 3);
      if (!silent) {
        _watchdogRestarts = 0;
        return;
      }
      t.cancel();
      if (_watchdogRestarts >= 2) return;
      _watchdogRestarts++;
      _queue(() async {
        await _stopCamera();
        await _startCamera();
      });
    });
  }

  /// Frees a camera that failed half-way.
  Future<void> _releaseController() async {
    final failed = _controller;
    _controller = null;
    try {
      await failed?.dispose();
    } catch (_) {}
  }

  bool _isPermissionError(CameraException e) {
    final what = '${e.code} ${e.description}'.toLowerCase();
    return what.contains('denied') || what.contains('notallowed') || what.contains('permission');
  }

  /// Turns camera errors into plain words.
  String _cameraProblem(CameraException e) {
    final what = '${e.code} ${e.description}'.toLowerCase();
    if (what.contains('denied') || what.contains('notallowed')) {
      return kIsWeb
          ? 'Camera permission is off. Click the camera icon in the address bar and allow it.'
          : 'Camera permission is off. Allow it in Settings > Apps > Aaina.';
    }
    if (what.contains('notreadable') || what.contains('in use') || what.contains('busy')) {
      return 'The camera is busy. Close other apps or browser tabs using it, then try again.';
    }
    return 'Camera problem: ${e.description ?? e.code}';
  }

  /// Web only: picture -> laptop -> boxes (+ names when signed in), in a
  /// loop until this camera is stopped.
  Future<void> _laptopLoop(CameraController c) async {
    while (_controller == c && mounted) {
      final started = DateTime.now();
      try {
        final jpeg = await (await c.takePicture()).readAsBytes();
        final api = _api;
        if (api != null) {
          final watch = Stopwatch()..start();
          final result = await api.recognize(jpeg);
          watch.stop();
          if (_controller != c || !mounted) break;
          // Faces are numbered by their position in this answer.
          _lastFrame = FaceFrame(
            [
              for (var i = 0; i < result.faces.length; i++)
                DetectedFace(box: result.faces[i].box, trackingId: i),
            ],
            result.imageSize,
            watch.elapsedMilliseconds,
            source: 'Laptop',
          );
          _recog.setWebResults(result.faces);
        } else {
          final frame = await _serverDetector.detect(jpeg);
          if (_controller != c || !mounted) break;
          setState(() {
            _lastFrame = frame;
            _detectDown = false;
          });
        }
      } on NotSignedIn {
        _recog.markSignedOut();
      } on ServerUnreachable {
        _recog.markServerDown();
        await Future.delayed(const Duration(seconds: 1));
      } catch (_) {
        if (_controller == c && mounted) setState(() => _detectDown = true);
        await Future.delayed(const Duration(seconds: 1)); // try again soon
      }
      final wait = 250 - DateTime.now().difference(started).inMilliseconds;
      if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
    }
  }

  Future<void> _stopCamera() async {
    _watchdog?.cancel();
    final c = _controller;
    _controller = null;
    _lastFrame = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
      await c.dispose();
    } catch (_) {
      // Already closed by Android; nothing left to free.
    }
  }

  void _flipCamera() {
    _queue(() async {
      await _stopCamera();
      if (!mounted) return;
      setState(() => _useFront = !_useFront);
      await _startCamera();
    });
  }

  // ------------------------------------------------------------------ build

  bool get _signedIn => _api != null;
  bool get _offline => _signedIn ? _recog.serverDown : _detectDown;

  /// What we know about each face in the latest frame.
  List<(DetectedFace, FaceIdentity?)> get _people => [
    for (final f in _lastFrame?.faces ?? const <DetectedFace>[])
      (f, _signedIn ? _recog.identityOf(f.trackingId) : null),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = kIsWeb && MediaQuery.sizeOf(context).width >= 900;
    final cameraArea = _cameraArea(wide);
    return Scaffold(
      body: wide
          ? Row(
              children: [
                Expanded(child: cameraArea),
                SizedBox(width: 280, child: _SidePanel(
                  people: _people,
                  onSignUp: () => _toast('Sign-up screens arrive in Milestone 7.'),
                  onConnect: _openConnect,
                  onOpen: (card) => _openProfile(card, source: 'In view now'),
                  signedIn: _signedIn,
                )),
              ],
            )
          : cameraArea,
    );
  }

  Widget _cameraArea(bool wide) {
    final c = _controller;
    final ready = _error == null && c != null && c.value.isInitialized;
    final noFaces = (_lastFrame?.faces.isEmpty ?? true);
    final mirror = _mirrorState();
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_error != null)
          _Problem(
            _error!,
            details: _cameraLog,
            permission: _error!.startsWith('Aaina needs the camera'),
            openSettings: _permissionBlocked,
            onRetry: () => _queue(_startCamera),
            onSwitch: _cameras.length > 1 ? _flipCamera : null,
          )
        else if (!ready)
          const _Starting()
        else ...[
          _FullScreenPreview(c),
          const _Vignette(),
          if (_qrMode)
            QrViewfinder(busy: _qrBusy)
          else ...[
            HudFrame(
              leftReadout: 'AAINA · LIVE',
              rightReadout: _lastFrame == null
                  ? ''
                  : '${_lastFrame!.source.toUpperCase()} ${_lastFrame!.detectMs} MS',
              inset: wide
                  ? const EdgeInsets.fromLTRB(20, 64, 20, 40)
                  : const EdgeInsets.fromLTRB(12, 64, 12, 132),
            ),
            if (noFaces) const ScanLine(),
            _faceLayer(wide),
          ],
        ],
        _topBar(),
        if (_offline)
          _offlineBanner()
        else if (mirror != null && !_qrMode)
          _mirrorBanner(mirror),
        if (ready && noFaces && !_qrMode && mirror == null) _hint(wide),
        if (!wide && !_qrMode && mirror?.matched == true)
          Positioned(
            left: AppSpace.md,
            right: AppSpace.md,
            bottom: 84,
            child: SafeArea(
              top: false,
              child: MirrorStats(visible: mirror!.visible, sharedCount: mirror.shared),
            ),
          )
        else if (!wide && _signedIn && !noFaces && !_qrMode)
          Positioned(
            left: AppSpace.md,
            right: AppSpace.md,
            bottom: 84,
            child: SafeArea(top: false, child: InViewStrip(people: _stripPeople())),
          ),
        if (!wide && _qrMode) ..._qrControls(),
        if (!wide) _bottomDock(),
      ],
    );
  }

  /// Mirror mode: front camera + signed in. Returns null when not in mirror mode.
  ///   matched = the camera currently recognises me
  ///   visible = I'm visible to others (hidden people show as Unknown)
  ///   shared  = how many card details others see
  ({bool matched, bool visible, int shared})? _mirrorState() {
    if (!_useFront || kIsWeb || _me == null) return null;
    final visible = _me!['visible'] != false;
    final matched = _people.any(
      (p) => p.$2?.status == IdentityStatus.known && _isMe(p.$2?.card),
    );
    if (!matched && visible) return null; // nothing to say yet
    final preview = (_me!['card_preview'] as Map?) ?? const {};
    final shared = preview.keys.where((k) => k != 'user_id' && k != 'student_status').length;
    return (matched: matched, visible: visible, shared: shared);
  }

  Widget _mirrorBanner(({bool matched, bool visible, int shared}) m) {
    return Positioned(
      top: 0,
      left: AppSpace.md,
      right: AppSpace.md,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 52),
          child: m.visible
              ? const MirrorBanner(
                  title: 'Mirror · this is you',
                  text: 'Exactly the card other people see when they point Aaina at you.',
                )
              : const MirrorBanner(
                  title: "You're hidden",
                  text: 'Others see you as Unknown. Turn visibility on in your profile.',
                  warn: true,
                ),
        ),
      ),
    );
  }

  /// QR mode: "Show my code" under the window and the Faces/QR switch.
  List<Widget> _qrControls() {
    return [
      Positioned(
        left: 0,
        right: 0,
        top: MediaQuery.sizeOf(context).height * 0.45 +
            (MediaQuery.sizeOf(context).width * 0.66).clamp(180.0, 300.0) / 2 +
            18,
        child: Center(
          child: GlassPill(
            icon: Icons.qr_code_2_rounded,
            text: 'Show my code',
            onTap: _openMyCode,
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 84,
        child: SafeArea(
          top: false,
          child: Center(child: ModeSwitch(qr: true, onChanged: _setQrMode)),
        ),
      ),
    ];
  }

  /// Frames, labels and cards for every face, converted to screen pixels.
  Widget _faceLayer(bool wide) {
    final frame = _lastFrame;
    if (frame == null) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, box) {
        final screen = Size(box.maxWidth, box.maxHeight);
        final frames = <Widget>[], labels = <Widget>[], cards = <Widget>[];

        // Known faces get cards; collect them first so they can share the space.
        final knownRects = <Rect>[];
        final knownCards = <(Key, Map<String, dynamic>, ArCardData)>[];

        for (final (f, id) in _people) {
          final rect = imageRectToScreen(
            f.box,
            frame.imageSize,
            screen,
            // The phone's front camera preview is mirrored, so its boxes are
            // flipped too. Browser pictures arrive already mirrored.
            mirror: _useFront && !kIsWeb,
          );
          final key = ValueKey(f.trackingId ?? frame.faces.indexOf(f));
          final look = switch (id?.status) {
            IdentityStatus.known => FaceLook.known,
            IdentityStatus.checking => FaceLook.checking,
            null when _signedIn && f.trackingId != null => FaceLook.checking,
            _ => FaceLook.unknown,
          };
          frames.add(FaceBox(key: key, rect: rect, look: look));

          final label = switch (id?.status) {
            IdentityStatus.known => null, // the card says it all
            IdentityStatus.unknown => ('Not on Aaina', false),
            IdentityStatus.tooFar => ('Move closer', false),
            _ when !_signedIn => ('Connect to see names', false),
            _ => ('Identifying', true),
          };
          if (label != null) {
            labels.add(Positioned(
              key: ValueKey('l$key'),
              left: rect.center.dx - 100,
              width: 200,
              top: rect.top - FaceBox.pad - 28,
              child: Center(child: HudLabel(label.$1, accent: label.$2)),
            ));
          }

          if (id?.status == IdentityStatus.known && id!.card != null) {
            knownRects.add(rect);
            knownCards.add((key, id.card!, cardToView(id.card!)));
          }
        }

        // 2+ people: smaller cards so they all fit.
        final compact = knownCards.length >= 2;
        final cardW = compact ? (wide ? 150.0 : 138.0) : (wide ? 188.0 : 168.0);
        final spots = placeCards(
          faces: knownRects,
          heights: [
            for (final k in knownCards) ArCard.heightFor(k.$3, compact: compact),
          ],
          screen: screen,
          width: cardW,
          facePad: FaceBox.pad,
          topLimit: wide ? 70 : 96,
          bottomLimit: wide ? 40 : 170,
        );

        for (var i = 0; i < knownCards.length; i++) {
          final (key, card, view) = knownCards[i];
          final spot = spots[i];
          cards
            ..add(Positioned.fill(
              key: ValueKey('ln$key'),
              child: LeaderLine(
                from: spot.lineFrom,
                to: spot.lineTo,
                vertical: spot.side == CardSide.above || spot.side == CardSide.below,
              ),
            ))
            ..add(AnimatedPositioned(
              key: ValueKey('c$key'),
              // Glide after the face instead of jumping with every frame.
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              left: spot.card.left,
              top: spot.card.top,
              child: ArCard(
                data: view,
                width: cardW,
                compact: compact,
                unfoldFromRight: spot.side == CardSide.left,
                isYou: _useFront && _isMe(card),
                onTap: () => _openProfile(card, source: 'In view now'),
                onLinkedIn: () => _openLink(linkedInUri(card)),
              ),
            ));
        }
        return Stack(children: [...frames, ...labels, ...cards]);
      },
    );
  }

  List<InViewPerson> _stripPeople() => [
    for (final (_, id) in _people)
      if (id?.status == IdentityStatus.known && id!.card != null)
        InViewPerson(
          initialsOf(id.name ?? ''),
          (id.name ?? '').split(' ').first,
          known: true,
        )
      else if (id?.status == IdentityStatus.unknown)
        const InViewPerson('?', 'Unknown'),
  ];

  Widget _topBar() {
    final n = _lastFrame?.faces.length ?? 0;
    final HudPill pill;
    if (!_signedIn) {
      pill = const HudPill(dot: AppColors.dim, text: 'Not connected');
    } else if (_offline) {
      pill = const HudPill(dot: AppColors.warn, text: 'Offline');
    } else {
      pill = HudPill(leading: const SignalBars(), text: 'Live · $n');
    }
    return Positioned(
      top: 0,
      left: AppSpace.md,
      right: AppSpace.md,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: AppSpace.sm),
          child: Row(
            children: [
              const AainaLogo(),
              const Spacer(),
              GestureDetector(onTap: _openConnect, child: pill),
              // Switch between back and front camera (hidden when there is
              // only one camera, like most laptops).
              if (_cameras.length > 1) ...[
                const SizedBox(width: AppSpace.sm),
                _RoundButton(
                  size: 34,
                  icon: Icons.cameraswitch_outlined,
                  tooltip: 'Switch camera',
                  onTap: _flipCamera,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _offlineBanner() {
    return Positioned(
      top: 0,
      left: AppSpace.md,
      right: AppSpace.md,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 52),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            decoration: BoxDecoration(
              color: const Color(0xC71E1608),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: AppColors.warn.withValues(alpha: 0.38)),
            ),
            child: Row(
              children: [
                const Icon(Icons.wifi_off_rounded, color: AppColors.warn, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Can't reach the laptop",
                          style: AppText.bodyStrong.copyWith(
                              color: AppColors.warn, fontSize: 12.5)),
                      Text(
                        kIsWeb
                            ? 'Is the backend running? (python run.py)'
                            : "Is the phone on the laptop's hotspot and the server running?",
                        style: AppText.small.copyWith(fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _openConnect,
                  child: Text('Fix', style: AppText.bodyStrong),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(bool wide) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: wide ? 60 : 150,
      child: Center(
        child: HudPill(
          text: _signedIn
              ? 'Point at someone who joined Aaina'
              : 'Point the camera at a face',
        ),
      ),
    );
  }

  /// Text on the big dock pill.
  String _mainLabel() {
    if (_qrMode) return _qrBusy ? 'Opening card…' : 'Looking for a code';
    if (_mirrorState()?.matched == true) return 'Mirror';
    final n = _lastFrame?.faces.length ?? 0;
    return n == 0 ? 'Scanning' : 'Scanning · $n';
  }

  Widget _bottomDock() {
    return Positioned(
      left: AppSpace.md,
      right: AppSpace.md,
      bottom: AppSpace.lg,
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _RoundButton(
              icon: _qrMode ? Icons.face_retouching_natural_rounded : Icons.qr_code_scanner_rounded,
              tooltip: _qrMode ? 'Back to faces' : 'Scan a QR code',
              active: _qrMode,
              onTap: () => _setQrMode(!_qrMode),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _MainButton(
                signedIn: _signedIn,
                onTap: _openConnect,
                label: _mainLabel(),
              ),
            ),
            const SizedBox(width: 10),
            _RoundButton(
              icon: Icons.person_outline_rounded,
              tooltip: 'Me',
              onTap: _openConnect,
            ),
          ],
        ),
      ),
    );
  }
}

/// Big pill in the dock: "Scanning" when signed in, else "Connect to Aaina".
class _MainButton extends StatelessWidget {
  final bool signedIn;
  final VoidCallback onTap;
  final String label; // text when signed in, e.g. "Scanning · 2"
  const _MainButton({required this.signedIn, required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: signedIn ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: signedIn ? AppColors.accent : AppColors.glass,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: signedIn
              ? null
              : Border.all(color: AppColors.accent.withValues(alpha: 0.55)),
          boxShadow: signedIn
              ? [BoxShadow(
                  color: AppColors.accent.withValues(alpha: 0.5),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                )]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (signedIn)
              const _PulseRing()
            else
              const Icon(Icons.wifi_rounded, size: 17, color: AppColors.fg),
            const SizedBox(width: 8),
            Text(
              signedIn ? label : 'Connect to Aaina',
              style: signedIn ? AppText.button : AppText.bodyStrong.copyWith(fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small ring that slowly blinks: "scanning is on".
class _PulseRing extends StatefulWidget {
  const _PulseRing();
  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: 0.35).animate(_c),
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.accentInk, width: 2),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double size;
  final bool active; // accent ring, e.g. while QR mode is on

  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.size = 50,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? AppColors.accent.withValues(alpha: 0.18) : AppColors.glass,
        shape: CircleBorder(
          side: BorderSide(color: active ? AppColors.accent : AppColors.line2),
        ),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, color: active ? AppColors.accent : AppColors.fg, size: size * 0.42),
          ),
        ),
      ),
    );
  }
}

/// Wide screens (stall laptop): who is in view + "Sign up on this laptop".
class _SidePanel extends StatelessWidget {
  final List<(DetectedFace, FaceIdentity?)> people;
  final bool signedIn;
  final VoidCallback onSignUp;
  final VoidCallback onConnect;
  final void Function(Map<String, dynamic> card) onOpen; // tap a known person

  const _SidePanel({
    required this.people,
    required this.signedIn,
    required this.onSignUp,
    required this.onConnect,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0D0F15), Color(0xFF090A0E)],
        ),
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('IN VIEW', style: AppText.hudReadout.copyWith(color: AppColors.mute, fontSize: 10)),
              const Spacer(),
              Text('${people.length}', style: AppText.mono.copyWith(color: AppColors.mute)),
            ],
          ),
          const SizedBox(height: 12),
          if (people.isEmpty)
            Text('Nobody in front of the camera.', style: AppText.small),
          for (final (_, id) in people) ...[
            _row(id),
            const SizedBox(height: 8),
          ],
          const Spacer(),
          _joinCard(),
          if (!signedIn) ...[
            const SizedBox(height: 10),
            TextButton(
              onPressed: onConnect,
              child: Text('Organiser: connect to show names',
                  style: AppText.small.copyWith(color: AppColors.accent)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(FaceIdentity? id) {
    final known = id?.status == IdentityStatus.known && id?.card != null;
    final view = known ? cardToView(id!.card!) : null;
    final (title, sub) = known
        ? (view!.name, [view.status, view.statusSub].whereType<String>().join(' · '))
        : switch (id?.status) {
            IdentityStatus.unknown => ('Unknown', 'Not on Aaina · nothing stored'),
            IdentityStatus.tooFar => ('Too far', 'Step closer to the camera'),
            _ => ('Identifying…', signedIn ? 'Asking the server' : 'Not connected'),
          };
    final row = Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: known ? AppColors.accent.withValues(alpha: 0.45) : AppColors.line,
        ),
        gradient: known
            ? LinearGradient(colors: [
                AppColors.accent.withValues(alpha: 0.12),
                AppColors.surface1,
              ])
            : null,
      ),
      child: Row(
        children: [
          InitialsBadge(view?.initials ?? '?', size: 32, round: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppText.arName.copyWith(fontSize: 13.5)),
                if (sub.isNotEmpty)
                  Text(sub, style: AppText.arSub, maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (known)
            const Icon(Icons.open_in_full_rounded, size: 13, color: AppColors.mute),
        ],
      ),
    );
    return known
        ? GestureDetector(onTap: () => onOpen(id!.card!), child: row)
        : row;
  }

  Widget _joinCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
        gradient: RadialGradient(
          center: Alignment.topLeft,
          radius: 1.4,
          colors: [AppColors.accent.withValues(alpha: 0.22), AppColors.surface1],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Join Aaina here', style: AppText.arName.copyWith(fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            'No Android phone? Sign up on this laptop with its camera in about a minute.',
            style: AppText.arSub,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onSignUp,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              minimumSize: const Size.fromHeight(40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            child: Text('Sign up on this laptop', style: AppText.button),
          ),
        ],
      ),
    );
  }
}

/// Darkens the top and bottom so the bars and buttons always read well.
class _Vignette extends StatelessWidget {
  const _Vignette();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xA8000000),
              Color(0x00000000),
              Color(0x00000000),
              Color(0xD9000000),
            ],
            stops: [0, 0.18, 0.64, 1],
          ),
        ),
      ),
    );
  }
}

/// Shows the camera preview filling the whole area (edges cut off, no
/// stretching), the same way face boxes are scaled in imageRectToScreen.
class _FullScreenPreview extends StatelessWidget {
  final CameraController controller;
  const _FullScreenPreview(this.controller);

  @override
  Widget build(BuildContext context) {
    // previewSize is given in landscape (e.g. 640x480).
    final size = controller.value.previewSize!;
    return ClipRect(
      child: FittedBox(
        fit: BoxFit.cover,
        child: kIsWeb
            // Laptop: the screen is landscape too, use the size as it is.
            ? SizedBox(
                width: size.width,
                height: size.height,
                child: controller.buildPreview(),
              )
            // Phone: we are in portrait, so width and height swap.
            : SizedBox(
                width: size.height,
                height: size.width,
                child: CameraPreview(controller),
              ),
      ),
    );
  }
}

/// Shown for a moment while the camera warms up: logo + a thin progress line.
class _Starting extends StatelessWidget {
  const _Starting();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AainaLogo(height: 22),
            const SizedBox(height: 22),
            SizedBox(
              width: 120,
              child: LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.accent,
                backgroundColor: AppColors.line2,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text('STARTING CAMERA', style: AppText.hudReadout.copyWith(color: AppColors.mute)),
          ],
        ),
      ),
    );
  }
}

/// A camera problem in plain words, with buttons that can fix it.
class _Problem extends StatelessWidget {
  final String text;
  final String? details; // technical text for the developer, small and dim
  final bool permission; // permission missing: friendlier title + Allow button
  final bool openSettings; // "don't ask again" was chosen: go to Settings
  final VoidCallback onRetry;
  final VoidCallback? onSwitch; // null = only one camera

  const _Problem(
    this.text, {
    required this.onRetry,
    this.details,
    this.permission = false,
    this.openSettings = false,
    this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    final mainLabel = !permission
        ? 'Try again'
        : (openSettings ? 'Open Settings' : 'Allow camera');
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 0.9,
          colors: [AppColors.accent.withValues(alpha: 0.14), AppColors.bg],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.line2),
                  ),
                  child: Icon(
                    permission ? Icons.photo_camera_outlined : Icons.videocam_off_outlined,
                    color: permission ? AppColors.accent : AppColors.warn,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(permission ? 'Allow the camera' : 'Camera unavailable',
                    style: AppText.sheetTitle),
                const SizedBox(height: 8),
                Text(text, style: AppText.small.copyWith(fontSize: 13),
                    textAlign: TextAlign.center),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: openSettings ? () => openAppSettings() : onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    minimumSize: const Size.fromHeight(46),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                  ),
                  child: Text(mainLabel, style: AppText.button.copyWith(fontSize: 14.5)),
                ),
                if (onSwitch != null && !permission) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: onSwitch,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(46),
                      side: const BorderSide(color: AppColors.line2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    child: Text('Use the other camera', style: AppText.bodyStrong),
                  ),
                ],
                if (details != null) ...[
                  const SizedBox(height: 16),
                  Text(details!, style: AppText.fine, textAlign: TextAlign.center, maxLines: 3),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
