// Replace android/app/google-services.json with the file from Firebase Console
// when enabling push notifications (FCM). A placeholder is committed for builds.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/config/app_config.dart';
import 'core/services/notification_service.dart';

// Must be a top-level function — background isolates cannot capture closures.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint(
    '[FCM background] id=${message.messageId} type=${message.data['type']}',
  );
  // TODO: prompt 15 — wake CallService for incoming call data messages
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!AppConfig.uiOnly) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  final container = ProviderContainer();
  await container.read(notificationServiceProvider).init();

  if (!AppConfig.uiOnly) {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const LuminApp(),
    ),
  );
}
