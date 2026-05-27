import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:photo_view/photo_view.dart';
import '../../../../core/theme/app_theme.dart' show AppTheme, AppColors;
import '../../data/models/message.dart';
import '../../data/services/chat_service.dart';

class ChatAttachmentsSheet extends StatefulWidget {
  final int chatId;
  final String chatName;
  final String token;

  const ChatAttachmentsSheet({
    super.key,
    required this.chatId,
    required this.chatName,
    required this.token,
  });

  static void show(
      BuildContext context, int chatId, String chatName, String token) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChatAttachmentsSheet(
        chatId: chatId,
        chatName: chatName,
        token: token,
      ),
    );
  }

  @override
  State<ChatAttachmentsSheet> createState() => _ChatAttachmentsSheetState();
}

class _ChatAttachmentsSheetState extends State<ChatAttachmentsSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, _) => Container(
        decoration: BoxDecoration(
          color: colors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: colors.textSecondary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.chatName,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Вложения',
                          style: TextStyle(
                              color: colors.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: colors.textSecondary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: AppTheme.accentIndigo,
              unselectedLabelColor: colors.textSecondary,
              indicatorColor: AppTheme.accentIndigo,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [
                Tab(text: 'Медиа'),
                Tab(text: 'Голосовые'),
                Tab(text: 'Файлы'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _MediaGrid(
                      chatId: widget.chatId, token: widget.token),
                  _VoiceList(
                      chatId: widget.chatId, token: widget.token),
                  _FileList(
                      chatId: widget.chatId, token: widget.token),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Медиа-сетка (image + video) ───────────────────────────────────────────────

class _MediaGrid extends StatefulWidget {
  final int chatId;
  final String token;
  const _MediaGrid({required this.chatId, required this.token});

  @override
  State<_MediaGrid> createState() => _MediaGridState();
}

class _MediaGridState extends State<_MediaGrid>
    with AutomaticKeepAliveClientMixin {
  final _api = ChatService();
  final _scroll = ScrollController();
  final List<Message> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  int? _beforeId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final (msgs, _) = await _api.getMessages(
      chatId: widget.chatId,
      token: widget.token,
      before: _beforeId,
      limit: 30,
      types: ['image', 'video'],
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (msgs.isEmpty) {
        _hasMore = false;
      } else {
        _items.addAll(msgs);
        _beforeId = msgs.last.id;
        if (msgs.length < 30) _hasMore = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = AppColors.of(context);
    if (!_loading && _items.isEmpty) {
      return Center(
        child: Text('Нет фото или видео',
            style: TextStyle(color: colors.textSecondary)),
      );
    }
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: _items.length + (_loading ? 3 : 0),
      itemBuilder: (_, i) {
        if (i >= _items.length) {
          return Container(color: colors.surface);
        }
        final msg = _items[i];
        return GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) =>
                _FullscreenMediaPage(url: msg.content, type: msg.type),
            fullscreenDialog: true,
          )),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                msg.content,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: colors.surface,
                  child: Icon(Icons.broken_image_outlined,
                      color: colors.textSecondary),
                ),
              ),
              if (msg.type == 'video')
                const Center(
                  child: Icon(Icons.play_circle_outline,
                      color: Colors.white, size: 32),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ── Список голосовых ─────────────────────────────────────────────────────────

class _VoiceList extends StatefulWidget {
  final int chatId;
  final String token;
  const _VoiceList({required this.chatId, required this.token});

  @override
  State<_VoiceList> createState() => _VoiceListState();
}

class _VoiceListState extends State<_VoiceList>
    with AutomaticKeepAliveClientMixin {
  final _api = ChatService();
  final _scroll = ScrollController();
  final List<Message> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  int? _beforeId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final (msgs, _) = await _api.getMessages(
      chatId: widget.chatId,
      token: widget.token,
      before: _beforeId,
      limit: 30,
      types: ['audio'],
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (msgs.isEmpty) {
        _hasMore = false;
      } else {
        _items.addAll(msgs);
        _beforeId = msgs.last.id;
        if (msgs.length < 30) _hasMore = false;
      }
    });
  }

  String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    const months = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${months[d.month - 1]}, $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = AppColors.of(context);
    if (!_loading && _items.isEmpty) {
      return Center(
        child: Text('Нет голосовых сообщений',
            style: TextStyle(color: colors.textSecondary)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length + (_loading ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accentIndigo)),
          );
        }
        final msg = _items[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _AttachAudioPlayer(url: msg.content),
                ),
                const SizedBox(width: 8),
                Text(
                  _fmtDate(msg.createdAt),
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Список файлов ─────────────────────────────────────────────────────────────

class _FileList extends StatefulWidget {
  final int chatId;
  final String token;
  const _FileList({required this.chatId, required this.token});

  @override
  State<_FileList> createState() => _FileListState();
}

class _FileListState extends State<_FileList>
    with AutomaticKeepAliveClientMixin {
  final _api = ChatService();
  final _scroll = ScrollController();
  final List<Message> _items = [];
  bool _loading = false;
  bool _hasMore = true;
  int? _beforeId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    final (msgs, _) = await _api.getMessages(
      chatId: widget.chatId,
      token: widget.token,
      before: _beforeId,
      limit: 30,
      types: ['file'],
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (msgs.isEmpty) {
        _hasMore = false;
      } else {
        _items.addAll(msgs);
        _beforeId = msgs.last.id;
        if (msgs.length < 30) _hasMore = false;
      }
    });
  }

  String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    const months = [
      'янв', 'фев', 'мар', 'апр', 'май', 'июн',
      'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colors = AppColors.of(context);
    if (!_loading && _items.isEmpty) {
      return Center(
        child:
            Text('Нет файлов', style: TextStyle(color: colors.textSecondary)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _items.length + (_loading ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accentIndigo)),
          );
        }
        final msg = _items[i];
        return ListTile(
          leading: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppTheme.accentIndigo.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.insert_drive_file_outlined,
                color: AppTheme.accentIndigo, size: 24),
          ),
          title: Text(
            msg.fileName ?? 'Файл',
            style:
                TextStyle(color: colors.textPrimary, fontSize: 14),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            [
              if (msg.fileSize != null) _fmtSize(msg.fileSize!),
              _fmtDate(msg.createdAt),
            ].join(' · '),
            style: TextStyle(color: colors.textSecondary, fontSize: 12),
          ),
        );
      },
    );
  }
}

