import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/lumio_icons.dart';
import '../../../../shared/widgets/settings_tile.dart';
import '../../../settings/domain/models/notification_preferences.dart';
import '../../../settings/domain/notification_settings_notifier.dart';
import 'message_sounds_screen.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.lumioColors;
    final isDark = context.isDarkMode;
    final async = ref.watch(notificationSettingsProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(LumioIcons.back, color: colors.fg1),
          onPressed: () => context.pop(),
        ),
        title: Text('Notifications', style: AppTextStyles.h1(color: colors.fg1)),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
          error: (e, _) => _ErrorRetry(
            onRetry: () =>
                ref.read(notificationSettingsProvider.notifier).load(),
          ),
          data: (prefs) => _Body(prefs: prefs),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final NotificationPreferences prefs;
  const _Body({required this.prefs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(notificationSettingsProvider.notifier);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.space4),
      child: Column(
        children: [
          SettingsSection(
            title: 'Conversations',
            tiles: [
              SettingsSwitchTile(
                icon: LumioIcons.message,
                label: 'Messages',
                subtitle: 'New direct messages',
                value: prefs.messagesEnabled,
                onChanged: notifier.setMessagesEnabled,
              ),
              SettingsSwitchTile(
                icon: LumioIcons.groups,
                label: 'Group messages',
                value: prefs.groupMessagesEnabled,
                onChanged: notifier.setGroupMessagesEnabled,
              ),
              SettingsSwitchTile(
                icon: LumioIcons.reactions,
                label: 'Reactions',
                value: prefs.reactionNotifications,
                onChanged: notifier.setReactionNotifications,
              ),
              SettingsSwitchTile(
                icon: LumioIcons.mention,
                label: 'Mentions',
                value: prefs.mentionNotifications,
                onChanged: notifier.setMentionNotifications,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Calls',
            tiles: [
              SettingsSwitchTile(
                icon: LumioIcons.phone,
                label: 'Call notifications',
                value: prefs.callsEnabled,
                onChanged: notifier.setCallsEnabled,
              ),
              SettingsSwitchTile(
                icon: LumioIcons.bell,
                label: 'High-priority notifications',
                subtitle: 'Show on top of the screen as banners',
                value: prefs.highPriorityNotifications,
                onChanged: notifier.setHighPriority,
              ),
              SettingsTile(
                icon: LumioIcons.musicNote,
                label: 'Call ringtone',
                subtitle: labelForSoundId(prefs.callRingtone),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MessageSoundsScreen(
                      kind: SoundKind.call,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Sound & vibration',
            tiles: [
              SettingsTile(
                icon: LumioIcons.volume,
                label: 'Message sound',
                subtitle: labelForSoundId(prefs.messageSound),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const MessageSoundsScreen(
                      kind: SoundKind.message,
                    ),
                  ),
                ),
              ),
              SettingsSwitchTile(
                icon: LumioIcons.vibration,
                label: 'Vibrate',
                value: prefs.vibrate,
                onChanged: notifier.setVibrate,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Display',
            tiles: [
              SettingsSwitchTile(
                icon: LumioIcons.eye,
                label: 'Show preview on lock screen',
                subtitle: prefs.showPreview
                    ? 'Message content is shown in notifications'
                    : 'Only sender name is shown',
                value: prefs.showPreview,
                onChanged: notifier.setShowPreview,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'Quiet hours',
            tiles: [
              SettingsSwitchTile(
                icon: LumioIcons.moon,
                label: 'Enable quiet hours',
                subtitle: 'Silence notifications during selected hours',
                value: prefs.quietHoursEnabled,
                onChanged: notifier.setQuietHoursEnabled,
              ),
              if (prefs.quietHoursEnabled) ...[
                _TimeTile(
                  label: 'Start',
                  value: prefs.quietHoursStart,
                  onPick: notifier.setQuietHoursStart,
                ),
                _TimeTile(
                  label: 'End',
                  value: prefs.quietHoursEnd,
                  onPick: notifier.setQuietHoursEnd,
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          SettingsSection(
            title: 'System',
            tiles: [
              SettingsTile(
                icon: LumioIcons.settings,
                label: 'Open system notification settings',
                subtitle: 'Fix OS-level notification blocks',
                onTap: () async {
                  await openAppSettings();
                },
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String label;
  final String value; // HH:MM
  final ValueChanged<String> onPick;

  const _TimeTile({
    required this.label,
    required this.value,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    return ListTile(
      leading: Icon(LumioIcons.clock, color: colors.fg2, size: 22),
      title: Text(label, style: AppTextStyles.body(color: colors.fg1)),
      trailing: Text(
        value,
        style: AppTextStyles.bodySemibold(color: AppColors.primary),
      ),
      onTap: () async {
        final parts = value.split(':');
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(
            hour: int.tryParse(parts[0]) ?? 22,
            minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
          ),
        );
        if (picked == null) return;
        final hh = picked.hour.toString().padLeft(2, '0');
        final mm = picked.minute.toString().padLeft(2, '0');
        onPick('$hh:$mm');
      },
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorRetry({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LumioIcons.warning, color: colors.fg2, size: 40),
          const SizedBox(height: 12),
          Text(
            'Could not load notification settings',
            style: AppTextStyles.body(color: colors.fg2),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
