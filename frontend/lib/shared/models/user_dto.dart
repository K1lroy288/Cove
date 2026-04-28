class UserDTO {
  final int id;
  final String username;

  UserDTO({required this.id, required this.username});

  // Превращаем JSON от Go-сервера в объект Dart
  factory UserDTO.fromJson(Map<String, dynamic> json) {
    return UserDTO(
      id: json['id'] as int,
      username: json['username'] as String,
    );
  }

  // На случай, если нужно отправить данные обратно
  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
  };
}