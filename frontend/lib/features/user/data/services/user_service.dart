import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import '../models/user_dto.dart';

class UserService {
  static const String _baseUrl = "http://localhost:3425";

  Future<UserDTO?> searchUser(String query) async {
    return _fetchUser('$_baseUrl/user/search?q=${Uri.encodeComponent(query)}');
  }

  Future<UserDTO?> findUserById(String id) async {
    return _fetchUser('$_baseUrl/user/$id');
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
}