// ── Аудиоплеер для листа вложений ─────────────────────────────────────────────

class _AttachAudioPlayer extends StatefulWidget {
  final String url;
  const _AttachAudioPlayer({required this.url});

  @override
  State<_AttachAudioPlayer> createState() => _AttachAudioPlayerState();
}

class _AttachAudioPlayerState extends State<_AttachAudioPlayer> {
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
    _posSub = _player.stream.position
        .listen((p) { if (mounted) setState(() => _position = p); });
    _durSub = _player.stream.duration
        .listen((d) { if (mounted) setState(() => _duration = d); });
    _playSub = _player.stream.playing
        .listen((p) { if (mounted) setState(() => _playing = p); });
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
    final colors = AppColors.of(context);
    final sliderVal = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Row(children: [
      GestureDetector(
        onTap: () => _playing ? _player.pause() : _player.play(),
        child: Icon(
          _playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
          color: AppTheme.accentIndigo,
          size: 36,
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 10),
                activeTrackColor: AppTheme.accentIndigo,
                inactiveTrackColor:
                    AppTheme.accentIndigo.withValues(alpha: 0.25),
                thumbColor: AppTheme.accentIndigo,
                overlayColor: AppTheme.accentIndigo.withValues(alpha: 0.2),
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
                style: TextStyle(fontSize: 10, color: colors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

// ── Полноэкранный просмотрщик медиа ──────────────────────────────────────────

class _FullscreenMediaPage extends StatefulWidget {
  final String url;
  final String type;
  const _FullscreenMediaPage({required this.url, required this.type});

  @override
  State<_FullscreenMediaPage> createState() => _FullscreenMediaPageState();
}

class _FullscreenMediaPageState extends State<_FullscreenMediaPage> {
  Player? _player;
  VideoController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.type == 'video') {
      _player = Player();
      _controller = VideoController(_player!);
      _player!.open(Media(widget.url));
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: widget.type == 'video' && _controller != null
          ? Center(
              child: Video(
                controller: _controller!,
                controls: AdaptiveVideoControls,
              ),
            )
          : PhotoView(
              imageProvider: NetworkImage(widget.url),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 4,
            ),
    );
  }
}
