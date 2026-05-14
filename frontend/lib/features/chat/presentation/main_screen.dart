import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../voice/data/services/voice_service.dart';
import '../../../core/theme/app_theme.dart' show AppTheme, AppColors;
import '../../settings/presentation/settings_screen.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../voice/presentation/voice_notifier.dart';
import '../../voice/presentation/widgets/voice_room_list_panel.dart';
import '../../voice/presentation/widgets/voice_room_page.dart';
import '../../chat/data/models/chat.dart';
import '../../friends/presentation/widgets/friends_panel.dart';
import '../data/models/notification.dart';
import 'notification_notifier.dart';
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

  final _chatListKey = ChatListPanel.createKey();
  final _friendsPanelKey = FriendsPanel.createKey();

  StreamSubscription<NewMessageNotification>? _notifSub;
  StreamSubscription<FriendRequestNotification>? _friendReqSub;
  StreamSubscription<void>? _friendAcceptedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notif = context.read<NotificationNotifier>();
      _notifSub = notif.messageStream.listen((n) {
        _chatListKey.currentState?.updateChatMessage(n.chatId, n.content, n.createdAt);
      });
      _friendReqSub = notif.friendRequestStream.listen((_) {
        _chatListKey.currentState?.refreshPendingRequests();
        if (_selectedIndex == 0) notif.decrementPendingCount();
      });
      _friendAcceptedSub = notif.friendAcceptedStream.listen((_) {
        _friendsPanelKey.currentState?.refresh();
      });
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    _friendReqSub?.cancel();
    _friendAcceptedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final voice = context.watch<VoiceNotifier>();
    final username = auth.username ?? "User";

    final colors = AppColors.of(context);
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                _buildNavigationRail(),
                VerticalDivider(width: 1, color: colors.divider),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: [
                      _buildChatLayout(username),
                      _buildFriendsLayout(),
                      _buildVoiceLayout(),
                      const SettingsScreen(),
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
    final colors = AppColors.of(context);
    return SizedBox(
      width: 72,
      child: Container(
        color: colors.bg,
        child: Column(
          children: [
            const SizedBox(height: 8),
            _sidebarIconWithBadge(Icons.forum_outlined, Icons.forum, 0),
            _sidebarIcon(Icons.people_outline, Icons.people, 1),
            _sidebarIcon(Icons.graphic_eq_outlined, Icons.graphic_eq, 2),
            const Spacer(),
            _sidebarIcon(Icons.settings_outlined, Icons.settings, 3),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _sidebarIcon(IconData icon, IconData selectedIcon, int index) {
    final sel = _selectedIndex == index;
    final colors = AppColors.of(context);
    return IconButton(
      icon: Icon(sel ? selectedIcon : icon),
      color: sel ? AppTheme.accentIndigo : colors.textSecondary,
      tooltip: ['Чаты', 'Друзья', 'Голос', 'Настройки'][index],
      onPressed: () => setState(() {
        _selectedIndex = index;
        if (index != 0) _selectedChat = null;
      }),
    );
  }

  Widget _sidebarIconWithBadge(IconData icon, IconData selectedIcon, int index) {
    final sel = _selectedIndex == index;
    final colors = AppColors.of(context);
    final count = context.watch<NotificationNotifier>().pendingRequestCount;
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: Icon(sel ? selectedIcon : icon),
          color: sel ? AppTheme.accentIndigo : colors.textSecondary,
          tooltip: 'Чаты',
          onPressed: () {
            setState(() => _selectedIndex = index);
            context.read<NotificationNotifier>().decrementPendingCount();
          },
        ),
        if (count > 0)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
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
                  key: _chatListKey,
                  onChatSelected: (chat) =>
                      setState(() => _selectedChat = chat),
                  onFriendAccepted: () =>
                      _friendsPanelKey.currentState?.refresh(),
                ),
              ),
              VerticalDivider(width: 1, color: AppColors.of(context).divider),
              Expanded(
                child: _selectedChat == null
                    ? _buildDashboard(username)
                    : ChatWindowPanel(
                        chat: _selectedChat!,
                        onBack: () => setState(() => _selectedChat = null),
                        onMessageSent: (msg) =>
                            _chatListKey.currentState?.updateChatMessage(
                                msg.chatId, msg.content, msg.createdAt),
                      ),
              ),
            ],
          );
        } else {
          return _selectedChat == null
              ? ChatListPanel(
                  key: _chatListKey,
                  onChatSelected: (chat) =>
                      setState(() => _selectedChat = chat),
                  onFriendAccepted: () =>
                      _friendsPanelKey.currentState?.refresh(),
                )
              : ChatWindowPanel(
                  chat: _selectedChat!,
                  onBack: () => setState(() => _selectedChat = null),
                  onMessageSent: (msg) =>
                      _chatListKey.currentState?.updateChatMessage(
                          msg.chatId, msg.content, msg.createdAt),
                );
        }
      },
    );
  }

  Widget _buildDashboard(String username) {
    final colors = AppColors.of(context);
    return Container(
      color: colors.bg,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Привет, $username",
            style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary),
          ),
          const SizedBox(height: 10),
          Text(
            "Выберите чат слева или найдите пользователя через поиск.",
            style: TextStyle(color: colors.textSecondary, fontSize: 16),
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
    final colors = AppColors.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.divider.withValues(alpha: 0.3)),
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
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: colors.textPrimary)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 13, color: colors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Friends layout ────────────────────────────────────────────────────────────

  Widget _buildFriendsLayout() {
    return FriendsPanel(
      key: _friendsPanelKey,
      onOpenChat: (Chat chat) {
        setState(() {
          _selectedIndex = 0;
          _selectedChat = chat;
        });
        _chatListKey.currentState?.reload();
      },
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
              VerticalDivider(width: 1, color: AppColors.of(context).divider),
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
                await VoiceService().leaveVoiceRoom(
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

}
