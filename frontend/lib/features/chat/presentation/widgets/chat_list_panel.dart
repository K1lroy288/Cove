import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart' show AppTheme, AppColors;
import '../../../auth/presentation/auth_notifier.dart';
import '../../../friends/data/models/friend.dart';
import '../../../friends/data/services/friendship_service.dart';
import '../../../user/data/models/friend_request.dart';
import '../../../user/data/models/user_dto.dart';
import '../../../user/data/services/user_service.dart';
import '../../../user/presentation/widgets/user_avatar.dart';
import '../../../user/presentation/widgets/user_profile_sheet.dart';
import '../../data/models/chat.dart';
import '../../data/services/chat_service.dart';
import '../notification_notifier.dart';
import 'create_group_sheet.dart';

enum _Tab { chats, requests }

class ChatListPanel extends StatefulWidget {
  final Function(Chat) onChatSelected;
  final VoidCallback? onFriendAccepted;

  const ChatListPanel({super.key, required this.onChatSelected, this.onFriendAccepted});

  // ignore: library_private_types_in_public_api
  static GlobalKey<_ChatListPanelState> createKey() => GlobalKey<_ChatListPanelState>();

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

  String? _errorMessage;

  StreamSubscription? _groupCreatedSub;
  StreamSubscription? _groupDissolvedSub;

