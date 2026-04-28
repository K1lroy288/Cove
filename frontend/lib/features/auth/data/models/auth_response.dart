class AuthResponse {
  final String token;
  final String userId;
  final String username;

  AuthResponse({
    required this.token,
    required this.userId,
    required this.username,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      token: json['token'] as String,
      userId: json['userId'].toString(),
      username: json['username'] as String,
    );
  }
}