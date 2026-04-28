import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

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
          _buildHeader(context),
          const Divider(height: 1, color: Colors.white10),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [],
            ),
          ),
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
