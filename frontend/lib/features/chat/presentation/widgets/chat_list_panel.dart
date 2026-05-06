import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/auth_notifier.dart';
import '../../../friends/data/models/friend.dart';
import '../../../friends/data/services/friendship_service.dart';
import '../../../user/data/models/friend_request.dart';
import '../../../user/data/models/user_dto.dart';
import '../../../user/data/services/user_service.dart';
import '../../data/models/chat.dart';
import '../../data/services/chat_service.dart';

enum _Tab { chats, requests }

class ChatListPanel extends StatefulWidget {
  final Function(Chat) onChatSelected;

  const ChatListPanel({super.key, required this.onChatSelected});

  @override
  State<ChatListPanel> createState() => _ChatListPanelState();
}

class _ChatListPanelState extends State<ChatListPanel> {
  final ChatService _chatService = ChatService();
  final FriendshipService _friendshipService = FriendshipService();
  final UserService _userService = UserService();
  final TextEditingController _searchController = TextEditingController();

  _Tab _activeTab = _Tab.chats;
  UserDTO? _foundUser;
  bool _isSearching = false;
  bool _isSendingRequest = false;
  String? _errorMessage;

  List<Chat> _chats = [];
  bool _isLoadingChats = true;

  List<FriendRequest> _pendingRequests = [];
  int get _pendingRequestsCount => _pendingRequests.length;
  final Set<int> _respondingIds = {};

  List<Friend> _friends = [];
  final Set<int> _sentRequestIds = {};

  bool get _hasQuery => _searchController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadChats();
    _loadPendingRequests();
    _loadFriends();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;

