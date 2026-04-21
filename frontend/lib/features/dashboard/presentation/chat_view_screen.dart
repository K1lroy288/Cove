import 'package:flutter/material.dart';

class ChatViewScreen extends StatelessWidget {
  final String chatId;
  final VoidCallback onToggleCall;

  // Убрал const, так как моковые данные генерируются динамически
  ChatViewScreen({super.key, required this.chatId, required this.onToggleCall});

  @override
  Widget build(BuildContext context) {
    // Генерируем сообщения локально внутри build
    final mockMessages = List.generate(20, (i) => 'Сообщение #$i: Привет, как дела с проектом?');

    return Column(
      children: [
        // Шапка чата
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF36393F),
            border: const Border(bottom: BorderSide(color: Color(0xFF202225))),
          ),
          child: Row(
            children: [
              Text('# ${chatId.toUpperCase()}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.phone_outlined), onPressed: onToggleCall),
              IconButton(icon: const Icon(Icons.videocam_outlined), onPressed: onToggleCall),
              IconButton(icon: const Icon(Icons.monitor_outlined), onPressed: onToggleCall),
            ],
          ),
        ),
        // Список сообщений
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: mockMessages.length,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2F3136),
                  borderRadius: BorderRadius.circular(8),
                ),
                // Заменил Colors.grey[300] на явный const Color (светло-серый Discord)
                child: Text(mockMessages[index], style: const TextStyle(color: Color(0xFFDCDDDE))),
              ),
            ),
          ),
        ),
        // Поле ввода
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF36393F),
          child: Row(
            children: [
              IconButton(icon: const Icon(Icons.add_circle_outline), onPressed: () {}),
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Написать сообщение...',
                    filled: true,
                    fillColor: const Color(0xFF40444B),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              IconButton(icon: const Icon(Icons.send), onPressed: () {}),
            ],
          ),
        ),
      ],
    );
  }
}