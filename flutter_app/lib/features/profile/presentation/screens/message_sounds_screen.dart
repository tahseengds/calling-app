import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/lumio_icons.dart';
import '../../../../shared/widgets/settings_tile.dart';
import '../../../settings/domain/models/notification_preferences.dart';
import '../../../settings/domain/notification_settings_notifier.dart';

enum SoundKind { message, call }

class MessageSoundsScreen extends ConsumerStatefulWidget {
  final SoundKind kind;
  const MessageSoundsScreen({super.key, this.kind = SoundKind.message});

  @override
  ConsumerState<MessageSoundsScreen> createState() =>
      _MessageSoundsScreenState();
}

class _MessageSoundsScreenState extends ConsumerState<MessageSoundsScreen> {
  final AudioPlayer _player = AudioPlayer();
  bool _playerReady = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    // Tell the OS this is media playback (not a silent voip prompt) so the
    // device routes it to the loudspeaker and respects the media volume slider.
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setVolume(1.0);
      await _player.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            isSpeakerphoneOn: true,
            stayAwake: false,
            contentType: AndroidContentType.sonification,
            usageType: AndroidUsageType.notification,
            audioFocus: AndroidAudioFocus.gainTransientMayDuck,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.ambient,
            options: const {AVAudioSessionOptions.mixWithOthers},
          ),
        ),
      );
      _playerReady = true;
    } catch (_) {
      // Keep _playerReady=false — preview will report the error visibly.
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _titleFor(SoundKind kind) => kind == SoundKind.call
      ? 'Call ringtone'
      : 'Message sound';

  String _currentSoundId(NotificationPreferences prefs) =>
      widget.kind == SoundKind.call ? prefs.callRingtone : prefs.messageSound;

  Future<void> _select(String id, NotificationSound? sound) async {
    final notifier = ref.read(notificationSettingsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    // 1) Persist the selection first so a preview failure doesn't lose the pick.
    try {
      if (widget.kind == SoundKind.call) {
        await notifier.setCallRingtone(id);
      } else {
        await notifier.setMessageSound(id);
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Could not save sound.'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    // 2) Preview.
    if (id == kNoneSoundId) {
      // Nothing to play.
      return;
    }
    if (sound?.assetPath == null) {
      // "System default" — play the OS notification beep so the user gets
      // audible confirmation.
      try {
        await SystemSound.play(SystemSoundType.alert);
      } catch (_) {}
      return;
    }
    if (!_playerReady) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
              'Audio player not ready. Try once more or check device volume.'),
        ),
      );
      return;
    }
    try {
      await _player.stop();
      await _player.play(AssetSource(sound!.assetPath!));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not play preview: ${_shortError(e)}'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  String _shortError(Object e) {
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 77)}…' : s;
  }

  @override
  Widget build(BuildContext context) {
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
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Text(_titleFor(widget.kind),
            style: AppTextStyles.h1(color: colors.fg1)),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
        ),
          error: (_, _) => Center(
            child: Text('Could not load sounds',
                style: AppTextStyles.body(color: colors.fg2)),
          ),
          data: (prefs) {
            final selected = _currentSoundId(prefs);
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.space4),
              child: Column(
                children: [
                  SettingsSection(
                    tiles: [
                      SettingsRadioTile<String>(
                        label: 'System default',
                        subtitle: 'Use the OS-wide notification sound',
                        value: kSystemDefaultSoundId,
                        groupValue: selected,
                        onChanged: (v) => _select(v, null),
                      ),
                      SettingsRadioTile<String>(
                        label: 'None',
                        subtitle: 'Silent',
                        value: kNoneSoundId,
                        groupValue: selected,
                        onChanged: (v) => _select(v, null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SettingsSection(
                    title: 'Bundled',
                    tiles: [
                      for (final sound in kBundledNotificationSounds)
                        SettingsRadioTile<String>(
                          label: sound.label,
                          value: sound.id,
                          groupValue: selected,
                          onChanged: (v) => _select(v, sound),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      'Tap a sound to preview and select it.',
                      style: AppTextStyles.caption(color: colors.fg3),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
