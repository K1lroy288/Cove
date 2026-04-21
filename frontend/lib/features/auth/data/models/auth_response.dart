class AuthResponse {
  final String token;
  final String userId;
  final String username;

  AuthResponse({
    required this.token,
    required this.userId,
    required this.username,
  });

  // Преобразует JSON от сервера в Dart-объект
  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      token: json['token'] as String,
      userId: json['userId'] as String,
      username: json['username'] as String,
    );
  }
}