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

    final resolvedDbPath = _resolveDatabasePath(config.dbPath);
    _log.i('Connecting to database: $resolvedDbPath');

    _db = await databaseFactory.openDatabase(
      resolvedDbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          // Enable foreign keys
          await db.execute('PRAGMA foreign_keys = ON');

          // **CRITICAL: Set busy timeout FIRST**
          // Must be set before any potentially-blocking operations
          await db.execute('PRAGMA busy_timeout = 5000');

          // WAL mode: allows multiple readers while a writer is active.
          // However, WAL requires OS-level shared memory and does NOT work
          // on network file shares (UNC paths like \\server\share or mapped
          // network drives). We detect this and fall back to DELETE mode.
          final isNetworkPath = _isNetworkPath(resolvedDbPath);
          if (isNetworkPath) {
            // DELETE mode: safe for network shares (no shared memory needed)
            await db.execute('PRAGMA journal_mode = DELETE');
            _log.w(
              'Network path detected — WAL disabled, using DELETE journal mode',
            );
          } else {
            // Local disk: use WAL for best multi-client concurrency
            try {
              await db.execute('PRAGMA journal_mode = WAL');
            } catch (e) {
              // Fallback in case WAL still fails (e.g. FS limitation)
              _log.w(
                'WAL mode failed ($e), falling back to DELETE journal mode',
              );
              await db.execute('PRAGMA journal_mode = DELETE');
            }
          }

          // Optimize sync strategy
          // NORMAL on network, FULL on local (safer for WAL)
          await db.execute(
            isNetworkPath
                ? 'PRAGMA synchronous = FULL' // safer for network
                : 'PRAGMA synchronous = NORMAL', // faster for local+WAL
          );

          // Cache size for better performance
          await db.execute('PRAGMA cache_size = -64000'); // 64MB

          _log.i('Database PRAGMAs configured (network=$isNetworkPath)');
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
      final resolvedDbPath = _resolveDatabasePath(config.dbPath);
      final db = await databaseFactory.openDatabase(
        resolvedDbPath,
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

  /// Detects whether [path] points to a network file system.
  ///
  /// Handles:
  /// - UNC paths: `\\server\share\...`
  /// - Forward-slash UNC: `//server/share/...`
  /// - Windows mapped network drives: detected via GetDriveTypeW (type = 4)
  static bool _isNetworkPath(String path) {
    // UNC paths always start with \\ or //
    if (path.startsWith(r'\\') || path.startsWith('//')) return true;

    if (Platform.isWindows && path.length >= 2 && path[1] == ':') {
      try {
        if (_getDriveDisplayRoot(path.substring(0, 2)).isNotEmpty) return true;
        // GetDriveTypeW returns 4 for DRIVE_REMOTE (network drives)
        final drivePath = '${path.substring(0, 2)}\\';
        final result = _getDriveType(drivePath);
        if (result == 4) return true; // DRIVE_REMOTE
      } catch (_) {
        // If the syscall fails, assume local to avoid breaking local setups
      }
    }
    return false;
  }

  /// Resolves mapped network drives like `Y:\folder\db.sqlite` to UNC paths.
  static String _resolveDatabasePath(String path) {
    if (!Platform.isWindows || path.length < 2 || path[1] != ':') return path;

    final displayRoot = _getDriveDisplayRoot(path.substring(0, 2));
    if (displayRoot.isEmpty) return path;

    final relativePath = path.substring(2).replaceAll('/', '\\');
    if (relativePath.isEmpty) return displayRoot;
    return '$displayRoot$relativePath';
  }

  /// Returns the UNC root for a mapped Windows drive, or an empty string.
  static String _getDriveDisplayRoot(String driveLetter) {
    if (!Platform.isWindows) return '';
    try {
      final result = Process.runSync('powershell', [
        '-NoProfile',
        '-Command',
        '(Get-PSDrive -Name "${driveLetter[0]}" -ErrorAction SilentlyContinue).DisplayRoot',
      ], runInShell: false);
      final output = result.stdout.toString().trim();
      return output.startsWith(r'\\') ? output : '';
    } catch (_) {
      return '';
    }
  }

  /// Calls Win32 GetDriveTypeW to determine the drive type.
  /// Returns: 1=unknown, 2=removable, 3=fixed, 4=remote(network), 5=cdrom, 6=ramdisk
  static int _getDriveType(String drivePath) {
    if (!Platform.isWindows) return 3; // assume fixed on non-Windows
    try {
      // Use dart:ffi to call GetDriveTypeW
      // Simpler approach: check via ProcessResult
      final result = Process.runSync('powershell', [
        '-NoProfile',
        '-Command',
        '(New-Object -ComObject Scripting.FileSystemObject).GetDrive("${drivePath.replaceAll("\\", "\\\\")}").DriveType',
      ], runInShell: false);
      // FSO DriveType: 0=unknown,1=removable,2=fixed,3=network,4=cdrom,5=ramdisk
      final fsoType = int.tryParse(result.stdout.toString().trim()) ?? 2;
      // Map FSO types to Win32: network = 3 in FSO → return 4 for our convention
      return fsoType == 3 ? 4 : fsoType;
    } catch (_) {
      return 3; // assume fixed
    }
  }
}
