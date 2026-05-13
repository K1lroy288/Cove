import 'dart:convert';
import 'dart:developer';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/message.dart';

class WsService {
  static const String _wsBaseUrl = 'ws://localhost:3425';

  WebSocketChannel? _channel;

  /// Подключается к чату и возвращает поток входящих сообщений.
  /// Предыдущее соединение закрывается автоматически.
  Stream<Message> connect(int chatId, String token) {
    disconnect();
    _channel = WebSocketChannel.connect(
      Uri.parse('$_wsBaseUrl/chat/$chatId/ws?token=${Uri.encodeComponent(token)}'),
    );
    return _channel!.stream.map((raw) {
      final json = jsonDecode(raw as String) as Map<String, dynamic>;
      return Message.fromJson(json);
    }).handleError((Object e) {
      log('ws error chat=$chatId: $e');
    });
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
