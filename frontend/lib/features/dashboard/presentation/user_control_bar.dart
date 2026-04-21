import 'package:flutter/material.dart';

class UserControlBar extends StatelessWidget {
  const UserControlBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF292B2F),
        border: Border(top: BorderSide(color: Colors.grey[800]!)),
      ),
      child: Row(
        children: [
          const CircleAvatar(radius: 20, backgroundColor: Color(0xFF5865F2), child: Icon(Icons.person, color: Colors.white)),
          const SizedBox(width: 12),
          const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ваш Ник', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              Text('В сети', style: TextStyle(color: Colors.green, fontSize: 12)),
            ],
          ),
          const Spacer(),
          IconButton(icon: const Icon(Icons.mic), onPressed: () {}),
          IconButton(icon: const Icon(Icons.headphones), onPressed: () {}),
          IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
        ],
      ),
    );
  }
}