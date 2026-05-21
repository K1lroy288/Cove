import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../data/models/notification.dart';
import '../data/services/global_ws_service.dart';

class NotificationNotifier extends ChangeNotifier {
  final GlobalWsService _wsService = GlobalWsService();
  StreamSubscription<AppNotification>? _sub;
  String? _token;

  final StreamController<ChatMessageNotification> _chatMsgController =
      StreamController.broadcast();
  final StreamController<NewMessageNotification> _msgController =
      StreamController.broadcast();
  final StreamController<FriendRequestNotification> _friendReqController =
      StreamController.broadcast();
  final StreamController<void> _friendAcceptedController =
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

  static const String _baseUrl = 'http://localhost:3425';

  Future<void> connect(String token) async {
    _token = token;
    await _sub?.cancel();
    await _fetchInitialCount(token);
    _subscribe();
  }

  void _subscribe() {
    if (_token == null) return;
    _sub = _wsService.connect(_token!).listen(
      _onNotification,
      onError: (e) => log('notification ws error: $e'),
      onDone: () {
        log('notification ws closed, reconnecting in 3s');
        Future.delayed(const Duration(seconds: 3), () {
          if (_token != null) _subscribe();
        });
      },
    );
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
      case 'chat_message':
        _chatMsgController.add(ChatMessageNotification.fromPayload(n.payload));
      case 'new_message':
        final newMsg = NewMessageNotification.fromPayload(n.payload);
        _msgController.add(newMsg);
        // Подтверждаем доставку: сообщение пришло на устройство
        ackDelivered(newMsg.chatId, newMsg.messageId);
      case 'friend_request':
        _pendingRequestCount++;
        _friendReqController.add(FriendRequestNotification.fromPayload(n.payload));
        notifyListeners();
      case 'friend_accepted':
        _friendAcceptedController.add(null);
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

  void decrementPendingCount() {
    if (_pendingRequestCount > 0) {
      _pendingRequestCount = 0;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    _token = null;
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
    _groupCreatedController.close();
    _groupUpdatedController.close();
    _memberChangedController.close();
    _groupDissolvedController.close();
    _roleChangedController.close();
    _msgDeliveredController.close();
    _msgReadController.close();
    super.dispose();
  }
}
