import 'package:flutter/foundation.dart';

class AuthNotifier extends ChangeNotifier {
  String? _username;
  String? _token;
  bool _isAuthenticated = false;

  // Геттеры для чтения данных
  String? get username => _username;
  String? get token => _token;
  bool get isAuthenticated => _isAuthenticated;

  // Метод вызывается после успешного логина
  void login(String username, String token) {
    _username = username;
    _token = token;
    _isAuthenticated = true;
    notifyListeners(); // 🔥 Уведомляем все виджеты, которые слушают этот класс
  }

  // Метод для выхода из аккаунта
  void logout() {
    _username = null;
    _token = null;
    _isAuthenticated = false;
    notifyListeners();
  }
}