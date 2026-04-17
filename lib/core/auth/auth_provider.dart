import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';
import 'rbac_models.dart';

/// Riverpod provider for authentication state management

/// Current logged-in user (null if not logged in)
final currentUserProvider = StateProvider<User?>((ref) {
  return AuthService.currentUser;
});

/// Current user session
final currentSessionProvider = StateProvider<UserSession?>((ref) {
  return AuthService.currentSession;
});

/// Login state notifier
final authNotifierProvider =
    StateNotifierProvider<AuthNotifier, AsyncValue<void>>((ref) {
      return AuthNotifier();
    });

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  AuthNotifier() : super(const AsyncValue.data(null));

  Future<bool> login(String username, String password) async {
    state = const AsyncValue.loading();
    try {
      final (success, message, user) = await AuthService.login(
        username,
        password,
      );
      if (success && user != null) {
        state = const AsyncValue.data(null);
      } else {
        state = AsyncValue.error(message, StackTrace.current);
      }
      return success;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      return false;
    }
  }

  Future<bool> logout() async {
    try {
      return await AuthService.logout();
    } catch (e) {
      return false;
    }
  }
}

/// Provider to check if user is logged in
final isLoggedInProvider = Provider<bool>((ref) {
  return AuthService.currentUser != null;
});

/// Provider to check if user has specific permission
final hasPermissionProvider = Provider.family<bool, PermissionCategory>((
  ref,
  permission,
) {
  return AuthService.hasPermission(permission);
});

/// Provider to get current user role
final currentUserRoleProvider = Provider<UserRole?>((ref) {
  return AuthService.currentUser?.role;
});

/// Provider to check if current user is admin
final isAdminProvider = Provider<bool>((ref) {
  return AuthService.currentUser?.role == UserRole.admin;
});
