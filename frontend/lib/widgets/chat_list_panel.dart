import 'package:flutter/material.dart';
import '../shared/theme/app_theme.dart';

class ChatListPanel extends StatelessWidget {
  final Function(String) onChatSelected;

  const ChatListPanel({super.key, required this.onChatSelected});

  @override
  Widget build(BuildContext context) {
    // В будущем этот список будет приходить из БД
    final List<Map<String, String>> demoChats = [];

    return Container(
      color: AppTheme.darkBg,
      child: Column(
        children: [
          // Заголовок списка
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Text("Сообщения", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.edit_note, color: Colors.white54), onPressed: () {}),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: demoChats.length,
              itemBuilder: (context, index) {
                final chat = demoChats[index];
                return ListTile(
                  onTap: () => onChatSelected(chat['name']!),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: CircleAvatar(
                    radius: 24,
                    backgroundColor: AppTheme.surface,
                    child: Text(chat['name']![0], style: const TextStyle(color: AppTheme.accentIndigo, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(chat['name']!, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(chat['lastMsg']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white38)),
                  trailing: Text(chat['time']!, style: const TextStyle(fontSize: 11, color: Colors.white24)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}