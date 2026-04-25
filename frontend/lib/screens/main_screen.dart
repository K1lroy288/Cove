import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../widgets/chat_list_panel.dart';
import '../widgets/chat_window_panel.dart';
import '../../../shared/theme/app_theme.dart';
import '../../../shared/services/auth_notifier.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; // 0 - Чаты, 1 - Поиск, 2 - Настройки
  String? _selectedChatId; // null означает, что открыт Дашборд

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // 1. Боковая навигация (Rail)
          NavigationRail(
            backgroundColor: AppTheme.darkBg,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
                // При переходе в поиск или настройки сбрасываем выбранный чат
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

          // 2. Основной контент
          Expanded(
            child: _buildCurrentContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildChatSection();
      case 1:
        return _buildSearchPage();
      case 2:
        return _buildSettingsPage();
      default:
        return _buildChatSection();
    }
  }

  // --- СЕКЦИЯ ЧАТОВ ---
  Widget _buildChatSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool isDesktop = constraints.maxWidth > 800;

        if (isDesktop) {
          return Row(
            children: [
              SizedBox(
                width: 300,
                child: ChatListPanel(
                  onChatSelected: (id) => setState(() => _selectedChatId = id),
                ),
              ),
              const VerticalDivider(width: 1, color: Colors.white10),
              Expanded(
                child: _selectedChatId == null 
                  ? _buildDashboard() 
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

  // --- ДАШБОРД (ПРИВЕТСТВИЕ) ---
  Widget _buildDashboard() {
    return Container(
      color: AppTheme.darkBg,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Привет, 👋", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text("Выберите чат, чтобы начать общение в Cove.", style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 40),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 20,
              mainAxisSpacing: 20,
              childAspectRatio: 2.5,
              children: [
                _dashboardCard("Активные звонки", "3 комнаты", Icons.graphic_eq, Colors.greenAccent),
                _dashboardCard("Новые реакции", "5 звуков", Icons.spatial_audio_off, AppTheme.accentIndigo),
                _dashboardCard("Тренды", "Популярные ветки", Icons.whatshot, Colors.orangeAccent),
                _dashboardCard("Безопасность", "Ключ активен", Icons.verified_user, Colors.blueAccent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dashboardCard(String title, String subtitle, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 16),
          Flexible(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
          )
        ],
      ),
    );
  }

  // --- ОБНОВЛЕННЫЙ ПОИСК ---
  Widget _buildSearchPage() {
    return Container(
      color: AppTheme.darkBg,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Поиск", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text("Найдите собеседника по никнейму", style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 30),
          TextField(
            decoration: InputDecoration(
              hintText: "Введите никнейм...",
              prefixIcon: const Icon(Icons.search, color: AppTheme.accentIndigo),
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const Spacer(),
          const Center(child: Icon(Icons.search_off, size: 80, color: Colors.white10)),
          const Center(child: Text("Тут появятся результаты поиска", style: TextStyle(color: Colors.white24))),
          const Spacer(),
        ],
      ),
    );
  }

  // --- ОБНОВЛЕННЫЕ НАСТРОЙКИ ---
  Widget _buildSettingsPage() {
    return Container(
      color: AppTheme.darkBg,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Настройки", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          const Text("Аккаунт и безопасность", style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 30),
          
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const CircleAvatar(radius: 30, backgroundColor: AppTheme.accentIndigo, child: Icon(Icons.person, size: 30, color: Colors.white)),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text("Ваш профиль", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text("@username", style: TextStyle(color: Colors.white54)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _settingsOption(Icons.key_outlined, "Кодовое слово", "Настройка восстановления"),
          const SizedBox(height: 12),
          _settingsOption(Icons.notifications_none_outlined, "Уведомления", "Звуки и реакции"),
          
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () => Provider.of<AuthNotifier>(context, listen: false).logout(),
              icon: const Icon(Icons.logout, color: Colors.redAccent),
              label: const Text("Выйти из системы", style: TextStyle(color: Colors.redAccent)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsOption(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.accentIndigo),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ],
          ),
          const Spacer(),
          const Icon(Icons.chevron_right, color: Colors.white24),
        ],
      ),
    );
  }
}