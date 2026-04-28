class UserDTO {
  final int id;
  final String username;

  UserDTO({required this.id, required this.username});

  factory UserDTO.fromJson(Map<String, dynamic> json) {
    return UserDTO(
      id: json['id'] as int,
      username: json['username'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
  };
}
