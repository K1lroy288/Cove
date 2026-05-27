import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart' show AppTheme, AppColors;
import '../../auth/presentation/auth_notifier.dart';
import '../../user/data/models/user_profile.dart';
import '../../user/data/services/user_service.dart';
import 'settings_notifier.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final UserService _userService = UserService();
  UserProfile? _myProfile;
  String? _openCategory;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  Future<void> _loadProfile() async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;
    final p = await _userService.getMe(token);
    if (mounted) setState(() => _myProfile = p);
  }

  Future<void> _showEditDialog() async {
    final auth = context.read<AuthNotifier>();
    final token = auth.token;
    if (token == null) return;

    final usernameCtrl = TextEditingController(text: auth.username ?? '');
    final bioCtrl = TextEditingController(text: _myProfile?.bio ?? '');
    bool saving = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Редактировать профиль'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(labelText: 'Имя пользователя'),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bioCtrl,
                decoration: InputDecoration(
                  labelText: 'О себе',
                  hintText: 'Расскажите о себе...',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.emoji_emotions_outlined, size: 20),
                    onPressed: () => _showEmojiSheet(ctx, bioCtrl),
                  ),
                ),
                maxLines: 3,
                maxLength: 500,
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final newUsername = usernameCtrl.text.trim();
                      final newBio = bioCtrl.text.trim();
                      if (newUsername.length < 2) {
                        setS(() => error = 'Имя слишком короткое');
                        return;
                      }
                      setS(() {
                        saving = true;
                        error = null;
                      });
                      final updated = await _userService.updateProfile(
                        token,
                        username: newUsername != auth.username ? newUsername : null,
                        bio: newBio,
                      );
                      if (!ctx.mounted || !mounted) return;
                      if (updated != null) {
                        context.read<AuthNotifier>().updateUsername(updated.username);
                        setState(() => _myProfile = updated);
                        Navigator.pop(ctx);
                      } else {
                        setS(() {
                          saving = false;
                          error = 'Имя уже занято или ошибка сервера';
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPasswordDialog() async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;

    final curCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool saving = false;
    String? error;
    bool obscureCur = true;
    bool obscureNew = true;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Сменить пароль'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: curCtrl,
                obscureText: obscureCur,
                decoration: InputDecoration(
                  labelText: 'Текущий пароль',
                  suffixIcon: IconButton(
                    icon: Icon(obscureCur
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setS(() => obscureCur = !obscureCur),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newCtrl,
                obscureText: obscureNew,
                decoration: InputDecoration(
                  labelText: 'Новый пароль',
                  suffixIcon: IconButton(
                    icon: Icon(obscureNew
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setS(() => obscureNew = !obscureNew),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Повторите новый пароль'),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (newCtrl.text != confirmCtrl.text) {
                        setS(() => error = 'Пароли не совпадают');
                        return;
                      }
                      if (newCtrl.text.length < 6) {
                        setS(() => error = 'Минимум 6 символов');
                        return;
                      }
                      setS(() {
                        saving = true;
                        error = null;
                      });
                      final (ok, msg) = await _userService.changePassword(
                        token,
                        currentPassword: curCtrl.text,
                        newPassword: newCtrl.text,
                      );
                      if (!ctx.mounted) return;
                      if (ok) {
                        Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(msg),
                              backgroundColor: Colors.green.shade700,
                            ),
                          );
                        }
                      } else {
                        setS(() {
                          saving = false;
                          error = msg;
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Сменить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteDialog() async {
    final auth = context.read<AuthNotifier>();
    final token = auth.token;
    if (token == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить аккаунт?'),
        content: const Text('Все ваши данные будут удалены. Это действие необратимо.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ok = await _userService.deleteAccount(token);
    if (!mounted) return;
    if (ok) {
      context.read<AuthNotifier>().logout();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ошибка при удалении аккаунта'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  void _showEmojiSheet(BuildContext ctx, TextEditingController ctrl) {
    final colors = AppColors.of(ctx);
    showModalBottomSheet(
      context: ctx,
      builder: (_) => SizedBox(
        height: 300,
        child: EmojiPicker(
          textEditingController: ctrl,
          config: AppTheme.emojiPickerConfig(colors, height: 300),
        ),
      ),
    );
  }

  void _updatePref(
    AuthNotifier auth,
    SettingsNotifier notifier,
    String key,
    dynamic value,
  ) {
    final token = auth.token;
    if (token != null) notifier.updatePref(token, key, value);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final colors = AppColors.of(context);

    return Container(
      color: colors.bg,
      child: _openCategory == null
          ? _buildMainPage(auth, colors)
          : _buildCategoryPage(auth, colors),
    );
  }

  // ── Главная страница ──────────────────────────────────────────────────────────

  Widget _buildMainPage(AuthNotifier auth, AppColors colors) {
    final username = auth.username ?? 'User';

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        _ProfileCard(
          username: username,
          bio: _myProfile?.bio,
          onEdit: _showEditDialog,
        ),
        const SizedBox(height: 24),
        _CategoryTile(
          icon: Icons.chat_bubble_outline,
          label: 'Настройки чата',
          category: 'chat',
          onTap: (c) => setState(() => _openCategory = c),
        ),
        _CategoryTile(
          icon: Icons.notifications_outlined,
          label: 'Уведомления',
          category: 'notifications',
          onTap: (c) => setState(() => _openCategory = c),
        ),
        _CategoryTile(
          icon: Icons.shield_outlined,
          label: 'Безопасность',
          category: 'security',
          onTap: (c) => setState(() => _openCategory = c),
        ),
        _CategoryTile(
          icon: Icons.palette_outlined,
          label: 'Внешний вид',
          category: 'appearance',
          onTap: (c) => setState(() => _openCategory = c),
        ),
        _CategoryTile(
          icon: Icons.visibility_outlined,
          label: 'Приватность',
          category: 'privacy',
          onTap: (c) => setState(() => _openCategory = c),
        ),
        _CategoryTile(
          icon: Icons.info_outlined,
          label: 'О приложении',
          category: 'about',
          onTap: (c) => setState(() => _openCategory = c),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent.withValues(alpha: 0.08),
              foregroundColor: Colors.redAccent,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 0,
            ),
            onPressed: () => Provider.of<AuthNotifier>(context, listen: false).logout(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text(
              'Выйти из аккаунта',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  // ── Страница категории ────────────────────────────────────────────────────────

  Widget _buildCategoryPage(AuthNotifier auth, AppColors colors) {
    final notifier = context.watch<SettingsNotifier>();
    final s = notifier.settings;

    final (title, content) = switch (_openCategory) {
      'chat' => (
          'Настройки чата',
          <Widget>[
            _ToggleTile(
              icon: Icons.send_outlined,
              title: 'Отправка по Enter',
              subtitle: 'Shift+Enter для новой строки',
              value: s.sendOnEnter,
              onChanged: (v) => _updatePref(auth, notifier, 'send_on_enter', v),
            ),
            _SegmentedPicker(
              icon: Icons.format_size_rounded,
              title: 'Размер шрифта',
              options: const [
                (value: 'small', label: 'А−'),
                (value: 'medium', label: 'А'),
                (value: 'large', label: 'А+'),
              ],
              current: s.chatFontSize,
              onChanged: (v) => _updatePref(auth, notifier, 'chat_font_size', v),
            ),
            _ToggleTile(
              icon: Icons.access_time_outlined,
              title: 'Метки времени',
              subtitle: 'Показывать время рядом с каждым сообщением',
              value: s.showMessageTime,
              onChanged: (v) => _updatePref(auth, notifier, 'show_message_time', v),
            ),
            _ToggleTile(
              icon: Icons.compress_rounded,
              title: 'Компактный вид',
              subtitle: 'Убирает отступы между сообщениями одного человека',
              value: s.compactChat,
              onChanged: (v) => _updatePref(auth, notifier, 'compact_chat', v),
            ),
          ],
        ),
      'notifications' => (
          'Уведомления',
          <Widget>[
            _ToggleTile(
              icon: Icons.notifications_outlined,
              title: 'Включить уведомления',
              subtitle: 'Получать пуши о новых сообщениях',
              value: s.notificationsEnabled,
              onChanged: (v) => _updatePref(auth, notifier, 'notifications_enabled', v),
            ),
            _ToggleTile(
              icon: Icons.preview_outlined,
              title: 'Предпросмотр сообщений',
              subtitle: 'Показывать текст в уведомлении',
              value: s.notificationPreview,
              onChanged: s.notificationsEnabled
                  ? (v) => _updatePref(auth, notifier, 'notification_preview', v)
                  : null,
            ),
            _ToggleTile(
              icon: Icons.do_not_disturb_on_outlined,
              title: 'Режим «Не беспокоить»',
              subtitle: 'Тихие часы: ${s.dndStart} — ${s.dndEnd}',
              value: s.dndEnabled,
              onChanged: (v) => _updatePref(auth, notifier, 'dnd_enabled', v),
            ),
            if (s.dndEnabled) ...[
              _DndTimePicker(
                label: 'Начало тихих часов',
                time: s.dndStart,
                onChanged: (t) => _updatePref(auth, notifier, 'dnd_start', t),
              ),
              _DndTimePicker(
                label: 'Конец тихих часов',
                time: s.dndEnd,
                onChanged: (t) => _updatePref(auth, notifier, 'dnd_end', t),
              ),
            ],
            _ToggleTile(
              icon: Icons.volume_up_outlined,
              title: 'Звук уведомлений',
              subtitle: 'Проигрывать звук при новом сообщении',
              value: s.notificationSound,
              onChanged: s.notificationsEnabled
                  ? (v) => _updatePref(auth, notifier, 'notification_sound', v)
                  : null,
            ),
            _ToggleTile(
              icon: Icons.vibration_rounded,
              title: 'Вибрация',
              subtitle: 'Вибрировать при новом уведомлении',
              value: s.notificationVibration,
              onChanged: s.notificationsEnabled
                  ? (v) => _updatePref(auth, notifier, 'notification_vibration', v)
                  : null,
            ),
            _ToggleTile(
              icon: Icons.people_outline,
              title: 'Только от друзей',
              subtitle: 'Не показывать уведомления от незнакомых',
              value: s.notifyFriendsOnly,
              onChanged: (v) => _updatePref(auth, notifier, 'notify_friends_only', v),
            ),
          ],
        ),
      'security' => (
          'Безопасность',
          <Widget>[
            _ActionTile(
              icon: Icons.lock_outline,
              label: 'Сменить пароль',
              onTap: _showPasswordDialog,
            ),
            _ActionTile(
              icon: Icons.delete_outline,
              label: 'Удалить аккаунт',
              onTap: _showDeleteDialog,
              color: Colors.redAccent,
            ),
          ],
        ),
      'appearance' => (
          'Внешний вид',
          <Widget>[
            _ThemePicker(
              current: s.theme,
              onChanged: (t) {
                final token = auth.token;
                if (token != null) notifier.updateTheme(token, t);
              },
            ),
            const SizedBox(height: 4),
            _SegmentedPicker(
              icon: Icons.density_medium_rounded,
              title: 'Плотность интерфейса',
              options: const [
                (value: 'compact', label: 'Компакт'),
                (value: 'normal', label: 'Обычный'),
                (value: 'comfortable', label: 'Просторный'),
              ],
              current: s.uiDensity,
              onChanged: (v) => _updatePref(auth, notifier, 'ui_density', v),
            ),
            _ToggleTile(
              icon: Icons.account_circle_outlined,
              title: 'Аватары в чате',
              subtitle: 'Показывать аватары отправителей в сообщениях',
              value: s.showAvatars,
              onChanged: (v) => _updatePref(auth, notifier, 'show_avatars', v),
            ),
            _ToggleTile(
              icon: Icons.schedule_outlined,
              title: '24-часовой формат',
              subtitle: '15:00 вместо 3:00 PM',
              value: s.use24hTime,
              onChanged: (v) => _updatePref(auth, notifier, 'use_24h_time', v),
            ),
          ],
        ),
      'privacy' => (
          'Приватность',
          <Widget>[
            _ToggleTile(
              icon: Icons.circle_outlined,
              title: 'Онлайн-статус',
              subtitle: 'Другие пользователи видят, что вы в сети',
              value: s.onlineStatusVisible,
              onChanged: (v) => _updatePref(auth, notifier, 'online_status_visible', v),
            ),
            _SegmentedPicker(
              icon: Icons.group_outlined,
              title: 'Добавление в группы',
              options: const [
                (value: 'everyone', label: 'Все'),
                (value: 'friends', label: 'Только друзья'),
              ],
              current: s.groupInvitePolicy,
              onChanged: (v) => _updatePref(auth, notifier, 'group_invite_policy', v),
            ),
            _ToggleTile(
              icon: Icons.mark_email_unread_outlined,
              title: 'Подтверждение приглашений',
              subtitle: 'Спрашивать перед вступлением в новую группу',
              value: s.confirmGroupInvite,
              onChanged: (v) => _updatePref(auth, notifier, 'confirm_group_invite', v),
            ),
          ],
        ),
      'about' => (
          'О приложении',
          <Widget>[
            _InfoTile(icon: Icons.info_outline, title: 'Версия', value: 'Cove v0.1.0'),
            _InfoTile(
              icon: Icons.shield_outlined,
              title: 'Безопасность',
              value: 'JWT · HS256 · 24ч',
            ),
            _ActionTile(
              icon: Icons.article_outlined,
              label: 'Лицензии',
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Cove',
                applicationVersion: '0.1.0',
              ),
            ),
          ],
        ),
      _ => ('', <Widget>[]),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CategoryHeader(
          title: title,
          onBack: () => setState(() => _openCategory = null),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
            children: content,
          ),
        ),
      ],
    );
  }
}

// ── Вспомогательные виджеты ───────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final String username;
  final String? bio;
  final VoidCallback onEdit;

  const _ProfileCard({
    required this.username,
    required this.onEdit,
    this.bio,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: AppTheme.accentIndigo,
            child: Text(
              username.isNotEmpty ? username[0].toUpperCase() : 'U',
              style: const TextStyle(
                  fontSize: 26, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary),
                ),
                if (bio != null && bio!.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    bio!,
                    style: TextStyle(fontSize: 13, color: colors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ] else ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'В сети',
                        style: TextStyle(color: colors.textSecondary, fontSize: 13),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onEdit,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.accentIndigo.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.edit_outlined, color: AppTheme.accentIndigo, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String category;
  final ValueChanged<String> onTap;

  const _CategoryTile({
    required this.icon,
    required this.label,
    required this.category,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.accentIndigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppTheme.accentIndigo, size: 20),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: colors.textSecondary, size: 20),
        onTap: () => onTap(category),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  const _CategoryHeader({required this.title, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 20, 28, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            color: colors.textPrimary,
            onPressed: onBack,
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final c = color ?? colors.textPrimary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        leading: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: c, size: 20),
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: c,
          ),
        ),
        trailing: Icon(Icons.chevron_right_rounded, color: colors.textSecondary, size: 20),
        onTap: onTap,
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        secondary: Icon(icon, color: AppTheme.accentIndigo, size: 24),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: onChanged == null ? colors.textSecondary : colors.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppTheme.accentIndigo,
        activeTrackColor: AppTheme.accentIndigo.withValues(alpha: 0.4),
      ),
    );
  }
}

class _DndTimePicker extends StatelessWidget {
  final String label;
  final String time;
  final ValueChanged<String> onChanged;

  const _DndTimePicker({
    required this.label,
    required this.time,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final parts = time.split(':');
    final tod = TimeOfDay(
      hour: int.tryParse(parts[0]) ?? 0,
      minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
    );

    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: const Icon(Icons.access_time, color: AppTheme.accentIndigo, size: 24),
        title: Text(
          label,
          style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary),
        ),
        trailing: Text(
          time,
          style: const TextStyle(
              color: AppTheme.accentIndigo, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: tod,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
              child: child!,
            ),
          );
          if (picked != null) {
            final h = picked.hour.toString().padLeft(2, '0');
            final m = picked.minute.toString().padLeft(2, '0');
            onChanged('$h:$m');
          }
        },
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accentIndigo, size: 24),
          const SizedBox(width: 18),
          Text(
            title,
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600, color: colors.textPrimary),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SegmentedPicker extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<({String value, String label})> options;
  final String current;
  final ValueChanged<String> onChanged;

  const _SegmentedPicker({
    required this.icon,
    required this.title,
    required this.options,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppTheme.accentIndigo, size: 22),
              const SizedBox(width: 14),
              Text(
                title,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: options.map((opt) {
              final selected = opt.value == current;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(opt.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(
                        right: opt == options.last ? 0 : 6),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppTheme.accentIndigo
                          : AppTheme.accentIndigo.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Text(
                        opt.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ThemePicker extends StatelessWidget {
  final String current;
  final ValueChanged<String> onChanged;

  const _ThemePicker({required this.current, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.palette_outlined, color: AppTheme.accentIndigo, size: 24),
              const SizedBox(width: 18),
              Text(
                'Тема оформления',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _ThemeOption(
                label: 'Тёмная',
                icon: Icons.dark_mode_outlined,
                selected: current == 'dark',
                onTap: () => onChanged('dark'),
              ),
              const SizedBox(width: 10),
              _ThemeOption(
                label: 'Светлая',
                icon: Icons.light_mode_outlined,
                selected: current == 'light',
                onTap: () => onChanged('light'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.accentIndigo.withValues(alpha: 0.15)
                : Colors.transparent,
            border: Border.all(
              color: selected ? AppTheme.accentIndigo : colors.divider,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: selected ? AppTheme.accentIndigo : colors.textSecondary,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: selected ? AppTheme.accentIndigo : colors.textSecondary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
