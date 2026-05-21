enum MessageStatus { sent, delivered, read }

class Message {
  final int id;
  final int chatId;
  final int senderId;
  final String content;
  final String type;
  final DateTime createdAt;
  final bool isOptimistic;
  final MessageStatus status;

  const Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    this.type = 'text',
    required this.createdAt,
    this.isOptimistic = false,
    this.status = MessageStatus.sent,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: (json['id'] as num).toInt(),
      chatId: (json['chat_id'] as num).toInt(),
      senderId: (json['sender_id'] as num).toInt(),
      content: json['content'] as String,
      type: json['type'] as String? ?? 'text',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Message copyWith({bool? isOptimistic, MessageStatus? status}) {
    return Message(
      id: id,
      chatId: chatId,
      senderId: senderId,
      content: content,
      type: type,
      createdAt: createdAt,
      isOptimistic: isOptimistic ?? this.isOptimistic,
      status: status ?? this.status,
    );
  }
}
