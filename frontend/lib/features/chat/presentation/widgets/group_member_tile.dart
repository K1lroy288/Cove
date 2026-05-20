import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart' show AppTheme, AppColors;
import '../../data/models/chat.dart';

class GroupMemberTile extends StatelessWidget {
  final GroupMember member;
  final bool isCurrentUser;
  final bool canManage; // текущий пользователь — admin
  final VoidCallback? onKick;
  final void Function(String role)? onSetRole;

  const GroupMemberTile({
    super.key,
    required this.member,
    this.isCurrentUser = false,
    this.canManage = false,
    this.onKick,
    this.onSetRole,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: member.isAdmin
            ? Colors.teal.withValues(alpha: 0.2)
            : AppTheme.accentIndigo.withValues(alpha: 0.15),
        child: Text(
          member.username[0].toUpperCase(),
          style: TextStyle(
            color: member.isAdmin ? Colors.teal : AppTheme.accentIndigo,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
      ),
      title: Row(
        children: [
          Text(
            member.username + (isCurrentUser ? " (вы)" : ""),
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary),
          ),
          const SizedBox(width: 6),
          if (member.isAdmin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                "admin",
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.teal,
                    fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      trailing: canManage && !isCurrentUser
          ? PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: colors.textSecondary, size: 18),
              color: colors.surface,
              itemBuilder: (_) => [
                if (!member.isAdmin)
                  PopupMenuItem(
                    value: 'promote',
                    child: Text("Сделать администратором",
                        style: TextStyle(
                            fontSize: 13, color: colors.textPrimary)),
                  ),
                if (member.isAdmin)
                  PopupMenuItem(
                    value: 'demote',
                    child: Text("Снять права администратора",
                        style: TextStyle(
                            fontSize: 13, color: colors.textPrimary)),
                  ),
                PopupMenuItem(
                  value: 'kick',
                  child: const Text("Исключить",
                      style: TextStyle(
                          fontSize: 13, color: Colors.redAccent)),
                ),
              ],
              onSelected: (value) {
                if (value == 'kick') {
                  onKick?.call();
                } else if (value == 'promote') {
                  onSetRole?.call('admin');
                } else if (value == 'demote') {
                  onSetRole?.call('member');
                }
              },
            )
          : null,
    );
  }
}
