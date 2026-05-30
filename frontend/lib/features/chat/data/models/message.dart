enum MessageStatus { sent, delivered, read }

class RepliedMessage {
  final int id;
  final int senderId;
  final String senderUsername;
  final String content;
  final String type;

  const RepliedMessage({
    required this.id,
    required this.senderId,
    required this.senderUsername,
    required this.content,
    required this.type,
  });

  factory RepliedMessage.fromJson(Map<String, dynamic> json) {
    return RepliedMessage(
      id: (json['id'] as num).toInt(),
      senderId: (json['sender_id'] as num).toInt(),
      senderUsername: json['sender_username'] as String? ?? '',
      content: json['content'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
    );
  }
}

class ReactionGroup {
  final String emoji;
  final int count;
  final bool hasMine;

  const ReactionGroup({
    required this.emoji,
    required this.count,
    required this.hasMine,
  });

  factory ReactionGroup.fromJson(Map<String, dynamic> json) {
    return ReactionGroup(
      emoji: json['emoji'] as String,
      count: (json['count'] as num).toInt(),
      hasMine: json['has_mine'] as bool? ?? false,
    );
  }
}

class PinnedMessage {
  final int id;
  final int senderId;
  final String content;
  final String type;

  const PinnedMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.type,
  });

  factory PinnedMessage.fromJson(Map<String, dynamic> json) {
    return PinnedMessage(
      id: (json['id'] as num).toInt(),
      senderId: (json['sender_id'] as num).toInt(),
      content: json['content'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
    );
  }
}

class Message {
  final int id;
  final int chatId;
  final int senderId;
  final String content;
  final String type;
  final String? fileName;
  final int? fileSize;
  final String? caption;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool isOptimistic;
  final bool isDeleted;
  final MessageStatus status;
  final RepliedMessage? repliedTo;
  final List<ReactionGroup> reactions;
  final int? forwardedFromId;
  final String? forwardedFromUsername;

  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    this.type = 'text',
    this.fileName,
    this.fileSize,
    this.caption,
    required this.createdAt,
    this.editedAt,
    this.isOptimistic = false,
    this.isDeleted = false,
    this.status = MessageStatus.sent,
    this.repliedTo,
    this.reactions = const [],
    this.forwardedFromId,
    this.forwardedFromUsername,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: (json['id'] as num).toInt(),
      chatId: (json['chat_id'] as num).toInt(),
      senderId: (json['sender_id'] as num).toInt(),
      content: json['content'] as String? ?? '',
      type: json['type'] as String? ?? 'text',
      fileName: json['file_name'] as String?,
      fileSize: json['file_size'] == null ? null : (json['file_size'] as num).toInt(),
      caption: json['caption'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      editedAt: json['edited_at'] != null
          ? DateTime.tryParse(json['edited_at'] as String)
          : null,
      isDeleted: json['is_deleted'] as bool? ?? false,
      repliedTo: json['reply_to'] != null
          ? RepliedMessage.fromJson(json['reply_to'] as Map<String, dynamic>)
          : null,
      reactions: (json['reactions'] as List<dynamic>?)
              ?.map((e) => ReactionGroup.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      forwardedFromId: json['forwarded_from_id'] == null
          ? null
          : (json['forwarded_from_id'] as num).toInt(),
      forwardedFromUsername: json['forwarded_from_username'] as String?,
    );
  }

  Message copyWith({
    bool? isOptimistic,
    MessageStatus? status,
    String? caption,
    String? content,
    bool? isDeleted,
    List<ReactionGroup>? reactions,
    DateTime? editedAt,
  }) {
    return Message(
      id: id,
      chatId: chatId,
      senderId: senderId,
      content: content ?? this.content,
      type: type,
      fileName: fileName,
      fileSize: fileSize,
      caption: caption ?? this.caption,
      createdAt: createdAt,
      editedAt: editedAt ?? this.editedAt,
      isOptimistic: isOptimistic ?? this.isOptimistic,
      isDeleted: isDeleted ?? this.isDeleted,
      status: status ?? this.status,
      repliedTo: repliedTo,
      reactions: reactions ?? this.reactions,
      forwardedFromId: forwardedFromId,
      forwardedFromUsername: forwardedFromUsername,
    );
  }
}
