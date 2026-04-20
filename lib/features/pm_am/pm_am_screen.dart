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
                  onPressed: () {},
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedPlusSign, size: 18, color: Colors.white),
                  label: const Text('สร้างแผน PM'),
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

class _ScheduleList extends StatelessWidget {
  final List<PmSchedule> schedules;
  final UserSession? user;
  final void Function(PmSchedule) onStartChecklist;

  const _ScheduleList({
    required this.schedules,
    this.user,
    required this.onStartChecklist,
  });

  @override
  Widget build(BuildContext context) {
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
                  ElevatedButton(
                    onPressed: () => onStartChecklist(s),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('เริ่ม Checklist'),
                  )
                else
                  const SizedBox(width: 104),
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
        width: 560,
        height: 400,
        child: tasksAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (tasks) => ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (ctx, i) {
              final t = tasks[i];
              final tid = t['task_id'] as String;
              final name = t['task_name'] as String? ?? '-';
              final isCritical = t['is_critical'] == 1;
              final result = _results[tid];

              return Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _typeColor(t['task_type'] as String?)
                            .withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _typeColor(
                                t['task_type'] as String?),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                                child: Text(name,
                                    style:
                                        AppTextStyles.bodyMedium)),
                            if (isCritical)
                              Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.error
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('Critical',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.error)),
                              ),
                          ]),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Pass/Fail/NA buttons
                    _ResultBtn(
                      label: 'ผ่าน',
                      selected: result == 'pass',
                      color: AppColors.success,
                      onTap: () =>
                          setState(() => _results[tid] = 'pass'),
                    ),
                    const SizedBox(width: 4),
                    _ResultBtn(
                      label: 'ไม่ผ่าน',
                      selected: result == 'fail',
                      color: AppColors.error,
                      onTap: () =>
                          setState(() => _results[tid] = 'fail'),
                    ),
                    const SizedBox(width: 4),
                    _ResultBtn(
                      label: 'N/A',
                      selected: result == 'na',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      onTap: () =>
                          setState(() => _results[tid] = 'na'),
                    ),
                  ],
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

  Color _typeColor(String? type) {
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

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final now = DateTime.now().toIso8601String();
      await DbHelper.execute(
        '''UPDATE pm_am_schedules SET status = 'completed', updated_at = @now
           WHERE schedule_id = @sid''',
        params: {'sid': widget.schedule.scheduleId, 'now': now},
      );
      if (mounted) Navigator.pop(context);
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
