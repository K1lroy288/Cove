class FriendRequest {
  final int userId;
  final String username;

  FriendRequest({required this.userId, required this.username});

  factory FriendRequest.fromJson(Map<String, dynamic> json) {
    return FriendRequest(
      userId: (json['user_id'] as num).toInt(),
      username: json['username'] as String,
    );
  }
}
