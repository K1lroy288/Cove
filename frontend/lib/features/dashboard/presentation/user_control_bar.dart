import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/services/auth_notifier.dart';
import '../../auth/presentation/auth_screen.dart'; // ← Импорт экрана входа

class UserControlBar extends StatelessWidget {
  const UserControlBar({super.key});

  // 🔥 Выносим логику выхода в отдельный метод для чистоты кода
  void _handleLogout(BuildContext context, AuthNotifier auth) async {
    // 1. Очищаем состояние (в памяти + позже в хранилище)
    await auth.logout();
    
    // 2. Перенаправляем на экран входа и удаляем всю историю навигации
    // pushAndRemoveUntil удаляет все предыдущие экраны из стека
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const AuthScreen()),
        (route) => false, // false = удалить ВСЕ предыдущие маршруты
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthNotifier>(
      builder: (context, auth, child) {
        return Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF292B2F),
            border: Border(top: BorderSide(color: Colors.grey[800]!)),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 20, 
                backgroundColor: Color(0xFF5865F2), 
                child: Icon(Icons.person, color: Colors.white)
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.username ?? 'Пользователь', 
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    auth.isAuthenticated ? 'В сети' : 'Не в сети', 
                    style: TextStyle(
                      color: auth.isAuthenticated ? Colors.green : Colors.grey, 
                      fontSize: 12
                    ),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(icon: const Icon(Icons.mic), onPressed: () {}),
              IconButton(icon: const Icon(Icons.headphones), onPressed: () {}),
              IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
              
              // 🔥 Кнопка выхода с правильной навигацией
              IconButton(
                icon: const Icon(Icons.logout, size: 20), 
                onPressed: () => _handleLogout(context, auth),
                tooltip: 'Выйти',
              ),
            ],
          ),
        );
      },
    );
  }
}