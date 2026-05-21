class AppNotification {
  final String type;
  final Map<String, dynamic> payload;

  AppNotification({required this.type, required this.payload});

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      type: json['type'] as String,
      payload: json['payload'] as Map<String, dynamic>,
    );
  }
}

class NewMessageNotification {
  final int messageId;
  final int chatId;
  final int senderId;
  final String content;
  final DateTime createdAt;

  NewMessageNotification({
    required this.messageId,
    required this.chatId,
    required this.senderId,
    required this.content,
    required this.createdAt,
  });

  factory NewMessageNotification.fromPayload(Map<String, dynamic> p) {
    return NewMessageNotification(
      messageId: (p['message_id'] as num).toInt(),
      chatId: (p['chat_id'] as num).toInt(),
      senderId: (p['sender_id'] as num).toInt(),
      content: p['content'] as String,
      createdAt: DateTime.parse(p['created_at'] as String),
    );
  }
}

class ChatMessageNotification {
  final int id;
  final int chatId;
  final int senderId;
  final String content;
  final DateTime createdAt;

  ChatMessageNotification({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessageNotification.fromPayload(Map<String, dynamic> p) {
    return ChatMessageNotification(
      id: (p['id'] as num).toInt(),
      chatId: (p['chat_id'] as num).toInt(),
      senderId: (p['sender_id'] as num).toInt(),
      content: p['content'] as String,
      createdAt: DateTime.parse(p['created_at'] as String),
    );
  }
}

class FriendRequestNotification {
  final int fromUserId;
  final String username;

  FriendRequestNotification({required this.fromUserId, required this.username});

  factory FriendRequestNotification.fromPayload(Map<String, dynamic> p) {
    return FriendRequestNotification(
      fromUserId: (p['from_user_id'] as num).toInt(),
      username: p['username'] as String,
    );
  }
}

class GroupCreatedNotification {
  final int chatId;
  final String groupName;
  final String groupAvatar;
  final int createdBy;

  GroupCreatedNotification({
    required this.chatId,
    required this.groupName,
    required this.groupAvatar,
    required this.createdBy,
  });

  factory GroupCreatedNotification.fromPayload(Map<String, dynamic> p) {
    return GroupCreatedNotification(
      chatId: (p['chat_id'] as num).toInt(),
      groupName: (p['group_name'] as String?) ?? '',
      groupAvatar: (p['group_avatar'] as String?) ?? '',
      createdBy: (p['created_by'] as num).toInt(),
    );
  }
}

class GroupUpdatedNotification {
  final int chatId;
  final String name;
  final String avatar;

  GroupUpdatedNotification({
    required this.chatId,
    required this.name,
    required this.avatar,
  });

  factory GroupUpdatedNotification.fromPayload(Map<String, dynamic> p) {
    return GroupUpdatedNotification(
      chatId: (p['chat_id'] as num).toInt(),
      name: (p['name'] as String?) ?? '',
      avatar: (p['avatar'] as String?) ?? '',
    );
  }
}

// reason: 'added' | 'kicked' | 'left'
class MemberChangedNotification {
  final int chatId;
  final int userId;
  final String username;
  final String reason;

  MemberChangedNotification({
    required this.chatId,
    required this.userId,
    required this.username,
    required this.reason,
  });

  factory MemberChangedNotification.fromPayload(Map<String, dynamic> p) {
    return MemberChangedNotification(
      chatId: (p['chat_id'] as num).toInt(),
      userId: (p['user_id'] as num).toInt(),
      username: (p['username'] as String?) ?? '',
      reason: (p['reason'] as String?) ?? '',
    );
  }
}

class GroupDissolvedNotification {
  final int chatId;

  GroupDissolvedNotification({required this.chatId});

  factory GroupDissolvedNotification.fromPayload(Map<String, dynamic> p) {
    return GroupDissolvedNotification(
      chatId: (p['chat_id'] as num).toInt(),
    );
  }
}

class RoleChangedNotification {
  final int chatId;
  final int userId;
  final String newRole;

  RoleChangedNotification({
    required this.chatId,
    required this.userId,
    required this.newRole,
  });

  factory RoleChangedNotification.fromPayload(Map<String, dynamic> p) {
    return RoleChangedNotification(
      chatId: (p['chat_id'] as num).toInt(),
      userId: (p['user_id'] as num).toInt(),
      newRole: (p['new_role'] as String?) ?? '',
    );
  }
}

class MessageDeliveredNotification {
  final int chatId;
  final int messageId;
  final DateTime deliveredAt;

  MessageDeliveredNotification({
    required this.chatId,
    required this.messageId,
    required this.deliveredAt,
  });

  factory MessageDeliveredNotification.fromPayload(Map<String, dynamic> p) {
    return MessageDeliveredNotification(
      chatId: (p['chat_id'] as num).toInt(),
      messageId: (p['message_id'] as num).toInt(),
      deliveredAt: DateTime.parse(p['delivered_at'] as String),
    );
  }
}

class UserPresenceNotification {
  final int userId;
  final bool isOnline;

  UserPresenceNotification({required this.userId, required this.isOnline});

  factory UserPresenceNotification.fromPayload(Map<String, dynamic> p) {
    return UserPresenceNotification(
      userId: (p['user_id'] as num).toInt(),
      isOnline: p['is_online'] as bool,
    );
  }
}

class MessageReadNotification {
  final int chatId;
  final int lastReadMessageId;
  final DateTime readAt;

  MessageReadNotification({
    required this.chatId,
    required this.lastReadMessageId,
    required this.readAt,
  });

  factory MessageReadNotification.fromPayload(Map<String, dynamic> p) {
    return MessageReadNotification(
      chatId: (p['chat_id'] as num).toInt(),
      lastReadMessageId: (p['last_read_message_id'] as num).toInt(),
      readAt: DateTime.parse(p['read_at'] as String),
    );
  }
}
