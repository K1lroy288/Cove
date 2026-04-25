import 'package:flutter/material.dart';
import '../../../shared/theme/app_theme.dart';

class ChatWindowPanel extends StatelessWidget {
  final String chatId;      // ID чата, который нужно открыть
  final VoidCallback onBack; // Функция для закрытия чата (возврата к дашборду)

  const ChatWindowPanel({
    super.key,
    required this.chatId,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Шапка чата
        AppBar(
          // Кнопка назад (появится автоматически на мобилках)
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: onBack,
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chatId, style: const TextStyle(fontSize: 16)), // В будущем тут будет имя юзера
              const Text("в сети", style: TextStyle(fontSize: 12, color: Colors.greenAccent)),
            ],
          ),
          centerTitle: false,
          actions: [
            IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () {}),
            IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
          ],
        ),

        // Область сообщений
        Expanded(
          child: Container(
            color: AppTheme.darkBg,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildMessage("Привет! Это чат $chatId", false),
                _buildNestedThread("Обсуждение внутри ветки..."),
              ],
            ),
          ),
        ),

        // Поле ввода
        _buildInputArea(),
      ],
    );
  }

  Widget _buildMessage(String text, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text),
      ),
    );
  }

  Widget _buildNestedThread(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 40, top: 8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accentIndigo.withOpacity(0.2),
              blurRadius: 10,
              spreadRadius: 1,
            )
          ],
        ),
        child: _buildMessage(text, false),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: AppTheme.darkBg,
      child: TextField(
        decoration: InputDecoration(
          hintText: "Написать сообщение...",
          prefixIcon: const Icon(Icons.add_circle_outline, color: AppTheme.accentIndigo),
          suffixIcon: const Icon(Icons.mic_none, color: AppTheme.accentIndigo),
          filled: true,
          fillColor: AppTheme.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}