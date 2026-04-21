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

  // 🔥 Обновлённый logout: очищает состояние и готов к расширению
  Future<void> logout() async {
    // 1. Очищаем память
    _username = null;
    _token = null;
    _isAuthenticated = false;
    
    // 2. TODO: Здесь позже добавим очистку безопасного хранилища:
    // final storage = FlutterSecureStorage();
    // await storage.delete(key: 'auth_token');
    
    notifyListeners();
  }
}