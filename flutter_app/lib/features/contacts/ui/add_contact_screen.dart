import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/dismiss_keyboard.dart';
import '../../../shared/widgets/fl_button.dart';
import '../../../shared/widgets/fl_text_field.dart';
import '../../../shared/widgets/lumio_back_button.dart';
import '../domain/contacts_notifier.dart';

class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  bool _isLoading = false;
  _AddError? _addError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nicknameCtrl.dispose();
    super.dispose();
  }

  String get _normalizedEmail => _emailCtrl.text.trim().toLowerCase();

  Future<void> _submit() async {
    setState(() => _addError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(contactsNotifierProvider.notifier).addContact(
            email: _normalizedEmail,
            nickname: _nicknameCtrl.text.trim().isEmpty
                ? null
                : _nicknameCtrl.text.trim(),
          );
      if (!mounted) return;
      context.pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Family member added!'),
          backgroundColor: AppColors.success,
        ),
      );
    } on DuplicateContactException {
      if (!mounted) return;
      setState(() => _addError = const _Duplicate());
    } on DioException catch (e) {
      if (!mounted) return;
      final status = e.response?.statusCode;
      final code = (e.response?.data as Map?)?['code'] as String? ?? '';
      final msg = (e.response?.data as Map?)?['detail'] as String? ??
          'Could not add contact.';
      setState(() {
        if (status == 404 || code == 'not_found' || code == 'user_not_found') {
          _addError = const _NotFound();
        } else if (status == 409 ||
            code == 'conflict' ||
            code == 'already_contact') {
          _addError = const _Duplicate();
        } else {
          _addError = _OtherError(msg);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _addError = _OtherError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final fg1 = colors.fg1;
    final fg2 = colors.fg2;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: DismissKeyboard(
          child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LumioBackButton(onPressed: () => context.pop()),
                const SizedBox(height: 20),
                Text(
                  'Add a family member',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: fg1,
                    letterSpacing: -0.01,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  "Enter their email. We'll find them on Lumio — or you can invite them if they haven't joined yet.",
                  style: TextStyle(fontSize: 15, color: fg2, height: 1.45),
                ),
                const SizedBox(height: 28),
                FlTextField(
                  label: 'Email',
                  controller: _emailCtrl,
                  hint: 'name@example.com',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return 'Enter an email';
                    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                        .hasMatch(t);
                    if (!ok) return 'Enter a valid email';
                    return null;
                  },
                  onChanged: (_) => setState(() => _addError = null),
                ),
                const SizedBox(height: 16),
                FlTextField(
                  label: 'Nickname · optional',
                  controller: _nicknameCtrl,
                  hint: 'e.g. Mom, Dad, Uncle Joe',
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
                if (_addError != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(error: _addError!),
                ],
                const SizedBox(height: 32),
                FlButton(
                  label: 'Add',
                  onPressed: _isLoading ? null : _submit,
                  isLoading: _isLoading,
                ),
                // "Send invite" was previously a dead button. Drop it until
                // we have a real invite flow (share_plus + deep link).
              ],
            ),
          ),
        ),
        ),
      ),
    );
  }
}

sealed class _AddError {
  const _AddError();
}

final class _NotFound extends _AddError {
  const _NotFound();
}

final class _Duplicate extends _AddError {
  const _Duplicate();
}

final class _OtherError extends _AddError {
  final String message;
  const _OtherError(this.message);
}

class _ErrorBanner extends StatelessWidget {
  final _AddError error;
  const _ErrorBanner({required this.error});

  @override
  Widget build(BuildContext context) {
    final (icon, title, subtitle) = switch (error) {
      _NotFound() => (
          Icons.person_search_outlined,
          'Not on Lumio yet',
          'No one with that email has joined Lumio. Invite them so they can join your family.',
        ),
      _Duplicate() => (
          Icons.people_outline,
          'Already in your family',
          'This person is already on your contact list.',
        ),
      _OtherError(:final message) => (
          Icons.error_outline,
          'Something went wrong',
          message,
        ),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withAlpha(80)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.danger, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: AppColors.danger.withAlpha(200),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
