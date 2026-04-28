import 'package:flutter/foundation.dart';

class AuthNotifier extends ChangeNotifier {
  String? _username;
  String? _token;
  bool _isAuthenticated = false;

  String? get username => _username;
  String? get token => _token;
  bool get isAuthenticated => _isAuthenticated;

  void login(String username, String token) {
    _username = username;
    _token = token;
    _isAuthenticated = true;
    notifyListeners();
  }

  Future<void> logout() async {
    _username = null;
    _token = null;
    _isAuthenticated = false;
    notifyListeners();
  }
}
