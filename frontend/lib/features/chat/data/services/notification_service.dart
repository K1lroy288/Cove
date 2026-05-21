import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static void Function(int chatId)? onNotificationTap;

  static Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const linux = LinuxInitializationSettings(defaultActionName: 'Открыть');

      const settings = InitializationSettings(
        android: android,
        iOS: ios,
        linux: linux,
      );

      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (NotificationResponse r) {
          final chatId = int.tryParse(r.payload ?? '');
          if (chatId != null) onNotificationTap?.call(chatId);
        },
      );
      _initialized = true;
    } catch (_) {
      // Платформа не поддерживается или плагин не зарегистрирован
    }
  }

  static Future<void> showMessageNotification({
    required String chatName,
    required String content,
    required int chatId,
  }) async {
    if (kIsWeb || !_initialized) return;

    final initial = chatName.isNotEmpty ? chatName[0] : '?';
    final bytes = await _makeAvatarBytes(initial, _avatarColor(chatName));

    final androidDetails = AndroidNotificationDetails(
      'cove_messages',
      'Сообщения',
      channelDescription: 'Уведомления о новых сообщениях',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
      largeIcon: bytes != null ? ByteArrayAndroidBitmap(bytes) : null,
    );
    const iosDetails = DarwinNotificationDetails();
    const linuxDetails = LinuxNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      linux: linuxDetails,
    );

    // id = chatId: новое сообщение из того же чата заменяет предыдущее уведомление
    await _plugin.show(chatId, chatName, content, details,
        payload: chatId.toString());
  }

  static Color _avatarColor(String name) {
    const palette = [
      Colors.blue,
      Colors.purple,
      Colors.teal,
      Colors.green,
      Colors.orange,
      Colors.indigo,
    ];
    return palette[name.hashCode.abs() % palette.length];
  }

  static Future<Uint8List?> _makeAvatarBytes(String initial, Color bg) async {
    try {
      const size = 96.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawCircle(
          const Offset(size / 2, size / 2), size / 2, Paint()..color = bg);
      final tp = TextPainter(
        text: TextSpan(
          text: initial.toUpperCase(),
          style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas,
          Offset((size - tp.width) / 2, (size - tp.height) / 2));
      final img = await recorder
          .endRecording()
          .toImage(size.toInt(), size.toInt());
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
