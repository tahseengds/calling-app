import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/analytics_service.dart';
import '../../core/services/remote_config_service.dart';
import '../../core/theme/app_colors.dart';

enum _GateMode { unknown, none, soft, hard, maintenance }

/// Wraps the app and enforces Remote Config update policy:
///   • maintenance_mode      → full-screen blocking maintenance notice
///   • version < min floor   → full-screen blocking "update required"
///   • version < latest      → dismissible soft "update available" card
///   • otherwise             → renders [child] untouched
///
/// Fully fail-open: any error (no PackageInfo, unparseable versions, Remote
/// Config unavailable) resolves to [_GateMode.none] so the gate can never lock
/// a working app out by mistake.
class UpdateGate extends ConsumerStatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  _GateMode _mode = _GateMode.unknown;
  bool _softVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    var mode = _GateMode.none;
    try {
      final rc = ref.read(remoteConfigServiceProvider);
      // Fetch+activate here (throttled internally to 1/hour). The real app
      // renders behind us while this runs, so a blocking screen — if needed —
      // simply appears a moment later rather than delaying first paint.
      await rc.init();

      final info = await PackageInfo.fromPlatform();
      final current = info.version;

      if (rc.maintenanceMode) {
        mode = _GateMode.maintenance;
      } else if (_isOlder(current, rc.minSupportedVersion)) {
        mode = _GateMode.hard;
      } else if (_isOlder(current, rc.latestVersion)) {
        mode = _GateMode.soft;
      }
    } catch (e) {
      debugPrint('[update_gate] check failed (fail-open): $e');
      mode = _GateMode.none;
    }
    if (!mounted) return;
    setState(() {
      _mode = mode;
      _softVisible = mode == _GateMode.soft;
    });
    if (mode != _GateMode.none) {
      ref.read(analyticsServiceProvider).logEvent(
        'app_update_prompt_shown',
        {'type': mode.name},
      );
    }
  }

  Future<void> _openStore() async {
    final rc = ref.read(remoteConfigServiceProvider);
    final url = Platform.isIOS ? rc.updateUrlIos : rc.updateUrlAndroid;
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('[update_gate] could not open store url: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_mode) {
      case _GateMode.maintenance:
        return _BlockingScreen(
          icon: Icons.build_outlined,
          title: 'Under maintenance',
          message: ref.read(remoteConfigServiceProvider).maintenanceMessage,
        );
      case _GateMode.hard:
        return _BlockingScreen(
          icon: Icons.system_update,
          title: 'Update required',
          message:
              'This version of Lumio is no longer supported. Please update to '
              'continue.',
          actionLabel: 'Update now',
          onAction: _openStore,
        );
      case _GateMode.unknown:
      case _GateMode.none:
      case _GateMode.soft:
        return Stack(
          children: [
            widget.child,
            if (_mode == _GateMode.soft && _softVisible)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _SoftUpdateCard(
                  onUpdate: _openStore,
                  onDismiss: () => setState(() => _softVisible = false),
                ),
              ),
          ],
        );
    }
  }

  // ── Version compare ────────────────────────────────────────────────────────

  /// True when [current] is strictly older than [target] (semver-ish: compares
  /// the dotted numeric core, ignoring any `-pre`/`+build` suffix). Fail-open:
  /// an empty or unparseable [target] never gates.
  static bool _isOlder(String current, String target) {
    if (target.trim().isEmpty) return false;
    return _compare(current, target) < 0;
  }

  static int _compare(String a, String b) {
    List<int> parse(String v) {
      final core = v.split('+').first.split('-').first.trim();
      return core
          .split('.')
          .map((p) => int.tryParse(p.trim()) ?? 0)
          .toList();
    }

    final pa = parse(a);
    final pb = parse(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}

// ── UI ────────────────────────────────────────────────────────────────────────

class _BlockingScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _BlockingScreen({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final fg = isDark ? Colors.white : const Color(0xFF1A1D26);
    final muted = isDark ? const Color(0xFF9AA3B2) : const Color(0xFF5C6370);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 56, color: AppColors.primary),
                const SizedBox(height: 20),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: fg,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 15, height: 1.4),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: onAction,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(actionLabel!),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SoftUpdateCard extends StatelessWidget {
  final VoidCallback onUpdate;
  final VoidCallback onDismiss;

  const _SoftUpdateCard({required this.onUpdate, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF1C1F28) : Colors.white;
    final fg = isDark ? Colors.white : const Color(0xFF1A1D26);
    final muted = isDark ? const Color(0xFF9AA3B2) : const Color(0xFF5C6370);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(16),
          color: card,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(
              children: [
                const Icon(Icons.system_update, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Update available',
                        style: TextStyle(
                          color: fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'A newer version of Lumio is ready.',
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                TextButton(onPressed: onUpdate, child: const Text('Update')),
                IconButton(
                  onPressed: onDismiss,
                  tooltip: 'Dismiss',
                  icon: Icon(Icons.close, color: muted, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
