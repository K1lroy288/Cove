import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import '../models/chat.dart';
import '../models/message.dart';
import '../models/partner_cursor.dart';

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

  Future<(List<Message>, PartnerCursorModel?)> getMessages({
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
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        final rawMessages = body['messages'] as List<dynamic>;
        final cursorJson = body['partner_cursor'] as Map<String, dynamic>?;

        PartnerCursorModel? cursor;
        if (cursorJson != null) {
          cursor = PartnerCursorModel.fromJson(cursorJson);
        }

        final messages = rawMessages.map((e) {
          final msg = Message.fromJson(e as Map<String, dynamic>);
          if (cursor == null) return msg;
          MessageStatus status = MessageStatus.sent;
          if (cursor.lastReadMessageId != null && msg.id <= cursor.lastReadMessageId!) {
            status = MessageStatus.read;
          } else if (cursor.lastDeliveredMessageId != null && msg.id <= cursor.lastDeliveredMessageId!) {
            status = MessageStatus.delivered;
          }
          return msg.copyWith(status: status);
        }).toList();

        return (messages, cursor);
      }
      return (<Message>[], null);
    } catch (e) {
      log("Error getMessages: $e");
      return (<Message>[], null);
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

  // --- Группы ---

  Future<Chat?> createGroup({
    required String name,
    required List<int> memberIds,
    String avatar = '',
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/groups/'),
        headers: _authHeaders(token),
        body: jsonEncode({
          'name': name,
          'avatar': avatar,
          'member_ids': memberIds,
        }),
      );
      if (response.statusCode == 201) {
        return Chat.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      }
      log("Error createGroup: ${response.statusCode} ${response.body}");
      return null;
    } catch (e) {
      log("Error createGroup: $e");
      return null;
    }
  }

  Future<List<GroupMember>> getGroupMembers({
    required int chatId,
    required String token,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/groups/$chatId/members'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data
            .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      log("Error getGroupMembers: $e");
      return [];
    }
  }

  Future<bool> addMembers({
    required int chatId,
    required List<int> userIds,
    required String token,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/groups/$chatId/members'),
        headers: _authHeaders(token),
        body: jsonEncode({'user_ids': userIds}),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error addMembers: $e");
      return false;
    }
  }

  Future<bool> kickMember({
    required int chatId,
    required int userId,
    required String token,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/groups/$chatId/members/$userId'),
        headers: _authHeaders(token),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error kickMember: $e");
      return false;
    }
  }

  Future<bool> leaveGroup({
    required int chatId,
    required String token,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/groups/$chatId/leave'),
        headers: _authHeaders(token),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error leaveGroup: $e");
      return false;
    }
  }

  Future<bool> deleteGroup({
    required int chatId,
    required String token,
  }) async {
    try {
      final response = await http.delete(
        Uri.parse('$_baseUrl/groups/$chatId'),
        headers: _authHeaders(token),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error deleteGroup: $e");
      return false;
    }
  }

  Future<Chat?> updateGroup({
    required int chatId,
    String? name,
    String? avatar,
    required String token,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name != null) body['name'] = name;
      if (avatar != null) body['avatar'] = avatar;
      final response = await http.patch(
        Uri.parse('$_baseUrl/groups/$chatId'),
        headers: _authHeaders(token),
        body: jsonEncode(body),
      );
      if (response.statusCode == 200) {
        return Chat.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      log("Error updateGroup: $e");
      return null;
    }
  }

  Future<bool> setMemberRole({
    required int chatId,
    required int userId,
    required String role,
    required String token,
  }) async {
    try {
      final response = await http.patch(
        Uri.parse('$_baseUrl/groups/$chatId/members/$userId/role'),
        headers: _authHeaders(token),
        body: jsonEncode({'role': role}),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error setMemberRole: $e");
      return false;
    }
  }
}
