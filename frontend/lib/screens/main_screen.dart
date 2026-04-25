import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/chat_list_panel.dart';
import '../widgets/chat_window_panel.dart';
import '../shared/theme/app_theme.dart';
import '../shared/services/auth_notifier.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; 
  String? _selectedChatId; 

  @override
  Widget build(BuildContext context) {
    // 🔥 Получаем данные пользователя
    final auth = context.watch<AuthNotifier>();
    final String currentUsername = auth.username ?? "User";

    return Scaffold(
      body: Row(
        children: [
          // 1. БОКОВАЯ ПАНЕЛЬ (NavigationRail)
          NavigationRail(
            backgroundColor: AppTheme.darkBg,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
                if (index != 0) _selectedChatId = null;
              });
            },
            labelType: NavigationRailLabelType.none,
            selectedIconTheme: const IconThemeData(color: AppTheme.accentIndigo),
            unselectedIconTheme: const IconThemeData(color: Colors.white24),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.forum_outlined), 
                selectedIcon: Icon(Icons.forum), 
                label: Text('Чаты')
              ),
              NavigationRailDestination(
                icon: Icon(Icons.search), 
                label: Text('Поиск')
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined), 
                selectedIcon: Icon(Icons.settings), 
                label: Text('Настройки')
              ),
            ],
          ),
          const VerticalDivider(width: 1, color: Colors.white10),

          // 2. ОСНОВНОЙ КОНТЕНТ
          Expanded(
            child: _buildCurrentPage(currentUsername),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPage(String username) {
    switch (_selectedIndex) {
      case 0:
        return _buildChatLayout(username);
      case 1:
        return _buildSearchPage();
      case 2:
        return _buildSettingsPage(username);
      default:
        return _buildChatLayout(username);
    }
  }

  // --- ЛОГИКА СЕКЦИИ ЧАТОВ ---
  Widget _buildChatLayout(String username) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth > 800;

        if (isDesktop) {
          return Row(
            children: [
              SizedBox(
                width: 320,
                child: ChatListPanel(
                  onChatSelected: (id) => setState(() => _selectedChatId = id),
                ),
              ),
              const VerticalDivider(width: 1, color: Colors.white10),
              Expanded(
                child: _selectedChatId == null 
                  ? _buildDashboard(username) 
                  : ChatWindowPanel(
                      chatId: _selectedChatId!, 
                      onBack: () => setState(() => _selectedChatId = null)
                    ),
              ),
            ],
          );
        } else {
          // Мобильная адаптация
          return _selectedChatId == null 
            ? ChatListPanel(onChatSelected: (id) => setState(() => _selectedChatId = id))
            : ChatWindowPanel(
                chatId: _selectedChatId!, 
                onBack: () => setState(() => _selectedChatId = null)
              );
        }
      },
    );
  }

  // --- РЕАЛЬНЫЙ ДАШБОРД (Без заглушек) ---
  Widget _buildDashboard(String username) {
    return Container(
      color: AppTheme.darkBg,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Привет, $username 👋", 
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 10),
          Text("Рады видеть тебя в Cove. У тебя нет пропущенных вызовов.", 
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16)),
          const SizedBox(height: 40),
          
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              childAspectRatio: 2.4,
              children: [
                _dashboardCard("Голосовые комнаты", "Активных сейчас: 0", Icons.graphic_eq, Colors.greenAccent),
                _dashboardCard("Реакции", "Новых звуков нет", Icons.spatial_audio_off, AppTheme.accentIndigo),
                _dashboardCard("Тренды сообщества", "Пока пусто", Icons.whatshot, Colors.orangeAccent),
                _dashboardCard("Безопасность", "Ключ настроен", Icons.verified_user, Colors.blueAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardCard(String title, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.03)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.white38)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- СТРАНИЦА ПОИСКА ---
  Widget _buildSearchPage() {
    return Container(
      color: AppTheme.darkBg,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Поиск", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text("Найдите собеседника по уникальному никнейму", style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 32),
          TextField(
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Например: alex_cove",
              hintStyle: const TextStyle(color: Colors.white24),
              prefixIcon: const Icon(Icons.search, color: AppTheme.accentIndigo),
              filled: true,
              fillColor: AppTheme.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
            ),
          ),
          const Spacer(),
          Center(
            child: Opacity(
              opacity: 0.3,
              child: Column(
                children: const [
                  Icon(Icons.manage_search, size: 64, color: Colors.white),
                  SizedBox(height: 16),
                  Text("Введите никнейм для начала поиска"),
                ],
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  // --- СТРАНИЦА НАСТРОЕК (Реальный профиль) ---
  Widget _buildSettingsPage(String username) {
    return Container(
      color: AppTheme.darkBg,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Настройки", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 32),
          
          // Аккаунт
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
                    style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold)
                  )
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(username, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.greenAccent, shape: BoxShape.circle)),
                        const SizedBox(width: 8),
                        const Text("В сети", style: TextStyle(color: Colors.white54, fontSize: 14)),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          _settingsOption(Icons.key_outlined, "Кодовое слово", "Используется для восстановления доступа"),
          _settingsOption(Icons.notifications_none_rounded, "Уведомления", "Настройка пушей и звуков"),
          _settingsOption(Icons.shield_outlined, "Приватность", "Кто может видеть ваш статус"),
          
          const Spacer(),
          
          // Кнопка выхода
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withOpacity(0.08),
                foregroundColor: Colors.redAccent,
                padding: const EdgeInsets.symmetric(vertical: 22),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              onPressed: () => Provider.of<AuthNotifier>(context, listen: false).logout(),
              icon: const Icon(Icons.logout_rounded),
              label: const Text("Выйти из аккаунта", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.4))),
            ],
          ),
          const Spacer(),
          Icon(Icons.chevron_right_rounded, color: Colors.white.withOpacity(0.2)),
        ],
      ),
    );
  }
}