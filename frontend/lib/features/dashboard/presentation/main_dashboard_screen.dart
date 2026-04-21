import 'package:flutter/material.dart';
import 'chat_list_screen.dart';
import 'chat_view_screen.dart';
import 'call_overlay_widget.dart';
import 'user_control_bar.dart';

class MainDashboardScreen extends StatefulWidget {
  const MainDashboardScreen({super.key});

  @override
  State<MainDashboardScreen> createState() => _MainDashboardScreenState();
}

class _MainDashboardScreenState extends State<MainDashboardScreen> {
  bool _isCallActive = false;
  String _activeChatId = 'personal';

  void _toggleCall() {
    setState(() => _isCallActive = !_isCallActive);
  }

  void _selectChat(String chatId) {
    setState(() => _activeChatId = chatId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Убираем дефолтный AppBar, рисуем свою шапку внутри ChatView
      extendBodyBehindAppBar: true,
      body: Row(
        children: [
          // 1️⃣ Левая панель: список чатов
          SizedBox(
            width: 280,
            child: ChatListScreen(
              activeChatId: _activeChatId,
              onChatSelected: _selectChat,
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),

          // 2️⃣ Основная область: чат + оверлей звонка
          Expanded(
            child: Stack(
              children: [
                ChatViewScreen(
                  chatId: _activeChatId,
                  onToggleCall: _toggleCall,
                ),
                // Оверлей появляется поверх чата при активном звонке
                if (_isCallActive)
                  CallOverlayWidget(
                    onEndCall: () => setState(() => _isCallActive = false),
                  ),
              ],
            ),
          ),
        ],
      ),
      // 3️⃣ Нижняя панель управления
      bottomNavigationBar: const UserControlBar(),
    );
  }
}