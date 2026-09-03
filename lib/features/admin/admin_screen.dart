import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/database/db_helper.dart';
import '../../features/auth/auth_provider.dart';
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class UserRecord {
  final String userId;
  final String? employeeNo;
  final String username;
  final String fullName;
  final String role;
  final String? deptId;
  final String? deptName;
  final String? email;
  final bool isActive;
  final DateTime? lastLoginAt;
  final DateTime createdAt;

  const UserRecord({
    required this.userId,
    this.employeeNo,
    required this.username,
    required this.fullName,
    required this.role,
    this.deptId,
    this.deptName,
    this.email,
    required this.isActive,
    this.lastLoginAt,
    required this.createdAt,
  });

  factory UserRecord.fromMap(Map<String, dynamic> m) => UserRecord(
        userId: m['user_id'] as String,
        employeeNo: m['employee_no'] as String?,
        username: m['username'] as String,
        fullName: m['full_name'] as String,
        role: m['role'] as String,
        deptId: m['dept_id'] as String?,
        deptName: m['dept_name'] as String?,
        email: m['email'] as String?,
        isActive: m['is_active'] == 1,
        lastLoginAt: m['last_login_at'] != null
            ? DateTime.tryParse(m['last_login_at'] as String)
            : null,
        createdAt: DateTime.parse(m['created_at'] as String),
      );

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

  Color get roleColor {
    final r = role.toLowerCase();
    if (r.contains('admin') || r.contains('ผู้ดูแล')) return AppColors.error;
    if (r.contains('engineer') || r.contains('วิศวกร') || r.contains('หัวหน้า')) return AppColors.primary;
    if (r.contains('safety') || r.contains('จป')) return AppColors.success;
    if (r.contains('technician') || r.contains('ช่าง')) return AppColors.machinePM;
    if (r.contains('executive') || r.contains('ผู้บริหาร')) return AppColors.info;
    return AppColors.textSecondary;
  }
}

class AuditLogEntry {
  final int logId;
  final String tableName;
  final String? recordId;
  final String action;
  final String? username;
  final String? hostname;
  final DateTime changedAt;

  const AuditLogEntry({
    required this.logId,
    required this.tableName,
    this.recordId,
    required this.action,
    this.username,
    this.hostname,
    required this.changedAt,
  });

