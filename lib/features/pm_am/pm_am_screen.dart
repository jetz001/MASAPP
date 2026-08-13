import 'dart:convert';
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
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:uuid/uuid.dart';
import 'package:go_router/go_router.dart';
import 'pm_am_pdf_service.dart';
import '../settings/settings_provider.dart';
import '../work_orders/work_order_models.dart';

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
  final String? assignedTo;       // user_id
  final String? assignedToName;
  final double? estimatedHours;
  final int? frequencyDays;
  final int? frequencyMonths;
  final List<String> attachments; // file paths stored as JSON
  final String? taskTopics; // concatenated task names

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
    this.assignedTo,
    this.assignedToName,
    this.estimatedHours,
    this.frequencyDays,
    this.frequencyMonths,
    this.attachments = const [],
    this.taskTopics,
  });

  bool get isOverdue => status == 'overdue' ||
      (status == 'pending' && DateUtils.dateOnly(scheduledDate).isBefore(DateUtils.dateOnly(DateTime.now())));

  factory PmSchedule.fromMap(Map<String, dynamic> m) {
    List<String> attachments = [];
    try {
      final raw = m['attachments'] as String?;
      if (raw != null && raw.isNotEmpty) {
        attachments = List<String>.from(jsonDecode(raw) as List);
      }
    } catch (_) {}
    return PmSchedule(
      scheduleId: m['schedule_id'] as String,
      planId: m['plan_id'] as String,
      planCode: m['plan_code'] as String? ?? '-',
      planName: m['plan_name'] as String? ?? '-',
      planType: m['plan_type'] as String? ?? 'PM',
      machineNo: m['machine_no'] as String? ?? '-',
      machineBrand: m['brand'] as String?,
      scheduledDate: DateTime.parse(m['scheduled_date'] as String),
      status: m['status'] as String? ?? 'pending',
      assignedTo: m['assigned_to'] as String?,
      assignedToName: m['assigned_to_name'] as String?,
      estimatedHours: (m['estimated_hours'] as num?)?.toDouble(),
      frequencyDays: m['frequency_days'] as int?,
      frequencyMonths: m['frequency_months'] as int?,
      attachments: attachments,
      taskTopics: m['task_topics'] as String?,
    );
  }
}

class PmScheduleFilter {
  final String? type;
  final String? search;
  final String? status;
  const PmScheduleFilter({this.type, this.search, this.status});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PmScheduleFilter &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          search == other.search &&
          status == other.status;

