import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/dismiss_keyboard.dart';
import '../../../../shared/widgets/error_snackbar.dart';
import '../../../../shared/widgets/fl_button.dart';
import '../../../../shared/widgets/lumio_icons.dart';
import '../../../settings/data/support_repository.dart';

enum _SupportCategory { bug, feature, account, other }

extension on _SupportCategory {
  String get wire => switch (this) {
        _SupportCategory.bug => 'bug',
        _SupportCategory.feature => 'feature',
        _SupportCategory.account => 'account',
        _SupportCategory.other => 'other',
      };

  String get label => switch (this) {
        _SupportCategory.bug => 'Bug',
        _SupportCategory.feature => 'Feature request',
        _SupportCategory.account => 'Account',
        _SupportCategory.other => 'Other',
      };

  IconData get icon => switch (this) {
        _SupportCategory.bug => LumioIcons.bug,
        _SupportCategory.feature => LumioIcons.heart,
        _SupportCategory.account => LumioIcons.users,
        _SupportCategory.other => LumioIcons.message,
      };
}

class HelpSupportScreen extends ConsumerStatefulWidget {
  const HelpSupportScreen({super.key});

  @override
  ConsumerState<HelpSupportScreen> createState() => _HelpSupportScreenState();
}

class _HelpSupportScreenState extends ConsumerState<HelpSupportScreen> {
  _SupportCategory _category = _SupportCategory.bug;
  final TextEditingController _messageCtrl = TextEditingController();
  bool _includeDeviceInfo = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _messageCtrl.text.trim();
    if (text.length < 10) {
      setState(() => _error = 'Please describe the issue in at least 10 characters.');
      return;
    }
    // Capture display metrics now, while we still hold a valid BuildContext
    // (MediaQuery can't be read after the awaits below).
    final media = MediaQuery.maybeOf(context);
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      String? version;
      try {
        final info = await PackageInfo.fromPlatform();
        version = '${info.version}+${info.buildNumber}';
      } catch (_) {}

      final platform = Platform.operatingSystem;
      final deviceInfo =
          _includeDeviceInfo ? await _collectDeviceInfo(media) : null;

      await ref.read(supportRepositoryProvider).submit(
            category: _category.wire,
            message: text,
            appVersion: version,
            platform: platform,
            deviceInfo: deviceInfo,
          );

