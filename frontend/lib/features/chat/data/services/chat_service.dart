import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import '../models/chat.dart';
import '../models/message.dart';

class ChatService {
  static const String _baseUrl = "http://localhost:3425";

  Map<String, String> _authHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<List<Chat>> getChats({required String token}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/chat/'),
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
        Uri.parse('$_baseUrl/chat/'),
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
        Uri.parse('$_baseUrl/chat/$chatId/messages$query'),
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
        Uri.parse('$_baseUrl/chat/$chatId/messages'),
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
}
