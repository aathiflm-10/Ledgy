import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/auth_provider.dart';
import '../main.dart';

// Screens
import '../screens/auth/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/onboarding/sms_permission_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/main_shell.dart';
import '../screens/transactions/transactions_screen.dart';
import '../screens/sms_review/sms_review_screen.dart';
import '../screens/analytics/analytics_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/settings/budgets/budgets_screen.dart';
import '../screens/settings/goals/goals_screen.dart';
import '../screens/settings/recurring/recurring_screen.dart';
import '../screens/settings/appearance/appearance_screen.dart';
import '../screens/settings/sms/sms_settings_screen.dart';
import '../screens/notifications/notifications_screen.dart';

// Helper class to adapt Dart Stream to GoRouter refresh Listenable
class GoRouterRefreshStream extends ChangeNotifier {
  late final StreamSubscription<dynamic> _subscription;

  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authService = ref.watch(authServiceProvider);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: GoRouterRefreshStream(authService.authStateChanges),
    redirect: (context, state) {
      final user = authService.currentSimulatedUser;
      final isLoggedIn = user != null;
      final loc = state.matchedLocation;

      final publicRoutes = ['/', '/login', '/signup'];

      // 1. If not logged in and trying to access an authenticated screen, force Login
      if (!isLoggedIn && !publicRoutes.contains(loc)) {
        return '/login';
      }

      // 2. If logged in and on public auth screens, redirect based on onboarding state
      if (isLoggedIn && (loc == '/login' || loc == '/signup' || loc == '/')) {
        final hasOnboarded = globalPrefs.getBool('hasOnboarded_${user.uid}') ?? false;
        if (!hasOnboarded) {
          return '/onboarding';
        }
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/sms-permission', builder: (_, __) => const SmsPermissionScreen()),
      
      // Main shell layout route
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/transactions', builder: (_, __) => const TransactionsScreen()),
          GoRoute(path: '/sms-review', builder: (_, __) => const SmsReviewScreen()),
          GoRoute(path: '/analytics', builder: (_, __) => const AnalyticsScreen()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        ],
      ),
      GoRoute(path: '/settings/budgets', builder: (_, __) => const BudgetsScreen()),
      GoRoute(path: '/settings/goals', builder: (_, __) => const GoalsScreen()),
      GoRoute(path: '/settings/recurring', builder: (_, __) => const RecurringScreen()),
      GoRoute(path: '/settings/appearance', builder: (_, __) => const AppearanceScreen()),
      GoRoute(path: '/settings/sms', builder: (_, __) => const SmsSettingsScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
    ],
  );
});
