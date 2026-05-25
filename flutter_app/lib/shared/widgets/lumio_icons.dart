import 'package:flutter/material.dart';

/// Stroke-style icons aligned with lumio-screens-design.html.
/// Uses Material outlined icons (compatible with all Flutter versions).
abstract final class LumioIcons {
  static const IconData phone = Icons.phone_outlined;
  static const IconData message = Icons.chat_bubble_outline;
  static const IconData users = Icons.people_outline;
  static const IconData settings = Icons.settings_outlined;
  static const IconData add = Icons.person_add_outlined;
  static const IconData search = Icons.search;
  static const IconData eye = Icons.visibility_outlined;
  static const IconData eyeOff = Icons.visibility_off_outlined;
  static const IconData back = Icons.arrow_back;
  static const IconData more = Icons.more_horiz;
  static const IconData bell = Icons.notifications_outlined;
  static const IconData shield = Icons.shield_outlined;
  static const IconData logout = Icons.logout;
  static const IconData chevronRight = Icons.chevron_right;
  static const IconData camera = Icons.camera_alt_outlined;
  static const IconData edit = Icons.edit_outlined;
  static const IconData help = Icons.help_outline;
  static const IconData info = Icons.info_outline;
  static const IconData battery = Icons.battery_charging_full_outlined;
  static const IconData send = Icons.send_outlined;
  static const IconData wifiOff = Icons.wifi_off;
  static const IconData people = Icons.people_outline;
  
  // Newly added for calls and chats
  static const IconData video = Icons.videocam_outlined;
  static const IconData videoOff = Icons.videocam_off_outlined;
  static const IconData mic = Icons.mic_none_outlined;
  static const IconData micOff = Icons.mic_off_outlined;
  static const IconData speaker = Icons.volume_up_outlined;
  static const IconData check = Icons.check;
  static const IconData attach = Icons.attach_file;
  static const IconData smile = Icons.sentiment_satisfied_alt_outlined;
  static const IconData chevron = Icons.chevron_right;
  static const IconData arrowDown = Icons.keyboard_arrow_down;
  static const IconData heart = Icons.favorite_border;
  static const IconData history = Icons.history;
  static const IconData arrowUp = Icons.arrow_upward;
  static const IconData arrowDownLeft = Icons.call_received;
  static const IconData arrowUpRight = Icons.call_made;
  static const IconData close = Icons.close;
}

/// US flag mini widget for phone prefix (design uses SVG, not emoji).
class UsFlagIcon extends StatelessWidget {
  final double width;
  final double height;

  const UsFlagIcon({super.key, this.width = 22, this.height = 16});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: CustomPaint(
        size: Size(width, height),
        painter: _UsFlagPainter(),
      ),
    );
  }
}

class _UsFlagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stripeH = size.height / 13;
    for (var i = 0; i < 13; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * stripeH, size.width, stripeH),
        Paint()..color = i.isEven ? const Color(0xFFB22234) : Colors.white,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width * 0.42, size.height * 0.54),
      Paint()..color = const Color(0xFF3C3B6E),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