  @override
  int get hashCode => type.hashCode ^ search.hashCode ^ status.hashCode;
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final pmSchedulesProvider =
    FutureProvider.family<List<PmSchedule>, PmScheduleFilter>((ref, filter) async {
  try {
    final where = <String>['1=1'];
    final params = <String, dynamic>{};
    if (filter.type != null) {
      where.add('pl.plan_type = @type');
      params['type'] = filter.type;
    }
    if (filter.status != null && filter.status != 'ทั้งหมด') {
      if (filter.status == 'เกินกำหนด') {
        where.add("(s.status = 'overdue' OR (s.status = 'pending' AND date(s.scheduled_date) < date('now', 'localtime')))");
      } else if (filter.status == 'เสร็จสิ้น') {
        where.add("s.status = 'completed'");
      } else if (filter.status == 'รอตรวจสอบ' || filter.status == 'กำลังดำเนินการ') {
        where.add("s.status = 'in_progress'");
      } else if (filter.status == 'ยังไม่เริ่ม') {
        where.add("(s.status = 'pending' AND date(s.scheduled_date) >= date('now', 'localtime'))");
      }
    }
    if (filter.search != null && filter.search!.trim().isNotEmpty) {
      where.add('(m.machine_no LIKE @search OR m.brand LIKE @search OR pl.plan_name LIKE @search OR sn.machine_no LIKE @search)');
      params['search'] = '%${filter.search!.trim()}%';
    }
    final rows = await DbHelper.query(
      '''SELECT s.schedule_id, s.plan_id, s.scheduled_date, s.status,
                s.assigned_to, s.attachments,
                pl.plan_code, pl.plan_name, pl.plan_type, pl.estimated_hours,
                pl.frequency_days, pl.frequency_months,
                COALESCE(sn.machine_no, m.machine_no) AS machine_no,
                COALESCE(sn.brand,      m.brand)      AS brand,
                u.full_name as assigned_to_name,
                (SELECT GROUP_CONCAT(task_name, ' / ') FROM pm_am_tasks WHERE plan_id = pl.plan_id) AS task_topics
         FROM pm_am_schedules s
         JOIN pm_am_plans pl ON pl.plan_id = s.plan_id
         LEFT JOIN machines m  ON m.machine_id = pl.machine_id
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
  
  String _searchQuery = '';
  String _statusFilter = 'ทั้งหมด';
  final Set<String> _selectedScheduleIds = {};
  bool _isPrinting = false;

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
    final filter = PmScheduleFilter(
      type: _tabs[_tabController.index].$2,
      search: _searchQuery,
      status: _statusFilter,
    );
    final schedulesAsync = ref.watch(pmSchedulesProvider(filter));

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
                  onPressed: () => _showImportFromMasterPlan(context),
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedDownload01, size: 18, color: Colors.white),
                  label: const Text('นำเข้าจากแผนแม่บท'),
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

        // Filter Bar
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, 0, AppSpacing.xxl, 0),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'ค้นหาเครื่องจักร, รหัสแผน...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 1,
                child: DropdownButtonFormField<String>(
                  value: _statusFilter,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ทั้งหมด', child: Text('ทุกสถานะ')),
                    DropdownMenuItem(value: 'ยังไม่เริ่ม', child: Text('ยังไม่เริ่ม')),
                    DropdownMenuItem(value: 'รอตรวจสอบ', child: Text('รอตรวจสอบ/กำลังดำเนินการ')),
                    DropdownMenuItem(value: 'เสร็จสิ้น', child: Text('เสร็จสิ้น')),
                    DropdownMenuItem(value: 'เกินกำหนด', child: Text('เกินกำหนด')),
                  ],
                  onChanged: (val) => setState(() => _statusFilter = val ?? 'ทั้งหมด'),
                ),
              ),
            ],
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
                      if (_selectedScheduleIds.isNotEmpty)
                        ElevatedButton.icon(
                          onPressed: _isPrinting ? null : () => _printSelectedSchedules(schedules),
                          icon: _isPrinting
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.print, size: 18),
                          label: Text('พิมพ์ ${_selectedScheduleIds.length} รายการ'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                        ),
                      const SizedBox(width: AppSpacing.md),
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
                      selectedIds: _selectedScheduleIds,
                      onSelect: (id, selected) {
                        setState(() {
                          if (selected) {
                            _selectedScheduleIds.add(id);
                          } else {
                            _selectedScheduleIds.remove(id);
                          }
                        });
                      },
                      onSelectAll: (selectAll) {
                        setState(() {
                          if (selectAll) {
                            _selectedScheduleIds.addAll(schedules.map((e) => e.scheduleId));
                          } else {
                            _selectedScheduleIds.clear();
                          }
                        });
                      },
                      onStartChecklist: _startChecklist,
                      onDelete: user?.isAdmin == true ? _deleteSchedule : null,
                      onAssign: (user?.isEngineerOrAbove ?? false) ? _assignTechnician : null,
                      onViewHistory: _viewHistory,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _printSelectedSchedules(List<PmSchedule> allSchedules) async {
    final toPrint = allSchedules.where((s) => _selectedScheduleIds.contains(s.scheduleId)).toList();
    if (toPrint.isEmpty) return;

    setState(() => _isPrinting = true);
    try {
      final user = ref.read(authProvider);
      final settings = ref.read(appSettingsProvider).valueOrNull;
      if (settings != null) {
        await PmAmPdfService.generateMultipleChecklistsPdf(
          schedules: toPrint,
          settings: settings,
          userName: user?.fullName ?? 'Unknown',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
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
        'DELETE FROM pm_am_schedules WHERE schedule_id = @id',
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

  void _showImportFromMasterPlan(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _ImportFromMasterPlanDialog(),
    ).then((_) => ref.invalidate(pmSchedulesProvider));
  }

  void _assignTechnician(PmSchedule schedule) {
    showDialog(
      context: context,
      builder: (ctx) => _AssignDialog(schedule: schedule),
    ).then((_) => ref.invalidate(pmSchedulesProvider));
  }

  void _viewHistory(PmSchedule schedule) {
    showDialog(
      context: context,
      builder: (ctx) => _HistoryDialog(schedule: schedule),
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
  final Set<String> selectedIds;
  final Function(String, bool) onSelect;
  final Function(bool) onSelectAll;
  final void Function(PmSchedule) onStartChecklist;
  final void Function(PmSchedule)? onDelete;
  final void Function(PmSchedule)? onAssign;
  final void Function(PmSchedule)? onViewHistory;

  const _ScheduleList({
    required this.schedules,
    this.user,
    required this.selectedIds,
    required this.onSelect,
    required this.onSelectAll,
    required this.onStartChecklist,
    this.onDelete,
    this.onAssign,
    this.onViewHistory,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allSelected = schedules.isNotEmpty && selectedIds.length == schedules.length;

    return Card(
      child: Column(
        children: [
          // Header row for Select All
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
            child: Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: (v) => onSelectAll(v ?? false),
                ),
                const Text('เลือกทั้งหมด', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
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

                final isSelected = selectedIds.contains(s.scheduleId);

                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.md),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        onChanged: (v) => onSelect(s.scheduleId, v ?? false),
                      ),
                      const SizedBox(width: AppSpacing.sm),
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
                      if (s.taskTopics != null && s.taskTopics!.isNotEmpty)
                        Text(s.taskTopics!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(
                        '${s.planCode} · ${s.machineNo}${s.machineBrand != null ? ' · ${s.machineBrand}' : ''}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                // Assigned person (clickable to assign)
                SizedBox(
                  width: 140,
                  child: GestureDetector(
                    onTap: (user?.isEngineerOrAbove ?? false) && s.status != 'completed'
                        ? () => onAssign?.call(s)
                        : null,
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.assignedToName ?? 'ยังไม่มอบหมาย',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: s.assignedToName != null
                                      ? AppColors.primary
                                      : Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontWeight: s.assignedToName != null
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if ((user?.isEngineerOrAbove ?? false) && s.status != 'completed')
                          Icon(Icons.edit, size: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ],
                    ),
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
                // Status badge
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
                const SizedBox(width: AppSpacing.sm),
                // History button (always visible)
                IconButton(
                  icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedClock01,
                      size: 18,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                  tooltip: 'ประวัติ PM/AM',
                  onPressed: () => onViewHistory?.call(s),
                ),
                // Attachment indicator
                if (s.attachments.isNotEmpty)
                  Tooltip(
                    message: 'มีไฟล์แนบ ${s.attachments.length} ไฟล์',
                    child: const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: HugeIcon(
                          icon: HugeIcons.strokeRoundedAttachment01,
                          size: 16,
                          color: AppColors.primary),
                    ),
                  ),
                // Actions
                if (s.status != 'completed' && (user?.isTechnicianOrAbove ?? false))
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedPrinter, size: 20, color: AppColors.primary),
                        onPressed: () {
                          final settings = ref.read(appSettingsProvider).valueOrNull;
                          final u = ref.read(authProvider);
                          if (settings != null) {
                            PmAmPdfService.generateChecklistPdf(
                              schedule: s,
                              settings: settings,
                              userName: u?.fullName ?? 'System User',
                            );
                          }
                        },
                        tooltip: 'พิมพ์ Checklist',
                      ),
                      const SizedBox(width: 4),
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
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
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
                          final u = ref.read(authProvider);
                          if (settings != null) {
                            PmAmPdfService.generateChecklistPdf(
                              schedule: s,
                              settings: settings,
                              userName: u?.fullName ?? 'System User',
                            );
                          }
                        },
                        tooltip: 'พิมพ์ผลการตรวจ',
                      ),
                      if (onDelete != null) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.red, size: 20),
                          onPressed: () => onDelete!(s),
                          tooltip: 'ลบแผนงาน',
                        ),
                      ],
                    ],
                  )
                else
                  const SizedBox(width: 120),
              ],
            ),
          );
        },
      ),
    ),
        ],
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
  final Map<String, String> _values = {};  // taskId -> actual_value
  final Map<String, String> _remarks = {}; // taskId -> remarks
  late List<String> _attachments;          // file paths
  bool _saving = false;

  final _tasksProvider = FutureProvider.autoDispose
      .family<List<Map<String, dynamic>>, String>((ref, planId) async {
    return await DbHelper.query(
      'SELECT * FROM pm_am_tasks WHERE plan_id = @pid ORDER BY task_order',
      params: {'pid': planId},
    );
  });

  @override
  void initState() {
    super.initState();
    _attachments = List<String>.from(widget.schedule.attachments);
  }

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(_tasksProvider(widget.schedule.planId));

    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text('Checklist: ${widget.schedule.planName}', overflow: TextOverflow.ellipsis)),
          // Machine & assigned info
          Text(
            'เครื่อง: ${widget.schedule.machineNo}'
            '${widget.schedule.assignedToName != null ? '  ·  ผู้รับผิดชอบ: ${widget.schedule.assignedToName}' : ''}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal,
                color: AppColors.textSecondary),
          ),
        ],
      ),
      content: SizedBox(
        width: 700,
        height: 560,
        child: Column(
          children: [
            // Tasks list
            Expanded(
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
                                  child: HugeIcon(
                                    icon: _typeIcon(type),
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
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  onTap: () => setState(() => _results[tid] = 'na'),
                                ),
                                const Spacer(),
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
                              ],
                            ),
                            if (result == 'fail' || result == 'na')
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        decoration: InputDecoration(
                                          labelText: 'หมายเหตุ / ปัญหาที่พบ',
                                          isDense: true,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        style: const TextStyle(fontSize: 12),
                                        onChanged: (v) => _remarks[tid] = v,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                      onPressed: () => _showRepairForm(t, _remarks[tid] ?? ''),
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
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            // ───── Attachments section ─────
            const Divider(height: 16),
            _AttachmentsSection(
              attachments: _attachments,
              onAdd: _pickFiles,
              onRemove: _removeAttachment,
              onOpen: _openFile,
            ),
          ],
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

  List<List<dynamic>> _typeIcon(String type) {
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

  Future<void> _showRepairForm(Map<String, dynamic> task, String remark) async {
    final res = await DbHelper.query(
        'SELECT machine_id FROM machines WHERE machine_no = @mno',
        params: {'mno': widget.schedule.machineNo});
    String? machineId;
    if (res.isNotEmpty) {
      machineId = res.first['machine_id'] as String;
    }

    final String probDesc = remark.isNotEmpty
        ? 'แจ้งซ่อมจากแผน ${widget.schedule.planName} (${task['task_name']})\nหมายเหตุ: $remark'
        : 'แจ้งซ่อมจากแผน ${widget.schedule.planName} (${task['task_name']})';

    final tempWo = WorkOrder(
      woId: const Uuid().v4(),
      woNo: '',
      machineId: machineId,
      machineNo: widget.schedule.machineNo,
      description: probDesc,
      reportedAt: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      status: WorkOrderStatus.pending,
      priority: WorkOrderPriority.normal,
    );

    if (mounted) {
      context.push('/work-orders/new', extra: tempWo);
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.any,
    );
    if (result != null) {
      setState(() {
        for (final f in result.files) {
          if (f.path != null && !_attachments.contains(f.path)) {
            _attachments.add(f.path!);
          }
        }
      });
    }
  }

  void _removeAttachment(String path) {
    setState(() => _attachments.remove(path));
  }

  Future<void> _openFile(String path) async {
    await OpenFilex.open(path);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final now = DateTime.now().toIso8601String();
      final user = ref.read(authProvider);
      final attachJson = jsonEncode(_attachments);

      await DbHelper.transaction((tx) async {
        // 1. Update schedule status + attachments
        await DbHelper.txExecute(tx,
          '''UPDATE pm_am_schedules
             SET status = 'completed', updated_at = @now, attachments = @att
             WHERE schedule_id = @sid''',
          params: {'sid': widget.schedule.scheduleId, 'now': now, 'att': attachJson},
        );

        // 2. Insert execution records
        for (final entry in _results.entries) {
          final taskId = entry.key;
          final result = entry.value;
          final actualValue = _values[taskId];
          final rem = _remarks[taskId];
          await DbHelper.txExecute(tx,
            '''INSERT INTO pm_am_executions (
                 execution_id, schedule_id, task_id, executed_by,
                 completed_at, result, actual_value, remarks, created_at
               ) VALUES (
                 @eid, @sid, @tid, @uid, @now, @res, @val, @rem, @now
               )''',
            params: {
              'eid': 'exec_${DateTime.now().millisecondsSinceEpoch}_$taskId',
              'sid': widget.schedule.scheduleId,
              'tid': taskId,
              'uid': user?.userId,
              'now': now,
              'res': result,
              'val': actualValue,
              'rem': rem,
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
// Attachments Section Widget
// ─────────────────────────────────────────────────────────────────────────────

class _AttachmentsSection extends StatelessWidget {
  final List<String> attachments;
  final VoidCallback onAdd;
  final void Function(String) onRemove;
  final void Function(String) onOpen;

  const _AttachmentsSection({
    required this.attachments,
    required this.onAdd,
    required this.onRemove,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const HugeIcon(icon: HugeIcons.strokeRoundedAttachment01, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('ไฟล์แนบ (${attachments.length})', style: AppTextStyles.labelMedium.copyWith(color: AppColors.primary)),
            const Spacer(),
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('แนบไฟล์', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
            ),
          ],
        ),
        if (attachments.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: attachments.map((path) {
              final name = path.split(RegExp(r'[/\\]')).last;
              final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
              final isImage = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext);
              return Chip(
                avatar: Icon(isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined, size: 14),
                label: Text(name, style: const TextStyle(fontSize: 11)),
                onDeleted: () => onRemove(path),
                deleteIcon: const Icon(Icons.close, size: 14),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
              );
            }).toList(),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Assign Technician Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _AssignDialog extends ConsumerStatefulWidget {
  final PmSchedule schedule;
  const _AssignDialog({required this.schedule});

  @override
  ConsumerState<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends ConsumerState<_AssignDialog> {
  String? _selectedUserId;
  bool _saving = false;

  final _usersProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
    return await DbHelper.query(
      '''SELECT user_id, full_name, role
         FROM users
         WHERE is_active = 1 AND role IN ('technician','engineer','admin','supervisor')
         ORDER BY full_name''',
    );
  });

  @override
  void initState() {
    super.initState();
    _selectedUserId = widget.schedule.assignedTo;
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(_usersProvider);
    return AlertDialog(
      title: Text('มอบหมายงาน: ${widget.schedule.planName}',
          style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 420,
        child: usersAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (users) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('เครื่องจักร: ${widget.schedule.machineNo}  ·  วันที่: ${DateFormat('dd/MM/yyyy').format(widget.schedule.scheduledDate)}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              Text('เลือกช่างผู้รับผิดชอบ', style: AppTextStyles.labelMedium),
              const SizedBox(height: 8),
              ...users.map((u) {
                final uid = u['user_id'] as String;
                final name = u['full_name'] as String? ?? '-';
                final roleStr = u['role'] as String? ?? '';
                final pos = roleStr.toUpperCase();
                return InkWell(
                  onTap: () => setState(() => _selectedUserId = uid),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      children: [
                        Radio<String>(
                          value: uid,
                          groupValue: _selectedUserId,
                          onChanged: (v) => setState(() => _selectedUserId = v),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              if (pos.isNotEmpty)
                                Text(pos, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              if (_selectedUserId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextButton.icon(
                    onPressed: () => setState(() => _selectedUserId = null),
                    icon: const Icon(Icons.clear, size: 14, color: AppColors.error),
                    label: const Text('ยกเลิกการมอบหมาย', style: TextStyle(color: AppColors.error, fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('บันทึก'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await DbHelper.execute(
        'UPDATE pm_am_schedules SET assigned_to = @uid WHERE schedule_id = @sid',
        params: {'uid': _selectedUserId, 'sid': widget.schedule.scheduleId},
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History Dialog — ประวัติการทำ PM/AM ของแผนนี้
// ─────────────────────────────────────────────────────────────────────────────

final _historyProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, planId) async {
  return await DbHelper.query(
    '''SELECT s.schedule_id, s.scheduled_date, s.status, s.attachments,
              u.full_name AS technician,
              COUNT(e.execution_id) AS task_count,
              SUM(CASE WHEN e.result = 'pass' THEN 1 ELSE 0 END) AS pass_count,
              SUM(CASE WHEN e.result = 'fail' THEN 1 ELSE 0 END) AS fail_count
       FROM pm_am_schedules s
       LEFT JOIN users u ON u.user_id = s.assigned_to
       LEFT JOIN pm_am_executions e ON e.schedule_id = s.schedule_id
       WHERE s.plan_id = @pid
       GROUP BY s.schedule_id
       ORDER BY s.scheduled_date DESC
       LIMIT 50''',
    params: {'pid': planId},
  );
});

class _HistoryDialog extends ConsumerWidget {
  final PmSchedule schedule;
  const _HistoryDialog({required this.schedule});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(_historyProvider(schedule.planId));
    return AlertDialog(
      title: Row(
        children: [
          const HugeIcon(icon: HugeIcons.strokeRoundedClock01, size: 20, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('ประวัติ: ${schedule.planName}', style: const TextStyle(fontSize: 15))),
          Text(schedule.machineNo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal, color: AppColors.textSecondary)),
        ],
      ),
      content: SizedBox(
        width: 700,
        height: 480,
        child: historyAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (rows) => rows.isEmpty
              ? const Center(child: Text('ยังไม่มีประวัติการทำ PM/AM'))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary row
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text('ทั้งหมด ${rows.length} ครั้ง', style: AppTextStyles.labelMedium),
                    ),
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: Row(
                        children: const [
                          SizedBox(width: 100, child: Text('วันที่', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                          SizedBox(width: 100, child: Text('สถานะ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                          SizedBox(width: 130, child: Text('ช่าง', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                          SizedBox(width: 80, child: Text('ผ่าน/ทั้งหมด', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                          Expanded(child: Text('ไฟล์แนบ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _a) => const Divider(height: 1),
                        itemBuilder: (ctx, i) {
                          final r = rows[i];
                          final date = DateTime.tryParse(r['scheduled_date'] as String? ?? '');
                          final status = r['status'] as String? ?? '';
                          final technician = r['technician'] as String? ?? '-';
                          final taskCount = (r['task_count'] as num?)?.toInt() ?? 0;
                          final passCount = (r['pass_count'] as num?)?.toInt() ?? 0;
                          final failCount = (r['fail_count'] as num?)?.toInt() ?? 0;
                          List<String> attachments = [];
                          try {
                            final raw = r['attachments'] as String?;
                            if (raw != null && raw.isNotEmpty) {
                              attachments = List<String>.from(jsonDecode(raw) as List);
                            }
                          } catch (_) {}
                          final isCompleted = status == 'completed';
                          final statusColor = isCompleted ? AppColors.success : AppColors.warning;

                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                // Date
                                SizedBox(
                                  width: 100,
                                  child: Text(
                                    date != null ? DateFormat('dd/MM/yyyy').format(date) : '-',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                // Status
                                SizedBox(
                                  width: 100,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      isCompleted ? 'เสร็จสิ้น' : 'รอดำเนินการ',
                                      style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                // Technician
                                SizedBox(
                                  width: 130,
                                  child: Text(technician, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                                ),
                                // Pass/Total
                                SizedBox(
                                  width: 80,
                                  child: taskCount > 0
                                      ? RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(text: '$passCount', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
                                              TextSpan(text: '/$taskCount', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface, fontSize: 12)),
                                              if (failCount > 0)
                                                TextSpan(text: '  ⚠$failCount', style: const TextStyle(color: AppColors.error, fontSize: 11)),
                                            ],
                                          ),
                                        )
                                      : const Text('-', style: TextStyle(fontSize: 12)),
                                ),
                                // Attachments
                                Expanded(
                                  child: attachments.isEmpty
                                      ? const Text('-', style: TextStyle(fontSize: 12))
                                      : Wrap(
                                          spacing: 4,
                                          children: attachments.map((path) {
                                            final name = path.split(RegExp(r'[/\\]')).last;
                                            return ActionChip(
                                              label: Text(name, style: const TextStyle(fontSize: 10)),
                                              avatar: const Icon(Icons.attach_file, size: 12),
                                              onPressed: () => OpenFilex.open(path),
                                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              visualDensity: VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                            );
                                          }).toList(),
                                        ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ปิด')),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Import From Master Plan Dialog
// ─────────────────────────────────────────────────────────────────────────────

/// Model ย่อสำหรับแสดงรายการแผนแม่บทใน dialog
class _MasterPlanItem {
  final String planId;
  final String planCode;
  final String planName;
  final String planType;
  final String machineNo;
  final String? machineBrand;
  final int? frequencyDays;
  final int? frequencyMonths;
  final String? taskTopics;
  bool selected;

  _MasterPlanItem({
    required this.planId,
    required this.planCode,
    required this.planName,
    required this.planType,
    required this.machineNo,
    this.machineBrand,
    this.frequencyDays,
    this.frequencyMonths,
    this.taskTopics,
    this.selected = false,
  });

  factory _MasterPlanItem.fromMap(Map<String, dynamic> m) => _MasterPlanItem(
        planId: m['plan_id'] as String,
        planCode: m['plan_code'] as String? ?? '-',
        planName: m['plan_name'] as String? ?? '-',
        planType: m['plan_type'] as String? ?? 'PM',
        machineNo: m['machine_no'] as String? ?? '-',
        machineBrand: m['brand'] as String?,
        frequencyDays: m['frequency_days'] as int?,
        frequencyMonths: m['frequency_months'] as int?,
        taskTopics: m['task_topics'] as String?,
      );
}

class _ImportFromMasterPlanDialog extends ConsumerStatefulWidget {
  const _ImportFromMasterPlanDialog();

  @override
  ConsumerState<_ImportFromMasterPlanDialog> createState() =>
      _ImportFromMasterPlanDialogState();
}

class _ImportFromMasterPlanDialogState
    extends ConsumerState<_ImportFromMasterPlanDialog> {
  List<_MasterPlanItem> _plans = [];
  bool _loading = true;
  bool _saving = false;
  String _typeFilter = 'ทั้งหมด';
  DateTime _scheduledDate = DateTime.now();
  String _errorMsg = '';

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final rows = await DbHelper.query(
        '''SELECT 
             p.plan_id, p.plan_code, p.plan_name, p.plan_type,
             p.frequency_days, p.frequency_months,
             m.machine_no, m.brand,
             (SELECT GROUP_CONCAT(task_name, ' / ') FROM pm_am_tasks WHERE plan_id = p.plan_id) AS task_topics
           FROM pm_am_plans p
           JOIN machines m ON m.machine_id = p.machine_id
           WHERE p.status = 'active' AND m.is_active = 1
           ORDER BY p.plan_type ASC, m.machine_no ASC''',
      );
      setState(() {
        _plans = rows.map(_MasterPlanItem.fromMap).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = 'โหลดข้อมูลล้มเหลว: $e';
        _loading = false;
      });
    }
  }

  List<_MasterPlanItem> get _filteredPlans {
    if (_typeFilter == 'ทั้งหมด') return _plans;
    return _plans.where((p) => p.planType == _typeFilter).toList();
  }

  int get _selectedCount => _plans.where((p) => p.selected).length;

  void _toggleAll(bool? value) {
    setState(() {
      for (final p in _filteredPlans) {
        p.selected = value ?? false;
      }
    });
  }

  Future<void> _import() async {
    final selected = _plans.where((p) => p.selected).toList();
    if (selected.isEmpty) return;

    setState(() => _saving = true);
    try {
      final dateStr = _scheduledDate.toIso8601String().substring(0, 10);
      int count = 0;
      for (final plan in selected) {
        // ตรวจสอบว่ามี schedule ของวันนี้อยู่แล้วหรือไม่
        final existing = await DbHelper.query(
          '''SELECT 1 FROM pm_am_schedules 
             WHERE plan_id = @pid 
               AND DATE(scheduled_date) = @date 
               AND status != 'cancelled'
             LIMIT 1''',
          params: {'pid': plan.planId, 'date': dateStr},
        );
        if (existing.isNotEmpty) continue; // ข้ามถ้ามีอยู่แล้ว

        final schedId =
            'sched_${DateTime.now().millisecondsSinceEpoch}_${count}_${plan.planId.substring(plan.planId.length > 6 ? plan.planId.length - 4 : 0)}';
        await DbHelper.execute(
          '''INSERT INTO pm_am_schedules (schedule_id, plan_id, scheduled_date, status)
             VALUES (@sid, @pid, @date, 'pending')''',
          params: {
            'sid': schedId,
            'pid': plan.planId,
            'date': '$dateStr 00:00:00',
          },
        );
        count++;
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count > 0
                  ? 'นำเข้ากำหนดการสำเร็จ $count รายการ'
                  : 'ไม่มีรายการใหม่ที่ต้องนำเข้า (มีกำหนดการในวันที่นี้อยู่แล้ว)',
            ),
            backgroundColor: count > 0 ? AppColors.success : AppColors.warning,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredPlans;
    final allSelected =
        filtered.isNotEmpty && filtered.every((p) => p.selected);
    final someSelected = filtered.any((p) => p.selected);

    return AlertDialog(
      title: Row(
        children: [
          const HugeIcon(
              icon: HugeIcons.strokeRoundedDownload01,
              size: 22,
              color: AppColors.primary),
          const SizedBox(width: 8),
          const Text('นำเข้าจากแผนแม่บท'),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date picker row
            Row(
              children: [
                const Text('วันที่กำหนดการ:',
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _scheduledDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) {
                      setState(() => _scheduledDate = picked);
                    }
                  },
                  icon: const Icon(Icons.calendar_today, size: 16),
                  label: Text(
                    DateFormat('dd/MM/yyyy').format(_scheduledDate),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                const Spacer(),
                // Type filter
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ทั้งหมด', label: Text('ทั้งหมด')),
                    ButtonSegment(value: 'PM', label: Text('PM')),
                    ButtonSegment(value: 'AM', label: Text('AM')),
                  ],
                  selected: {_typeFilter},
                  onSelectionChanged: (s) =>
                      setState(() => _typeFilter = s.first),
                  style: const ButtonStyle(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (!_loading && _errorMsg.isEmpty && filtered.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Checkbox(
                      value: allSelected ? true : (someSelected ? null : false),
                      tristate: true,
                      onChanged: _toggleAll,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'เลือกทั้งหมด (${filtered.length} รายการ)',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      'เลือกแล้ว $_selectedCount รายการ',
                      style: TextStyle(
                          fontSize: 12,
                          color: _selectedCount > 0
                              ? AppColors.primary
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),

            // Plan list
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _errorMsg.isNotEmpty
                      ? Center(
                          child: Text(_errorMsg,
                              style:
                                  const TextStyle(color: AppColors.error)))
                      : filtered.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inbox_outlined,
                                      size: 48,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'ไม่พบแผนแม่บทที่อนุมัติแล้ว\nกรุณาตั้งค่าแผนแม่บทก่อน',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final plan = filtered[i];
                                return CheckboxListTile(
                                  dense: true,
                                  value: plan.selected,
                                  onChanged: (v) =>
                                      setState(() => plan.selected = v ?? false),
                                  title: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        plan.planName,
                                        style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500),
                                      ),
                                      if (plan.taskTopics != null && plan.taskTopics!.isNotEmpty)
                                        Text(
                                          plan.taskTopics!,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                    ],
                                  ),
                                  subtitle: Text(
                                    '${plan.planCode} · ${plan.machineNo}${plan.machineBrand != null ? ' · ${plan.machineBrand}' : ''}'
                                    '${plan.frequencyDays != null ? ' · ทุก ${plan.frequencyDays} วัน' : ''}'
                                    '${plan.frequencyMonths != null ? ' · ทุก ${plan.frequencyMonths} เดือน' : ''}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  secondary: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: (plan.planType == 'PM'
                                              ? AppColors.primary
                                              : AppColors.machineAM)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      plan.planType,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: plan.planType == 'PM'
                                            ? AppColors.primary
                                            : AppColors.machineAM,
                                      ),
                                    ),
                                  ),
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        ElevatedButton.icon(
          onPressed:
              (_saving || _selectedCount == 0) ? null : _import,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: Colors.white))
              : const HugeIcon(
                  icon: HugeIcons.strokeRoundedDownload01,
                  size: 16,
                  color: Colors.white),
          label: Text(_saving
              ? 'กำลังนำเข้า...'
              : 'นำเข้า $_selectedCount รายการ'),
        ),
      ],
    );
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
