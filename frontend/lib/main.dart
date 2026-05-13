import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/presentation/auth_notifier.dart';
import 'features/auth/presentation/auth_screen.dart';
import 'features/chat/presentation/main_screen.dart';
import 'features/chat/presentation/notification_notifier.dart';
import 'features/voice/presentation/voice_notifier.dart';

void main() {
  final authNotifier = AuthNotifier();
  final notifNotifier = NotificationNotifier();

  authNotifier.addListener(() {
    if (authNotifier.isAuthenticated && authNotifier.token != null) {
      notifNotifier.connect(authNotifier.token!);
    } else {
      notifNotifier.disconnect();
    }
  });

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authNotifier),
        ChangeNotifierProvider(create: (_) => VoiceNotifier()),
        ChangeNotifierProvider.value(value: notifNotifier),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cove',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
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
