import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../voice/presentation/voice_notifier.dart';
import '../../voice/presentation/widgets/voice_room_list_panel.dart';
import '../../voice/presentation/widgets/voice_room_page.dart';
import '../../chat/data/models/chat.dart';
import 'widgets/chat_list_panel.dart';
import 'widgets/chat_window_panel.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  Chat? _selectedChat;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final voice = context.watch<VoiceNotifier>();
    final username = auth.username ?? "User";

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _buildNavigationRail(),
                const VerticalDivider(width: 1, color: Colors.white10),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      _buildChatLayout(username),
                      _buildVoiceLayout(),
                      _buildSettingsPage(username),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (voice.isInRoom) _buildPersistentCallBar(voice),
        ],
      ),
    );
  }

  Widget _buildNavigationRail() {
    return NavigationRail(
      backgroundColor: AppTheme.darkBg,
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) {
        setState(() {
          _selectedIndex = index;
          if (index != 0) _selectedChat = null;
        });
      },
      labelType: NavigationRailLabelType.none,
      selectedIconTheme: const IconThemeData(color: AppTheme.accentIndigo),
      unselectedIconTheme: const IconThemeData(color: Colors.white24),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.forum_outlined),
          selectedIcon: Icon(Icons.forum),
          label: Text('Чаты'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.graphic_eq_outlined),
          selectedIcon: Icon(Icons.graphic_eq),
          label: Text('Голос'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Настройки'),
        ),
      ],
    );
  }

  // ── Chat layout ───────────────────────────────────────────────────────────────

  Widget _buildChatLayout(String username) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 800;

        if (isDesktop) {
          return Row(
            children: [
              SizedBox(
                width: 320,
                child: ChatListPanel(
                  onChatSelected: (chat) =>
                      setState(() => _selectedChat = chat),
                ),
              ),
              const VerticalDivider(width: 1, color: Colors.white10),
              Expanded(
                child: _selectedChat == null
                    ? _buildDashboard(username)
                    : ChatWindowPanel(
                        chat: _selectedChat!,
                        onBack: () => setState(() => _selectedChat = null),
                      ),
              ),
            ],
          );
        } else {
          return _selectedChat == null
              ? ChatListPanel(
                  onChatSelected: (chat) =>
                      setState(() => _selectedChat = chat),
                )
              : ChatWindowPanel(
                  chat: _selectedChat!,
                  onBack: () => setState(() => _selectedChat = null),
                );
        }
      },
    );
  }

  Widget _buildDashboard(String username) {
    return Container(
      color: AppTheme.darkBg,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Привет, $username",
            style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            "Выберите чат слева или найдите пользователя через поиск.",
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
          ),
          const SizedBox(height: 40),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              childAspectRatio: 2.4,
              children: [
                _dashboardCard("Голосовые комнаты", "Нажмите на иконку микрофона",
                    Icons.graphic_eq, Colors.greenAccent,
                    onTap: () => setState(() => _selectedIndex = 1)),
                _dashboardCard("Заявки в друзья", "Проверьте вкладку «Заявки»",
                    Icons.person_add_outlined, AppTheme.accentIndigo),
                _dashboardCard("Реакции", "Скоро появятся голосовые реакции",
                    Icons.spatial_audio_off, Colors.orangeAccent),
                _dashboardCard("Безопасность", "JWT-аутентификация активна",
                    Icons.verified_user, Colors.blueAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardCard(
    String title,
    String subtitle,
    IconData icon,
    Color color, {
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.03)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white38)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Voice layout ──────────────────────────────────────────────────────────────

  Widget _buildVoiceLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > 700;
        if (isDesktop) {
          return Row(
            children: [
              const SizedBox(
                width: 280,
                child: VoiceRoomListPanel(),
              ),
              const VerticalDivider(width: 1, color: Colors.white10),
              const Expanded(child: VoiceRoomPage()),
            ],
          );
        }
        // Mobile: toggle between list and room
        return context.watch<VoiceNotifier>().isInRoom
            ? const VoiceRoomPage()
            : const VoiceRoomListPanel();
      },
    );
  }

  // ── Persistent call bar ───────────────────────────────────────────────────────

  Widget _buildPersistentCallBar(VoiceNotifier voice) {
    final room = voice.currentRoom!;
    return Container(
      color: const Color(0xFF0E1A12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.greenAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.name,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.greenAccent),
                ),
                Text(
                  '${room.members.length} участн.',
                  style:
                      const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              voice.isMuted ? Icons.mic_off : Icons.mic,
              size: 20,
              color: voice.isMuted ? Colors.redAccent : Colors.white70,
            ),
            tooltip: voice.isMuted ? 'Включить микрофон' : 'Выключить микрофон',
            onPressed: voice.toggleMute,
          ),
          IconButton(
            icon: const Icon(Icons.call_end, size: 20, color: Colors.white),
            tooltip: 'Выйти из комнаты',
            style: IconButton.styleFrom(
              backgroundColor: Colors.redAccent,
              padding: const EdgeInsets.all(8),
            ),
            onPressed: () async {
              final token = context.read<AuthNotifier>().token;
              if (token != null && voice.currentRoom != null) {
                await ApiService().leaveVoiceRoom(
                  roomId: voice.currentRoom!.id,
                  token: token,
                );
              }
              voice.leaveRoom();
            },
          ),
        ],
      ),
    );
  }

  // ── Settings ──────────────────────────────────────────────────────────────────

  Widget _buildSettingsPage(String username) {
    return Container(
      color: AppTheme.darkBg,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Настройки",
              style:
                  TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 35,
                  backgroundColor: AppTheme.accentIndigo,
                  child: Text(
                    username.isNotEmpty ? username[0].toUpperCase() : "U",
                    style: const TextStyle(
                        fontSize: 28,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(username,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        const Text("В сети",
                            style: TextStyle(
                                color: Colors.white54, fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          _settingsOption(Icons.notifications_none_rounded, "Уведомления",
              "Настройка пушей и звуков"),
          _settingsOption(Icons.shield_outlined, "Приватность",
              "Кто может видеть ваш статус"),
          _settingsOption(Icons.info_outline, "О приложении", "Cove v0.1.0"),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.08),
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 22),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              onPressed: () =>
                  Provider.of<AuthNotifier>(context, listen: false).logout(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text("Выйти из аккаунта",
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsOption(IconData icon, String title, String subtitle) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accentIndigo, size: 26),
          const SizedBox(width: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.white.withValues(alpha: 0.4))),
            ],
          ),
          const Spacer(),
          Icon(Icons.chevron_right_rounded,
              color: Colors.white.withValues(alpha: 0.2)),
        ],
      ),
    );
  }
}
