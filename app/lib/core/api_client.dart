// api_client.dart: every call from the app to the laptop backend. No UI here.
//
// Plain HTTP over the hotspot/LAN. Each scan carries the login token
// ("Authorization: Bearer ..."); there is no shared API key in the app (rule 4).

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Rect, Size;

import 'package:http/http.dart' as http;

/// Thrown when the laptop can't be reached (wrong address, server off, no Wi-Fi).
class ServerUnreachable implements Exception {
  final String reason;
  ServerUnreachable(this.reason);
  @override
  String toString() => reason;
}

/// Thrown when the server refuses the login token (expired or logged out).
class NotSignedIn implements Exception {}

/// Thrown for a clear answer from the server, e.g. "Wrong username or password."
class ServerMessage implements Exception {
  final String message;
  ServerMessage(this.message);
  @override
  String toString() => message;
}

/// One face the server found in a photo we sent.
class RecognizedFace {
  final Rect box; // in the sent photo's pixels
  final String status; // "match", "unknown" or "too_small"
  final double? score; // similarity, only for a match
  final Map<String, dynamic>? card; // profile card, only for a match

  const RecognizedFace(this.box, this.status, this.score, this.card);

  bool get isMatch => status == 'match' && card != null;
}

class RecognizeResult {
  final Size imageSize;
  final List<RecognizedFace> faces;
  const RecognizeResult(this.imageSize, this.faces);
}

class AainaApi {
  final String baseUrl;
  final String? token;
  final http.Client _client;

  AainaApi(this.baseUrl, {this.token, http.Client? client})
    : _client = client ?? http.Client();

  Map<String, String> get _auth =>
      token == null ? {} : {'Authorization': 'Bearer $token'};

  /// Is the server there? Returns how many faces it has loaded.
  Future<int> health() async {
    final r = await _send(() => _client.get(Uri.parse('$baseUrl/health')),
        timeout: 4);
    return (jsonDecode(r.body)['faces_loaded'] as num).toInt();
  }

  /// Logs in and returns the token.
  Future<String> login(String username, String password) async {
    final r = await _send(
      () => _client.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      ),
    );
    return jsonDecode(r.body)['token'] as String;
  }

  /// Ends this login on the server (the token stops working everywhere).
  Future<void> logout() async {
    await _send(
      () => _client.post(Uri.parse('$baseUrl/auth/logout'), headers: _auth),
      timeout: 4,
    );
  }

  /// Sends one JPEG (a face crop or a whole frame) and asks "who is this?".
  Future<RecognizeResult> recognize(Uint8List jpeg) async {
    final request =
        http.MultipartRequest('POST', Uri.parse('$baseUrl/recognize'))
          ..headers.addAll(_auth)
          ..files.add(
            http.MultipartFile.fromBytes('photo', jpeg, filename: 'face.jpg'),
          );
    final r = await _send(
      () async => http.Response.fromStream(await _client.send(request)),
    );
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final size = data['image_size'] as List;
    return RecognizeResult(
      Size((size[0] as num).toDouble(), (size[1] as num).toDouble()),
      [
        for (final f in data['faces'] as List)
          RecognizedFace(
            Rect.fromLTRB(
              (f['box'][0] as num).toDouble(),
              (f['box'][1] as num).toDouble(),
              (f['box'][2] as num).toDouble(),
              (f['box'][3] as num).toDouble(),
            ),
            f['status'] as String,
            (f['score'] as num?)?.toDouble(),
            f['card'] as Map<String, dynamic>?,
          ),
      ],
    );
  }

  /// My own profile: user_id, visible, share switches, qr_value, card_preview...
  Future<Map<String, dynamic>> me() async {
    final r = await _send(
      () => _client.get(Uri.parse('$baseUrl/me'), headers: _auth),
    );
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// QR fallback: the card behind a scanned "aaina:..." code.
  /// Throws ServerMessage if the code is unknown, replaced or the person is hidden.
  Future<Map<String, dynamic>> qrLookup(String code) async {
    final r = await _send(
      () => _client.get(
        Uri.parse('$baseUrl/qr/${Uri.encodeComponent(code)}'),
        headers: _auth,
      ),
    );
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Makes a new QR code for me; the old one stops working. Returns the new value.
  Future<String> newQr() async {
    final r = await _send(
      () => _client.post(Uri.parse('$baseUrl/me/qr/new'), headers: _auth),
    );
    return jsonDecode(r.body)['qr_value'] as String;
  }

  /// Runs one request and turns failures into the three error types above.
  Future<http.Response> _send(
    Future<http.Response> Function() call, {
    int timeout = 8,
  }) async {
    final http.Response r;
    try {
      r = await call().timeout(Duration(seconds: timeout));
    } catch (e) {
      throw ServerUnreachable('$e');
    }
    if (r.statusCode == 401) {
      // Login route: wrong password. Other routes: token no longer valid.
      if (r.request?.url.path == '/auth/login') {
        throw ServerMessage(_detail(r) ?? 'Wrong username or password.');
      }
      throw NotSignedIn();
    }
    if (r.statusCode != 200) {
      throw ServerMessage(_detail(r) ?? 'Server answered ${r.statusCode}.');
    }
    return r;
  }

  /// FastAPI puts error text in {"detail": "..."}.
  String? _detail(http.Response r) {
    try {
      final d = jsonDecode(r.body)['detail'];
      return d is String ? d : null;
    } catch (_) {
      return null;
    }
  }

  void close() => _client.close();
}
