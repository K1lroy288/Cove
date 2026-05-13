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
  final StreamController<NewMessageNotification> _msgController =
      StreamController.broadcast();

  final StreamController<FriendRequestNotification> _friendReqController =
      StreamController.broadcast();
  final StreamController<void> _friendAcceptedController =
      StreamController.broadcast();

  int _pendingRequestCount = 0;
  int get pendingRequestCount => _pendingRequestCount;
  Stream<NewMessageNotification> get messageStream => _msgController.stream;
  Stream<FriendRequestNotification> get friendRequestStream => _friendReqController.stream;
  Stream<void> get friendAcceptedStream => _friendAcceptedController.stream;

  static const String _baseUrl = 'http://localhost:3425';

  Future<void> connect(String token) async {
    await _sub?.cancel();
    await _fetchInitialCount(token);
    _sub = _wsService.connect(token).listen(
      _onNotification,
      onError: (e) => log('notification ws error: $e'),
      onDone: () => log('notification ws closed'),
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
      case 'new_message':
        _msgController.add(NewMessageNotification.fromPayload(n.payload));
      case 'friend_request':
        _pendingRequestCount++;
        _friendReqController.add(FriendRequestNotification.fromPayload(n.payload));
        notifyListeners();
      case 'friend_accepted':
        _friendAcceptedController.add(null);
    }
  }

  void decrementPendingCount() {
    if (_pendingRequestCount > 0) {
      _pendingRequestCount = 0;
      notifyListeners();
    }
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _wsService.disconnect();
    _pendingRequestCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _wsService.disconnect();
    _msgController.close();
    _friendReqController.close();
    _friendAcceptedController.close();
    super.dispose();
  }
}
