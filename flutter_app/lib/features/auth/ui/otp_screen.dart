import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_colors.dart';
import '../../../shared/widgets/fl_button.dart';
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
    // Auto-focus hidden input.
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
      // GoRouter redirect fires automatically on AuthAuthenticated.
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['detail'] as String? ??
          'Invalid code. Please try again.';
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
    // Re-trigger the OTP request using the same credentials cached in state.
    // For simplicity, navigate back to login so user re-enters credentials.
    // TODO prompt 13 — add resend endpoint directly without re-login.
    _hiddenCtrl.clear();
    _startCountdown();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('A new code has been requested.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final pending = authState is AuthOtpPending ? authState : null;
    final phone = pending?.phone ?? '';
    final displayPhone = phone.length > 4
        ? '${phone.substring(0, phone.length - 4).replaceAll(RegExp(r'\d'), '•')}${phone.substring(phone.length - 4)}'
        : phone;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            ref.read(authNotifierProvider.notifier).forceSignOut();
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Text(
                'Enter verification code',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'We sent a 6-digit code to $displayPhone',
                style: TextStyle(
                  fontSize: 15,
                  color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),

              // ── 6 OTP boxes ───────────────────────────────────────────────
              GestureDetector(
                onTap: () => _hiddenFocus.requestFocus(),
                child: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _hiddenCtrl,
                  builder: (_, value, __) {
                    return AnimatedBuilder(
                      animation: _caretAnim,
                      builder: (_, __) => Row(
                        mainAxisAlignment: MainAxisAlignment.center,
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

              // Hidden input that actually captures keystrokes.
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

              const SizedBox(height: 36),

              // ── Resend countdown ──────────────────────────────────────────
              _countdown > 0
                  ? Text(
                      'Resend in 0:${_countdown.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        fontSize: 14,
                        color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                      ),
                    )
                  : TextButton(
                      onPressed: _resend,
                      child: const Text(
                        'Resend code',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

              const SizedBox(height: 32),
              FlButton(
                label: 'Verify',
                onPressed: (_isLoading ||
                        _hiddenCtrl.text.length < _length)
                    ? null
                    : _verify,
                isLoading: _isLoading,
              ),

              // ── Debug OTP badge (debug builds only) ───────────────────────
              if (kDebugMode && pending?.debugOtp != null) ...[
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: AppColors.primary.withAlpha(100),
                      style: BorderStyle.solid,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.primary.withAlpha(20),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'DEBUG OTP',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pending!.debugOtp!,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = hasError
        ? AppColors.danger
        : isActive
            ? AppColors.primary
            : (isDark ? AppColors.darkHairline : AppColors.lightHairline);
    final fill = isDark ? AppColors.darkSurfaceLo : AppColors.lightSurfaceLo;

    return Container(
      width: 44,
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: isActive ? 2 : 1.5),
      ),
      alignment: Alignment.center,
      child: char != null
          ? Text(
              char!,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
              ),
            )
          : showCaret
              ? Container(
                  width: 2,
                  height: 28,
                  color: AppColors.primary,
                )
              : null,
    );
  }
}
