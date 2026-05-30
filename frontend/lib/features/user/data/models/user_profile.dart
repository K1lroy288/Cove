enum FriendshipStatus { none, friends, pendingIncoming, pendingOutgoing }

FriendshipStatus _parseFriendshipStatus(String? s) {
  switch (s) {
    case 'friends':
      return FriendshipStatus.friends;
    case 'pending_incoming':
      return FriendshipStatus.pendingIncoming;
    case 'pending_outgoing':
      return FriendshipStatus.pendingOutgoing;
    default:
      return FriendshipStatus.none;
  }
}

class UserProfile {
  final int id;
  final String username;
  final String? bio;
  final String? avatarUrl;
  final DateTime memberSince;
  final FriendshipStatus? friendshipStatus;
  final bool isBlocked;
  final DateTime? lastSeenAt;

  const UserProfile({
    required this.id,
    required this.username,
    this.bio,
    this.avatarUrl,
    required this.memberSince,
    this.friendshipStatus,
    this.isBlocked = false,
    this.lastSeenAt,
  });

  UserProfile copyWith({FriendshipStatus? friendshipStatus, bool? isBlocked}) {
    return UserProfile(
      id: id,
      username: username,
      bio: bio,
      avatarUrl: avatarUrl,
      memberSince: memberSince,
      friendshipStatus: friendshipStatus ?? this.friendshipStatus,
      isBlocked: isBlocked ?? this.isBlocked,
      lastSeenAt: lastSeenAt,
    );
  }

  factory UserProfile.fromJson(Map<String, dynamic> json, {bool isMe = false}) {
    return UserProfile(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String,
      bio: json['bio'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      memberSince: DateTime.parse(json['member_since'] as String),
      friendshipStatus: isMe ? null : _parseFriendshipStatus(json['friendship_status'] as String?),
      isBlocked: json['is_blocked'] as bool? ?? false,
      lastSeenAt: json['last_seen_at'] != null
          ? DateTime.tryParse(json['last_seen_at'] as String)
          : null,
    );
  }
}
