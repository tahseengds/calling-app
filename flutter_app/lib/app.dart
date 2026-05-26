import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/config/app_config.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/domain/auth_notifier.dart';
import 'features/auth/domain/auth_state.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/auth/ui/otp_screen.dart';
import 'features/auth/ui/register_screen.dart';
import 'features/auth/ui/splash_screen.dart';
import 'features/contacts/ui/add_contact_screen.dart';
import 'features/shell/ui/shell_screen.dart';
// Chat screens
import 'features/chat/presentation/chat_screen.dart';
import 'features/chat/presentation/media_viewer_screen.dart';
// Search (legacy mock)
import 'features/chats/presentation/screens/search_screen.dart';
// New calling screens (Prompt 14)
import 'features/calling/presentation/incoming_call_screen.dart';
import 'features/calling/presentation/outgoing_call_screen.dart';
import 'features/calling/presentation/active_call_screen.dart';
import 'features/calling/presentation/video_call_screen.dart';
import 'features/calling/presentation/call_history_screen.dart';
import 'features/calling/domain/call_notifier.dart';
import 'features/calling/domain/call_state.dart';
// Profile screens
import 'features/profile/presentation/screens/change_number_screen.dart';
import 'features/profile/presentation/screens/edit_name_screen.dart';
import 'main.dart';

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
    initialLocation: AppConfig.uiOnly ? '/home' : '/splash',
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
        AuthOtpPending() => loc == '/otp' ? null : '/otp',
        AuthAuthenticated() => switch (loc) {
            '/login' || '/register' || '/otp' || '/splash' => '/home',
            _ => null,
          },
      };
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(path: '/otp', builder: (_, _) => const OtpScreen()),
      // ── Authenticated shell ───────────────────────────────────────────────
      GoRoute(path: '/home', builder: (_, _) => const ShellScreen()),
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
        builder: (_, state) => ChatScreen(
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
          path: '/profile/change-number',
          builder: (_, _) => const ChangeNumberScreen()),
      GoRoute(
          path: '/profile/edit-name',
          builder: (_, _) => const EditNameScreen()),
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final path =
          ref.read(pendingDeepLinkProvider.notifier).consume();
      if (path != null) {
        ref.read(_routerProvider).push(path);
      }
    });
  }

  @override
  void dispose() {
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
    );
  }
}
