import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/config/app_colors.dart';
import '../../../shared/widgets/fl_button.dart';
import '../../../shared/widgets/fl_text_field.dart';
import '../domain/contacts_notifier.dart';

class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  bool _isLoading = false;
  _AddError? _addError;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nicknameCtrl.dispose();
    super.dispose();
  }

  String get _fullPhone => '+1${_phoneCtrl.text.replaceAll(RegExp(r'\D'), '')}';

  Future<void> _submit() async {
    setState(() => _addError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      await ref.read(contactsNotifierProvider.notifier).addContact(
            phone: _fullPhone,
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
    } on DioException catch (e) {
      if (!mounted) return;
      final code =
          (e.response?.data as Map?)?['code'] as String? ?? '';
      final msg = (e.response?.data as Map?)?['detail'] as String? ??
          'Could not add contact.';
      setState(() {
        _addError = code == 'user_not_found'
            ? const _NotFound()
            : code == 'already_contact'
                ? const _Duplicate()
                : _OtherError(msg);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add family member'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                Text(
                  'Enter their phone number',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'They must already have a FamilyLink account.',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Phone ─────────────────────────────────────────────────
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
                    final d = v?.replaceAll(RegExp(r'\D'), '') ?? '';
                    if (d.length < 10) return 'Enter a valid 10-digit number';
                    return null;
                  },
                  onChanged: (_) => setState(() => _addError = null),
                ),
                const SizedBox(height: 16),

                // ── Nickname ──────────────────────────────────────────────
                FlTextField(
                  label: 'Nickname (optional)',
                  controller: _nicknameCtrl,
                  hint: 'e.g. Mom, Dad, Uncle Joe',
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),

                // ── Error messages ────────────────────────────────────────
                if (_addError != null) ...[
                  const SizedBox(height: 16),
                  _ErrorBanner(error: _addError!),
                ],

                const SizedBox(height: 32),
                FlButton(
                  label: 'Add family member',
                  onPressed: _isLoading ? null : _submit,
                  isLoading: _isLoading,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Error types ───────────────────────────────────────────────────────────────

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
          'User not found',
          'No FamilyLink account exists for that number.',
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
        border: Border.all(
          color: AppColors.danger.withAlpha(80),
        ),
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
