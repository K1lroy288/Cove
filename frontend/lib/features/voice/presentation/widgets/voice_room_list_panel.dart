import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../core/theme/app_theme.dart' show AppTheme, AppColors;
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
    final colors = AppColors.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        title: Text('Новая комната', style: TextStyle(color: colors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Название комнаты',
            hintStyle: TextStyle(color: colors.textSecondary),
            filled: true,
            fillColor: colors.bg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            suffixIcon: IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
              onPressed: () => showModalBottomSheet(
                context: ctx,
                builder: (_) => SizedBox(
                  height: 300,
                  child: EmojiPicker(
                    textEditingController: controller,
                    config: AppTheme.emojiPickerConfig(colors, height: 300),
                  ),
                ),
              ),
            ),
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Отмена', style: TextStyle(color: colors.textSecondary)),
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
    final colors = AppColors.of(context);
    return Container(
      color: colors.bg,
      child: Column(
        children: [
          _buildHeader(),
          Divider(height: 1, color: colors.divider),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
      child: Row(
        children: [
          Text(
            'Голосовые комнаты',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textPrimary),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.refresh, size: 20, color: colors.textSecondary),
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

    final colors = AppColors.of(context);

    if (_rooms.isEmpty) {
      return Center(
        child: Opacity(
          opacity: 0.35,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.graphic_eq, size: 48, color: colors.textPrimary),
              const SizedBox(height: 12),
              Text('Нет активных комнат',
                  style: TextStyle(fontSize: 14, color: colors.textPrimary)),
              const SizedBox(height: 6),
              Text('Нажмите + чтобы создать',
                  style: TextStyle(fontSize: 12, color: colors.textPrimary)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _rooms.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: colors.divider, indent: 16),
      itemBuilder: (context, index) => _buildRoomTile(_rooms[index]),
    );
  }

  Widget _buildRoomTile(VoiceRoom room) {
    final voice = context.watch<VoiceNotifier>();
    final isCurrentRoom = voice.currentRoom?.id == room.id;
    final isJoining = _joiningRoomId == room.id;
    final colors = AppColors.of(context);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isCurrentRoom
              ? Colors.greenAccent.withValues(alpha: 0.15)
              : colors.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          Icons.graphic_eq,
          color: isCurrentRoom ? Colors.greenAccent : colors.textSecondary,
          size: 20,
        ),
      ),
      title: Text(
        room.name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isCurrentRoom ? Colors.greenAccent : colors.textPrimary,
        ),
      ),
      subtitle: Text(
        '${room.members.length} участн.',
        style: TextStyle(fontSize: 12, color: colors.textSecondary),
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
