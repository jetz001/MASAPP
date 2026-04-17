import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'db_connection.dart';

/// Convenience wrapper for running SQLite queries and transactions.
/// Maps PostgreSQL-style named parameters (@param) to SQLite positional (?) parameters.
class DbHelper {
  static Database get _db => DbConnection.instance.db;

  /// Helper to convert "@param" syntax to "?" and return ordered arguments.
  static (String, List<Object?>) _prepare(String sql, Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return (sql, []);
    
    final args = <Object?>[];
    final matches = RegExp(r'@([a-zA-Z0-9_]+)').allMatches(sql);
    
    String finalSql = sql;
    // Iterate in reverse to keep indices valid after replacement
    final matchesList = matches.toList();
    for (var i = matchesList.length - 1; i >= 0; i--) {
      final match = matchesList[i];
      final name = match.group(1);
      if (params.containsKey(name)) {
        args.insert(0, params[name]);
        finalSql = finalSql.replaceRange(match.start, match.end, '?');
      }
    }
    
    return (finalSql, args);
  }

  /// Run a query and return rows.
  static Future<List<Map<String, dynamic>>> query(
    String sql, {
    Map<String, dynamic>? params,
  }) async {
    final (sqliteSql, args) = _prepare(sql, params);
    return await _db.rawQuery(sqliteSql, args);
  }

  /// Query one or null.
  static Future<Map<String, dynamic>?> queryOne(
    String sql, {
    Map<String, dynamic>? params,
  }) async {
    final rows = await query(sql, params: params);
    return rows.isEmpty ? null : rows.first;
  }

  /// Execute write and return affected rows.
  static Future<int> execute(
    String sql, {
    Map<String, dynamic>? params,
  }) async {
    final (sqliteSql, args) = _prepare(sql, params);
    if (sqliteSql.trim().toUpperCase().startsWith('INSERT')) {
      await _db.rawInsert(sqliteSql, args);
      return 1; // Simplification for affected rows
    }
    return await _db.rawUpdate(sqliteSql, args);
  }

  /// Transaction wrapper.
  static Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action,
  ) async {
    return await _db.transaction(action);
  }

  /// Execute inside transaction.
  static Future<int> txExecute(
    Transaction txn,
    String sql, {
    Map<String, dynamic>? params,
  }) async {
    final (sqliteSql, args) = _prepare(sql, params);
    return await txn.rawUpdate(sqliteSql, args);
  }

  /// Query inside transaction.
  static Future<List<Map<String, dynamic>>> txQuery(
    Transaction txn,
    String sql, {
    Map<String, dynamic>? params,
  }) async {
    final (sqliteSql, args) = _prepare(sql, params);
    return await txn.rawQuery(sqliteSql, args);
  }
}
