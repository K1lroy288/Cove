import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart' show AppTheme;

class UserAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initial;
  final double radius;
  final Color? bgColor;
  final Color? textColor;

  const UserAvatar({
    super.key,
    required this.initial,
    required this.radius,
    this.avatarUrl,
    this.bgColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(avatarUrl!),
        backgroundColor: Colors.transparent,
        onBackgroundImageError: (_, _) {},
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor ?? AppTheme.accentIndigo,
      child: Text(
        initial.toUpperCase(),
        style: TextStyle(
          fontSize: radius * 0.65,
          color: textColor ?? Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
