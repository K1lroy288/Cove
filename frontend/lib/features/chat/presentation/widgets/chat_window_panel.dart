import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart' show AppTheme, AppColors;
import '../../../auth/presentation/auth_notifier.dart';
import '../../../user/presentation/widgets/user_profile_sheet.dart';
import '../../data/models/chat.dart';
import '../../data/models/message.dart';
import '../../data/models/notification.dart';
import '../../data/services/chat_service.dart';
import '../notification_notifier.dart';
import '../../../settings/data/models/user_settings.dart';
import '../../../settings/presentation/settings_notifier.dart';
import 'group_info_sheet.dart';

class ChatWindowPanel extends StatefulWidget {
  final Chat chat;
  final VoidCallback onBack;
  final Function(Message)? onMessageSent;

  const ChatWindowPanel({super.key, required this.chat, required this.onBack, this.onMessageSent});

  @override
  State<ChatWindowPanel> createState() => _ChatWindowPanelState();
}

class _ChatWindowPanelState extends State<ChatWindowPanel> {
  final ChatService _api = ChatService();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<int, String> _drafts = {};

  StreamSubscription<ChatMessageNotification>? _chatSub;
  StreamSubscription<MessageDeliveredNotification>? _deliveredSub;
  StreamSubscription<MessageReadNotification>? _readSub;
  Timer? _minuteTimer;
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  int _optimisticCounter = -1;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToChat(widget.chat.id);
    _minuteTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) { if (mounted) setState(() {}); },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didUpdateWidget(ChatWindowPanel old) {
    super.didUpdateWidget(old);
    if (old.chat.id != widget.chat.id) {
      _drafts[old.chat.id] = _inputController.text;
      final restored = _drafts[widget.chat.id] ?? '';
      _inputController.text = restored;
      _inputController.selection =
          TextSelection.collapsed(offset: restored.length);

      final notif = context.read<NotificationNotifier>();
      notif.unsubscribeFromChat(old.chat.id);
      _chatSub?.cancel();
      _deliveredSub?.cancel();
      _readSub?.cancel();
      setState(() {
        _messages = [];
        _isLoading = true;
      });
      _loadMessages();
      _subscribeToChat(widget.chat.id);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    context.read<NotificationNotifier>().unsubscribeFromChat(widget.chat.id);
    _chatSub?.cancel();
    _deliveredSub?.cancel();
    _readSub?.cancel();
    _minuteTimer?.cancel();
    _inputController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _subscribeToChat(int chatId) {
    final notif = context.read<NotificationNotifier>();
    notif.subscribeToChat(chatId);

    _chatSub = notif.chatMessageStream
        .where((m) => m.chatId == chatId)
        .listen(_onIncomingMessage, onError: (e) => log('chat ws error: $e'));

    _deliveredSub = notif.messageDeliveredStream
        .where((e) => e.chatId == chatId)
        .listen(_onMessageDelivered);

    _readSub = notif.messageReadStream
        .where((e) => e.chatId == chatId)
        .listen(_onMessageRead);
  }

  void _onIncomingMessage(ChatMessageNotification n) {
    if (!mounted) return;
    setState(() {
      _messages.add(Message(
        id: n.id,
        chatId: n.chatId,
        senderId: n.senderId,
        content: n.content,
        createdAt: n.createdAt,
      ));
      _messages.sort((a, b) => a.id.compareTo(b.id));
    });
    _scrollToBottom();
  }

  void _onMessageDelivered(MessageDeliveredNotification n) {
    if (!mounted) return;
    setState(() {
      _messages = _messages.map((m) {
        if (m.id <= n.messageId && m.status == MessageStatus.sent) {
          return m.copyWith(status: MessageStatus.delivered);
        }
        return m;
      }).toList();
    });
  }

  void _onMessageRead(MessageReadNotification n) {
    if (!mounted) return;
    setState(() {
      _messages = _messages.map((m) {
        if (m.id <= n.lastReadMessageId && m.status != MessageStatus.read) {
          return m.copyWith(status: MessageStatus.read);
        }
        return m;
      }).toList();
    });
  }

  Future<void> _loadMessages() async {
    final auth = context.read<AuthNotifier>();
    if (auth.token == null) return;

    final (msgs, _) = await _api.getMessages(
      chatId: widget.chat.id,
      token: auth.token!,
    );

    if (mounted) {
      setState(() {
        final loadedIds = msgs.map((m) => m.id).toSet();
        final extras = _messages
            .where((m) => m.id > 0 && !loadedIds.contains(m.id))
            .toList();
        _messages = [...msgs, ...extras]
          ..sort((a, b) => a.id.compareTo(b.id));
        _isLoading = false;
      });
      _scrollToBottom();

      // Отмечаем прочитанными все загруженные сообщения
      if (msgs.isNotEmpty) {
        final latestId = msgs.last.id;
        context.read<NotificationNotifier>().markRead(widget.chat.id, latestId);
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;

    final auth = context.read<AuthNotifier>();
    final myId = int.tryParse(auth.userId ?? '');
    if (myId == null || auth.token == null) return;

    _inputController.clear();
    _drafts.remove(widget.chat.id);
    _focusNode.requestFocus();
    setState(() => _isSending = true);

    final tempId = _optimisticCounter--;
    final optimistic = Message(
      id: tempId,
      chatId: widget.chat.id,
      senderId: myId,
      content: text,
      createdAt: DateTime.now(),
      isOptimistic: true,
    );
    setState(() => _messages.add(optimistic));
    _scrollToBottom();

    final sent = await _api.sendMessage(
      chatId: widget.chat.id,
      content: text,
      token: auth.token!,
    );

    if (mounted) {
      setState(() {
        _isSending = false;
        if (sent != null) {
          _messages.removeWhere((m) => m.id == tempId);
          _messages.add(sent);
          _messages.sort((a, b) => a.id.compareTo(b.id));
          widget.onMessageSent?.call(sent);
        } else {
          final idx = _messages.indexWhere((m) => m.id == tempId);
          if (idx != -1) {
            _messages[idx] = optimistic.copyWith(isOptimistic: true);
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final chatSettings = context.watch<SettingsNotifier>().settings;
    return Container(
      color: colors.bg,
      child: Column(
        children: [
          _buildHeader(),
          Divider(height: 1, color: colors.divider),
          Expanded(child: _buildMessageList(chatSettings)),
          Divider(height: 1, color: colors.divider),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final chat = widget.chat;
    final colors = AppColors.of(context);
    final isGroup = chat.isGroup;
    final avatarColor = isGroup ? Colors.teal : AppTheme.accentIndigo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, size: 18),
            onPressed: widget.onBack,
          ),
          CircleAvatar(
            radius: 18,
            backgroundColor: avatarColor.withValues(alpha: 0.2),
            child: Text(
              chat.avatarInitial,
              style: TextStyle(
                  color: avatarColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: isGroup ? null : () => UserProfileSheet.show(context, chat.partnerId),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    chat.displayName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (isGroup)
                    Text(
                      "${chat.memberCount ?? '?'} участников",
                      style: TextStyle(
                          color: colors.textSecondary, fontSize: 11),
                    )
                  else if (context
                      .watch<NotificationNotifier>()
                      .isOnline(chat.partnerId))
                    const Text(
                      'В сети',
                      style: TextStyle(color: Color(0xFF4CAF50), fontSize: 11),
                    ),
                ],
              ),
            ),
          ),
          if (isGroup)
            IconButton(
              icon: Icon(Icons.info_outline,
                  size: 20, color: colors.textSecondary),
              tooltip: "Информация о группе",
              onPressed: _openGroupInfo,
            ),
          IconButton(
            icon: Icon(Icons.refresh,
                size: 20, color: colors.textSecondary),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadMessages();
            },
          ),
        ],
      ),
    );
  }

  void _openGroupInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GroupInfoSheet(
        chat: widget.chat,
        onGroupLeft: widget.onBack,
        onGroupDeleted: widget.onBack,
      ),
    );
  }

  Widget _buildMessageList(UserSettings s) {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.accentIndigo));
    }

    if (_messages.isEmpty) {
      final colors = AppColors.of(context);
      return Center(
        child: Opacity(
          opacity: 0.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chat_bubble_outline, size: 48, color: colors.textPrimary),
              const SizedBox(height: 12),
              Text("Начните общение",
                  style: TextStyle(fontSize: 14, color: colors.textPrimary)),
            ],
          ),
        ),
      );
    }

    final auth = context.read<AuthNotifier>();
    final myId = int.tryParse(auth.userId ?? '') ?? -1;

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: s.uiDensityPadding),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isMe = msg.senderId == myId;
        final showDate = index == 0 ||
            !_isSameDay(_messages[index - 1].createdAt, msg.createdAt);
        final prevSameSender = !showDate &&
            index > 0 &&
            _messages[index - 1].senderId == msg.senderId;

        return Column(
          children: [
            if (showDate) _buildDateDivider(msg.createdAt),
            _buildBubble(msg, isMe, s, compact: s.compactChat && prevSameSender),
          ],
        );
      },
    );
  }

  Widget _buildDateDivider(DateTime date) {
    final now = DateTime.now();
    String label;
    if (_isSameDay(date, now)) {
      label = 'Сегодня';
    } else if (_isSameDay(date, now.subtract(const Duration(days: 1)))) {
      label = 'Вчера';
    } else {
      label = '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    }

    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: colors.divider)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label,
                style: TextStyle(fontSize: 11, color: colors.textSecondary)),
          ),
          Expanded(child: Divider(color: colors.divider)),
        ],
      ),
    );
  }

  Widget _buildBubble(Message msg, bool isMe, UserSettings s, {bool compact = false}) {
    final failed = msg.isOptimistic;
    final colors = AppColors.of(context);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(bottom: compact ? 2 : 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isMe
              ? (failed
                  ? Colors.redAccent.withValues(alpha: 0.3)
                  : AppTheme.accentIndigo)
              : colors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              msg.content,
              style: TextStyle(
                fontSize: s.chatFontSizeValue,
                color: isMe ? Colors.white : colors.textPrimary,
              ),
            ),
            if (s.showMessageTime) ...[
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(msg.createdAt),
                    style: TextStyle(
                      fontSize: 10,
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.6)
                          : colors.textSecondary,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    _buildStatusIcon(msg),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(Message msg) {
    if (msg.isOptimistic) {
      return const Icon(Icons.error_outline, size: 12, color: Colors.redAccent);
    }
    switch (msg.status) {
      case MessageStatus.read:
        return const Icon(Icons.done_all, size: 15, color: Color(0xFF80DEEA));
      case MessageStatus.delivered:
        return const Icon(Icons.done_all, size: 15, color: Colors.white);
      case MessageStatus.sent:
        return Icon(Icons.done, size: 15, color: Colors.white.withValues(alpha: 0.8));
    }
  }

  Widget _buildInputArea() {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _focusNode,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: "Напишите что-нибудь...",
                hintStyle: TextStyle(color: colors.textSecondary, fontSize: 14),
                filled: true,
                fillColor: colors.surface,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: _isSending
                ? const SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.accentIndigo)),
                  )
                : GestureDetector(
                    onTap: _sendMessage,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        color: AppTheme.accentIndigo,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.send_rounded,
                          color: Colors.white, size: 20),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
