import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/auth_response.dart';
import '../../../../core/config.dart';

class AuthService {
  String get baseUrl => AppConfig.baseUrl;

  // 🔐 Логин: ожидаем тело с токеном
  Future<AuthResponse> login(String username, String password) async {
    final uri = Uri.parse('$baseUrl/auth/login');
    
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    // ✅ Ранний возврат при успехе
    if (response.statusCode == 200) {
      if (response.body.isEmpty) {
        throw Exception('Пустой ответ от сервера');
      }
      final Map<String, dynamic> data = jsonDecode(response.body);
      return AuthResponse.fromJson(data);
    }

    // ✅ Если не 200 — выбрасываем ошибку и завершаем
    _handleError(response);
  }

  // ✍️ Регистрация: тело ответа опционально
  Future<void> register(String username, String password) async {
    final uri = Uri.parse('$baseUrl/auth/register');
    
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    // ✅ Ранний возврат при успехе
    if (response.statusCode == 201) {
      return;
    }

    // ✅ Если не 201 — выбрасываем ошибку
    _handleError(response);
  }

  // 🛡 Универсальная обработка ошибок (всегда бросает исключение!)
  Never _handleError(http.Response response) {
    String message = 'Ошибка сервера';
    
    if (response.body.isNotEmpty) {
      try {
        final errorBody = jsonDecode(response.body);
        message = errorBody['message'] ?? errorBody['error'] ?? message;
      } catch (_) {
        message = response.body;
      }
    }
    
    throw Exception(message);
  }
}