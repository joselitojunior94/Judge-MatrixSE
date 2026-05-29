import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';

/// Central auth + session singleton.
///
/// Responsibilities:
///   - Store / load JWT tokens from SharedPreferences
///   - Expose [api] — a ready-to-use [Api] instance with refresh wired up
///   - Expose [currentUser] — the /api/auth/me/ payload after login
///   - [login], [logout] lifecycle
///   - Notify listeners on every state change so the UI rebuilds
class AuthService extends ChangeNotifier {
  // ---- singleton ----------------------------------------------------------
  static final AuthService instance = AuthService._();
  AuthService._();

  // ---- state --------------------------------------------------------------
  String? _access;
  String? _refresh;
  Map<String, dynamic>? _currentUser;
  bool _initialised = false;
  bool _sessionExpired = false;

  bool get isLoggedIn => _access != null;
  Map<String, dynamic>? get currentUser => _currentUser;
  bool get initialised => _initialised;
  bool get sessionExpired => _sessionExpired;

  String get username => (_currentUser?['username'] as String?) ?? 'unknown';
  String get displayName =>
      (_currentUser?['display_name'] as String?) ?? username;

  // ---- API access ---------------------------------------------------------

  /// Returns a fully-configured [Api] instance.  Throws if not logged in.
  Api get api {
    if (_access == null) throw Exception('Not logged in');
    return Api(_access!, onTokenExpired: _tryRefresh);
  }

  // ---- initialization -----------------------------------------------------

  /// Must be called once at app startup (before runApp is useful, ideally in
  /// main() after WidgetsFlutterBinding.ensureInitialized()).
  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    _access = sp.getString('access');
    _refresh = sp.getString('refresh');

    if (_access != null) {
      // Try to fetch the current user — if the token is expired, attempt
      // refresh right now so the user doesn't land on a broken Shell.
      try {
        _currentUser = await api.me();
      } catch (_) {
        final fresh = await _tryRefresh();
        if (fresh != null) {
          try {
            _currentUser = await api.me();
          } catch (_) {
            _clearTokens();
          }
        } else {
          _clearTokens();
        }
      }
    }

    _initialised = true;
    notifyListeners();
  }

  // ---- login / logout -----------------------------------------------------

  /// Authenticates with username + password.
  /// Throws a human-readable [Exception] on failure.
  Future<void> login(String username, String password) async {
    final r = await http.post(
      Uri.parse('$kApiBaseUrl/api/auth/token/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (r.statusCode == 200) {
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      await _saveTokens(j['access'] as String, j['refresh'] as String);
      _sessionExpired = false;
      try {
        _currentUser = await api.me();
      } catch (_) {}
      notifyListeners();
    } else if (r.statusCode == 401) {
      throw Exception('Invalid username or password');
    } else {
      throw Exception('Login failed (${r.statusCode})');
    }
  }

  /// Registers a new account and immediately logs in.
  Future<void> register(String username, String password) async {
    final r = await http.post(
      Uri.parse('$kApiBaseUrl/api/auth/register/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (r.statusCode == 201) {
      await login(username, password);
    } else {
      final body = jsonDecode(r.body);
      final detail = body is Map ? (body['detail'] ?? body.toString()) : r.body;
      throw Exception('Registration failed: $detail');
    }
  }

  Future<void> logout() async {
    _clearTokens();
    _currentUser = null;
    _sessionExpired = false;
    notifyListeners();
  }

  Future<void> acknowledgeSessionExpired() async {
    _sessionExpired = false;
    notifyListeners();
  }

  Future<void> refreshCurrentUser() async {
    if (_access == null) return;
    _currentUser = await api.me();
    notifyListeners();
  }

  // ---- token refresh (called by Api on 401) --------------------------------

  Future<String?> _tryRefresh() async {
    if (_refresh == null) return null;
    try {
      final r = await http.post(
        Uri.parse('$kApiBaseUrl/api/auth/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': _refresh}),
      );
      if (r.statusCode == 200) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        final newAccess = j['access'] as String;
        _access = newAccess;
        final sp = await SharedPreferences.getInstance();
        await sp.setString('access', newAccess);
        // If the response includes a rotated refresh token, persist it too.
        if (j.containsKey('refresh')) {
          _refresh = j['refresh'] as String;
          await sp.setString('refresh', _refresh!);
        }
        return newAccess;
      }
    } catch (_) {}
    // Refresh failed — force a clean return to login through AuthGate.
    await _expireSession();
    return null;
  }

  // ---- helpers ------------------------------------------------------------

  Future<void> _expireSession() async {
    await _clearTokens();
    _currentUser = null;
    _sessionExpired = true;
    notifyListeners();
  }

  Future<void> _saveTokens(String access, String refresh) async {
    _access = access;
    _refresh = refresh;
    final sp = await SharedPreferences.getInstance();
    await sp.setString('access', access);
    await sp.setString('refresh', refresh);
  }

  Future<void> _clearTokens() async {
    _access = null;
    _refresh = null;
    final sp = await SharedPreferences.getInstance();
    await sp.remove('access');
    await sp.remove('refresh');
  }
}
