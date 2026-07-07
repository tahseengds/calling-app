import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/fl_button.dart';
import '../../../shared/widgets/lumio_icons.dart';
import '../../../shared/widgets/lumio_logo.dart';
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
  // When true the overlay shows an inline PIN entry (biometric unavailable but
  // a PIN is set). We render PIN entry INSIDE the overlay rather than pushing a
  // route: AppLockGate lives in MaterialApp.router's builder, above the
  // Router's Navigator, so Navigator.of(context) here has no Navigator ancestor
  // and pushing would throw — permanently locking out non-biometric devices.
  bool _showPinEntry = false;
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
      // Show the inline PIN entry inside the overlay (see _showPinEntry doc).
      if (!mounted) return;
      setState(() => _showPinEntry = true);
    } finally {
      _prompting = false;
    }
  }

  void _onPinSuccess() {
    if (!mounted) return;
    setState(() {
      _locked = false;
      _showPinEntry = false;
    });
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
        Positioned.fill(
          child: _LockOverlay(
            onUnlock: _tryUnlock,
            showPinEntry: _showPinEntry,
            onPinSuccess: _onPinSuccess,
          ),
        ),
      ],
    );
  }
}

class _LockOverlay extends StatelessWidget {
  final VoidCallback onUnlock;
  final bool showPinEntry;
  final VoidCallback onPinSuccess;
  const _LockOverlay({
    required this.onUnlock,
    required this.showPinEntry,
    required this.onPinSuccess,
  });

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
                showPinEntry
                    ? 'Enter your PIN to unlock.'
                    : 'Use biometric or PIN to unlock.',
                textAlign: TextAlign.center,
                style: AppTextStyles.secondary(color: colors.fg2),
              ),
              const SizedBox(height: AppSpacing.space8),
              if (showPinEntry)
                _PinUnlock(onSuccess: onPinSuccess)
              else
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: onUnlock,
                    icon:
                        const Icon(LumioIcons.fingerprint, color: Colors.white),
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

/// Inline PIN verification rendered inside the lock overlay. Verifies against
/// [AppLockController.verifyPin] and calls [onSuccess] on a match. Deliberately
/// does not touch the Navigator (see [_AppLockGateState._showPinEntry]).
class _PinUnlock extends ConsumerStatefulWidget {
  final VoidCallback onSuccess;
  const _PinUnlock({required this.onSuccess});

  @override
  ConsumerState<_PinUnlock> createState() => _PinUnlockState();
}

class _PinUnlockState extends ConsumerState<_PinUnlock> {
  final TextEditingController _ctrl = TextEditingController();
  bool _checking = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_checking) return;
    setState(() => _checking = true);
    final ok = await ref.read(appLockControllerProvider).verifyPin(_ctrl.text);
    if (!mounted) return;
    if (ok) {
      widget.onSuccess();
      return;
    }
    setState(() {
      _error = 'Incorrect PIN. Try again.';
      _checking = false;
      _ctrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    return Column(
      children: [
        TextField(
          controller: _ctrl,
          autofocus: true,
          obscureText: true,
          maxLength: 8,
          enabled: !_checking,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          textAlign: TextAlign.center,
          style: AppTextStyles.h2(color: colors.fg1).copyWith(letterSpacing: 8),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••',
            errorText: _error,
          ),
        ),
        const SizedBox(height: AppSpacing.space6),
        FlButton(
          label: 'Unlock',
          isLoading: _checking,
          onPressed: _submit,
        ),
      ],
    );
  }
}
