class UserSettings {
  final String theme;
  final String locale;
  final Map<String, dynamic> preferences;

  const UserSettings({
    required this.theme,
    required this.locale,
    required this.preferences,
  });

  factory UserSettings.defaults() => const UserSettings(
        theme: 'dark',
        locale: 'ru',
        preferences: {},
      );

  factory UserSettings.fromJson(Map<String, dynamic> json) => UserSettings(
        theme: json['theme'] as String? ?? 'dark',
        locale: json['locale'] as String? ?? 'ru',
        preferences: (json['preferences'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toJson() => {
        'theme': theme,
        'locale': locale,
        'preferences': preferences,
      };

  // ── Уведомления ──────────────────────────────────────────────────────────
  bool get notificationsEnabled =>
      preferences['notifications_enabled'] as bool? ?? true;
  bool get notificationPreview =>
      preferences['notification_preview'] as bool? ?? true;
  bool get dndEnabled => preferences['dnd_enabled'] as bool? ?? false;
  String get dndStart => preferences['dnd_start'] as String? ?? '23:00';
  String get dndEnd => preferences['dnd_end'] as String? ?? '08:00';
  bool get notificationSound =>
      preferences['notification_sound'] as bool? ?? true;
  bool get notificationVibration =>
      preferences['notification_vibration'] as bool? ?? true;
  bool get notifyFriendsOnly =>
      preferences['notify_friends_only'] as bool? ?? false;

  // ── Чат ──────────────────────────────────────────────────────────────────
  bool get sendOnEnter => preferences['send_on_enter'] as bool? ?? true;
  String get chatFontSize =>
      preferences['chat_font_size'] as String? ?? 'medium';
  bool get showMessageTime =>
      preferences['show_message_time'] as bool? ?? true;
  bool get compactChat => preferences['compact_chat'] as bool? ?? false;

  // ── Внешний вид ───────────────────────────────────────────────────────────
  String get uiDensity => preferences['ui_density'] as String? ?? 'normal';
  bool get showAvatars => preferences['show_avatars'] as bool? ?? true;
  bool get use24hTime => preferences['use_24h_time'] as bool? ?? true;

  // ── Приватность ───────────────────────────────────────────────────────────
  bool get onlineStatusVisible =>
      preferences['online_status_visible'] as bool? ?? true;
  String get groupInvitePolicy =>
      preferences['group_invite_policy'] as String? ?? 'everyone';
  bool get confirmGroupInvite =>
      preferences['confirm_group_invite'] as bool? ?? false;

  // ── Computed (не сохраняются) ─────────────────────────────────────────────
  double get chatFontSizeValue => switch (chatFontSize) {
        'small' => 13.0,
        'large' => 16.0,
        _ => 14.0,
      };

  double get uiDensityPadding => switch (uiDensity) {
        'compact' => 8.0,
        'comfortable' => 18.0,
        _ => 12.0,
      };

  UserSettings copyWithTheme(String t) =>
      UserSettings(theme: t, locale: locale, preferences: preferences);

  UserSettings copyWithPref(String key, dynamic value) {
    final p = Map<String, dynamic>.from(preferences);
    p[key] = value;
    return UserSettings(theme: theme, locale: locale, preferences: p);
  }
}

class ChatNotifSettings {
  final bool muted;
  final DateTime? muteUntil;
  final int notifyLevel;

  const ChatNotifSettings({
    required this.muted,
    this.muteUntil,
    required this.notifyLevel,
  });

  factory ChatNotifSettings.defaults() =>
      const ChatNotifSettings(muted: false, notifyLevel: 0);

  factory ChatNotifSettings.fromJson(Map<String, dynamic> json) =>
      ChatNotifSettings(
        muted: json['muted'] as bool? ?? false,
        muteUntil: json['mute_until'] == null
            ? null
            : DateTime.parse(json['mute_until'] as String),
        notifyLevel: json['notify_level'] as int? ?? 0,
      );
}
