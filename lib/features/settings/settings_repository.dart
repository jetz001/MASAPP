import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/db_helper.dart';

class SettingsRepository {
  /// Get a setting by key.
  Future<String?> getSetting(String key) async {
    final row = await DbHelper.queryOne(
      'SELECT setting_value FROM app_settings WHERE setting_key = @key',
      params: {'key': key},
    );
    return row?['setting_value']?.toString();
  }

  /// Save a setting (UPSERT).
  Future<void> saveSetting(String key, String value, {String? description}) async {
    await DbHelper.execute(
      '''
      INSERT INTO app_settings (setting_key, setting_value, description, updated_at)
      VALUES (@key, @val, @desc, CURRENT_TIMESTAMP)
      ON CONFLICT(setting_key) DO UPDATE SET
        setting_value = excluded.setting_value,
        description = COALESCE(excluded.description, description),
        updated_at = excluded.updated_at
      ''',
      params: {
        'key': key,
        'val': value,
        'desc': description,
      },
    );
  }

  /// Get multiple settings at once.
  Future<Map<String, String>> getAllSettings() async {
    final rows = await DbHelper.query('SELECT setting_key, setting_value FROM app_settings');
    return {
      for (final r in rows)
        r['setting_key'].toString(): r['setting_value'].toString(),
    };
  }
}

final settingsRepositoryProvider = Provider((ref) => SettingsRepository());
