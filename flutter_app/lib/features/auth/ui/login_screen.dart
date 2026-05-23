import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_colors.dart';
import '../../../shared/widgets/fl_button.dart';
import '../../../shared/widgets/fl_text_field.dart';
import '../domain/auth_notifier.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String get _fullPhone => '+1${_phoneCtrl.text.replaceAll(RegExp(r'\D'), '')}';

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).requestLoginOtp(
            phone: _fullPhone,
            password: _passwordCtrl.text,
          );
      // GoRouter redirect fires automatically on AuthOtpPending state.
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['detail'] as String? ??
          'Login failed. Please try again.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: AppColors.danger,
        ),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 64),
                // ── Heading ───────────────────────────────────────────────
                Text(
                  'Welcome back',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to stay close to family',
                  style: TextStyle(
                    fontSize: 16,
                    color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                  ),
                ),
                const SizedBox(height: 40),
                // ── Phone field ───────────────────────────────────────────
                FlTextField(
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
                  validator: (v) {
                    final digits = v?.replaceAll(RegExp(r'\D'), '') ?? '';
                    if (digits.length < 10) {
                      return 'Enter a valid 10-digit US number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // ── Password field ────────────────────────────────────────
                FlTextField(
                  label: 'Password',
                  controller: _passwordCtrl,
                  obscureText: true,
                  showToggle: true,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (v) {
                    if ((v?.length ?? 0) < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                // ── Forgot password ───────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      // TODO prompt 13 — forgot-password flow
                    },
                    child: const Text(
                      'Forgot password?',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // ── Submit ────────────────────────────────────────────────
                FlButton(
                  label: 'Sign in',
                  onPressed: _isLoading ? null : _submit,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 32),
                // ── Register link ─────────────────────────────────────────
                Center(
                  child: GestureDetector(
                    onTap: () => context.go('/register'),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                        ),
                        children: const [
                          TextSpan(text: 'New here? '),
                          TextSpan(
                            text: 'Create an account',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
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
