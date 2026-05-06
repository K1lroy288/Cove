import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../auth/presentation/auth_notifier.dart';
import '../../data/models/chat.dart';
import '../../data/models/message.dart';
import '../../data/services/chat_service.dart';

class ChatWindowPanel extends StatefulWidget {
  final Chat chat;
  final VoidCallback onBack;

  const ChatWindowPanel({super.key, required this.chat, required this.onBack});

  @override
  State<ChatWindowPanel> createState() => _ChatWindowPanelState();
}

class _ChatWindowPanelState extends State<ChatWindowPanel> {
  final ChatService _api = ChatService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  int _optimisticCounter = -1; // negative IDs for optimistic messages

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void didUpdateWidget(ChatWindowPanel old) {
    super.didUpdateWidget(old);
    if (old.chat.id != widget.chat.id) {
      setState(() {
        _messages = [];
        _isLoading = true;
      });
      _loadMessages();
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final auth = context.read<AuthNotifier>();
    if (auth.token == null) return;

    final msgs = await _api.getMessages(
      chatId: widget.chat.id,
      token: auth.token!,
    );

    if (mounted) {
      setState(() {
        _messages = msgs;
        _isLoading = false;
      });
      _scrollToBottom();
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
    setState(() => _isSending = true);

    // Optimistic insert
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
        final idx = _messages.indexWhere((m) => m.id == tempId);
        if (sent != null && idx != -1) {
          _messages[idx] = sent;
        } else if (idx != -1) {
          // Mark failed — keep optimistic with red tint handled by isOptimistic
          _messages[idx] = optimistic.copyWith(isOptimistic: true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.darkBg,
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Colors.white10),
          Expanded(child: _buildMessageList()),
          const Divider(height: 1, color: Colors.white10),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
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
            backgroundColor: AppTheme.accentIndigo.withValues(alpha: 0.2),
            child: Text(
              widget.chat.partnerName[0].toUpperCase(),
              style: const TextStyle(
                  color: AppTheme.accentIndigo,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.chat.partnerName,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const Text("в сети",
                  style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20, color: Colors.white38),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadMessages();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppTheme.accentIndigo));
    }

    if (_messages.isEmpty) {
      return Center(
        child: Opacity(
          opacity: 0.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.chat_bubble_outline, size: 48, color: Colors.white),
              SizedBox(height: 12),
              Text("Начните общение",
                  style: TextStyle(fontSize: 14, color: Colors.white)),
            ],
          ),
        ),
      );
    }

    final auth = context.read<AuthNotifier>();
    final myId = int.tryParse(auth.userId ?? '') ?? -1;

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final msg = _messages[index];
        final isMe = msg.senderId == myId;
        final showDate = index == 0 ||
            !_isSameDay(_messages[index - 1].createdAt, msg.createdAt);

        return Column(
          children: [
            if (showDate) _buildDateDivider(msg.createdAt),
            _buildBubble(msg, isMe),
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

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: Colors.white10)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(label,
                style: const TextStyle(fontSize: 11, color: Colors.white24)),
          ),
          const Expanded(child: Divider(color: Colors.white10)),
        ],
      ),
    );
  }

  Widget _buildBubble(Message msg, bool isMe) {
    final failed = msg.isOptimistic;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.65,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isMe
              ? (failed
                  ? Colors.redAccent.withValues(alpha: 0.3)
                  : AppTheme.accentIndigo)
              : AppTheme.surface,
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
                fontSize: 14,
                color: isMe ? Colors.white : Colors.white.withValues(alpha: 0.9),
              ),
            ),
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
                        : Colors.white38,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  Icon(
                    failed ? Icons.error_outline : Icons.done,
                    size: 12,
                    color: failed
                        ? Colors.redAccent
                        : Colors.white.withValues(alpha: 0.6),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _inputController,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: "Напишите что-нибудь...",
                hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
                filled: true,
                fillColor: AppTheme.surface,
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
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
