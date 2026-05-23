import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/config/theme.dart';
import 'features/auth/domain/auth_notifier.dart';
import 'features/auth/domain/auth_state.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/auth/ui/otp_screen.dart';
import 'features/auth/ui/register_screen.dart';
import 'features/auth/ui/splash_screen.dart';
import 'features/contacts/ui/add_contact_screen.dart';
import 'features/shell/ui/shell_screen.dart';

// ── Router ────────────────────────────────────────────────────────────────────

/// [_routerProvider] is invalidated whenever authState changes, which causes
/// GoRouter to re-evaluate the redirect. This is the single source of
/// navigation truth — screens never push/replace routes for auth transitions.
final _routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final loc = state.matchedLocation;

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
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/otp',
        builder: (_, __) => const OtpScreen(),
      ),
      // ── Authenticated shell ─────────────────────────────────────────────
      GoRoute(
        path: '/home',
        builder: (_, __) => const ShellScreen(),
      ),
      // AddContact is a full-screen route pushed over the shell.
      GoRoute(
        path: '/contacts/add',
        builder: (_, __) => const AddContactScreen(),
      ),
      // ── Placeholders for later prompts ──────────────────────────────────
      GoRoute(
        path: '/chat/:conversationId',
        builder: (_, state) => _Placeholder(
          'Chat ${state.pathParameters['conversationId']}',
        ),
      ),
      GoRoute(
        path: '/call/incoming',
        builder: (_, __) => const _Placeholder('Incoming Call'),
      ),
      GoRoute(
        path: '/call/active',
        builder: (_, __) => const _Placeholder('Active Call'),
      ),
    ],
  );
});

// ── App root ──────────────────────────────────────────────────────────────────

class FamilyLinkApp extends ConsumerWidget {
  const FamilyLinkApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    return MaterialApp.router(
      title: 'FamilyLink',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

// ── Generic placeholder for routes built in later prompts ─────────────────────

class _Placeholder extends StatelessWidget {
  final String name;
  const _Placeholder(this.name);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: Center(
        child: Text(
          name,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
      ),
    );
  }
}
