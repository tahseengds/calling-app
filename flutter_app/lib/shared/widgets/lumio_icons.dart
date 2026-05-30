import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Semantic icon aliases used across the app, backed by the Lucide icon set
/// (lucide_icons_flutter). Centralising them here gives a single swap point.
abstract final class LumioIcons {
  static const IconData phone = LucideIcons.phone;
  static const IconData message = LucideIcons.messageCircle;
  static const IconData users = LucideIcons.users;
  static const IconData settings = LucideIcons.settings;
  static const IconData add = LucideIcons.userPlus;
  static const IconData search = LucideIcons.search;
  static const IconData eye = LucideIcons.eye;
  static const IconData eyeOff = LucideIcons.eyeOff;
  static const IconData back = LucideIcons.arrowLeft;
  static const IconData more = LucideIcons.ellipsis;
  static const IconData bell = LucideIcons.bell;
  static const IconData shield = LucideIcons.shield;
  static const IconData logout = LucideIcons.logOut;
  static const IconData chevronRight = LucideIcons.chevronRight;
  static const IconData camera = LucideIcons.camera;
  static const IconData edit = LucideIcons.pencil;
  static const IconData help = LucideIcons.circleHelp;
  static const IconData info = LucideIcons.info;
  static const IconData battery = LucideIcons.batteryCharging;
  static const IconData send = LucideIcons.send;
  static const IconData wifiOff = LucideIcons.wifiOff;
  static const IconData people = LucideIcons.users;
  
  // Newly added for calls and chats
  static const IconData video = LucideIcons.video;
  static const IconData videoOff = LucideIcons.videoOff;
  static const IconData mic = LucideIcons.mic;
  static const IconData micOff = LucideIcons.micOff;
  static const IconData speaker = LucideIcons.volume2;
  static const IconData check = LucideIcons.check;
  static const IconData attach = LucideIcons.paperclip;
  static const IconData smile = LucideIcons.smile;
  static const IconData chevron = LucideIcons.chevronRight;
  static const IconData arrowDown = LucideIcons.chevronDown;
  static const IconData heart = LucideIcons.heart;
  static const IconData history = LucideIcons.history;
  static const IconData arrowUp = LucideIcons.arrowUp;
  static const IconData arrowDownLeft = LucideIcons.phoneIncoming;
  static const IconData arrowUpRight = LucideIcons.phoneOutgoing;
  static const IconData close = LucideIcons.x;

  // Settings-screens additions
  static const IconData lock = LucideIcons.lock;
  static const IconData mail = LucideIcons.mail;
  static const IconData volume = LucideIcons.volume2;
  static const IconData volumeOff = LucideIcons.volumeX;
  static const IconData block = LucideIcons.ban;
  static const IconData vibration = LucideIcons.vibrate;
  static const IconData clock = LucideIcons.clock;
  static const IconData moon = LucideIcons.moon;
  static const IconData musicNote = LucideIcons.music;
  static const IconData lockClock = LucideIcons.lock;
  static const IconData fingerprint = LucideIcons.fingerprint;
  static const IconData warning = LucideIcons.triangleAlert;
  static const IconData bookOpen = LucideIcons.bookOpen;
  static const IconData heartFilled = LucideIcons.heart;
  static const IconData openInNew = LucideIcons.externalLink;
  static const IconData fileText = LucideIcons.fileText;
  static const IconData bug = LucideIcons.bug;
  static const IconData userMinus = LucideIcons.userMinus;
  static const IconData phoneOff = LucideIcons.phoneOff;
  static const IconData groups = LucideIcons.users;
  static const IconData reactions = LucideIcons.smile;
  static const IconData mention = LucideIcons.atSign;
  static const IconData trash = LucideIcons.trash2;
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
