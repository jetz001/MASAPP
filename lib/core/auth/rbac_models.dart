/// Role-based access control models and enums for MASAPP.
/// Supports 6 main roles with hierarchical permissions.
library;

/// Available user roles in the system
enum UserRole {
  admin, // Full system access, can manage users and system settings
  engineer, // Can approve PM/AM, manage work orders, view analytics
  supervisor, // Can dispatch work, manage technicians, view assigned areas
  technician, // Can perform PM/AM, create work orders, view machine data
  operator, // Can perform AM, view assigned machines only
  viewer, // Read-only access
}

extension UserRoleExt on UserRole {
  /// Get display name for role
  String get displayName {
    switch (this) {
      case UserRole.admin:
        return 'Administrator';
      case UserRole.engineer:
        return 'Engineer';
      case UserRole.supervisor:
        return 'Supervisor';
      case UserRole.technician:
        return 'Technician';
      case UserRole.operator:
        return 'Operator';
      case UserRole.viewer:
        return 'Viewer';
    }
  }

  /// Get role from string (for database)
  static UserRole fromString(String roleStr) {
    return UserRole.values.firstWhere(
      (role) => role.name == roleStr.toLowerCase(),
      orElse: () => UserRole.viewer,
    );
  }

  /// Convert to string for storage
  String toDbString() => name;
}

/// Permission categories for feature access control
enum PermissionCategory {
  // Machine Management
  machineView,
  machineCreate,
  machineEdit,
  machineDelete,
  machineTransfer,

  // Maintenance (PM/AM)
  pmView,
  pmCreate,
  pmExecute,
  amView,
  amExecute,

  // Work Orders
  woView,
  woCreate,
  woApprove,
  woExecute,
  woClose,

  // Work Permits
  wpView,
  wpCreate,
  wpApprove,
  wpSign,

  // Spare Parts
  spView,
  spCreate,
  spRequestStock,
  spAdjustStock,

  // Analytics & Reports
  analyticsView,
  reportGenerate,

  // Admin & Settings
  userManage,
  roleManage,
  auditView,
  settingsManage,
  backupManage,
}

/// Map of role to permissions
final rolePermissions = <UserRole, Set<PermissionCategory>>{
  UserRole.admin: {
    // Full access to everything
    ...PermissionCategory.values.toSet(),
  },
  UserRole.engineer: {
    // Can view and approve work orders, analytics
    PermissionCategory.machineView,
    PermissionCategory.pmView,
    PermissionCategory.pmCreate,
    PermissionCategory.amView,
    PermissionCategory.woView,
    PermissionCategory.woApprove,
    PermissionCategory.wpView,
    PermissionCategory.wpApprove,
    PermissionCategory.spView,
    PermissionCategory.analyticsView,
    PermissionCategory.reportGenerate,
    PermissionCategory.auditView,
  },
  UserRole.supervisor: {
    // Can dispatch work and manage technicians
    PermissionCategory.machineView,
    PermissionCategory.pmView,
    PermissionCategory.amView,
    PermissionCategory.woView,
    PermissionCategory.woCreate,
    PermissionCategory.woExecute,
    PermissionCategory.wpView,
    PermissionCategory.wpCreate,
    PermissionCategory.spView,
    PermissionCategory.analyticsView,
  },
  UserRole.technician: {
    // Can execute PM/AM and create work orders
    PermissionCategory.machineView,
    PermissionCategory.pmView,
    PermissionCategory.pmExecute,
    PermissionCategory.amView,
    PermissionCategory.amExecute,
    PermissionCategory.woView,
    PermissionCategory.woCreate,
    PermissionCategory.woExecute,
    PermissionCategory.wpView,
    PermissionCategory.spView,
    PermissionCategory.spRequestStock,
  },
  UserRole.operator: {
    // Can only perform AM and view assigned machines
    PermissionCategory.machineView,
    PermissionCategory.amView,
    PermissionCategory.amExecute,
    PermissionCategory.woView,
  },
  UserRole.viewer: {
    // Read-only access
    PermissionCategory.machineView,
    PermissionCategory.pmView,
    PermissionCategory.amView,
    PermissionCategory.woView,
    PermissionCategory.wpView,
    PermissionCategory.spView,
    PermissionCategory.analyticsView,
  },
};

/// User model representing logged-in user
class User {
  final String userId;
  final String employeeNo;
  final String username;
  final String fullName;
  final String? email;
  final String? phone;
  final UserRole role;
  final String deptId;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? lastLoginAt;

  User({
    required this.userId,
    required this.employeeNo,
    required this.username,
    required this.fullName,
    this.email,
    this.phone,
    required this.role,
    required this.deptId,
    required this.isActive,
    required this.createdAt,
    this.lastLoginAt,
  });

  /// Create from database map
  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      userId: map['user_id'] as String,
      employeeNo: map['employee_no'] as String? ?? '',
      username: map['username'] as String,
      fullName: map['full_name'] as String,
      email: map['email'] as String?,
      phone: map['phone'] as String?,
      role: UserRoleExt.fromString(map['role'] as String? ?? 'viewer'),
      deptId: map['dept_id'] as String? ?? '',
      isActive: (map['is_active'] as int?) == 1,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastLoginAt: map['last_login_at'] != null
          ? DateTime.parse(map['last_login_at'] as String)
          : null,
    );
  }

  /// Convert to map for display/serialization
  Map<String, dynamic> toMap() => {
    'userId': userId,
    'employeeNo': employeeNo,
    'username': username,
    'fullName': fullName,
    'email': email,
    'phone': phone,
    'role': role.displayName,
    'deptId': deptId,
    'isActive': isActive,
    'createdAt': createdAt.toIso8601String(),
    'lastLoginAt': lastLoginAt?.toIso8601String(),
  };

  /// Check if user has permission
  bool hasPermission(PermissionCategory permission) {
    return rolePermissions[role]?.contains(permission) ?? false;
  }

  /// Get all permissions for this user's role
  Set<PermissionCategory> getPermissions() {
    return rolePermissions[role] ?? {};
  }
}

/// User session for audit trail
class UserSession {
  final String sessionId;
  final String userId;
  final String? ipAddress;
  final String? hostname;
  final DateTime loginAt;
  final DateTime? logoutAt;
  final bool isActive;

  UserSession({
    required this.sessionId,
    required this.userId,
    this.ipAddress,
    this.hostname,
    required this.loginAt,
    this.logoutAt,
    required this.isActive,
  });

  factory UserSession.fromMap(Map<String, dynamic> map) {
    return UserSession(
      sessionId: map['session_id'] as String,
      userId: map['user_id'] as String,
      ipAddress: map['ip_address'] as String?,
      hostname: map['hostname'] as String?,
      loginAt: DateTime.parse(map['login_at'] as String),
      logoutAt: map['logout_at'] != null
          ? DateTime.parse(map['logout_at'] as String)
          : null,
      isActive: (map['is_active'] as int?) == 1,
    );
  }
}
