import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_notifier.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/chat/presentation/main_screen.dart';
import 'features/chat/presentation/notification_notifier.dart';
import 'features/settings/presentation/settings_notifier.dart';
import 'features/voice/presentation/voice_notifier.dart';

void main() {
  final authNotifier = AuthNotifier();
  final notifNotifier = NotificationNotifier();
  final settingsNotifier = SettingsNotifier();

  authNotifier.addListener(() {
    if (authNotifier.isAuthenticated && authNotifier.token != null) {
      notifNotifier.connect(authNotifier.token!);
      settingsNotifier.load(authNotifier.token!);
    } else {
      notifNotifier.disconnect();
      settingsNotifier.clear();
    }
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authNotifier),
        ChangeNotifierProvider(create: (_) => VoiceNotifier()),
        ChangeNotifierProvider.value(value: notifNotifier),
        ChangeNotifierProvider.value(value: settingsNotifier),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<SettingsNotifier>().theme;
    return MaterialApp(
      title: 'Cove',
      debugShowCheckedModeBanner: false,
      theme: theme == 'light' ? AppTheme.lightTheme : AppTheme.darkTheme,
      home: Consumer<AuthNotifier>(
        builder: (context, auth, _) {
          return auth.isAuthenticated
              ? const MainScreen()
              : const AuthScreen();
        },
      ),
    );
  }
}
