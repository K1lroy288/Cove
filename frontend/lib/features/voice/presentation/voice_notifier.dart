import 'package:flutter/foundation.dart';
import '../data/models/voice_room.dart';

class VoiceNotifier extends ChangeNotifier {
  VoiceRoom? _currentRoom;
  bool _isMuted = false;

  VoiceRoom? get currentRoom => _currentRoom;
  bool get isMuted => _isMuted;
  bool get isInRoom => _currentRoom != null;

  void joinRoom(VoiceRoom room) {
    _currentRoom = room;
    _isMuted = false;
    notifyListeners();
  }

  void leaveRoom() {
    _currentRoom = null;
    _isMuted = false;
    notifyListeners();
  }

  void toggleMute() {
    _isMuted = !_isMuted;
    notifyListeners();
  }

  void updateMembers(List<RoomMember> members) {
    if (_currentRoom == null) return;
    _currentRoom = VoiceRoom(
      id: _currentRoom!.id,
      name: _currentRoom!.name,
      createdBy: _currentRoom!.createdBy,
      isActive: _currentRoom!.isActive,
      members: members,
    );
    notifyListeners();
  }
}
