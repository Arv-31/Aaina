// session_store.dart: remembers the login and server address on this phone.
// No UI here.
//
// Saved with shared_preferences (a small key-value file private to the app).
// Only the login TOKEN is kept, never the password. The token can be revoked
// on the server (log out), and the server stores only a hash of it.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class Session {
  final String serverUrl;
  final String? token; // null = not signed in
  final String? username;

  const Session({required this.serverUrl, this.token, this.username});

  bool get signedIn => token != null;
}

class SessionStore {
  static const _kServer = 'server_url';
  static const _kToken = 'token';
  static const _kUser = 'username';

  /// The address used when nothing was saved yet.
  static String get defaultServer =>
      kIsWeb ? AppConfig.laptopServerUrl : AppConfig.serverUrl;

  static Future<Session> load() async {
    final p = await SharedPreferences.getInstance();
    return Session(
      serverUrl: p.getString(_kServer) ?? defaultServer,
      token: p.getString(_kToken),
      username: p.getString(_kUser),
    );
  }

  static Future<void> save(Session s) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kServer, s.serverUrl);
    if (s.token == null) {
      await p.remove(_kToken);
      await p.remove(_kUser);
    } else {
      await p.setString(_kToken, s.token!);
      await p.setString(_kUser, s.username ?? '');
    }
  }
}
