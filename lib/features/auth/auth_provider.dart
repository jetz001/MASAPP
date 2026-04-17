import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logger/logger.dart';
import '../../core/config/app_config.dart';
import '../../core/database/db_connection.dart';
import '../../core/database/db_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Model
// ─────────────────────────────────────────────────────────────────────────────

class UserSession {
  final String userId;
  final String username;
  final String fullName;
  final String role;
  final String? deptId;
  final String sessionId;
  final String? ipAddress;
  final String? hostname;

  const UserSession({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.role,
    required this.sessionId,
    this.deptId,
    this.ipAddress,
    this.hostname,
  });

  bool get isAdmin => role == 'admin';
  bool get isEngineerOrAbove =>
      ['engineer', 'executive', 'admin'].contains(role);
  bool get isSafetyOrAbove =>
      ['safety', 'engineer', 'executive', 'admin'].contains(role);
  bool get isTechnicianOrAbove =>
      ['technician', 'safety', 'engineer', 'executive', 'admin'].contains(role);

  bool canWrite(String module) {
    if (role == 'admin') return true;
    if (role == 'executive') return false;
    if (role == 'engineer') return true;
    if (role == 'safety') {
      return ['work_permit', 'work_orders'].contains(module);
    }
    if (role == 'technician') {
      return ['work_orders', 'pm_am', 'spare_parts'].contains(module);
    }
    if (role == 'operator') return ['pm_am'].contains(module);
    return false;
  }

  String get roleDisplayName {
    const names = {
      'operator': 'พนักงานคุมเครื่อง',
      'viewer': 'ผู้ดูข้อมูล',
      'technician': 'ช่างเทคนิค',
      'safety': 'จป. / Safety',
      'engineer': 'วิศวกร / หัวหน้า',
      'executive': 'ผู้บริหาร',
      'admin': 'ผู้ดูแลระบบ',
    };
    return names[role] ?? role;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final authProvider = StateNotifierProvider<AuthNotifier, UserSession?>(
  (ref) => AuthNotifier(),
);

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<UserSession?> {
  AuthNotifier() : super(null);

  /// Attempt login. Returns null on success, error message on failure.
  Future<String?> login(String username, String password) async {
    try {
      // Auto-reconnect if DB is not yet connected
      if (!DbConnection.instance.isConnected) {
        final config = await AppConfigService.load();
        if (config == null) {
          return 'ยังไม่ได้ตั้งค่าการเชื่อมต่อฐานข้อมูล\nกรุณากดปุ่ม "ตั้งค่าฐานข้อมูล" ด้านล่าง';
        }
        try {
          await DbConnection.instance.connect(config);
        } catch (e) {
          return 'เชื่อมต่อฐานข้อมูลไม่ได้\n${e.toString().split("\n").first}';
        }
      }

      // Check plain text password directly
      Logger().d('[Login] Attempting for user: $username');
      Logger().d('[Login] Password entered: $password');

      final row = await DbHelper.queryOne(
        '''
        SELECT user_id, username, full_name, role, dept_id, is_active, password_hash
        FROM users
        WHERE LOWER(username) = LOWER(@username)
        ''',
        params: {'username': username.trim()},
      );

      Logger().d('[Login] User found in DB: ${row != null}');
      if (row != null) {
        Logger().d('[Login] Password in DB: ${row['password_hash']}');
        Logger().d('[Login] Match: ${row['password_hash'] == password}');
      }

      if (row == null || row['password_hash'] != password) {
        return 'ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง';
      }
      if (row['is_active'] == false || row['is_active'] == 0) {
        return 'บัญชีผู้ใช้ถูกระงับ กรุณาติดต่อผู้ดูแลระบบ';
      }

      // Collect client info for audit
      String? hostname;
      String? ipAddress;
      try {
        hostname = Platform.localHostname;
        final interfaces = await NetworkInterface.list();
        for (final iface in interfaces) {
          for (final addr in iface.addresses) {
            if (!addr.isLoopback) {
              ipAddress = addr.address;
              break;
            }
          }
          if (ipAddress != null) break;
        }
        ipAddress ??= '127.0.0.1';
      } catch (_) {
        hostname = 'unknown';
        ipAddress = '0.0.0.0';
      }

      // Create session record
      final sessionId = 'SESS-${DateTime.now().millisecondsSinceEpoch}';
      await DbHelper.execute(
        '''
        INSERT INTO user_sessions (session_id, user_id, ip_address, hostname, login_at)
        VALUES (@sid, @uid, @ip, @host, CURRENT_TIMESTAMP)
        ''',
        params: {
          'sid': sessionId,
          'uid': row['user_id'],
          'ip': ipAddress,
          'host': hostname,
        },
      );

      await DbHelper.execute(
        'UPDATE users SET last_login_at = CURRENT_TIMESTAMP WHERE user_id = @uid',
        params: {'uid': row['user_id']},
      );

      state = UserSession(
        userId: row['user_id'].toString(),
        username: row['username'].toString(),
        fullName: row['full_name'].toString(),
        role: row['role'].toString(),
        deptId: row['dept_id']?.toString(),
        sessionId: sessionId,
        ipAddress: ipAddress,
        hostname: hostname,
      );

      return null;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('no such table')) {
        return 'ฐานข้อมูลยังไม่ได้ตั้งค่าเริ่มต้น (Initialize)\nกรุณากดปุ่ม "ตั้งค่าฐานข้อมูล" เพื่อตั้งค่าโครงสร้างข้อมูล';
      }
      return 'เกิดข้อผิดพลาดในการเชื่อมต่อ: $e';
    }
  }

  /// Logout — closes the session in DB
  Future<void> logout() async {
    final s = state;
    if (s != null && s.sessionId.isNotEmpty) {
      try {
        await DbHelper.execute(
          '''UPDATE user_sessions
             SET logout_at = CURRENT_TIMESTAMP, is_active = 0
             WHERE session_id = @sid''',
          params: {'sid': s.sessionId},
        );
      } catch (_) {}
    }
    state = null;
  }
}
