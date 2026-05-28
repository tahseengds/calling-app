import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/avatar.dart';
import '../../../../shared/widgets/lumio_icons.dart';
import '../../../contacts/data/contact_repository.dart';

class BlockedContactsScreen extends ConsumerStatefulWidget {
  const BlockedContactsScreen({super.key});

  @override
  ConsumerState<BlockedContactsScreen> createState() =>
      _BlockedContactsScreenState();
}

class _BlockedContactsScreenState extends ConsumerState<BlockedContactsScreen> {
  late Future<List<BlockedContactEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<BlockedContactEntry>> _load() async {
    return ref.read(contactRepositoryProvider).getBlocked();
  }

  Future<void> _unblock(BlockedContactEntry entry) async {
    final repo = ref.read(contactRepositoryProvider);
    try {
      await repo.setBlocked(contactId: entry.contactId, blocked: false);
      if (!mounted) return;
      setState(() => _future = _load());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unblocked ${entry.user.name}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not unblock contact.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
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
        title:
            Text('Blocked contacts', style: AppTextStyles.h1(color: colors.fg1)),
      ),
      body: SafeArea(
        child: FutureBuilder<List<BlockedContactEntry>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              );
            }
            if (snap.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LumioIcons.warning, color: colors.fg2, size: 36),
                    const SizedBox(height: 8),
                    Text('Could not load blocked contacts',
                        style: AppTextStyles.body(color: colors.fg2)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () =>
                          setState(() => _future = _load()),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            final entries = snap.data ?? const [];
            if (entries.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.space6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(LumioIcons.block,
                          color: colors.fg3, size: 48),
                      const SizedBox(height: 12),
                      Text(
                        'No blocked contacts',
                        style: AppTextStyles.body(color: colors.fg2),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Blocked contacts can\'t call you or send you messages.',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.caption(color: colors.fg3),
                      ),
                    ],
                  ),
                ),
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.space2,
              ),
              itemCount: entries.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, indent: 72, color: colors.hairline),
              itemBuilder: (_, i) {
                final entry = entries[i];
                return ListTile(
                  leading: UserAvatar(
                    displayName: entry.user.name,
                    imageUrl: entry.user.avatarUrl,
                    radius: 22,
                  ),
                  title: Text(entry.user.name,
                      style: AppTextStyles.body(color: colors.fg1)),
                  subtitle: Text(entry.user.email ?? '',
                      style: AppTextStyles.caption(color: colors.fg3)),
                  trailing: TextButton(
                    onPressed: () => _unblock(entry),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                    ),
                    child: const Text('Unblock'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
