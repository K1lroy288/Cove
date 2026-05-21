import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart' show AppTheme, AppColors;
import '../../../auth/presentation/auth_notifier.dart';
import '../../../chat/data/models/chat.dart';
import '../../../chat/data/services/chat_service.dart';
import '../../../friends/data/services/friendship_service.dart';
import '../../data/models/user_profile.dart';
import '../../data/services/user_service.dart';

class UserProfileSheet extends StatefulWidget {
  final int userId;
  final Function(Chat)? onOpenChat;

  const UserProfileSheet({super.key, required this.userId, this.onOpenChat});

  static Future<void> show(
    BuildContext context,
    int userId, {
    Function(Chat)? onOpenChat,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => UserProfileSheet(userId: userId, onOpenChat: onOpenChat),
    );
  }

  @override
  State<UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends State<UserProfileSheet> {
  final UserService _userService = UserService();
  final FriendshipService _friendshipService = FriendshipService();
  final ChatService _chatService = ChatService();

  UserProfile? _profile;
  bool _loading = true;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;
    final profile = await _userService.getUserProfile(widget.userId, token);
    if (mounted) setState(() { _profile = profile; _loading = false; });
  }

  Future<void> _addFriend() async {
    final auth = context.read<AuthNotifier>();
    final myId = int.tryParse(auth.userId ?? '');
    if (myId == null || auth.token == null) return;
    setState(() => _actionLoading = true);
    final (ok, msg) = await _friendshipService.createFriendship(
      userId: myId, friendId: widget.userId, token: auth.token!,
    );
    if (!mounted) return;
    setState(() {
      _actionLoading = false;
      if (ok && _profile != null) {
        _profile = UserProfile(
          id: _profile!.id, username: _profile!.username,
          bio: _profile!.bio, memberSince: _profile!.memberSince,
          friendshipStatus: FriendshipStatus.pendingOutgoing,
        );
      }
    });
    _showSnack(msg, ok);
  }

  Future<void> _respond(String status) async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;
    setState(() => _actionLoading = true);
    final (ok, msg) = await _friendshipService.respondToFriendRequest(
      fromUserId: widget.userId, status: status, token: token,
    );
    if (!mounted) return;
    setState(() {
      _actionLoading = false;
      if (ok && _profile != null) {
        _profile = UserProfile(
          id: _profile!.id, username: _profile!.username,
          bio: _profile!.bio, memberSince: _profile!.memberSince,
          friendshipStatus: status == 'accepted'
              ? FriendshipStatus.friends
              : FriendshipStatus.none,
        );
      }
    });
    _showSnack(msg, ok);
  }

  Future<void> _openChat() async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;
    setState(() => _actionLoading = true);
    final chat = await _chatService.createChat(friendId: widget.userId, token: token);
    if (!mounted) return;
    setState(() => _actionLoading = false);
    if (chat != null) {
      Navigator.of(context).pop();
      widget.onOpenChat?.call(chat);
    } else {
      _showSnack('Не удалось открыть чат', false);
    }
  }

  void _showSnack(String msg, bool ok) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: ok ? Colors.green.shade700 : Colors.red.shade700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.35,
      maxChildSize: 0.75,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: colors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentIndigo))
                  : _profile == null
                      ? Center(child: Text('Пользователь не найден', style: TextStyle(color: colors.textSecondary)))
                      : _buildContent(_profile!, controller),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(UserProfile p, ScrollController controller) {
    final colors = AppColors.of(context);
    final palette = [AppTheme.accentIndigo, Colors.teal, Colors.deepPurple, Colors.blueAccent, Colors.green];
    final color = palette[p.id % palette.length];

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        Center(
          child: CircleAvatar(
            radius: 42,
            backgroundColor: color.withValues(alpha: 0.18),
            child: Text(
              p.username.isNotEmpty ? p.username[0].toUpperCase() : '?',
              style: TextStyle(fontSize: 36, color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Center(
          child: Text(p.username,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colors.textPrimary)),
        ),
        if (p.bio != null && p.bio!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Center(
            child: Text(p.bio!, textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: colors.textSecondary)),
          ),
        ],
        const SizedBox(height: 6),
        Center(
          child: Text(
            'В Cove с ${_formatDate(p.memberSince)}',
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ),
        const SizedBox(height: 28),
        _buildActions(p),
      ],
    );
  }

  Widget _buildActions(UserProfile p) {
    if (_actionLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentIndigo),
        ),
      );
    }

    final status = p.friendshipStatus ?? FriendshipStatus.none;

    switch (status) {
      case FriendshipStatus.none:
        return _actionButton(
          icon: Icons.person_add_outlined,
          label: 'Добавить в друзья',
          color: AppTheme.accentIndigo,
          onTap: _addFriend,
        );
      case FriendshipStatus.pendingOutgoing:
        return _actionButton(
          icon: Icons.schedule,
          label: 'Заявка отправлена',
          color: Colors.grey,
          onTap: null,
        );
      case FriendshipStatus.pendingIncoming:
        return Row(
          children: [
            Expanded(
              child: _actionButton(
                icon: Icons.check_circle_outline,
                label: 'Принять',
                color: Colors.green,
                onTap: () => _respond('accepted'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _actionButton(
                icon: Icons.cancel_outlined,
                label: 'Отклонить',
                color: Colors.redAccent,
                onTap: () => _respond('declined'),
              ),
            ),
          ],
        );
      case FriendshipStatus.friends:
        return _actionButton(
          icon: Icons.chat_bubble_outline,
          label: 'Написать',
          color: AppTheme.accentIndigo,
          onTap: widget.onOpenChat != null ? _openChat : null,
        );
    }
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: onTap != null ? color.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.08),
        foregroundColor: onTap != null ? color : Colors.grey,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
    );
  }

  String _formatDate(DateTime dt) {
    const months = [
      'янв', 'фев', 'мар', 'апр', 'мая', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }
}
