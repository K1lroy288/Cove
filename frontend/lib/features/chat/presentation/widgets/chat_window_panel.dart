import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' show min;
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
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

String _fileType(String ext) {
  const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
  const videoExts = {'mp4', 'mov', 'webm', 'avi', 'mkv', 'm4v'};
  const audioExts = {'m4a', 'mp3', 'wav', 'ogg', 'opus', 'aac'};
  if (imageExts.contains(ext)) return 'image';
  if (videoExts.contains(ext)) return 'video';
  if (audioExts.contains(ext)) return 'audio';
  return 'file';
}

// Запускается в отдельном изоляте через compute().
Future<Uint8List?> _compressImageFile(String filePath) async {
  try {
    final bytes = await File(filePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    final target = longest > 2048
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 2048 : null,
            height: decoded.height > decoded.width ? 2048 : null,
          )
        : decoded;
    return Uint8List.fromList(img.encodeJpg(target, quality: 92));
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
  bool _showEmojiPicker = false;
  Map<int, String> _memberNames = {};

  // Ожидающий отправки файл
  String? _pendingFilePath;
  String? _pendingFileName;
  int? _pendingFileSize;
  String? _pendingFileType; // 'image' | 'video' | 'audio' | 'file'

  // ── Запись голосовых ────────────────────────────────────────────────────
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  @override
  void initState() {
    super.initState();
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
    _inputController.addListener(() { if (mounted) setState(() {}); });
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
      if (_isRecording) {
        _recorder.cancel();
        _recordingTimer?.cancel();
        _isRecording = false;
        _recordingSeconds = 0;
      }
      setState(() {
        _messages = [];
        _isLoading = true;
        _pendingFilePath = null;
        _pendingFileName = null;
        _pendingFileSize = null;
        _pendingFileType = null;
      });
      _memberNames.clear();
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
    _recordingTimer?.cancel();
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
          });
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

    final auth = context.read<AuthNotifier>();
    final myId = int.tryParse(auth.userId ?? '');
    if (myId == null || auth.token == null) return;

    if (hasFile) {
      // Снимаем состояние ожидания и создаём оптимистичное сообщение
      final filePath = _pendingFilePath!;
      final fileName = _pendingFileName;
      final fileSize = _pendingFileSize;
      final fileType = _pendingFileType!;
      final caption = text.isNotEmpty ? text : null;

      setState(() {
        _pendingFilePath = null;
        _pendingFileName = null;
        _pendingFileSize = null;
        _pendingFileType = null;
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

      // Сжимаем изображение перед загрузкой (в фоновом изоляте)
      Uint8List? compressed;
      if (fileType == 'image') {
        compressed = await compute(_compressImageFile, filePath);
      }

      // Загружаем файл
      final upload = await _api.uploadFile(
        token: auth.token!,
        filePath: compressed == null ? filePath : null,
        fileBytes: compressed,
        fileName: compressed != null ? 'image.jpg' : fileName,
      );
      if (!mounted) return;

      if (upload == null) {
        setState(() {
          _isSending = false;
          // Оставляем optimistic с isOptimistic=true → красный tint
        });
        return;
      }

      // Отправляем сообщение с URL
      final sent = await _api.sendMessage(
        chatId: widget.chat.id,
        content: upload.url,
        token: auth.token!,
        type: upload.type,
        fileName: upload.fileName,
        fileSize: upload.fileSize,
        caption: caption,
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
      // Обычный текстовый поток
      _inputController.clear();
      _drafts.remove(widget.chat.id);
      if (!_showEmojiPicker) _focusNode.requestFocus();
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
        style: TextStyle(
          fontSize: s.chatFontSizeValue,
          color: isMe ? Colors.white : colors.textPrimary,
        ),
      );
    }

    final isMedia = msg.type == 'image' || msg.type == 'video';

    // Для медиа оборачиваем контент в Stack с оверлеем времени
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
          content,
          if (hasCaption)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Text(
                msg.caption!,
                style: TextStyle(
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

    if (!isMe && s.showAvatars) {
      final name = _memberNames[msg.senderId] ?? '?';
      final initial = name[0].toUpperCase();
      return Padding(
        padding: EdgeInsets.only(bottom: compact ? 2 : 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            compact
                ? const SizedBox(width: 36)
                : CircleAvatar(
                    radius: 14,
                    backgroundColor: AppTheme.accentIndigo.withValues(alpha: 0.2),
                    child: Text(
                      initial,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.accentIndigo,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
            const SizedBox(width: 6),
            bubble,
          ],
        ),
      );
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(bottom: compact ? 2 : 4),
        child: bubble,
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
              errorBuilder: (_, _, _) => const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.broken_image_outlined, size: 40)),
              ),
            )
          : Image.network(
              msg.content,
              width: double.infinity,
              fit: BoxFit.cover,
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
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Row(
        children: [
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
                hintText: _pendingFilePath != null
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
                : _shouldShowMicButton()
                    ? GestureDetector(
                        key: const ValueKey('mic'),
                        onTap: _startRecording,
                        child: Container(
                          width: 44,
                          height: 44,
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
        ),
      );
}
