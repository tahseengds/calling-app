import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/connectivity.dart';
import '../../core/theme/app_colors.dart';
import 'lumio_icons.dart';

/// Slim "no internet connection" bar. Renders nothing while online (and while
/// connectivity is still unknown at cold start, so it never flashes), and a
/// compact banner when the device goes offline. Mount it at the top of a
/// screen's body, above the scrolling content.
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Default to "online" until the stream emits so we don't show the banner
    // before connectivity has been determined.
    final online = ref.watch(isOnlineProvider).valueOrNull ?? true;
    if (online) return const SizedBox.shrink();

    return Material(
      color: AppColors.danger,
      child: SafeArea(
        bottom: false,
        child: Semantics(
          liveRegion: true,
          label: 'No internet connection',
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(LumioIcons.wifiOff, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'No internet connection',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
