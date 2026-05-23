// IMPORTANT: Add your google-services.json from the Firebase console to
// android/app/google-services.json before building. A placeholder file exists
// at that path — replace it with the real file to enable Firebase.

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
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

  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Android 13+ requires runtime notification permission.
  await FirebaseMessaging.instance.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  final container = ProviderContainer();
  await container.read(notificationServiceProvider).init();

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const FamilyLinkApp(),
    ),
  );
}
