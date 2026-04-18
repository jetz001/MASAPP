import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/db_helper.dart';
import '../../features/auth/auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final notifier = ThemeModeNotifier();
  // When auth state changes, reload theme from DB
  ref.listen<UserSession?>(authProvider, (_, user) {
    if (user != null) {
      notifier.loadFromDb(user.userId);
    } else {
      notifier.resetToDefault();
    }
  });
  return notifier;
});

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark);

  String? _currentUserId;

  /// Load saved theme preference from DB for the given user.
  Future<void> loadFromDb(String userId) async {
    _currentUserId = userId;
    try {
      final row = await DbHelper.queryOne(
        'SELECT theme_preference FROM users WHERE user_id = @uid',
        params: {'uid': userId},
      );
      final pref = row?['theme_preference'] as String? ?? 'dark';
      state = pref == 'light' ? ThemeMode.light : ThemeMode.dark;
    } catch (_) {
      state = ThemeMode.dark;
    }
  }

  /// Toggle between light and dark, persist to DB.
  Future<void> toggle() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    state = next;
    await _persist(next);
  }

  /// Set specific mode.
  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    await _persist(mode);
  }

  void resetToDefault() {
    _currentUserId = null;
    state = ThemeMode.dark;
  }

  Future<void> _persist(ThemeMode mode) async {
    if (_currentUserId == null) return;
    try {
      await DbHelper.execute(
        '''UPDATE users SET theme_preference = @pref
           WHERE user_id = @uid''',
        params: {
          'pref': mode == ThemeMode.light ? 'light' : 'dark',
          'uid': _currentUserId,
        },
      );
    } catch (_) {/* silently ignore if column not yet in schema */}
  }
}
