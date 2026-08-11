import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/database/db_helper.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:empty_view/empty_view.dart';
import '../auth/auth_provider.dart';
import '../settings/settings_provider.dart';
import 'pm_am_pdf_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class MachinePmSummary {
  final String machineId;
  final String machineNo;
  final String? machineBrand;
  final int planCount;
  final String? status; // active, suspended
  final String? remark;

  bool get hasPlan => planCount > 0;

  const MachinePmSummary({
    required this.machineId,
    required this.machineNo,
    this.machineBrand,
    required this.planCount,
    this.status,
    this.remark,
  });

  factory MachinePmSummary.fromMap(Map<String, dynamic> m) {
    return MachinePmSummary(
      machineId: m['machine_id'] as String,
      machineNo: m['machine_no'] as String? ?? '-',
      machineBrand: m['brand'] as String?,
      planCount: (m['plan_count'] as num?)?.toInt() ?? 0,
      status: m['plan_status'] as String?,
      remark: m['plan_description'] as String?,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final pmPlansProvider =
    FutureProvider.family<List<MachinePmSummary>, String>((ref, type) async {
  try {
    final rows = await DbHelper.query(
      '''SELECT 
           m.machine_id, m.machine_no, m.brand,
           COUNT(pl.plan_id) as plan_count,
           MAX(pl.status) as plan_status,
           MAX(pl.description) as plan_description
         FROM machines m
         LEFT JOIN pm_am_plans pl ON pl.machine_id = m.machine_id AND pl.plan_type = @type
         WHERE m.is_active = 1
         GROUP BY m.machine_id, m.machine_no, m.brand
         ORDER BY m.machine_no ASC
         LIMIT 300''',
      params: {'type': type},
    );
    return rows.map(MachinePmSummary.fromMap).toList();
  } catch (e) {
    debugPrint('Error loading machines: $e');
    return [];
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class PmAmPlanScreen extends ConsumerStatefulWidget {
  const PmAmPlanScreen({super.key});

  @override
  ConsumerState<PmAmPlanScreen> createState() => _PmAmPlanScreenState();
}

class _PmAmPlanScreenState extends ConsumerState<PmAmPlanScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = ['PM', 'AM'];

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
    final currentType = _tabs[_tabController.index];
    final plansAsync = ref.watch(pmPlansProvider(currentType));

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
                    const HugeIcon(icon: HugeIcons.strokeRoundedBookOpen01,
                        color: AppColors.primary, size: 24),
                    const SizedBox(width: AppSpacing.sm),
                    Text('แผนแม่บท PM / AM',
                        style: AppTextStyles.headlineLarge),
                  ]),
                  const SizedBox(height: 4),
                  Text('รายชื่อเครื่องจักรและการตั้งค่ารายละเอียด PM/AM',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _printAllLogsheet(currentType),
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedFileEdit, size: 18, color: Colors.teal),
                label: const Text('พิมพ์ Logsheet ทั้งหมด', style: TextStyle(color: Colors.teal)),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 20, color: AppColors.textSecondary),
                tooltip: 'รีเฟรชข้อมูล',
                onPressed: () => ref.invalidate(pmPlansProvider),
              ),
            ],
          ),
        ),

        // Tabs
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: _tabs
              .map((t) => Tab(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(t),
                    ),
                  ))
              .toList(),
          labelStyle:
              const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          unselectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.normal, fontSize: 14),
          dividerColor: AppColors.divider,
        ),
        const SizedBox(height: AppSpacing.lg),

        // Content
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.xxl),
            child: plansAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (plans) => plans.isEmpty
                  ? EmptyView(
                      title: 'ไม่มีข้อมูลเครื่องจักร',
                      description: 'ไม่พบเครื่องจักรในระบบ',
                      onButtonTap: () => ref.invalidate(pmPlansProvider),
                    )
                  : _PlanList(
                      plans: plans,
                      currentType: currentType,
                      onEdit: (m) => _showPlanForm(m, currentType),
                      onView: (m) => _showPlanView(m, currentType),
                      onDelete: (m) => _deletePlan(m, currentType),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _printAllLogsheet(String planType) async {
    try {
      // Fetch all tasks for all machines that have plans of this type
      final rows = await DbHelper.query(
        '''SELECT 
             m.machine_no, m.brand,
             p.plan_id, p.frequency_days, p.frequency_months,
             t.task_name, t.expected_result,
             u2.full_name as approver_name
           FROM machines m
           JOIN pm_am_plans p ON p.machine_id = m.machine_id AND p.plan_type = @type
           LEFT JOIN pm_am_tasks t ON t.plan_id = p.plan_id
           LEFT JOIN users u2 ON p.approved_by = u2.user_id
           WHERE m.is_active = 1
           ORDER BY m.machine_no ASC, p.created_at ASC''',
        params: {'type': planType},
      );

      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('ไม่พบแผนที่ตั้งค่าไว้ กรุณาตั้งค่าแผนก่อน')),
          );
        }
        return;
      }

      final settingsAsync = ref.read(appSettingsProvider);
      final settings = settingsAsync.valueOrNull ?? 
          await ref.read(appSettingsProvider.future).catchError((_) => AppSettingsState());
      final user = ref.read(authProvider);

      await PmAmPdfService.generateAllMachinesLogsheetPdf(
        planType: planType,
        rows: rows,
        settings: settings,
        userName: user?.fullName ?? 'ไม่ระบุตัวตน',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    }
  }

  void _showPlanForm(MachinePmSummary machine, String type) {
    showDialog(
      context: context,
      builder: (ctx) => _PlanFormDialog(summary: machine, planType: type),
    ).then((_) => ref.invalidate(pmPlansProvider));
  }

  void _showPlanView(MachinePmSummary machine, String type) {
    showDialog(
      context: context,
      builder: (ctx) => _PlanViewDialog(
        summary: machine, 
        planType: type,
        onEdit: () => _showPlanForm(machine, type),
      ),
    ).then((_) => ref.invalidate(pmPlansProvider));
  }

  Future<void> _deletePlan(MachinePmSummary machine, String type) async {
    if (!machine.hasPlan) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการล้างข้อมูลแผน'),
        content: Text('คุณต้องการล้างข้อมูลแผนงาน $type ทั้งหมดของเครื่องจักร "${machine.machineNo}" ใช่หรือไม่?\n(กำหนดการที่เคยถูกสร้างไว้แล้วจะถูกลบไปด้วย)'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ล้างข้อมูลแผน'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await DbHelper.execute(
        'DELETE FROM pm_am_plans WHERE machine_id = @mid AND plan_type = @type',
        params: {'mid': machine.machineId, 'type': type},
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ล้างข้อมูลแผนสำเร็จ')),
        );
        ref.invalidate(pmPlansProvider);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    }
  }
}

