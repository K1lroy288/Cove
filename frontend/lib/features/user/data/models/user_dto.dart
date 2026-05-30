class UserDTO {
  final int id;
  final String username;
  final String? avatarUrl;

  UserDTO({required this.id, required this.username, this.avatarUrl});

  factory UserDTO.fromJson(Map<String, dynamic> json) {
    return UserDTO(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    if (avatarUrl != null) 'avatar_url': avatarUrl,
  };
}
