import 'package:flutter/foundation.dart';
import '../data/models/user_settings.dart';
import '../data/services/settings_service.dart';

class SettingsNotifier extends ChangeNotifier {
  final SettingsService _service = SettingsService();

  UserSettings _settings = UserSettings.defaults();
  bool _isLoading = false;

  UserSettings get settings => _settings;
  bool get isLoading => _isLoading;
  String get theme => _settings.theme;

  Future<void> load(String token) async {
    _isLoading = true;
    notifyListeners();
    final result = await _service.getSettings(token: token);
    _settings = result ?? UserSettings.defaults();
    _isLoading = false;
    notifyListeners();
  }

  void clear() {
    _settings = UserSettings.defaults();
    notifyListeners();
  }

  Future<void> updateTheme(String token, String theme) async {
    // Оптимистичное обновление
    _settings = _settings.copyWithTheme(theme);
    notifyListeners();
    await _service.updateSettings(token: token, theme: theme);
  }

  Future<void> updatePref(String token, String key, dynamic value) async {
    _settings = _settings.copyWithPref(key, value);
    notifyListeners();
    await _service.updateSettings(
      token: token,
      preferences: {key: value},
    );
  }
}
