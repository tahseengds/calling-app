import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_theme.dart';
import 'lumio_icons.dart';

/// Section heading + a rounded card containing one or more setting rows.
///
/// Use any of [SettingsTile], [SettingsSwitchTile], [SettingsRadioTile],
/// or [SettingsDestructiveTile] as children — they all render hairlines
/// between rows consistently.
class SettingsSection extends StatelessWidget {
  final String? title;
  final List<Widget> tiles;

  const SettingsSection({super.key, this.title, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title!.toUpperCase(),
              style: AppTextStyles.captionSemibold(color: colors.fg3)
                  .copyWith(letterSpacing: 0.8),
            ),
          ),
        Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Column(
            children: [
              for (int i = 0; i < tiles.length; i++) ...[
                tiles[i],
                if (i < tiles.length - 1)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: colors.hairline,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Standard navigation row: leading icon, label, optional subtitle, chevron.
class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SettingsTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      leading: Icon(icon, color: colors.fg2, size: 22),
      title: Text(label, style: AppTextStyles.body(color: colors.fg1)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: AppTextStyles.caption(color: colors.fg3))
          : null,
      trailing: trailing ??
          Icon(LumioIcons.chevronRight, color: colors.fg3, size: 20),
      onTap: onTap,
    );
  }
}

/// Toggle row backed by [Switch.adaptive].
class SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      leading: Icon(icon, color: colors.fg2, size: 22),
      title: Text(label, style: AppTextStyles.body(color: colors.fg1)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: AppTextStyles.caption(color: colors.fg3))
          : null,
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.primary,
      ),
      onTap: onChanged == null ? null : () => onChanged!(!value),
    );
  }
}

/// A radio-style row used inside picker screens.
class SettingsRadioTile<T> extends StatelessWidget {
  final String label;
  final String? subtitle;
  final T value;
  final T groupValue;
  final ValueChanged<T>? onChanged;
  final Widget? trailing;

  const SettingsRadioTile({
    super.key,
    required this.label,
    this.subtitle,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final selected = value == groupValue;
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      title: Text(label, style: AppTextStyles.body(color: colors.fg1)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: AppTextStyles.caption(color: colors.fg3))
          : null,
      trailing: trailing ??
          (selected
              ? const Icon(LumioIcons.check, color: AppColors.primary, size: 22)
              : const SizedBox(width: 22)),
      onTap: onChanged == null ? null : () => onChanged!(value),
    );
  }
}

/// Destructive (red) row — e.g. "Log out", "Delete account".
class SettingsDestructiveTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Widget? trailing;

  const SettingsDestructiveTile({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        leading: Icon(icon, color: AppColors.danger),
        title: Text(
          label,
          style: AppTextStyles.bodySemibold(color: AppColors.danger),
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
