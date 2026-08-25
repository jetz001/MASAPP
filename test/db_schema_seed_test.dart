import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:masapp/core/database/db_initializer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Database Schema & Seed Verification', () {
    late Database db;
    late String tempDbPath;

    setUp(() async {
      final tempDir = Directory.systemTemp.createTempSync('masapp_test_');
      tempDbPath = '${tempDir.path}\\test_masapp.db';
      db = await databaseFactory.openDatabase(
        tempDbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
        ),
      );
    });

    tearDown(() async {
      await db.close();
      try {
        final f = File(tempDbPath);
        if (f.existsSync()) f.deleteSync();
        final dir = f.parent;
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('Fresh Database Setup runs without error and creates all tables', () async {
      // 1. Setup fresh database
      await DbInitializer.setupFreshDatabase(
        db,
        adminUsername: 'testadmin',
        adminPasswordHash: 'hash123',
        approvalPinHash: 'pin123',
        companyName: 'Test Corp',
        serialKey: 'TEST-KEY',
      );

      // 2. Verify tables exist
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      );
      final tableNames = tables.map((t) => t['name'] as String).toSet();

      expect(tableNames.contains('departments'), isTrue);
      expect(tableNames.contains('users'), isTrue);
      expect(tableNames.contains('machine_categories'), isTrue);
      expect(tableNames.contains('machines'), isTrue);
      expect(tableNames.contains('work_orders'), isTrue);
      expect(tableNames.contains('work_permits'), isTrue);
      expect(tableNames.contains('spare_parts'), isTrue);
      expect(tableNames.contains('knowledge_vectors'), isTrue);
      expect(tableNames.contains('ai_chat_history'), isTrue);
      expect(tableNames.contains('app_settings'), isTrue);

      // 3. Verify admin user was updated
      final adminUsers = await db.query(
        'users',
        where: 'username = ?',
        whereArgs: ['testadmin'],
      );
      expect(adminUsers.isNotEmpty, isTrue);
      expect(adminUsers.first['role'], equals('admin'));
      expect(adminUsers.first['password_hash'], equals('hash123'));

      // 4. Verify seed data exists
      final depts = await db.query('departments');
      expect(depts.isNotEmpty, isTrue);

      final vectors = await db.query('knowledge_vectors');
      expect(vectors.isNotEmpty, isTrue);
    });

    test('Idempotency: Re-running initialization on existing database succeeds', () async {
      await DbInitializer.setupFreshDatabase(
        db,
        adminUsername: 'admin',
        adminPasswordHash: 'hash',
        approvalPinHash: 'pin',
      );

      // Re-run standard initializeDatabase
      final result = await DbInitializer.initializeDatabase(db);
      expect(result, isTrue);
    });
  });
}
