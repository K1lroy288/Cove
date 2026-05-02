import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import '../../features/chat/data/models/chat.dart';
import '../../features/chat/data/models/message.dart';
import '../../features/friends/data/models/friend.dart';
import '../../features/user/data/models/friend_request.dart';
import '../../features/user/data/models/user_dto.dart';
import '../../features/voice/data/models/voice_room.dart';

class ApiService {
  static const String baseUrl = "http://localhost:3425";

  // ── Auth headers helper ─────────────────────────────────────────────────────

  Map<String, String> _authHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  // ── Users ───────────────────────────────────────────────────────────────────

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
      return null;
    } catch (e) {
      log("Network error fetchUser: $e");
      return null;
    }
  }

  // ── Friendships ─────────────────────────────────────────────────────────────

  Future<List<FriendRequest>> getPendingRequests({
    required String userId,
    required String token,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/friendship/pending?user_id=$userId'),
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
        Uri.parse('$baseUrl/friendship/friends?user_id=$userId'),
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

  Future<(bool, String)> createFriendship({
    required int userId,
    required int friendId,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/friendship/'),
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
    required String status, // "accepted" | "declined"
    required String token,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/friendship/$fromUserId/status'),
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

  // ── Chats ───────────────────────────────────────────────────────────────────

  Future<List<Chat>> getChats({required String token}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/chat/'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data
            .map((e) => Chat.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      log("Error getChats: $e");
      return [];
    }
  }

  Future<Chat?> createChat({
    required int friendId,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/'),
        headers: _authHeaders(token),
        body: jsonEncode({'friend_id': friendId}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Chat.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      log("Error createChat: $e");
      return null;
    }
  }

  // ── Messages ─────────────────────────────────────────────────────────────────

  Future<List<Message>> getMessages({
    required int chatId,
    required String token,
    int? before,
    int limit = 50,
  }) async {
    try {
      final query = before != null
          ? '?before=$before&limit=$limit'
          : '?limit=$limit';
      final response = await http.get(
        Uri.parse('$baseUrl/chat/$chatId/messages$query'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data
            .map((e) => Message.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      log("Error getMessages: $e");
      return [];
    }
  }

  Future<Message?> sendMessage({
    required int chatId,
    required String content,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/chat/$chatId/messages'),
        headers: _authHeaders(token),
        body: jsonEncode({'content': content, 'type': 'text'}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return Message.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      log("Error sendMessage: $e");
      return null;
    }
  }

  // ── Voice Rooms ──────────────────────────────────────────────────────────────

  Future<List<VoiceRoom>> getVoiceRooms({required String token}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/voice-room/'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data
            .map((e) => VoiceRoom.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      log("Error getVoiceRooms: $e");
      return [];
    }
  }

  Future<VoiceRoom?> createVoiceRoom({
    required String name,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/voice-room/'),
        headers: _authHeaders(token),
        body: jsonEncode({'name': name}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return VoiceRoom.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      log("Error createVoiceRoom: $e");
      return null;
    }
  }

  Future<VoiceRoom?> joinVoiceRoom({
    required int roomId,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/voice-room/$roomId/join'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        return VoiceRoom.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      log("Error joinVoiceRoom: $e");
      return null;
    }
  }

  Future<bool> leaveVoiceRoom({
    required int roomId,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/voice-room/$roomId/leave'),
        headers: _authHeaders(token),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error leaveVoiceRoom: $e");
      return false;
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

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
