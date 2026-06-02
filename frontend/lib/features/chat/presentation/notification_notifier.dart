import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../data/models/notification.dart';
import '../data/services/global_ws_service.dart';
import '../../../core/config.dart';

enum WsConnectionState { connected, connecting, disconnected }

class NotificationNotifier extends ChangeNotifier {
  final GlobalWsService _wsService = GlobalWsService();
  StreamSubscription<AppNotification>? _sub;
  String? _token;
  int _reconnectAttempt = 0;

  WsConnectionState _connectionState = WsConnectionState.disconnected;
  WsConnectionState get connectionState => _connectionState;

  final StreamController<ChatMessageNotification> _chatMsgController =
      StreamController.broadcast();
  final StreamController<NewMessageNotification> _msgController =
      StreamController.broadcast();
  final StreamController<FriendRequestNotification> _friendReqController =
      StreamController.broadcast();
  final StreamController<void> _friendAcceptedController =
      StreamController.broadcast();
  final StreamController<void> _friendRemovedController =
      StreamController.broadcast();

  // Групповые события
  final StreamController<GroupCreatedNotification> _groupCreatedController =
      StreamController.broadcast();
  final StreamController<GroupUpdatedNotification> _groupUpdatedController =
      StreamController.broadcast();
  final StreamController<MemberChangedNotification> _memberChangedController =
      StreamController.broadcast();
  final StreamController<GroupDissolvedNotification> _groupDissolvedController =
      StreamController.broadcast();
  final StreamController<RoleChangedNotification> _roleChangedController =
      StreamController.broadcast();
  final StreamController<MessageDeliveredNotification> _msgDeliveredController =
      StreamController.broadcast();
  final StreamController<MessageReadNotification> _msgReadController =
      StreamController.broadcast();

  // Новые события
  final StreamController<MessageEditedNotification> _msgEditedController =
      StreamController.broadcast();
  final StreamController<MessageDeletedNotification> _msgDeletedController =
      StreamController.broadcast();
  final StreamController<TypingNotification> _typingController =
      StreamController.broadcast();
  final StreamController<ReactionUpdatedNotification> _reactionController =
      StreamController.broadcast();
  final StreamController<MessagePinnedNotification> _pinnedController =
      StreamController.broadcast();

  int _pendingRequestCount = 0;
  int get pendingRequestCount => _pendingRequestCount;

  final Map<int, bool> _presenceMap = {};
  bool isOnline(int userId) => _presenceMap[userId] ?? false;

  Stream<ChatMessageNotification> get chatMessageStream =>
      _chatMsgController.stream;
  Stream<NewMessageNotification> get messageStream => _msgController.stream;
  Stream<FriendRequestNotification> get friendRequestStream =>
      _friendReqController.stream;
  Stream<void> get friendAcceptedStream => _friendAcceptedController.stream;
  Stream<void> get friendRemovedStream => _friendRemovedController.stream;
  Stream<GroupCreatedNotification> get groupCreatedStream =>
      _groupCreatedController.stream;
  Stream<GroupUpdatedNotification> get groupUpdatedStream =>
      _groupUpdatedController.stream;
  Stream<MemberChangedNotification> get memberChangedStream =>
      _memberChangedController.stream;
  Stream<GroupDissolvedNotification> get groupDissolvedStream =>
      _groupDissolvedController.stream;
  Stream<RoleChangedNotification> get roleChangedStream =>
      _roleChangedController.stream;
  Stream<MessageDeliveredNotification> get messageDeliveredStream =>
      _msgDeliveredController.stream;
  Stream<MessageReadNotification> get messageReadStream =>
      _msgReadController.stream;
  Stream<MessageEditedNotification> get messageEditedStream =>
      _msgEditedController.stream;
  Stream<MessageDeletedNotification> get messageDeletedStream =>
      _msgDeletedController.stream;
  Stream<TypingNotification> get typingStream => _typingController.stream;
  Stream<ReactionUpdatedNotification> get reactionUpdatedStream =>
      _reactionController.stream;
  Stream<MessagePinnedNotification> get messagePinnedStream =>
      _pinnedController.stream;

  static String get _baseUrl => AppConfig.baseUrl;

  Future<void> connect(String token) async {
    _token = token;
    _reconnectAttempt = 0;
    await _sub?.cancel();
    await _fetchInitialCount(token);
    _subscribe();
  }

  void _subscribe() {
    if (_token == null) return;
    _connectionState = WsConnectionState.connecting;
    notifyListeners();

    _sub = _wsService.connect(_token!).listen(
      (n) {
        if (_connectionState != WsConnectionState.connected) {
          _connectionState = WsConnectionState.connected;
          _reconnectAttempt = 0;
          notifyListeners();
        }
        _onNotification(n);
      },
      onError: (e) {
        log('notification ws error: $e');
        _scheduleReconnect();
      },
      onDone: () {
        log('notification ws closed');
        _scheduleReconnect();
      },
    );
  }

