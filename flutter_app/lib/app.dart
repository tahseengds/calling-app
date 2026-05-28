import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/services/deep_link_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/domain/auth_notifier.dart';
import 'features/auth/domain/auth_state.dart';
import 'features/auth/ui/email_verify_pending_screen.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/auth/ui/register_screen.dart';
import 'features/auth/ui/splash_screen.dart';
import 'features/contacts/ui/add_contact_screen.dart';
import 'features/contacts/ui/contacts_screen.dart';
import 'features/shell/ui/shell_screen.dart';
// Chat screens — all live under features/chat/ now (the old features/chats/
// split was removed). ChatRichScreen is the polished UI wired to chat_notifier.
import 'features/chat/presentation/chat_rich_screen.dart';
import 'features/chat/presentation/media_viewer_screen.dart';
import 'features/chat/presentation/search_screen.dart';
// New calling screens (Prompt 14)
import 'features/calling/presentation/incoming_call_screen.dart';
import 'features/calling/presentation/outgoing_call_screen.dart';
import 'features/calling/presentation/active_call_screen.dart';
import 'features/calling/presentation/video_call_screen.dart';
import 'features/calling/presentation/call_history_screen.dart';
import 'features/calling/domain/call_notifier.dart';
import 'features/calling/domain/call_state.dart';
// App lock gate
import 'features/settings/ui/app_lock_gate.dart';
// Profile screens
import 'features/profile/presentation/screens/about_screen.dart';
import 'features/profile/presentation/screens/blocked_contacts_screen.dart';
import 'features/profile/presentation/screens/edit_name_screen.dart';
import 'features/profile/presentation/screens/help_support_screen.dart';
import 'features/profile/presentation/screens/message_sounds_screen.dart';
import 'features/profile/presentation/screens/notification_settings_screen.dart';
import 'features/profile/presentation/screens/privacy_screen.dart';
import 'core/services/pending_deep_link.dart';

// ── Router ────────────────────────────────────────────────────────────────────

final _routerRefreshProvider = Provider<GoRouterRefreshNotifier>((ref) {
  final notifier = GoRouterRefreshNotifier();
  ref.listen(authNotifierProvider, (_, _) => notifier.notify());
  ref.onDispose(notifier.dispose);
  return notifier;
});

class GoRouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

final _routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_routerRefreshProvider);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final authState = ref.read(authNotifierProvider);

      return switch (authState) {
        AuthUnknown() => loc == '/splash' ? null : '/splash',
        AuthUnauthenticated() => switch (loc) {
            '/login' || '/register' => null,
            _ => '/login',
          },
        AuthEmailVerificationPending() =>
          loc == '/verify-email' ? null : '/verify-email',
        AuthAuthenticated() => switch (loc) {
            '/login' ||
            '/register' ||
            '/verify-email' ||
            '/splash' =>
              '/home',
            _ => null,
          },
      };
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
          path: '/verify-email',
          builder: (_, _) => const EmailVerifyPendingScreen()),
      // ── Authenticated shell ───────────────────────────────────────────────
      GoRoute(path: '/home', builder: (_, _) => const ShellScreen()),
      // Contacts is no longer a bottom-nav tab; it's a pushed page reached
      // via the "new chat" FAB on the chats home screen.
      GoRoute(
          path: '/contacts',
          builder: (_, _) => const ContactsScreen()),
      GoRoute(
          path: '/contacts/add',
          builder: (_, _) => const AddContactScreen()),
      // ── Search ───────────────────────────────────────────────────────────
      GoRoute(
          path: '/chat/search',
          builder: (_, _) => const SearchScreen()),
      // ── Chat ─────────────────────────────────────────────────────────────
      GoRoute(
        path: '/chat/:conversationId',
        builder: (_, state) => ChatRichScreen(
          conversationId:
              state.pathParameters['conversationId'] ?? '',
          contactName: state.uri.queryParameters['name'],
        ),
      ),
      // ── Media viewer ──────────────────────────────────────────────────────
      GoRoute(
        path: '/media',
        builder: (_, state) {
          final kind = state.uri.queryParameters['kind'] ?? 'image';
          final url = state.uri.queryParameters['url'] ?? '';
          return MediaViewerScreen(
            url: url,
            kind: kind,
            sender: state.uri.queryParameters['sender'],
            when: state.uri.queryParameters['when'],
          );
        },
      ),
      // ── Calling (Prompt 14) ───────────────────────────────────────────────
      GoRoute(
          path: '/call/incoming',
          builder: (_, _) => const IncomingCallScreen()),
      GoRoute(
          path: '/call/outgoing',
          builder: (_, _) => const OutgoingCallScreen()),
      GoRoute(
          path: '/call/active',
          builder: (_, _) => const ActiveCallScreen()),
      GoRoute(
          path: '/call/video',
          builder: (_, _) => const VideoCallScreen()),
      GoRoute(
          path: '/call/history',
          builder: (_, _) => const CallHistoryScreen()),
      // ── Profile ───────────────────────────────────────────────────────────
      GoRoute(
          path: '/profile/edit-name',
          builder: (_, _) => const EditNameScreen()),
      GoRoute(
          path: '/profile/notifications',
          builder: (_, _) => const NotificationSettingsScreen()),
      GoRoute(
          path: '/profile/sounds',
          builder: (_, _) => const MessageSoundsScreen()),
      GoRoute(
          path: '/profile/privacy',
          builder: (_, _) => const PrivacyScreen()),
      GoRoute(
          path: '/profile/privacy/blocked',
          builder: (_, _) => const BlockedContactsScreen()),
      GoRoute(
          path: '/profile/help',
          builder: (_, _) => const HelpSupportScreen()),
      GoRoute(
          path: '/profile/about',
          builder: (_, _) => const AboutScreen()),
    ],
  );
});

