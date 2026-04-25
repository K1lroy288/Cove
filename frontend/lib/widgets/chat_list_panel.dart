import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';

class ChatListPanel extends StatelessWidget {
  final Function(String) onChatSelected; // Добавляем коллбэк

  const ChatListPanel({super.key, required this.onChatSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.darkBg,
      child: ListView.builder(
        itemCount: 20,
        itemBuilder: (context, index) {
          return ListTile(
            onTap: () => onChatSelected("chat_$index"), // Передаем ID чата
            leading: const CircleAvatar(backgroundColor: AppTheme.surface, child: Icon(Icons.person)),
            title: Text("Пользователь $index"),
            subtitle: const Text("Последнее сообщение...", maxLines: 1),
          );
        },
      ),
    );
  }
}