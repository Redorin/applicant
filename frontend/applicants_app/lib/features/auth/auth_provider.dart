import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/routing/app_router.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(
      // A 401 outside of login/logout means the session died from under us
      // (most likely the API service restarted) — every other screen would
      // otherwise just fail silently forever, which is exactly what this
      // replaces: send the encoder back to a login screen that explains why.
      onUnauthorized: () {
        ref.read(authProvider.notifier).forceSignOut();
        appRouter.go('/login');
      },
    ));

class AuthState {
  const AuthState({
    this.isSignedIn = false,
    this.isBusy = false,
    this.error,
    this.username,
    this.fullName,
  });
  final bool isSignedIn;
  final bool isBusy;
  final String? error;
  final String? username;
  final String? fullName;

  AuthState copyWith({
    bool? isSignedIn,
    bool? isBusy,
    String? error,
    String? username,
    String? fullName,
  }) =>
      AuthState(
        isSignedIn: isSignedIn ?? this.isSignedIn,
        isBusy: isBusy ?? this.isBusy,
        error: error,
        username: username ?? this.username,
        fullName: fullName ?? this.fullName,
      );
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Future<bool> signIn(String username, String password) async {
    state = state.copyWith(isBusy: true, error: null);
    try {
      final api = ref.read(apiClientProvider);
      final res = await api.post('/api/auth/login', body: {
        'username': username,
        'password': password,
      });
      api.sessionToken = res['token'] as String;
      final fullName = res['fullName'] as String?;
      state = AuthState(
        isSignedIn: true,
        username: username,
        fullName: fullName,
      );
      Sentry.configureScope((scope) {
        scope.setUser(SentryUser(
          id: username,
          username: username,
        ));
      });
      Sentry.addBreadcrumb(Breadcrumb(
        category: 'auth',
        message: 'User signed in',
        data: {'username': username},
      ));
      return true;
    } on ApiException catch (e) {
      state = AuthState(error: e.message);
      Sentry.addBreadcrumb(Breadcrumb(
        category: 'auth',
        message: 'Sign-in failed',
        data: {'username': username, 'error': e.message},
        level: SentryLevel.warning,
      ));
      return false;
    } catch (_) {
      state = const AuthState(
        error: 'Cannot reach the local service. Is it running?',
      );
      return false;
    }
  }

  /// Verifies the current password, then updates it — surfaces the server's
  /// error message (e.g. "Current password is incorrect.") the same way
  /// signIn does, rather than throwing.
  Future<bool> changePassword(String current, String newPassword) async {
    final api = ref.read(apiClientProvider);
    try {
      await api.post('/api/auth/change-password', body: {
        'currentPassword': current,
        'newPassword': newPassword,
      });
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    }
  }

  /// Updates the account's display name and refreshes it locally from the
  /// server's response, so the Profile card reflects it immediately.
  Future<bool> updateProfile(String firstName, String lastName) async {
    final api = ref.read(apiClientProvider);
    try {
      final res = await api.put('/api/auth/profile', body: {
        'firstName': firstName,
        'lastName': lastName,
      });
      state = state.copyWith(fullName: res['fullName'] as String?);
      return true;
    } on ApiException catch (e) {
      state = state.copyWith(error: e.message);
      return false;
    }
  }

  Future<void> signOut() async {
    final api = ref.read(apiClientProvider);
    try {
      await api.post('/api/auth/logout');
    } catch (_) {
      // Signing out locally always succeeds even if the service is down.
    }
    Sentry.configureScope((scope) => scope.clear());
    Sentry.addBreadcrumb(Breadcrumb(
      category: 'auth',
      message: 'User signed out',
    ));
    api.sessionToken = null;
    state = const AuthState();
  }

  /// The session died from under us (see apiClientProvider's
  /// onUnauthorized) — unlike signOut(), there's no live token worth
  /// telling the server about, and the login screen should say why.
  void forceSignOut() {
    ref.read(apiClientProvider).sessionToken = null;
    state = const AuthState(error: 'Your session expired. Please sign in again.');
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);
