import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/auth_widgets.dart';
import '../../../shared/widgets/dismiss_keyboard.dart';
import '../../../shared/widgets/error_snackbar.dart';
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
      showErrorSnackbar(context, _firebaseAuthMessage(e));
    } catch (_) {
      if (!mounted) return;
      showErrorSnackbar(
          context, 'Could not create the account. Please try again.');
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
      showErrorSnackbar(context, _firebaseAuthMessage(e));
    } catch (_) {
      if (!mounted) return;
      showErrorSnackbar(context, 'Google sign-in failed. Please try again.');
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
        child: DismissKeyboard(
          child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: AutofillGroup(
            child: Form(
              key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Create your account',
                  style: AppTextStyles.display(color: fg1)
                      .copyWith(fontSize: 30, height: 1.15),
                ),
                const SizedBox(height: 10),
                Text(
                  'We\'ll email you a link to confirm your address.',
                  style: AppTextStyles.body(color: fg2),
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
                    textCapitalization: TextCapitalization.words,
                    validator: _touched.contains('name') ? _validateName : null,
                    autofillHints: const [AutofillHints.name],
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
                    autofillHints: const [AutofillHints.email, AutofillHints.username],
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
                  autofillHints: const [AutofillHints.newPassword],
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
                  autofillHints: const [AutofillHints.newPassword],
                ),
                const SizedBox(height: 24),
                FlButton(
                  label: 'Create account',
                  loadingLabel: 'Creating…',
                  onPressed: (_isLoading || _isGoogleLoading) ? null : _submitEmail,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 20),
                OrDivider(color: colors.hairline, fg: fg3),
                const SizedBox(height: 20),
                GoogleButton(
                  label: 'Continue with Google',
                  onPressed:
                      (_isLoading || _isGoogleLoading) ? null : _submitGoogle,
                  isLoading: _isGoogleLoading,
                ),
                const SizedBox(height: 20),
                Text(
                  'By continuing, you agree to our Terms and Privacy notice.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption(color: fg3),
                ),
                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/login'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
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
        ),
      ),
    );
  }
}
