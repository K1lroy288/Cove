import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Твои существующие импорты
import 'shared/theme/app_theme.dart';
import 'shared/services/auth_notifier.dart';
import 'features/auth/presentation/auth_screen.dart';

// Новый импорт для главного экрана
import 'screens/main_screen.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => AuthNotifier(),
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
      // Используем твою общую тему из shared/theme/app_theme.dart
      theme: AppTheme.darkTheme, 
      
      // Используем Consumer, чтобы автоматически переключать экраны,
      // когда AuthNotifier вызовет notifyListeners()
      home: Consumer<AuthNotifier>(
        builder: (context, auth, _) {
          // Если пользователь авторизован — показываем новый адаптивный MainScreen
          // Если нет — отправляем на AuthScreen
          if (auth.isAuthenticated) {
            return const MainScreen();
          } else {
            return const AuthScreen();
          }
        },
      ),
    );
  }
}