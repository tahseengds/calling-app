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
import '../../../shared/widgets/fl_text_field.dart';
import '../domain/auth_notifier.dart';

/// "Set your display name + phone" — the user is signing up for the first
/// time and wants to pick the name we show their family. After this, the
/// flow is identical to login: Firebase sends an SMS, the OTP screen
/// verifies it, the backend upserts the User row using *this* name.
///
/// Existing users can also reach this screen — the name is ignored
/// server-side on returning sign-in.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  String? _e164Phone;
  bool _isLoading = false;
  final _touched = <String>{};

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    if ((v?.trim().length ?? 0) < 2) return 'Enter your name';
    return null;
  }

  Future<void> _submit() async {
    setState(() => _touched.add('name'));
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
            name: _nameCtrl.text.trim(),
            isRegistering: true,
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
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set your profile',
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
                  'Pick the name family sees. We\'ll send a code to your phone to verify.',
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
                IntlPhoneField(
                  decoration: InputDecoration(
                    labelText: 'Phone number',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  initialCountryCode: 'US',
                  invalidNumberMessage: 'Enter a valid phone number',
                  onChanged: (PhoneNumber phone) {
                    _e164Phone = phone.completeNumber;
                  },
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 32),
                FlButton(
                  label: 'Send code',
                  loadingLabel: 'Sending…',
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
