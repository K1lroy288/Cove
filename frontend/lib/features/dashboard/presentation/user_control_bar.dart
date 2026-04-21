import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../shared/services/auth_notifier.dart';

class UserControlBar extends StatelessWidget {
  const UserControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    // 🔥 Consumer — виджет-слушатель.
    // Он автоматически перестраивается, когда в AuthNotifier меняется состояние.
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
                  // 🔥 Здесь берем username из auth (наш AuthNotifier)
                  // Если null — показываем "Загрузка..."
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
              // Кнопка выхода для теста
              IconButton(
                icon: const Icon(Icons.logout, size: 20), 
                onPressed: () => auth.logout(),
                tooltip: 'Выйти',
              ),
            ],
          ),
        );
      },
    );
  }
}