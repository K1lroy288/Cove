class PartnerCursorModel {
  final int? lastReadMessageId;
  final int? lastDeliveredMessageId;

  const PartnerCursorModel({
    this.lastReadMessageId,
    this.lastDeliveredMessageId,
  });

  factory PartnerCursorModel.fromJson(Map<String, dynamic> json) {
    return PartnerCursorModel(
      lastReadMessageId: json['last_read_message_id'] != null
          ? (json['last_read_message_id'] as num).toInt()
          : null,
      lastDeliveredMessageId: json['last_delivered_message_id'] != null
          ? (json['last_delivered_message_id'] as num).toInt()
          : null,
    );
  }
}
