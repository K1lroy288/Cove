import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../core/network/api_service.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../features/auth/presentation/auth_notifier.dart';
import '../../data/models/voice_room.dart';
import '../voice_notifier.dart';

class VoiceRoomPage extends StatefulWidget {
  const VoiceRoomPage({super.key});

  @override
  State<VoiceRoomPage> createState() => _VoiceRoomPageState();
}

class _VoiceRoomPageState extends State<VoiceRoomPage>
    with TickerProviderStateMixin {
  final ApiService _api = ApiService();
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _leaveRoom(BuildContext context) async {
    final voice = context.read<VoiceNotifier>();
    final auth = context.read<AuthNotifier>();
    final roomId = voice.currentRoom?.id;

    if (roomId != null && auth.token != null) {
      await _api.leaveVoiceRoom(roomId: roomId, token: auth.token!);
    }
    voice.leaveRoom();
  }

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoiceNotifier>();
    final room = voice.currentRoom;

    if (room == null) return _buildEmptyState();

    return Container(
      color: AppTheme.darkBg,
      child: Column(
        children: [
          _buildHeader(room),
          const Divider(height: 1, color: Colors.white10),
          Expanded(child: _buildMembersGrid(room.members, voice)),
          const Divider(height: 1, color: Colors.white10),
          _buildControls(context, voice),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      color: AppTheme.darkBg,
      child: Center(
        child: Opacity(
          opacity: 0.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.mic_none, size: 64, color: Colors.white),
              SizedBox(height: 16),
              Text('Выберите комнату слева',
                  style: TextStyle(fontSize: 16, color: Colors.white)),
              SizedBox(height: 8),
              Text('или создайте новую',
                  style: TextStyle(fontSize: 13, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(VoiceRoom room) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.greenAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.graphic_eq,
                color: Colors.greenAccent, size: 20),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(room.name,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(
                '${room.members.length} участн.',
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ],
          ),
          const Spacer(),
          _connectionQualityBadge(),
        ],
      ),
    );
  }

  Widget _connectionQualityBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.greenAccent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: Colors.greenAccent.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.signal_cellular_alt, size: 14, color: Colors.greenAccent),
          SizedBox(width: 4),
          Text('Хорошее',
              style: TextStyle(fontSize: 11, color: Colors.greenAccent)),
        ],
      ),
    );
  }

  Widget _buildMembersGrid(List<RoomMember> members, VoiceNotifier voice) {
    if (members.isEmpty) {
      return Center(
        child: Opacity(
          opacity: 0.35,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.person_outline, size: 48, color: Colors.white),
              SizedBox(height: 12),
              Text('Вы одни в комнате',
                  style: TextStyle(fontSize: 14, color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisExtent: 140,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: members.length,
      itemBuilder: (context, index) =>
          _buildMemberTile(members[index], voice),
    );
  }

  Widget _buildMemberTile(RoomMember member, VoiceNotifier voice) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: member.isSpeaking ? _pulseAnimation.value : 1.0,
              child: Container(
                decoration: member.isSpeaking
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.greenAccent.withValues(alpha: 0.5),
                            blurRadius: 16,
                            spreadRadius: 4,
                          ),
                        ],
                      )
                    : null,
                child: child,
              ),
            );
          },
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 34,
                backgroundColor: member.isSpeaking
                    ? Colors.greenAccent.withValues(alpha: 0.15)
                    : AppTheme.surface,
                child: Text(
                  member.username[0].toUpperCase(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: member.isSpeaking
                        ? Colors.greenAccent
                        : Colors.white70,
                  ),
                ),
              ),
              if (member.isMuted)
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppTheme.darkBg, width: 2),
                  ),
                  child: const Icon(Icons.mic_off,
                      size: 10, color: Colors.white),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          member.username,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: member.isSpeaking ? Colors.greenAccent : Colors.white,
          ),
          overflow: TextOverflow.ellipsis,
        ),
        if (member.isSpeaking)
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text('говорит...',
                style: TextStyle(fontSize: 10, color: Colors.greenAccent)),
          ),
      ],
    );
  }

  Widget _buildControls(BuildContext context, VoiceNotifier voice) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _controlBtn(
            icon: voice.isMuted ? Icons.mic_off : Icons.mic,
            label: voice.isMuted ? 'Включить' : 'Выключить',
            color: voice.isMuted ? Colors.redAccent : Colors.white70,
            bgColor: voice.isMuted
                ? Colors.redAccent.withValues(alpha: 0.15)
                : AppTheme.surface,
            onTap: voice.toggleMute,
          ),
          const SizedBox(width: 32),
          _controlBtn(
            icon: Icons.call_end,
            label: 'Выйти',
            color: Colors.white,
            bgColor: Colors.redAccent,
            onTap: () => _leaveRoom(context),
          ),
        ],
      ),
    );
  }

  Widget _controlBtn({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.white54)),
        ],
      ),
    );
  }
}
