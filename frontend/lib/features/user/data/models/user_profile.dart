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
  final DateTime memberSince;
  final FriendshipStatus? friendshipStatus;

  const UserProfile({
    required this.id,
    required this.username,
    this.bio,
    required this.memberSince,
    this.friendshipStatus,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json, {bool isMe = false}) {
    return UserProfile(
      id: (json['id'] as num).toInt(),
      username: json['username'] as String,
      bio: json['bio'] as String?,
      memberSince: DateTime.parse(json['member_since'] as String),
      friendshipStatus: isMe ? null : _parseFriendshipStatus(json['friendship_status'] as String?),
    );
  }
}
