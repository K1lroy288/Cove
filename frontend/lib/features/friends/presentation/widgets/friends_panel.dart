import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../features/auth/presentation/auth_notifier.dart';
import '../../../../features/chat/data/models/chat.dart';
import '../../../../features/chat/data/services/chat_service.dart';
import '../../data/models/friend.dart';
import '../../data/services/friendship_service.dart';

class FriendsPanel extends StatefulWidget {
  final Function(Chat) onOpenChat;

  const FriendsPanel({super.key, required this.onOpenChat});

  @override
  State<FriendsPanel> createState() => _FriendsPanelState();
}

class _FriendsPanelState extends State<FriendsPanel> {
  final FriendshipService _friendshipService = FriendshipService();
  final ChatService _chatService = ChatService();
  final TextEditingController _searchController = TextEditingController();

  List<Friend> _friends = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int? _openingChatForId; // ID друга, для которого открывается чат

  List<Friend> get _filtered {
    if (_searchQuery.isEmpty) return _friends;
    return _friends
        .where((f) =>
            f.username.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFriends() async {
    final auth = context.read<AuthNotifier>();
    if (auth.userId == null || auth.token == null) return;

    setState(() => _isLoading = true);

    final friends = await _friendshipService.getFriends(
      userId: auth.userId!,
      token: auth.token!,
    );

    if (mounted) {
      setState(() {
        _friends = friends;
        _isLoading = false;
      });
    }
  }

  Future<void> _openChat(Friend friend) async {
    final auth = context.read<AuthNotifier>();
    if (auth.token == null) return;

    setState(() => _openingChatForId = friend.id);

    final chat = await _chatService.createChat(
      friendId: friend.id,
      token: auth.token!,
    );

    if (!mounted) return;
    setState(() => _openingChatForId = null);

    if (chat != null) {
      widget.onOpenChat(chat);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось открыть чат'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.darkBg,
      child: Column(
        children: [
          _buildHeader(),
          _buildSearch(),
          const Divider(height: 1, color: Colors.white10),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 12),
      child: Row(
        children: [
          const Text(
            'Друзья',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          if (_friends.isNotEmpty) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.accentIndigo.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_friends.length}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.accentIndigo,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: Colors.white38),
            tooltip: 'Обновить',
            onPressed: _loadFriends,
          ),
        ],
      ),
    );
  }

  Widget _buildSearch() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v.trim()),
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Поиск среди друзей...',
          hintStyle: const TextStyle(color: Colors.white30, fontSize: 14),
          prefixIcon: const Icon(Icons.search, color: Colors.white30, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close,
                      color: Colors.white30, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: AppTheme.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppTheme.accentIndigo),
      );
    }

    if (_friends.isEmpty) {
      return Center(
        child: Opacity(
          opacity: 0.35,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.people_outline, size: 56, color: Colors.white),
              SizedBox(height: 14),
              Text('Друзей пока нет',
                  style: TextStyle(fontSize: 16, color: Colors.white)),
              SizedBox(height: 8),
              Text('Найдите пользователя через поиск в чатах',
                  style: TextStyle(fontSize: 13, color: Colors.white)),
            ],
          ),
        ),
      );
    }

    final list = _filtered;

    if (list.isEmpty) {
      return Center(
        child: Text(
          'Никого не найдено по «$_searchQuery»',
          style: const TextStyle(color: Colors.white38, fontSize: 14),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.accentIndigo,
      onRefresh: _loadFriends,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: list.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: Colors.white10, indent: 72),
        itemBuilder: (context, i) => _buildFriendTile(list[i]),
      ),
    );
  }

  Widget _buildFriendTile(Friend friend) {
    final isOpening = _openingChatForId == friend.id;
    final initial = friend.username.isNotEmpty
        ? friend.username[0].toUpperCase()
        : '?';

    // Случайный, но стабильный цвет на основе ID
    final colors = [
      AppTheme.accentIndigo,
      Colors.teal,
      Colors.deepPurple,
      Colors.blueAccent,
      Colors.green,
    ];
    final color = colors[friend.id % colors.length];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: color.withValues(alpha: 0.18),
            child: Text(
              initial,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.darkBg, width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Text(
        friend.username,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: const Text(
        'Не в сети',
        style: TextStyle(fontSize: 12, color: Colors.white38),
      ),
      trailing: isOpening
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accentIndigo),
            )
          : OutlinedButton.icon(
              onPressed: () => _openChat(friend),
              icon: const Icon(Icons.chat_bubble_outline, size: 14),
              label: const Text('Написать'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accentIndigo,
                side: BorderSide(
                    color: AppTheme.accentIndigo.withValues(alpha: 0.5)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
    );
  }
}
