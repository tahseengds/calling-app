import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:intl_phone_field/phone_number.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../shared/widgets/fl_button.dart';
import '../../../shared/widgets/lumio_logo.dart';
import '../domain/auth_notifier.dart';

/// Login = "enter your phone, we'll text you a code" — the entire auth
/// flow now goes through Firebase Phone Auth. There's no password and no
/// separate Register / Login distinction (the backend upserts the User
/// row on first sign-in).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();

  /// Latest E.164 phone number assembled by [IntlPhoneField] (country
  /// dial code + local number). Null until the user has typed enough
  /// digits to be valid for the selected country.
  String? _e164Phone;
  bool _isLoading = false;

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final phone = _e164Phone;
    if (phone == null || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid phone number for the selected country.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(authNotifierProvider.notifier).startPhoneVerification(
            phone: phone,
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
          content: Text('Could not send the code. Please try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _firebaseAuthMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return 'That doesn\'t look like a valid phone number.';
      case 'too-many-requests':
        return 'Too many attempts. Try again in a few minutes.';
      case 'network-request-failed':
        return 'Network error. Please check your connection.';
      default:
        return e.message ?? 'Could not send the code. Please try again.';
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
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LumioLogoBar(),
                const SizedBox(height: 24),
                Text(
                  'Welcome to Lumio',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: fg1,
                    height: 1.1,
                    letterSpacing: -0.01,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Enter your phone number — we\'ll send you a code by SMS.',
                  style: TextStyle(fontSize: 16, color: fg2, height: 1.4),
                ),
                const SizedBox(height: 32),
                IntlPhoneField(
                  decoration: InputDecoration(
                    labelText: 'Phone number',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  initialCountryCode: 'US',
                  // Show the most common family-app countries near the top of
                  // the picker. The user can still scroll for anything else.
                  // (intl_phone_field doesn't natively support this, so we
                  // leave the default alphabetical list — the search box in
                  // the picker covers the long tail.)
                  invalidNumberMessage: 'Enter a valid phone number',
                  onChanged: (PhoneNumber phone) {
                    _e164Phone = phone.completeNumber;
                  },
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 24),
                FlButton(
                  label: 'Send code',
                  loadingLabel: 'Sending…',
                  onPressed: _isLoading ? null : _submit,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 24),
                Text(
                  'New here? Just enter your phone — we\'ll set up your account when you verify.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: fg3, height: 1.4),
                ),
                const SizedBox(height: 16),
                Center(
                  child: GestureDetector(
                    onTap: () => context.go('/register'),
                    child: const Text(
                      'Set a display name first',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (AppConfig.uiOnly) ...[
                  const SizedBox(height: 16),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
