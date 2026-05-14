import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart' show AppTheme, AppColors;
import '../../auth/presentation/auth_notifier.dart';
import 'settings_notifier.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final notifier = context.watch<SettingsNotifier>();
    final s = notifier.settings;
    final username = auth.username ?? 'User';

    final colors = AppColors.of(context);
    return Container(
      color: colors.bg,
      child: ListView(
        padding: const EdgeInsets.all(32),
        children: [
          // ── Профиль ───────────────────────────────────────────────────────────
          _ProfileCard(username: username),
          const SizedBox(height: 28),

          // ── Внешний вид ───────────────────────────────────────────────────────
          _SectionHeader(title: 'Внешний вид'),
          const SizedBox(height: 12),
          _ThemePicker(
            current: s.theme,
            onChanged: (t) {
              final token = auth.token;
              if (token != null) notifier.updateTheme(token, t);
            },
          ),
          const SizedBox(height: 24),

          // ── Уведомления ───────────────────────────────────────────────────────
          _SectionHeader(title: 'Уведомления'),
          const SizedBox(height: 12),
          _ToggleTile(
            icon: Icons.notifications_outlined,
            title: 'Включить уведомления',
            subtitle: 'Получать пуши о новых сообщениях',
            value: s.notificationsEnabled,
            onChanged: (v) => _updatePref(context, auth, notifier, 'notifications_enabled', v),
          ),
          _ToggleTile(
            icon: Icons.preview_outlined,
            title: 'Предпросмотр сообщений',
            subtitle: 'Показывать текст в уведомлении',
            value: s.notificationPreview,
            onChanged: s.notificationsEnabled
                ? (v) => _updatePref(context, auth, notifier, 'notification_preview', v)
                : null,
          ),
          _ToggleTile(
            icon: Icons.do_not_disturb_on_outlined,
            title: 'Режим «Не беспокоить»',
            subtitle: 'Тихие часы: ${s.dndStart} — ${s.dndEnd}',
            value: s.dndEnabled,
            onChanged: (v) => _updatePref(context, auth, notifier, 'dnd_enabled', v),
          ),
          if (s.dndEnabled) ...[
            _DndTimePicker(
              label: 'Начало тихих часов',
              time: s.dndStart,
              onChanged: (t) => _updatePref(context, auth, notifier, 'dnd_start', t),
            ),
            _DndTimePicker(
              label: 'Конец тихих часов',
              time: s.dndEnd,
              onChanged: (t) => _updatePref(context, auth, notifier, 'dnd_end', t),
            ),
          ],
          const SizedBox(height: 24),

          // ── Приватность ───────────────────────────────────────────────────────
          _SectionHeader(title: 'Приватность'),
          const SizedBox(height: 12),
          _ToggleTile(
            icon: Icons.done_all_rounded,
            title: 'Галочки прочтения',
            subtitle: 'Собеседник видит, что вы прочли',
            value: s.readReceiptsEnabled,
            onChanged: (v) => _updatePref(context, auth, notifier, 'read_receipts_enabled', v),
          ),
          _ToggleTile(
            icon: Icons.keyboard_outlined,
            title: 'Индикатор набора текста',
            subtitle: 'Показывать «печатает...» собеседнику',
            value: s.typingIndicatorsEnabled,
            onChanged: (v) =>
                _updatePref(context, auth, notifier, 'typing_indicators_enabled', v),
          ),
          _ToggleTile(
            icon: Icons.circle_outlined,
            title: 'Онлайн-статус',
            subtitle: 'Другие пользователи видят, что вы в сети',
            value: s.onlineStatusVisible,
            onChanged: (v) =>
                _updatePref(context, auth, notifier, 'online_status_visible', v),
          ),
          const SizedBox(height: 24),

          // ── О приложении ──────────────────────────────────────────────────────
          _SectionHeader(title: 'О приложении'),
          const SizedBox(height: 12),
          _InfoTile(icon: Icons.info_outline, title: 'Версия', value: 'Cove v0.1.0'),
          _InfoTile(
              icon: Icons.shield_outlined,
              title: 'Безопасность',
              value: 'JWT · HS256 · 24ч'),
          const SizedBox(height: 32),

          // ── Выход ─────────────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.08),
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              onPressed: () =>
                  Provider.of<AuthNotifier>(context, listen: false).logout(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Выйти из аккаунта',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _updatePref(
    BuildContext context,
    AuthNotifier auth,
    SettingsNotifier notifier,
    String key,
    dynamic value,
  ) {
    final token = auth.token;
    if (token != null) notifier.updatePref(token, key, value);
  }
}

// ── Вспомогательные виджеты ───────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  final String username;
  const _ProfileCard({required this.username});

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
            radius: 35,
            backgroundColor: AppTheme.accentIndigo,
            child: Text(
              username.isNotEmpty ? username[0].toUpperCase() : 'U',
              style: const TextStyle(
                  fontSize: 28,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 20),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(username,
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary)),
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                        color: Colors.greenAccent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Text('В сети',
                      style: TextStyle(
                          color: colors.textSecondary, fontSize: 14)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: colors.textSecondary,
        letterSpacing: 1.2,
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        secondary: Icon(icon, color: AppTheme.accentIndigo, size: 24),
        title: Text(title,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: onChanged == null
                    ? colors.textSecondary
                    : colors.textPrimary)),
        subtitle: Text(subtitle,
            style: TextStyle(fontSize: 12, color: colors.textSecondary)),
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
        leading:
            const Icon(Icons.access_time, color: AppTheme.accentIndigo, size: 24),
        title: Text(label,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary)),
        trailing: Text(time,
            style: const TextStyle(
                color: AppTheme.accentIndigo,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        onTap: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: tod,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(alwaysUse24HourFormat: true),
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
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary)),
          const Spacer(),
          Text(value,
              style: TextStyle(fontSize: 14, color: colors.textSecondary)),
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
              const Icon(Icons.palette_outlined,
                  color: AppTheme.accentIndigo, size: 24),
              const SizedBox(width: 18),
              Text('Тема оформления',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary)),
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
              Icon(icon,
                  color: selected ? AppTheme.accentIndigo : colors.textSecondary,
                  size: 22),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 13,
                    color: selected ? AppTheme.accentIndigo : colors.textSecondary,
                    fontWeight: selected
                        ? FontWeight.w600
                        : FontWeight.normal,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
