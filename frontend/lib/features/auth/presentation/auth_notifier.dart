import 'package:flutter/foundation.dart';

class AuthNotifier extends ChangeNotifier {
  String? _userId;
  String? _username;
  String? _token;
  bool _isAuthenticated = false;

  String? get userId => _userId;
  String? get username => _username;
  String? get token => _token;
  bool get isAuthenticated => _isAuthenticated;

  void login(String userId, String username, String token) {
    _userId = userId;
    _username = username;
    _token = token;
    _isAuthenticated = true;
    notifyListeners();
  }

  void updateUsername(String username) {
    _username = username;
    notifyListeners();
  }

  Future<void> logout() async {
    _userId = null;
    _username = null;
    _token = null;
    _isAuthenticated = false;
    notifyListeners();
  }
}