  factory AuditLogEntry.fromMap(Map<String, dynamic> m) => AuditLogEntry(
        logId: m['log_id'] as int,
        tableName: m['table_name'] as String,
        recordId: m['record_id'] as String?,
        action: m['action'] as String,
        username: m['username'] as String?,
        hostname: m['hostname'] as String?,
        changedAt:
            DateTime.parse(m['changed_at'] as String),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final userListProvider = FutureProvider<List<UserRecord>>((ref) async {
  try {
    final rows = await DbHelper.query(
      '''SELECT u.*, d.dept_name FROM users u
         LEFT JOIN departments d ON d.dept_id = u.dept_id
         ORDER BY u.role, u.full_name''',
    );
    return rows.map(UserRecord.fromMap).toList();
  } catch (_) {
    return [];
  }
});

final auditLogProvider = FutureProvider<List<AuditLogEntry>>((ref) async {
  try {
    final rows = await DbHelper.query(
      '''SELECT * FROM audit_log
         ORDER BY changed_at DESC LIMIT 200''',
    );
    return rows.map(AuditLogEntry.fromMap).toList();
  } catch (_) {
    return [];
  }
});

final departmentsListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  try {
    return await DbHelper.query(
      'SELECT dept_id, dept_code, dept_name FROM departments ORDER BY dept_name',
    );
  } catch (_) {
    return [];
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Admin Screen (Tabs: Users | Audit Log)
// ─────────────────────────────────────────────────────────────────────────────

class AdminScreen extends ConsumerStatefulWidget {
  const AdminScreen({super.key});

  @override
  ConsumerState<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends ConsumerState<AdminScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);

    if (!(user?.isAdmin ?? false)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, size: 48, color: AppColors.error),
            const SizedBox(height: 16),
            Text('สิทธิ์การเข้าถึงไม่เพียงพอ',
                style: AppTextStyles.headlineSmall),
            const SizedBox(height: 8),
            Text('หน้านี้สำหรับผู้ดูแลระบบเท่านั้น',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    )),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.lg),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.manage_accounts_rounded,
                        color: AppColors.primary, size: 24),
                    const SizedBox(width: AppSpacing.sm),
                    Text('จัดการผู้ใช้งานและระบบ',
                        style: AppTextStyles.headlineLarge),
                  ]),
                  const SizedBox(height: 4),
                  Text('Admin Panel · User Management · Audit Trail',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () => _showUserDialog(context, null),
                icon: const Icon(Icons.person_add_rounded, size: 18),
                label: const Text('เพิ่มผู้ใช้'),
              ),
            ],
          ),
        ),

        // Tabs
        Container(
          color: Theme.of(context).cardTheme.color,
          child: TabBar(
            controller: _tabCtrl,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: const [
              Tab(icon: Icon(Icons.people_rounded, size: 16), text: 'ผู้ใช้งาน'),
              Tab(icon: Icon(Icons.history_rounded, size: 16), text: 'บันทึกการใช้งาน'),
            ],
          ),
        ),

        // Content
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _UserManagementTab(
                  onEdit: (u) => _showUserDialog(context, u)),
              const _AuditLogTab(),
            ],
          ),
        ),
      ],
    );
  }

  void _showUserDialog(BuildContext context, UserRecord? existing) {
    showDialog(
      context: context,
      builder: (ctx) => _UserDialog(
        existing: existing,
        onSaved: () {
          ref.invalidate(userListProvider);
          Navigator.pop(ctx);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// User Management Tab
// ─────────────────────────────────────────────────────────────────────────────

class _UserManagementTab extends ConsumerStatefulWidget {
  final void Function(UserRecord) onEdit;
  const _UserManagementTab({required this.onEdit});

  @override
  ConsumerState<_UserManagementTab> createState() => _UserManagementTabState();
}

class _UserManagementTabState extends ConsumerState<_UserManagementTab> {
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all', 'active', 'inactive'
  String? _deptFilter; // null = all departments
  bool _hideInactive = false;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _toggleUserStatus(UserRecord u, {bool? forceDeactivate}) async {
    final newStatus = forceDeactivate == true ? false : !u.isActive;
    try {
      final now = DateTime.now().toIso8601String();
      await DbHelper.execute(
        'UPDATE users SET is_active = @active, updated_at = @now WHERE user_id = @uid',
        params: {
          'active': newStatus ? 1 : 0,
          'now': now,
          'uid': u.userId,
        },
      );
      ref.invalidate(userListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newStatus
                ? 'เปิดใช้งาน "${u.fullName}" แล้ว'
                : 'เปลี่ยนสถานะ "${u.fullName}" เป็น "ระงับการใช้งาน" เรียบร้อยแล้ว'),
            backgroundColor: newStatus ? AppColors.success : AppColors.warning,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถเปลี่ยนสถานะได้: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _deleteUser(UserRecord u) async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.manage_accounts_rounded, color: AppColors.primary, size: 24),
            SizedBox(width: 8),
            Text('จัดการ / ลบผู้ใช้งาน'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'เลือกการดำเนินการสำหรับ "${u.fullName}" (${u.username}):',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => Navigator.pop(ctx, 'deactivate'),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.block_rounded, color: AppColors.warning, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ระงับการใช้งาน (แนะนำ)',
                              style: TextStyle(fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text(
                            'ปิดสิทธิ์ใช้งานและซ่อนผู้ใช้ โดยยังคงรักษาประวัติงานเดิมในระบบ',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.md),
              onTap: () => Navigator.pop(ctx, 'delete'),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.delete_forever_rounded, color: AppColors.error, size: 22),
                    SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ลบข้อมูลถาวร',
                              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text(
                            'ลบออกจากฐานข้อมูลทันที (ใช้ได้เฉพาะผู้ใช้ที่ไม่มีประวัติงานผูกอยู่)',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
        ],
      ),
    );

    if (choice == 'deactivate') {
      await _toggleUserStatus(u, forceDeactivate: true);
    } else if (choice == 'delete') {
      try {
        await DbHelper.execute(
          'DELETE FROM users WHERE user_id = @uid',
          params: {'uid': u.userId},
        );
        ref.invalidate(userListProvider);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('ลบผู้ใช้งาน "${u.fullName}" เรียบร้อยแล้ว'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          final deact = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 24),
                  SizedBox(width: 8),
                  Text('ไม่สามารถลบถาวรได้'),
                ],
              ),
              content: Text(
                'ผู้ใช้งาน "${u.fullName}" มีประวัติการทำงานผูกอยู่ในระบบ ทำให้ไม่สามารถลบถาวรได้\n\nต้องการเปลี่ยนสถานะเป็น "ระงับการใช้งาน" เพื่อปิดสิทธิ์และซ่อนจากระบบแทนหรือไม่?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.warning,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('ระงับการใช้งานทันที'),
                ),
              ],
            ),
          );
          if (deact == true) {
            await _toggleUserStatus(u, forceDeactivate: true);
          }
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(userListProvider);
    final deptsAsync = ref.watch(departmentsListProvider);
    final currentUser = ref.watch(authProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (allUsers) {
          // Filter users
          final filteredUsers = allUsers.where((u) {
            // Search query filter
            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              final match = u.fullName.toLowerCase().contains(q) ||
                  u.username.toLowerCase().contains(q) ||
                  (u.employeeNo?.toLowerCase().contains(q) ?? false) ||
                  (u.deptName?.toLowerCase().contains(q) ?? false) ||
                  u.roleDisplayName.toLowerCase().contains(q);
              if (!match) return false;
            }

            // Department filter
            if (_deptFilter != null && u.deptId != _deptFilter) {
              return false;
            }

            // Hide inactive filter toggle
            if (_hideInactive && !u.isActive) {
              return false;
            }

            // Status category filter
            if (_statusFilter == 'active' && !u.isActive) return false;
            if (_statusFilter == 'inactive' && u.isActive) return false;

            return true;
          }).toList();

          final inactiveCount = allUsers.where((u) => !u.isActive).length;

          return Column(
            children: [
              // Toolbar: Search & Filter / Hide Inactive / Department
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  children: [
                    // Search box
                    Expanded(
                      flex: 2,
                      child: SizedBox(
                        height: 40,
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: (val) =>
                              setState(() => _searchQuery = val.trim()),
                          decoration: InputDecoration(
                            hintText: 'ค้นหาชื่อ, Username, รหัส, ตำแหน่ง...',
                            hintStyle: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                            prefixIcon: const Icon(Icons.search_rounded, size: 20),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 16),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            contentPadding: const EdgeInsets.symmetric(
                                vertical: 0, horizontal: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              borderSide: BorderSide(
                                  color: Theme.of(context).colorScheme.outline),
                            ),
                            filled: true,
                            fillColor:
                                Theme.of(context).cardTheme.color,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),

                    // Department Filter Dropdown
                    deptsAsync.when(
                      data: (depts) => SizedBox(
                        height: 40,
                        child: DropdownButtonHideUnderline(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardTheme.color,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                  color: Theme.of(context).colorScheme.outline),
                            ),
                            child: DropdownButton<String?>(
                              value: _deptFilter,
                              hint: const Text('แผนกทั้งหมด',
                                  style: TextStyle(fontSize: 12)),
                              items: [
                                const DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('แผนกทั้งหมด',
                                      style: TextStyle(fontSize: 12)),
                                ),
                                ...depts.map((d) => DropdownMenuItem<String?>(
                                      value: d['dept_id'] as String,
                                      child: Text('${d['dept_name']}',
                                          style: const TextStyle(fontSize: 12)),
                                    )),
                              ],
                              onChanged: (val) =>
                                  setState(() => _deptFilter = val),
                            ),
                          ),
                        ),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),

                    const SizedBox(width: AppSpacing.sm),

                    // Quick Hide Inactive Switch
                    FilterChip(
                      selected: _hideInactive,
                      avatar: Icon(
                        _hideInactive
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_rounded,
                        size: 16,
                        color: _hideInactive ? AppColors.warning : null,
                      ),
                      label: Text(
                        'ซ่อนผู้ใช้ที่ระงับ ($inactiveCount)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: _hideInactive
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: _hideInactive ? AppColors.warning : null,
                        ),
                      ),
                      onSelected: (val) =>
                          setState(() => _hideInactive = val),
                    ),

                    const SizedBox(width: AppSpacing.sm),

                    // Status Segment Filters
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'all', label: Text('ทั้งหมด')),
                        ButtonSegment(value: 'active', label: Text('เปิดใช้งาน')),
                        ButtonSegment(value: 'inactive', label: Text('ระงับ')),
                      ],
                      selected: {_statusFilter},
                      onSelectionChanged: (newVal) =>
                          setState(() => _statusFilter = newVal.first),
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),

                    const Spacer(),

                    // Summary count
                    Text(
                      'แสดง ${filteredUsers.length} จาก ${allUsers.length} รายการ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),

              // Table Card
              Expanded(
                child: Card(
                  child: Column(
                    children: [
                      // Table header
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(AppRadius.lg),
                            topRight: Radius.circular(AppRadius.lg),
                          ),
                        ),
                        child: const Row(children: [
                          _H('รหัส', flex: 1),
                          _H('ชื่อ-นามสกุล', flex: 3),
                          _H('Username', flex: 2),
                          _H('ตำแหน่ง', flex: 2),
                          _H('แผนก', flex: 2),
                          _H('Login ล่าสุด', flex: 2),
                          _H('สถานะ', flex: 1),
                          _H('จัดการ', flex: 1),
                        ]),
                      ),
                      Container(
                          height: 1,
                          color: Theme.of(context).colorScheme.outline),
                      Expanded(
                        child: filteredUsers.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.person_off_outlined,
                                        size: 40,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.5)),
                                    const SizedBox(height: 8),
                                    Text(
                                      'ไม่พบข้อมูลผู้ใช้งานที่ตรงกับเงื่อนไข',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                itemCount: filteredUsers.length,
                                separatorBuilder: (context, index) => Container(
                                  height: 1,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline
                                      .withValues(alpha: 0.3),
                                ),
                                itemBuilder: (ctx, i) {
                                  final u = filteredUsers[i];
                                  final isProtected = u.username
                                              .toLowerCase() ==
                                          'admin' ||
                                      u.username.toUpperCase() == 'SYSTEM' ||
                                      u.userId == currentUser?.userId;

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.lg,
                                        vertical: AppSpacing.md),
                                    child: Row(children: [
                                      Expanded(
                                        flex: 1,
                                        child: Text(u.employeeNo ?? '-',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                )),
                                      ),
                                      Expanded(
                                        flex: 3,
                                        child: Row(children: [
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor: u.roleColor
                                                .withValues(alpha: 0.15),
                                            child: Text(
                                              u.fullName.isNotEmpty
                                                  ? u.fullName.substring(0, 1)
                                                  : '?',
                                              style: TextStyle(
                                                  fontSize: 13,
                                                  color: u.roleColor,
                                                  fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(u.fullName,
                                                style: AppTextStyles.bodyMedium
                                                    .copyWith(
                                                  decoration: u.isActive
                                                      ? null
                                                      : TextDecoration
                                                          .lineThrough,
                                                  color: u.isActive
                                                      ? null
                                                      : Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                                ),
                                                overflow: TextOverflow.ellipsis),
                                          ),
                                        ]),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(u.username,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                )),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: u.roleColor
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                                AppRadius.full),
                                          ),
                                          child: Text(u.roleDisplayName,
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: u.roleColor,
                                                  fontWeight: FontWeight.w600)),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(u.deptName ?? '-',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                )),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(
                                          u.lastLoginAt != null
                                              ? DateFormat('dd/MM/yy HH:mm')
                                                  .format(u.lastLoginAt!)
                                              : 'ยังไม่เคย',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                              ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(
                                              AppRadius.full),
                                          onTap: isProtected
                                              ? null
                                              : () => _toggleUserStatus(u),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: u.isActive
                                                  ? AppColors.success
                                                      .withValues(alpha: 0.15)
                                                  : AppColors.error
                                                      .withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(
                                                  AppRadius.full),
                                              border: Border.all(
                                                color: u.isActive
                                                    ? AppColors.success
                                                        .withValues(alpha: 0.4)
                                                    : AppColors.error
                                                        .withValues(alpha: 0.4),
                                              ),
                                            ),
                                            child: Tooltip(
                                              message: isProtected
                                                  ? 'บัญชีระบบ'
                                                  : 'คลิกเพื่อสลับสถานะ (ใช้งาน/ระงับ)',
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                children: [
                                                  Icon(
                                                    u.isActive
                                                        ? Icons
                                                            .check_circle_outline_rounded
                                                        : Icons.block_rounded,
                                                    size: 13,
                                                    color: u.isActive
                                                        ? AppColors.success
                                                        : AppColors.error,
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    u.isActive
                                                        ? 'ใช้งาน'
                                                        : 'ระงับ',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: u.isActive
                                                          ? AppColors.success
                                                          : AppColors.error,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 16),
                                              onPressed: () =>
                                                  widget.onEdit(u),
                                              tooltip: 'แก้ไข',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                  minWidth: 28, minHeight: 28),
                                              color: AppColors.textSecondary,
                                            ),
                                            if (!isProtected) ...[
                                              const SizedBox(width: 4),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 16),
                                                onPressed: () =>
                                                    _deleteUser(u),
                                                tooltip: 'ลบผู้ใช้',
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(
                                                        minWidth: 28,
                                                        minHeight: 28),
                                                color: AppColors.error,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ]),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _H extends StatelessWidget {
  final String label;
  final int flex;
  const _H(this.label, {this.flex = 1});
  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Audit Log Tab
// ─────────────────────────────────────────────────────────────────────────────

class _AuditLogTab extends ConsumerWidget {
  const _AuditLogTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(auditLogProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (logs) => logs.isEmpty
            ? const Center(child: Text('ไม่มีบันทึกการใช้งาน'))
            : Card(
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(AppRadius.lg),
                          topRight: Radius.circular(AppRadius.lg),
                        ),
                      ),
                      child: const Row(children: [
                        _H('เวลา', flex: 2),
                        _H('ผู้ใช้', flex: 2),
                        _H('การกระทำ', flex: 1),
                        _H('ตาราง', flex: 2),
                        _H('Record ID', flex: 2),
                        _H('เครื่องคอมพิวเตอร์', flex: 2),
                      ]),
                    ),
                    Container(
                        height: 1,
                        color: Theme.of(context).colorScheme.outline),
                    Expanded(
                      child: ListView.separated(
                        itemCount: logs.length,
                        separatorBuilder: (context, index) => Container(
                          height: 1,
                          color: Theme.of(context)
                              .colorScheme
                              .outline
                              .withValues(alpha: 0.3),
                        ),
                        itemBuilder: (ctx, i) {
                          final log = logs[i];
                          final actionColor =
                              log.action == 'INSERT'
                                  ? AppColors.success
                                  : log.action == 'DELETE'
                                      ? AppColors.error
                                      : AppColors.warning;
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg,
                                vertical: AppSpacing.sm),
                            child: Row(children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  DateFormat('dd/MM/yy HH:mm:ss')
                                      .format(log.changedAt),
                                  style: AppTextStyles.labelSmall,
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(log.username ?? '-',
                                    style: AppTextStyles.bodySmall),
                              ),
                              Expanded(
                                flex: 1,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: actionColor
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                        AppRadius.sm),
                                  ),
                                  child: Text(log.action,
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: actionColor,
                                          fontWeight: FontWeight.w700)),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(log.tableName,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                    log.recordId ?? '-',
                                    style: AppTextStyles.labelSmall,
                                    overflow: TextOverflow.ellipsis),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(log.hostname ?? '-',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        )),
                              ),
                            ]),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// User Edit Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _UserDialog extends ConsumerStatefulWidget {
  final UserRecord? existing;
  final VoidCallback onSaved;
  const _UserDialog({this.existing, required this.onSaved});

  @override
  ConsumerState<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends ConsumerState<_UserDialog> {
  final _nameCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _empCtrl = TextEditingController();
  String _role = 'technician';
  String? _deptId;
  bool _active = true;
  bool _saving = false;
  String? _errorMsg;

  static const _roles = [
    ('operator', 'พนักงานคุมเครื่อง'),
    ('viewer', 'ผู้ดูข้อมูล'),
    ('technician', 'ช่างเทคนิค'),
    ('safety', 'จป. / Safety'),
    ('engineer', 'วิศวกร / หัวหน้า'),
    ('executive', 'ผู้บริหาร'),
    ('admin', 'ผู้ดูแลระบบ'),
  ];

  static String _normalizeRole(String? raw) {
    final r = (raw ?? '').trim();
    if (r.isEmpty) return 'technician';
    final lower = r.toLowerCase();
    for (final role in _roles) {
      if (role.$1 == lower || role.$2 == r) return role.$1;
    }
    return r;
  }

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final u = widget.existing!;
      _nameCtrl.text = u.fullName;
      _usernameCtrl.text = u.username;
      _empCtrl.text = u.employeeNo ?? '';
      _role = _normalizeRole(u.role);
      _deptId = u.deptId;
      _active = u.isActive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final roleItems = [
      ..._roles,
      if (!_roles.any((r) => r.$1 == _role)) (_role, _role),
    ];
    final deptsAsync = ref.watch(departmentsListProvider);

    return AlertDialog(
      title: Text(isEdit ? 'แก้ไขผู้ใช้งาน' : 'เพิ่มผู้ใช้งานใหม่'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_errorMsg != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: AppColors.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMsg!,
                          style: const TextStyle(color: AppColors.error, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _empCtrl,
                      decoration: const InputDecoration(
                          labelText: 'รหัสพนักงาน'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _usernameCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Username *'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'ชื่อ-นามสกุล *'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText:
                      isEdit ? 'รหัสผ่านใหม่ (เว้นว่างถ้าไม่เปลี่ยน)' : 'รหัสผ่าน *',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: roleItems.any((r) => r.$1 == _role) ? _role : 'technician',
                      decoration:
                          const InputDecoration(labelText: 'ตำแหน่ง / สิทธิ์'),
                      items: roleItems
                          .map((r) => DropdownMenuItem(
                                value: r.$1,
                                child: Text(r.$2),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _role = v ?? _role),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: deptsAsync.when(
                      data: (depts) => DropdownButtonFormField<String?>(
                        value: depts.any((d) => d['dept_id'] == _deptId) ? _deptId : null,
                        decoration: const InputDecoration(labelText: 'แผนก'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('- ไม่ระบุแผนก -',
                                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          ),
                          ...depts.map((d) => DropdownMenuItem<String?>(
                                value: d['dept_id'] as String,
                                child: Text('${d['dept_name']}',
                                    style: const TextStyle(fontSize: 13)),
                              )),
                        ],
                        onChanged: (v) => setState(() => _deptId = v),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                title: Text('สถานะบัญชี: ${_active ? "ใช้งาน" : "ระงับ"}',
                    style: AppTextStyles.bodyMedium),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (isEdit &&
            widget.existing!.username.toLowerCase() != 'admin' &&
            widget.existing!.username.toUpperCase() != 'SYSTEM')
          TextButton.icon(
            onPressed: _saving ? null : _delete,
            icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
            label: const Text('ลบผู้ใช้', style: TextStyle(color: AppColors.error)),
          ),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(isEdit ? 'บันทึก' : 'สร้างบัญชี'),
        ),
      ],
    );
  }

  Future<void> _delete() async {
    if (widget.existing == null) return;
    final u = widget.existing!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 24),
            SizedBox(width: 8),
            Text('ยืนยันการลบผู้ใช้'),
          ],
        ),
        content: Text('คุณต้องการลบผู้ใช้งาน "${u.fullName}" (${u.username}) หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบผู้ใช้'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() {
      _saving = true;
      _errorMsg = null;
    });

    try {
      await DbHelper.execute('DELETE FROM users WHERE user_id = @uid', params: {'uid': u.userId});
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'ไม่สามารถลบได้เนื่องจากมีข้อมูลประวัติงานในระบบ แนะนำให้เปลี่ยนสถานะเป็น "ระงับ" แทน';
          _saving = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final uname = _usernameCtrl.text.trim();
    final fname = _nameCtrl.text.trim();
    final emp = _empCtrl.text.trim().isEmpty ? null : _empCtrl.text.trim();

    if (uname.isEmpty || fname.isEmpty) {
      setState(() => _errorMsg = 'กรุณากรอก Username และ ชื่อ-นามสกุล');
      return;
    }

    setState(() {
      _saving = true;
      _errorMsg = null;
    });

    try {
      final now = DateTime.now().toIso8601String();
      if (widget.existing == null) {
        // Check duplicate username
        final checkUname = await DbHelper.query(
          'SELECT user_id FROM users WHERE LOWER(username) = LOWER(@uname)',
          params: {'uname': uname},
        );
        if (checkUname.isNotEmpty) {
          setState(() {
            _errorMsg = 'Username "$uname" มีอยู่ในระบบแล้ว กรุณาใช้ Username อื่น';
            _saving = false;
          });
          return;
        }

        // Check duplicate employee_no if provided
        if (emp != null) {
          final checkEmp = await DbHelper.query(
            'SELECT user_id FROM users WHERE LOWER(employee_no) = LOWER(@emp)',
            params: {'emp': emp},
          );
          if (checkEmp.isNotEmpty) {
            setState(() {
              _errorMsg = 'รหัสพนักงาน "$emp" มีอยู่ในระบบแล้ว';
              _saving = false;
            });
            return;
          }
        }

        // Create
        final id = 'USR-${DateTime.now().millisecondsSinceEpoch}';
        await DbHelper.execute(
          '''INSERT INTO users (user_id, employee_no, username, full_name,
             role, dept_id, password_hash, is_active, created_at, updated_at)
             VALUES (@uid, @emp, @uname, @fname, @role, @dept, @pwd,
                     @active, @now, @now)''',
          params: {
            'uid': id,
            'emp': emp,
            'uname': uname,
            'fname': fname,
            'role': _role,
            'dept': _deptId,
            'pwd': _passwordCtrl.text.isEmpty ? '1234' : _passwordCtrl.text,
            'active': _active ? 1 : 0,
            'now': now,
          },
        );
      } else {
        // Check duplicate username against other users
        final checkUname = await DbHelper.query(
          'SELECT user_id FROM users WHERE LOWER(username) = LOWER(@uname) AND user_id != @uid',
          params: {'uname': uname, 'uid': widget.existing!.userId},
        );
        if (checkUname.isNotEmpty) {
          setState(() {
            _errorMsg = 'Username "$uname" ซ้ำกับผู้ใช้อื่นในระบบ';
            _saving = false;
          });
          return;
        }

        // Check duplicate employee_no against other users
        if (emp != null) {
          final checkEmp = await DbHelper.query(
            'SELECT user_id FROM users WHERE LOWER(employee_no) = LOWER(@emp) AND user_id != @uid',
            params: {'emp': emp, 'uid': widget.existing!.userId},
          );
          if (checkEmp.isNotEmpty) {
            setState(() {
              _errorMsg = 'รหัสพนักงาน "$emp" ซ้ำกับผู้ใช้อื่นในระบบ';
              _saving = false;
            });
            return;
          }
        }

        // Update
        final params = <String, dynamic>{
          'uid': widget.existing!.userId,
          'emp': emp,
          'uname': uname,
          'fname': fname,
          'role': _role,
          'dept': _deptId,
          'active': _active ? 1 : 0,
          'now': now,
        };
        String pwdClause = '';
        if (_passwordCtrl.text.isNotEmpty) {
          pwdClause = ', password_hash = @pwd';
          params['pwd'] = _passwordCtrl.text;
        }
        await DbHelper.execute(
          '''UPDATE users SET employee_no=@emp, username=@uname, full_name=@fname,
             role=@role, dept_id=@dept, is_active=@active$pwdClause, updated_at=@now
             WHERE user_id=@uid''',
          params: params,
        );
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        String msg = 'เกิดข้อผิดพลาดในการบันทึก: $e';
        final errStr = e.toString();
        if (errStr.contains('users.username') || errStr.contains('UNIQUE constraint failed: users.username')) {
          msg = 'Username "$uname" มีอยู่ในระบบแล้ว กรุณาใช้ Username อื่น';
        } else if (errStr.contains('users.employee_no') || errStr.contains('UNIQUE constraint failed: users.employee_no')) {
          msg = 'รหัสพนักงาน "$emp" มีอยู่ในระบบแล้ว';
        }
        setState(() => _errorMsg = msg);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
