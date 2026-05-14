import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import '../models/user_settings.dart';

class SettingsService {
  static const String _baseUrl = 'http://localhost:3425';

  Map<String, String> _headers(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<UserSettings?> getSettings({required String token}) async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/settings/'),
        headers: _headers(token),
      );
      if (resp.statusCode == 200) {
        return UserSettings.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (e) {
      log('getSettings error: $e');
    }
    return null;
  }

  Future<UserSettings?> updateSettings({
    required String token,
    String? theme,
    String? locale,
    Map<String, dynamic>? preferences,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (theme != null) body['theme'] = theme;
      if (locale != null) body['locale'] = locale;
      if (preferences != null) body['preferences'] = preferences;

      final resp = await http.patch(
        Uri.parse('$_baseUrl/settings/'),
        headers: _headers(token),
        body: jsonEncode(body),
      );
      if (resp.statusCode == 200) {
        return UserSettings.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (e) {
      log('updateSettings error: $e');
    }
    return null;
  }

  Future<ChatNotifSettings?> getChatNotifSettings({
    required String token,
    required int chatId,
  }) async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/settings/chat/$chatId'),
        headers: _headers(token),
      );
      if (resp.statusCode == 200) {
        return ChatNotifSettings.fromJson(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (e) {
      log('getChatNotifSettings error: $e');
    }
    return null;
  }

  Future<ChatNotifSettings?> updateChatNotifSettings({
    required String token,
    required int chatId,
    bool? muted,
    DateTime? muteUntil,
    int? notifyLevel,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (muted != null) body['muted'] = muted;
      if (muteUntil != null) body['mute_until'] = muteUntil.toIso8601String();
      if (notifyLevel != null) body['notify_level'] = notifyLevel;

      final resp = await http.patch(
        Uri.parse('$_baseUrl/settings/chat/$chatId'),
        headers: _headers(token),
        body: jsonEncode(body),
      );
      if (resp.statusCode == 200) {
        return ChatNotifSettings.fromJson(
            jsonDecode(resp.body) as Map<String, dynamic>);
      }
    } catch (e) {
      log('updateChatNotifSettings error: $e');
    }
    return null;
  }
}
