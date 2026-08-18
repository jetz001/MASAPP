import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// Holds the SQLite database configuration for Serverless LAN deployment.
///
/// **Supports two modes:**
/// 1. **Local Mode**: Database file stored locally (for development/single-user)
/// 2. **Network Mode**: Database file on shared folder (\\\\192.168.1.50\\MaintenanceApp\\db.sqlite)
///
/// Configuration is persisted to %APPDATA%\\masapp\\config.json on startup.
class AppConfig {
  final String dbPath;
  final String? sharedFolderPath; // Optional: for shared drawings, documents
  final bool isNetworkMode;
  final String appVersion;

  const AppConfig({
    required this.dbPath,
    this.sharedFolderPath,
    this.isNetworkMode = false,
    this.appVersion = '1.0.0',
  });

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      dbPath: json['db_path'] as String? ?? 'masapp.db',
      sharedFolderPath: json['shared_folder_path'] as String?,
      isNetworkMode: json['is_network_mode'] as bool? ?? false,
      appVersion: json['app_version'] as String? ?? '1.0.0',
    );
  }

  Map<String, dynamic> toJson() => {
    'db_path': dbPath,
    'shared_folder_path': sharedFolderPath,
    'is_network_mode': isNetworkMode,
    'app_version': appVersion,
  };

  AppConfig copyWith({
    String? dbPath,
    String? sharedFolderPath,
    bool? isNetworkMode,
    String? appVersion,
  }) {
    return AppConfig(
      dbPath: dbPath ?? this.dbPath,
      sharedFolderPath: sharedFolderPath ?? this.sharedFolderPath,
      isNetworkMode: isNetworkMode ?? this.isNetworkMode,
      appVersion: appVersion ?? this.appVersion,
    );
  }

  /// Validates that the database path is accessible (file or directory exists).
  Future<bool> validateDbPath() async {
    try {
      final file = File(dbPath);
      final dir = file.parent;

      // Check if parent directory is accessible
      if (await dir.exists()) {
        return true;
      }

      // Try to create if it doesn't exist (for local mode)
      await dir.create(recursive: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Default config for development (local mode)
  static Future<AppConfig> createDefault() async {
    final docDir = await getApplicationDocumentsDirectory();
    final path = '${docDir.path}\\MASAPP\\masapp.db';
    return AppConfig(dbPath: path, isNetworkMode: false);
  }
}

class AppConfigService {
  static const _configFileName = 'config.json';
  static AppConfig? _cached;

  static Future<List<Directory>> _candidateConfigDirs() async {
    final dirs = <Directory>[];

    final appData = await getApplicationSupportDirectory();
    final normalizedAppData = appData.path.replaceAll('/', '\\').toLowerCase();
    final appDataDir = normalizedAppData.endsWith(r'\masapp')
        ? Directory(appData.path)
        : Directory('${appData.path}\\masapp');
    dirs.add(appDataDir);

    final documents = await getApplicationDocumentsDirectory();
    dirs.add(Directory('${documents.path}\\MASAPP'));
    dirs.add(Directory('${Directory.current.path}\\.masapp'));
    return dirs;
  }

  static Future<File?> _configFileForRead() async {
    for (final dir in await _candidateConfigDirs()) {
      try {
        final file = File('${dir.path}\\$_configFileName');
        if (await file.exists()) return file;
      } on FileSystemException {
        // Ignore inaccessible locations and try the next fallback.
      }
    }
    return null;
  }

  static Future<List<File>> _configFilesForWrite() async {
    final files = <File>[];
    for (final dir in await _candidateConfigDirs()) {
      files.add(File('${dir.path}\\$_configFileName'));
    }
    return files;
  }

  /// Returns true if a saved config exists.
  static Future<bool> isConfigured() async {
    final file = await _configFileForRead();
    return file != null;
  }

  /// Loads config from disk (or returns null if not found).
  static Future<AppConfig?> load() async {
    if (_cached != null) return _cached;
    final file = await _configFileForRead();
    if (file == null) return null;
    try {
      final contents = await file.readAsString();
      final json = jsonDecode(contents) as Map<String, dynamic>;
      _cached = AppConfig.fromJson(json);
      return _cached;
    } catch (_) {
      return null;
    }
  }

  /// Saves config to disk.
  static Future<void> save(AppConfig config) async {
    FileSystemException? lastError;
    final payload = jsonEncode(config.toJson());

    for (final file in await _configFilesForWrite()) {
      try {
        final dir = file.parent;
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        await file.writeAsString(payload, flush: true);
        _cached = config;
        return;
      } on FileSystemException catch (e) {
        lastError = e;
      }
    }

    if (lastError != null) throw lastError;
    throw const FileSystemException('Cannot resolve writable config directory');
  }

  static void clearCache() => _cached = null;
}
