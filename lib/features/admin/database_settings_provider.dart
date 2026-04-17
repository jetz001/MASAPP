import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../core/database/db_connection.dart';
import '../../core/database/db_initializer.dart';
import 'package:logger/logger.dart';

final _log = Logger();

/// Provider for current app configuration
final appConfigProvider = StateNotifierProvider<AppConfigNotifier, AppConfig>((
  ref,
) {
  return AppConfigNotifier();
});

class AppConfigNotifier extends StateNotifier<AppConfig> {
  AppConfigNotifier()
    : super(AppConfig(dbPath: 'masapp.db', isNetworkMode: false)) {
    _initialize();
  }

  Future<void> _initialize() async {
    final config = await AppConfigService.load();
    if (config != null) {
      state = config;
    }
  }

  Future<bool> updateDbPath(String newPath) async {
    try {
      final newConfig = state.copyWith(dbPath: newPath);

      // Validate path
      if (!await newConfig.validateDbPath()) {
        _log.e('Invalid path: $newPath');
        return false;
      }

      // Test connection
      if (!await DbConnection.instance.testConnection(newConfig)) {
        _log.e('Cannot connect to database at: $newPath');
        return false;
      }

      // Disconnect from old database
      await DbConnection.instance.disconnect();

      // Update config
      state = newConfig;
      await AppConfigService.save(newConfig);

      // Reconnect with new config
      await DbConnection.instance.connect(newConfig);

      return true;
    } catch (e) {
      _log.e('Error updating database path: $e');
      return false;
    }
  }

  Future<bool> updateSharedFolderPath(String newPath) async {
    try {
      final dir = await Directory(newPath).exists();
      if (!dir) {
        _log.e('Shared folder does not exist: $newPath');
        return false;
      }

      state = state.copyWith(sharedFolderPath: newPath);
      await AppConfigService.save(state);
      return true;
    } catch (e) {
      _log.e('Error updating shared folder path: $e');
      return false;
    }
  }

  Future<bool> createBackup() async {
    try {
      final result = await DbInitializer.createBackup(state.dbPath);
      return result;
    } catch (e) {
      _log.e('Error creating backup: $e');
      return false;
    }
  }
}

/// Provider for list of recent backups
final recentBackupsProvider = FutureProvider<List<FileInfo>>((ref) async {
  final config = ref.watch(appConfigProvider);
  final backups = await DbInitializer.getBackups(config.dbPath);
  return backups
      .map(
        (f) => FileInfo(
          path: f.path,
          name: f.path.split('\\').last,
          sizeMB: f.lengthSync() / (1024 * 1024),
          modifiedAt: f.statSync().modified,
        ),
      )
      .toList();
});

class FileInfo {
  final String path;
  final String name;
  final double sizeMB;
  final DateTime modifiedAt;

  FileInfo({
    required this.path,
    required this.name,
    required this.sizeMB,
    required this.modifiedAt,
  });
}
