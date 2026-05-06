import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../core/theme/app_theme.dart';
import '../../../../features/auth/presentation/auth_notifier.dart';
import '../../data/models/voice_room.dart';
import '../../data/services/voice_service.dart';
import '../voice_notifier.dart';

class VoiceRoomListPanel extends StatefulWidget {
  const VoiceRoomListPanel({super.key});

  @override
  State<VoiceRoomListPanel> createState() => _VoiceRoomListPanelState();
}

class _VoiceRoomListPanelState extends State<VoiceRoomListPanel> {
  final VoiceService _api = VoiceService();

  List<VoiceRoom> _rooms = [];
  bool _isLoading = true;
  int? _joiningRoomId;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    final auth = context.read<AuthNotifier>();
    if (auth.token == null) return;

    final rooms = await _api.getVoiceRooms(token: auth.token!);
    if (mounted) {
      setState(() {
        _rooms = rooms;
        _isLoading = false;
      });
    }
  }

  Future<void> _joinRoom(VoiceRoom room) async {
    final auth = context.read<AuthNotifier>();
    if (auth.token == null) return;

    setState(() => _joiningRoomId = room.id);

    final joined = await _api.joinVoiceRoom(
      roomId: room.id,
      token: auth.token!,
    );

    if (!mounted) return;
    setState(() => _joiningRoomId = null);

    if (joined != null) {
      context.read<VoiceNotifier>().joinRoom(joined);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось войти в комнату'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showCreateRoomDialog() async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;

    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Новая комната'),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Название комнаты',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: AppTheme.darkBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentIndigo,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;

    final room = await _api.createVoiceRoom(name: name, token: token);
    if (!mounted) return;

    if (room != null) {
      context.read<VoiceNotifier>().joinRoom(room);
      await _loadRooms();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось создать комнату'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.darkBg,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Colors.white10),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      child: Row(
        children: [
          const Text(
            'Голосовые комнаты',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: Colors.white38),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadRooms();
            },
          ),
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.accentIndigo),
            tooltip: 'Создать комнату',
            onPressed: _showCreateRoomDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.accentIndigo));
    }

    if (_rooms.isEmpty) {
      return Center(
        child: Opacity(
          opacity: 0.35,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.graphic_eq, size: 48, color: Colors.white),
              SizedBox(height: 12),
              Text('Нет активных комнат',
                  style: TextStyle(fontSize: 14, color: Colors.white)),
              SizedBox(height: 6),
              Text('Нажмите + чтобы создать',
                  style: TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _rooms.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, color: Colors.white10, indent: 16),
      itemBuilder: (context, index) => _buildRoomTile(_rooms[index]),
    );
  }

  Widget _buildRoomTile(VoiceRoom room) {
    final voice = context.watch<VoiceNotifier>();
    final isCurrentRoom = voice.currentRoom?.id == room.id;
    final isJoining = _joiningRoomId == room.id;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isCurrentRoom
              ? Colors.greenAccent.withValues(alpha: 0.15)
              : AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.graphic_eq,
          color: isCurrentRoom ? Colors.greenAccent : Colors.white38,
          size: 20,
        ),
      ),
      title: Text(
        room.name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isCurrentRoom ? Colors.greenAccent : Colors.white,
        ),
      ),
      subtitle: Text(
        '${room.members.length} участн.',
        style: const TextStyle(fontSize: 12, color: Colors.white38),
      ),
      trailing: isCurrentRoom
          ? Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('В эфире',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.w600)),
            )
          : isJoining
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.accentIndigo),
                )
              : TextButton(
                  onPressed: () => _joinRoom(room),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentIndigo,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                  ),
                  child: const Text('Войти',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
    );
  }
}
