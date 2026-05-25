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
// New real chat screens (prompt 13).
import 'features/chat/presentation/chat_screen.dart';
import 'features/chat/presentation/media_viewer_screen.dart';
// Legacy mock screens — kept for backwards compat during transition.
import 'features/chats/presentation/screens/search_screen.dart';
import 'features/calls/presentation/screens/incoming_call_screen.dart';
import 'features/calls/presentation/screens/outgoing_call_screen.dart';
import 'features/calls/presentation/screens/active_call_screen.dart';
import 'features/profile/presentation/screens/change_number_screen.dart';
import 'features/profile/presentation/screens/edit_name_screen.dart';
import 'main.dart';

// ── Router ────────────────────────────────────────────────────────────────────

final _routerRefreshProvider = Provider<GoRouterRefreshNotifier>((ref) {
  final notifier = GoRouterRefreshNotifier();
  ref.listen(authNotifierProvider, (_, next) => notifier.notify());
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
      // ── Authenticated shell ─────────────────────────────────────────────
      GoRoute(path: '/home', builder: (_, _) => const ShellScreen()),
      GoRoute(
          path: '/contacts/add',
          builder: (_, _) => const AddContactScreen()),
      // ── Chat search (legacy mock, replaced in prompt 14) ────────────────
      GoRoute(
          path: '/chat/search', builder: (_, _) => const SearchScreen()),
      // ── Chat — uses new real ChatScreen ─────────────────────────────────
      GoRoute(
        path: '/chat/:conversationId',
        builder: (_, state) => ChatScreen(
          conversationId: state.pathParameters['conversationId'] ?? '',
          contactName: state.uri.queryParameters['name'],
        ),
      ),
      // ── Media viewer — new full-screen viewer with photo_view / video ────
      GoRoute(
        path: '/media',
        builder: (_, state) {
          final kind = state.uri.queryParameters['kind'] ?? 'image';
          final url = state.uri.queryParameters['url'];
          if (url != null && (kind == 'image' || kind == 'video')) {
            return MediaViewerScreen(
              url: url,
              kind: kind,
              sender: state.uri.queryParameters['sender'],
              when: state.uri.queryParameters['when'],
            );
          }
          // Fallback to legacy placeholder for document / audio.
          return MediaViewerScreen(
            url: url ?? '',
            kind: kind,
            sender: state.uri.queryParameters['sender'],
            when: state.uri.queryParameters['when'],
          );
        },
      ),
      // ── Calls ────────────────────────────────────────────────────────────
      GoRoute(
        path: '/call/incoming',
        builder: (_, state) => IncomingCallScreen(
          name: state.uri.queryParameters['name'] ?? 'Family',
          kind: state.uri.queryParameters['kind'] ?? 'video',
        ),
      ),
      GoRoute(
        path: '/call/outgoing',
        builder: (_, state) => OutgoingCallScreen(
          name: state.uri.queryParameters['name'] ?? 'Family',
          kind: state.uri.queryParameters['kind'] ?? 'video',
        ),
      ),
      GoRoute(
        path: '/call/active',
        builder: (_, state) => ActiveCallScreen(
          name: state.uri.queryParameters['name'] ?? 'Family',
          kind: state.uri.queryParameters['kind'] ?? 'video',
        ),
      ),
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
    // Consume any pending deep-link from FCM cold-start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final path = ref.read(pendingDeepLinkProvider.notifier).consume();
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
