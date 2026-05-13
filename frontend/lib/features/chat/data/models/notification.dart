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
  final int chatId;
  final int senderId;
  final String content;
  final DateTime createdAt;

  NewMessageNotification({
    required this.chatId,
    required this.senderId,
    required this.content,
    required this.createdAt,
  });

  factory NewMessageNotification.fromPayload(Map<String, dynamic> p) {
    return NewMessageNotification(
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
