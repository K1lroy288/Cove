import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import '../models/voice_room.dart';

class VoiceService {
  static const String _baseUrl = "http://localhost:3425";

  Map<String, String> _authHeaders(String token) => {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };

  Future<List<VoiceRoom>> getVoiceRooms({required String token}) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/voice-room/'),
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
        Uri.parse('$_baseUrl/voice-room/'),
        headers: _authHeaders(token),
        body: jsonEncode({'name': name}),
      );
      if (response.statusCode == 200 || response.statusCode == 201) {
        return VoiceRoom.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
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
        Uri.parse('$_baseUrl/voice-room/$roomId/join'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        return VoiceRoom.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
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
        Uri.parse('$_baseUrl/voice-room/$roomId/leave'),
        headers: _authHeaders(token),
      );
      return response.statusCode == 200;
    } catch (e) {
      log("Error leaveVoiceRoom: $e");
      return false;
    }
  }
}