// ── App root ──────────────────────────────────────────────────────────────────

class LuminApp extends ConsumerStatefulWidget {
  final VoidCallback? onResume;
  const LuminApp({super.key, this.onResume});

  @override
  ConsumerState<LuminApp> createState() => _LuminAppState();
}

class _LuminAppState extends ConsumerState<LuminApp>
    with WidgetsBindingObserver {
  StreamSubscription<Uri>? _appLinksSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeConsumeDeepLink();
      _bootstrapDeepLinks();
    });
  }

  /// Push a pending deep-link only after the auth state has resolved to
  /// authenticated — otherwise the GoRouter redirect overrides any push to
  /// /chat/... with /splash (during AuthUnknown) or /login (after a transient
  /// network failure), and the FCM notification tap silently lands the user on
  /// the wrong screen.
  void _maybeConsumeDeepLink() {
    if (!mounted) return;
    final pending = ref.read(pendingDeepLinkProvider);
    if (pending == null) return;
    final auth = ref.read(authNotifierProvider);
    if (auth is AuthAuthenticated) {
      final path = ref.read(pendingDeepLinkProvider.notifier).consume();
      if (path != null) {
        ref.read(_routerProvider).push(path);
      }
    }
    // else: wait — the ref.listen in build() will fire when auth resolves.
  }

  /// Cold-start link consumption + runtime listener. Routes verification
  /// links to [AuthNotifier.handleVerificationDeepLink]; on success the
  /// auth state flips to [AuthAuthenticated] and the GoRouter redirect
  /// auto-advances to `/home`. We don't navigate manually here.
  void _bootstrapDeepLinks() {
    final service = ref.read(deepLinkServiceProvider);

    // Cold start.
    service.getInitialLink().then((uri) {
      if (uri != null) _handleAppLink(uri);
    });

    // Foreground / background hand-off.
    _appLinksSub?.cancel();
    _appLinksSub = service.uriStream.listen(_handleAppLink);
  }

  Future<void> _handleAppLink(Uri uri) async {
    // Email verification — fall through silently if the URI is for anything
    // else (the auth-notifier method checks the shape and returns false).
    try {
      final ok = await ref
          .read(authNotifierProvider.notifier)
          .handleVerificationDeepLink(uri);
      if (!ok && mounted) {
        // We were on /verify-email and the link didn't apply — give the
        // user a hint instead of leaving them wondering.
        final messenger = _rootMessenger;
        if (messenger != null &&
            ref.read(authNotifierProvider) is AuthEmailVerificationPending) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                  'Verification link is invalid or has expired. Tap Resend to get a fresh one.'),
            ),
          );
        }
      }
    } catch (e, st) {
      debugPrint('[deep-link] verification handler threw: $e\n$st');
    }
  }

  ScaffoldMessengerState? get _rootMessenger {
    // ScaffoldMessenger lives below MaterialApp.router; reach it via the
    // builder context. Tolerant of times when no route is mounted yet.
    final ctx = _routerNavigatorKey?.currentContext;
    if (ctx == null) return null;
    return ScaffoldMessenger.maybeOf(ctx);
  }

  GlobalKey<NavigatorState>? get _routerNavigatorKey =>
      ref.read(_routerProvider).routerDelegate.navigatorKey;

  @override
  void dispose() {
    _appLinksSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.onResume?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(_routerProvider);

    // ── Pending deep-link, post-auth ─────────────────────────────────────────
    // FCM notification tap stashes the path in pendingDeepLinkProvider before
    // the auth state has had a chance to restore. The router's redirect runs
    // synchronously off the auth state, so a push during AuthUnknown gets
    // rewritten to /splash. Watch for the transition to AuthAuthenticated and
    // push the saved path then.
    ref.listen<AuthState>(authNotifierProvider, (prev, next) {
      if (next is AuthAuthenticated) {
        final path =
            ref.read(pendingDeepLinkProvider.notifier).consume();
        if (path != null) {
          router.push(path);
        }
      }
    });

    // ── Call navigation observer ─────────────────────────────────────────────
    // When a call arrives or phase changes, navigate to the right screen.
    ref.listen<CallSession?>(callSessionProvider, (prev, next) {
      if (!context.mounted) {
        return;
      }
      if (next == null) {
        return;
      }

      // New incoming call
      if (next.phase == CallPhase.incomingRinging &&
          (prev == null ||
              prev.callId != next.callId ||
              prev.phase != CallPhase.incomingRinging)) {
        router.push('/call/incoming');
        return;
      }

      // New outgoing call started (e.g. from call history)
      if (next.phase == CallPhase.outgoingRinging &&
          (prev == null || prev.callId != next.callId)) {
        router.push('/call/outgoing');
      }
    });

    return MaterialApp.router(
      title: 'Lumio',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // ── Status-bar contrast ──────────────────────────────────────────────
      // Without this, edge-to-edge Android paints the status bar opaque black
      // by default — invisible in light mode. Read the resolved brightness
      // here (inside Theme scope) and pin matching system-UI icon colors.
      builder: (context, child) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final overlay = SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor:
              isDark ? const Color(0xFF0B0F1A) : Colors.white,
          systemNavigationBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
          systemNavigationBarDividerColor: Colors.transparent,
        );
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: overlay,
          // Wrap every route in the App Lock gate so a locked app can't be
          // bypassed by deep-linking past the home screen.
          child: AppLockGate(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}
