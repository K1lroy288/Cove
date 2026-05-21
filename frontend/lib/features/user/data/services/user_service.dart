import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import '../models/user_dto.dart';
import '../models/user_profile.dart';

class UserService {
  static const String _baseUrl = "http://localhost:3425";

  Map<String, String> _authHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<UserDTO?> searchUser(String query) async {
    return _fetchUser('$_baseUrl/user/search?q=${Uri.encodeComponent(query)}');
  }

  Future<UserDTO?> findUserById(String id) async {
    return _fetchUser('$_baseUrl/user/$id');
  }

  Future<UserProfile?> getMe(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user/me'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        return UserProfile.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
          isMe: true,
        );
      }
      return null;
    } catch (e) {
      log("Error getMe: $e");
      return null;
    }
  }

  Future<UserProfile?> getUserProfile(int userId, String token) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/user/$userId/profile'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        return UserProfile.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      log("Error getUserProfile: $e");
      return null;
    }
  }

  Future<UserProfile?> updateProfile(String token, {String? username, String? bio}) async {
    try {
      final body = <String, dynamic>{};
      if (username != null) body['username'] = username;
      if (bio != null) body['bio'] = bio;
      final response = await http.patch(
        Uri.parse('$_baseUrl/user/me'),
        headers: _authHeaders(token),
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return UserProfile.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
          isMe: true,
        );
      }
      return null;
    } catch (e) {
      log("Error updateProfile: $e");
      return null;
    }
  }

  Future<(bool, String)> changePassword(
    String token, {
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/user/me/password'),
        headers: _authHeaders(token),
        body: jsonEncode({
          'current_password': currentPassword,
          'new_password': newPassword,
        }),
      );
      if (response.statusCode == 204) return (true, 'Пароль изменён');
      final msg = _extractMessage(response) ?? _defaultMsg(response.statusCode);
      return (false, msg);
    } catch (e) {
      log("Error changePassword: $e");
      return (false, 'Ошибка сети');
    }
  }

  Future<bool> deleteAccount(String token) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/user/me'),
        headers: _authHeaders(token),
      );
      return response.statusCode == 204;
    } catch (e) {
      log("Error deleteAccount: $e");
      return false;
    }
  }

  Future<UserDTO?> _fetchUser(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200) {
        return UserDTO.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      log("Network error fetchUser: $e");
      return null;
    }
  }

  String? _extractMessage(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      return (jsonDecode(response.body) as Map<String, dynamic>)['message'] as String?;
    } catch (_) {
      return null;
    }
  }

  String _defaultMsg(int code) {
    switch (code) {
      case 401:
        return 'Неверный текущий пароль';
      case 409:
        return 'Имя пользователя уже занято';
      default:
        return 'Ошибка сервера ($code)';
    }
  }
}
