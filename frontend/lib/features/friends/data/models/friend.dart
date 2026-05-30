class Friend {
  final int id;
  final String username;
  final String? avatarUrl;
  final DateTime? lastSeenAt;

  const Friend({required this.id, required this.username, this.avatarUrl, this.lastSeenAt});

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String,
      avatarUrl: json['avatar_url'] as String?,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'] as String)
          : null,
    );
  }
}
