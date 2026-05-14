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

  bool get notificationsEnabled =>
      preferences['notifications_enabled'] as bool? ?? true;
  bool get notificationPreview =>
      preferences['notification_preview'] as bool? ?? true;
  bool get dndEnabled => preferences['dnd_enabled'] as bool? ?? false;
  String get dndStart => preferences['dnd_start'] as String? ?? '23:00';
  String get dndEnd => preferences['dnd_end'] as String? ?? '08:00';
  bool get readReceiptsEnabled =>
      preferences['read_receipts_enabled'] as bool? ?? true;
  bool get typingIndicatorsEnabled =>
      preferences['typing_indicators_enabled'] as bool? ?? true;
  bool get onlineStatusVisible =>
      preferences['online_status_visible'] as bool? ?? true;

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
