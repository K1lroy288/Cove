class RoomMember {
  final int userId;
  final String username;
  final bool isMuted;
  bool isSpeaking;

  RoomMember({
    required this.userId,
    required this.username,
    this.isMuted = false,
    this.isSpeaking = false,
  });

  factory RoomMember.fromJson(Map<String, dynamic> json) {
    return RoomMember(
      userId: (json['user_id'] as num).toInt(),
      username: json['username'] as String,
      isMuted: json['is_muted'] as bool? ?? false,
    );
  }
}

class VoiceRoom {
  final int id;
  final String name;
  final int createdBy;
  final bool isActive;
  final List<RoomMember> members;

  const VoiceRoom({
    required this.id,
    required this.name,
    required this.createdBy,
    required this.isActive,
    this.members = const [],
  });

  factory VoiceRoom.fromJson(Map<String, dynamic> json) {
    return VoiceRoom(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      createdBy: (json['created_by'] as num).toInt(),
      isActive: json['is_active'] as bool? ?? true,
      members: (json['members'] as List<dynamic>?)
              ?.map((m) => RoomMember.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
