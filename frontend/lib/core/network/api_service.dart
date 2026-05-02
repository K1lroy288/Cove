import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import '../../features/user/data/models/friend_request.dart';
import '../../features/user/data/models/user_dto.dart';

class ApiService {
  static const String baseUrl = "http://localhost:3425";

  Future<List<FriendRequest>> getPendingRequests({required String userId, required String token}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/friendship/pending?user_id=$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => FriendRequest.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      log("Error getting pending requests: $e");
      return [];
    }
  }

  Future<int> getPendingRequestsCount({required String userId, required String token}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/friendship/pending/count?user_id=$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['count'] as num).toInt();
      }
      return 0;
    } catch (e) {
      log("Error getting pending count: $e");
      return 0;
    }
  }

  Future<UserDTO?> searchUser(String query) async {
    return _fetchUser('$baseUrl/user/search?q=${Uri.encodeComponent(query)}');
  }

  Future<UserDTO?> findUserById(String id) async {
    return _fetchUser('$baseUrl/user/$id');
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
      log("User not found: ${response.statusCode} $url");
      return null;
    } catch (e) {
      log("Network error: $e");
      return null;
    }
  }

  /// Возвращает (success, message) где message — текст для показа пользователю.
  Future<(bool, String)> createFriendship({
    required int userId,
    required int friendId,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/friendship/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'user_id': userId,
          'friend_id': friendId,
          'status': 'pending',
        }),
      );

      if (response.statusCode == 201) {
        return (true, 'Запрос в друзья отправлен');
      }

      // Пробуем достать message из тела
      String message = _defaultMessage(response.statusCode);
      if (response.body.isNotEmpty) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          message = data['message'] as String? ?? message;
        } catch (_) {}
      }

      return (false, message);
    } catch (e) {
      log("Network error at createFriendship: $e");
      return (false, 'Ошибка сети');
    }
  }

  String _defaultMessage(int statusCode) {
    switch (statusCode) {
      case 400: return 'Некорректный запрос';
      case 401: return 'Необходима авторизация';
      case 500: return 'Ошибка сервера';
      default:  return 'Что-то пошло не так (код $statusCode)';
    }
  }
}
