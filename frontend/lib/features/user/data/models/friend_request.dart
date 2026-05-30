class FriendRequest {
  final int userId;
  final String username;
  final String? avatarUrl;

  FriendRequest({required this.userId, required this.username, this.avatarUrl});

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      userId: (json['user_id'] as num).toInt(),
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
    );
  }
}
