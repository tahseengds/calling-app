import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/lumio_icons.dart';
import '../../domain/profile_notifier.dart';

class ChangeNumberScreen extends ConsumerStatefulWidget {
  const ChangeNumberScreen({super.key});

  @override
  ConsumerState<ChangeNumberScreen> createState() => _ChangeNumberScreenState();
}

class _ChangeNumberScreenState extends ConsumerState<ChangeNumberScreen> {
  int _currentStep = 0; // 0: Input phone, 1: Verify OTP, 2: Success status
  final _phoneController = TextEditingController();
  final _phoneFormKey = GlobalKey<FormState>();
  
  bool _isLoading = false;
  String _newPhone = '';
  String? _phoneError;
  String? _otpError;
  
  // OTP Step details
  late Timer _resendTimer;
  int _resendSeconds = 30;
  bool _canResend = false;
  String _generatedOtp = '123456'; // Default mock OTP

  @override
  void initState() {
    super.initState();
    _phoneController.text = '+';
  }

  @override
  void dispose() {
    _phoneController.dispose();
    if (_currentStep == 1) {
      _resendTimer.cancel();
    }
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _resendSeconds = 30;
      _canResend = false;
    });
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds == 0) {
        setState(() {
          _canResend = true;
          timer.cancel();
        });
      } else {
        setState(() {
          _resendSeconds--;
        });
      }
    });
  }

  // Step 1: Request OTP
  Future<void> _requestOtp() async {
    if (!_phoneFormKey.currentState!.validate()) return;
    
    final phone = _phoneController.text.trim();
    final profileState = ref.read(profileNotifierProvider);
    
    if (profileState.hasValue && profileState.value!.phone == phone) {
      setState(() {
        _phoneError = 'This is already your current number';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _phoneError = null;
    });

    // Simulate requesting OTP from backend
    await Future.delayed(const Duration(milliseconds: 1000));

    if (!mounted) return;
    
    // Generate a mock code for UI demonstration
    final randomOtp = (100000 + (900000 * (DateTime.now().millisecond / 1000))).round().toString();
    
    setState(() {
      _isLoading = false;
      _newPhone = phone;
      _generatedOtp = AppConfig.uiOnly ? '123456' : randomOtp;
      _currentStep = 1;
    });
    
    _startResendTimer();
    
    // Show OTP in debug mode / UI-only mode
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Verification code sent! Code is: $_generatedOtp (Mock)',
          style: AppTextStyles.secondaryMedium(color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    );
  }

  // Step 2: Verify OTP and save phone number
  Future<void> _verifyAndSubmit(String code) async {
    if (code != _generatedOtp) {
      setState(() {
        _otpError = 'Invalid code. Try again.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _otpError = null;
    });

    try {
      // Call profile notifier to update number on state/server
      await ref.read(profileNotifierProvider.notifier).updatePhone(_newPhone);
      
      if (_resendTimer.isActive) {
        _resendTimer.cancel();
      }

      setState(() {
        _isLoading = false;
        _currentStep = 2; // Success
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _otpError = 'Failed to update phone number. Please try again.';
      });
    }
  }

  void _resendCode() {
    if (!_canResend) return;
    _startResendTimer();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Code re-sent! Code is: $_generatedOtp (Mock)',
          style: AppTextStyles.secondaryMedium(color: Colors.white),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final isDark = context.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: _currentStep == 2
          ? null // No app bar for success screen
          : AppBar(
              backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
              elevation: 0,
              leading: IconButton(
                icon: Icon(LumioIcons.back, color: colors.fg1),
                onPressed: () {
                  if (_currentStep == 1) {
                    _resendTimer.cancel();
                    setState(() {
                      _currentStep = 0;
                      _otpError = null;
                    });
                  } else {
                    context.pop();
                  }
                },
              ),
              title: Text(
                'Change Number',
                style: AppTextStyles.h1(color: colors.fg1),
              ),
            ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildStepContent(colors, isDark),
        ),
      ),
    );
  }

  Widget _buildStepContent(LumioColors colors, bool isDark) {
    switch (_currentStep) {
      case 0:
        return _buildPhoneInputStep(colors, isDark);
      case 1:
        return _buildOtpVerifyStep(colors, isDark);
      case 2:
        return _buildSuccessStep(colors, isDark);
      default:
        return const SizedBox();
    }
  }

  // STEP 0: PHONE INPUT
  Widget _buildPhoneInputStep(LumioColors colors, bool isDark) {
    final profileState = ref.watch(profileNotifierProvider);
    final currentPhone = profileState.value?.phone ?? 'Not available';

    return Padding(
      key: const ValueKey('phone_input_step'),
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(AppSpacing.space4),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colors.hairline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(LumioIcons.info, color: AppColors.primary, size: 20),
                const SizedBox(width: AppSpacing.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Important Notice',
                        style: AppTextStyles.bodySemibold(color: colors.fg1),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Changing your phone number will update your profile. Your chats, groups, call logs, and contacts will remain linked to your account.',
                        style: AppTextStyles.secondary(color: colors.fg2).copyWith(height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space6),
          
          Text(
            'CURRENT PHONE NUMBER',
            style: AppTextStyles.captionSemibold(color: colors.fg3).copyWith(letterSpacing: 0.8),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            currentPhone,
            style: AppTextStyles.body(color: colors.fg2),
          ),
          
          const SizedBox(height: AppSpacing.space6),
          
          Form(
            key: _phoneFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ENTER NEW PHONE NUMBER',
                  style: AppTextStyles.captionSemibold(color: colors.fg3).copyWith(letterSpacing: 0.8),
                ),
                const SizedBox(height: AppSpacing.space2),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: AppTextStyles.body(color: colors.fg1),
                  decoration: InputDecoration(
                    hintText: '+1 555-555-5555',
                    hintStyle: AppTextStyles.body(color: colors.fg3),
                    errorText: _phoneError,
                  ),
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Phone number is required';
                    }
                    if (!val.startsWith('+')) {
                      return 'Must include country code starting with +';
                    }
                    if (val.length < 8) {
                      return 'Enter a valid phone number';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          
          const Spacer(),
          
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _requestOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(
                      'Next',
                      style: AppTextStyles.bodySemibold(color: Colors.white),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // STEP 1: OTP VERIFY
  Widget _buildOtpVerifyStep(LumioColors colors, bool isDark) {
    return Padding(
      key: const ValueKey('otp_verify_step'),
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verify your number',
            style: AppTextStyles.h2(color: colors.fg1),
          ),
          const SizedBox(height: AppSpacing.space2),
          Text(
            'We\'ve sent a 6-digit verification code to $_newPhone.',
            style: AppTextStyles.secondary(color: colors.fg2),
          ),
          const SizedBox(height: AppSpacing.space6),
          
          _OtpInputRow(
            onCompleted: _verifyAndSubmit,
            errorText: _otpError,
          ),
          
          const SizedBox(height: AppSpacing.space6),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Didn\'t receive code? ',
                style: AppTextStyles.secondary(color: colors.fg2),
              ),
              GestureDetector(
                onTap: _canResend ? _resendCode : null,
                child: Text(
                  _canResend ? 'Resend' : 'Resend in ${_resendSeconds}s',
                  style: AppTextStyles.secondarySemibold(
                    color: _canResend ? AppColors.primary : colors.fg3,
                  ),
                ),
              ),
            ],
          ),
          
          if (_isLoading) ...[
            const SizedBox(height: AppSpacing.space6),
            const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          ],
        ],
      ),
    );
  }

  // STEP 2: SUCCESS STATUS
  Widget _buildSuccessStep(LumioColors colors, bool isDark) {
    return Padding(
      key: const ValueKey('success_step'),
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          // Beautiful Circle Success Animation Mock
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.success.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LumioIcons.check,
                color: AppColors.success,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.space6),
          Text(
            'Number Changed!',
            style: AppTextStyles.display(color: colors.fg1),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.space3),
          Text(
            'Your phone number has been successfully updated to $_newPhone. All account details are preserved.',
            style: AppTextStyles.body(color: colors.fg2),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: () {
                context.pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                elevation: 0,
              ),
              child: Text(
                'Done',
                style: AppTextStyles.bodySemibold(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Custom Row of 6 individual code fields
class _OtpInputRow extends StatefulWidget {
  final ValueChanged<String> onCompleted;
  final String? errorText;

  const _OtpInputRow({
    required this.onCompleted,
    this.errorText,
  });

  @override
  State<_OtpInputRow> createState() => _OtpInputRowState();
}

class _OtpInputRowState extends State<_OtpInputRow> {
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final List<TextEditingController> _controllers = List.generate(6, (_) => TextEditingController());
  final List<String> _code = List.filled(6, '');

  @override
  void dispose() {
    for (var f in _focusNodes) {
      f.dispose();
    }
    for (var c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (value.length > 1) {
      // If user pastes a multi-digit code, distribute it
      final cleanText = value.replaceAll(RegExp(r'\D'), '');
      for (int i = 0; i < 6 && i < cleanText.length; i++) {
        _controllers[index + i].text = cleanText[i];
        _code[index + i] = cleanText[i];
      }
      final fullCode = _code.join();
      if (fullCode.length == 6) {
        widget.onCompleted(fullCode);
      }
      FocusScope.of(context).requestFocus(_focusNodes[5]);
      return;
    }

    _code[index] = value;
    if (value.isNotEmpty) {
      if (index < 5) {
        FocusScope.of(context).requestFocus(_focusNodes[index + 1]);
      } else {
        _focusNodes[index].unfocus();
        final fullCode = _code.join();
        if (fullCode.length == 6) {
          widget.onCompleted(fullCode);
        }
      }
    }
    setState(() {});
  }

  void _onKey(KeyEvent event, int index) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.backspace) {
      if (_controllers[index].text.isEmpty && index > 0) {
        _controllers[index - 1].clear();
        _code[index - 1] = '';
        FocusScope.of(context).requestFocus(_focusNodes[index - 1]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final isDark = context.isDarkMode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) {
            return SizedBox(
              width: 48,
              height: 56,
              child: KeyboardListener(
                focusNode: FocusNode(), // Dummy focus node to capture key events before textfield gets it
                onKeyEvent: (event) => _onKey(event, index),
                child: TextField(
                  controller: _controllers[index],
                  focusNode: _focusNodes[index],
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.h1(color: colors.fg1),
                  maxLength: 1,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    fillColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    filled: true,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(
                        color: widget.errorText != null ? AppColors.danger : colors.hairline,
                        width: 1.5,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2.0,
                      ),
                    ),
                  ),
                  onChanged: (val) => _onChanged(val, index),
                ),
              ),
            );
          }),
        ),
        if (widget.errorText != null) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(
            widget.errorText!,
            style: AppTextStyles.secondary(color: AppColors.danger),
          ),
        ],
      ],
    );
  }
}
