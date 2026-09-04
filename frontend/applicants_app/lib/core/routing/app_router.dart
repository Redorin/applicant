import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../features/applicant_browse/applicant_browse_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/dashboard/dashboard_screen.dart';
import '../../features/data_health/data_health_screen.dart';
import '../../features/master_data/archived_screen.dart';
import '../../features/import/import_screen.dart';
import '../../features/logs/logs_screen.dart';
import '../../features/master_data/master_data_screen.dart';
import '../../features/preferences/preferences_screen.dart';
import '../../features/reports/summary_reports_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/splash/splash_screen.dart';

/// TESTING MODE: skips the login screen — the splash signs in automatically.
/// Set to false (initial route becomes /login) before deploying for real use.
const kAutoLoginForTesting = false;

/// Sidebar tabs share the shell frame, so switching between them shouldn't
/// replay a full page-navigation transition — just a quick fade.
Page<void> _tabPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 90),
    reverseTransitionDuration: const Duration(milliseconds: 90),
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// One route, one branch: each screen under the shell keeps its own widget
/// subtree (and Riverpod-independent local state — scroll position, in-
/// progress form fields, etc.) alive in the shell's `IndexedStack` instead
/// of being torn down and rebuilt from scratch every time you navigate away
/// and back. This is what used to make switching sidebar tabs (and jumping
/// out to Settings/Archived/Import and back) feel slow.
StatefulShellBranch _branch(GoRoute route) =>
    StatefulShellBranch(routes: [route]);

/// Routes: /login → /splash → shell tabs. The shell route keeps the
/// sidebar/topbar alive while the content area swaps per tab.
final appRouter = GoRouter(
  initialLocation: kAutoLoginForTesting ? '/splash' : '/login',
  routes: [
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(path: '/splash', builder: (context, state) => const SplashScreen()),
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) => AppShell(
        currentPath: state.uri.path,
        child: navigationShell,
      ),
      branches: [
        _branch(GoRoute(
          path: '/dashboard',
          pageBuilder: (context, state) =>
              _tabPage(state, const DashboardScreen()),
        )),
        _branch(GoRoute(
          path: '/master-data',
          pageBuilder: (context, state) => _tabPage(
            state,
            MasterDataScreen(
              initialSearch: state.uri.queryParameters['search'],
              initialId:
                  int.tryParse(state.uri.queryParameters['id'] ?? ''),
            ),
          ),
        )),
        _branch(GoRoute(
          path: '/list',
          pageBuilder: (context, state) =>
              _tabPage(state, const ApplicantBrowseScreen(hiredOnly: false)),
        )),
        _branch(GoRoute(
          path: '/hired',
          pageBuilder: (context, state) =>
              _tabPage(state, const ApplicantBrowseScreen(hiredOnly: true)),
        )),
        _branch(GoRoute(
          path: '/reports',
          pageBuilder: (context, state) =>
              _tabPage(state, const SummaryReportsScreen()),
        )),
        _branch(GoRoute(
          path: '/data-health',
          pageBuilder: (context, state) =>
              _tabPage(state, const DataHealthScreen()),
        )),
        _branch(GoRoute(
          path: '/logs',
          pageBuilder: (context, state) => _tabPage(state, const LogsScreen()),
        )),
        _branch(GoRoute(
          path: '/settings',
          pageBuilder: (context, state) =>
              _tabPage(state, const SettingsScreen()),
        )),
        _branch(GoRoute(
          path: '/archived',
          pageBuilder: (context, state) =>
              _tabPage(state, const ArchivedScreen()),
        )),
        _branch(GoRoute(
          path: '/preferences',
          pageBuilder: (context, state) =>
              _tabPage(state, const PreferencesScreen()),
        )),
        _branch(GoRoute(
          path: '/import',
          pageBuilder: (context, state) =>
              _tabPage(state, const ImportScreen()),
        )),
      ],
    ),
  ],
);
