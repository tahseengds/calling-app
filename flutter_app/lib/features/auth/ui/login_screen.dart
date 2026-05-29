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
import '../../../shared/widgets/lumio_logo.dart';
import '../domain/auth_notifier.dart';

/// Sign in with email + password, or with Google.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return 'Enter your email';
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t);
    if (!ok) return 'Enter a valid email';
    return null;
  }

  String? _validatePassword(String? v) {
    if ((v ?? '').isEmpty) return 'Enter your password';
    return null;
  }

  Future<void> _submitEmail() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).signInWithEmail(
            email: _emailCtrl.text,
            password: _passwordCtrl.text,
          );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      showErrorSnackbar(context, _firebaseAuthMessage(e));
    } catch (_) {
      if (!mounted) return;
      showErrorSnackbar(context, 'Could not sign in. Please try again.');
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
      case 'invalid-email':
        return 'That doesn\'t look like a valid email.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Email or password is incorrect.';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a few minutes.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return e.message ?? 'Could not sign in. Please try again.';
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
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: AutofillGroup(
            child: Form(
              key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LumioLogoBar(),
                const SizedBox(height: 24),
                Text(
                  'Welcome to Lumio',
                  style: AppTextStyles.display(color: fg1)
                      .copyWith(fontSize: 32, height: 1.1),
                ),
                const SizedBox(height: 10),
                Text(
                  'Sign in with your email and password.',
                  style: AppTextStyles.body(color: fg2),
                ),
                const SizedBox(height: 32),
                FlTextField(
                  label: 'Email',
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: _validateEmail,
                  autofillHints: const [AutofillHints.email, AutofillHints.username],
                ),
                const SizedBox(height: 14),
                FlTextField(
                  label: 'Password',
                  controller: _passwordCtrl,
                  obscureText: true,
                  showToggle: true,
                  textInputAction: TextInputAction.done,
                  validator: _validatePassword,
                  onFieldSubmitted: (_) => _submitEmail(),
                  autofillHints: const [AutofillHints.password],
                ),
                const SizedBox(height: 24),
                FlButton(
                  label: 'Sign in',
                  loadingLabel: 'Signing in…',
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
                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/register'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      tapTargetSize: MaterialTapTargetSize.padded,
                    ),
                    child: RichText(
                      text: TextSpan(
                        text: 'New to Lumio? ',
                        style: AppTextStyles.secondary(color: fg2),
                        children: [
                          TextSpan(
                            text: 'Create an account',
                            style: AppTextStyles.secondarySemibold(
                                color: AppColors.primary),
                          ),
                        ],
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
