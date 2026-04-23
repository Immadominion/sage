import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:aura/core/repositories/bot_repository.dart';
import 'package:aura/core/services/auth_service.dart';
import 'package:aura/features/navigation/presentation/app_shell.dart';
import 'package:aura/features/home/presentation/home_screen.dart';
import 'package:aura/features/home/presentation/position_detail_screen.dart';
import 'package:aura/features/home/presentation/position_history_screen.dart';
import 'package:aura/features/chat/presentation/aura_chat_screen.dart';
import 'package:aura/features/automate/presentation/automate_screen.dart';
import 'package:aura/features/automate/presentation/strategy_detail_screen.dart';
import 'package:aura/features/pools/presentation/pool_browser_screen.dart';
import 'package:aura/features/decisions/presentation/decision_log_screen.dart';
import 'package:aura/features/automate/presentation/create_strategy_screen.dart';
import 'package:aura/features/fleet/presentation/fleet_screen.dart';
import 'package:aura/features/onboarding/presentation/onboarding_screen.dart';
import 'package:aura/features/auth/presentation/connect_wallet_screen.dart';
import 'package:aura/features/setup/presentation/setup_screen.dart';
import 'package:aura/features/wallet/presentation/profile_screen.dart';
import 'package:aura/features/splash/presentation/splash_screen.dart';
import 'package:aura/shared/app_lifecycle_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// Whether the user has completed onboarding.
/// Drives the post-splash navigation decision.
final onboardingSeenProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('onboarding_seen') ?? false;
});

/// Whether the user has completed the post-auth setup wizard.
/// Derived from the server-side user record (survives reinstalls / device
/// changes). Falls back to a local SharedPreferences cache so the router
/// doesn't flicker while waiting for the auth state to resolve.
final setupCompletedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  final user = authState.value;
  // Server says complete → trust it.
  if (user != null && user.setupCompleted) return true;
  // Not authenticated → false (router sends to login).
  if (user == null) return false;
  // Authenticated + has bots → setup is definitely complete, even if the
  // flag was never persisted (e.g. bot created via CreateStrategyScreen
  // which doesn't call _markSetupComplete).
  final botList = ref.watch(botListProvider);
  if (botList.hasValue && botList.value!.isNotEmpty) return true;
  // Authenticated but server says incomplete — check local cache.
  // This handles the case where POST /auth/setup-complete succeeded locally
  // but the cached/server user object has stale data.
  final localSetup = ref.watch(_localSetupCompletedProvider);
  return localSetup.value ?? false;
});

/// Local SharedPreferences cache for setup_completed flag.
/// Set by _markSetupComplete() in setup_screen.dart.
final _localSetupCompletedProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('setup_completed') ?? false;
});

/// Tracks whether the splash sequence has completed at least once during
/// this Dart isolate's lifetime. Reset only by a true cold start (process
/// killed by the OS). On warm starts within the same process — typically
/// any resume within ~5 min on iOS — this stays true and lets the splash
/// gate resolve immediately.
///
/// Per audit §5.1: "Cold start only: full sequence. Warm start: bypass
/// /splash entirely; router redirects straight to the resolved destination."
bool _splashShownThisSession = false;

/// Minimum splash duration — full animation only on cold start. Warm starts
/// (process still alive) skip the hold so the daily-driver experience isn't
/// gated on a 3.8 s replay.
final splashMinDelayProvider = FutureProvider<void>((ref) async {
  if (_splashShownThisSession) return;
  await Future.delayed(const Duration(milliseconds: 3800));
  _splashShownThisSession = true;
});

// ═══════════════════════════════════════════════════════════════
// Stable GoRouter — created ONCE, re-evaluates redirects via
// refreshListenable instead of recreating the entire router.
// This prevents widget-tree remounts, splash flashes, and
// unnecessary provider re-triggers on auth state changes.
// ═══════════════════════════════════════════════════════════════

