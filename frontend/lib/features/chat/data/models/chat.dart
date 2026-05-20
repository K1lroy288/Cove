class Chat {
  final int id;
  final String chatType; // 'dm' | 'group'
  // DM fields
  final int partnerId;
  final String partnerName;
  // Group fields
  final String? groupName;
  final String? groupAvatar;
  final int? memberCount;
  final String? myRole; // 'member' | 'admin'
  // Shared
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  const Chat({
    required this.id,
    required this.chatType,
    this.partnerId = 0,
    this.partnerName = '',
    this.groupName,
    this.groupAvatar,
    this.memberCount,
    this.myRole,
    this.lastMessage,
    this.lastMessageAt,
    this.unreadCount = 0,
  });

  bool get isGroup => chatType == 'group';

  String get displayName =>
      isGroup ? (groupName ?? '') : partnerName;

  String get avatarInitial {
    if (isGroup) {
      if (groupAvatar != null && groupAvatar!.isNotEmpty) return groupAvatar!;
      return groupName?.isNotEmpty == true ? groupName![0].toUpperCase() : '?';
    }
    return partnerName.isNotEmpty ? partnerName[0].toUpperCase() : '?';
  }

  bool get isAdmin => myRole == 'admin';

  Chat copyWith({
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
    String? groupName,
    String? groupAvatar,
    int? memberCount,
  }) {
    return Chat(
      id: id,
      chatType: chatType,
      partnerId: partnerId,
      partnerName: partnerName,
      groupName: groupName ?? this.groupName,
      groupAvatar: groupAvatar ?? this.groupAvatar,
      memberCount: memberCount ?? this.memberCount,
      myRole: myRole,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: (json['id'] as num).toInt(),
      chatType: (json['chat_type'] as String?) ?? 'dm',
      partnerId: (json['partner_id'] as num?)?.toInt() ?? 0,
      partnerName: (json['partner_name'] as String?) ?? '',
      groupName: json['group_name'] as String?,
      groupAvatar: json['group_avatar'] as String?,
      memberCount: (json['member_count'] as num?)?.toInt(),
      myRole: json['my_role'] as String?,
      lastMessage: json['last_message'] as String?,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null,
      unreadCount: (json['unread_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class GroupMember {
  final int userId;
  final String username;
  final String role;
  final DateTime joinedAt;

  const GroupMember({
    required this.userId,
    required this.username,
    required this.role,
    required this.joinedAt,
  });

  bool get isAdmin => role == 'admin';

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: (json['user_id'] as num).toInt(),
      username: json['username'] as String,
      role: json['role'] as String,
      joinedAt: DateTime.parse(json['joined_at'] as String),
    );
  }
}
