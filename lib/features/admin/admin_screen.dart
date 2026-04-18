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
    switch (role) {
      case 'admin': return AppColors.error;
      case 'engineer': return AppColors.primary;
      case 'safety': return AppColors.success;
      case 'technician': return AppColors.machinePM;
      case 'executive': return AppColors.info;
      default: return AppColors.textSecondary;
    }
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

class _UserManagementTab extends ConsumerWidget {
  final void Function(UserRecord) onEdit;
  const _UserManagementTab({required this.onEdit});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(userListProvider);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: usersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (users) => Card(
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
                  _H('', flex: 1),
                ]),
              ),
              Container(
                  height: 1,
                  color: Theme.of(context).colorScheme.outline),
              Expanded(
                child: ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (context, index) => Container(
                    height: 1,
                    color: Theme.of(context)
                        .colorScheme
                        .outline
                        .withValues(alpha: 0.3),
                  ),
                  itemBuilder: (ctx, i) {
                    final u = users[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md),
                      child: Row(children: [
                        Expanded(
                          flex: 1,
                          child: Text(u.employeeNo ?? '-',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  )),
                        ),
                        Expanded(
                          flex: 3,
                          child: Row(children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  u.roleColor.withValues(alpha: 0.15),
                              child: Text(
                                u.fullName.substring(0, 1),
                                style: TextStyle(
                                    fontSize: 13,
                                    color: u.roleColor,
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(u.fullName,
                                  style: AppTextStyles.bodyMedium,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ]),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(u.username,
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  )),
                        ),
                        Expanded(
                          flex: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color:
                                  u.roleColor.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
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
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  )),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            u.lastLoginAt != null
                                ? DateFormat('dd/MM/yy HH:mm')
                                    .format(u.lastLoginAt!)
                                : 'ยังไม่เคย',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: u.isActive
                                  ? AppColors.success.withValues(alpha: 0.12)
                                  : AppColors.error.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.full),
                            ),
                            child: Text(
                              u.isActive ? 'ใช้งาน' : 'ระงับ',
                              style: TextStyle(
                                fontSize: 10,
                                color: u.isActive
                                    ? AppColors.success
                                    : AppColors.error,
                                fontWeight: FontWeight.w600,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            onPressed: () => onEdit(u),
                            tooltip: 'แก้ไข',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            color: AppColors.textSecondary,
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
  bool _active = true;
  bool _saving = false;

  static const _roles = [
    ('operator', 'พนักงานคุมเครื่อง'),
    ('viewer', 'ผู้ดูข้อมูล'),
    ('technician', 'ช่างเทคนิค'),
    ('safety', 'จป. / Safety'),
    ('engineer', 'วิศวกร / หัวหน้า'),
    ('executive', 'ผู้บริหาร'),
    ('admin', 'ผู้ดูแลระบบ'),
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final u = widget.existing!;
      _nameCtrl.text = u.fullName;
      _usernameCtrl.text = u.username;
      _empCtrl.text = u.employeeNo ?? '';
      _role = u.role;
      _active = u.isActive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'แก้ไขผู้ใช้งาน' : 'เพิ่มผู้ใช้งานใหม่'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            DropdownButtonFormField<String>(
              initialValue: _role,
              decoration:
                  const InputDecoration(labelText: 'ตำแหน่ง / สิทธิ์'),
              items: _roles
                  .map((r) => DropdownMenuItem(
                        value: r.$1,
                        child: Text(r.$2),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => _role = v ?? _role),
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
      actions: [
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

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty ||
        _usernameCtrl.text.trim().isEmpty) {
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now().toIso8601String();
      if (widget.existing == null) {
        // Create
        final id =
            'USR-${DateTime.now().millisecondsSinceEpoch}';
        await DbHelper.execute(
          '''INSERT INTO users (user_id, employee_no, username, full_name,
             role, password_hash, is_active, created_at, updated_at)
             VALUES (@uid, @emp, @uname, @fname, @role, @pwd,
                     @active, @now, @now)''',
          params: {
            'uid': id,
            'emp': _empCtrl.text.trim().isEmpty ? null : _empCtrl.text.trim(),
            'uname': _usernameCtrl.text.trim(),
            'fname': _nameCtrl.text.trim(),
            'role': _role,
            'pwd': _passwordCtrl.text.isEmpty ? '1234' : _passwordCtrl.text,
            'active': _active ? 1 : 0,
            'now': now,
          },
        );
      } else {
        // Update
        final params = <String, dynamic>{
          'uid': widget.existing!.userId,
          'fname': _nameCtrl.text.trim(),
          'role': _role,
          'active': _active ? 1 : 0,
          'now': now,
        };
        String pwdClause = '';
        if (_passwordCtrl.text.isNotEmpty) {
          pwdClause = ', password_hash = @pwd';
          params['pwd'] = _passwordCtrl.text;
        }
        await DbHelper.execute(
          '''UPDATE users SET full_name=@fname, role=@role,
             is_active=@active$pwdClause, updated_at=@now
             WHERE user_id=@uid''',
          params: params,
        );
      }
      widget.onSaved();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
