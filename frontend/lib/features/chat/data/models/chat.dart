class Chat {
  final int id;
  final int partnerId;
  final String partnerName;
  final String? lastMessage;
  final DateTime? lastMessageAt;

  const Chat({
    required this.id,
    required this.partnerId,
    required this.partnerName,
    this.lastMessage,
    this.lastMessageAt,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: (json['id'] as num).toInt(),
      partnerId: (json['partner_id'] as num).toInt(),
      partnerName: json['partner_name'] as String,
      lastMessage: json['last_message'] as String?,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null,
    );
  }
}
