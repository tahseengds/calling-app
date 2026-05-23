import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/config/app_colors.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/avatar.dart';
import '../../auth/domain/auth_notifier.dart';
import '../domain/profile_notifier.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileNotifierProvider);

    return profileAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 16),
              const Text('Could not load profile'),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () =>
                    ref.read(profileNotifierProvider.notifier).load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (user) => _ProfileView(user: user),
    );
  }
}

class _ProfileView extends ConsumerStatefulWidget {
  final User user;
  const _ProfileView({required this.user});

  @override
  ConsumerState<_ProfileView> createState() => _ProfileViewState();
}

class _ProfileViewState extends ConsumerState<_ProfileView> {
  bool _isSigningOut = false;

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
    );
    if (image == null || !mounted) return;
    try {
      await ref.read(profileNotifierProvider.notifier).updateAvatar(image.path);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update photo.'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _editName() async {
    final ctrl = TextEditingController(text: widget.user.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit name'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Display name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && mounted) {
      try {
        await ref.read(profileNotifierProvider.notifier).updateName(result);
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to update name.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'You will need to sign in again to use FamilyLink.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Sign out',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _isSigningOut = true);
    try {
      await ref.read(authNotifierProvider.notifier).signOut();
      // GoRouter redirect fires automatically on AuthUnauthenticated.
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = widget.user;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── App bar ──────────────────────────────────────────────────
            SliverAppBar(
              backgroundColor:
                  isDark ? AppColors.darkBg : AppColors.lightBg,
              title: const Text('Profile'),
              pinned: true,
              elevation: 0,
            ),

            // ── Avatar + name ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      // 96 px avatar with camera button overlay
                      Stack(
                        children: [
                          UserAvatar(
                            displayName: user.name,
                            imageUrl: user.avatarUrl,
                            radius: 48,
                          ),
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: GestureDetector(
                              onTap: _pickAvatar,
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark
                                        ? AppColors.darkBg
                                        : AppColors.lightBg,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Name with edit icon
                      GestureDetector(
                        onTap: _editName,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              user.name,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.darkFg1
                                    : AppColors.lightFg1,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color:
                                  isDark ? AppColors.darkFg3 : AppColors.lightFg2,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.phone,
                        style: TextStyle(
                          fontSize: 15,
                          color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── "Reliable calls" battery card ────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _ReliableCallsCard(),
              ),
            ),

            // ── Settings sections ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Column(
                  children: [
                    _SettingsSection(
                      title: 'Account',
                      tiles: [
                        _SettingsTile(
                          icon: Icons.notifications_outlined,
                          label: 'Notifications',
                          onTap: () {
                            // TODO prompt 15 — notification settings
                          },
                        ),
                        _SettingsTile(
                          icon: Icons.lock_outlined,
                          label: 'Privacy & security',
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SettingsSection(
                      title: 'Support',
                      tiles: [
                        _SettingsTile(
                          icon: Icons.help_outline,
                          label: 'Help & feedback',
                          onTap: () {},
                        ),
                        _SettingsTile(
                          icon: Icons.info_outline,
                          label: 'About FamilyLink',
                          onTap: () {},
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Logout ────────────────────────────────────────────
                    Material(
                      color: isDark
                          ? AppColors.darkSurface
                          : AppColors.lightSurface,
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        leading: const Icon(
                          Icons.logout,
                          color: AppColors.danger,
                        ),
                        title: const Text(
                          'Sign out',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: _isSigningOut ? null : _signOut,
                        trailing: _isSigningOut
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.danger,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reliable calls card ───────────────────────────────────────────────────────

class _ReliableCallsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withAlpha(30),
            AppColors.primary.withAlpha(15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withAlpha(60)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withAlpha(40),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.battery_charging_full,
              color: AppColors.primary,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Reliable calls',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Disable battery optimisation so calls always connect.',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              // TODO prompt 15 — open battery optimization settings intent
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: const Text(
              'Fix',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Settings section ──────────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<_SettingsTile> tiles;

  const _SettingsSection({required this.title, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: isDark ? AppColors.darkFg3 : AppColors.lightFg2,
            ),
          ),
        ),
        Material(
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              for (int i = 0; i < tiles.length; i++) ...[
                tiles[i],
                if (i < tiles.length - 1)
                  Divider(
                    height: 1,
                    indent: 56,
                    color: isDark ? AppColors.darkHairline : AppColors.lightHairline,
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return ListTile(
      shape: shape,
      leading: Icon(
        icon,
        color: isDark ? AppColors.darkFg2 : AppColors.lightFg2,
        size: 22,
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          color: isDark ? AppColors.darkFg1 : AppColors.lightFg1,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: isDark ? AppColors.darkFg3 : AppColors.lightFg2,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}
