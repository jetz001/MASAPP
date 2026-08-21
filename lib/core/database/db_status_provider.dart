import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_config.dart';
import 'db_connection.dart';

class DbStatusState {
  final bool isConnected;
  final String? dbPath;
  final String? errorMessage;
  final bool isNetworkPath;
  final bool isRetrying;

  const DbStatusState({
    this.isConnected = false,
    this.dbPath,
    this.errorMessage,
    this.isNetworkPath = false,
    this.isRetrying = false,
  });

  DbStatusState copyWith({
    bool? isConnected,
    String? dbPath,
    String? errorMessage,
    bool? isNetworkPath,
    bool? isRetrying,
  }) {
    return DbStatusState(
      isConnected: isConnected ?? this.isConnected,
      dbPath: dbPath ?? this.dbPath,
      errorMessage: errorMessage,
      isNetworkPath: isNetworkPath ?? this.isNetworkPath,
      isRetrying: isRetrying ?? this.isRetrying,
    );
  }
}

class DbStatusNotifier extends StateNotifier<DbStatusState> {
  DbStatusNotifier() : super(const DbStatusState());

  void setConnected(String path) {
    state = DbStatusState(
      isConnected: true,
      dbPath: path,
      isNetworkPath: DbConnection.isNetworkPath(path),
      errorMessage: null,
      isRetrying: false,
    );
  }

  void setError(String path, dynamic error) {
    final errStr = error.toString();
    String friendlyMessage = 'เกิดข้อผิดพลาดในการเชื่อมต่อฐานข้อมูล';

    if (errStr.contains('3338') ||
        errStr.contains('266') ||
        errStr.contains('not ready') ||
        errStr.contains('disk I/O error')) {
      friendlyMessage =
          'ไดรฟ์เครือข่ายหรือเซิร์ฟเวอร์ไม่พร้อมใช้งาน (Server / Disk Offline หรือยังไม่ได้เสียบไดรฟ์ Z:)';
    } else if (errStr.contains('no such table') || errStr.contains('corrupt')) {
      friendlyMessage = 'โครงสร้างไฟล์ฐานข้อมูลไม่สมบูรณ์หรือชำรุด';
    } else if (errStr.contains('PathNotFound') || errStr.contains('Cannot find path')) {
      friendlyMessage = 'ไม่พบโฟลเดอร์หรือตำแหน่งไฟล์ฐานข้อมูลที่ระบุ';
    } else if (errStr.contains('Access is denied') || errStr.contains('Permission')) {
      friendlyMessage = 'ไม่มีสิทธิ์เข้าถึงโฟลเดอร์เครือข่ายปลายทาง (Permission Denied)';
    }

    state = DbStatusState(
      isConnected: false,
      dbPath: path,
      isNetworkPath: DbConnection.isNetworkPath(path),
      errorMessage: friendlyMessage,
      isRetrying: false,
    );
  }

  Future<bool> retryConnect() async {
    state = state.copyWith(isRetrying: true);
    final config = await AppConfigService.load();
    if (config == null) {
      state = state.copyWith(isRetrying: false);
      return false;
    }

    try {
      await DbConnection.instance.connect(
        config,
        skipInitialization: DbConnection.isNetworkPath(config.dbPath),
      );
      setConnected(config.dbPath);
      return true;
    } catch (e) {
      setError(config.dbPath, e);
      return false;
    }
  }

  Future<void> switchToLocal() async {
    state = state.copyWith(isRetrying: true);
    final localConfig = await AppConfig.createDefault();
    await AppConfigService.save(localConfig);
    try {
      await DbConnection.instance.connect(localConfig);
      setConnected(localConfig.dbPath);
    } catch (e) {
      setError(localConfig.dbPath, e);
    }
  }
}

final dbStatusProvider =
    StateNotifierProvider<DbStatusNotifier, DbStatusState>((ref) {
  return DbStatusNotifier();
});
