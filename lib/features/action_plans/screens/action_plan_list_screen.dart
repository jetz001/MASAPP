import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/theme/app_spacing.dart';
import '../models/action_plan_model.dart';
import '../providers/action_plan_provider.dart';

class ActionPlanListScreen extends ConsumerStatefulWidget {
  const ActionPlanListScreen({super.key});

  @override
  ConsumerState<ActionPlanListScreen> createState() => _ActionPlanListScreenState();
}

class _ActionPlanListScreenState extends ConsumerState<ActionPlanListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plansAsync = ref.watch(actionPlanListProvider);
    final filteredPlans = ref.watch(filteredActionPlanListProvider);
    final filterState = ref.watch(actionPlanFilterProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.checklist_rounded,
                size: 20,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(width: 12),
            const Text('ทะเบียนแผนปฏิบัติการ & ติดตามผล (Action Plan Registry)'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'รีเฟรชข้อมูล',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(actionPlanListProvider.notifier).reload(),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.purple.shade700,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.troubleshoot_rounded, size: 18),
            label: const Text('Problem Solving & RCA'),
            onPressed: () => context.push('/problem-solving'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: plansAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('เกิดข้อผิดพลาดในการโหลด: $err')),
        data: (allPlans) {
          final totalCount = allPlans.length;
          final inProgressCount = allPlans.where((p) => p.status == 'in_progress').length;
          final completedCount = allPlans.where((p) => p.status == 'completed' || p.status == 'closed').length;
          final verifiedCount = allPlans.where((p) => p.verificationResult != null && p.verificationResult!.isNotEmpty).length;

          int totalSteps = 0;
          int completedSteps = 0;
          for (final p in allPlans) {
            totalSteps += p.totalStepsCount;
            completedSteps += p.completedStepsCount;
          }
          final overallProgress = totalSteps > 0 ? (completedSteps / totalSteps) : 0.0;

          return Column(
            children: [
              // 1. KPI Metric Summary Cards
              _buildMetricCards(
                theme,
                totalCount: totalCount,
                inProgressCount: inProgressCount,
                completedCount: completedCount,
                verifiedCount: verifiedCount,
                overallProgress: overallProgress,
                completedSteps: completedSteps,
                totalSteps: totalSteps,
              ),

              // 2. Search and Filter Bar
              _buildFilterBar(theme, filterState),

              // 3. Action Plans List
              Expanded(
                child: filteredPlans.isEmpty
                    ? _buildEmptyState(theme, totalCount)
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        itemCount: filteredPlans.length,
                        itemBuilder: (context, index) {
                          final plan = filteredPlans[index];
                          return _buildActionPlanCard(context, theme, plan);
                        },
                      ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_task_rounded),
        label: const Text('สร้าง Action Plan ใหม่'),
        onPressed: () => context.push('/problem-solving'),
      ),
    );
  }

  Widget _buildMetricCards(
    ThemeData theme, {
    required int totalCount,
    required int inProgressCount,
    required int completedCount,
    required int verifiedCount,
    required double overallProgress,
    required int completedSteps,
    required int totalSteps,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          _buildStatBox(
            title: 'แผนงานทั้งหมด',
            value: '$totalCount',
            unit: 'แผน',
            icon: Icons.list_alt_rounded,
            color: Colors.blue,
          ),
          const SizedBox(width: 12),
          _buildStatBox(
            title: 'กำลังดำเนินการ',
            value: '$inProgressCount',
            unit: 'แผน',
            icon: Icons.pending_actions_rounded,
            color: Colors.orange,
          ),
          const SizedBox(width: 12),
          _buildStatBox(
            title: 'เสร็จสมบูรณ์ / ปิดแผน',
            value: '$completedCount',
            unit: 'แผน',
            icon: Icons.task_alt_rounded,
            color: Colors.green,
          ),
          const SizedBox(width: 12),
          _buildStatBox(
            title: 'สอบทานผลแล้ว (V&V)',
            value: '$verifiedCount',
            unit: 'รายการ',
            icon: Icons.verified_outlined,
            color: Colors.purple,
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'ความคืบหน้าขั้นตอนรวม',
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '$completedSteps/$totalSteps ขั้นตอน (${(overallProgress * 100).toStringAsFixed(0)}%)',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: overallProgress >= 1.0 ? Colors.green : Colors.blueAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: overallProgress,
                      minHeight: 8,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        overallProgress >= 1.0 ? Colors.green : (overallProgress > 0 ? Colors.blue : Colors.orange),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatBox({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      flex: 1,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Text(
                        value,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        unit,
                        style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme, ActionPlanFilterState filter) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          // Search box
          SizedBox(
            width: 260,
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'ค้นหาปัญหา, สาเหตุ, ผู้รับผิดชอบ...',
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(actionPlanFilterProvider.notifier).state =
                              filter.copyWith(searchQuery: '');
                        },
                      )
                    : null,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8))),
              ),
              style: const TextStyle(fontSize: 12),
              onChanged: (val) {
                ref.read(actionPlanFilterProvider.notifier).state =
                    filter.copyWith(searchQuery: val);
              },
            ),
          ),
          const SizedBox(width: 12),

          // Status segmented buttons
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            segments: const [
              ButtonSegment(value: 'all', label: Text('ทั้งหมด', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 'in_progress', label: Text('🔄 กำลังทำ', style: TextStyle(fontSize: 11))),
              ButtonSegment(value: 'completed', label: Text('✅ เสร็จแล้ว', style: TextStyle(fontSize: 11))),
            ],
            selected: {filter.statusFilter},
            onSelectionChanged: (val) {
              ref.read(actionPlanFilterProvider.notifier).state =
                  filter.copyWith(statusFilter: val.first);
            },
          ),
          const SizedBox(width: 12),

          // Source filter chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildSourceChip('all', 'ทุกแหล่งที่มา', filter),
                  const SizedBox(width: 6),
                  _buildSourceChip('work_order', '🔧 งานซ่อมบำรุง (WO)', filter),
                  const SizedBox(width: 6),
                  _buildSourceChip('line_balancing', '⚙️ Line Balancing', filter),
                  const SizedBox(width: 6),
                  _buildSourceChip('sop_step', '📋 SOP ขั้นตอนงาน', filter),
                  const SizedBox(width: 6),
                  _buildSourceChip('custom', '🎯 ปัญหากำหนดเอง', filter),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceChip(String value, String label, ActionPlanFilterState filter) {
    final isSelected = filter.sourceFilter == value;
    return FilterChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
      selected: isSelected,
      onSelected: (_) {
        ref.read(actionPlanFilterProvider.notifier).state =
            filter.copyWith(sourceFilter: value);
      },
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }

  Widget _buildEmptyState(ThemeData theme, int total) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.assignment_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            total == 0 ? 'ยังไม่มีรายการแผนปฏิบัติการในระบบ' : 'ไม่พบแผนปฏิบัติการตามเงื่อนไขค้นหา',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Text(
            total == 0
                ? 'คุณสามารถวิเคราะห์ปัญหาและสร้าง Action Plan ได้จากหน้า Problem Solving & RCA'
                : 'ลองเปลี่ยนคำค้นหาหรือตัวกรองสถานะด้านบน',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 16),
          if (total == 0)
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('ไปสร้างแผนปฏิบัติการใน Problem Solving'),
              onPressed: () => context.push('/problem-solving'),
            ),
        ],
      ),
    );
  }

  Widget _buildActionPlanCard(BuildContext context, ThemeData theme, ActionPlanRecord plan) {
    final isCompleted = plan.status == 'completed' || plan.status == 'closed';
    final progressPct = (plan.progress * 100).toStringAsFixed(0);

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCompleted ? Colors.green.withValues(alpha: 0.3) : theme.dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Card Header (Source badge, Title, Status, Action buttons)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSourceBadge(plan.sourceType),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        plan.problemTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      if (plan.createdAt != null)
                        Text(
                          'วันที่บันทึก: ${plan.createdAt}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                    ],
                  ),
                ),
                _buildStatusDropdown(plan),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (val) async {
                    if (val == 'open_rca') {
                      context.push('/problem-solving');
                    } else if (val == 'delete') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('ยืนยันการลบ Action Plan'),
                          content: Text('คุณต้องการลบ "${plan.problemTitle}" หรือไม่?'),
                          actions: [
                            TextButton(onPressed: () => ctx.pop(false), child: const Text('ยกเลิก')),
                            FilledButton(
                              style: FilledButton.styleFrom(backgroundColor: Colors.red),
                              onPressed: () => ctx.pop(true),
                              child: const Text('ลบ'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        ref.read(actionPlanListProvider.notifier).deleteActionPlan(plan.rcaId);
                      }
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(
                      value: 'open_rca',
                      child: Row(
                        children: [
                          Icon(Icons.troubleshoot_rounded, size: 16, color: Colors.purple),
                          SizedBox(width: 8),
                          Text('เปิดใน Problem Solving & RCA', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                          SizedBox(width: 8),
                          Text('ลบ Action Plan', style: TextStyle(fontSize: 12, color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const Divider(height: 20),

            // Root Cause Callout
            if (plan.rootCause != null && plan.rootCause!.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.crisis_alert_rounded, color: Colors.redAccent, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'สาเหตุรากเหง้า (Root Cause): ${plan.rootCause}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ),

            // Progress Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ขั้นตอนการปฏิบัติงาน (${plan.completedStepsCount}/${plan.totalStepsCount} ขั้นตอนเสร็จสิ้น)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  '$progressPct%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isCompleted ? Colors.green : Colors.blueAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: plan.progress,
                minHeight: 6,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isCompleted ? Colors.green : Colors.blueAccent,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Step Checklist
            if (plan.actionSteps.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: plan.actionSteps.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final step = entry.value;
                    final isStepDone = step.status == 'completed';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        border: idx < plan.actionSteps.length - 1
                            ? Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)))
                            : null,
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: isStepDone,
                            onChanged: (val) {
                              final newStatus = (val == true) ? 'completed' : 'pending';
                              ref
                                  .read(actionPlanListProvider.notifier)
                                  .updateStepStatus(plan.rcaId, step.id, newStatus);
                            },
                          ),
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: isStepDone ? Colors.green : Colors.blue.shade700,
                            child: Text('${idx + 1}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              step.title,
                              style: TextStyle(
                                fontSize: 13,
                                decoration: isStepDone ? TextDecoration.lineThrough : null,
                                color: isStepDone ? Colors.grey : null,
                              ),
                            ),
                          ),
                          if (step.assignee.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: Colors.blue.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.person_outline, size: 12, color: Colors.blueAccent),
                                  const SizedBox(width: 4),
                                  Text(step.assignee, style: const TextStyle(fontSize: 11, color: Colors.blueAccent)),
                                ],
                              ),
                            ),
                          if (step.dueDate.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.access_time, size: 12, color: Colors.orange),
                                  const SizedBox(width: 4),
                                  Text(step.dueDate, style: const TextStyle(fontSize: 11, color: Colors.orange)),
                                ],
                              ),
                            ),
                          DropdownButton<String>(
                            value: step.status,
                            underline: const SizedBox(),
                            isDense: true,
                            style: const TextStyle(fontSize: 11, color: Colors.black),
                            items: const [
                              DropdownMenuItem(value: 'pending', child: Text('⏳ รอดำเนินการ')),
                              DropdownMenuItem(value: 'in_progress', child: Text('🔄 กำลังทำ')),
                              DropdownMenuItem(value: 'completed', child: Text('✅ เสร็จแล้ว')),
                            ],
                            onChanged: (newStatus) {
                              if (newStatus != null) {
                                ref
                                    .read(actionPlanListProvider.notifier)
                                    .updateStepStatus(plan.rcaId, step.id, newStatus);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),

            // Verification & Validation Section (if verified)
            if (plan.targetMetric != null && plan.targetMetric!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.verified_outlined, size: 16, color: Colors.green),
                            const SizedBox(width: 6),
                            Text(
                              'การสอบทานผล (${plan.targetMetric}): ',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.green),
                            ),
                          ],
                        ),
                        if (plan.verificationResult != null)
                          _buildVerificationResultBadge(plan.verificationResult!),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text(
                          'ก่อน: ${plan.beforeValue?.toStringAsFixed(1) ?? "-"} ${plan.metricUnit ?? ""}  ➔  เป้าหมาย: ${plan.targetValue?.toStringAsFixed(1) ?? "-"}  ➔  ผลจริง: ${plan.actualValue?.toStringAsFixed(1) ?? "-"} ${plan.metricUnit ?? ""}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        if (plan.reductionPercentage != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: plan.reductionPercentage! > 0 ? Colors.green.shade100 : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              plan.reductionPercentage! > 0
                                  ? 'ลดลง ${plan.reductionPercentage!.toStringAsFixed(1)}%'
                                  : 'เพิ่มขึ้น ${plan.reductionPercentage!.abs().toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: plan.reductionPercentage! > 0 ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (plan.verifiedBy != null && plan.verifiedBy!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'ผู้ตรวจสอบ: ${plan.verifiedBy} (${plan.verificationDate ?? "-"}) | แผนคงสภาพ: ${plan.standardizationNotes ?? "-"}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            // Attachments & Photos Section
            const SizedBox(height: 12),
            _buildAttachmentsSection(context, theme, plan),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentsSection(BuildContext context, ThemeData theme, ActionPlanRecord plan) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.attach_file_rounded, size: 16, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'รูปภาพและเอกสารแนบ (${plan.attachments.length} ไฟล์):',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 8)),
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
              label: const Text('+ แนบรูป/เอกสาร', style: TextStyle(fontSize: 11)),
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(
                  allowMultiple: true,
                  type: FileType.custom,
                  allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'xlsx', 'docx'],
                );
                if (result != null && result.files.isNotEmpty) {
                  for (final f in result.files) {
                    if (f.path != null) {
                      await ref.read(actionPlanListProvider.notifier).addAttachment(
                            plan.rcaId,
                            f.path!,
                            displayName: f.name,
                          );
                    }
                  }
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('แนบไฟล์ลงใน Action Plan สำเร็จ!')),
                    );
                  }
                }
              },
            ),
          ],
        ),
        if (plan.attachments.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: plan.attachments.map((asset) {
              final fileName = asset['display_name'] ?? asset['file_name'] ?? 'เอกสารแนบ';
              final filePath = asset['storage_path'] ?? asset['source_path'] ?? asset['file_path'] ?? '';
              final isImg = fileName.toLowerCase().endsWith('.png') ||
                  fileName.toLowerCase().endsWith('.jpg') ||
                  fileName.toLowerCase().endsWith('.jpeg');
              final isPdf = fileName.toLowerCase().endsWith('.pdf');

              return InkWell(
                onTap: () {
                  if (filePath.isNotEmpty) {
                    OpenFilex.open(filePath);
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isImg ? Icons.image_rounded : (isPdf ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded),
                        size: 16,
                        color: isImg ? Colors.teal : (isPdf ? Colors.red : Colors.blue),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          fileName,
                          style: const TextStyle(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () {
                          final assetId = asset['asset_id']?.toString();
                          if (assetId != null) {
                            ref.read(actionPlanListProvider.notifier).removeAttachment(assetId);
                          }
                        },
                        child: const Icon(Icons.close, size: 14, color: Colors.redAccent),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildSourceBadge(String sourceType) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (sourceType) {
      case 'work_order':
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        label = 'งานซ่อม (WO)';
        icon = Icons.build_circle_outlined;
        break;
      case 'line_balancing':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        label = 'Line Balancing';
        icon = Icons.account_tree_outlined;
        break;
      case 'sop_step':
        bg = Colors.teal.shade50;
        fg = Colors.teal.shade800;
        label = 'SOP ขั้นตอนงาน';
        icon = Icons.format_list_numbered_rounded;
        break;
      default:
        bg = Colors.purple.shade50;
        fg = Colors.purple.shade800;
        label = 'ปัญหากำหนดเอง';
        icon = Icons.flag_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDropdown(ActionPlanRecord plan) {
    Color color;
    switch (plan.status) {
      case 'completed':
      case 'closed':
        color = Colors.green;
        break;
      case 'in_progress':
        color = Colors.orange;
        break;
      default:
        color = Colors.blueGrey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: plan.status,
          isDense: true,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
          items: const [
            DropdownMenuItem(value: 'pending', child: Text('⏳ รอดำเนินการ')),
            DropdownMenuItem(value: 'in_progress', child: Text('🔄 กำลังดำเนินการ')),
            DropdownMenuItem(value: 'completed', child: Text('✅ เสร็จสมบูรณ์')),
            DropdownMenuItem(value: 'closed', child: Text('🔒 ปิดแผนงานแล้ว')),
          ],
          onChanged: (newStatus) {
            if (newStatus != null) {
              ref.read(actionPlanListProvider.notifier).updatePlanStatus(plan.rcaId, newStatus);
            }
          },
        ),
      ),
    );
  }

  Widget _buildVerificationResultBadge(String res) {
    Color color;
    String text;
    switch (res) {
      case 'achieved':
        color = Colors.green;
        text = '✅ สำเร็จตามเป้า';
        break;
      case 'partial':
        color = Colors.orange;
        text = '🔄 ดีขึ้นแต่ยังไม่ถึงเป้า';
        break;
      case 'failed':
        color = Colors.red;
        text = '⚠️ ไม่สำเร็จ';
        break;
      default:
        color = Colors.blue;
        text = '⏳ อยู่ระหว่างตรวจวัด';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
    );
  }
}
