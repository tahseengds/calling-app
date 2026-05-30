import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/models/user.dart';
import '../../../shared/widgets/avatar.dart';
import '../../../shared/widgets/error_snackbar.dart';
import '../../../shared/widgets/lumio_icons.dart';
import '../../../shared/widgets/settings_tile.dart';
import 'package:go_router/go_router.dart';
import '../../auth/domain/auth_notifier.dart';
import '../data/profile_repository.dart';
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
              const Icon(LucideIcons.circleAlert, size: 48),
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
  bool _isDeletingAccount = false;
  bool _uploadingAvatar = false;
  String? _versionLabel;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _versionLabel = 'Version ${info.version} (${info.buildNumber})');
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionLabel = 'Version 1.0.0');
    }
  }

  Future<void> _pickAvatar() async {
    if (_uploadingAvatar) return;

    // Step 1: pick from gallery (no pre-scaling — let the cropper handle it)
    final image = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (image == null || !mounted) return;

    // Step 2: interactive crop — 1:1 square, circle overlay
    final cropped = await ImageCropper().cropImage(
      sourcePath: image.path,
      maxWidth: 512,
      maxHeight: 512,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 85,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop photo',
          toolbarColor: AppColors.primary,
          toolbarWidgetColor: Colors.white,
          cropStyle: CropStyle.circle,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          showCropGrid: false,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Crop photo',
          cropStyle: CropStyle.circle,
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
      ],
    );
    if (cropped == null || !mounted) return;

    setState(() => _uploadingAvatar = true);
    try {
      // Step 3: safety-net — image_cropper at 512×512/q85 is normally
      // 30–120 KB, but if somehow the file is still > 900 KB, compress further.
      String uploadPath = cropped.path;
      if (await File(cropped.path).length() > 900 * 1024) {
        final dir = await getTemporaryDirectory();
        final target = '${dir.path}/avatar_upload.jpg';
        final compressed = await FlutterImageCompress.compressAndGetFile(
          cropped.path,
          target,
          minWidth: 512,
          minHeight: 512,
          quality: 60,
          format: CompressFormat.jpeg,
        );
        if (compressed != null) uploadPath = compressed.path;
      }

      await ref.read(profileNotifierProvider.notifier).updateAvatar(uploadPath);
      if (mounted) {
        showSuccessSnackbar(context, 'Photo updated!');
      }
    } catch (_) {
      if (!mounted) return;
      showErrorSnackbar(context, 'Failed to update photo.');
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  void _editName() {
    context.push('/profile/edit-name');
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
            'You will need to sign in again to use Lumio.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Log out',
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

  Future<void> _resetPassword() async {
    final email = widget.user.email;
    if (email == null || email.isEmpty) {
      showErrorSnackbar(context, 'No email on file to reset a password.');
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset password?'),
        content: Text(
          "We'll email a password-reset link to $email. "
          'If you sign in with Google, your account has no password to reset.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send link'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await ref.read(authNotifierProvider.notifier).sendPasswordResetEmail();
      ref.read(analyticsServiceProvider).passwordResetRequested();
      if (mounted) {
        showSuccessSnackbar(context, 'Password reset link sent to $email');
      }
    } catch (_) {
      if (!mounted) return;
      showErrorSnackbar(
        context,
        "Couldn't send a reset link. Google sign-in accounts have no password.",
      );
    }
  }

  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account and removes your personal '
          'data. You will be signed out on all devices. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _isDeletingAccount = true);
    try {
      await ref.read(profileRepositoryProvider).deleteAccount();
      ref.read(analyticsServiceProvider).accountDeleted();
      // Local teardown — server already revoked every session. The GoRouter
      // redirect fires automatically on AuthUnauthenticated.
      await ref.read(authNotifierProvider.notifier).handleAccountDeleted();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isDeletingAccount = false);
      showErrorSnackbar(
        context,
        "Couldn't delete your account. Check your connection and try again.",
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.lumioColors;
    final user = widget.user;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(profileNotifierProvider.notifier).load(),
          child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── App bar ──────────────────────────────────────────────────
            SliverAppBar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              pinned: true,
              elevation: 0,
              toolbarHeight: 64,
              title: Text(
                'Profile',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  color: colors.fg1,
                ),
              ),
            ),

            // ── Avatar + name ────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      // 96 px avatar with camera button overlay.
                      // clipBehavior: none so the camera button (offset -6,-6)
                      // and its ring aren't truncated at the Stack's bounds.
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          UserAvatar(
                            displayName: user.name,
                            imageUrl: user.avatarUrl,
                            radius: 48,
                          ),
                          if (_uploadingAvatar)
                            Positioned.fill(
                              child: Container(
                                decoration: const BoxDecoration(
                                  color: Colors.black38,
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            right: -6,
                            bottom: -6,
                            child: Material(
                              color: AppColors.primary,
                              shape: const CircleBorder(),
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: _pickAvatar,
                                child: Semantics(
                                  button: true,
                                  label: 'Change profile photo',
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Theme.of(context)
                                            .scaffoldBackgroundColor,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Icon(
                                      LumioIcons.camera,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Display name only — editing lives in Account › Edit name.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          user.name,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: colors.fg1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email ?? '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          color: colors.fg2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Settings sections ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
                child: Column(
                  children: [
                    SettingsSection(
                      title: 'Account',
                      tiles: [
                        SettingsTile(
                          icon: LumioIcons.edit,
                          label: 'Edit name',
                          onTap: _editName,
                        ),
                        SettingsTile(
                          icon: LumioIcons.shield,
                          label: 'Privacy',
                          onTap: () => context.push('/profile/privacy'),
                        ),
                        SettingsTile(
                          icon: LumioIcons.lock,
                          label: 'Reset password',
                          onTap: _resetPassword,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SettingsSection(
                      title: 'Notifications',
                      tiles: [
                        SettingsTile(
                          icon: LumioIcons.bell,
                          label: 'Notification settings',
                          onTap: () => context.push('/profile/notifications'),
                        ),
                        SettingsTile(
                          icon: LumioIcons.message,
                          label: 'Message sounds',
                          onTap: () => context.push('/profile/sounds'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SettingsSection(
                      title: 'Help',
                      tiles: [
                        SettingsTile(
                          icon: LumioIcons.help,
                          label: 'Help & support',
                          onTap: () => context.push('/profile/help'),
                        ),
                        SettingsTile(
                          icon: LumioIcons.info,
                          label: 'About Lumio',
                          subtitle: _versionLabel,
                          onTap: () => context.push('/profile/about'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Logout ────────────────────────────────────────────
                    SettingsDestructiveTile(
                      icon: LumioIcons.logout,
                      label: 'Log out',
                      onTap: (_isSigningOut || _isDeletingAccount)
                          ? null
                          : _signOut,
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
                    const SizedBox(height: 12),

                    // ── Delete account ────────────────────────────────────
                    SettingsDestructiveTile(
                      icon: LumioIcons.trash,
                      label: 'Delete account',
                      onTap: (_isSigningOut || _isDeletingAccount)
                          ? null
                          : _deleteAccount,
                      trailing: _isDeletingAccount
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
                    const SizedBox(height: 32),
                  ],
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
