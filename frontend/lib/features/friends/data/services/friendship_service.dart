import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import '../models/friend.dart';
import '../../../user/data/models/friend_request.dart';
import '../../../../core/config.dart';

class FriendshipService {
  static String get _baseUrl => AppConfig.baseUrl;

  Map<String, String> _authHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<List<FriendRequest>> getPendingRequests({
    required String userId,
    required String token,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/friendship/pending?user_id=$userId'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data
            .map((e) => FriendRequest.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      log("Error getPendingRequests: $e");
      return [];
    }
  }

  Future<List<Friend>> getFriends({
    required String userId,
    required String token,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/friendship/friends?user_id=$userId'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data
            .map((e) => Friend.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      log("Error getFriends: $e");
      return [];
    }
  }

  Future<Set<int>> getSentRequestIds({required String token}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/friendship/sent'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => (e['id'] as num).toInt()).toSet();
      }
      return {};
    } catch (e) {
      log("Error getSentRequestIds: $e");
      return {};
    }
  }

  Future<(bool, String)> createFriendship({
    required int userId,
    required int friendId,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/friendship/'),
        headers: _authHeaders(token),
        body: jsonEncode({
          'user_id': userId,
          'friend_id': friendId,
          'status': 'pending',
        }),
      );
      if (response.statusCode == 201) {
        return (true, 'Запрос в друзья отправлен');
      }
      return (false, _extractMessage(response) ?? _defaultMessage(response.statusCode));
    } catch (e) {
      log("Network error createFriendship: $e");
      return (false, 'Ошибка сети');
    }
  }

  Future<(bool, String)> respondToFriendRequest({
    required int fromUserId,
    required String status,
    required String token,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/friendship/$fromUserId/status'),
        headers: _authHeaders(token),
        body: jsonEncode({'status': status}),
      );
      if (response.statusCode == 200) {
        final ok = status == 'accepted';
        return (true, ok ? 'Заявка принята' : 'Заявка отклонена');
      }
      return (false, _extractMessage(response) ?? _defaultMessage(response.statusCode));
    } catch (e) {
      log("Network error respondToFriendRequest: $e");
      return (false, 'Ошибка сети');
    }
  }

  Future<bool> removeFriend({required int userId, required String token}) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/friendship/$userId'),
        headers: _authHeaders(token),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error removeFriend: $e");
      return false;
    }
  }

  Future<bool> blockUser({required int userId, required String token}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/friendship/$userId/block'),
        headers: _authHeaders(token),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error blockUser: $e");
      return false;
    }
  }

  Future<bool> unblockUser({required int userId, required String token}) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/friendship/$userId/block'),
        headers: _authHeaders(token),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error unblockUser: $e");
      return false;
    }
  }

  Future<List<Friend>> getBlockedUsers({required String token}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/friendship/blocked'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((e) => Friend.fromJson(e as Map<String, dynamic>)).toList();
      }
      return [];
    } catch (e) {
      log("Error getBlockedUsers: $e");
      return [];
    }
  }

  String? _extractMessage(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['message'] as String?;
    } catch (_) {
      return null;
    }
  }

  String _defaultMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Некорректный запрос';
      case 401:
        return 'Необходима авторизация';
      case 404:
        return 'Не найдено';
      case 409:
        return 'Уже существует';
      case 500:
        return 'Ошибка сервера';
      default:
        return 'Что-то пошло не так (код $statusCode)';
    }
  }
}
