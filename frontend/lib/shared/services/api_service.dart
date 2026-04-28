import 'dart:convert';
import 'dart:developer';
import 'package:http/http.dart' as http;
import '../models/user_dto.dart'; // проверь путь до модели

class ApiService {
  static const String baseUrl = "http://localhost:3425"; 

  Future<UserDTO?> findUserById(String id) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/user/$id'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return UserDTO.fromJson(data);
      } else {
        log("User not found or server error: ${response.statusCode}");
        return null;
      }
    } catch (e) {
      log("Network error: $e");
      return null;
    }
  }
}