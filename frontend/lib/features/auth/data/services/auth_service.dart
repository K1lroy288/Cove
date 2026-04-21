import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/auth_response.dart';

class AuthService {
  // В продакшене выноси в .env или конфиг!
  final String baseUrl = 'http://localhost:3425';

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

    if (response.statusCode == 200) {
      final Map<String, dynamic> data = jsonDecode(response.body);
      return AuthResponse.fromJson(data);
    } else {
      // Сервер вернул ошибку (401, 400, 500 и т.д.)
      final errorBody = jsonDecode(response.body);
      throw Exception(errorBody['message'] ?? 'Ошибка авторизации');
    }
  }

  Future<AuthResponse> register(String username, String password) async {
    final uri = Uri.parse('$baseUrl/auth/register');
    
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );

    if (response.statusCode == 201) { // 201 Created для регистрации
      final Map<String, dynamic> data = jsonDecode(response.body);
      return AuthResponse.fromJson(data);
    } else {
      final errorBody = jsonDecode(response.body);
      throw Exception(errorBody['message'] ?? 'Ошибка регистрации');
    }
  }
}