class _PlanList extends StatelessWidget {
  final List<MachinePmSummary> plans;
  final String currentType;
  final void Function(MachinePmSummary) onEdit;
  final void Function(MachinePmSummary) onView;
  final void Function(MachinePmSummary) onDelete;

  const _PlanList({
    required this.plans,
    required this.currentType,
    required this.onEdit,
    required this.onView,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: ListView.separated(
        itemCount: plans.length,
        separatorBuilder: (context, index) =>
            const Divider(height: 1, color: AppColors.divider),
        itemBuilder: (context, index) {
          final p = plans[index];
          
          final isPM = currentType == 'PM';
          final badgeColor = p.hasPlan ? (isPM ? Colors.blue.shade100 : Colors.purple.shade100) : Colors.grey.shade200;
          final badgeTextColor = p.hasPlan ? (isPM ? Colors.blue.shade800 : Colors.purple.shade800) : Colors.grey.shade600;

          return InkWell(
            onTap: () => p.hasPlan ? onView(p) : onEdit(p),
            hoverColor: Colors.grey.shade50,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Type Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      currentType,
                      style: TextStyle(
                        color: badgeTextColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Machine Info
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'เครื่องจักร: ${p.machineNo} ${p.machineBrand ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          p.hasPlan ? 'มีการตั้งค่าแผน $currentType จำนวน ${p.planCount} รายการ' : 'ยังไม่ได้ตั้งค่าแผน $currentType',
                          style: TextStyle(color: p.hasPlan ? Colors.grey.shade800 : Colors.red.shade300, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Status
                  if (p.hasPlan) ...[
                    Builder(
                      builder: (context) {
                        Color bgColor;
                        Color borderColor;
                        Color textColor;
                        String text;

                        switch (p.status) {
                          case 'active':
                            bgColor = Colors.green.shade50;
                            borderColor = Colors.green.shade200;
                            textColor = Colors.green.shade700;
                            text = 'อนุมัติ / ใช้งานอยู่';
                            break;
                          case 'pending_approval':
                            bgColor = Colors.orange.shade50;
                            borderColor = Colors.orange.shade200;
                            textColor = Colors.orange.shade700;
                            text = 'รออนุมัติแผน';
                            break;
                          case 'draft':
                            bgColor = Colors.blue.shade50;
                            borderColor = Colors.blue.shade200;
                            textColor = Colors.blue.shade700;
                            text = 'แบบร่างแผน';
                            break;
                          case 'rejected':
                            bgColor = Colors.red.shade50;
                            borderColor = Colors.red.shade200;
                            textColor = Colors.red.shade700;
                            text = 'ตีกลับแก้ไขแผน';
                            break;
                          case 'suspended':
                          default:
                            bgColor = Colors.grey.shade100;
                            borderColor = Colors.grey.shade300;
                            textColor = Colors.grey.shade600;
                            text = 'ระงับการใช้งาน';
                            break;
                        }
                        
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor),
                          ),
                          child: Text(text, style: TextStyle(fontSize: 11, color: textColor)),
                        );
                      }
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  
                  // View Button or Setup Button
                  if (p.hasPlan)
                    TextButton.icon(
                      onPressed: () => onView(p),
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedView, 
                        size: 18, 
                        color: AppColors.primary
                      ),
                      label: const Text('ดูรายละเอียด', style: TextStyle(color: AppColors.primary)),
                    )
                  else
                    TextButton.icon(
                      onPressed: () => onEdit(p),
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedPlusSign, 
                        size: 18, 
                        color: Colors.orange
                      ),
                      label: Text('ตั้งค่าแผน $currentType', style: const TextStyle(color: Colors.orange)),
                    ),
                  
                  // Edit Button (only if plan exists)
                  if (p.hasPlan)
                    IconButton(
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit02, size: 20, color: AppColors.primary),
                      onPressed: () => onEdit(p),
                      tooltip: 'แก้ไขแผน $currentType',
                    ),
                  
                  // Delete Action (only if plan exists)
                  if (p.hasPlan)
                    IconButton(
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 20, color: Colors.red),
                      onPressed: () => onDelete(p),
                      tooltip: 'ล้างข้อมูลแผน $currentType',
                    )
                  else
                    const SizedBox(width: 40),
                    
                  const SizedBox(width: AppSpacing.sm),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// View Plan Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _PlanViewDialog extends ConsumerStatefulWidget {
  final MachinePmSummary summary;
  final String planType;
  final VoidCallback onEdit;
  
  const _PlanViewDialog({required this.summary, required this.planType, required this.onEdit});

  @override
  ConsumerState<_PlanViewDialog> createState() => _PlanViewDialogState();
}

class _PlanViewDialogState extends ConsumerState<_PlanViewDialog> {
  bool _loading = true;
  List<Map<String, dynamic>> _tasks = [];

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      final rows = await DbHelper.query(
        '''SELECT p.plan_id, p.frequency_days, p.frequency_months, t.task_name, t.expected_result,
                  u1.full_name as creator_name,
                  u2.full_name as approver_name
           FROM pm_am_plans p 
           LEFT JOIN pm_am_tasks t ON t.plan_id = p.plan_id 
           LEFT JOIN users u1 ON p.created_by = u1.user_id
           LEFT JOIN users u2 ON p.approved_by = u2.user_id
           WHERE p.machine_id = @mid AND p.plan_type = @type
           ORDER BY p.created_at ASC''',
        params: {'mid': widget.summary.machineId, 'type': widget.planType},
      );
      if (mounted) {
        setState(() {
          _tasks = rows;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final machineName = '${widget.summary.machineNo} ${widget.summary.machineBrand ?? ''}'.trim();
    
    return AlertDialog(
      title: Row(
        children: [
          Text('รายละเอียดแผน ${widget.planType}'),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _getBadgeColor(widget.summary.status),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _getBadgeBorderColor(widget.summary.status)),
            ),
            child: Text(
              _getStatusText(widget.summary.status),
              style: TextStyle(fontSize: 12, color: _getBadgeTextColor(widget.summary.status)),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        child: _loading 
            ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 20, color: AppColors.primaryDark),
                          const SizedBox(width: 8),
                          Text('เครื่องจักร: ', style: TextStyle(color: Colors.grey.shade700)),
                          Text(machineName, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryDark)),
                        ],
                      ),
                    ),
                    if (widget.summary.status == 'rejected' && widget.summary.remark != null && widget.summary.remark!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('เหตุผลการตีกลับ:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                            const SizedBox(height: 4),
                            Text(widget.summary.remark!, style: TextStyle(color: Colors.red.shade900)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    const Text('รายการเช็คลิสต์', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: AppSpacing.sm),
                    
                    if (_tasks.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: Text('ไม่พบรายการเช็คลิสต์', style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ..._tasks.asMap().entries.map((entry) {
                        final i = entry.key;
                        final t = entry.value;
                        final String days = t['frequency_days']?.toString() ?? '';
                        final String months = t['frequency_months']?.toString() ?? '';
                        String freqStr = '';
                        if (days.isNotEmpty && months.isNotEmpty) {
                          freqStr = 'ทุก $days วัน และ $months เดือน';
                        } else if (days.isNotEmpty) {
                          freqStr = 'ทุก $days วัน';
                        } else if (months.isNotEmpty) {
                          freqStr = 'ทุก $months เดือน';
                        } else {
                          freqStr = '-';
                        }
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade200),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))
                            ]
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                    child: Text('ข้อที่ ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryDark, fontSize: 12)),
                                  ),
                                  const Spacer(),
                                  Row(
                                    children: [
                                      const Icon(Icons.timer_outlined, size: 14, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      Text(freqStr, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(t['task_name'] as String? ?? '-', style: const TextStyle(fontWeight: FontWeight.w600)),
                              if ((t['expected_result'] as String?)?.isNotEmpty ?? false)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Text('มาตรฐาน: ${t['expected_result']}', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
      ),
      actions: [
        if (widget.summary.status == 'pending_approval') ...[
          TextButton.icon(
            onPressed: _showRejectDialog,
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedCancel01, size: 18, color: Colors.red),
            label: const Text('ปฏิเสธ (ตีกลับ)', style: TextStyle(color: Colors.red)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => _updateStatus('active'),
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkBadge01, size: 18, color: Colors.white),
            label: const Text('อนุมัติแผน'),
          ),
        ] else if (widget.summary.status == 'draft' || widget.summary.status == 'rejected') ...[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ปิดหน้าต่าง')),
          FilledButton.icon(
            onPressed: () => _updateStatus('pending_approval'),
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedSent, size: 18, color: Colors.white),
            label: const Text('ส่งแผน'),
          ),
        ] else ...[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ปิดหน้าต่าง')),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              widget.onEdit();
            },
            icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit02, size: 18, color: Colors.white),
            label: const Text('แก้ไขแผน'),
          ),
        ],
        
        TextButton.icon(
          onPressed: _tasks.isEmpty ? null : () async {
            try {
              final settings = ref.read(appSettingsProvider).valueOrNull;
              final user = ref.read(authProvider);
              final creatorName = _tasks.isNotEmpty ? (_tasks.first['creator_name'] as String?) : null;
              final approverName = _tasks.isNotEmpty ? (_tasks.first['approver_name'] as String?) : null;
              
              if (settings != null) {
                await PmAmPdfService.generateMasterPlanPdf(
                  machineNo: widget.summary.machineNo,
                  machineBrand: widget.summary.machineBrand,
                  planType: widget.planType,
                  tasks: _tasks,
                  settings: settings,
                  userName: user?.fullName ?? 'ไม่ระบุตัวตน',
                  createdByName: creatorName,
                  approvedByName: approverName,
                );
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กำลังโหลดข้อมูลการตั้งค่า กรุณาลองใหม่')));
                }
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาดในการสร้าง PDF: $e')));
              }
            }
          },
          icon: const HugeIcon(icon: HugeIcons.strokeRoundedPrinter, size: 18, color: AppColors.textSecondary),
          label: const Text('พิมพ์แผน (PDF)', style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }

  Future<void> _updateStatus(String newStatus, {String? remark}) async {
    try {
      final user = ref.read(authProvider);
      
      await DbHelper.execute(
        '''UPDATE pm_am_plans 
           SET status = @status, 
               approved_by = CASE WHEN @status = 'active' THEN @uid ELSE approved_by END,
               description = CASE WHEN @remark IS NOT NULL THEN @remark ELSE description END,
               updated_at = CURRENT_TIMESTAMP
           WHERE machine_id = @mid AND plan_type = @type''',
        params: {
          'status': newStatus,
          'uid': user?.userId,
          'remark': remark,
          'mid': widget.summary.machineId,
          'type': widget.planType,
        },
      );
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('อัพเดทสถานะแผนเป็น $newStatus สำเร็จ')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
      }
    }
  }

  void _showRejectDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ปฏิเสธแผน / ตีกลับแก้ไข'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'เหตุผล (Remark)', hintText: 'เช่น ข้อมูลไม่ครบถ้วน'),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              _updateStatus('rejected', remark: ctrl.text.trim());
            },
            child: const Text('ยืนยันปฏิเสธ'),
          ),
        ],
      ),
    );
  }

  Color _getBadgeColor(String? status) {
    if (status == 'active') return Colors.green.shade50;
    if (status == 'pending_approval') return Colors.orange.shade50;
    if (status == 'draft') return Colors.blue.shade50;
    if (status == 'rejected') return Colors.red.shade50;
    return Colors.grey.shade100;
  }

  Color _getBadgeBorderColor(String? status) {
    if (status == 'active') return Colors.green.shade200;
    if (status == 'pending_approval') return Colors.orange.shade200;
    if (status == 'draft') return Colors.blue.shade200;
    if (status == 'rejected') return Colors.red.shade200;
    return Colors.grey.shade300;
  }

  Color _getBadgeTextColor(String? status) {
    if (status == 'active') return Colors.green.shade700;
    if (status == 'pending_approval') return Colors.orange.shade700;
    if (status == 'draft') return Colors.blue.shade700;
    if (status == 'rejected') return Colors.red.shade700;
    return Colors.grey.shade600;
  }

  String _getStatusText(String? status) {
    if (status == 'active') return 'อนุมัติ / ใช้งานอยู่';
    if (status == 'pending_approval') return 'รออนุมัติแผน';
    if (status == 'draft') return 'แบบร่างแผน';
    if (status == 'rejected') return 'ตีกลับแก้ไขแผน';
    return 'ระงับการใช้งาน';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create/Edit Plan Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _TaskInput {
  final String? planId; // If null, it's a new task
  final TextEditingController nameCtrl;
  final TextEditingController standardCtrl;
  final TextEditingController daysCtrl;
  final TextEditingController monthsCtrl;

  _TaskInput({
    this.planId,
    String name = '',
    String standard = '',
    String days = '',
    String months = '',
  })  : nameCtrl = TextEditingController(text: name),
        standardCtrl = TextEditingController(text: standard),
        daysCtrl = TextEditingController(text: days),
        monthsCtrl = TextEditingController(text: months);

  void dispose() {
    nameCtrl.dispose();
    standardCtrl.dispose();
    daysCtrl.dispose();
    monthsCtrl.dispose();
  }
}

class _PlanFormDialog extends ConsumerStatefulWidget {
  final MachinePmSummary summary;
  final String planType;
  const _PlanFormDialog({required this.summary, required this.planType});

  @override
  ConsumerState<_PlanFormDialog> createState() => _PlanFormDialogState();
}

class _PlanFormDialogState extends ConsumerState<_PlanFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _loading = true;

  List<_TaskInput> _tasks = [];
  final List<String> _deletedPlanIds = [];

  @override
  void initState() {
    super.initState();
    final p = widget.summary;

    if (p.hasPlan) {
      _loadTasks();
    } else {
      _tasks.add(_TaskInput());
      _loading = false;
    }
  }

  Future<void> _loadTasks() async {
    try {
      final rows = await DbHelper.query(
        '''SELECT p.plan_id, p.frequency_days, p.frequency_months, t.task_name, t.expected_result 
           FROM pm_am_plans p 
           LEFT JOIN pm_am_tasks t ON t.plan_id = p.plan_id 
           WHERE p.machine_id = @mid AND p.plan_type = @type
           ORDER BY p.created_at ASC''',
        params: {'mid': widget.summary.machineId, 'type': widget.planType},
      );
      if (mounted) {
        setState(() {
          if (rows.isNotEmpty) {
            _tasks = rows.map((r) => _TaskInput(
              planId: r['plan_id'] as String?,
              name: r['task_name'] as String? ?? '',
              standard: r['expected_result'] as String? ?? '',
              days: r['frequency_days']?.toString() ?? '',
              months: r['frequency_months']?.toString() ?? '',
            )).toList();
          } else {
            _tasks.add(_TaskInput());
          }
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading tasks: $e');
      if (mounted) {
        setState(() {
          _tasks.add(_TaskInput());
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    for (var t in _tasks) {
      t.dispose();
    }
    super.dispose();
  }

  void _removeTask(int index) {
    setState(() {
      final t = _tasks[index];
      if (t.planId != null) {
        _deletedPlanIds.add(t.planId!);
      }
      t.dispose();
      _tasks.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.summary.hasPlan;
    final machineName = '${widget.summary.machineNo} ${widget.summary.machineBrand ?? ''}'.trim();
    final typeName = widget.planType == 'PM' ? 'PM (Preventive)' : 'AM (Autonomous)';

    return AlertDialog(
      title: Text(isEdit ? 'แก้ไขแผน $typeName' : 'กำหนดแผน $typeName'),
      content: SizedBox(
        width: 600,
        child: _loading 
            ? const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
            : Form(
                key: _formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Machine Display
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Row(
                          children: [
                            const HugeIcon(icon: HugeIcons.strokeRoundedSettings01, size: 20, color: Colors.grey),
                            const SizedBox(width: 8),
                            Text('เครื่องจักร: ', style: TextStyle(color: Colors.grey.shade700)),
                            Text(machineName, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: AppSpacing.lg),
                      const Text('รายการตรวจสอบบำรุงรักษา (Checklist)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: AppSpacing.sm),
                      
                      ..._tasks.asMap().entries.map((entry) {
                        final i = entry.key;
                        final t = entry.value;
                        return Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.md),
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.divider),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))
                            ]
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
                                    child: Text('ข้อที่ ${i + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primaryDark, fontSize: 12)),
                                  ),
                                  const Spacer(),
                                  if (_tasks.length > 1)
                                    IconButton(
                                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 18, color: Colors.red),
                                      onPressed: () => _removeTask(i),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                    ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextFormField(
                                controller: t.nameCtrl,
                                decoration: const InputDecoration(labelText: 'รายละเอียด PM * (เช่น ตรวจน้ำมันเครื่อง)'),
                                validator: (v) => v == null || v.trim().isEmpty ? 'กรุณาระบุรายละเอียด' : null,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              TextFormField(
                                controller: t.standardCtrl,
                                decoration: const InputDecoration(labelText: 'มาตรฐานการ PM (ไม่บังคับ)'),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: t.daysCtrl,
                                      decoration: const InputDecoration(labelText: 'รอบความถี่ทุกๆ (วัน)', suffixText: 'วัน'),
                                      keyboardType: TextInputType.number,
                                      validator: (v) {
                                        if ((v == null || v.isEmpty) && t.monthsCtrl.text.isEmpty) {
                                          return 'ระบุวัน หรือ เดือน';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: TextFormField(
                                      controller: t.monthsCtrl,
                                      decoration: const InputDecoration(labelText: 'รอบความถี่ทุกๆ (เดือน)', suffixText: 'เดือน'),
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                      
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _tasks.add(_TaskInput())),
                          icon: const HugeIcon(icon: HugeIcons.strokeRoundedPlusSign, size: 18, color: AppColors.primary),
                          label: const Text('เพิ่มรายการใหม่'),
                        ),
                      ),
                      
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        OutlinedButton(
          onPressed: (_saving || _loading) ? null : () => _save('draft'),
          child: const Text('บันทึกแบบร่าง'),
        ),
        FilledButton(
          onPressed: (_saving || _loading) ? null : () => _save('pending_approval'),
          child: const Text('ส่งแผน'),
        ),
      ],
    );
  }

  Future<void> _save(String nextStatus) async {
    if (!_formKey.currentState!.validate()) return;
    
    // Ensure all tasks have at least one frequency defined
    for (var t in _tasks) {
      if (t.daysCtrl.text.trim().isEmpty && t.monthsCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาระบุความถี่ (วัน หรือ เดือน) ให้ครบทุกข้อ')));
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final machineId = widget.summary.machineId;
      final type = widget.planType;
      final planNamePrefix = '$type ${widget.summary.machineNo}';
      final currentUserId = ref.read(authProvider)?.userId;
      
      await DbHelper.transaction((tx) async {
        // 1. Process deletions
        for (final deletedId in _deletedPlanIds) {
          await DbHelper.txExecute(tx, 'DELETE FROM pm_am_plans WHERE plan_id = @pid', params: {'pid': deletedId});
          await DbHelper.txExecute(tx, 'DELETE FROM pm_am_tasks WHERE plan_id = @pid', params: {'pid': deletedId});
        }
        
        // 2. Process updates and inserts
        for (int i = 0; i < _tasks.length; i++) {
          final t = _tasks[i];
          final days = int.tryParse(t.daysCtrl.text.trim());
          final months = int.tryParse(t.monthsCtrl.text.trim());
          
          if (t.planId != null) {
            // Update existing plan
            await DbHelper.txExecute(tx, 
              '''UPDATE pm_am_plans SET 
                   plan_type = @type,
                   frequency_days = @days,
                   frequency_months = @months,
                   status = @status,
                   approved_by = CASE WHEN @status = 'active' AND approved_by IS NULL THEN @uid ELSE approved_by END,
                   updated_at = CURRENT_TIMESTAMP
                 WHERE plan_id = @id''',
              params: {
                'id': t.planId,
                'type': type,
                'days': days,
                'months': months,
                'status': nextStatus,
                'uid': currentUserId,
              }
            );
            
            // Update task
            await DbHelper.txExecute(tx, 
              '''UPDATE pm_am_tasks SET
                   task_name = @name,
                   expected_result = @result
                 WHERE plan_id = @pid''',
              params: {
                'pid': t.planId,
                'name': t.nameCtrl.text.trim(),
                'result': t.standardCtrl.text.trim(),
              }
            );
          } else {
            // Insert new plan
            final newPlanId = 'plan_${DateTime.now().millisecondsSinceEpoch}_$i';
            final planCode = '$type-${DateTime.now().year.toString().substring(2)}${DateTime.now().month.toString().padLeft(2, '0')}-${newPlanId.substring(newPlanId.length - 4)}';
            
            await DbHelper.txExecute(tx, 
              '''INSERT INTO pm_am_plans (
                   plan_id, machine_id, plan_type, plan_code, plan_name, 
                   frequency_days, frequency_months, status, created_by, approved_by
                 ) VALUES (@id, @mid, @type, @code, @name, @days, @months, @status, @uid, @apid)''',
              params: {
                'id': newPlanId,
                'mid': machineId,
                'type': type,
                'code': planCode,
                'name': '$planNamePrefix - ข้อ ${i + 1}',
                'days': days,
                'months': months,
                'status': nextStatus,
                'uid': currentUserId,
                'apid': nextStatus == 'active' ? currentUserId : null,
              },
            );
            
            // Insert task
            await DbHelper.txExecute(tx, 
              '''INSERT INTO pm_am_tasks (
                   task_id, plan_id, task_order, task_name, task_type, expected_result
                 ) VALUES (
                   @tid, @pid, 1, @name, 'inspect', @result
                 )''',
              params: {
                'tid': 'task_${DateTime.now().millisecondsSinceEpoch}_$i',
                'pid': newPlanId,
                'name': t.nameCtrl.text.trim(),
                'result': t.standardCtrl.text.trim(),
              }
            );
          }
        }
      });

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
