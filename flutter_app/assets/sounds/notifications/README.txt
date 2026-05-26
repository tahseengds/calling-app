Notification sound assets
=========================

Drop short MP3 or OGG clips (1–2 seconds) here. They are surfaced in the
Message Sounds screen (lib/features/profile/presentation/screens/
message_sounds_screen.dart) via the kBundledNotificationSounds list in
lib/features/settings/domain/models/notification_preferences.dart.

Expected file names (the screen falls back gracefully if any are missing):

  chime.mp3
  pop.mp3
  ding.mp3
  note.mp3
  bubble.mp3
  pulse.mp3

To add or rename sounds: update kBundledNotificationSounds AND drop the
matching file in this directory. Anything in this folder is bundled into
the APK via the pubspec.yaml flutter.assets declaration.
