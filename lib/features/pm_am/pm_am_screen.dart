import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/database/db_helper.dart';
import '../../features/auth/auth_provider.dart';
import 'package:intl/intl.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:empty_view/empty_view.dart';
import 'pm_am_pdf_service.dart';
import '../settings/settings_provider.dart';
// import '../work_orders/work_order_list_screen.dart'; 

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class PmSchedule {
  final String scheduleId;
  final String planId;
  final String planCode;
  final String planName;
  final String planType; // PM, AM
  final String machineNo;
  final String? machineBrand;
  final DateTime scheduledDate;
  final String status; // pending, overdue, in_progress, completed, cancelled
  final String? assignedToName;
  final double? estimatedHours;
  final int? frequencyDays;
  final int? frequencyMonths;

  const PmSchedule({
    required this.scheduleId,
    required this.planId,
    required this.planCode,
    required this.planName,
    required this.planType,
    required this.machineNo,
    this.machineBrand,
    required this.scheduledDate,
    required this.status,
    this.assignedToName,
    this.estimatedHours,
    this.frequencyDays,
    this.frequencyMonths,
  });

  bool get isOverdue => status == 'overdue' ||
      (status == 'pending' && scheduledDate.isBefore(DateTime.now()));

  factory PmSchedule.fromMap(Map<String, dynamic> m) => PmSchedule(
        scheduleId: m['schedule_id'] as String,
        planId: m['plan_id'] as String,
        planCode: m['plan_code'] as String? ?? '-',
        planName: m['plan_name'] as String? ?? '-',
        planType: m['plan_type'] as String? ?? 'PM',
        machineNo: m['machine_no'] as String? ?? '-',
        machineBrand: m['brand'] as String?,
        scheduledDate: DateTime.parse(m['scheduled_date'] as String),
        status: m['status'] as String? ?? 'pending',
        assignedToName: m['assigned_to_name'] as String?,
        estimatedHours: (m['estimated_hours'] as num?)?.toDouble(),
        frequencyDays: m['frequency_days'] as int?,
        frequencyMonths: m['frequency_months'] as int?,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final pmSchedulesProvider =
    FutureProvider.family<List<PmSchedule>, String?>((ref, type) async {
  try {
    final where = <String>['1=1'];
    final params = <String, dynamic>{};
    if (type != null) {
      where.add('pl.plan_type = @type');
      params['type'] = type;
    }
    final rows = await DbHelper.query(
      '''SELECT s.schedule_id, s.plan_id, s.scheduled_date, s.status,
                pl.plan_code, pl.plan_name, pl.plan_type, pl.estimated_hours,
                pl.frequency_days, pl.frequency_months,
                sn.machine_no, sn.brand,
                u.full_name as assigned_to_name
         FROM pm_am_schedules s
         JOIN pm_am_plans pl ON pl.plan_id = s.plan_id
         LEFT JOIN machine_snapshots sn ON sn.snapshot_id = pl.snapshot_id
         LEFT JOIN users u ON u.user_id = s.assigned_to
         WHERE ${where.join(' AND ')}
         ORDER BY s.scheduled_date DESC
         LIMIT 200''',
      params: params,
    );
    return rows.map(PmSchedule.fromMap).toList();
  } catch (_) {
    return [];
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// PM/AM List Screen
// ─────────────────────────────────────────────────────────────────────────────

class PmAmListScreen extends ConsumerStatefulWidget {
  const PmAmListScreen({super.key});

  @override
  ConsumerState<PmAmListScreen> createState() => _PmAmListScreenState();
}

class _PmAmListScreenState extends ConsumerState<PmAmListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    ('ทั้งหมด', null),
    ('PM', 'PM'),
    ('AM', 'AM'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final typeFilter = _tabs[_tabController.index].$2;
    final schedulesAsync = ref.watch(pmSchedulesProvider(typeFilter));

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
                    const HugeIcon(icon: HugeIcons.strokeRoundedSettings01,
                        color: AppColors.primary, size: 24),
                    const SizedBox(width: AppSpacing.sm),
                    Text('แผนการบำรุงรักษา PM / AM',
                        style: AppTextStyles.headlineLarge),
                  ]),
                  const SizedBox(height: 4),
                  Text('Preventive & Autonomous Maintenance Schedules',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
              const Spacer(),
              if (user?.isEngineerOrAbove ?? false)
                ElevatedButton.icon(
                  onPressed: () => _showCreatePlan(context),
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedPlusSign, size: 18, color: Colors.white),
                  label: const Text('สร้างแผน PM/AM'),
                ),
            ],
          ),
        ),

        // Tabs
        Container(
          color: Theme.of(context).cardTheme.color,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: _tabs.map((t) => Tab(text: t.$1)).toList(),
            tabAlignment: TabAlignment.start,
          ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // Summary chips
        schedulesAsync.whenOrNull(
              data: (schedules) {
                final overdue = schedules.where((s) => s.isOverdue).length;
                final today = schedules
                    .where((s) =>
                        DateUtils.isSameDay(s.scheduledDate, DateTime.now()))
                    .length;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(
                      AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.md),
                  child: Row(
                    children: [
                      _SummaryChip(
                        label: 'เกินกำหนด',
                        count: overdue,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      _SummaryChip(
                        label: 'วันนี้',
                        count: today,
                        color: AppColors.warning,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      _SummaryChip(
                        label: 'ทั้งหมด',
                        count: schedules.length,
                        color: AppColors.primary,
                      ),
                      const Spacer(),
                      IconButton(
                        icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        onPressed: () => ref.invalidate(pmSchedulesProvider),
                        tooltip: 'รีเฟรช',
                      ),
                    ],
                  ),
                );
              },
            ) ??
            const SizedBox.shrink(),

        // Schedule list
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.xxl),
            child: schedulesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (schedules) => schedules.isEmpty
                  ? EmptyView(
                      title: 'ไม่มีแผนการบำรุงรักษา',
                      description: 'ยังไม่มีกำหนดการ PM หรือ AM ในช่วงเวลานี้',
                      onButtonTap: () => ref.invalidate(pmSchedulesProvider),
                    )
                  : _ScheduleList(
                      schedules: schedules,
                      user: user,
                      onStartChecklist: _startChecklist,
                      onDelete: user?.isAdmin == true ? _deleteSchedule : null,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  void _startChecklist(PmSchedule schedule) {
    showDialog(
      context: context,
      builder: (ctx) => _ChecklistDialog(schedule: schedule),
    );
  }

  Future<void> _deleteSchedule(PmSchedule schedule) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('คุณต้องการลบแผนงาน "${schedule.planName}" ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบข้อมูล'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await DbHelper.execute(
        'DELETE FROM pm_schedules WHERE schedule_id = @id',
        params: {'id': schedule.scheduleId},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบแผนงานสำเร็จ')),
        );
        ref.invalidate(pmSchedulesProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    }
  }

  void _showCreatePlan(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _CreatePlanDialog(),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _SummaryChip(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text('$label: $count',
              style: AppTextStyles.labelMedium.copyWith(color: color)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedule List
// ─────────────────────────────────────────────────────────────────────────────

class _ScheduleList extends ConsumerWidget {
  final List<PmSchedule> schedules;
  final UserSession? user;
  final void Function(PmSchedule) onStartChecklist;
  final void Function(PmSchedule)? onDelete;

  const _ScheduleList({
    required this.schedules,
    this.user,
    required this.onStartChecklist,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListView.separated(
        itemCount: schedules.length,
        separatorBuilder: (context, index) => Container(
          height: 1,
          color:
              Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
        itemBuilder: (context, i) {
          final s = schedules[i];
          final isOverdue = s.isOverdue;
          final isToday =
              DateUtils.isSameDay(s.scheduledDate, DateTime.now());

          Color statusColor;
          if (s.status == 'completed') {
            statusColor = AppColors.success;
          } else if (isOverdue) {
            statusColor = AppColors.error;
          } else if (isToday) {
            statusColor = AppColors.warning;
          } else {
            statusColor = Theme.of(context).colorScheme.onSurfaceVariant;
          }

          return Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                // Type badge
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: s.planType == 'PM'
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : AppColors.machineAM.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Center(
                    child: Text(
                      s.planType,
                      style: AppTextStyles.labelMedium.copyWith(
                        color: s.planType == 'PM'
                            ? AppColors.primary
                            : AppColors.machineAM,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.planName, style: AppTextStyles.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        '${s.planCode} · ${s.machineNo}${s.machineBrand != null ? ' · ${s.machineBrand}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                // Assigned
                SizedBox(
                  width: 140,
                  child: Text(
                    s.assignedToName ?? 'ยังไม่มอบหมาย',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Scheduled date
                SizedBox(
                  width: 110,
                  child: Text(
                    DateFormat('dd/MM/yyyy').format(s.scheduledDate),
                    style: AppTextStyles.labelMedium.copyWith(
                        color: isOverdue ? AppColors.error : null),
                  ),
                ),
                // Status
                SizedBox(
                  width: 100,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Text(
                      isOverdue && s.status != 'completed'
                          ? 'เกินกำหนด'
                          : _statusLabel(s.status),
                      style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                // Action
                if (s.status != 'completed' &&
                    (user?.isTechnicianOrAbove ?? false))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedPrinter, size: 20, color: AppColors.primary),
                        onPressed: () {
                          final settings = ref.read(appSettingsProvider).valueOrNull;
                          final user = ref.read(authProvider);
                          if (settings != null) {
                            PmAmPdfService.generateChecklistPdf(
                              schedule: s, 
                              settings: settings,
                              userName: user?.fullName ?? 'System User',
                            );
                          }
                        },
                        tooltip: 'พิมพ์ Checklist',
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      ElevatedButton(
                        onPressed: () => onStartChecklist(s),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                        child: const Text('เริ่ม Checklist'),
                      ),
                      if (onDelete != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => onDelete!(s),
                          tooltip: 'ลบแผนงาน',
                        ),
                      ],
                    ],
                  )
                else if (s.status == 'completed')
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedPrinter, size: 20, color: AppColors.primary),
                        onPressed: () {
                          final settings = ref.read(appSettingsProvider).valueOrNull;
                          final user = ref.read(authProvider);
                          if (settings != null) {
                            PmAmPdfService.generateChecklistPdf(
                              schedule: s, 
                              settings: settings,
                              userName: user?.fullName ?? 'System User',
                            );
                          }
                        },
                        tooltip: 'พิมพ์ผลการตรวจ',
                      ),
                      if (onDelete != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                          onPressed: () => onDelete!(s),
                          tooltip: 'ลบแผนงาน',
                        ),
                      ],
                    ],
                  )
                else
                  const SizedBox(width: 144),
              ],
            ),
          );
        },
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'เสร็จสิ้น';
      case 'in_progress':
        return 'กำลังดำเนินการ';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return 'รอดำเนินการ';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Checklist Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ChecklistDialog extends ConsumerStatefulWidget {
  final PmSchedule schedule;
  const _ChecklistDialog({required this.schedule});

  @override
  ConsumerState<_ChecklistDialog> createState() => _ChecklistDialogState();
}

class _ChecklistDialogState extends ConsumerState<_ChecklistDialog> {
  final Map<String, String> _results = {}; // taskId -> pass/fail/na
  final Map<String, String> _values = {}; // taskId -> actual_value
  bool _saving = false;

  final _tasksProvider = FutureProvider.autoDispose
      .family<List<Map<String, dynamic>>, String>((ref, planId) async {
    return await DbHelper.query(
      'SELECT * FROM pm_am_tasks WHERE plan_id = @pid ORDER BY task_order',
      params: {'pid': planId},
    );
  });

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(_tasksProvider(widget.schedule.planId));

    return AlertDialog(
      title: Text('Checklist: ${widget.schedule.planName}'),
      content: SizedBox(
        width: 650,
        height: 500,
        child: tasksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (tasks) => ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (ctx, i) {
              final t = tasks[i];
              final tid = t['task_id'] as String;
              final name = t['task_name'] as String? ?? '-';
              final type = t['task_type'] as String? ?? 'inspect';
              final isCritical = t['is_critical'] == 1;
              final paramType = t['param_type'] as String?;
              final paramUnit = t['param_unit'] as String? ?? '';
              final result = _results[tid];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: _typeColor(type).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _typeIcon(type),
                              size: 16,
                              color: _typeColor(type),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: AppTextStyles.titleSmall),
                                Text(
                                  type.toUpperCase(),
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: _typeColor(type)),
                                ),
                              ],
                            ),
                          ),
                          if (isCritical)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.error.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('CRITICAL',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.error)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          // Result Buttons
                          _ResultBtn(
                            label: 'ผ่าน',
                            selected: result == 'pass',
                            color: AppColors.success,
                            onTap: () => setState(() => _results[tid] = 'pass'),
                          ),
                          const SizedBox(width: 4),
                          _ResultBtn(
                            label: 'ไม่ผ่าน',
                            selected: result == 'fail',
                            color: AppColors.error,
                            onTap: () => setState(() => _results[tid] = 'fail'),
                          ),
                          const SizedBox(width: 4),
                          _ResultBtn(
                            label: 'N/A',
                            selected: result == 'na',
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            onTap: () => setState(() => _results[tid] = 'na'),
                          ),
                          const Spacer(),
                          // Param Input if needed
                          if (paramType != null && paramType != 'none')
                            SizedBox(
                              width: 120,
                              child: TextField(
                                decoration: InputDecoration(
                                  labelText: 'ค่าที่วัดได้',
                                  suffixText: paramUnit,
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 12),
                                keyboardType: paramType == 'numeric'
                                    ? TextInputType.number
                                    : TextInputType.text,
                                onChanged: (v) => _values[tid] = v,
                              ),
                            ),
                          const SizedBox(width: 8),
                          // Abnormality Action
                          if (result == 'fail')
                            TextButton.icon(
                              onPressed: () => _showRepairForm(t),
                              icon: const HugeIcon(
                                  icon: HugeIcons.strokeRoundedAlert01,
                                  size: 14,
                                  color: AppColors.error),
                              label: const Text('แจ้งซ่อมทันที',
                                  style: TextStyle(
                                      fontSize: 11, color: AppColors.error)),
                              style: TextButton.styleFrom(
                                backgroundColor:
                                    AppColors.error.withValues(alpha: 0.08),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ปิด')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('บันทึกผล'),
        ),
      ],
    );
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'clean':
        return AppColors.info;
      case 'lubricate':
        return AppColors.success;
      case 'inspect':
        return AppColors.primary;
      case 'tighten':
        return AppColors.warning;
      case 'replace':
        return AppColors.error;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  dynamic _typeIcon(String type) {
    switch (type) {
      case 'clean':
        return HugeIcons.strokeRoundedPaintBucket;
      case 'lubricate':
        return HugeIcons.strokeRoundedDroplet;
      case 'inspect':
        return HugeIcons.strokeRoundedSearch01;
      case 'tighten':
        return HugeIcons.strokeRoundedSettings01;
      case 'replace':
        return HugeIcons.strokeRoundedPackage;
      default:
        return HugeIcons.strokeRoundedTask01;
    }
  }

  void _showRepairForm(Map<String, dynamic> task) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('เปิดหน้าต่างแจ้งซ่อมสำหรับ ${widget.schedule.machineNo}...'),
        backgroundColor: AppColors.error,
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final user = ref.read(authProvider);

      await DbHelper.transaction((tx) async {
        // 1. Update schedule status
        await DbHelper.txExecute(tx, 
          '''UPDATE pm_am_schedules SET status = 'completed', updated_at = @now
             WHERE schedule_id = @sid''',
          params: {'sid': widget.schedule.scheduleId, 'now': now},
        );

        // 2. Insert execution records for each task
        for (final entry in _results.entries) {
          final taskId = entry.key;
          final result = entry.value;
          final actualValue = _values[taskId];

          await DbHelper.txExecute(tx, 
            '''INSERT INTO pm_am_executions (
                 execution_id, schedule_id, task_id, executed_by, 
                 completed_at, result, actual_value, created_at
               ) VALUES (
                 @eid, @sid, @tid, @uid, @now, @res, @val, @now
               )''',
            params: {
              'eid': 'exec_${DateTime.now().millisecondsSinceEpoch}_$taskId',
              'sid': widget.schedule.scheduleId,
              'tid': taskId,
              'uid': user?.userId,
              'now': now,
              'res': result,
              'val': actualValue,
            },
          );
        }
      });

      ref.invalidate(pmSchedulesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Plan Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _CreatePlanDialog extends ConsumerStatefulWidget {
  const _CreatePlanDialog();

  @override
  ConsumerState<_CreatePlanDialog> createState() => _CreatePlanDialogState();
}

class _CreatePlanDialogState extends ConsumerState<_CreatePlanDialog> {
  final _formKey = GlobalKey<FormState>();
  String _type = 'PM';
  String? _selectedMachine;
  String _name = '';
  int? _days;
  int? _months;
  bool _saving = false;

  final _machinesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
    return await DbHelper.query('SELECT machine_id, machine_no, brand FROM machines WHERE is_active = 1');
  });

  @override
  Widget build(BuildContext context) {
    final machinesAsync = ref.watch(_machinesProvider);

    return AlertDialog(
      title: const Text('สร้างแผนการบำรุงรักษาใหม่'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'PM', label: Text('PM (Preventive)')),
                  ButtonSegment(value: 'AM', label: Text('AM (Autonomous)')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: AppSpacing.lg),
              machinesAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (machines) => DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'เลือกเครื่องจักร'),
                  items: machines.map((m) => DropdownMenuItem(
                    value: m['machine_id'] as String,
                    child: Text('${m['machine_no']} - ${m['brand'] ?? ''}'),
                  )).toList(),
                  onChanged: (v) => _selectedMachine = v,
                  validator: (v) => v == null ? 'กรุณาเลือกเครื่องจักร' : null,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                decoration: const InputDecoration(labelText: 'ชื่อแผน (เช่น PM เครื่องจักร A ประจำเดือน)'),
                onChanged: (v) => _name = v,
                validator: (v) => v == null || v.isEmpty ? 'กรุณาระบุชื่อแผน' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('ความถี่ในการทำ (เลือกอย่างใดอย่างหนึ่ง)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'ทุกๆ (วัน)', suffixText: 'วัน'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _days = int.tryParse(v),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextFormField(
                      decoration: const InputDecoration(labelText: 'ทุกๆ (เดือน)', suffixText: 'เดือน'),
                      keyboardType: TextInputType.number,
                      onChanged: (v) => _months = int.tryParse(v),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: const Text('สร้างแผน'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _saving = true);
    try {
      final planId = 'plan_${DateTime.now().millisecondsSinceEpoch}';
      final planCode = '$_type-${DateFormat('yyMM').format(DateTime.now())}-${planId.substring(planId.length - 4)}';
      
      await DbHelper.execute(
        '''INSERT INTO pm_am_plans (
             plan_id, machine_id, plan_type, plan_code, plan_name, 
             frequency_days, frequency_months, status
           ) VALUES (@id, @mid, @type, @code, @name, @days, @months, 'active')''',
        params: {
          'id': planId,
          'mid': _selectedMachine,
          'type': _type,
          'code': planCode,
          'name': _name,
          'days': _days,
          'months': _months,
        },
      );
      
      await DbHelper.execute(
        '''INSERT INTO pm_am_schedules (schedule_id, plan_id, scheduled_date, status)
           VALUES (@sid, @pid, @date, 'pending')''',
        params: {
          'sid': 'sched_${DateTime.now().millisecondsSinceEpoch}',
          'pid': planId,
          'date': DateTime.now().toIso8601String(),
        },
      );

      ref.invalidate(pmSchedulesProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ResultBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ResultBtn({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.2)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
              color: selected ? color : Theme.of(context).colorScheme.outline),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 11,
              color: selected ? color : Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight:
                  selected ? FontWeight.w700 : FontWeight.w400),
        ),
      ),
    );
  }
}