  Timer? _minuteTimer;
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
    _loadSentRequestIds();
    _minuteTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) { if (mounted) setState(() {}); },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribeToGroupEvents());
  }

  void _subscribeToGroupEvents() {
    final notifier = context.read<NotificationNotifier>();

    _groupCreatedSub = notifier.groupCreatedStream.listen((event) {
      if (!mounted) return;
      // Перезагружаем список чтобы получить полный ChatDTO от сервера
      _loadChats();
    });

    _groupDissolvedSub = notifier.groupDissolvedStream.listen((event) {
      if (!mounted) return;
      setState(() => _chats.removeWhere((c) => c.id == event.chatId));
    });
  }

  @override
  void dispose() {
    _groupCreatedSub?.cancel();
    _groupDissolvedSub?.cancel();
    _minuteTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void reload() => _loadChats();
  void refreshPendingRequests() => _loadPendingRequests();

  void incrementUnreadCount(int chatId) {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx == -1) return;
    setState(() => _chats[idx] = _chats[idx].copyWith(unreadCount: _chats[idx].unreadCount + 1));
  }

  void clearUnreadCount(int chatId) {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx == -1) return;
    setState(() => _chats[idx] = _chats[idx].copyWith(unreadCount: 0));
  }

  Chat? findChatById(int chatId) {
    try {
      return _chats.firstWhere((c) => c.id == chatId);
    } catch (_) {
      return null;
    }
  }

  void _openCreateGroupSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateGroupSheet(
        onCreated: (group) {
          setState(() {
            _chats.insert(0, group);
          });
          widget.onChatSelected(group);
        },
      ),
    );
  }

  void updateChatMessage(int chatId, String content, DateTime time) {
    final idx = _chats.indexWhere((c) => c.id == chatId);
    if (idx == -1) {
      _loadChats();
      return;
    }
    setState(() {
      _chats[idx] = _chats[idx].copyWith(lastMessage: content, lastMessageAt: time);
      _sortByRecent();
    });
  }

  void _sortByRecent() {
    _chats.sort((a, b) {
      if (a.lastMessageAt == null) return 1;
      if (b.lastMessageAt == null) return -1;
      return b.lastMessageAt!.compareTo(a.lastMessageAt!);
    });
  }

  Future<void> _loadChats() async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;

    final chats = await _chatService.getChats(token: token);
    if (mounted) {
      setState(() {
        _chats = chats;
        _sortByRecent();
        _isLoadingChats = false;
      });
      final partnerIds = chats
          .where((c) => !c.isGroup && c.partnerId != 0)
          .map((c) => c.partnerId)
          .toList();
      if (partnerIds.isNotEmpty) {
        context.read<NotificationNotifier>().fetchPresence(partnerIds, token);
      }
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

  Future<void> _loadSentRequestIds() async {
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;
    final ids = await _friendshipService.getSentRequestIds(token: token);
    if (mounted) setState(() => _sentRequestIds.addAll(ids));
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

    if (success && status == 'accepted') {
      _loadChats();
      widget.onFriendAccepted?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      color: colors.bg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text("Сообщения",
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary)),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.group_add_outlined, color: colors.textSecondary),
                  tooltip: "Создать группу",
                  onPressed: _openCreateGroupSheet,
                ),
                IconButton(
                    icon: Icon(Icons.edit_note, color: colors.textSecondary),
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
                style: TextStyle(color: colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: "Найти пользователя...",
                  hintStyle:
                      TextStyle(color: colors.textSecondary, fontSize: 14),
                  prefixIcon: Icon(Icons.search,
                      color: colors.textSecondary, size: 20),
                  suffixIcon: _hasQuery
                      ? IconButton(
                          icon: Icon(Icons.close,
                              color: colors.textSecondary, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _handleSearch('');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: colors.surface,
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
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: colors.surface,
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
    final colors = AppColors.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = tab),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isActive ? colors.bg : Colors.transparent,
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
                  color: isActive ? colors.textPrimary : colors.textSecondary,
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
            style: TextStyle(color: AppColors.of(context).textSecondary, fontSize: 14)),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildUserResultCard(UserDTO user) {
    final isAlreadyFriend = _friends.any((f) => f.id == user.id);
    final hasIncomingRequest = _pendingRequests.any((r) => r.userId == user.id);
    final hasSentRequest = _sentRequestIds.contains(user.id);

    final String subtitle;
    final IconData trailingIcon;
    final Color trailingColor;

    if (isAlreadyFriend) {
      subtitle = "Уже в друзьях";
      trailingIcon = Icons.check_circle_outline;
      trailingColor = Colors.greenAccent;
    } else if (hasIncomingRequest) {
      subtitle = "Прислал вам заявку";
      trailingIcon = Icons.mail_outline;
      trailingColor = Colors.amber;
    } else if (hasSentRequest) {
      subtitle = "Запрос отправлен";
      trailingIcon = Icons.schedule;
      trailingColor = Colors.white38;
    } else {
      subtitle = "Нажмите, чтобы открыть профиль";
      trailingIcon = Icons.person_add_outlined;
      trailingColor = AppTheme.accentIndigo;
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: () => UserProfileSheet.show(
        context,
        user.id,
        onOpenChat: widget.onChatSelected,
      ),
      leading: UserAvatar(
        avatarUrl: user.avatarUrl,
        initial: user.username.isNotEmpty ? user.username[0] : '?',
        radius: 24,
        bgColor: AppTheme.accentIndigo.withValues(alpha: 0.2),
        textColor: AppTheme.accentIndigo,
      ),
      title: Text(user.username,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(
              color: AppColors.of(context).textSecondary, fontSize: 12)),
      trailing: Icon(trailingIcon, color: trailingColor, size: 20),
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
      final colors = AppColors.of(context);
      return Center(
        child: Opacity(
          opacity: 0.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 48, color: colors.textPrimary),
              const SizedBox(height: 12),
              Text("Чатов пока нет",
                  style: TextStyle(fontSize: 14, color: colors.textPrimary)),
              const SizedBox(height: 6),
              Text("Добавьте друга через поиск",
                  style: TextStyle(fontSize: 12, color: colors.textPrimary)),
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
    final colors = AppColors.of(context);
    final avatarColor =
        chat.isGroup ? Colors.teal : AppTheme.accentIndigo;
    final avatarBg = avatarColor.withValues(alpha: 0.2);
    final partnerOnline = !chat.isGroup &&
        context.watch<NotificationNotifier>().isOnline(chat.partnerId);

    return ListTile(
      onTap: () => widget.onChatSelected(chat),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          UserAvatar(
            avatarUrl: chat.isGroup ? null : chat.partnerAvatarUrl,
            initial: chat.avatarInitial,
            radius: 24,
            bgColor: avatarBg,
            textColor: avatarColor,
          ),
          if (chat.isGroup)
            Positioned(
              right: 0,
              bottom: 0,
              child: CircleAvatar(
                radius: 9,
                backgroundColor: colors.bg,
                child: Icon(Icons.group, size: 12, color: Colors.teal),
              ),
            ),
          if (partnerOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50),
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.bg, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              chat.displayName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: colors.textPrimary),
            ),
          ),
          if (chat.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
              decoration: BoxDecoration(
                color: AppTheme.accentIndigo,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  chat.unreadCount > 99 ? '99+' : '${chat.unreadCount}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      height: 1.2),
                ),
              ),
            ),
        ],
      ),
      subtitle: chat.lastMessage != null
          ? Text(
              chat.lastMessage!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            )
          : Text("Нет сообщений",
              style: TextStyle(color: colors.textSecondary, fontSize: 12)),
      trailing: chat.lastMessageAt != null
          ? Text(
              _formatTime(chat.lastMessageAt!),
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            )
          : null,
    );
  }

  // ── Friend requests list ──────────────────────────────────────────────────────

  Widget _buildRequestsList() {
    if (_pendingRequests.isEmpty) {
      final colors = AppColors.of(context);
      return Center(
        child: Opacity(
          opacity: 0.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 48, color: colors.textPrimary),
              const SizedBox(height: 12),
              Text("Заявок пока нет",
                  style: TextStyle(fontSize: 14, color: colors.textPrimary)),
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
      leading: UserAvatar(
        avatarUrl: req.avatarUrl,
        initial: req.username.isNotEmpty ? req.username[0] : '?',
        radius: 24,
        bgColor: AppTheme.accentIndigo.withValues(alpha: 0.2),
        textColor: AppTheme.accentIndigo,
      ),
      title: Text(req.username,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text("Хочет добавить вас в друзья",
          style: TextStyle(color: AppColors.of(context).textSecondary, fontSize: 12)),
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
    final local = dt.toLocal();
    final now = DateTime.now();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    }
    return '${local.day}.${local.month.toString().padLeft(2, '0')}';
  }
}
