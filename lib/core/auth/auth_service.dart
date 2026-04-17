import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../database/db_helper.dart';
import 'rbac_models.dart';

final _log = Logger();

/// Service for user authentication and authorization.
/// Handles login, session management, and permission checking.
class AuthService {
  static const uuid = Uuid();
  static User? _currentUser;
  static UserSession? _currentSession;

  /// Get currently logged-in user
  static User? get currentUser => _currentUser;
  static UserSession? get currentSession => _currentSession;

  /// Hash password using SHA-256
  static String hashPassword(String password) {
    return sha256.convert(password.codeUnits).toString();
  }

  /// Attempt to login with username and password
  static Future<(bool success, String message, User? user)> login(
    String username,
    String password,
  ) async {
    try {
      // Find user by username
      final result = await DbHelper.queryOne(
        'SELECT * FROM users WHERE username = @username AND is_active = 1',
        params: {'username': username},
      );

      if (result == null) {
        _log.w('Login failed: user not found - $username');
        return (false, 'Invalid username or password', null);
      }

      final user = User.fromMap(result);
      final passwordHash = hashPassword(password);

      // Verify password
      if (result['password_hash'] != passwordHash) {
        _log.w('Login failed: invalid password - $username');
        return (false, 'Invalid username or password', null);
      }

      // Create session
      final sessionId = uuid.v4();
      final ipAddress = await _getIpAddress();
      final hostname = await _getHostname();
      final now = DateTime.now().toIso8601String();

      await DbHelper.execute(
        '''INSERT INTO user_sessions 
           (session_id, user_id, ip_address, hostname, login_at, is_active)
           VALUES (@session_id, @user_id, @ip_address, @hostname, @login_at, 1)''',
        params: {
          'session_id': sessionId,
          'user_id': user.userId,
          'ip_address': ipAddress,
          'hostname': hostname,
          'login_at': now,
        },
      );

      // Update last login
      await DbHelper.execute(
        'UPDATE users SET last_login_at = @now WHERE user_id = @user_id',
        params: {'now': now, 'user_id': user.userId},
      );

      // Set current user and session
      _currentUser = user;
      _currentSession = UserSession(
        sessionId: sessionId,
        userId: user.userId,
        ipAddress: ipAddress,
        hostname: hostname,
        loginAt: DateTime.now(),
        isActive: true,
      );

      _log.i(
        'User logged in successfully: ${user.username} (${user.role.name})',
      );
      return (true, 'Login successful', user);
    } catch (e) {
      _log.e('Login error: $e');
      return (false, 'Login error: $e', null);
    }
  }

  /// Logout current user
  static Future<bool> logout() async {
    try {
      if (_currentSession == null) return true;

      final now = DateTime.now().toIso8601String();
      await DbHelper.execute(
        '''UPDATE user_sessions 
           SET logout_at = @now, is_active = 0 
           WHERE session_id = @session_id''',
        params: {'now': now, 'session_id': _currentSession!.sessionId},
      );

      _log.i('User logged out: ${_currentUser?.username}');
      _currentUser = null;
      _currentSession = null;
      return true;
    } catch (e) {
      _log.e('Logout error: $e');
      return false;
    }
  }

  /// Check if user has permission for specific action
  static bool hasPermission(PermissionCategory permission) {
    return _currentUser?.hasPermission(permission) ?? false;
  }

  /// Check if user has any of the given permissions
  static bool hasAnyPermission(List<PermissionCategory> permissions) {
    return permissions.any((p) => hasPermission(p));
  }

  /// Check if user has all of the given permissions
  static bool hasAllPermissions(List<PermissionCategory> permissions) {
    return permissions.every((p) => hasPermission(p));
  }

  /// Get user by ID
  static Future<User?> getUserById(String userId) async {
    try {
      final result = await DbHelper.queryOne(
        'SELECT * FROM users WHERE user_id = @user_id',
        params: {'user_id': userId},
      );
      return result != null ? User.fromMap(result) : null;
    } catch (e) {
      _log.e('Error getting user: $e');
      return null;
    }
  }

  /// Get all users
  static Future<List<User>> getAllUsers() async {
    try {
      final results = await DbHelper.query(
        'SELECT * FROM users ORDER BY full_name',
      );
      return results.map((map) => User.fromMap(map)).toList();
    } catch (e) {
      _log.e('Error getting users: $e');
      return [];
    }
  }

  /// Create new user
  static Future<(bool success, String message)> createUser({
    required String employeeNo,
    required String username,
    required String fullName,
    required String password,
    required UserRole role,
    required String deptId,
    String? email,
    String? phone,
  }) async {
    try {
      // Check if username already exists
      final existing = await DbHelper.queryOne(
        'SELECT user_id FROM users WHERE username = @username',
        params: {'username': username},
      );
      if (existing != null) {
        return (false, 'Username already exists');
      }

      final userId = uuid.v4();
      final passwordHash = hashPassword(password);
      final now = DateTime.now().toIso8601String();

      await DbHelper.execute(
        '''INSERT INTO users 
           (user_id, employee_no, username, full_name, email, phone, 
            role, dept_id, password_hash, is_active, created_at, updated_at)
           VALUES (@user_id, @employee_no, @username, @full_name, @email, @phone,
                   @role, @dept_id, @password_hash, 1, @now, @now)''',
        params: {
          'user_id': userId,
          'employee_no': employeeNo,
          'username': username,
          'full_name': fullName,
          'email': email,
          'phone': phone,
          'role': role.toDbString(),
          'dept_id': deptId,
          'password_hash': passwordHash,
          'now': now,
        },
      );

      _log.i('User created: $username');
      return (true, 'User created successfully');
    } catch (e) {
      _log.e('Error creating user: $e');
      return (false, 'Error: $e');
    }
  }

  /// Update user role
  static Future<(bool success, String message)> updateUserRole(
    String userId,
    UserRole newRole,
  ) async {
    try {
      final now = DateTime.now().toIso8601String();
      await DbHelper.execute(
        'UPDATE users SET role = @role, updated_at = @now WHERE user_id = @user_id',
        params: {'role': newRole.toDbString(), 'user_id': userId, 'now': now},
      );
      _log.i('User role updated: $userId -> ${newRole.name}');
      return (true, 'Role updated successfully');
    } catch (e) {
      _log.e('Error updating user role: $e');
      return (false, 'Error: $e');
    }
  }

  /// Deactivate user
  static Future<(bool success, String message)> deactivateUser(
    String userId,
  ) async {
    try {
      await DbHelper.execute(
        'UPDATE users SET is_active = 0 WHERE user_id = @user_id',
        params: {'user_id': userId},
      );
      _log.i('User deactivated: $userId');
      return (true, 'User deactivated successfully');
    } catch (e) {
      _log.e('Error deactivating user: $e');
      return (false, 'Error: $e');
    }
  }

  /// Get IP address of current device
  static Future<String?> _getIpAddress() async {
    try {
      final wifiIP = await NetworkInfo().getWifiIP();
      return wifiIP;
    } catch (e) {
      _log.e('Error getting IP address: $e');
      return null;
    }
  }

  /// Get hostname of current device
  static Future<String?> _getHostname() async {
    try {
      return '${await NetworkInfo().getWifiName()}_${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      _log.e('Error getting hostname: $e');
      return null;
    }
  }
}
