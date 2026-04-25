import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';

class ChatWindowPanel extends StatelessWidget {
  final String chatId;
  final VoidCallback onBack;

  const ChatWindowPanel({super.key, required this.chatId, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.darkBg,
      child: Column(
        children: [
          // ШАПКА ЧАТА
          _buildHeader(context),
          const Divider(height: 1, color: Colors.white10),

          // ОКНО СООБЩЕНИЙ
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _buildMessage("Привет! Как продвигается разработка Cove?", false, "11:00"),
                _buildMessage("Почти закончил с интерфейсом, перехожу к Go.", true, "11:05"),
                
                // Вложенный тред (уникальная фишка)
                _buildThreadWrapper([
                  _buildMessage("Не забудь про PostgreSQL 17!", false, "11:06"),
                  _buildVoiceReaction("Ок, сделаю!", true),
                ]),
                
                _buildMessage("Кстати, голосовые реакции работают отлично.", false, "11:10"),
              ],
            ),
          ),

          // ПАНЕЛЬ ВВОДА
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios_new, size: 20), onPressed: onBack),
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.accentIndigo,
            child: Text(chatId[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(chatId, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Text("в сети", style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
            ],
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: () {}),
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildMessage(String text, bool isMe, String time) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: isMe ? AppTheme.accentIndigo : AppTheme.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 4),
            Text(time, style: TextStyle(color: isMe ? Colors.white60 : Colors.white24, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // Голосовая реакция (3-секундный звук)
  Widget _buildVoiceReaction(String text, bool isMe) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.accentIndigo.withOpacity(0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_circle_fill, color: AppTheme.accentIndigo, size: 20),
            const SizedBox(width: 8),
            const Icon(Icons.graphic_eq, color: AppTheme.accentIndigo, size: 16),
            const SizedBox(width: 8),
            Text(text, style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  // Обертка для веток обсуждения (Heatmap эффект)
  Widget _buildThreadWrapper(List<Widget> messages) {
    return Container(
      // Заменяем vertical: 10 на top: 10, bottom: 10
      margin: const EdgeInsets.only(left: 20, top: 10, bottom: 10),
      padding: const EdgeInsets.only(left: 16),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: AppTheme.accentIndigo, width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, // Чтобы сообщения в треде не прыгали
        children: messages,
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.add_circle_outline, color: Colors.white24), onPressed: () {}),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: "Напишите что-нибудь...",
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: AppTheme.surface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                suffixIcon: const Icon(Icons.emoji_emotions_outlined, color: Colors.white24),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const CircleAvatar(
            backgroundColor: AppTheme.accentIndigo,
            child: Icon(Icons.mic, color: Colors.white),
          ),
        ],
      ),
    );
  }
}