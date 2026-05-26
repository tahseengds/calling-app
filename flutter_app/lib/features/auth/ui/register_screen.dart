import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/fl_button.dart';
import '../../../shared/widgets/fl_text_field.dart';
import '../domain/auth_notifier.dart';

/// Create a Lumio account with email + password (verification link emailed
/// after submit) or with one-tap Google sign-up.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool _isLoading = false;
  bool _isGoogleLoading = false;
  final _touched = <String>{};

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    if ((v?.trim().length ?? 0) < 2) return 'Enter your name';
    return null;
  }

  String? _validateEmail(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Enter your email';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
    if (!ok) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if ((v ?? '').length < 8) return 'At least 8 characters';
    return null;
  }

  String? _validateConfirm(String? v) {
    if ((v ?? '') != _passwordCtrl.text) return 'Passwords don\'t match';
    return null;
  }

  Future<void> _submitEmail() async {
    setState(() => _touched.addAll(['name', 'email', 'password', 'confirm']));
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).registerWithEmail(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
            name: _nameCtrl.text.trim(),
          );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_firebaseAuthMessage(e)),
          backgroundColor: AppColors.danger,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create the account. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitGoogle() async {
    setState(() => _isGoogleLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithGoogle();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_firebaseAuthMessage(e)),
          backgroundColor: AppColors.danger,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Google sign-in failed. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  String _firebaseAuthMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'That email is already registered. Try signing in.';
      case 'invalid-email':
        return 'That doesn\'t look like a valid email.';
      case 'weak-password':
        return 'That password is too weak. Use at least 8 characters.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled.';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a few minutes.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return e.message ?? 'Could not create the account. Please try again.';
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
                  'We\'ll email you a link to confirm your address.',
                  style: TextStyle(fontSize: 16, color: fg2, height: 1.4),
                ),
                const SizedBox(height: 32),
                Focus(
                  onFocusChange: (f) {
                    if (!f) setState(() => _touched.add('name'));
                  },
                  child: FlTextField(
                    label: 'Display name',
                    controller: _nameCtrl,
                    textInputAction: TextInputAction.next,
                    validator: _touched.contains('name') ? _validateName : null,
                  ),
                ),
                const SizedBox(height: 14),
                Focus(
                  onFocusChange: (f) {
                    if (!f) setState(() => _touched.add('email'));
                  },
                  child: FlTextField(
                    label: 'Email',
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator:
                        _touched.contains('email') ? _validateEmail : null,
                  ),
                ),
                const SizedBox(height: 14),
                FlTextField(
                  label: 'Password',
                  controller: _passwordCtrl,
                  obscureText: true,
                  showToggle: true,
                  textInputAction: TextInputAction.next,
                  validator:
                      _touched.contains('password') ? _validatePassword : null,
                ),
                const SizedBox(height: 14),
                FlTextField(
                  label: 'Confirm password',
                  controller: _confirmCtrl,
                  obscureText: true,
                  showToggle: true,
                  textInputAction: TextInputAction.done,
                  validator:
                      _touched.contains('confirm') ? _validateConfirm : null,
                  onFieldSubmitted: (_) => _submitEmail(),
                ),
                const SizedBox(height: 24),
                FlButton(
                  label: 'Create account',
                  loadingLabel: 'Creating…',
                  onPressed: _isLoading ? null : _submitEmail,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 20),
                _OrDivider(color: colors.hairline, fg: fg3),
                const SizedBox(height: 20),
                _GoogleButton(
                  label: 'Continue with Google',
                  onPressed:
                      _isGoogleLoading ? null : _submitGoogle,
                  isLoading: _isGoogleLoading,
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
                      '← Back to sign in',
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

class _OrDivider extends StatelessWidget {
  final Color color;
  final Color fg;
  const _OrDivider({required this.color, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: color, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('or', style: TextStyle(color: fg, fontSize: 13)),
        ),
        Expanded(child: Divider(color: color, thickness: 1)),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _GoogleButton({
    required this.label,
    required this.onPressed,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final disabled = onPressed == null;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          side: BorderSide(color: colors.hairline, width: 1),
          foregroundColor: colors.fg1,
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFFFFFFFF),
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x22000000),
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'G',
                      style: TextStyle(
                        color: Color(0xFF4285F4),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    label,
                    style: TextStyle(
                      color: disabled ? colors.fg3 : colors.fg1,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
