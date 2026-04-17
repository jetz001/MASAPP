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

  static Future<Directory> _configDir() async {
    final appData = await getApplicationSupportDirectory();
    final dir = Directory('${appData.path}\\masapp');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _configFile() async {
    final dir = await _configDir();
    return File('${dir.path}\\$_configFileName');
  }

  /// Returns true if a saved config exists.
  static Future<bool> isConfigured() async {
    final file = await _configFile();
    return file.existsSync();
  }

  /// Loads config from disk (or returns null if not found).
  static Future<AppConfig?> load() async {
    if (_cached != null) return _cached;
    final file = await _configFile();
    if (!file.existsSync()) return null;
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
    final file = await _configFile();
    await file.writeAsString(jsonEncode(config.toJson()), flush: true);
    _cached = config;
  }

  static void clearCache() => _cached = null;
}