/// ChangeNotifier that fires whenever a routing-relevant provider changes.
/// GoRouter listens to this and re-runs its redirect function.
class _RouterRefresh extends ChangeNotifier {
  _RouterRefresh(Ref ref) {
    // Listen (don't watch) — we only need to trigger a refresh, not rebuild.
    ref.listen(authStateProvider, (_, _) => notifyListeners());
    ref.listen(onboardingSeenProvider, (_, _) => notifyListeners());
    ref.listen(splashMinDelayProvider, (_, _) => notifyListeners());
    ref.listen(_localSetupCompletedProvider, (_, _) => notifyListeners());
    ref.listen(setupCompletedProvider, (_, _) => notifyListeners());
    // setupCompletedProvider is derived from authState, so it auto-updates.
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh(ref);
  ref.onDispose(() => refresh.dispose());

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      // Read (not watch) — the refreshListenable triggers re-evaluation.
      final authState = ref.read(authStateProvider);
      final onboardingSeen = ref.read(onboardingSeenProvider);
      final splashReady = ref.read(splashMinDelayProvider);
      final setupCompleted = ref.read(setupCompletedProvider);

      final loc = state.matchedLocation;

      // ── Still loading ──
      // Don't yank users off auth screens during sign-in — those
      // screens already show their own loading indicators. Redirecting
      // to /splash causes a jarring dark-navy flash in light mode.
      if (authState.isLoading ||
          onboardingSeen.isLoading ||
          splashReady.isLoading) {
        if (loc == '/connect-wallet' ||
            loc == '/onboarding' ||
            loc == '/setup') {
          return null; // stay put — screen handles its own loading state
        }
        return loc == '/splash' ? null : '/splash';
      }

      // When auth has an error (e.g. signIn failed) and user is on
      // connect-wallet, let them stay — the screen shows the error.
      if (authState.hasError && loc == '/connect-wallet') {
        return null;
      }

      final isAuthenticated = authState.value != null;
      final hasSeenOnboarding = onboardingSeen.value ?? false;
      final hasCompletedSetup = setupCompleted; // already a plain bool

      // ── On splash: loading done, route to the right destination ──
      if (loc == '/splash') {
        if (!isAuthenticated) {
          return hasSeenOnboarding ? '/connect-wallet' : '/onboarding';
        }
        // Authenticated — check if setup wizard is needed.
        return hasCompletedSetup ? '/' : '/setup';
      }

      final isPreAuthRoute = loc == '/onboarding' || loc == '/connect-wallet';
      final isSetupRoute = loc == '/setup';

      // ── Authenticated + on a pre-auth screen → setup or home ──
      if (isAuthenticated && isPreAuthRoute) {
        return hasCompletedSetup ? '/' : '/setup';
      }

      // ── Authenticated + on setup but already completed → home ──
      if (isAuthenticated && isSetupRoute && hasCompletedSetup) {
        return '/';
      }

      // ── Not authenticated + on a protected route → gate ──
      // This includes /setup — if auth expired while on setup,
      // the user must re-authenticate.
      if (!isAuthenticated && !isPreAuthRoute) {
        return hasSeenOnboarding ? '/connect-wallet' : '/onboarding';
      }

      return null;
    },
    routes: [
      // ── Splash (initial loading screen) ──
      GoRoute(
        path: '/splash',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const SplashScreen()),
      ),

      // ── Onboarding (outside shell) ──
      GoRoute(
        path: '/onboarding',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const OnboardingScreen()),
      ),

      // ── Connect Wallet (outside shell) ──
      GoRoute(
        path: '/connect-wallet',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const ConnectWalletScreen()),
      ),

      // ── Setup wizard (new users, outside shell) ──
      GoRoute(
        path: '/setup',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const SetupScreen()),
      ),

      // ── Profile (pushed over shell) ──
      GoRoute(
        path: '/profile',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: ProfileScreen()),
      ),

      // ── Fleet leaderboard (pushed over shell from Automate CTA) ──
      GoRoute(
        path: '/fleet',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const FleetScreen()),
      ),

      // ── Position detail (pushed over shell) ──
      GoRoute(
        path: '/position/:positionId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final positionId = state.pathParameters['positionId'] ?? '';
          return PositionDetailScreen(positionId: positionId);
        },
      ),

      // ── Position history (pushed over shell) ──
      GoRoute(
        path: '/history',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PositionHistoryScreen(),
      ),

      // ── Strategy detail (pushed over shell) ──
      GoRoute(
        path: '/strategy/:botId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final botId = state.pathParameters['botId'] ?? '';
          return StrategyDetailScreen(botId: botId);
        },
      ),

      // ── Create new strategy (pushed over shell) ──
      GoRoute(
        path: '/create-strategy',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const CreateStrategyScreen()),
      ),

      // ── Pool Browser (Phase 15, audit §6.1) ──
      // Drill-in from Home, also callable from Chat ("What pools are
      // trending?"). Read-only candidate list.
      GoRoute(
        path: '/pools',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            _fadePage(state: state, child: const PoolBrowserScreen()),
      ),

      // ── Decision Log (Phase 16, audit §6.2) ──
      GoRoute(
        path: '/decisions/:botId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final botId = state.pathParameters['botId'] ?? '';
          return DecisionLogScreen(botId: botId);
        },
      ),

      // ── Main app shell (3 modes) ──
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppLifecycleManager(
            child: AppShell(navigationShell: navigationShell),
          );
        },
        branches: [
          // Mode 1: Delegate — capital overview
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          // Mode 2: Intelligence — Aura AI Chat
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/intelligence',
                builder: (context, state) => const AuraChatScreen(),
              ),
            ],
          ),
          // Mode 3: Automate — strategies + execution
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/control',
                builder: (context, state) => const AutomateScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Returns a [CustomTransitionPage] with a 300 ms fade.
/// Eliminates the white-background slide that MaterialPage shows by default.
CustomTransitionPage<void> _fadePage({
  required GoRouterState state,
  required Widget child,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    transitionsBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}
