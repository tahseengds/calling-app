import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/lumio_icons.dart';
import '../../../../shared/widgets/settings_tile.dart';
import '../../../settings/domain/app_lock_controller.dart';
import '../../../settings/domain/models/privacy_settings.dart';
import '../../../settings/domain/privacy_settings_notifier.dart';
import '../../../settings/domain/settings_save_error.dart';
import 'app_lock_pin_screen.dart';

class PrivacyScreen extends ConsumerWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lumioColors;
    final isDark = context.isDarkMode;
    final async = ref.watch(privacySettingsProvider);

    // Surface save failures (the toggle already rolled back) with a snackbar.
    ref.listen(settingsSaveErrorProvider, (_, err) {
      if (err == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Couldn't save — check your connection and try again."),
          backgroundColor: AppColors.danger,
        ),
      );
      ref.read(settingsSaveErrorProvider.notifier).state = null;
    });

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
        title: Text('Privacy', style: AppTextStyles.h1(color: colors.fg1)),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
        ),
          error: (_, _) => Center(
            child: TextButton(
              onPressed: () =>
                  ref.read(privacySettingsProvider.notifier).load(),
              child: const Text('Retry'),
            ),
          ),
          data: (p) => _Body(prefs: p),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final PrivacySettings prefs;
  const _Body({required this.prefs});

  Future<void> _pickVisibility(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required VisibilityLevel current,
    required Future<void> Function(VisibilityLevel) setter,
  }) async {
    final v = await Navigator.of(context).push<VisibilityLevel>(
      MaterialPageRoute(
        builder: (_) => _VisibilityPickerScreen(
          title: title,
          current: current,
        ),
      ),
    );
    if (v != null) await setter(v);
  }

  Future<void> _pickOnline(BuildContext context, WidgetRef ref) async {
    final v = await Navigator.of(context).push<OnlineVisibility>(
      MaterialPageRoute(
        builder: (_) => _OnlinePickerScreen(current: prefs.onlineStatusVisibility),
      ),
    );
    if (v != null) {
      await ref.read(privacySettingsProvider.notifier).setOnlineStatus(v);
    }
  }

  Future<void> _pickGroups(BuildContext context, WidgetRef ref) async {
    final v = await Navigator.of(context).push<GroupsWhoCanAdd>(
      MaterialPageRoute(
        builder: (_) => _GroupsPickerScreen(current: prefs.groupsWhoCanAdd),
      ),
    );
    if (v != null) {
      await ref.read(privacySettingsProvider.notifier).setGroupsWhoCanAdd(v);
    }
  }

  Future<void> _pickAutoLock(BuildContext context, WidgetRef ref) async {
    const options = <int>[0, 1, 5, 30];
    final v = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => _AutoLockPickerScreen(
          current: prefs.appLockAutoLockMinutes,
          options: options,
        ),
      ),
    );
    if (v != null) {
      await ref.read(privacySettingsProvider.notifier).setAppLockAutoLockMinutes(v);
    }
  }

  Future<void> _toggleAppLock(
    BuildContext context,
    WidgetRef ref,
    bool turnOn,
  ) async {
    final notifier = ref.read(privacySettingsProvider.notifier);
    final controller = ref.read(appLockControllerProvider);
    final messenger = ScaffoldMessenger.of(context);

    if (!turnOn) {
      try {
        await notifier.setAppLockEnabled(false);
        await controller.clearPin();
      } catch (_) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Could not disable App Lock. Try again.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      return;
    }

    // ── Turning ON ──
    // First, try biometrics — if the device supports it AND a real prompt
    // succeeds, no PIN is needed (the OS already gates with biometric).
    final hasBio = await controller.canUseBiometrics();
    if (hasBio) {
      final result =
          await controller.authenticateBiometric(reason: 'Enable App Lock');
      switch (result) {
        case AuthOutcome.success:
          try {
            await notifier.setAppLockEnabled(true);
            messenger.showSnackBar(
              const SnackBar(content: Text('App Lock enabled')),
            );
          } catch (_) {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Could not save App Lock setting.'),
                backgroundColor: AppColors.danger,
              ),
            );
          }
          return;
        case AuthOutcome.cancelled:
          // User backed out — leave the switch off, say nothing.
          return;
        case AuthOutcome.unavailable:
          // Fall through to PIN setup.
          break;
      }
    }

    // No biometrics (or biometrics unavailable) → set a PIN.
    if (!context.mounted) return;
    final pin = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => const AppLockPinScreen(mode: PinMode.setup),
      ),
    );
    if (pin == null || pin.isEmpty) return;
    try {
      await controller.setPin(pin);
      await notifier.setAppLockEnabled(true);
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('App Lock enabled — PIN set')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not save PIN. Try again.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  String _autoLockLabel(int m) => switch (m) {
        0 => 'Immediately',
        1 => 'After 1 minute',
        5 => 'After 5 minutes',
        30 => 'After 30 minutes',
        _ => 'After $m minutes',
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(privacySettingsProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Column(
        children: [
          SettingsSection(
            title: 'Who can see my…',
            tiles: [
              SettingsTile(
                icon: LumioIcons.eye,
                label: 'Last seen',
                subtitle: prefs.lastSeenVisibility.label,
                onTap: () => _pickVisibility(
                  context,
                  ref,
                  title: 'Last seen',
                  current: prefs.lastSeenVisibility,
                  setter: notifier.setLastSeen,
                ),
              ),
              SettingsTile(
                icon: LumioIcons.camera,
                label: 'Profile photo',
                subtitle: prefs.profilePhotoVisibility.label,
                onTap: () => _pickVisibility(
                  context,
                  ref,
                  title: 'Profile photo',
                  current: prefs.profilePhotoVisibility,
                  setter: notifier.setProfilePhoto,
                ),
              ),
              SettingsTile(
                icon: LumioIcons.info,
                label: 'About',
                subtitle: prefs.aboutVisibility.label,
                onTap: () => _pickVisibility(
                  context,
                  ref,
                  title: 'About',
                  current: prefs.aboutVisibility,
                  setter: notifier.setAbout,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Messaging',
            tiles: [
              SettingsSwitchTile(
                icon: LumioIcons.check,
                label: 'Read receipts',
                subtitle:
                    "If turned off, you won't see read receipts from others either.",
                value: prefs.readReceipts,
                onChanged: notifier.setReadReceipts,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Presence',
            tiles: [
              SettingsTile(
                icon: LumioIcons.eye,
                label: 'Online',
                subtitle: prefs.onlineStatusVisibility.label,
                onTap: () => _pickOnline(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Groups',
            tiles: [
              SettingsTile(
                icon: LumioIcons.groups,
                label: 'Who can add me to groups',
                subtitle: prefs.groupsWhoCanAdd.label,
                onTap: () => _pickGroups(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Calls',
            tiles: [
              SettingsSwitchTile(
                icon: LumioIcons.phoneOff,
                label: 'Silence unknown callers',
                subtitle:
                    'Calls from people not in your contacts are silenced and sent to call history.',
                value: prefs.callsSilenceUnknown,
                onChanged: notifier.setSilenceUnknownCallers,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'App lock',
            tiles: [
              SettingsSwitchTile(
                icon: LumioIcons.fingerprint,
                label: 'Require unlock',
                subtitle: prefs.appLockEnabled
                    ? 'Biometric or PIN required to open Lumio'
                    : 'Use biometric or PIN to open Lumio',
                value: prefs.appLockEnabled,
                onChanged: (v) => _toggleAppLock(context, ref, v),
              ),
              if (prefs.appLockEnabled)
                SettingsTile(
                  icon: LumioIcons.lockClock,
                  label: 'Auto-lock',
                  subtitle: _autoLockLabel(prefs.appLockAutoLockMinutes),
                  onTap: () => _pickAutoLock(context, ref),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Blocked',
            tiles: [
              SettingsTile(
                icon: LumioIcons.block,
                label: 'Blocked contacts',
                onTap: () => context.push('/profile/privacy/blocked'),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Pickers ─────────────────────────────────────────────────────────────

class _VisibilityPickerScreen extends StatelessWidget {
  final String title;
  final VisibilityLevel current;

  const _VisibilityPickerScreen({required this.title, required this.current});

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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title, style: AppTextStyles.h1(color: colors.fg1)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: SettingsSection(
            tiles: [
              for (final v in VisibilityLevel.values)
                SettingsRadioTile<VisibilityLevel>(
                  label: v.label,
                  value: v,
                  groupValue: current,
                  onChanged: (chosen) => Navigator.of(context).pop(chosen),
                ),
            ],
        ),
        ),
      ),
    );
  }
}

class _OnlinePickerScreen extends StatelessWidget {
  final OnlineVisibility current;
  const _OnlinePickerScreen({required this.current});

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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Online', style: AppTextStyles.h1(color: colors.fg1)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: SettingsSection(
            tiles: [
              for (final v in OnlineVisibility.values)
                SettingsRadioTile<OnlineVisibility>(
                  label: v.label,
                  value: v,
                  groupValue: current,
                  onChanged: (chosen) => Navigator.of(context).pop(chosen),
                ),
            ],
        ),
        ),
      ),
    );
  }
}

class _GroupsPickerScreen extends StatelessWidget {
  final GroupsWhoCanAdd current;
  const _GroupsPickerScreen({required this.current});

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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Who can add me to groups',
            style: AppTextStyles.h1(color: colors.fg1)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: SettingsSection(
            tiles: [
              for (final v in GroupsWhoCanAdd.values)
                SettingsRadioTile<GroupsWhoCanAdd>(
                  label: v.label,
                  value: v,
                  groupValue: current,
                  onChanged: (chosen) => Navigator.of(context).pop(chosen),
                ),
            ],
        ),
        ),
      ),
    );
  }
}

class _AutoLockPickerScreen extends StatelessWidget {
  final int current;
  final List<int> options;
  const _AutoLockPickerScreen({required this.current, required this.options});

  String _label(int m) => switch (m) {
        0 => 'Immediately',
        1 => 'After 1 minute',
        5 => 'After 5 minutes',
        30 => 'After 30 minutes',
        _ => 'After $m minutes',
      };

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
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Auto-lock', style: AppTextStyles.h1(color: colors.fg1)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space4),
          child: SettingsSection(
            tiles: [
              for (final m in options)
                SettingsRadioTile<int>(
                  label: _label(m),
                  value: m,
                  groupValue: current,
                  onChanged: (chosen) => Navigator.of(context).pop(chosen),
                ),
            ],
        ),
        ),
      ),
    );
  }
}
