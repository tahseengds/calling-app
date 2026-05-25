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
import 'features/chats/presentation/screens/chat_rich_screen.dart';
import 'features/chats/presentation/screens/search_screen.dart';
import 'features/chats/presentation/screens/media_viewer.dart';
import 'features/calls/presentation/screens/incoming_call_screen.dart';
import 'features/calls/presentation/screens/outgoing_call_screen.dart';
import 'features/calls/presentation/screens/active_call_screen.dart';
import 'features/profile/presentation/screens/change_number_screen.dart';
import 'features/profile/presentation/screens/edit_name_screen.dart';

// ── Router ────────────────────────────────────────────────────────────────────

/// Notifies GoRouter when auth changes so redirects run without recreating the
/// router (recreating it was unreliable on release builds).
final _routerRefreshProvider = Provider<GoRouterRefreshNotifier>((ref) {
  final notifier = GoRouterRefreshNotifier();
  ref.listen(authNotifierProvider, (_, next) => notifier.notify());
  ref.onDispose(notifier.dispose);
  return notifier;
});

class GoRouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Single GoRouter instance; [redirect] reads live auth state via [Ref.read].
final _routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(_routerRefreshProvider);

  return GoRouter(
    initialLocation: AppConfig.uiOnly ? '/home' : '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final authState = ref.read(authNotifierProvider);

      return switch (authState) {
        // Still checking stored session — stay on splash.
        AuthUnknown() =>
          loc == '/splash' ? null : '/splash',

        // No session — allow auth routes, redirect everything else.
        AuthUnauthenticated() => switch (loc) {
            '/login' || '/register' => null,
            _ => '/login',
          },

        // Waiting for OTP — must be on /otp.
        AuthOtpPending() =>
          loc == '/otp' ? null : '/otp',

        // Fully authenticated — redirect auth/splash routes to home.
        AuthAuthenticated() => switch (loc) {
            '/login' || '/register' || '/otp' || '/splash' => '/home',
            _ => null,
          },
      };
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/otp',
        builder: (context, state) => const OtpScreen(),
      ),
      // ── Authenticated shell ─────────────────────────────────────────────
      GoRoute(
        path: '/home',
        builder: (context, state) => const ShellScreen(),
      ),
      // AddContact is a full-screen route pushed over the shell.
      GoRoute(
        path: '/contacts/add',
        builder: (context, state) => const AddContactScreen(),
      ),
      // ── Chats and Calls Routes ──────────────────────────────────────────
      GoRoute(
        path: '/chat/search',
        builder: (context, state) => const SearchScreen(),
      ),
      GoRoute(
        path: '/chat/:conversationId',
        builder: (_, state) => ChatRichScreen(
          conversationId: state.pathParameters['conversationId'] ?? 'rose',
          // Pass the contact's display name so the screen doesn't need to
          // guess it from the ID (important for real UUID-based IDs).
          contactName: state.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: '/media',
        builder: (_, state) => MediaViewer(
          kind: state.uri.queryParameters['kind'] ?? 'image',
          sender: state.uri.queryParameters['sender'] ?? 'Grandma Rose',
          when: state.uri.queryParameters['when'] ?? 'Today · 7:42 PM',
          // null when not provided → widget falls back to placeholder art
          url: state.uri.queryParameters['url'],
        ),
      ),
      GoRoute(
        path: '/call/incoming',
        builder: (_, state) => IncomingCallScreen(
          name: state.uri.queryParameters['name'] ?? 'Grandma Rose',
          kind: state.uri.queryParameters['kind'] ?? 'video',
        ),
      ),
      GoRoute(
        path: '/call/outgoing',
        builder: (_, state) => OutgoingCallScreen(
          name: state.uri.queryParameters['name'] ?? 'Grandma Rose',
          kind: state.uri.queryParameters['kind'] ?? 'video',
        ),
      ),
      GoRoute(
        path: '/call/active',
        builder: (_, state) => ActiveCallScreen(
          name: state.uri.queryParameters['name'] ?? 'Grandma Rose',
          kind: state.uri.queryParameters['kind'] ?? 'video',
        ),
      ),
      GoRoute(
        path: '/profile/change-number',
        builder: (context, state) => const ChangeNumberScreen(),
      ),
      GoRoute(
        path: '/profile/edit-name',
        builder: (context, state) => const EditNameScreen(),
      ),
    ],
  );
});

// ── App root ──────────────────────────────────────────────────────────────────

class LuminApp extends ConsumerWidget {
  const LuminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
