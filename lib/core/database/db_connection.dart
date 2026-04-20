import 'dart:async';
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../config/app_config.dart';
import 'package:logger/logger.dart';
import 'db_initializer.dart';

final _log = Logger();

/// Singleton SQLite database connection for MASAPP.
///
/// **CRITICAL for Shared LAN Database:**
/// - Enables WAL (Write-Ahead Logging) mode for multi-client concurrency
/// - Sets busy timeout to allow clients to wait if DB is locked
/// - Uses transactions for multi-step operations
/// - Properly manages connection lifecycle
class DbConnection {
  static DbConnection? _instance;
  static Database? _db;

  static bool _ffiInitialized = false;
  DbConnection._();

  static DbConnection get instance => _instance ??= DbConnection._();

  bool get isConnected => _db != null;

  /// Initialize the SQLite database connection with LAN optimization.
  ///
  /// **Enables:**
  /// 1. WAL mode: Allows readers to work while writers are active
  /// 2. Busy timeout: Clients wait up to 5000ms instead of immediate "database locked" error
  /// 3. Foreign key constraints
  /// 4. Synchronous mode optimized for network shares
  Future<void> connect(AppConfig config) async {
    await _db?.close();

    // Initialize FFI for Desktop only once
    if (Platform.isWindows || Platform.isLinux) {
      if (!_ffiInitialized) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
        _ffiInitialized = true;
      }
    }

    _log.i('Connecting to database: ${config.dbPath}');

    _db = await databaseFactory.openDatabase(
      config.dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          // Enable foreign keys
          await db.execute('PRAGMA foreign_keys = ON');

          // **CRITICAL: Enable WAL mode for multi-client support**
          // WAL (Write-Ahead Logging) allows multiple readers while writing
          await db.execute('PRAGMA journal_mode = WAL');

          // **CRITICAL: Set busy timeout for network shares**
          // If DB is locked, wait up to 5 seconds instead of immediate error
          await db.execute('PRAGMA busy_timeout = 5000');

          // Optimize for network file shares (less aggressive sync)
          // NORMAL = fsync only after transaction commit (good for network)
          await db.execute('PRAGMA synchronous = NORMAL');

          // Cache size for better performance
          await db.execute('PRAGMA cache_size = -64000'); // 64MB

          _log.i('Database PRAGMAs configured for LAN mode');
        },
        onOpen: (db) async {
          _log.i('Database connection opened successfully');
          // [TEMPORARY WIPE] Remove after one run
          // await DbInitializer.wipeMachineData(db); 
          
          await DbInitializer.initializeDatabase(db);
        },
      ),
    );
  }

  /// Close the connection.
  Future<void> disconnect() async {
    _log.i('Closing database connection');
    await _db?.close();
    _db = null;
  }

  /// Test connectivity (checks if file exists or can be opened).
  /// Does NOT modify any PRAGMAs—just tests basic connectivity.
  Future<bool> testConnection(AppConfig config) async {
    try {
      if (Platform.isWindows || Platform.isLinux) {
        if (!_ffiInitialized) {
          sqfliteFfiInit();
          databaseFactory = databaseFactoryFfi;
          _ffiInitialized = true;
        }
      }
      final db = await databaseFactory.openDatabase(
        config.dbPath,
        options: OpenDatabaseOptions(readOnly: true),
      );
      await db.query('sqlite_master', limit: 1);
      await db.close();
      return true;
    } catch (e) {
      _log.e('Database test failed: $e');
      return false;
    }
  }

  /// Returns the Database instance; throws if not connected.
  Database get db {
    final d = _db;
    if (d == null) {
      throw StateError('DB not connected. Call DbConnection.connect() first.');
    }
    return d;
  }

  /// Get database file size in MB (useful for backup monitoring)
  Future<double?> getDbFileSizeMB() async {
    try {
      final file = File(_db?.path ?? '');
      if (await file.exists()) {
        final sizeInBytes = await file.length();
        return sizeInBytes / (1024 * 1024);
      }
    } catch (_) {}
    return null;
  }
}
