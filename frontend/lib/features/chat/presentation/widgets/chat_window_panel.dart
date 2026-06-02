import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' show min;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:photo_view/photo_view.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/theme/app_theme.dart' show AppTheme, AppColors;
import '../../../auth/presentation/auth_notifier.dart';
import '../../../user/data/services/user_service.dart';
import '../../../user/presentation/widgets/user_profile_sheet.dart';
import '../../data/models/chat.dart';
import '../../data/models/message.dart';
import '../../data/models/notification.dart';
import '../../data/services/chat_service.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../notification_notifier.dart';
import '../../../settings/data/models/user_settings.dart';
import '../../../settings/presentation/settings_notifier.dart';
import 'group_info_sheet.dart';
import 'chat_attachments_sheet.dart';
import '../../../user/presentation/widgets/user_avatar.dart';

String _fileType(String ext) {
  const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
  const videoExts = {'mp4', 'mov', 'webm', 'avi', 'mkv', 'm4v'};
  const audioExts = {'m4a', 'mp3', 'wav', 'ogg', 'opus', 'aac'};
  if (imageExts.contains(ext)) return 'image';
  if (videoExts.contains(ext)) return 'video';
  if (audioExts.contains(ext)) return 'audio';
  return 'file';
}

Future<Uint8List?> _compressImageFile(String filePath) async {
  try {
    final bytes = await File(filePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    // Если фото и так маленькое — не перекодируем, отдаём оригинал (null = use filePath).
    if (longest <= 2560) return null;
    final resized = img.copyResize(
      decoded,
      width: decoded.width >= decoded.height ? 2560 : null,
      height: decoded.height > decoded.width ? 2560 : null,
      interpolation: img.Interpolation.average,
    );
    return Uint8List.fromList(img.encodeJpg(resized, quality: 92));
  } catch (_) {
    return null;
  }
}

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
  final _userService = UserService();
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final Map<int, String> _drafts = {};

  StreamSubscription<ChatMessageNotification>? _chatSub;
  StreamSubscription<MessageDeliveredNotification>? _deliveredSub;
  StreamSubscription<MessageReadNotification>? _readSub;
  StreamSubscription<MessageEditedNotification>? _editedSub;
  StreamSubscription<MessageDeletedNotification>? _deletedSub;
  StreamSubscription<TypingNotification>? _typingSub;
  StreamSubscription<ReactionUpdatedNotification>? _reactionSub;
  StreamSubscription<MessagePinnedNotification>? _pinnedSub;

  Timer? _minuteTimer;
  List<Message> _messages = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _isSending = false;
  int _optimisticCounter = -1;
  bool _showEmojiPicker = false;
  Map<int, String> _memberNames = {};
  Map<int, String?> _memberAvatars = {};

  // Reply / Edit
  Message? _replyingTo;
  Message? _editingMessage;
  PinnedMessage? _localPinnedMessage;

  // Partner presence
  DateTime? _partnerLastSeen;

  // Multi-select
  bool _selectionMode = false;
  final Set<int> _selectedMessageIds = {};

  // Typing indicator
  final Map<int, String> _typingUsers = {};
  final Map<int, Timer> _typingTimers = {};
  Timer? _typingDebounce;

  // Pending file
  String? _pendingFilePath;
  String? _pendingFileName;
  int? _pendingFileSize;
  String? _pendingFileType;

  // Voice recording
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
    _localPinnedMessage = widget.chat.pinnedMessage;
    _scrollController.addListener(_onScroll);
    _loadMessages();
    _subscribeToChat(widget.chat.id);
    _minuteTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) { if (mounted) setState(() {}); },
    );
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
    });
    _inputController.addListener(() {
      if (mounted) {
        setState(() {});
        _sendTypingDebounced();
      }
    });
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
      _editedSub?.cancel();
      _deletedSub?.cancel();
      _typingSub?.cancel();
      _reactionSub?.cancel();
      _pinnedSub?.cancel();
      _typingDebounce?.cancel();
      for (final t in _typingTimers.values) { t.cancel(); }

      if (_isRecording) {
        _recorder.cancel();
        _recordingTimer?.cancel();
        _isRecording = false;
        _recordingSeconds = 0;
      }
      setState(() {
        _messages = [];
        _isLoading = true;
        _isLoadingMore = false;
        _hasMore = true;
        _partnerLastSeen = null;
        _pendingFilePath = null;
        _pendingFileName = null;
        _pendingFileSize = null;
        _pendingFileType = null;
        _replyingTo = null;
        _editingMessage = null;
        _typingUsers.clear();
        _typingTimers.clear();
        _localPinnedMessage = widget.chat.pinnedMessage;
      });
      _memberNames.clear();
      _memberAvatars.clear();
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
    _editedSub?.cancel();
    _deletedSub?.cancel();
    _typingSub?.cancel();
    _reactionSub?.cancel();
    _pinnedSub?.cancel();
    _minuteTimer?.cancel();
    _recordingTimer?.cancel();
    _typingDebounce?.cancel();
    for (final t in _typingTimers.values) { t.cancel(); }
    _recorder.dispose();
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

    _editedSub = notif.messageEditedStream
        .where((e) => e.chatId == chatId)
        .listen(_onMessageEdited);

    _deletedSub = notif.messageDeletedStream
        .where((e) => e.chatId == chatId)
        .listen(_onMessageDeleted);

    _typingSub = notif.typingStream
        .where((e) => e.chatId == chatId)
        .listen(_onTyping);

    _reactionSub = notif.reactionUpdatedStream
        .where((e) => e.chatId == chatId)
        .listen(_onReactionUpdated);

    _pinnedSub = notif.messagePinnedStream
        .where((e) => e.chatId == chatId)
        .listen(_onMessagePinned);
  }

  void _onIncomingMessage(ChatMessageNotification n) {
    if (!mounted) return;
    setState(() {
      _messages.add(Message(
        id: n.id,
        chatId: n.chatId,
        senderId: n.senderId,
        content: n.content,
        type: n.type,
        fileName: n.fileName,
        fileSize: n.fileSize,
        createdAt: n.createdAt,
        repliedTo: n.replyTo != null ? RepliedMessage.fromJson(n.replyTo!) : null,
        forwardedFromId: n.forwardedFromId,
        forwardedFromUsername: n.forwardedFromUsername,
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

  void _onMessageEdited(MessageEditedNotification n) {
    if (!mounted) return;
    setState(() {
      _messages = _messages.map((m) {
        if (m.id == n.messageId) {
          return m.copyWith(content: n.newContent, editedAt: n.editedAt);
        }
        return m;
      }).toList();
    });
  }

  void _onMessageDeleted(MessageDeletedNotification n) {
    if (!mounted) return;
    setState(() {
      _messages = _messages.map((m) {
        if (m.id == n.messageId) return m.copyWith(isDeleted: true, content: '');
        return m;
      }).toList();
    });
  }

  void _onTyping(TypingNotification n) {
    if (!mounted) return;
    final myId = int.tryParse(context.read<AuthNotifier>().userId ?? '') ?? -1;
    if (n.userId == myId) return;
    _typingTimers[n.userId]?.cancel();
    setState(() => _typingUsers[n.userId] = n.username);
    _typingTimers[n.userId] = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _typingUsers.remove(n.userId));
    });
  }

  void _onReactionUpdated(ReactionUpdatedNotification n) {
    if (!mounted) return;
    setState(() {
      _messages = _messages.map((m) {
        if (m.id == n.messageId) {
          final reactions = n.reactions
              .map((r) => ReactionGroup.fromJson(r))
              .toList();
          return m.copyWith(reactions: reactions);
        }
        return m;
      }).toList();
    });
  }

  void _onMessagePinned(MessagePinnedNotification n) {
    if (!mounted) return;
    setState(() {
      if (n.pinned == null) {
        _localPinnedMessage = null;
      } else {
        _localPinnedMessage = PinnedMessage(
          id: (n.pinned!['id'] as num).toInt(),
          senderId: (n.pinned!['sender_id'] as num).toInt(),
          content: n.pinned!['content'] as String? ?? '',
          type: n.pinned!['type'] as String? ?? 'text',
        );
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    if (_scrollController.position.pixels <= 200) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (_messages.isEmpty) return;
    final auth = context.read<AuthNotifier>();
    if (auth.token == null) return;
    setState(() => _isLoadingMore = true);

    final beforeId = _messages.first.id;
    final (older, _) = await _api.getMessages(
      chatId: widget.chat.id,
      token: auth.token!,
      before: beforeId,
    );

    if (!mounted) return;
    setState(() {
      _isLoadingMore = false;
      if (older.isEmpty || older.length < 50) _hasMore = false;
      if (older.isNotEmpty) {
        final existingIds = _messages.map((m) => m.id).toSet();
        final newOnes = older.where((m) => !existingIds.contains(m.id));
        _messages = [...newOnes, ..._messages]
          ..sort((a, b) => a.id.compareTo(b.id));
      }
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
        _hasMore = msgs.length >= 50;
        if (!widget.chat.isGroup) {
          _memberNames = {widget.chat.partnerId: widget.chat.partnerName};
        }
      });
      _scrollToBottom();

      if (msgs.isNotEmpty) {
        final latestId = msgs.last.id;
        context.read<NotificationNotifier>().markRead(widget.chat.id, latestId);
      }

      if (widget.chat.isGroup) {
        final members = await _api.getGroupMembers(
          chatId: widget.chat.id,
          token: auth.token!,
        );
        if (mounted) {
          setState(() {
            _memberNames = {for (final m in members) m.userId: m.username};
            _memberAvatars = {for (final m in members) m.userId: m.avatarUrl};
          });
        }
      } else {
        // Загружаем lastSeenAt партнёра для DM
        final profile = await _userService.getUserProfile(
          widget.chat.partnerId,
          auth.token!,
        );
        if (mounted && profile != null) {
          setState(() => _partnerLastSeen = profile.lastSeenAt);
        }
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

  void _sendTypingDebounced() {
    if (_editingMessage != null || _inputController.text.isEmpty) return;
    _typingDebounce?.cancel();
    _typingDebounce = Timer(const Duration(milliseconds: 500), () {
      context.read<NotificationNotifier>().sendTyping(widget.chat.id);
    });
  }

  Future<void> _pickFile() async {
    try {
      final XFile? xfile = await openFile();
      if (xfile == null) return;
      final size = await xfile.length();
      final name = xfile.name;
      final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
      if (mounted) {
        setState(() {
          _pendingFilePath = xfile.path;
          _pendingFileName = name;
          _pendingFileSize = size;
          _pendingFileType = _fileType(ext);
        });
      }
    } catch (_) {
      if (mounted) _showManualFileInputDialog();
    }
  }

  void _showManualFileInputDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final colors = AppColors.of(ctx);
        return AlertDialog(
          title: const Text('Путь к файлу'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: '/home/user/image.jpg',
              hintStyle: TextStyle(color: colors.textSecondary),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () async {
                final path = ctrl.text.trim();
                Navigator.pop(ctx);
                if (path.isEmpty) return;
                final file = File(path);
                if (!file.existsSync()) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Файл не найден')),
                    );
                  }
                  return;
                }
                final size = await file.length();
                final name = path.split(Platform.pathSeparator).last;
                final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
                if (mounted) {
                  setState(() {
                    _pendingFilePath = path;
                    _pendingFileName = name;
                    _pendingFileSize = size;
                    _pendingFileType = _fileType(ext);
                  });
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  bool _shouldShowMicButton() =>
      _inputController.text.trim().isEmpty && _pendingFilePath == null;

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Нет доступа к микрофону')),
        );
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    if (!mounted) return;
    setState(() { _isRecording = true; _recordingSeconds = 0; });
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recordingSeconds++);
    });
  }

  Future<void> _stopAndSendRecording() async {
    _recordingTimer?.cancel();
    final auth = context.read<AuthNotifier>();
    final myId = int.tryParse(auth.userId ?? '');
    final token = auth.token;
    if (myId == null || token == null) { await _recorder.stop(); return; }

    final path = await _recorder.stop();
    if (mounted) setState(() { _isRecording = false; _recordingSeconds = 0; });
    if (path == null) return;

    final file = File(path);
    final fileSize = await file.length();
    final fileName = path.split(Platform.pathSeparator).last;

    final tempId = _optimisticCounter--;
    final optimistic = Message(
      id: tempId, chatId: widget.chat.id, senderId: myId,
      content: path, type: 'audio', fileName: fileName, fileSize: fileSize,
      createdAt: DateTime.now(), isOptimistic: true,
    );
    if (mounted) setState(() => _messages.add(optimistic));
    _scrollToBottom();

    final upload = await _api.uploadFile(token: token, filePath: path, fileName: fileName);
    if (!mounted) return;
    if (upload == null) return;

    final sent = await _api.sendMessage(
      chatId: widget.chat.id, content: upload.url,
      token: token, type: 'audio',
      fileName: upload.fileName, fileSize: upload.fileSize,
    );
    if (mounted) {
      setState(() {
        if (sent != null) {
          _messages.removeWhere((m) => m.id == tempId);
          _messages.add(sent);
          _messages.sort((a, b) => a.id.compareTo(b.id));
          widget.onMessageSent?.call(sent);
        }
      });
    }
    try { await file.delete(); } catch (_) {}
  }

  Future<void> _cancelRecording() async {
    _recordingTimer?.cancel();
    await _recorder.cancel();
    if (mounted) setState(() { _isRecording = false; _recordingSeconds = 0; });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    final hasFile = _pendingFilePath != null;
    if ((text.isEmpty && !hasFile) || _isSending) return;

    // Edit mode
    if (_editingMessage != null) {
      await _confirmEdit();
      return;
    }

    final auth = context.read<AuthNotifier>();
    final myId = int.tryParse(auth.userId ?? '');
    if (myId == null || auth.token == null) return;

    if (hasFile) {
      final filePath = _pendingFilePath!;
      final fileName = _pendingFileName;
      final fileSize = _pendingFileSize;
      final fileType = _pendingFileType!;
      final caption = text.isNotEmpty ? text : null;
      final replyId = _replyingTo?.id;

      setState(() {
        _pendingFilePath = null;
        _pendingFileName = null;
        _pendingFileSize = null;
        _pendingFileType = null;
        _replyingTo = null;
        _isSending = true;
      });
      _inputController.clear();
      _drafts.remove(widget.chat.id);

      final tempId = _optimisticCounter--;
      final optimistic = Message(
        id: tempId,
        chatId: widget.chat.id,
        senderId: myId,
        content: filePath,
        type: fileType,
        fileName: fileName,
        fileSize: fileSize,
        caption: caption,
        createdAt: DateTime.now(),
        isOptimistic: true,
      );
      setState(() => _messages.add(optimistic));
      _scrollToBottom();

      Uint8List? compressed;
      if (fileType == 'image') {
        compressed = await compute(_compressImageFile, filePath);
      }

      final upload = await _api.uploadFile(
        token: auth.token!,
        filePath: compressed == null ? filePath : null,
        fileBytes: compressed,
        fileName: compressed != null ? 'image.jpg' : fileName,
      );
      if (!mounted) return;

      if (upload == null) {
        setState(() { _isSending = false; });
        return;
      }

      final sent = await _api.sendMessage(
        chatId: widget.chat.id,
        content: upload.url,
        token: auth.token!,
        type: upload.type,
        fileName: upload.fileName,
        fileSize: upload.fileSize,
        caption: caption,
        replyToId: replyId,
      );

      if (mounted) {
        setState(() {
          _isSending = false;
          if (sent != null) {
            _messages.removeWhere((m) => m.id == tempId);
            _messages.add(sent);
            _messages.sort((a, b) => a.id.compareTo(b.id));
            widget.onMessageSent?.call(sent);
          }
        });
      }
    } else {
      final replyId = _replyingTo?.id;
      _inputController.clear();
      _drafts.remove(widget.chat.id);
      if (!_showEmojiPicker) _focusNode.requestFocus();
      setState(() { _isSending = true; _replyingTo = null; });

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
        replyToId: replyId,
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
  }

  Future<void> _confirmEdit() async {
    final msg = _editingMessage;
    if (msg == null) return;
    final text = _inputController.text.trim();
    if (text.isEmpty || text == msg.content) {
      _cancelEdit();
      return;
    }
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;
    setState(() { _editingMessage = null; });
    _inputController.clear();

    final updated = await _api.editMessage(
      chatId: widget.chat.id,
      messageId: msg.id,
      content: text,
      token: token,
    );
    if (updated != null && mounted) {
      setState(() {
        _messages = _messages.map((m) => m.id == msg.id ? updated : m).toList();
      });
    }
  }

  void _cancelEdit() {
    setState(() { _editingMessage = null; });
    _inputController.clear();
  }

  void _cancelReply() {
    setState(() { _replyingTo = null; });
  }

  void _showMessageMenu(Message msg, bool isMe) {
    final isAdmin = widget.chat.isAdmin && widget.chat.isGroup;
    final canEdit = isMe && !msg.isDeleted && msg.type == 'text';
    final canDelete = (isMe || isAdmin) && !msg.isDeleted;
    final canPin = (isMe || isAdmin) && !msg.isDeleted;
    final isCurrentlyPinned = _localPinnedMessage?.id == msg.id;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = AppColors.of(ctx);
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!msg.isDeleted)
                _menuItem(ctx, Icons.reply, 'Ответить', () {
                  Navigator.pop(ctx);
                  setState(() { _replyingTo = msg; _editingMessage = null; });
                  _focusNode.requestFocus();
                }),
              if (msg.type == 'text' && !msg.isDeleted)
                _menuItem(ctx, Icons.copy_outlined, 'Копировать', () {
                  Navigator.pop(ctx);
                  Clipboard.setData(ClipboardData(text: msg.content));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Скопировано'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }),
              if (canEdit)
                _menuItem(ctx, Icons.edit_outlined, 'Редактировать', () {
                  Navigator.pop(ctx);
                  setState(() {
                    _editingMessage = msg;
                    _replyingTo = null;
                    _inputController.text = msg.content;
                    _inputController.selection =
                        TextSelection.collapsed(offset: msg.content.length);
                  });
                  _focusNode.requestFocus();
                }),
              if (!msg.isDeleted)
                _menuItem(ctx, Icons.forward_outlined, 'Переслать', () {
                  Navigator.pop(ctx);
                  _showForwardSheet(msg);
                }),
              if (canPin)
                _menuItem(
                  ctx,
                  isCurrentlyPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  isCurrentlyPinned ? 'Открепить' : 'Закрепить',
                  () async {
                    Navigator.pop(ctx);
                    final token = context.read<AuthNotifier>().token;
                    if (token == null) return;
                    if (isCurrentlyPinned) {
                      await _api.unpinMessage(chatId: widget.chat.id, token: token);
                      if (mounted) setState(() => _localPinnedMessage = null);
                    } else {
                      final ok = await _api.pinMessage(
                        chatId: widget.chat.id, messageId: msg.id, token: token);
                      if (ok && mounted) {
                        setState(() => _localPinnedMessage = PinnedMessage(
                          id: msg.id, senderId: msg.senderId,
                          content: msg.content, type: msg.type,
                        ));
                      }
                    }
                  },
                ),
              if (!msg.isDeleted)
                _menuItem(ctx, Icons.emoji_emotions_outlined, 'Реакция', () {
                  Navigator.pop(ctx);
                  _showReactionPicker(msg);
                }),
              if (canDelete)
                _menuItem(ctx, Icons.delete_outline, 'Удалить', () async {
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (dctx) => AlertDialog(
                      title: const Text('Удалить сообщение?'),
                      content: const Text('Сообщение удалится у всех участников.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dctx, false),
                          child: const Text('Отмена'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dctx, true),
                          child: const Text('Удалить',
                              style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true || !mounted) return;
                  final token = context.read<AuthNotifier>().token;
                  if (token == null) return;
                  final ok = await _api.deleteMessage(
                    chatId: widget.chat.id, messageId: msg.id, token: token);
                  if (!mounted) return;
                  if (ok) {
                    setState(() {
                      final idx = _messages.indexWhere((m) => m.id == msg.id);
                      if (idx != -1) {
                        _messages[idx] = _messages[idx].copyWith(isDeleted: true, content: '');
                      }
                    });
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Не удалось удалить сообщение')),
                    );
                  }
                }),
            ],
          ),
        );
      },
    );
  }

  Widget _menuItem(BuildContext ctx, IconData icon, String label, VoidCallback onTap) {
    final colors = AppColors.of(ctx);
    return ListTile(
      leading: Icon(icon, color: colors.textPrimary, size: 22),
      title: Text(label, style: TextStyle(color: colors.textPrimary, fontSize: 15)),
      dense: true,
      onTap: onTap,
    );
  }

  void _showReactionPicker(Message msg) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '🔥', '👎'];
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = AppColors.of(ctx);
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: emojis.map((e) => GestureDetector(
              onTap: () async {
                Navigator.pop(ctx);
                await _api.toggleReaction(
                  chatId: widget.chat.id,
                  messageId: msg.id,
                  emoji: e,
                  token: token,
                );
              },
              child: Text(e, style: DefaultEmojiTextStyle.copyWith(fontSize: 30)),
            )).toList(),
          ),
        );
      },
    );
  }

  void _showForwardSheet(Message msg) {
    final token = context.read<AuthNotifier>().token;
    final username = context.read<AuthNotifier>().username ?? '';
    if (token == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ForwardSheet(
        chatService: _api,
        token: token,
        message: msg,
        senderUsername: username,
      ),
    );
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
          if (_typingUsers.isNotEmpty) _buildTypingIndicator(colors),
          if (_editingMessage != null) _buildEditBar(colors),
          if (_replyingTo != null && _editingMessage == null)
            _buildReplyPreviewBar(colors),
          if (_pendingFilePath != null) _buildPendingAttachment(colors),
          if (_isRecording)
            _buildRecordingBar(colors)
          else
            _buildInputArea(chatSettings),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: _showEmojiPicker && !_isRecording ? 256 : 0,
            child: _showEmojiPicker && !_isRecording
                ? EmojiPicker(
                    textEditingController: _inputController,
                    config: AppTheme.emojiPickerConfig(colors),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator(AppColors colors) {
    final names = _typingUsers.values.toList();
    final text = names.length == 1
        ? '${names[0]} печатает...'
        : '${names.join(', ')} печатают...';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          _TypingDots(color: colors.textSecondary),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 12, color: colors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildEditBar(AppColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      color: AppTheme.accentIndigo.withValues(alpha: 0.08),
      child: Row(
        children: [
          const Icon(Icons.edit, size: 16, color: AppTheme.accentIndigo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Редактирование',
              style: TextStyle(fontSize: 12, color: AppTheme.accentIndigo),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.close, size: 16, color: colors.textSecondary),
            onPressed: _cancelEdit,
          ),
        ],
      ),
    );
  }

  Widget _buildReplyPreviewBar(AppColors colors) {
    final reply = _replyingTo!;
    final previewText = reply.isDeleted
        ? 'Сообщение удалено'
        : (reply.type == 'text' ? reply.content : '[${reply.type}]');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 8, 6),
      color: AppTheme.accentIndigo.withValues(alpha: 0.08),
      child: Row(
        children: [
          Container(
            width: 3, height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accentIndigo,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _memberNames[reply.senderId] ?? 'Пользователь',
                  style: const TextStyle(
                    fontSize: 12, color: AppTheme.accentIndigo,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  previewText,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(Icons.close, size: 16, color: colors.textSecondary),
            onPressed: _cancelReply,
          ),
        ],
      ),
    );
  }

  Widget _buildPendingAttachment(AppColors colors) {
    final isImage = _pendingFileType == 'image';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      color: colors.surface,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: isImage
                ? Image.file(
                    File(_pendingFilePath!),
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _fileIconPlaceholder(colors),
                  )
                : _fileIconPlaceholder(colors),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _pendingFileName ?? 'Файл',
                  style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_pendingFileSize != null)
                  Text(
                    _formatFileSize(_pendingFileSize!),
                    style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: colors.textSecondary),
            onPressed: () => setState(() {
              _pendingFilePath = null;
              _pendingFileName = null;
              _pendingFileSize = null;
              _pendingFileType = null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _fileIconPlaceholder(AppColors colors) {
    return Container(
      width: 48,
      height: 48,
      color: AppTheme.accentIndigo.withValues(alpha: 0.15),
      child: const Icon(Icons.insert_drive_file_outlined,
          color: AppTheme.accentIndigo, size: 28),
    );
  }

  Widget _buildSelectionHeader() {
    final colors = AppColors.of(context);
    final count = _selectedMessageIds.length;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => setState(() {
              _selectionMode = false;
              _selectedMessageIds.clear();
            }),
          ),
          Expanded(
            child: Text(
              'Выбрано: $count',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
          if (count > 0) ...[
            IconButton(
              icon: Icon(Icons.forward_outlined, color: colors.textSecondary),
              tooltip: 'Переслать',
              onPressed: () {
                final msgs = _messages
                    .where((m) => _selectedMessageIds.contains(m.id))
                    .toList();
                setState(() {
                  _selectionMode = false;
                  _selectedMessageIds.clear();
                });
                if (msgs.isNotEmpty) _showForwardSheet(msgs.first);
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: 'Удалить',
              onPressed: () => _deleteSelectedMessages(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _deleteSelectedMessages() async {
    final ids = List<int>.from(_selectedMessageIds);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: Text('Удалить ${ids.length} сообщ.?'),
        content: const Text('Сообщения удалятся у всех участников.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dctx, true),
            child: const Text('Удалить',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
    final token = context.read<AuthNotifier>().token;
    if (token == null) return;
    for (final id in ids) {
      final ok =
          await _api.deleteMessage(chatId: widget.chat.id, messageId: id, token: token);
      if (!mounted) break;
      if (ok) {
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == id);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(isDeleted: true, content: '');
          }
        });
      }
    }
  }

  Widget _buildHeader() {
    if (_selectionMode) return _buildSelectionHeader();

    final chat = widget.chat;
    final colors = AppColors.of(context);
    final isGroup = chat.isGroup;
    final avatarColor = isGroup ? Colors.teal : AppTheme.accentIndigo;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                onPressed: widget.onBack,
              ),
              UserAvatar(
                avatarUrl: chat.isGroup ? null : chat.partnerAvatarUrl,
                initial: chat.avatarInitial,
                radius: 18,
                bgColor: avatarColor.withValues(alpha: 0.2),
                textColor: avatarColor,
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
                        )
                      else if (_partnerLastSeen != null)
                        Text(
                          _formatLastSeen(_partnerLastSeen!),
                          style: TextStyle(color: colors.textSecondary, fontSize: 11),
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
                icon: Icon(Icons.photo_library_outlined,
                    size: 20, color: colors.textSecondary),
                tooltip: "Вложения",
                onPressed: _openAttachments,
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
        ),
        if (_localPinnedMessage != null) _buildPinBanner(colors),
      ],
    );
  }

  Widget _buildPinBanner(AppColors colors) {
    final pin = _localPinnedMessage!;
    final preview = pin.type == 'text'
        ? pin.content
        : '[${pin.type}]';
    return GestureDetector(
      onTap: () {
        final idx = _messages.indexWhere((m) => m.id == pin.id);
        if (idx >= 0 && _scrollController.hasClients) {
          _scrollController.animateTo(
            idx * 72.0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        color: AppTheme.accentIndigo.withValues(alpha: 0.06),
        child: Row(
          children: [
            const Icon(Icons.push_pin, size: 14, color: AppTheme.accentIndigo),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                preview,
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openAttachments() {
    final auth = context.read<AuthNotifier>();
    ChatAttachmentsSheet.show(
      context,
      widget.chat.id,
      widget.chat.displayName,
      auth.token!,
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

    // Первый элемент — индикатор загрузки истории (если есть ещё сообщения)
    final extraItem = _isLoadingMore || _hasMore ? 1 : 0;

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: s.uiDensityPadding),
      itemCount: _messages.length + extraItem,
      itemBuilder: (context, index) {
        if (index == 0 && extraItem == 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: _isLoadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accentIndigo),
                    )
                  : const SizedBox.shrink(),
            ),
          );
        }
        final msgIndex = index - extraItem;
        final msg = _messages[msgIndex];
        final isMe = msg.senderId == myId;
        final showDate = msgIndex == 0 ||
            !_isSameDay(_messages[msgIndex - 1].createdAt, msg.createdAt);
        final prevSameSender = !showDate &&
            msgIndex > 0 &&
            _messages[msgIndex - 1].senderId == msg.senderId;

        return Column(
          children: [
            if (showDate) _buildDateDivider(msg.createdAt),
            _buildBubble(msg, isMe, myId, s, compact: s.compactChat && prevSameSender),
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

  Widget _buildBubble(Message msg, bool isMe, int myId, UserSettings s, {bool compact = false}) {
    final colors = AppColors.of(context);

    // Deleted message placeholder
    if (msg.isDeleted) {
      final widget_ = Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.divider),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.block, size: 13, color: colors.textSecondary),
          const SizedBox(width: 6),
          Text(
            'Сообщение удалено',
            style: TextStyle(
              fontSize: 13, color: colors.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ]),
      );
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(padding: EdgeInsets.only(bottom: compact ? 2 : 4), child: widget_),
      );
    }

    final failed = msg.isOptimistic;
    final hasCaption = (msg.type == 'image' || msg.type == 'video') &&
        (msg.caption?.isNotEmpty ?? false);

    Widget messageContent;
    if (msg.type == 'image') {
      messageContent = _buildImageContent(msg, roundAllCorners: !hasCaption);
    } else if (msg.type == 'video') {
      messageContent = _buildVideoContent(msg, roundAllCorners: !hasCaption);
    } else if (msg.type == 'audio') {
      messageContent = _buildAudioContent(msg, isMe, colors);
    } else if (msg.type == 'file') {
      messageContent = _buildFileContent(msg, isMe, colors);
    } else {
      messageContent = Text(
        msg.content,
        style: DefaultEmojiTextStyle.copyWith(
          fontSize: s.chatFontSizeValue,
          color: isMe ? Colors.white : colors.textPrimary,
        ),
      );
    }

    final isMedia = msg.type == 'image' || msg.type == 'video';

    Widget content = messageContent;
    if (isMedia) {
      content = Stack(
        children: [
          messageContent,
          if (s.showMessageTime)
            Positioned(
              bottom: hasCaption ? null : 6,
              top: hasCaption ? 6 : null,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatTime(msg.createdAt, s.use24hTime),
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      _buildStatusIcon(msg),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    }

    final bubble = Container(
      clipBehavior: Clip.antiAlias,
      constraints: BoxConstraints(
        maxWidth: min(MediaQuery.of(context).size.width * 0.65, 420.0),
      ),
      padding: isMedia
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
          if (msg.forwardedFromUsername != null)
            _buildForwardHeader(msg, isMe, colors),
          if (msg.repliedTo != null)
            _buildReplyQuote(msg.repliedTo!, isMe, colors),
          content,
          if (hasCaption)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Text(
                msg.caption!,
                style: DefaultEmojiTextStyle.copyWith(
                  fontSize: s.chatFontSizeValue,
                  color: isMe ? Colors.white : colors.textPrimary,
                ),
              ),
            ),
          if (s.showMessageTime && !isMedia) ...[
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _formatTime(msg.createdAt, s.use24hTime),
                  style: TextStyle(
                    fontSize: 10,
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.6)
                        : colors.textSecondary,
                  ),
                ),
                if (msg.editedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'изм.',
                      style: TextStyle(
                        fontSize: 10,
                        color: isMe
                            ? Colors.white.withValues(alpha: 0.5)
                            : colors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
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
    );

    final bubbleWithReactions = Column(
      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onLongPress: () {
            if (!_selectionMode) {
              setState(() {
                _selectionMode = true;
                _selectedMessageIds.add(msg.id);
              });
            } else {
              _showMessageMenu(msg, isMe);
            }
          },
          onSecondaryTap: () => _showMessageMenu(msg, isMe),
          onTap: _selectionMode
              ? () => setState(() {
                    if (_selectedMessageIds.contains(msg.id)) {
                      _selectedMessageIds.remove(msg.id);
                      if (_selectedMessageIds.isEmpty) _selectionMode = false;
                    } else {
                      _selectedMessageIds.add(msg.id);
                    }
                  })
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: _selectionMode && _selectedMessageIds.contains(msg.id)
                ? BoxDecoration(
                    color: AppTheme.accentIndigo.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  )
                : null,
            child: bubble,
          ),
        ),
        if (msg.reactions.isNotEmpty)
          _buildReactionRow(msg, myId, colors),
      ],
    );

    if (!isMe && s.showAvatars) {
      final name = _memberNames[msg.senderId] ?? '?';
      return Padding(
        padding: EdgeInsets.only(bottom: compact ? 2 : 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            compact
                ? const SizedBox(width: 36)
                : UserAvatar(
                    avatarUrl: _memberAvatars[msg.senderId],
                    initial: name.isNotEmpty ? name[0] : '?',
                    radius: 14,
                    bgColor: AppTheme.accentIndigo.withValues(alpha: 0.2),
                    textColor: AppTheme.accentIndigo,
                  ),
            const SizedBox(width: 6),
            bubbleWithReactions,
          ],
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: compact ? 2 : 4),
        child: bubbleWithReactions,
      ),
    );
  }

  Widget _buildForwardHeader(Message msg, bool isMe, AppColors colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.forward, size: 13,
              color: isMe ? Colors.white70 : AppTheme.accentIndigo),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              'Переслано от @${msg.forwardedFromUsername}',
              style: TextStyle(
                fontSize: 11,
                color: isMe ? Colors.white70 : AppTheme.accentIndigo,
                fontStyle: FontStyle.italic,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToMessage(int messageId) {
    // Ищем в загруженных сообщениях
    final extraItem = (_isLoadingMore || _hasMore) ? 1 : 0;
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx < 0 || !_scrollController.hasClients) return;
    final itemIdx = idx + extraItem;
    // Приблизительный offset — точный расчёт через keys сложен, используем itemExtent ~80
    final approxOffset = (itemIdx * 80.0)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      approxOffset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  Widget _buildReplyQuote(RepliedMessage reply, bool isMe, AppColors colors) {
    final quoteText = reply.type == 'text' ? reply.content : '[${reply.type}]';
    final senderName = _memberNames[reply.senderId] ?? reply.senderUsername;
    return GestureDetector(
      onTap: () => _scrollToMessage(reply.id),
      child: Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.15)
            : AppTheme.accentIndigo.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white54 : AppTheme.accentIndigo,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isMe ? Colors.white70 : AppTheme.accentIndigo,
            ),
          ),
          Text(
            quoteText,
            style: DefaultEmojiTextStyle.copyWith(
              fontSize: 11,
              color: isMe
                  ? Colors.white.withValues(alpha: 0.75)
                  : colors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildReactionRow(Message msg, int myId, AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: msg.reactions.map((r) {
          final isMine = r.hasMine;
          return GestureDetector(
            onTap: () async {
              final token = context.read<AuthNotifier>().token;
              if (token == null) return;
              await _api.toggleReaction(
                chatId: widget.chat.id,
                messageId: msg.id,
                emoji: r.emoji,
                token: token,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: isMine
                    ? AppTheme.accentIndigo.withValues(alpha: 0.2)
                    : colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isMine ? AppTheme.accentIndigo : colors.divider,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.emoji, style: DefaultEmojiTextStyle.copyWith(fontSize: 14)),
                  if (r.count > 1) ...[
                    const SizedBox(width: 3),
                    Text(
                      '${r.count}',
                      style: TextStyle(
                        fontSize: 11,
                        color: isMine ? AppTheme.accentIndigo : colors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildImageContent(Message msg, {bool roundAllCorners = true}) {
    final isLocal = msg.isOptimistic && !msg.content.startsWith('http');
    final radius = roundAllCorners
        ? BorderRadius.circular(16)
        : const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          );
    final image = ClipRRect(
      borderRadius: radius,
      child: isLocal
          ? Image.file(
              File(msg.content),
              width: double.infinity,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              errorBuilder: (_, _, _) => const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.broken_image_outlined, size: 40)),
              ),
            )
          : Image.network(
              msg.content,
              width: double.infinity,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const SizedBox(
                      height: 140,
                      child: Center(
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.accentIndigo)),
                    ),
              errorBuilder: (_, _, _) => const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.broken_image_outlined, size: 40)),
              ),
            ),
    );
    if (isLocal) return image;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _FullscreenImagePage(url: msg.content),
        fullscreenDialog: true,
      )),
      child: image,
    );
  }

  Widget _buildVideoContent(Message msg, {bool roundAllCorners = true}) {
    final radius = roundAllCorners
        ? BorderRadius.circular(16)
        : const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
          );
    if (msg.isOptimistic) {
      return ClipRRect(
        borderRadius: radius,
        child: const SizedBox(
          width: double.infinity,
          height: 180,
          child: ColoredBox(
            color: Colors.black87,
            child: Center(child: CircularProgressIndicator(color: Colors.white)),
          ),
        ),
      );
    }
    return _VideoPlayerWidget(url: msg.content);
  }

  Widget _buildAudioContent(Message msg, bool isMe, AppColors colors) {
    if (msg.isOptimistic) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(
          width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentIndigo),
        ),
        const SizedBox(width: 10),
        Text('Голосовое', style: TextStyle(
          color: isMe ? Colors.white70 : colors.textPrimary, fontSize: 13)),
      ]);
    }
    return _AudioPlayerWidget(url: msg.content, isMe: isMe);
  }

  Widget _buildFileContent(Message msg, bool isMe, AppColors colors) {
    final canOpen = !msg.isOptimistic && msg.content.startsWith('http');
    return GestureDetector(
      onTap: canOpen
          ? () => launchUrl(Uri.parse(msg.content),
              mode: LaunchMode.externalApplication)
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.insert_drive_file_outlined,
            color: isMe ? Colors.white70 : AppTheme.accentIndigo,
            size: 32,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.fileName ?? 'Файл',
                  style: TextStyle(
                    color: isMe ? Colors.white : colors.textPrimary,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (msg.fileSize != null)
                  Text(
                    _formatFileSize(msg.fileSize!),
                    style: TextStyle(
                      color: isMe
                          ? Colors.white.withValues(alpha: 0.6)
                          : colors.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          if (canOpen)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(Icons.download_outlined,
                  size: 18,
                  color: isMe ? Colors.white70 : AppTheme.accentIndigo),
            ),
        ],
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

  Widget _buildRecordingBar(AppColors colors) {
    final m = _recordingSeconds ~/ 60;
    final s = _recordingSeconds % 60;
    final time = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(children: [
        IconButton(
          icon: Icon(Icons.close, color: colors.textSecondary),
          onPressed: _cancelRecording,
        ),
        Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 10, height: 10,
            margin: const EdgeInsets.only(right: 8),
            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
          ),
          Text(time, style: TextStyle(
            color: colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w500)),
        ])),
        GestureDetector(
          onTap: _stopAndSendRecording,
          child: Container(
            width: 44, height: 44,
            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
            child: const Icon(Icons.stop_rounded, color: Colors.white, size: 22),
          ),
        ),
      ]),
    );
  }

  Widget _buildInputArea(UserSettings s) {
    final colors = AppColors.of(context);
    final isEditMode = _editingMessage != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
          if (!isEditMode)
            IconButton(
              icon: Icon(Icons.add_rounded,
                  color: _pendingFilePath != null
                      ? AppTheme.accentIndigo
                      : colors.textSecondary,
                  size: 24),
              onPressed: _pickFile,
            ),
          Expanded(
            child: TextField(
              controller: _inputController,
              focusNode: _focusNode,
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              maxLines: null,
              textInputAction: s.sendOnEnter
                  ? TextInputAction.send
                  : TextInputAction.newline,
              onSubmitted: s.sendOnEnter ? (_) => _sendMessage() : null,
              decoration: InputDecoration(
                hintText: isEditMode
                    ? "Редактировать сообщение..."
                    : _pendingFilePath != null
                        ? "Подпись (необязательно)..."
                        : "Напишите что-нибудь...",
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
          if (!isEditMode)
            IconButton(
              icon: Icon(
                _showEmojiPicker
                    ? Icons.keyboard_rounded
                    : Icons.emoji_emotions_outlined,
                color: colors.textSecondary,
                size: 22,
              ),
              onPressed: () {
                if (_showEmojiPicker) {
                  setState(() => _showEmojiPicker = false);
                  _focusNode.requestFocus();
                } else {
                  _focusNode.unfocus();
                  setState(() => _showEmojiPicker = true);
                }
              },
            ),
          const SizedBox(width: 4),
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
                : isEditMode
                    ? GestureDetector(
                        key: const ValueKey('confirm_edit'),
                        onTap: _confirmEdit,
                        child: Container(
                          width: 44, height: 44,
                          decoration: const BoxDecoration(
                            color: AppTheme.accentIndigo,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              color: Colors.white, size: 22),
                        ),
                      )
                    : _shouldShowMicButton()
                        ? GestureDetector(
                            key: const ValueKey('mic'),
                            onTap: _startRecording,
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.of(context).surface,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.mic_rounded,
                                  color: AppColors.of(context).textSecondary, size: 22),
                            ),
                          )
                        : GestureDetector(
                            key: const ValueKey('send'),
                            onTap: _sendMessage,
                            child: Container(
                              width: 44, height: 44,
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

  String _formatLastSeen(DateTime dt) {
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'был(а) только что';
    if (diff.inMinutes < 60) return 'был(а) ${diff.inMinutes} мин назад';
    if (diff.inHours < 24) return 'был(а) ${diff.inHours} ч назад';
    if (diff.inDays < 7) return 'был(а) ${diff.inDays} д назад';
    final local = dt.toLocal();
    return 'был(а) ${local.day}.${local.month.toString().padLeft(2, '0')}.${local.year}';
  }

  String _formatTime(DateTime dt, bool use24h) {
    final local = dt.toLocal();
    final m = local.minute.toString().padLeft(2, '0');
    if (use24h) {
      return '${local.hour.toString().padLeft(2, '0')}:$m';
    }
    final isPM = local.hour >= 12;
    final h12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    return '$h12:$m ${isPM ? 'PM' : 'AM'}';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }
}

// ── Animated typing dots ────────────────────────────────────────────────────

class _TypingDots extends StatefulWidget {
  final Color color;
  const _TypingDots({required this.color});

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final offset = ((_ctrl.value * 3) - i).clamp(0.0, 1.0);
            final scale = 0.6 + 0.4 * (offset < 0.5 ? offset * 2 : (1 - offset) * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1.5),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 5, height: 5,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Forward sheet ───────────────────────────────────────────────────────────

class _ForwardSheet extends StatefulWidget {
  final ChatService chatService;
  final String token;
  final Message message;
  final String senderUsername;

  const _ForwardSheet({
    required this.chatService,
    required this.token,
    required this.message,
    required this.senderUsername,
  });

  @override
  State<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends State<_ForwardSheet> {
  List<Chat> _chats = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final chats = await widget.chatService.getChats(token: widget.token);
    if (mounted) setState(() { _chats = chats; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Переслать в...',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
          Divider(height: 1, color: colors.divider),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : ListView.builder(
                    itemCount: _chats.length,
                    itemBuilder: (ctx, i) {
                      final chat = _chats[i];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.accentIndigo.withValues(alpha: 0.2),
                          child: Text(chat.avatarInitial[0],
                              style: const TextStyle(color: AppTheme.accentIndigo)),
                        ),
                        title: Text(chat.displayName,
                            style: TextStyle(color: colors.textPrimary)),
                        onTap: () async {
                          Navigator.pop(ctx);
                          await widget.chatService.sendMessage(
                            chatId: chat.id,
                            content: widget.message.content,
                            token: widget.token,
                            type: widget.message.type,
                            fileName: widget.message.fileName,
                            fileSize: widget.message.fileSize,
                            forwardedFromId: widget.message.senderId,
                            forwardedFromUsername: widget.senderUsername,
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Video player ─────────────────────────────────────────────────────────────

class _VideoPlayerWidget extends StatefulWidget {
  final String url;
  const _VideoPlayerWidget({required this.url});

  @override
  State<_VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<_VideoPlayerWidget> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    _player.open(Media(widget.url), play: false);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: double.infinity,
          height: 220,
          child: Video(controller: _controller, controls: AdaptiveVideoControls),
        ),
      );
}

// ── Audio player ─────────────────────────────────────────────────────────────

class _AudioPlayerWidget extends StatefulWidget {
  final String url;
  final bool isMe;
  const _AudioPlayerWidget({required this.url, required this.isMe});

  @override
  State<_AudioPlayerWidget> createState() => _AudioPlayerWidgetState();
}

class _AudioPlayerWidgetState extends State<_AudioPlayerWidget> {
  late final Player _player;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _playSub;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _player.open(Media(widget.url), play: false);
    _posSub = _player.stream.position.listen((p) { if (mounted) setState(() => _position = p); });
    _durSub = _player.stream.duration.listen((d) { if (mounted) setState(() => _duration = d); });
    _playSub = _player.stream.playing.listen((p) { if (mounted) setState(() => _playing = p); });
    _player.stream.completed.listen((done) {
      if (done && mounted) {
        setState(() { _playing = false; _position = Duration.zero; });
        _player.seek(Duration.zero);
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _playSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  String _fmt(Duration d) =>
      '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
      '${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ic = widget.isMe ? Colors.white : AppTheme.accentIndigo;
    final tc = widget.isMe ? Colors.white60 : AppColors.of(context).textSecondary;
    final sliderVal = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      width: 220,
      child: Row(children: [
        GestureDetector(
          onTap: () => _playing ? _player.pause() : _player.play(),
          child: Icon(
            _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
            color: ic, size: 36,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: ic,
                inactiveTrackColor: ic.withValues(alpha: 0.25),
                thumbColor: ic,
                overlayColor: ic.withValues(alpha: 0.2),
              ),
              child: Slider(
                value: sliderVal,
                onChanged: (v) => _player.seek(
                    Duration(milliseconds: (v * _duration.inMilliseconds).round())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 2),
              child: Text(
                _duration.inSeconds > 0
                    ? '${_fmt(_position)} / ${_fmt(_duration)}'
                    : _fmt(_position),
                style: TextStyle(fontSize: 10, color: tc),
              ),
            ),
          ],
        )),
      ]),
    );
  }
}

// ── Fullscreen image ─────────────────────────────────────────────────────────

class _FullscreenImagePage extends StatelessWidget {
  final String url;
  const _FullscreenImagePage({required this.url});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: PhotoView(
          imageProvider: NetworkImage(url),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 4,
          filterQuality: FilterQuality.high,
        ),
      );
}
