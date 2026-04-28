import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'widgets/chat_list_panel.dart';
import 'widgets/chat_window_panel.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/presentation/auth_notifier.dart';
import '../../../core/network/api_service.dart';
import '../../user/data/models/user_dto.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  String? _selectedChatId;
  final ApiService _apiService = ApiService();
  final TextEditingController _searchController = TextEditingController();
  UserDTO? _foundUser;
  bool _isSearching = false;
  String? _errorMessage;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthNotifier>();
    final String currentUsername = auth.username ?? "User";

    return Scaffold(
      body: Row(
        children: [
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
                label: Text('Чаты'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.search),
                label: Text('Поиск'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Настройки'),
              ),
            ],
          ),
          const VerticalDivider(width: 1, color: Colors.white10),
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
                        onBack: () => setState(() => _selectedChatId = null),
                      ),
              ),
            ],
          );
        } else {
          return _selectedChatId == null
              ? ChatListPanel(onChatSelected: (id) => setState(() => _selectedChatId = id))
              : ChatWindowPanel(
                  chatId: _selectedChatId!,
                  onBack: () => setState(() => _selectedChatId = null),
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
            "Привет, $username 👋",
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Text(
            "Рады видеть тебя в Cove. У тебя нет пропущенных вызовов.",
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16),
          ),
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
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.white38)),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
            controller: _searchController,
            onSubmitted: (_) => _handleSearch(),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: "Введите ID (например: 1)",
              suffixIcon: IconButton(
                icon: _isSearching
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.arrow_forward, color: AppTheme.accentIndigo),
                onPressed: _handleSearch,
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_foundUser != null)
            _buildUserResultCard(_foundUser!)
          else if (_errorMessage != null)
            Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent))),
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

  Widget _buildUserResultCard(UserDTO user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.accentIndigo,
            child: Text(user.username[0].toUpperCase()),
          ),
          const SizedBox(width: 16),
          Text(user.username, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          ElevatedButton(
            onPressed: () => log("Запрос в друзья для ID: ${user.id}"),
            child: const Text("Добавить"),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _foundUser = null;
    });

    final user = await _apiService.findUserById(query);

    setState(() {
      _isSearching = false;
      if (user != null) {
        _foundUser = user;
      } else {
        _errorMessage = "Пользователь не найден";
      }
    });
  }

  Widget _buildSettingsPage(String username) {
    return Container(
      color: AppTheme.darkBg,
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Настройки", style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
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
                    style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
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
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent.withValues(alpha: 0.08),
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
              Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.4))),
            ],
          ),
          const Spacer(),
          Icon(Icons.chevron_right_rounded, color: Colors.white.withValues(alpha: 0.2)),
        ],
      ),
    );
  }
}
