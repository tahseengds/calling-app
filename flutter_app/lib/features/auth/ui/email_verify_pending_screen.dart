import 'dart:async';
import 'dart:io' show Platform;

import 'package:android_intent_plus/android_intent.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/fl_button.dart';
import '../../../shared/widgets/lumio_back_button.dart';
import '../domain/auth_notifier.dart';
import '../domain/auth_state.dart';

/// Shown after registering (or after signing in with an unverified
/// email/password account). Tells the user to check their email for the
/// verification link, with buttons to resend and to check verification
/// status.
///
/// Auto-polls every 4 s in the background — when the user clicks the
/// link in another tab/window, we'll quietly complete the backend
/// handshake and the router redirects to /home.
class EmailVerifyPendingScreen extends ConsumerStatefulWidget {
  const EmailVerifyPendingScreen({super.key});

  @override
  ConsumerState<EmailVerifyPendingScreen> createState() =>
      _EmailVerifyPendingScreenState();
}

class _EmailVerifyPendingScreenState
    extends ConsumerState<EmailVerifyPendingScreen> {
  bool _isChecking = false;
  bool _isResending = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  Timer? _pollTimer;

  static const _resendCooldownSeconds = 60;

  @override
  void initState() {
    super.initState();
    // Quietly poll for verification — most users won't tap the button.
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _check(silent: true);
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _resendCooldown = _resendCooldownSeconds;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_resendCooldown > 0) {
          _resendCooldown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _check({bool silent = false}) async {
    if (_isChecking) return;
    if (!silent) setState(() => _isChecking = true);
    try {
      final verified = await ref
          .read(authNotifierProvider.notifier)
          .reloadAndCompleteVerification();
      if (!silent && !verified && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Email not verified yet. Click the link we sent you, then try again.'),
          ),
        );
      }
    } catch (_) {
      // Silent — keep polling.
    } finally {
      if (!silent && mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _openMailApp() async {
    // On Android: launch ACTION_MAIN with category APP_EMAIL — the system
    // picks the default mail client and opens it at its launch screen
    // (i.e. the inbox), not at compose. mailto: would always land on
    // compose, which is the wrong UX here.
    //
    // On iOS / other: fall back to mailto: (best we can do without
    // platform-specific tricks; opens Apple Mail at compose, but at least
    // surfaces an email app).
    try {
      if (Platform.isAndroid) {
        const intent = AndroidIntent(
          action: 'android.intent.action.MAIN',
          category: 'android.intent.category.APP_EMAIL',
          flags: <int>[0x10000000], // FLAG_ACTIVITY_NEW_TASK
        );
        await intent.launch();
        return;
      }
      final launched = await launchUrl(
        Uri(scheme: 'mailto', path: ''),
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No email app is installed.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open mail app.')),
      );
    }
  }

  Future<void> _resend() async {
    if (_resendCooldown > 0 || _isResending) return;
    setState(() => _isResending = true);
    try {
      await ref
          .read(authNotifierProvider.notifier)
          .resendVerificationEmail();
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new verification link has been sent.')),
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'too-many-requests'
          ? 'Too many attempts. Try again in a few minutes.'
          : e.message ?? 'Could not resend the email.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not resend the email. Try again in a moment.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(authNotifierProvider);
    final email =
        pending is AuthEmailVerificationPending ? pending.email : '';
    final colors = context.lumioColors;
    final fg1 = colors.fg1;
    final fg2 = colors.fg2;
    final fg3 = colors.fg3;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LumioBackButton(
                      onPressed: () {
                        ref.read(authNotifierProvider.notifier).forceSignOut();
                      },
                    ),
              const SizedBox(height: 24),
              Text(
                'Verify your email',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: fg1,
                  letterSpacing: -0.01,
                ),
              ),
              const SizedBox(height: 12),
              RichText(
                text: TextSpan(
                  text: 'We sent a verification link to ',
                  style: TextStyle(fontSize: 16, color: fg2, height: 1.4),
                  children: [
                    TextSpan(
                      text: email,
                      style: TextStyle(
                        color: fg1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const TextSpan(
                      text:
                          '. Click the link in that email, then tap the button below.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              FlButton(
                label: 'Open mail app',
                onPressed: _openMailApp,
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed:
                      (_resendCooldown > 0 || _isResending) ? null : _resend,
                  child: Text(
                    _resendCooldown > 0
                        ? 'Resend in 0:${_resendCooldown.toString().padLeft(2, '0')}'
                        : (_isResending ? 'Sending…' : 'Resend link'),
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  onPressed: _isChecking ? null : () => _check(),
                  child: Text(
                    _isChecking ? 'Checking…' : "I've already verified",
                    style: TextStyle(
                      color: _isChecking ? fg3 : AppColors.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              Center(
                child: TextButton(
                  onPressed: () {
                    ref.read(authNotifierProvider.notifier).signOut();
                    context.go('/login');
                  },
                  child: const Text(
                    'Use a different account',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  'Check your spam folder if you don\'t see it.',
                  style: TextStyle(fontSize: 13, color: fg3),
                ),
              ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
