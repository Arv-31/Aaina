// connect_sheet.dart: "Connect to Aaina" bottom sheet.
//
// Server address (checked live while you type), username and password.
// Signing in gives a token that is saved on the phone (session_store.dart).
// Temporary home for sign-in until the real login screen arrives in M7.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/session_store.dart';
import '../../core/theme.dart';

/// Opens the sheet. Returns the new Session, or null if closed without change.
Future<Session?> showConnectSheet(BuildContext context, Session current) {
  return showModalBottomSheet<Session>(
    context: context,
    isScrollControlled: true, // lets the sheet move up above the keyboard
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x8C040508),
    builder: (_) => _ConnectSheet(current),
  );
}

class _ConnectSheet extends StatefulWidget {
  final Session current;
  const _ConnectSheet(this.current);

  @override
  State<_ConnectSheet> createState() => _ConnectSheetState();
}

enum _ServerState { checking, online, offline }

class _ConnectSheetState extends State<_ConnectSheet> {
  late final _server = TextEditingController(
    text: _short(widget.current.serverUrl),
  );
  late final _user = TextEditingController(text: widget.current.username ?? '');
  final _pass = TextEditingController();

  _ServerState _serverState = _ServerState.checking;
  Timer? _debounce;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkServer();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _server.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  /// "http://192.168.137.1:8000" <-> "192.168.137.1:8000" (less to type).
  static String _short(String url) => url.replaceFirst(RegExp(r'^https?://'), '');
  String get _url {
    final t = _server.text.trim().replaceAll(RegExp(r'/+$'), '');
    final withScheme = t.startsWith('http') ? t : 'http://$t';
    // No port typed? The backend uses 8000.
    return RegExp(r':\d+$').hasMatch(withScheme) ? withScheme : '$withScheme:8000';
  }

  void _onServerChanged(String _) {
    _debounce?.cancel();
    setState(() => _serverState = _ServerState.checking);
    _debounce = Timer(const Duration(milliseconds: 600), _checkServer);
  }

  Future<void> _checkServer() async {
    final url = _url;
    final api = AainaApi(url);
    try {
      await api.health();
      if (mounted && url == _url) setState(() => _serverState = _ServerState.online);
    } catch (_) {
      if (mounted && url == _url) setState(() => _serverState = _ServerState.offline);
    } finally {
      api.close();
    }
  }

  Future<void> _signIn() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Enter your username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = AainaApi(_url);
    try {
      final token = await api.login(_user.text.trim(), _pass.text);
      final session = Session(
        serverUrl: _url,
        token: token,
        username: _user.text.trim().toLowerCase(),
      );
      await SessionStore.save(session);
      if (mounted) Navigator.pop(context, session);
    } on ServerUnreachable {
      setState(() => _error = "Can't reach the laptop. Check the address and that the phone is on its hotspot.");
    } catch (e) {
      setState(() => _error = '$e');
    } finally {
      api.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut() async {
    final api = AainaApi(widget.current.serverUrl, token: widget.current.token);
    try {
      await api.logout(); // revoke the token on the server too
    } catch (_) {
      // Server unreachable: the token is still forgotten on this phone.
    } finally {
      api.close();
    }
    final session = Session(serverUrl: widget.current.serverUrl);
    await SessionStore.save(session);
    if (mounted) Navigator.pop(context, session);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = widget.current.signedIn;
    return Padding(
      // Keeps the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF131722), Color(0xFF0B0D12)],
          ),
          border: Border(top: BorderSide(color: AppColors.line2)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.line2,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              Text(
                signedIn ? 'Connected' : 'Connect to Aaina',
                style: AppText.sheetTitle,
              ),
              const SizedBox(height: 4),
              Text(
                signedIn
                    ? 'Signed in as ${widget.current.username}.'
                    : "Join the stall laptop's hotspot, then sign in.",
                style: AppText.small,
              ),
              const SizedBox(height: 6),
              _label('Server'),
              _field(
                _server,
                mono: true,
                hint: '192.168.137.1:8000',
                onChanged: _onServerChanged,
                keyboard: TextInputType.url,
                trailing: _serverBadge(),
              ),
              if (!signedIn) ...[
                _label('Username'),
                _field(_user, hint: 'your username', keyboard: TextInputType.emailAddress),
                _label('Password'),
                _field(_pass, hint: '••••••••', obscure: true, onSubmit: _signIn),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: AppText.small.copyWith(color: AppColors.bad)),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 46,
                child: signedIn
                    ? OutlinedButton(
                        onPressed: _signOut,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.fg,
                          side: const BorderSide(color: AppColors.line2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        child: Text('Sign out', style: AppText.bodyStrong),
                      )
                    : FilledButton(
                        onPressed: _busy ? null : _signIn,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.accentInk,
                                ),
                              )
                            : Text('Sign in', style: AppText.button.copyWith(fontSize: 14.5)),
                      ),
              ),
              const SizedBox(height: 10),
              Text(
                'The address is printed when the laptop runs python run.py',
                textAlign: TextAlign.center,
                style: AppText.small.copyWith(color: AppColors.dim, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 5),
    child: Text(text, style: AppText.fieldLabel),
  );

  Widget _serverBadge() {
    final (color, text) = switch (_serverState) {
      _ServerState.online => (AppColors.ok, 'online'),
      _ServerState.offline => (AppColors.bad, 'not found'),
      _ServerState.checking => (AppColors.dim, 'checking'),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: color, blurRadius: 6)],
          ),
        ),
        const SizedBox(width: 5),
        Text(text, style: AppText.mono.copyWith(fontSize: 10.5, color: color)),
        const SizedBox(width: 12),
      ],
    );
  }

  Widget _field(
    TextEditingController c, {
    String? hint,
    bool mono = false,
    bool obscure = false,
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
    VoidCallback? onSubmit,
    Widget? trailing,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      borderSide: const BorderSide(color: AppColors.line2),
    );
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      autocorrect: false,
      onChanged: onChanged,
      onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
      style: mono ? AppText.mono.copyWith(fontSize: 13.5) : AppText.input,
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: AppText.input.copyWith(color: AppColors.dim),
        filled: true,
        fillColor: AppColors.surface2,
        contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
        ),
        suffixIcon: trailing,
        suffixIconConstraints: const BoxConstraints(minHeight: 0, minWidth: 0),
      ),
    );
  }
}
