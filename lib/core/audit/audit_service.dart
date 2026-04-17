import 'dart:convert';
import 'package:logger/logger.dart';
import '../database/db_helper.dart';
import '../auth/auth_service.dart';

final _log = Logger();

/// Audit log entry types
enum AuditAction { insert, update, delete }

extension AuditActionExt on AuditAction {
  String toDbString() => name.toUpperCase();
}

/// Service for logging all database changes to audit trail.
/// Every INSERT, UPDATE, DELETE is automatically logged with:
/// - Table name and record ID
/// - User who made the change
/// - Old and new data (as JSON)
/// - Timestamp and client info
class AuditService {
  /// Log INSERT action
  static Future<void> logInsert(
    String tableName,
    String recordId,
    Map<String, dynamic> newData,
  ) async {
    await _logAuditTrail(
      tableName: tableName,
      recordId: recordId,
      action: AuditAction.insert,
      newData: newData,
    );
  }

  /// Log UPDATE action
  static Future<void> logUpdate(
    String tableName,
    String recordId,
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
  ) async {
    await _logAuditTrail(
      tableName: tableName,
      recordId: recordId,
      action: AuditAction.update,
      oldData: oldData,
      newData: newData,
    );
  }

  /// Log DELETE action
  static Future<void> logDelete(
    String tableName,
    String recordId,
    Map<String, dynamic> oldData,
  ) async {
    await _logAuditTrail(
      tableName: tableName,
      recordId: recordId,
      action: AuditAction.delete,
      oldData: oldData,
    );
  }

  /// Internal method to write audit log entry
  static Future<void> _logAuditTrail({
    required String tableName,
    required String recordId,
    required AuditAction action,
    Map<String, dynamic>? oldData,
    Map<String, dynamic>? newData,
  }) async {
    try {
      final user = AuthService.currentUser;
      final session = AuthService.currentSession;

      await DbHelper.execute(
        '''INSERT INTO audit_log 
           (table_name, record_id, action, user_id, username, ip_address, hostname, old_data, new_data, changed_at)
           VALUES (@table_name, @record_id, @action, @user_id, @username, @ip_address, @hostname, @old_data, @new_data, @changed_at)''',
        params: {
          'table_name': tableName,
          'record_id': recordId,
          'action': action.toDbString(),
          'user_id': user?.userId ?? 'SYSTEM',
          'username': user?.username ?? 'SYSTEM',
          'ip_address': session?.ipAddress ?? 'UNKNOWN',
          'hostname': session?.hostname ?? 'UNKNOWN',
          'old_data': oldData != null ? jsonEncode(oldData) : null,
          'new_data': newData != null ? jsonEncode(newData) : null,
          'changed_at': DateTime.now().toIso8601String(),
        },
      );

      _log.d('Audit logged: $action on $tableName[$recordId]');
    } catch (e) {
      _log.e('Error logging audit trail: $e');
      // Don't throw—audit failure should not break main operation
    }
  }

  /// Query audit logs with filters
  static Future<List<Map<String, dynamic>>> getAuditLogs({
    String? tableName,
    String? userId,
    String? action,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      var sql = 'SELECT * FROM audit_log WHERE 1=1';
      final params = <String, dynamic>{};

      if (tableName != null) {
        sql += ' AND table_name = @table_name';
        params['table_name'] = tableName;
      }

      if (userId != null) {
        sql += ' AND user_id = @user_id';
        params['user_id'] = userId;
      }

      if (action != null) {
        sql += ' AND action = @action';
        params['action'] = action;
      }

      if (startDate != null) {
        sql += ' AND changed_at >= @start_date';
        params['start_date'] = startDate.toIso8601String();
      }

      if (endDate != null) {
        sql += ' AND changed_at <= @end_date';
        params['end_date'] = endDate.toIso8601String();
      }

      sql += ' ORDER BY changed_at DESC';

      return await DbHelper.query(sql, params: params);
    } catch (e) {
      _log.e('Error querying audit logs: $e');
      return [];
    }
  }

  /// Get audit logs for specific record
  static Future<List<Map<String, dynamic>>> getRecordHistory(
    String tableName,
    String recordId,
  ) async {
    try {
      return await DbHelper.query(
        'SELECT * FROM audit_log WHERE table_name = @table_name AND record_id = @record_id ORDER BY changed_at DESC',
        params: {'table_name': tableName, 'record_id': recordId},
      );
    } catch (e) {
      _log.e('Error getting record history: $e');
      return [];
    }
  }

  /// Get audit logs by user
  static Future<List<Map<String, dynamic>>> getUserActivity(
    String userId,
  ) async {
    try {
      return await DbHelper.query(
        'SELECT * FROM audit_log WHERE user_id = @user_id ORDER BY changed_at DESC LIMIT 100',
        params: {'user_id': userId},
      );
    } catch (e) {
      _log.e('Error getting user activity: $e');
      return [];
    }
  }

  /// Get recent activity across all tables
  static Future<List<Map<String, dynamic>>> getRecentActivity({
    int limit = 100,
  }) async {
    try {
      return await DbHelper.query(
        'SELECT * FROM audit_log ORDER BY changed_at DESC LIMIT @limit',
        params: {'limit': limit},
      );
    } catch (e) {
      _log.e('Error getting recent activity: $e');
      return [];
    }
  }

  /// Archive old audit logs (keep only last N days)
  static Future<int> cleanupOldLogs({int daysToKeep = 365}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: daysToKeep));
      const sql = 'DELETE FROM audit_log WHERE changed_at < @cutoff_date';
      final deletedCount = await DbHelper.execute(
        sql,
        params: {'cutoff_date': cutoffDate.toIso8601String()},
      );
      _log.i('Cleanup audit logs: deleted $deletedCount old entries');
      return deletedCount;
    } catch (e) {
      _log.e('Error cleaning up audit logs: $e');
      return 0;
    }
  }
}
