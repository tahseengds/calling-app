import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/lumio_icons.dart';
import '../../../settings/domain/app_lock_controller.dart';

enum PinMode { setup, verify }

/// In [PinMode.setup] the user enters a PIN twice; the resulting digits
/// are returned via `Navigator.pop(pin)`. In [PinMode.verify] the user
/// enters a PIN once and `pop(true|false)` reports whether it matched.
class AppLockPinScreen extends ConsumerStatefulWidget {
  final PinMode mode;
  const AppLockPinScreen({super.key, required this.mode});

  @override
  ConsumerState<AppLockPinScreen> createState() => _AppLockPinScreenState();
}

class _AppLockPinScreenState extends ConsumerState<AppLockPinScreen> {
  static const _len = 6;
  final TextEditingController _first = TextEditingController();
  final TextEditingController _second = TextEditingController();
  bool _confirming = false;
  String? _error;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _onPrimary() async {
    final controller = ref.read(appLockControllerProvider);

    if (widget.mode == PinMode.verify) {
      final ok = await controller.verifyPin(_first.text);
      if (!mounted) return;
      if (!ok) {
        setState(() => _error = 'Incorrect PIN. Try again.');
        _first.clear();
        return;
      }
      Navigator.of(context).pop(true);
      return;
    }

    // Setup
    if (!_confirming) {
      if (_first.text.length < 4) {
        setState(() => _error = 'PIN must be at least 4 digits');
        return;
      }
      setState(() {
        _confirming = true;
        _error = null;
      });
      return;
    }

    if (_first.text != _second.text) {
      setState(() {
        _error = "PINs don't match";
        _second.clear();
      });
      return;
    }
    Navigator.of(context).pop(_first.text);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final isDark = context.isDarkMode;
    final isSetup = widget.mode == PinMode.setup;

    final title = isSetup
        ? (_confirming ? 'Confirm PIN' : 'Set a PIN')
        : 'Enter PIN';

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LumioIcons.back, color: colors.fg1),
          tooltip: 'Back',
          onPressed: () {
            if (isSetup) {
              Navigator.of(context).pop();
            } else {
              Navigator.of(context).pop(false);
            }
          },
        ),
        title: Text(title, style: AppTextStyles.h1(color: colors.fg1)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isSetup
                    ? (_confirming
                        ? 'Re-enter the PIN to confirm.'
                        : 'Choose a 4–8 digit PIN used to unlock Lumio when biometrics aren\'t available.')
                    : 'Enter the PIN you set up to unlock Lumio.',
                style: AppTextStyles.body(color: colors.fg2),
              ),
              const SizedBox(height: AppSpacing.space6),
              TextField(
                controller: _confirming ? _second : _first,
                autofocus: true,
                obscureText: true,
                maxLength: _len,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: AppTextStyles.h2(color: colors.fg1)
                    .copyWith(letterSpacing: 8),
                textAlign: TextAlign.center,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '••••',
                  errorText: _error,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _onPrimary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isSetup
                        ? (_confirming ? 'Confirm' : 'Next')
                        : 'Unlock',
                    style: AppTextStyles.bodySemibold(color: Colors.white),
                  ),
                ),
              ),
            ],
        ),
        ),
      ),
    );
  }
}
