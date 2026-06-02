import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class AuthNotifier extends ChangeNotifier {
  // ── Хранилище ────────────────────────────────────────────────────────────────
  // Используем файл в applicationSupportDirectory как надёжный кросс-платформенный
  // fallback (flutter_secure_storage не работает без активного D-Bus keyring на Linux)

  static Future<File> _sessionFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/.cove_session');
  }

  static Future<void> _writeSession(String token, String userId, String username) async {
    try {
      final file = await _sessionFile();
      await file.writeAsString(jsonEncode({
        'token': token,
        'userId': userId,
        'username': username,
      }));
    } catch (e) {
      log('AuthNotifier: failed to write session: $e');
    }
  }

  static Future<Map<String, String>?> _readSession() async {
    try {
      final file = await _sessionFile();
      if (!await file.exists()) return null;
      final raw = await file.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final token = map['token'] as String?;
      final userId = map['userId'] as String?;
      final username = map['username'] as String?;
      if (token == null || userId == null || username == null) return null;
      return {'token': token, 'userId': userId, 'username': username};
    } catch (e) {
      log('AuthNotifier: failed to read session: $e');
      return null;
    }
  }

  static Future<void> _clearSession() async {
    try {
      final file = await _sessionFile();
      if (await file.exists()) await file.delete();
    } catch (e) {
      log('AuthNotifier: failed to clear session: $e');
    }
  }

  // ── Стейт ────────────────────────────────────────────────────────────────────
  String? _userId;
  String? _username;
  String? _token;
  bool _isAuthenticated = false;
  bool _isRestoring = true;

  String? get userId => _userId;
  String? get username => _username;
  String? get token => _token;
  bool get isAuthenticated => _isAuthenticated;
  bool get isRestoring => _isRestoring;

  Future<void> tryRestoreSession() async {
    final session = await _readSession();
    if (session != null) {
      _userId = session['userId'];
      _username = session['username'];
      _token = session['token'];
      _isAuthenticated = true;
      log('AuthNotifier: session restored for $_username');
    }
    _isRestoring = false;
    notifyListeners();
  }

  Future<void> login(String userId, String username, String token) async {
    _userId = userId;
    _username = username;
    _token = token;
    _isAuthenticated = true;
    notifyListeners();
    await _writeSession(token, userId, username);
  }

  void updateUsername(String username) {
    _username = username;
    notifyListeners();
    if (_token != null && _userId != null) {
      _writeSession(_token!, _userId!, username);
    }
  }

  Future<void> logout() async {
    _userId = null;
    _username = null;
    _token = null;
    _isAuthenticated = false;
    notifyListeners();
    await _clearSession();
  }
}
