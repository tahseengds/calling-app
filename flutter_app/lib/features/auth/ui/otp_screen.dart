import 'dart:async';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/fl_button.dart';
import '../../../shared/widgets/lumio_back_button.dart';
import '../domain/auth_notifier.dart';
import '../domain/auth_state.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen>
    with SingleTickerProviderStateMixin {
  static const _length = 6;
  static const _resendSeconds = 60;

  final _hiddenCtrl = TextEditingController();
  final _hiddenFocus = FocusNode();
  late final AnimationController _caretAnim;

  bool _isLoading = false;
  bool _hasError = false;
  int _countdown = _resendSeconds;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _caretAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..repeat(reverse: true);
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _hiddenFocus.requestFocus(),
    );
  }

  @override
  void dispose() {
    _hiddenCtrl.dispose();
    _hiddenFocus.dispose();
    _caretAnim.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdown = _resendSeconds;
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        if (_countdown > 0) {
          _countdown--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _verify() async {
    if (_hiddenCtrl.text.length < _length) return;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });
    try {
      await ref.read(authNotifierProvider.notifier).verifyOtp(
            code: _hiddenCtrl.text,
          );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => _hasError = true);
      _hiddenCtrl.clear();
      final msg = switch (e.code) {
        'invalid-verification-code' => 'That code doesn\'t match. Try again.',
        'session-expired' => 'The code expired. Tap Resend to get a new one.',
        _ => e.message ?? 'Invalid code. Please try again.',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
      );
    } on DioException catch (e) {
      // Backend rejected the Firebase ID token (very rare — replay window,
      // misconfigured project, etc.).
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['detail'] as String? ??
          'Could not finish sign-in. Please try again.';
      setState(() => _hasError = true);
      _hiddenCtrl.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _hasError = true);
      _hiddenCtrl.clear();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resend() async {
    if (_countdown > 0) return;
    _hiddenCtrl.clear();
    try {
      await ref.read(authNotifierProvider.notifier).resendOtp();
      if (!mounted) return;
      _startCountdown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('A new code has been sent.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not resend the code. Try again in a moment.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  String _formatPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 11 && digits.startsWith('1')) {
      final d = digits.substring(1);
      return '+1 (${d.substring(0, 3)}) ${d.substring(3, 6)} · ${d.substring(6)}';
    }
    return phone;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final pending = authState is AuthOtpPending ? authState : null;
    final phone = pending?.phone ?? '';
    final colors = context.lumioColors;
    final fg1 = colors.fg1;
    final fg2 = colors.fg2;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
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
                'Verify your number',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w600,
                  color: fg1,
                  letterSpacing: -0.01,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'We sent a code to ${_formatPhone(phone)}',
                style: TextStyle(fontSize: 16, color: fg2, height: 1.4),
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onTap: () => _hiddenFocus.requestFocus(),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _hiddenCtrl,
                  builder: (context, value, _) {
                    return AnimatedBuilder(
                      animation: _caretAnim,
                      builder: (context, _) => Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(_length, (i) {
                          final filled = i < value.text.length;
                          final isActive =
                              i == value.text.length && _hiddenFocus.hasFocus;
                          return _OtpBox(
                            char: filled ? value.text[i] : null,
                            isActive: isActive,
                            hasError: _hasError,
                            showCaret: isActive && _caretAnim.value > 0.5,
                          );
                        }),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                height: 0,
                width: 0,
                child: TextField(
                  controller: _hiddenCtrl,
                  focusNode: _hiddenFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(_length),
                  ],
                  onChanged: (v) {
                    setState(() => _hasError = false);
                    if (v.length == _length) _verify();
                  },
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "Didn't get it? ",
                    style: TextStyle(fontSize: 14, color: fg2),
                  ),
                  if (_countdown > 0)
                    Text(
                      'Resend in 0:${_countdown.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: _resend,
                      child: const Text(
                        'Resend code',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 32),
              FlButton(
                label: 'Verify',
                onPressed: (_isLoading || _hiddenCtrl.text.length < _length)
                    ? null
                    : _verify,
                isLoading: _isLoading,
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () {
                    ref.read(authNotifierProvider.notifier).forceSignOut();
                    context.go('/login');
                  },
                  child: const Text(
                    'Wrong number? Change it',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
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

class _OtpBox extends StatelessWidget {
  final String? char;
  final bool isActive;
  final bool hasError;
  final bool showCaret;

  const _OtpBox({
    this.char,
    required this.isActive,
    required this.hasError,
    required this.showCaret,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final borderColor = hasError
        ? AppColors.danger
        : isActive
            ? AppColors.primary
            : colors.hairline;

    return Container(
      width: 48,
      height: 60,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isActive ? 2 : 1),
      ),
      alignment: Alignment.center,
      child: char != null
          ? Text(
              char!,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colors.fg1,
              ),
            )
          : showCaret
              ? Container(width: 2, height: 28, color: AppColors.primary)
              : null,
    );
  }
}
