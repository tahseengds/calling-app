import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/lumio_icons.dart';
import '../../../shared/widgets/lumio_logo.dart';
import '../../profile/presentation/screens/app_lock_pin_screen.dart';
import '../domain/app_lock_controller.dart';
import '../domain/privacy_settings_notifier.dart';

/// Wraps the active route. When PrivacySettings.appLockEnabled is true,
/// this widget watches AppLifecycleState and presents an opaque unlock
/// overlay whenever the app comes back from pause beyond the auto-lock
/// window (0 minutes = lock immediately).
///
/// Drop it inside MaterialApp.router's builder.
class AppLockGate extends ConsumerStatefulWidget {
  final Widget child;
  const AppLockGate({super.key, required this.child});

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate>
    with WidgetsBindingObserver {
  bool _locked = false;
  bool _prompting = false;
  DateTime? _pausedAt;
  bool _firstFrameDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame, if app lock was already enabled when the app
    // cold-started, lock immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _firstFrameDone = true;
      final prefs = ref.read(privacySettingsProvider).value;
      if (prefs != null && prefs.appLockEnabled) {
        setState(() => _locked = true);
        _tryUnlock();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The biometric prompt and the PIN sheet themselves dispatch
    // inactive/paused/resumed transitions. If we react to them we'd lock
    // the app the moment the prompt closes after a successful unlock,
    // which causes the prompt to immediately re-appear in a loop.
    if (_prompting) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _pausedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed && _firstFrameDone) {
      _maybeLockOnResume();
    }
  }

  void _maybeLockOnResume() {
    final prefs = ref.read(privacySettingsProvider).value;
    if (prefs == null || !prefs.appLockEnabled) {
      _pausedAt = null;
      return;
    }
    final paused = _pausedAt;
    _pausedAt = null;
    // A `resumed` without a matching prior pause is not a real
    // foreground-from-background transition — typically it's the system
    // delivering a delayed event after the auth prompt closed. Don't lock.
    if (paused == null) return;
    final elapsedMinutes = DateTime.now().difference(paused).inMinutes;
    if (elapsedMinutes >= prefs.appLockAutoLockMinutes) {
      if (!_locked) setState(() => _locked = true);
      _tryUnlock();
    }
  }

  Future<void> _tryUnlock() async {
    if (_prompting || !mounted) return;
    _prompting = true;

    final controller = ref.read(appLockControllerProvider);
    try {
      // 1) Biometric first if the device can.
      final hasBio = await controller.canUseBiometrics();
      if (hasBio) {
        final result =
            await controller.authenticateBiometric(reason: 'Unlock Lumio');
        if (result == AuthOutcome.success) {
          if (!mounted) return;
          setState(() => _locked = false);
          return;
        }
        if (result == AuthOutcome.cancelled) {
          // User dismissed — leave locked. The "Unlock" button on the overlay
          // gives them another shot.
          return;
        }
        // Unavailable → PIN fallback below.
      }

      // 2) PIN fallback.
      if (!await controller.hasPin()) {
        // No biometrics AND no PIN ever set — graceful: let the user in
        // rather than locking themselves out forever. This is the cold-start
        // case where the device lost biometric enrolment.
        if (!mounted) return;
        setState(() => _locked = false);
        return;
      }
      if (!mounted) return;
      final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
        MaterialPageRoute(
          builder: (_) => const AppLockPinScreen(mode: PinMode.verify),
          fullscreenDialog: true,
        ),
      );
      if (ok == true && mounted) {
        setState(() => _locked = false);
      }
    } finally {
      _prompting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch so we react when the user toggles the setting in PrivacyScreen
    // without backgrounding the app.
    final prefs = ref.watch(privacySettingsProvider).value;
    final enabled = prefs?.appLockEnabled ?? false;

    if (!enabled || !_locked) {
      return widget.child;
    }
    return Stack(
      children: [
        widget.child,
        Positioned.fill(child: _LockOverlay(onUnlock: _tryUnlock)),
      ],
    );
  }
}

class _LockOverlay extends StatelessWidget {
  final VoidCallback onUnlock;
  const _LockOverlay({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final isDark = context.isDarkMode;

    return Material(
      color: isDark ? AppColors.darkBg : AppColors.lightBg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const LumioMark(size: 88),
              const SizedBox(height: AppSpacing.space6),
              Text('Lumio is locked',
                  style: AppTextStyles.h1(color: colors.fg1)),
              const SizedBox(height: AppSpacing.space2),
              Text(
                'Use biometric or PIN to unlock.',
                textAlign: TextAlign.center,
                style: AppTextStyles.secondary(color: colors.fg2),
              ),
              const SizedBox(height: AppSpacing.space8),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(LumioIcons.fingerprint, color: Colors.white),
                  label: Text(
                    'Unlock',
                    style: AppTextStyles.bodySemibold(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
