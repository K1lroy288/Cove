import 'dart:convert';
import 'dart:developer';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/notification.dart';

class GlobalWsService {
  static const String _wsBaseUrl = 'ws://localhost:3425';

  WebSocketChannel? _channel;

  Stream<AppNotification> connect(String token) {
    disconnect();
    _channel = WebSocketChannel.connect(
      Uri.parse('$_wsBaseUrl/ws?token=${Uri.encodeComponent(token)}'),
    );
    return _channel!.stream.map((raw) {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      return AppNotification.fromJson(json);
    }).handleError((Object e) {
      log('global ws error: $e');
    });
  }

  void send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