    final chats = await _chatService.getChats(token: token);
    if (mounted) {
      setState(() {
        _chats = chats;
        _isLoadingChats = false;
      });
    }
  }

  Future<void> _loadPendingRequests() async {
    final auth = context.read<AuthNotifier>();
    if (auth.userId == null || auth.token == null) return;

    final requests = await _friendshipService.getPendingRequests(
      userId: auth.userId!,
      token: auth.token!,
    );
    if (mounted) setState(() => _pendingRequests = requests);
  }

  Future<void> _loadFriends() async {
    final auth = context.read<AuthNotifier>();
    if (auth.userId == null || auth.token == null) return;
    final friends = await _friendshipService.getFriends(
      userId: auth.userId!,
      token: auth.token!,
    );
    if (mounted) setState(() => _friends = friends);
  }

  Future<void> _handleSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _foundUser = null;
        _errorMessage = null;
      });
      return;
    }

    final auth = context.read<AuthNotifier>();
    final isSelf =
        trimmed.toLowerCase() == (auth.username ?? '').toLowerCase() ||
            trimmed == (auth.userId ?? '');
    if (isSelf) {
      setState(() {
        _foundUser = null;
        _errorMessage = "Это вы";
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
      _foundUser = null;
    });

    final user = await _userService.searchUser(trimmed);

    if (mounted) {
      setState(() {
        _isSearching = false;
        if (user != null) {
          _foundUser = user;
        } else {
          _errorMessage = "Пользователь не найден";
        }
      });
    }
  }

  Future<void> _handleAddFriend(UserDTO friend) async {
    final auth = context.read<AuthNotifier>();
    final currentUserId = int.tryParse(auth.userId ?? '');
    final token = auth.token;
    if (currentUserId == null || token == null) return;

    setState(() => _isSendingRequest = true);

    final (success, message) = await _friendshipService.createFriendship(
      userId: currentUserId,
      friendId: friend.id,
      token: token,
    );

    if (!mounted) return;
    setState(() {
      _isSendingRequest = false;
      if (success) _sentRequestIds.add(friend.id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            success ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _respondToRequest(FriendRequest req, String status) async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;

    setState(() => _respondingIds.add(req.userId));

    final (success, message) = await _friendshipService.respondToFriendRequest(
      fromUserId: req.userId,
      status: status,
      token: token,
    );

    if (!mounted) return;

    setState(() {
      _respondingIds.remove(req.userId);
      if (success) {
        _pendingRequests.removeWhere((r) => r.userId == req.userId);
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            success ? Colors.green.shade700 : Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );

    // Refresh chat list after accepting so new DM appears
    if (success && status == 'accepted') _loadChats();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.darkBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Text("Сообщения",
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                    icon: const Icon(Icons.edit_note, color: Colors.white54),
                    onPressed: () {}),
              ],
            ),
          ),
          _buildTabSwitcher(),
          if (_activeTab == _Tab.chats)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TextField(
                controller: _searchController,
                onChanged: _handleSearch,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Найти пользователя...",
                  hintStyle:
                      const TextStyle(color: Colors.white30, fontSize: 14),
                  prefixIcon: const Icon(Icons.search,
                      color: Colors.white30, size: 20),
                  suffixIcon: _hasQuery
                      ? IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white30, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _handleSearch('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.surface,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          Expanded(
            child: _activeTab == _Tab.chats
                ? (_hasQuery ? _buildSearchResults() : _buildChatList())
                : _buildRequestsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            _tabButton("Чаты", _Tab.chats),
            _tabButton("Заявки", _Tab.requests,
                badge: _pendingRequestsCount),
          ],
        ),
      ),
    );
  }

  Widget _tabButton(String label, _Tab tab, {int badge = 0}) {
    final isActive = _activeTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.darkBg : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isActive ? FontWeight.w600 : FontWeight.normal,
                  color: isActive ? Colors.white : Colors.white38,
                ),
              ),
              if (badge > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.redAccent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badge',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── Search results ────────────────────────────────────────────────────────────

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Center(
          child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_foundUser != null) return _buildUserResultCard(_foundUser!);
    if (_errorMessage != null) {
      return Center(
        child: Text(_errorMessage!,
            style:
                const TextStyle(color: Colors.white38, fontSize: 14)),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildUserResultCard(UserDTO user) {
    final isAlreadyFriend = _friends.any((f) => f.id == user.id);
    final hasIncomingRequest = _pendingRequests.any((r) => r.userId == user.id);
    final hasSentRequest = _sentRequestIds.contains(user.id);

    final String subtitle;
    final Widget trailing;

    if (isAlreadyFriend) {
      subtitle = "Уже в друзьях";
      trailing = const Icon(Icons.check, color: Colors.greenAccent);
    } else if (hasIncomingRequest) {
      subtitle = "Прислал вам заявку";
      trailing = const Icon(Icons.mail_outline, color: Colors.amber);
    } else if (hasSentRequest) {
      subtitle = "Запрос отправлен";
      trailing = const Icon(Icons.schedule, color: Colors.white38);
    } else if (_isSendingRequest) {
      subtitle = "Нажмите, чтобы добавить";
      trailing = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
            strokeWidth: 2, color: AppTheme.accentIndigo),
      );
    } else {
      subtitle = "Нажмите, чтобы добавить";
      trailing = IconButton(
        icon: const Icon(Icons.person_add_outlined,
            color: AppTheme.accentIndigo),
        onPressed: () => _handleAddFriend(user),
      );
    }

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.accentIndigo.withValues(alpha: 0.2),
        child: Text(
          user.username[0].toUpperCase(),
          style: const TextStyle(
              color: AppTheme.accentIndigo, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(user.username,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
      trailing: trailing,
    );
  }

  // ── Chat list ─────────────────────────────────────────────────────────────────

  Widget _buildChatList() {
    if (_isLoadingChats) {
      return const Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.accentIndigo));
    }

    if (_chats.isEmpty) {
      return Center(
        child: Opacity(
          opacity: 0.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.forum_outlined, size: 48, color: Colors.white),
              SizedBox(height: 12),
              Text("Чатов пока нет",
                  style: TextStyle(fontSize: 14, color: Colors.white)),
              SizedBox(height: 6),
              Text("Добавьте друга через поиск",
                  style: TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: AppTheme.accentIndigo,
      onRefresh: _loadChats,
      child: ListView.builder(
        itemCount: _chats.length,
        itemBuilder: (context, index) => _buildChatTile(_chats[index]),
      ),
    );
  }

  Widget _buildChatTile(Chat chat) {
    final initial = chat.partnerName.isNotEmpty
        ? chat.partnerName[0].toUpperCase()
        : '?';

    return ListTile(
      onTap: () => widget.onChatSelected(chat),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.accentIndigo.withValues(alpha: 0.2),
        child: Text(
          initial,
          style: const TextStyle(
              color: AppTheme.accentIndigo, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(chat.partnerName,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: chat.lastMessage != null
          ? Text(
              chat.lastMessage!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            )
          : const Text("Нет сообщений",
              style: TextStyle(color: Colors.white24, fontSize: 12)),
      trailing: chat.lastMessageAt != null
          ? Text(
              _formatTime(chat.lastMessageAt!),
              style:
                  const TextStyle(fontSize: 11, color: Colors.white24),
            )
          : null,
    );
  }

  // ── Friend requests list ──────────────────────────────────────────────────────

  Widget _buildRequestsList() {
    if (_pendingRequests.isEmpty) {
      return Center(
        child: Opacity(
          opacity: 0.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.people_outline, size: 48, color: Colors.white),
              SizedBox(height: 12),
              Text("Заявок пока нет",
                  style: TextStyle(fontSize: 14, color: Colors.white)),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _pendingRequests.length,
      itemBuilder: (context, index) =>
          _buildRequestTile(_pendingRequests[index]),
    );
  }

  Widget _buildRequestTile(FriendRequest req) {
    final isResponding = _respondingIds.contains(req.userId);

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.accentIndigo.withValues(alpha: 0.2),
        child: Text(
          req.username[0].toUpperCase(),
          style: const TextStyle(
              color: AppTheme.accentIndigo, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(req.username,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: const Text("Хочет добавить вас в друзья",
          style: TextStyle(color: Colors.white38, fontSize: 12)),
      trailing: isResponding
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.accentIndigo),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.check_circle_outline,
                      color: Colors.greenAccent),
                  tooltip: "Принять",
                  onPressed: () =>
                      _respondToRequest(req, 'accepted'),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel_outlined,
                      color: Colors.redAccent),
                  tooltip: "Отклонить",
                  onPressed: () =>
                      _respondToRequest(req, 'declined'),
                ),
              ],
            ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day}.${dt.month.toString().padLeft(2, '0')}';
  }
}
