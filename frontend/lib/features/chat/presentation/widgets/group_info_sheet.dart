import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart' show AppTheme, AppColors;
import '../../../auth/presentation/auth_notifier.dart';
import '../../data/models/chat.dart';
import '../../data/services/chat_service.dart';
import 'group_member_tile.dart';

class GroupInfoSheet extends StatefulWidget {
  final Chat chat;
  final void Function(Chat updated)? onGroupUpdated;
  final VoidCallback? onGroupLeft;
  final VoidCallback? onGroupDeleted;

  const GroupInfoSheet({
    super.key,
    required this.chat,
    this.onGroupUpdated,
    this.onGroupLeft,
    this.onGroupDeleted,
  });

  @override
  State<GroupInfoSheet> createState() => _GroupInfoSheetState();
}

class _GroupInfoSheetState extends State<GroupInfoSheet> {
  final ChatService _chatService = ChatService();
  List<GroupMember> _members = [];
  bool _isLoading = true;

  late Chat _chat;

  @override
  void initState() {
    super.initState();
    _chat = widget.chat;
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;
    final members = await _chatService.getGroupMembers(
      chatId: _chat.id,
      token: token,
    );
    if (mounted) {
      setState(() {
        _members = members;
        _isLoading = false;
      });
    }
  }

  int get _myUserId {
    final uid = context.read<AuthNotifier>().userId;
    return int.tryParse(uid ?? '') ?? 0;
  }

  Future<void> _handleKick(GroupMember member) async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;
    final ok = await _chatService.kickMember(
      chatId: _chat.id,
      userId: member.userId,
      token: token,
    );
    if (ok && mounted) {
      setState(() => _members.removeWhere((m) => m.userId == member.userId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("${member.username} исключён"),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleSetRole(GroupMember member, String role) async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;
    final ok = await _chatService.setMemberRole(
      chatId: _chat.id,
      userId: member.userId,
      role: role,
      token: token,
    );
    if (ok && mounted) {
      await _loadMembers();
    }
  }

  Future<void> _handleLeave() async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;

    final confirmed = await _confirmDialog(
      context,
      "Покинуть группу?",
      "Вы выйдете из группы «${_chat.groupName}».",
      confirmLabel: "Покинуть",
      isDangerous: true,
    );
    if (!confirmed) return;
    final ok = await _chatService.leaveGroup(chatId: _chat.id, token: token);
    if (ok && mounted) {
      Navigator.of(context).pop();
      widget.onGroupLeft?.call();
    }
  }

  Future<void> _handleDelete() async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;

    final confirmed = await _confirmDialog(
      context,
      "Удалить группу?",
      "Группа «${_chat.groupName}» будет удалена для всех участников.",
      confirmLabel: "Удалить",
      isDangerous: true,
    );
    if (!confirmed) return;
    final ok = await _chatService.deleteGroup(chatId: _chat.id, token: token);
    if (ok && mounted) {
      Navigator.of(context).pop();
      widget.onGroupDeleted?.call();
    }
  }

  Future<void> _handleRename() async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;

    final controller =
        TextEditingController(text: _chat.groupName ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.of(context).bg,
        title: Text("Переименовать группу",
            style:
                TextStyle(color: AppColors.of(context).textPrimary, fontSize: 16)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          style: TextStyle(color: AppColors.of(context).textPrimary),
          decoration: InputDecoration(
            hintText: "Название",
            hintStyle: TextStyle(color: AppColors.of(context).textSecondary),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Отмена")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text("Сохранить",
                  style: TextStyle(color: AppTheme.accentIndigo))),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    final updated = await _chatService.updateGroup(
      chatId: _chat.id,
      name: result,
      token: token,
    );
    if (updated != null && mounted) {
      setState(() => _chat = updated);
      widget.onGroupUpdated?.call(updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final myId = _myUserId;
    final isAdmin = _chat.isAdmin;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => Container(
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Аватар и название
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.teal.withValues(alpha: 0.2),
                    child: Text(
                      _chat.avatarInitial,
                      style: const TextStyle(
                          color: Colors.teal,
                          fontSize: 22,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _chat.groupName ?? '',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: colors.textPrimary),
                        ),
                        Text(
                          "${_chat.memberCount ?? _members.length} участников",
                          style: TextStyle(
                              fontSize: 13, color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (isAdmin)
                    IconButton(
                      icon: Icon(Icons.edit_outlined,
                          color: colors.textSecondary, size: 20),
                      tooltip: "Переименовать",
                      onPressed: _handleRename,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Список участников
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accentIndigo))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: _members.length,
                      itemBuilder: (_, i) {
                        final m = _members[i];
                        return GroupMemberTile(
                          member: m,
                          isCurrentUser: m.userId == myId,
                          canManage: isAdmin,
                          onKick: () => _handleKick(m),
                          onSetRole: (role) => _handleSetRole(m, role),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            // Кнопки действий
            Padding(
              padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: MediaQuery.of(context).padding.bottom + 12),
              child: Column(
                children: [
                  if (isAdmin)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _handleDelete,
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent, size: 18),
                        label: const Text("Удалить группу",
                            style: TextStyle(color: Colors.redAccent)),
                        style: OutlinedButton.styleFrom(
                          side:
                              const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _handleLeave,
                      icon: Icon(Icons.exit_to_app,
                          color: colors.textSecondary, size: 18),
                      label: Text("Покинуть группу",
                          style: TextStyle(color: colors.textSecondary)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                            color: colors.textSecondary.withValues(alpha: 0.4)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool> _confirmDialog(
  BuildContext context,
  String title,
  String content, {
  required String confirmLabel,
  bool isDangerous = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.of(context).bg,
      title: Text(title,
          style: TextStyle(
              color: AppColors.of(context).textPrimary, fontSize: 16)),
      content: Text(content,
          style: TextStyle(
              color: AppColors.of(context).textSecondary, fontSize: 14)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text("Отмена"),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            confirmLabel,
            style: TextStyle(
                color: isDangerous ? Colors.redAccent : AppTheme.accentIndigo),
          ),
        ),
      ],
    ),
  );
  return result == true;
}
