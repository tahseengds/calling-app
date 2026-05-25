import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
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
    setState(() => _touched.addAll(['name', 'phone', 'password', 'confirm']));
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).register(
            name: _nameCtrl.text.trim(),
            phone: _fullPhone,
            password: _passwordCtrl.text,
          );
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
    final colors = context.lumioColors;
    final fg1 = colors.fg1;
    final fg2 = colors.fg2;
    final fg3 = colors.fg3;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create your account',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: fg1,
                    height: 1.15,
                    letterSpacing: -0.01,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'One account keeps you connected to everyone in the family.',
                  style: TextStyle(fontSize: 16, color: fg2, height: 1.4),
                ),
                const SizedBox(height: 32),
                Focus(
                  onFocusChange: (f) {
                    if (!f) setState(() => _touched.add('name'));
                  },
                  child: FlTextField(
                    label: 'Full name',
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    validator: _touched.contains('name') ? _validateName : null,
                  ),
                ),
                const SizedBox(height: 14),
                Focus(
                  onFocusChange: (f) {
                    if (!f) setState(() => _touched.add('phone'));
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
                const SizedBox(height: 14),
                Focus(
                  onFocusChange: (f) {
                    if (!f) setState(() => _touched.add('password'));
                  },
                  child: FlTextField(
                    label: 'Password',
                    controller: _passwordCtrl,
                    obscureText: true,
                    showToggle: true,
                    textInputAction: TextInputAction.next,
                    hint: 'At least 8 characters.',
                    validator: _touched.contains('password')
                        ? _validatePassword
                        : null,
                  ),
                ),
                const SizedBox(height: 14),
                Focus(
                  onFocusChange: (f) {
                    if (!f) setState(() => _touched.add('confirm'));
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
                  label: 'Continue',
                  onPressed: _isLoading ? null : _submit,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 20),
                Text(
                  'By continuing, you agree to our Terms and Privacy notice.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: fg3, height: 1.45),
                ),
                if (AppConfig.uiOnly) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => ref
                              .read(authNotifierProvider.notifier)
                              .signInDemo(),
                      child: const Text(
                        'Explore app without signing in',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Center(
                  child: GestureDetector(
                    onTap: () => context.go('/login'),
                    child: const Text(
                      '← Back to login',
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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