  void _scheduleReconnect() {
    if (_token == null) return;
    _connectionState = WsConnectionState.disconnected;
    notifyListeners();

    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, max 30s
    final delay = Duration(seconds: (1 << _reconnectAttempt).clamp(1, 30));
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(0, 5);
    log('ws reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempt)');

    Future.delayed(delay, () {
      if (_token != null) _subscribe();
    });
  }

  Future<void> _fetchInitialCount(String token) async {
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/friendship/pending/count'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        _pendingRequestCount = (data['count'] as num).toInt();
        notifyListeners();
      }
    } catch (e) {
      log('fetch pending count error: $e');
    }
  }

  void _onNotification(AppNotification n) {
    switch (n.type) {
      case 'connected':
        break; // обрабатывается в _subscribe до вызова _onNotification
      case 'chat_message':
        _chatMsgController.add(ChatMessageNotification.fromPayload(n.payload));
      case 'new_message':
        final newMsg = NewMessageNotification.fromPayload(n.payload);
        _msgController.add(newMsg);
        ackDelivered(newMsg.chatId, newMsg.messageId);
      case 'friend_request':
        _pendingRequestCount++;
        _friendReqController.add(FriendRequestNotification.fromPayload(n.payload));
        notifyListeners();
      case 'friend_accepted':
        _friendAcceptedController.add(null);
      case 'friend_removed':
        _friendRemovedController.add(null);
      case 'group_created':
        _groupCreatedController
            .add(GroupCreatedNotification.fromPayload(n.payload));
      case 'group_updated':
        _groupUpdatedController
            .add(GroupUpdatedNotification.fromPayload(n.payload));
      case 'member_added':
      case 'member_removed':
        _memberChangedController
            .add(MemberChangedNotification.fromPayload(n.payload));
      case 'group_dissolved':
        _groupDissolvedController
            .add(GroupDissolvedNotification.fromPayload(n.payload));
      case 'role_changed':
        _roleChangedController
            .add(RoleChangedNotification.fromPayload(n.payload));
      case 'message_delivered':
        _msgDeliveredController
            .add(MessageDeliveredNotification.fromPayload(n.payload));
      case 'message_read':
        _msgReadController
            .add(MessageReadNotification.fromPayload(n.payload));
      case 'message_edited':
        _msgEditedController
            .add(MessageEditedNotification.fromPayload(n.payload));
      case 'message_deleted':
        _msgDeletedController
            .add(MessageDeletedNotification.fromPayload(n.payload));
      case 'typing':
        _typingController.add(TypingNotification.fromPayload(n.payload));
      case 'reaction_updated':
        _reactionController
            .add(ReactionUpdatedNotification.fromPayload(n.payload));
      case 'message_pinned':
        _pinnedController
            .add(MessagePinnedNotification.fromPayload(n.payload));
      case 'user_presence':
        final p = UserPresenceNotification.fromPayload(n.payload);
        _presenceMap[p.userId] = p.isOnline;
        notifyListeners();
    }
  }

  Future<void> fetchPresence(List<int> userIds, String token) async {
    if (userIds.isEmpty) return;
    try {
      final resp = await http.get(
        Uri.parse('$_baseUrl/user/presence?ids=${userIds.join(',')}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final map = jsonDecode(resp.body) as Map<String, dynamic>;
        map.forEach((k, v) {
          final id = int.tryParse(k);
          if (id != null) _presenceMap[id] = v as bool;
        });
        notifyListeners();
      }
    } catch (e) {
      log('fetchPresence error: $e');
    }
  }

  void subscribeToChat(int chatId) =>
      _wsService.send({'type': 'subscribe_chat', 'chat_id': chatId});

  void unsubscribeFromChat(int chatId) =>
      _wsService.send({'type': 'unsubscribe_chat', 'chat_id': chatId});

  void ackDelivered(int chatId, int messageId) =>
      _wsService.send({'type': 'ack_delivered', 'chat_id': chatId, 'message_id': messageId});

  void markRead(int chatId, int messageId) =>
      _wsService.send({'type': 'mark_read', 'chat_id': chatId, 'message_id': messageId});

  void sendTyping(int chatId) =>
      _wsService.send({'type': 'typing', 'chat_id': chatId});

  void decrementPendingCount() {
    if (_pendingRequestCount > 0) {
      _pendingRequestCount = 0;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _token = null;
    _reconnectAttempt = 0;
    _connectionState = WsConnectionState.disconnected;
    await _sub?.cancel();
    _wsService.disconnect();
    _pendingRequestCount = 0;
    _presenceMap.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _token = null;
    _sub?.cancel();
    _wsService.disconnect();
    _chatMsgController.close();
    _msgController.close();
    _friendReqController.close();
    _friendAcceptedController.close();
    _friendRemovedController.close();
    _groupCreatedController.close();
    _groupUpdatedController.close();
    _memberChangedController.close();
    _groupDissolvedController.close();
    _roleChangedController.close();
    _msgDeliveredController.close();
    _msgReadController.close();
    _msgEditedController.close();
    _msgDeletedController.close();
    _typingController.close();
    _reactionController.close();
    _pinnedController.close();
    super.dispose();
  }
}
