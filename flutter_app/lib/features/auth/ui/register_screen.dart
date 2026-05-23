import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_colors.dart';
import '../../../shared/widgets/fl_button.dart';
import '../../../shared/widgets/fl_text_field.dart';
import '../domain/auth_notifier.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading = false;
  // Track fields that have been blurred at least once for on-blur validation UX.
  final _touched = <String>{};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String get _fullPhone => '+1${_phoneCtrl.text.replaceAll(RegExp(r'\D'), '')}';

  String? _validateName(String? v) {
    if ((v?.trim().length ?? 0) < 2) return 'Enter your full name';
    return null;
  }

  String? _validatePhone(String? v) {
    final digits = v?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (digits.length < 10) return 'Enter a valid 10-digit US number';
    return null;
  }

  String? _validatePassword(String? v) {
    if ((v?.length ?? 0) < 8) return 'At least 8 characters';
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v != _passwordCtrl.text) return 'Passwords do not match';
    return null;
  }

  Future<void> _submit() async {
    // Mark all fields touched so errors are shown.
    setState(() => _touched.addAll(['name', 'phone', 'password', 'confirm']));
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).register(
            name: _nameCtrl.text.trim(),
            phone: _fullPhone,
            password: _passwordCtrl.text,
          );
      // GoRouter redirect fires automatically on AuthOtpPending state.
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['detail'] as String? ??
          'Registration failed. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An unexpected error occurred.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 64),
                Text(
                  'Create your account',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Join your family on FamilyLink',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                  ),
                ),
                const SizedBox(height: 40),

                // ── Full name ─────────────────────────────────────────────
                Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) setState(() => _touched.add('name'));
                  },
                  child: FlTextField(
                    label: 'Full name',
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    validator: _touched.contains('name') ? _validateName : null,
                    onChanged: (_) =>
                        _touched.contains('name') ? setState(() {}) : null,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Phone ─────────────────────────────────────────────────
                Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) setState(() => _touched.add('phone'));
                  },
                  child: FlTextField(
                    label: 'Phone number',
                    controller: _phoneCtrl,
                    hint: '(555) 000-0000',
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    prefixWidget: const PhonePrefix(),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    validator:
                        _touched.contains('phone') ? _validatePhone : null,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Password ──────────────────────────────────────────────
                Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) setState(() => _touched.add('password'));
                  },
                  child: FlTextField(
                    label: 'Password',
                    controller: _passwordCtrl,
                    obscureText: true,
                    showToggle: true,
                    textInputAction: TextInputAction.next,
                    hint: 'At least 8 characters',
                    validator: _touched.contains('password')
                        ? _validatePassword
                        : null,
                  ),
                ),
                const SizedBox(height: 16),

                // ── Confirm password ──────────────────────────────────────
                Focus(
                  onFocusChange: (hasFocus) {
                    if (!hasFocus) setState(() => _touched.add('confirm'));
                  },
                  child: FlTextField(
                    label: 'Confirm password',
                    controller: _confirmCtrl,
                    obscureText: true,
                    showToggle: true,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: _touched.contains('confirm')
                        ? _validateConfirm
                        : null,
                  ),
                ),

                const SizedBox(height: 32),
                FlButton(
                  label: 'Create account',
                  onPressed: _isLoading ? null : _submit,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 28),

                // ── Back to login ─────────────────────────────────────────
                Center(
                  child: GestureDetector(
                    onTap: () => context.go('/login'),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.arrow_back,
                          size: 16,
                          color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Back to login',
                          style: TextStyle(
                            fontSize: 15,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
