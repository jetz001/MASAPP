import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:masapp/core/database/db_connection.dart';

final _log = Logger();
const _uuid = Uuid();

class UsageLogService {
  /// Records a user action in the database usage_logs table.
  /// 
  /// [userId] and [username] can be null if the user is not logged in (e.g., failed login attempt).
  /// [action] is a short string describing what happened (e.g., 'LOGIN', 'APP_START').
  /// [details] can be any JSON or text string containing extra context.
  static Future<void> logAction({
    String? userId,
    String? username,
    required String action,
    String? details,
  }) async {
    try {
      if (!DbConnection.instance.isConnected) {
        _log.w('Cannot log action "$action": Database not connected.');
        return;
      }

      final db = DbConnection.instance.db;
      final logId = _uuid.v4();

      await db.insert('usage_logs', {
        'log_id': logId,
        'user_id': userId,
        'username': username,
        'action': action,
        'details': details,
        // using sqlite's current_timestamp or let dart pass it
        // leaving it null lets the db default CURRENT_TIMESTAMP take over
        // 'created_at': DateTime.now().toIso8601String(), 
      });

      _log.d('Logged action: $action by ${username ?? 'Unknown'}');
    } catch (e) {
      _log.e('Failed to log action: $e');
    }
  }
}
