import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';
import '../storage/attachment_storage_service.dart';
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
  static const _legacyFileMigrationSettingKey =
      'file_assets_legacy_storage_migrated_v1';

  static const _defaultAdminUserId = '00000000-0000-0000-0001-000000000001';
  static const _defaultAdminDeptId = '00000000-0000-0000-0000-000000000001';
  static const _defaultAdminEmployeeNo = 'EMP001';

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
        final hasThemeCol = userTableInfo.any(
          (col) => col['name'] == 'theme_preference',
        );
        final hasPinCol = userTableInfo.any(
          (col) => col['name'] == 'approval_pin_hash',
        );

        // 2. Check for machine_positions (renamed from layout_machines)
        final posTable = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'machine_positions'],
        );

        if (!hasThemeCol || !hasPinCol || posTable.isEmpty) {
          _log.i(
            'Migration: Outdated schema detected. Forcing full initialization...',
          );
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
        final hasSnapshotId = woTableInfo.any(
          (col) => col['name'] == 'snapshot_id',
        );
        if (!hasSnapshotId) {
          _log.i('Migration: Adding snapshot_id to work_orders...');
          await db.execute(
            'ALTER TABLE work_orders ADD COLUMN snapshot_id TEXT REFERENCES machine_snapshots(snapshot_id)',
          );
        }
        if (!woTableInfo.any((col) => col['name'] == 'closure_notes')) {
          _log.i('Migration: Adding closure_notes to work_orders...');
          await db.execute(
            'ALTER TABLE work_orders ADD COLUMN closure_notes TEXT',
          );
        }

        final supplierTableInfo = await db.rawQuery(
          'PRAGMA table_info(suppliers)',
        );
        if (!supplierTableInfo.any((col) => col['name'] == 'service_scope')) {
          _log.i('Migration: Adding service_scope to suppliers...');
          await db.execute(
            'ALTER TABLE suppliers ADD COLUMN service_scope TEXT',
          );
        }

        // 6. Create handover_attachments if not exists
        final haTable = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'handover_attachments'],
        );
        if (haTable.isEmpty) {
          _log.i('Migration: Creating handover_attachments table...');
          await db.execute('''
            CREATE TABLE handover_attachments (
              attachment_id TEXT PRIMARY KEY,
              handover_id   TEXT NOT NULL REFERENCES machine_handover(handover_id) ON DELETE CASCADE,
              file_name     TEXT NOT NULL,
              file_path     TEXT NOT NULL,
              file_size     INTEGER,
              mime_type     TEXT,
              uploaded_by   TEXT REFERENCES users(user_id),
              uploaded_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
        }
        if (!supplierTableInfo.any((col) => col['name'] == 'vendor_type')) {
          _log.i('Migration: Adding vendor_type to suppliers...');
          await db.execute(
            "ALTER TABLE suppliers ADD COLUMN vendor_type TEXT NOT NULL DEFAULT 'repair'",
          );
        }
        if (!supplierTableInfo.any(
          (col) => col['name'] == 'is_outsource_vendor',
        )) {
          _log.i('Migration: Adding is_outsource_vendor to suppliers...');
          await db.execute(
            'ALTER TABLE suppliers ADD COLUMN is_outsource_vendor INTEGER NOT NULL DEFAULT 0',
          );
        }

        // 6. Add snapshot_id to pm_am_plans and work_permits (Added 2026-04-20)
        final pmTableInfo = await db.rawQuery('PRAGMA table_info(pm_am_plans)');
        if (!pmTableInfo.any((col) => col['name'] == 'snapshot_id')) {
          _log.i('Migration: Adding snapshot_id to pm_am_plans...');
          await db.execute(
            'ALTER TABLE pm_am_plans ADD COLUMN snapshot_id TEXT REFERENCES machine_snapshots(snapshot_id)',
          );
        }
        final wpTableInfo = await db.rawQuery(
          'PRAGMA table_info(work_permits)',
        );
        if (!wpTableInfo.any((col) => col['name'] == 'snapshot_id')) {
          _log.i('Migration: Adding snapshot_id to work_permits...');
          await db.execute(
            'ALTER TABLE work_permits ADD COLUMN snapshot_id TEXT REFERENCES machine_snapshots(snapshot_id)',
          );
        }
        if (!wpTableInfo.any((col) => col['name'] == 'wo_id')) {
          _log.i('Migration: Adding wo_id to work_permits...');
          await db.execute(
            'ALTER TABLE work_permits ADD COLUMN wo_id TEXT REFERENCES work_orders(wo_id) ON DELETE SET NULL',
          );
        }
        if (!wpTableInfo.any((col) => col['name'] == 'pm_am_id')) {
          _log.i('Migration: Adding pm_am_id to work_permits...');
          await db.execute(
            'ALTER TABLE work_permits ADD COLUMN pm_am_id TEXT REFERENCES pm_am_plans(plan_id) ON DELETE SET NULL',
          );
        }
        if (!wpTableInfo.any((col) => col['name'] == 'required_equipments')) {
          _log.i('Migration: Adding required_equipments to work_permits...');
          await db.execute(
            'ALTER TABLE work_permits ADD COLUMN required_equipments TEXT',
          );
        }
        if (!wpTableInfo.any((col) => col['name'] == 'approval_remarks')) {
          _log.i('Migration: Adding approval_remarks to work_permits...');
          await db.execute(
            'ALTER TABLE work_permits ADD COLUMN approval_remarks TEXT',
          );
        }
        final machinesTableInfo = await db.rawQuery(
          'PRAGMA table_info(machines)',
        );
        if (!machinesTableInfo.any(
          (col) => col['name'] == 'handover_conclusion',
        )) {
          _log.i('Migration: Adding handover_conclusion to machines...');
          await db.execute(
            'ALTER TABLE machines ADD COLUMN handover_conclusion TEXT',
          );
        }

        // 8. Add layout background columns (Added 2026-04-21)
        // 8. Add layout background columns (Added 2026-04-21)
        final List<Map<String, dynamic>> layoutsInfo = await db.rawQuery(
          'PRAGMA table_info(factory_layouts)',
        );

        final bool hasBgPath = layoutsInfo.any(
          (col) => col['name'] == 'background_path',
        );
        if (!hasBgPath) {
          _log.i('Migration: Adding background_path to factory_layouts...');
          await db.execute(
            'ALTER TABLE factory_layouts ADD COLUMN background_path TEXT',
          );
        }

        final bool hasBgOpacity = layoutsInfo.any(
          (col) => col['name'] == 'background_opacity',
        );
        if (!hasBgOpacity) {
          _log.i('Migration: Adding background_opacity to factory_layouts...');
          await db.execute(
            'ALTER TABLE factory_layouts ADD COLUMN background_opacity REAL DEFAULT 1.0',
          );
        }

        final bool hasWidth = layoutsInfo.any(
          (col) => col['name'] == 'width_m',
        );
        if (!hasWidth) {
          _log.i('Migration: Adding width_m to factory_layouts...');
          await db.execute(
            'ALTER TABLE factory_layouts ADD COLUMN width_m REAL DEFAULT 100.0',
          );
        }

        // Check for work_processes and work_process_steps (Added 2026-08)
        final workProcTable = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'work_processes'],
        );
        if (workProcTable.isEmpty) {
          _log.i('Migration: Creating work_processes and work_process_steps tables...');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS work_processes (
              process_id        TEXT PRIMARY KEY,
              process_no        TEXT NOT NULL,
              title             TEXT NOT NULL,
              company           TEXT,
              factory           TEXT,
              department        TEXT,
              method_type       TEXT NOT NULL DEFAULT 'current',
              parent_process_id TEXT REFERENCES work_processes(process_id) ON DELETE SET NULL,
              work_type         TEXT NOT NULL DEFAULT 'man',
              machine_id        TEXT REFERENCES machines(machine_id) ON DELETE SET NULL,
              line_id           TEXT,
              prepared_by       TEXT,
              prepared_date     TEXT,
              approved_by       TEXT,
              approved_date     TEXT,
              notes             TEXT,
              status            TEXT NOT NULL DEFAULT 'draft',
              created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
              updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS work_process_steps (
              step_id          TEXT PRIMARY KEY,
              process_id       TEXT NOT NULL REFERENCES work_processes(process_id) ON DELETE CASCADE,
              step_no          INTEGER NOT NULL,
              description      TEXT NOT NULL,
              event_type       TEXT NOT NULL,
              distance_meters  REAL NOT NULL DEFAULT 0.0,
              parts_quantity   TEXT,
              tools_used       TEXT,
              duration_minutes REAL NOT NULL DEFAULT 0.0,
              value_type       TEXT NOT NULL,
              problem_cause    TEXT,
              improvement_idea TEXT,
              created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_work_process_steps_process ON work_process_steps(process_id, step_no)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_work_processes_method ON work_processes(method_type, parent_process_id)');
        }

        // Check for problem_solving_records (Action Plans & RCA)
        final rcaTable = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'problem_solving_records'],
        );
        if (rcaTable.isEmpty) {
          _log.i('Migration: Creating problem_solving_records table...');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS problem_solving_records (
              rca_id                TEXT PRIMARY KEY,
              source_type           TEXT NOT NULL,
              source_id             TEXT,
              problem_title         TEXT NOT NULL,
              why_1                 TEXT,
              why_2                 TEXT,
              why_3                 TEXT,
              why_4                 TEXT,
              why_5                 TEXT,
              root_cause            TEXT,
              fishbone_man          TEXT,
              fishbone_machine      TEXT,
              fishbone_material     TEXT,
              fishbone_method       TEXT,
              fishbone_env          TEXT,
              action_steps_json     TEXT,
              target_metric         TEXT,
              before_value          REAL,
              target_value          REAL,
              actual_value          REAL,
              metric_unit           TEXT,
              verified_by           TEXT,
              verification_date     TEXT,
              verification_result   TEXT,
              standardization_notes TEXT,
              status                TEXT DEFAULT 'in_progress',
              created_at            DATETIME DEFAULT CURRENT_TIMESTAMP,
              updated_at            DATETIME DEFAULT CURRENT_TIMESTAMP
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_rca_source ON problem_solving_records(source_type, source_id)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_rca_status ON problem_solving_records(status)');
        } else {
          final rcaTableInfo = await db.rawQuery('PRAGMA table_info(problem_solving_records)');
          final existingCols = rcaTableInfo.map((c) => c['name']?.toString().toLowerCase()).toSet();
          final requiredCols = {
            'why_1': 'TEXT',
            'why_2': 'TEXT',
            'why_3': 'TEXT',
            'why_4': 'TEXT',
            'why_5': 'TEXT',
            'root_cause': 'TEXT',
            'fishbone_man': 'TEXT',
            'fishbone_machine': 'TEXT',
            'fishbone_material': 'TEXT',
            'fishbone_method': 'TEXT',
            'fishbone_env': 'TEXT',
            'action_steps_json': 'TEXT',
            'target_metric': 'TEXT',
            'before_value': 'REAL',
            'target_value': 'REAL',
            'actual_value': 'REAL',
            'metric_unit': 'TEXT',
            'verified_by': 'TEXT',
            'verification_date': 'TEXT',
            'verification_result': 'TEXT',
            'standardization_notes': 'TEXT',
            'status': "TEXT DEFAULT 'in_progress'",
            'updated_at': 'DATETIME DEFAULT CURRENT_TIMESTAMP',
          };

          for (final entry in requiredCols.entries) {
            if (!existingCols.contains(entry.key.toLowerCase())) {
              try {
                _log.i('Migration: Adding column ${entry.key} to problem_solving_records...');
                await db.execute('ALTER TABLE problem_solving_records ADD COLUMN ${entry.key} ${entry.value}');
              } catch (_) {}
            }
          }
        }

        // 9. Check for work_order_outsource (Added 2026-08)
        final outsourceTable = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'work_order_outsource'],
        );
        if (outsourceTable.isEmpty) {
          _log.i('Migration: Creating work_order_outsource table...');
          await db.execute('''
            CREATE TABLE work_order_outsource (
              outsource_id      TEXT PRIMARY KEY,
              wo_id             TEXT NOT NULL REFERENCES work_orders(wo_id) ON DELETE CASCADE,
              vendor_name       TEXT NOT NULL,
              repair_details    TEXT,
              replaced_parts    TEXT,
              gate_pass_no      TEXT,
              expected_return_date DATETIME,
              actual_return_date DATETIME,
              inspector_id      TEXT REFERENCES users(user_id),
              notes             TEXT,
              created_by        TEXT REFERENCES users(user_id),
              created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
              is_passed_inspection INTEGER DEFAULT 1
            )
          ''');
        } else {
          final outsourceTableInfo = await db.rawQuery(
            'PRAGMA table_info(work_order_outsource)',
          );
          if (!outsourceTableInfo.any(
            (col) => col['name'] == 'is_passed_inspection',
          )) {
            _log.i(
              'Migration: Adding is_passed_inspection to work_order_outsource and removing UNIQUE constraint...',
            );
            await db.execute(
              'ALTER TABLE work_order_outsource ADD COLUMN is_passed_inspection INTEGER DEFAULT 1',
            );

            await db.execute(
              'ALTER TABLE work_order_outsource RENAME TO work_order_outsource_old',
            );
            await db.execute('''
              CREATE TABLE work_order_outsource (
                outsource_id      TEXT PRIMARY KEY,
                wo_id             TEXT NOT NULL REFERENCES work_orders(wo_id) ON DELETE CASCADE,
                vendor_name       TEXT NOT NULL,
                repair_details    TEXT,
                replaced_parts    TEXT,
                gate_pass_no      TEXT,
                expected_return_date DATETIME,
                actual_return_date DATETIME,
                inspector_id      TEXT REFERENCES users(user_id),
                notes             TEXT,
                created_by        TEXT REFERENCES users(user_id),
                created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
                is_passed_inspection INTEGER DEFAULT 1
              )
            ''');
            await db.execute('''
              INSERT INTO work_order_outsource 
              SELECT outsource_id, wo_id, vendor_name, repair_details, replaced_parts, gate_pass_no, 
                     expected_return_date, actual_return_date, inspector_id, notes, created_by, created_at, 
                     is_passed_inspection 
              FROM work_order_outsource_old
            ''');
            await db.execute('DROP TABLE work_order_outsource_old');
          }
        }

        final bool hasHeight = layoutsInfo.any(
          (col) => col['name'] == 'height_m',
        );
        if (!hasHeight) {
          _log.i('Migration: Adding height_m to factory_layouts...');
          await db.execute(
            'ALTER TABLE factory_layouts ADD COLUMN height_m REAL DEFAULT 20.0',
          );
        }

        // 10. Check for approved_by in pm_am_plans
        final pmAmPlansTableInfo = await db.rawQuery(
          'PRAGMA table_info(pm_am_plans)',
        );
        if (!pmAmPlansTableInfo.any((col) => col['name'] == 'approved_by')) {
          _log.i('Migration: Adding approved_by to pm_am_plans...');
          await db.execute(
            'ALTER TABLE pm_am_plans ADD COLUMN approved_by TEXT REFERENCES users(user_id)',
          );
        }

        // 9. Make machine_id nullable in work_orders
        final woTableInfo3 = await db.rawQuery(
          'PRAGMA table_info(work_orders)',
        );
        final machineIdCol = woTableInfo3.firstWhere(
          (col) => col['name'] == 'machine_id',
          orElse: () => {},
        );
        if (machineIdCol.isNotEmpty && machineIdCol['notnull'] == 1) {
          _log.i('Migration: Making machine_id nullable in work_orders...');
          await db.execute('PRAGMA foreign_keys=OFF;');
          await db.execute(
            'ALTER TABLE work_orders RENAME TO work_orders_old;',
          );
          await db.execute('''
            CREATE TABLE work_orders (
              wo_id             TEXT PRIMARY KEY,
              wo_no             TEXT UNIQUE NOT NULL,
              machine_id        TEXT,
              snapshot_id       TEXT REFERENCES machine_snapshots(snapshot_id),
              status            TEXT NOT NULL DEFAULT 'pending',
              priority          TEXT NOT NULL DEFAULT 'normal',
              title             TEXT NOT NULL,
              description       TEXT,
              failure_symptom   TEXT,
              failure_cause     TEXT,
              assigned_to       TEXT REFERENCES users(user_id),
              approved_by       TEXT REFERENCES users(user_id),
              estimated_hours   REAL,
              actual_hours      REAL,
              closure_notes     TEXT,
              started_at        DATETIME,
              completed_at      DATETIME,
              approved_at       DATETIME,
              created_by        TEXT NOT NULL REFERENCES users(user_id),
              created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
              updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
              attachments       TEXT
            )
          ''');
          final oldCols = woTableInfo3
              .map((c) => c['name'] as String)
              .join(', ');
          await db.execute(
            'INSERT INTO work_orders ($oldCols) SELECT $oldCols FROM work_orders_old;',
          );
          await db.execute('DROP TABLE work_orders_old;');
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_work_orders_machine ON work_orders(machine_id);',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_work_orders_status ON work_orders(status);',
          );
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_work_orders_assigned_to ON work_orders(assigned_to);',
          );
          await db.execute('PRAGMA foreign_keys=ON;');
        }

        // 10. Add attachments to work_orders
        final woTableInfo4 = await db.rawQuery(
          'PRAGMA table_info(work_orders)',
        );
        final bool hasAttachments = woTableInfo4.any(
          (col) => col['name'] == 'attachments',
        );
        if (!hasAttachments) {
          _log.i('Migration: Adding attachments to work_orders...');
          await db.execute(
            'ALTER TABLE work_orders ADD COLUMN attachments TEXT',
          );
        }

        final bool hasBgScale = layoutsInfo.any(
          (col) => col['name'] == 'background_scale',
        );
        if (!hasBgScale) {
          _log.i('Migration: Adding background_scale to factory_layouts...');
          await db.execute(
            'ALTER TABLE factory_layouts ADD COLUMN background_scale REAL DEFAULT 1.0',
          );
        }

        final bool hasBgOffsetX = layoutsInfo.any(
          (col) => col['name'] == 'bg_offset_x',
        );
        if (!hasBgOffsetX) {
          _log.i('Migration: Adding bg_offset_x to factory_layouts...');
          await db.execute(
            'ALTER TABLE factory_layouts ADD COLUMN bg_offset_x REAL DEFAULT 0.0',
          );
        }

        final bool hasBgOffsetY = layoutsInfo.any(
          (col) => col['name'] == 'bg_offset_y',
        );
        if (!hasBgOffsetY) {
          _log.i('Migration: Adding bg_offset_y to factory_layouts...');
          await db.execute(
            'ALTER TABLE factory_layouts ADD COLUMN bg_offset_y REAL DEFAULT 0.0',
          );
        }

        final bool hasApproved = layoutsInfo.any(
          (col) => col['name'] == 'is_approved',
        );
        if (!hasApproved) {
          _log.i('Migration: Adding is_approved to factory_layouts...');
          await db.execute(
            'ALTER TABLE factory_layouts ADD COLUMN is_approved INTEGER DEFAULT 0',
          );
        }

        // 9. PM/AM Parameter Support (Added 2026-04-23)
        final pmTasksInfo = await db.rawQuery('PRAGMA table_info(pm_am_tasks)');
        if (!pmTasksInfo.any((col) => col['name'] == 'param_type')) {
          _log.i('Migration: Adding param_type to pm_am_tasks...');
          await db.execute(
            'ALTER TABLE pm_am_tasks ADD COLUMN param_type TEXT',
          );
          await db.execute(
            'ALTER TABLE pm_am_tasks ADD COLUMN param_unit TEXT',
          );
        }

        final pmExecInfo = await db.rawQuery(
          'PRAGMA table_info(pm_am_executions)',
        );
        if (!pmExecInfo.any((col) => col['name'] == 'actual_value')) {
          _log.i('Migration: Adding actual_value to pm_am_executions...');
          await db.execute(
            'ALTER TABLE pm_am_executions ADD COLUMN actual_value TEXT',
          );
        }

        final pmPlansInfo = await db.rawQuery('PRAGMA table_info(pm_am_plans)');
        if (!pmPlansInfo.any((col) => col['name'] == 'frequency_months')) {
          _log.i('Migration: Adding frequency_months to pm_am_plans...');
          await db.execute(
            'ALTER TABLE pm_am_plans ADD COLUMN frequency_months INTEGER',
          );
        }

        // 11. Add attachments to pm_am_schedules (Added 2026-08)
        final pmSchedulesInfo = await db.rawQuery(
          'PRAGMA table_info(pm_am_schedules)',
        );
        if (!pmSchedulesInfo.any((col) => col['name'] == 'attachments')) {
          _log.i('Migration: Adding attachments to pm_am_schedules...');
          await db.execute(
            'ALTER TABLE pm_am_schedules ADD COLUMN attachments TEXT',
          );
        }

        // 10. Add usage_logs table
        final usageLogsTable = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'usage_logs'],
        );
        if (usageLogsTable.isEmpty) {
          _log.i('Migration: Creating usage_logs table...');
          await db.execute('''
            CREATE TABLE usage_logs (
              log_id        TEXT PRIMARY KEY,
              user_id       TEXT,
              username      TEXT,
              action        TEXT NOT NULL,
              details       TEXT,
              created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
        }

        // 11. Add part_machine_map and PR tables
        final mapTable = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'part_machine_map'],
        );
        if (mapTable.isEmpty) {
          _log.i('Migration: Creating part_machine_map and PR tables...');
          await db.execute('''
            CREATE TABLE part_machine_map (
              map_id            TEXT PRIMARY KEY,
              part_id           TEXT NOT NULL REFERENCES spare_parts(part_id) ON DELETE CASCADE,
              machine_id        TEXT NOT NULL REFERENCES machines(machine_id) ON DELETE CASCADE,
              quantity          INTEGER NOT NULL DEFAULT 1,
              notes             TEXT,
              UNIQUE(part_id, machine_id)
            )
          ''');

          await db.execute('''
            CREATE TABLE purchase_requests (
              pr_id             TEXT PRIMARY KEY,
              pr_no             TEXT UNIQUE NOT NULL,
              requested_by      TEXT REFERENCES users(user_id),
              status            TEXT NOT NULL DEFAULT 'draft',
              remarks           TEXT,
              created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
              updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');

          await db.execute('''
            CREATE TABLE purchase_request_items (
              pr_item_id        TEXT PRIMARY KEY,
              pr_id             TEXT NOT NULL REFERENCES purchase_requests(pr_id) ON DELETE CASCADE,
              part_id           TEXT NOT NULL REFERENCES spare_parts(part_id),
              quantity          INTEGER NOT NULL,
              unit_cost         REAL,
              supplier_id       TEXT REFERENCES suppliers(supplier_id)
            )
          ''');
        }

        // 12. Add image_path to spare_parts
        final sparePartsCols = await db.rawQuery(
          'PRAGMA table_info(spare_parts)',
        );
        final hasSparePartsImage = sparePartsCols.any(
          (col) => col['name'] == 'image_path',
        );
        if (!hasSparePartsImage) {
          _log.i('Migration: Adding image_path to spare_parts...');
          await db.execute(
            'ALTER TABLE spare_parts ADD COLUMN image_path TEXT',
          );
        }

        // 13. Add tools and tool_transactions
        final toolsTable = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'tools'],
        );
        if (toolsTable.isEmpty) {
          _log.i('Migration: Creating tools and tool_transactions tables...');
          await db.execute('''
            CREATE TABLE tools (
              tool_id       TEXT PRIMARY KEY,
              tool_code     TEXT UNIQUE NOT NULL,
              tool_name     TEXT NOT NULL,
              category      TEXT,
              image_path    TEXT,
              status        TEXT DEFAULT 'available',
              purchase_date DATETIME,
              price         REAL,
              notes         TEXT,
              created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
              is_active     INTEGER DEFAULT 1
            )
          ''');

          await db.execute('''
            CREATE TABLE tool_transactions (
              transaction_id TEXT PRIMARY KEY,
              tool_id        TEXT NOT NULL REFERENCES tools(tool_id),
              action_type    TEXT NOT NULL,
              user_id        TEXT REFERENCES users(user_id),
              reference_no   TEXT,
              notes          TEXT,
              action_date    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
        }

        // 13.1 Add tool_machine_map
        final toolMapTable = await db.query(
          'sqlite_master',
          where: 'type = ? AND name = ?',
          whereArgs: ['table', 'tool_machine_map'],
        );
        if (toolMapTable.isEmpty) {
          _log.i('Migration: Creating tool_machine_map table...');
          await db.execute('''
            CREATE TABLE tool_machine_map (
              map_id      TEXT PRIMARY KEY,
              tool_id     TEXT NOT NULL REFERENCES tools(tool_id) ON DELETE CASCADE,
              machine_id  TEXT NOT NULL REFERENCES machines(machine_id) ON DELETE CASCADE,
              quantity    INTEGER NOT NULL DEFAULT 1,
              notes       TEXT,
              UNIQUE(tool_id, machine_id)
            )
          ''');
        }

        // 14. Repair any dangling foreign keys referencing work_orders_old
        final brokenTables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND sql LIKE '%work_orders_old%'",
        );
        if (brokenTables.isNotEmpty) {
          _log.w(
            'Migration: Found tables with broken foreign keys referencing work_orders_old. Repairing...',
          );
          await db.execute('PRAGMA writable_schema = ON;');
          await db.execute(
            "UPDATE sqlite_master SET sql = replace(sql, 'work_orders_old', 'work_orders') WHERE type='table' AND sql LIKE '%work_orders_old%'",
          );
          await db.execute('PRAGMA writable_schema = OFF;');
          final versionRow = await db.rawQuery('PRAGMA schema_version;');
          final version = versionRow.first.values.first as int;
          await db.execute('PRAGMA schema_version = ${version + 1};');
        }

        // 15. Create technician profile tables and modify technician_skills
        final techAttachmentsTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='technician_attachments'",
        );
        if (techAttachmentsTable.isEmpty) {
          _log.i('Migration: Creating technician_attachments table...');
          await db.execute('''
            CREATE TABLE technician_attachments (
              attachment_id  TEXT PRIMARY KEY,
              technician_id  TEXT NOT NULL REFERENCES users(user_id),
              document_type  TEXT NOT NULL,
              file_name      TEXT NOT NULL,
              file_path      TEXT NOT NULL,
              uploaded_by    TEXT REFERENCES users(user_id),
              uploaded_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
        }

        // Check if technician_skills has score column
        final skillColumns = await db.rawQuery(
          "PRAGMA table_info(technician_skills)",
        );
        if (skillColumns.isNotEmpty &&
            !skillColumns.any((col) => col['name'] == 'score')) {
          _log.i(
            'Migration: Adding score, rated_by, rated_at to technician_skills...',
          );
          await db.execute(
            'ALTER TABLE technician_skills ADD COLUMN score INTEGER',
          );
          await db.execute(
            'ALTER TABLE technician_skills ADD COLUMN rated_by TEXT REFERENCES users(user_id)',
          );
          await db.execute(
            'ALTER TABLE technician_skills ADD COLUMN rated_at DATETIME',
          );
        }

        // 16. Create work_order_parts table
        final woPartsTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='work_order_parts'",
        );
        if (woPartsTable.isEmpty) {
          _log.i('Migration: Creating work_order_parts table...');
          await db.execute('''
            CREATE TABLE work_order_parts (
              wo_part_id TEXT PRIMARY KEY,
              wo_id      TEXT NOT NULL REFERENCES work_orders(wo_id) ON DELETE CASCADE,
              part_id    TEXT NOT NULL REFERENCES spare_parts(part_id),
              quantity   REAL NOT NULL DEFAULT 1,
              created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
        }

        // 17. Create notifications table
        final notifTable = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='notifications'",
        );
        if (notifTable.isEmpty) {
          _log.i('Migration: Creating notifications table...');
          await db.execute('''
            CREATE TABLE notifications (
              id TEXT PRIMARY KEY,
              user_id TEXT NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
              title TEXT NOT NULL,
              message TEXT,
              type TEXT,
              related_id TEXT,
              is_read INTEGER NOT NULL DEFAULT 0,
              created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
        }

        // 18. Add fuel/gas consumption columns to machine_specs
        final msColumns = await db.rawQuery(
          "PRAGMA table_info('machine_specs')",
        );
        if (!msColumns.any((c) => c['name'] == 'fuel_consumption_rate')) {
          _log.i('Migration: Adding fuel columns to machine_specs table...');
          await db.execute(
            'ALTER TABLE machine_specs ADD COLUMN fuel_consumption_rate REAL;',
          );
          await db.execute(
            'ALTER TABLE machine_specs ADD COLUMN fuel_type TEXT;',
          );

          // Migration for default_workers
          var specCols3 = await db.rawQuery(
            "PRAGMA table_info('machine_specs');",
          );
          bool hasDefaultWorkers = specCols3.any(
            (col) => col['name'] == 'default_workers',
          );
          if (!hasDefaultWorkers) {
            await db.execute(
              'ALTER TABLE machine_specs ADD COLUMN default_workers INTEGER;',
            );
          }
        }
      }

      await _ensureFileAssetsSchema(db);
      await _ensureKnowledgeVectorsSchema(db);
      await _ensureAiChatHistorySchema(db);
      await _ensureWorkOrderRcaSchema(db);
      await _backfillLegacyFileAssets(db);
      await _migrateLegacyFileAssetsToManagedStorage(db);

      return true;
    } catch (e) {
      _log.e('Failed to initialize database: $e');
      return false;
    }
  }

  static Future<void> setupFreshDatabase(
    Database db, {
    required String adminUsername,
    required String adminPasswordHash,
    required String approvalPinHash,
    String? companyName,
    String? serialKey,
    String? orgLogoBase64,
  }) async {
    await _createSchema(db);
    await _seedInitialData(db);

    final normalizedUsername = adminUsername.trim();
    final normalizedCompany = companyName?.trim() ?? '';
    final normalizedSerial = serialKey?.trim() ?? '';
    final normalizedLogo = orgLogoBase64?.trim() ?? '';

    await db.transaction((txn) async {
      if (normalizedCompany.isNotEmpty) {
        await txn.rawUpdate(
          '''
          UPDATE app_settings
          SET setting_value = ?, updated_at = CURRENT_TIMESTAMP
          WHERE setting_key = 'app.company_name'
          ''',
          [normalizedCompany],
        );
      }

      if (normalizedSerial.isNotEmpty) {
        await txn.rawInsert(
          '''
          INSERT INTO app_settings(setting_key, setting_value, description, updated_at)
          VALUES ('app.serial_key', ?, 'Serial License Key', CURRENT_TIMESTAMP)
          ON CONFLICT(setting_key) DO UPDATE SET
            setting_value = excluded.setting_value,
            description = excluded.description,
            updated_at = CURRENT_TIMESTAMP
          ''',
          [normalizedSerial],
        );
      }

      if (normalizedLogo.isNotEmpty) {
        await txn.rawInsert(
          '''
          INSERT INTO app_settings(setting_key, setting_value, description, updated_at)
          VALUES ('org_logo', ?, 'Organization logo as base64', CURRENT_TIMESTAMP)
          ON CONFLICT(setting_key) DO UPDATE SET
            setting_value = excluded.setting_value,
            description = excluded.description,
            updated_at = CURRENT_TIMESTAMP
          ''',
          [normalizedLogo],
        );
      }

      await txn.rawUpdate(
        '''
        UPDATE users
        SET employee_no = ?,
            username = ?,
            full_name = ?,
            password_hash = ?,
            approval_pin_hash = ?,
            updated_at = CURRENT_TIMESTAMP
        WHERE user_id = ?
        ''',
        [
          _defaultAdminEmployeeNo,
          normalizedUsername,
          'System Administrator',
          adminPasswordHash,
          approvalPinHash,
          _defaultAdminUserId,
        ],
      );

      await txn.rawInsert(
        '''
        INSERT OR IGNORE INTO users(
          user_id, employee_no, username, full_name, email, role, dept_id,
          password_hash, approval_pin_hash, theme_preference, is_active
        ) VALUES (?, ?, ?, ?, ?, 'admin', ?, ?, ?, 'dark', 1)
        ''',
        [
          _defaultAdminUserId,
          _defaultAdminEmployeeNo,
          normalizedUsername,
          'System Administrator',
          'admin@masapp.local',
          _defaultAdminDeptId,
          adminPasswordHash,
          approvalPinHash,
        ],
      );
    });
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
        'machine_snapshots',
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

  static Future<void> _ensureFileAssetsSchema(Database db) async {
    final table = await db.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: ['table', 'file_assets'],
    );

    if (table.isEmpty) {
      _log.i('Migration: Creating file_assets table...');
      await db.execute('''
        CREATE TABLE file_assets (
          asset_id        TEXT PRIMARY KEY,
          module_type     TEXT NOT NULL,
          entity_id       TEXT NOT NULL,
          category        TEXT NOT NULL DEFAULT 'attachment',
          display_name    TEXT NOT NULL,
          source_path     TEXT NOT NULL,
          storage_path    TEXT NOT NULL,
          preview_path    TEXT,
          thumbnail_path  TEXT,
          mime_type       TEXT,
          file_ext        TEXT,
          file_size       INTEGER,
          width           INTEGER,
          height          INTEGER,
          page_count      INTEGER,
          is_primary      INTEGER NOT NULL DEFAULT 0,
          created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
    }

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_file_assets_entity ON file_assets(module_type, entity_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_file_assets_category ON file_assets(category)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_file_assets_unique_path ON file_assets(module_type, entity_id, storage_path)',
    );
  }

  static Future<void> _ensureKnowledgeVectorsSchema(Database db) async {
    final table = await db.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: ['table', 'knowledge_vectors'],
    );

    if (table.isEmpty) {
      _log.i('Migration: Creating knowledge_vectors table...');
      await db.execute('''
        CREATE TABLE knowledge_vectors (
          vector_id      TEXT PRIMARY KEY,
          source_type    TEXT NOT NULL,
          source_id      TEXT,
          title          TEXT NOT NULL,
          category       TEXT,
          content_chunk  TEXT NOT NULL,
          embedding_json TEXT NOT NULL,
          metadata_json  TEXT,
          created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
    }

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_knowledge_vectors_source ON knowledge_vectors(source_type, source_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_knowledge_vectors_category ON knowledge_vectors(category)',
    );
  }

  static Future<void> _ensureAiChatHistorySchema(Database db) async {
    final table = await db.query(
      'sqlite_master',
      where: 'type = ? AND name = ?',
      whereArgs: ['table', 'ai_chat_history'],
    );

    if (table.isEmpty) {
      _log.i('Migration: Creating ai_chat_history table...');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ai_chat_history (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id  TEXT NOT NULL,
          user_id     TEXT,
          role        TEXT NOT NULL CHECK(role IN ('user', 'assistant', 'tool')),
          content     TEXT NOT NULL,
          tool_calls  TEXT,
          created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
      ''');
    }

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_ai_chat_session ON ai_chat_history(session_id, created_at)',
    );
  }

  static Future<void> _backfillLegacyFileAssets(Database db) async {
    await _backfillHandoverAttachments(db);
    await _backfillWorkOrderAttachments(db);
    await _backfillSparePartImages(db);
    await _backfillToolImages(db);
  }

  static Future<void> _migrateLegacyFileAssetsToManagedStorage(
    Database db,
  ) async {
    final alreadyMigrated = await _readAppSetting(
      db,
      _legacyFileMigrationSettingKey,
    );
    if (alreadyMigrated == 'true') {
      return;
    }

    final storageService = AttachmentStorageService.instance;
    final rows = await db.rawQuery('''
      SELECT
        asset_id,
        module_type,
        entity_id,
        category,
        display_name,
        source_path,
        storage_path,
        mime_type,
        is_primary
      FROM file_assets
      ORDER BY created_at ASC
    ''');

    var migratedCount = 0;
    var failedCount = 0;

    for (final row in rows) {
      final assetId = row['asset_id']?.toString() ?? '';
      final moduleType = row['module_type']?.toString() ?? '';
      final entityId = row['entity_id']?.toString() ?? '';
      final category = row['category']?.toString() ?? 'attachment';
      final displayName = row['display_name']?.toString() ?? '';
      final currentStoragePath = row['storage_path']?.toString().trim() ?? '';
      final sourcePath = row['source_path']?.toString().trim() ?? '';
      final lookupPath = sourcePath.isNotEmpty
          ? sourcePath
          : currentStoragePath;

      if (assetId.isEmpty ||
          moduleType.isEmpty ||
          entityId.isEmpty ||
          lookupPath.isEmpty ||
          storageService.looksManagedPath(currentStoragePath)) {
        continue;
      }

      try {
        final migrated = await storageService.migrateLegacyFile(
          moduleType: moduleType,
          entityId: entityId,
          sourcePath: lookupPath,
          displayName: displayName,
          category: category,
          isPrimary: (row['is_primary'] as num?)?.toInt() == 1,
          mimeType: row['mime_type']?.toString(),
          storageRootPath: db.path,
        );

        await db.update(
          'file_assets',
          {
            'display_name': migrated.displayName,
            'storage_path': migrated.storagePath,
            'preview_path': migrated.previewPath,
            'thumbnail_path': migrated.thumbnailPath,
            'mime_type': migrated.mimeType,
            'file_ext': p.extension(migrated.storagePath).toLowerCase(),
            'file_size': migrated.fileSize,
            'width': migrated.width,
            'height': migrated.height,
            'page_count': migrated.pageCount,
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'asset_id = ?',
          whereArgs: [assetId],
        );

        await _rewriteLegacyAssetReferences(
          db,
          moduleType: moduleType,
          entityId: entityId,
          oldPath: currentStoragePath,
          newPath: migrated.storagePath,
          displayName: migrated.displayName,
          fileSize: migrated.fileSize,
          mimeType: migrated.mimeType,
        );

        migratedCount++;
      } catch (e) {
        failedCount++;
        _log.w('Legacy asset migration skipped for $lookupPath: $e');
      }
    }

    if (failedCount == 0) {
      await _writeAppSetting(db, _legacyFileMigrationSettingKey, 'true');
    }

    _log.i(
      'Legacy file asset migration complete: migrated=$migratedCount failed=$failedCount',
    );
  }

  static Future<void> _backfillHandoverAttachments(Database db) async {
    final rows = await db.rawQuery('''
      SELECT handover_id, file_name, file_path, file_size, mime_type, uploaded_at
      FROM handover_attachments
      WHERE file_path IS NOT NULL AND TRIM(file_path) != ''
    ''');

    for (final row in rows) {
      final path = row['file_path']?.toString().trim() ?? '';
      if (path.isEmpty) continue;

      await _insertLegacyAsset(
        db,
        moduleType: 'machine_handover',
        entityId: row['handover_id']?.toString() ?? '',
        category: 'attachment',
        displayName: row['file_name']?.toString().trim().isNotEmpty == true
            ? row['file_name']!.toString().trim()
            : p.basename(path),
        sourcePath: path,
        storagePath: path,
        mimeType: row['mime_type']?.toString(),
        fileSize: (row['file_size'] as num?)?.toInt(),
        createdAt: row['uploaded_at']?.toString(),
        updatedAt: row['uploaded_at']?.toString(),
      );
    }
  }

  static Future<void> _backfillWorkOrderAttachments(Database db) async {
    final rows = await db.rawQuery('''
      SELECT wo_id, attachments, created_at, updated_at
      FROM work_orders
      WHERE attachments IS NOT NULL AND TRIM(attachments) != ''
    ''');

    for (final row in rows) {
      final entityId = row['wo_id']?.toString() ?? '';
      if (entityId.isEmpty) continue;

      final raw = row['attachments']?.toString() ?? '';
      if (raw.trim().isEmpty) continue;

      List<dynamic> paths;
      try {
        paths = jsonDecode(raw) as List<dynamic>;
      } catch (_) {
        continue;
      }

      for (final entry in paths) {
        final path = entry?.toString().trim() ?? '';
        if (path.isEmpty) continue;

        await _insertLegacyAsset(
          db,
          moduleType: 'work_order',
          entityId: entityId,
          category: 'attachment',
          displayName: p.basename(path),
          sourcePath: path,
          storagePath: path,
          createdAt: row['created_at']?.toString(),
          updatedAt: row['updated_at']?.toString(),
        );
      }
    }
  }

  static Future<void> _backfillSparePartImages(Database db) async {
    final rows = await db.rawQuery('''
      SELECT part_id, part_name, image_path, created_at
      FROM spare_parts
      WHERE image_path IS NOT NULL AND TRIM(image_path) != ''
    ''');

    for (final row in rows) {
      final path = row['image_path']?.toString().trim() ?? '';
      final entityId = row['part_id']?.toString() ?? '';
      if (path.isEmpty || entityId.isEmpty) continue;

      await _insertLegacyAsset(
        db,
        moduleType: 'spare_part',
        entityId: entityId,
        category: 'image',
        displayName: row['part_name']?.toString().trim().isNotEmpty == true
            ? row['part_name']!.toString().trim()
            : p.basename(path),
        sourcePath: path,
        storagePath: path,
        isPrimary: true,
        createdAt: row['created_at']?.toString(),
        updatedAt: row['created_at']?.toString(),
      );
    }
  }

  static Future<void> _backfillToolImages(Database db) async {
    final rows = await db.rawQuery('''
      SELECT tool_id, tool_name, image_path, created_at
      FROM tools
      WHERE image_path IS NOT NULL AND TRIM(image_path) != ''
    ''');

    for (final row in rows) {
      final path = row['image_path']?.toString().trim() ?? '';
      final entityId = row['tool_id']?.toString() ?? '';
      if (path.isEmpty || entityId.isEmpty) continue;

      await _insertLegacyAsset(
        db,
        moduleType: 'tool',
        entityId: entityId,
        category: 'image',
        displayName: row['tool_name']?.toString().trim().isNotEmpty == true
            ? row['tool_name']!.toString().trim()
            : p.basename(path),
        sourcePath: path,
        storagePath: path,
        isPrimary: true,
        createdAt: row['created_at']?.toString(),
        updatedAt: row['created_at']?.toString(),
      );
    }
  }

  static Future<void> _insertLegacyAsset(
    Database db, {
    required String moduleType,
    required String entityId,
    required String category,
    required String displayName,
    required String sourcePath,
    required String storagePath,
    String? mimeType,
    int? fileSize,
    bool isPrimary = false,
    String? createdAt,
    String? updatedAt,
  }) async {
    if (moduleType.isEmpty || entityId.isEmpty || storagePath.trim().isEmpty) {
      return;
    }

    final path = storagePath.trim();
    final ext = p.extension(path).toLowerCase();
    final resolvedMimeType = (mimeType?.trim().isNotEmpty ?? false)
        ? mimeType!.trim()
        : _guessMimeType(ext);

    final metadata = <String, Object?>{
      'asset_id': const Uuid().v4(),
      'module_type': moduleType,
      'entity_id': entityId,
      'category': category,
      'display_name': displayName.trim().isNotEmpty
          ? displayName.trim()
          : p.basename(path),
      'source_path': sourcePath.trim().isNotEmpty ? sourcePath.trim() : path,
      'storage_path': path,
      'mime_type': resolvedMimeType,
      'file_ext': ext,
      'file_size': _resolveLegacyFileSize(path, fileSize),
      'is_primary': isPrimary ? 1 : 0,
    };

    if (createdAt != null && createdAt.trim().isNotEmpty) {
      metadata['created_at'] = createdAt.trim();
    }
    if (updatedAt != null && updatedAt.trim().isNotEmpty) {
      metadata['updated_at'] = updatedAt.trim();
    }

    await db.insert(
      'file_assets',
      metadata,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<void> _rewriteLegacyAssetReferences(
    Database db, {
    required String moduleType,
    required String entityId,
    required String oldPath,
    required String newPath,
    required String displayName,
    required int fileSize,
    required String mimeType,
  }) async {
    if (oldPath.trim().isEmpty || newPath.trim().isEmpty) return;

    switch (moduleType) {
      case 'machine_handover':
        await db.rawUpdate(
          '''
          UPDATE handover_attachments
          SET file_path = ?,
              file_name = ?,
              file_size = ?,
              mime_type = ?
          WHERE handover_id = ?
            AND file_path = ?
          ''',
          [newPath, displayName, fileSize, mimeType, entityId, oldPath],
        );
        break;
      case 'work_order':
        final row = await db.rawQuery(
          'SELECT attachments FROM work_orders WHERE wo_id = ? LIMIT 1',
          [entityId],
        );
        if (row.isEmpty) break;

        final raw = row.first['attachments']?.toString() ?? '';
        if (raw.trim().isEmpty) break;

        try {
          final items = List<String>.from(jsonDecode(raw) as List);
          var changed = false;
          final updated = items.map((item) {
            if (item.trim() == oldPath.trim()) {
              changed = true;
              return newPath;
            }
            return item;
          }).toList();

          if (changed) {
            await db.rawUpdate(
              '''
              UPDATE work_orders
              SET attachments = ?, updated_at = CURRENT_TIMESTAMP
              WHERE wo_id = ?
              ''',
              [jsonEncode(updated), entityId],
            );
          }
        } catch (_) {}
        break;
      case 'spare_part':
        await db.rawUpdate(
          '''
          UPDATE spare_parts
          SET image_path = ?
          WHERE part_id = ?
            AND image_path = ?
          ''',
          [newPath, entityId, oldPath],
        );
        break;
      case 'tool':
        await db.rawUpdate(
          '''
          UPDATE tools
          SET image_path = ?
          WHERE tool_id = ?
            AND image_path = ?
          ''',
          [newPath, entityId, oldPath],
        );
        break;
    }
  }

  static Future<String?> _readAppSetting(Database db, String key) async {
    final rows = await db.rawQuery(
      'SELECT setting_value FROM app_settings WHERE setting_key = ? LIMIT 1',
      [key],
    );
    if (rows.isEmpty) return null;
    final value = rows.first['setting_value']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static Future<void> _writeAppSetting(
    Database db,
    String key,
    String value,
  ) async {
    await db.rawInsert(
      '''
      INSERT INTO app_settings(setting_key, setting_value, description, updated_at)
      VALUES (?, ?, ?, CURRENT_TIMESTAMP)
      ON CONFLICT(setting_key) DO UPDATE SET
        setting_value = excluded.setting_value,
        description = excluded.description,
        updated_at = CURRENT_TIMESTAMP
      ''',
      [
        key,
        value,
        'Internal migration marker for legacy managed storage rewrite',
      ],
    );
  }

  static int? _resolveLegacyFileSize(String path, int? fallback) {
    if (fallback != null && fallback > 0) return fallback;

    try {
      final file = File(path);
      if (file.existsSync()) {
        return file.lengthSync();
      }
    } catch (_) {}

    return fallback;
  }

  static String _guessMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
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

  static Future<void> _ensureWorkOrderRcaSchema(Database db) async {
    try {
      final rcaTable = await db.query(
        'sqlite_master',
        where: 'type = ? AND name = ?',
        whereArgs: ['table', 'work_order_rca'],
      );
      if (rcaTable.isNotEmpty) {
        final cols = await db.rawQuery("PRAGMA table_info('work_order_rca');");
        if (!cols.any((col) => col['name'] == 'cause_category')) {
          _log.i('Migration: Adding cause_category to work_order_rca...');
          await db.execute('ALTER TABLE work_order_rca ADD COLUMN cause_category TEXT;');
        }
      }
    } catch (e) {
      _log.e('Failed to ensure work_order_rca schema: $e');
    }
  }
}
