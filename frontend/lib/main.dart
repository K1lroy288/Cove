import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // ← Импортируем provider
import 'shared/theme/app_theme.dart';
import 'shared/services/auth_notifier.dart'; // ← Импортируем наш нотифаер
import 'features/auth/presentation/auth_screen.dart';

void main() {
  runApp(
    // Оборачиваем приложение в ChangeNotifierProvider
    ChangeNotifierProvider(
      create: (context) => AuthNotifier(), // Создаём экземпляр
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
      home: const AuthScreen(),
    );
  }
}