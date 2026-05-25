import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// Avatar that shows a CachedNetworkImage when [imageUrl] is non-null, and
/// falls back to initials with a deterministic tint derived from [displayName]
/// (matching the Atoms.jsx tintFor() logic in the design system).
class UserAvatar extends StatelessWidget {
  final String? imageUrl;
  final String displayName;
  final double radius;

  const UserAvatar({
    super.key,
    this.imageUrl,
    required this.displayName,
    this.radius = 24,
  });

  String get _initials {
    // Strip family-role prefixes so "Grandma Rose" → "GR" not "GR".
    final cleaned = displayName
        .replaceAll(
          RegExp(r'^(Grandma|Grandpa|Uncle|Aunt)\s+', caseSensitive: false),
          '',
        )
        .trim();
    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final tint = AppColors.avatarTintFor(displayName);

    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: tint,
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: imageUrl!,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            placeholder: (context, url) =>
                _InitialsAvatar(initials: _initials, radius: radius, tint: tint),
            errorWidget: (context, url, error) =>
                _InitialsAvatar(initials: _initials, radius: radius, tint: tint),
          ),
        ),
      );
    }
    return _InitialsAvatar(initials: _initials, radius: radius, tint: tint);
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String initials;
  final double radius;
  final Color tint;

  const _InitialsAvatar({
    required this.initials,
    required this.radius,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: tint,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.65,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