      if (!mounted) return;
      showSuccessSnackbar(context, "Thanks — we'll look into it.");
      context.pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Could not submit. Check your connection and try again.';
      });
    }
  }

  /// Gathers as much diagnostic detail as we can about the app, OS, hardware,
  /// and display. Every section is individually guarded so a single failure
  /// never blocks the report. We deliberately collect no contacts, messages,
  /// or precise identifiers beyond the OS-provided vendor/device IDs.
  Future<Map<String, dynamic>> _collectDeviceInfo(MediaQueryData? media) async {
    final map = <String, dynamic>{};

    // ── App / package ────────────────────────────────────────────────────
    try {
      final info = await PackageInfo.fromPlatform();
      map['app'] = {
        'name': info.appName,
        'package': info.packageName,
        'version': info.version,
        'build_number': info.buildNumber,
        if (info.installerStore != null) 'installer': info.installerStore,
      };
    } catch (_) {}

    // ── OS / runtime (dart:io) ───────────────────────────────────────────
    try {
      final now = DateTime.now();
      map['os'] = {
        'platform': Platform.operatingSystem,
        'os_version': Platform.operatingSystemVersion,
        'locale': Platform.localeName,
        'num_processors': Platform.numberOfProcessors,
        'timezone': now.timeZoneName,
        'timezone_offset_minutes': now.timeZoneOffset.inMinutes,
        'dart_version': Platform.version,
      };
    } catch (_) {}

    // ── Display metrics ──────────────────────────────────────────────────
    if (media != null) {
      try {
        map['display'] = {
          'width_dp': media.size.width.round(),
          'height_dp': media.size.height.round(),
          'device_pixel_ratio': media.devicePixelRatio,
          'text_scale': media.textScaler.scale(1.0),
          'brightness': media.platformBrightness.name,
          'padding_top': media.padding.top.round(),
          'padding_bottom': media.padding.bottom.round(),
        };
      } catch (_) {}
    }

    // ── Hardware / device (device_info_plus) ─────────────────────────────
    try {
      final plugin = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await plugin.androidInfo;
        map['device'] = {
          'type': 'android',
          'brand': a.brand,
          'manufacturer': a.manufacturer,
          'model': a.model,
          'device': a.device,
          'product': a.product,
          'hardware': a.hardware,
          'board': a.board,
          'android_release': a.version.release,
          'sdk_int': a.version.sdkInt,
          'security_patch': a.version.securityPatch,
          'is_physical_device': a.isPhysicalDevice,
          'supported_abis': a.supportedAbis,
          'fingerprint': a.fingerprint,
        };
      } else if (Platform.isIOS) {
        final i = await plugin.iosInfo;
        map['device'] = {
          'type': 'ios',
          'name': i.name,
          'model': i.model,
          'localized_model': i.localizedModel,
          'system_name': i.systemName,
          'system_version': i.systemVersion,
          'machine': i.utsname.machine,
          'is_physical_device': i.isPhysicalDevice,
          'identifier_for_vendor': i.identifierForVendor,
        };
      }
    } catch (_) {}

    return map;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final isDark = context.isDarkMode;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LumioIcons.back, color: colors.fg1),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Help & support',
          style: AppTextStyles.h1(color: colors.fg1),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: DismissKeyboard(
          child: SingleChildScrollView(
          // Pad the bottom by the keyboard inset so the Submit button always
          // clears the on-screen keyboard on small phones.
          padding: EdgeInsets.fromLTRB(
            AppSpacing.space4,
            AppSpacing.space4,
            AppSpacing.space4,
            AppSpacing.space4 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    const Icon(LumioIcons.info,
                        color: AppColors.primary, size: 20),
                    const SizedBox(width: AppSpacing.space3),
                    Expanded(
                      child: Text(
                        'Tell us what\'s wrong, what you\'d like to see, or anything else on your mind. Reports go straight to the Lumio team.',
                        style: AppTextStyles.secondary(color: colors.fg2)
                            .copyWith(height: 1.35),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space6),
              Text(
                'CATEGORY',
                style: AppTextStyles.captionSemibold(color: colors.fg3)
                    .copyWith(letterSpacing: 0.8),
              ),
              const SizedBox(height: AppSpacing.space2),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in _SupportCategory.values)
                    ChoiceChip(
                      avatar: Icon(c.icon, size: 18,
                          color: _category == c
                              ? Colors.white
                              : colors.fg2),
                      label: Text(c.label),
                      labelStyle: AppTextStyles.secondarySemibold(
                        color: _category == c ? Colors.white : colors.fg1,
                      ),
                      selected: _category == c,
                      selectedColor: AppColors.primary,
                      backgroundColor: isDark
                          ? AppColors.darkSurface
                          : AppColors.lightSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        side: BorderSide(color: colors.hairline),
                      ),
                      onSelected: (_) => setState(() => _category = c),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.space6),
              Text(
                'WHAT HAPPENED?',
                style: AppTextStyles.captionSemibold(color: colors.fg3)
                    .copyWith(letterSpacing: 0.8),
              ),
              const SizedBox(height: AppSpacing.space2),
              TextField(
                controller: _messageCtrl,
                style: AppTextStyles.body(color: colors.fg1),
                maxLines: 6,
                minLines: 6,
                maxLength: 1000,
                decoration: InputDecoration(
                  hintText:
                      'Describe what went wrong, what you expected, and steps to reproduce…',
                  hintStyle: AppTextStyles.body(color: colors.fg3),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: AppSpacing.space2),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeDeviceInfo,
                onChanged: (v) => setState(() => _includeDeviceInfo = v ?? true),
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: AppColors.primary,
                title: Text(
                  'Include device info',
                  style: AppTextStyles.body(color: colors.fg1),
                ),
                subtitle: Text(
                  'Helps us diagnose. We never collect contacts or messages.',
                  style: AppTextStyles.caption(color: colors.fg3),
                ),
              ),
              const SizedBox(height: AppSpacing.space6),
              FlButton(
                label: 'Submit',
                loadingLabel: 'Submitting…',
                isLoading: _submitting,
                onPressed: _submitting ? null : _submit,
              ),
            ],
        ),
        ),
        ),
      ),
    );
  }
}
