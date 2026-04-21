import 'package:flutter/material.dart';

class ChatListScreen extends StatelessWidget {
  final String activeChatId;
  final Function(String) onChatSelected;

  const ChatListScreen({
    super.key,
    required this.activeChatId,
    required this.onChatSelected,
  });

  // Моковые данные
  final List<Map<String, dynamic>> _chats = const [
    {'id': 'personal', 'name': 'Личные сообщения', 'type': 'dm', 'unread': 0},
    {'id': 'dev_team', 'name': 'Dev Team', 'type': 'group', 'unread': 3},
    {'id': 'gaming', 'name': 'Gaming Lounge', 'type': 'group', 'unread': 0},
    {'id': 'voice_room', 'name': '🔊 Общая голосовая', 'type': 'voice', 'unread': 0},
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF202225),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Поиск чата...',
                prefixIcon: const Icon(Icons.search, size: 20),
                filled: true,
                fillColor: const Color(0xFF2F3136),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _chats.length,
              itemBuilder: (context, index) {
                final chat = _chats[index];
                final isActive = chat['id'] == activeChatId;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isActive ? const Color(0xFF5865F2) : Colors.grey[700],
                    child: Text(chat['type'] == 'dm' ? '👤' : chat['type'] == 'voice' ? '' : '#'),
                  ),
                  title: Text(chat['name'], style: TextStyle(color: isActive ? Colors.white : Colors.grey[300])),
                  subtitle: chat['unread'] > 0 ? Text('${chat['unread']} новых') : null,
                  selected: isActive,
                  selectedTileColor: const Color(0xFF36393F).withOpacity(0.5),
                  onTap: () => onChatSelected(chat['id']),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}