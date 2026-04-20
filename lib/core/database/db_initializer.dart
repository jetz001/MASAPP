import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'db_connection.dart';

final _log = Logger();

/// Initializes and manages SQLite database schema, seed data, and backups.
///
/// Responsibilities:
/// - Create/update schema from SQL file
/// - Seed initial data
/// - Auto-backup database daily
/// - Migration handling
class DbInitializer {
  static const _schemaAsset = 'db/schema_sqlite.sql';
  static const _seedAsset = 'db/seed_sqlite.sql';

  /// Initialize database: create schema if not exists, run seed if new.
  /// Accepts database instance directly to avoid singleton access issues.
  /// Returns true if successful.
  static Future<bool> initializeDatabase(Database db) async {
    try {
      // Check if latest schema already exists (look for machine_running_hours table which was added in latest version)
      final result = await db.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'machine_running_hours'],
      );

      if (result.isEmpty) {
        _log.i(
          'Database schema is outdated or new. Creating/updating schema...',
        );
        await _createSchema(db);
        await _seedInitialData(db);
        _log.i('Database schema and seed data created/updated successfully');
      } else {
        // --- ADDED MIGRATION CHECKS FOR DEV PARITY ---
        
        final userTableInfo = await db.rawQuery('PRAGMA table_info(users)');
        final hasThemeCol = userTableInfo.any((col) => col['name'] == 'theme_preference');
        final hasPinCol = userTableInfo.any((col) => col['name'] == 'approval_pin_hash');
        
        // 2. Check for machine_positions (renamed from layout_machines)
        final posTable = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'machine_positions'],
        );

        if (!hasThemeCol || !hasPinCol || posTable.isEmpty) {
          _log.i('Migration: Outdated schema detected. Forcing full initialization...');
          await _createSchema(db);
          await _seedInitialData(db);
        }

        // 4. Check for machine_snapshots (Added 2026-04-20)
        final snapTable = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'machine_snapshots'],
        );
        if (snapTable.isEmpty) {
          _log.i('Migration: Creating machine_snapshots table...');
          await db.execute('''
            CREATE TABLE machine_snapshots (
              snapshot_id   TEXT PRIMARY KEY,
              machine_id    TEXT NOT NULL,
              machine_no    TEXT NOT NULL,
              machine_name  TEXT,
              brand         TEXT,
              model         TEXT,
              dept_name     TEXT,
              location      TEXT,
              captured_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
        }

        // 5. Add snapshot_id to work_orders (Added 2026-04-20)
        final woTableInfo = await db.rawQuery('PRAGMA table_info(work_orders)');
        final hasSnapshotId = woTableInfo.any((col) => col['name'] == 'snapshot_id');
        if (!hasSnapshotId) {
          _log.i('Migration: Adding snapshot_id to work_orders...');
          await db.execute('ALTER TABLE work_orders ADD COLUMN snapshot_id TEXT REFERENCES machine_snapshots(snapshot_id)');
        }

        // 6. Add snapshot_id to pm_am_plans and work_permits (Added 2026-04-20)
        final pmTableInfo = await db.rawQuery('PRAGMA table_info(pm_am_plans)');
        if (!pmTableInfo.any((col) => col['name'] == 'snapshot_id')) {
          _log.i('Migration: Adding snapshot_id to pm_am_plans...');
          await db.execute('ALTER TABLE pm_am_plans ADD COLUMN snapshot_id TEXT REFERENCES machine_snapshots(snapshot_id)');
        }
        final wpTableInfo = await db.rawQuery('PRAGMA table_info(work_permits)');
        if (!wpTableInfo.any((col) => col['name'] == 'snapshot_id')) {
          _log.i('Migration: Adding snapshot_id to work_permits...');
          await db.execute('ALTER TABLE work_permits ADD COLUMN snapshot_id TEXT REFERENCES machine_snapshots(snapshot_id)');
        }

        final machinesTableInfo = await db.rawQuery('PRAGMA table_info(machines)');
        if (!machinesTableInfo.any((col) => col['name'] == 'handover_conclusion')) {
          _log.i('Migration: Adding handover_conclusion to machines...');
          await db.execute('ALTER TABLE machines ADD COLUMN handover_conclusion TEXT');
        }

        _log.i('Database schema is up to date (or migrated). Skipping full initialization.');
      }

      return true;
    } catch (e) {
      _log.e('Failed to initialize database: $e');
      return false;
    }
  }

  /// [TEMPORARY] Wipe all machine-related data to allow a fresh start.
  static Future<void> wipeMachineData(Database db) async {
    _log.w('WIPING ALL MACHINE DATA AS REQUESTED...');
    await db.transaction((tx) async {
      final tables = [
        'handover_attachments',
        'handover_checklist_results',
        'machine_handover',
        'machine_specs',
        'permit_safety_checks',
        'work_permits',
        'pm_am_executions',
        'pm_am_tasks',
        'pm_am_schedules',
        'pm_am_plans',
        'machine_positions',
        'work_order_rca',
        'work_order_labor',
        'work_orders',
        'machine_running_hours',
        'machines',
        'machine_snapshots'
      ];
      for (final table in tables) {
        try {
          await tx.execute('DELETE FROM $table');
          _log.i('Cleared table: $table');
        } catch (e) {
          _log.w('Failed to clear $table: $e');
        }
      }
    });
    _log.i('Database machine data wipe completed.');
  }

  /// Load and execute schema SQL from asset.
  static Future<void> _createSchema(Database db) async {
    try {
      final schemaSql = await rootBundle.loadString(_schemaAsset);
      final statements = _splitSqlStatements(schemaSql);

      int executed = 0;
      int failed = 0;

      for (final statement in statements) {
        try {
          await db.execute(statement);
          executed++;
        } catch (e) {
          failed++;
          _log.w(
            'Statement skipped (may not be critical): ${e.toString().split(':').first}',
          );
        }
      }

      _log.i(
        'Schema created: $executed executed, $failed skipped from ${statements.length} statements',
      );
    } catch (e) {
      _log.e('Error creating schema: $e');
      rethrow;
    }
  }

  /// Load and execute seed SQL from asset.
  static Future<void> _seedInitialData(Database db) async {
    try {
      final seedSql = await rootBundle.loadString(_seedAsset);
      final statements = _splitSqlStatements(seedSql);

      for (final statement in statements) {
        await db.execute(statement);
      }

      _log.i('Seed data inserted with ${statements.length} statements');
    } catch (e) {
      _log.e('Error seeding data: $e');
      rethrow;
    }
  }

  /// Helper to split SQL file into individual statements while removing comments.
  static List<String> _splitSqlStatements(String sql) {
    if (sql.isEmpty) return [];

    // 1. Split by semicolon
    final parts = sql.split(';');
    final statements = <String>[];

    for (var part in parts) {
      // 2. Process each part: remove line comments (starting with --)
      final lines = part.split('\n');
      final processedLines = lines.where((line) {
        final trimmedLine = line.trim();
        return trimmedLine.isNotEmpty && !trimmedLine.startsWith('--');
      }).toList();

      // 3. Rejoin and check if there's actual SQL content
      final statement = processedLines.join('\n').trim();
      if (statement.isNotEmpty) {
        statements.add(statement);
      }
    }

    return statements;
  }

  /// Create daily backup of database file.
  /// Call this during app startup or on a schedule.
  /// Backs up to: [dbPath]_backups/[date_time].db
  static Future<bool> createBackup(String dbPath) async {
    try {
      final originalFile = File(dbPath);
      if (!await originalFile.exists()) {
        _log.w('Database file not found for backup: $dbPath');
        return false;
      }

      // Create backup directory
      final backupDir = Directory('${dbPath}_backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      // Generate backup filename with timestamp
      final now = DateTime.now();
      final timestamp = now
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')[0];
      final backupPath = '${backupDir.path}/masapp_backup_$timestamp.db';

      // Copy file
      await originalFile.copy(backupPath);
      _log.i('Database backed up to: $backupPath');

      // Cleanup old backups (keep only last 30 days)
      await _cleanupOldBackups(backupDir, daysToKeep: 30);

      return true;
    } catch (e) {
      _log.e('Failed to create backup: $e');
      return false;
    }
  }

  /// Remove backup files older than daysToKeep.
  static Future<void> _cleanupOldBackups(
    Directory backupDir, {
    int daysToKeep = 30,
  }) async {
    try {
      final files = await backupDir.list().toList();
      final now = DateTime.now();

      for (final entity in files) {
        if (entity is File && entity.path.endsWith('.db')) {
          final stat = await entity.stat();
          final age = now.difference(stat.modified);

          if (age.inDays > daysToKeep) {
            await entity.delete();
            _log.d('Deleted old backup: ${entity.path}');
          }
        }
      }
    } catch (e) {
      _log.e('Error cleaning up old backups: $e');
    }
  }

  /// Get list of recent backups.
  static Future<List<File>> getBackups(String dbPath) async {
    try {
      final backupDir = Directory('${dbPath}_backups');
      if (!await backupDir.exists()) {
        return [];
      }

      final files = await backupDir.list().toList();
      final backups = files
          .whereType<File>()
          .where((f) => f.path.endsWith('.db'))
          .toList();

      // Sort by modified time, newest first
      backups.sort(
        (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
      );
      return backups;
    } catch (e) {
      _log.e('Error getting backups: $e');
      return [];
    }
  }

  /// Restore database from a backup file.
  static Future<bool> restoreFromBackup(
    String backupPath,
    String targetDbPath,
  ) async {
    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        _log.e('Backup file not found: $backupPath');
        return false;
      }

      // Close current connection
      await DbConnection.instance.disconnect();

      // Replace database file
      final targetFile = File(targetDbPath);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await backupFile.copy(targetDbPath);

      _log.i('Database restored from backup: $backupPath');
      return true;
    } catch (e) {
      _log.e('Error restoring from backup: $e');
      return false;
    }
  }
}
