import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/lumio_icons.dart';
import '../../domain/profile_notifier.dart';

class EditNameScreen extends ConsumerStatefulWidget {
  const EditNameScreen({super.key});

  @override
  ConsumerState<EditNameScreen> createState() => _EditNameScreenState();
}

class _EditNameScreenState extends ConsumerState<EditNameScreen> {
  late final TextEditingController _controller;
  bool _isLoading = false;
  String _initialName = '';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    // Prefill the field once the data is loaded
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profileState = ref.read(profileNotifierProvider);
      if (profileState.hasValue) {
        final currentName = profileState.value!.name;
        setState(() {
          _initialName = currentName;
          _controller.text = currentName;
        });
      }
    });
    _controller.addListener(_validateInput);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validateInput() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _errorText = 'Name cannot be empty');
    } else if (text.length < 2) {
      setState(() => _errorText = 'Name must be at least 2 characters');
    } else if (text.length > 30) {
      setState(() => _errorText = 'Name cannot exceed 30 characters');
    } else {
      setState(() => _errorText = null);
    }
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _errorText != null || text == _initialName) return;

    setState(() => _isLoading = true);

    try {
      await ref.read(profileNotifierProvider.notifier).updateName(text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(LumioIcons.check, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Name updated successfully',
                  style: AppTextStyles.secondaryMedium(color: Colors.white),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update name. Please try again.',
              style: AppTextStyles.secondaryMedium(color: Colors.white),
            ),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final isDark = context.isDarkMode;
    final text = _controller.text.trim();
    final canSave = text.isNotEmpty && _errorText == null && text != _initialName && !_isLoading;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LumioIcons.back, color: colors.fg1),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Edit Name',
          style: AppTextStyles.h1(color: colors.fg1),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.space4),
            child: Center(
              child: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.0,
                        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                      ),
                    )
                  : TextButton(
                      onPressed: canSave ? _save : null,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        disabledForegroundColor: colors.fg3,
                      ),
                      child: Text(
                        'Save',
                        style: AppTextStyles.secondarySemibold(
                          color: canSave ? AppColors.primary : colors.fg3,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter your display name',
                style: AppTextStyles.captionSemibold(color: colors.fg3).copyWith(
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: AppSpacing.space3),
              TextField(
                controller: _controller,
                autofocus: true,
                style: AppTextStyles.body(color: colors.fg1),
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: 'Display name',
                  hintStyle: AppTextStyles.body(color: colors.fg3),
                  errorText: _errorText,
                  suffixIcon: _controller.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: colors.fg3, size: 20),
                          onPressed: () => _controller.clear(),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: AppSpacing.space3),
              Text(
                'This name will be visible to other members when you make calls or send messages on Lumio.',
                style: AppTextStyles.caption(color: colors.fg2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
