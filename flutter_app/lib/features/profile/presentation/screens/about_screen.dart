import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/error_snackbar.dart';
import '../../../../shared/widgets/lumio_icons.dart';
import '../../../../shared/widgets/lumio_logo.dart';
import '../../../../shared/widgets/settings_tile.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _info;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _info = info);
    });
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      showErrorSnackbar(context, 'Could not open link.');
    }
  }

  void _showWhatsNew() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("What's new"),
        content: const SingleChildScrollView(
          child: Text(
            '• Notification settings, message sounds, privacy controls, '
            'help & support form, and a redesigned About screen.\n'
            '• App lock with biometric / PIN.\n'
            '• Quiet hours.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final isDark = context.isDarkMode;
    final info = _info;

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
        title: Text('About', style: AppTextStyles.h1(color: colors.fg1)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.space6),
              const LumioMark(size: 88),
              const SizedBox(height: AppSpacing.space3),
              Text('Lumio',
                  style: AppTextStyles.display(color: colors.fg1)),
              const SizedBox(height: 4),
              Text(
                info == null
                    ? 'Loading version…'
                    : 'Version ${info.version} (${info.buildNumber})',
                style: AppTextStyles.secondary(color: colors.fg2),
              ),
              const SizedBox(height: AppSpacing.space8),
              SettingsSection(
                title: 'About',
                tiles: [
                  SettingsTile(
                    icon: LumioIcons.bookOpen,
                    label: "What's new",
                    onTap: _showWhatsNew,
                  ),
                  SettingsTile(
                    icon: LumioIcons.fileText,
                    label: 'Open-source licenses',
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'Lumio',
                      applicationVersion: info?.version ?? '1.0.0',
                    ),
                  ),
                  SettingsTile(
                    icon: LumioIcons.openInNew,
                    label: 'Terms of Service',
                    onTap: () => _openUrl(AppConfig.termsUrl),
                  ),
                  SettingsTile(
                    icon: LumioIcons.shield,
                    label: 'Privacy Policy',
                    onTap: () => _openUrl(AppConfig.privacyUrl),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.space8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.space4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Made with ',
                      style: AppTextStyles.caption(color: colors.fg3),
                    ),
                    const Icon(LumioIcons.heartFilled,
                        size: 12, color: AppColors.danger),
                    Text(
                      ' by Lumio',
                      style: AppTextStyles.caption(color: colors.fg3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.space6),
            ],
        ),
        ),
      ),
    );
  }
}
