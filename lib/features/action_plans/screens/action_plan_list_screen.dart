import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_spacing.dart';
import '../action_plan_pdf_service.dart';
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
            const Text('ทะเบียนแผนการปรับปรุง (Action Plan Registry)'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'รีเฟรชข้อมูล',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.read(actionPlanListProvider.notifier).reload(),
          ),
          const SizedBox(width: 8),
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

          return Column(
            children: [
              // 1. KPI Metric Summary Cards
              _buildMetricCards(
                theme,
                totalCount: totalCount,
                inProgressCount: inProgressCount,
                completedCount: completedCount,
                verifiedCount: verifiedCount,
              ),

              // 2. Search and Filter Bar
              _buildFilterBar(theme, filterState),

              // 3. Action Plans List (Click to open details)
              Expanded(
                child: filteredPlans.isEmpty
                    ? _buildEmptyState(theme, totalCount)
                    : ListView.builder(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        itemCount: filteredPlans.length,
                        itemBuilder: (context, index) {
                          final plan = filteredPlans[index];
                          return _buildActionPlanRowCard(context, theme, plan);
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricCards(
    ThemeData theme, {
    required int totalCount,
    required int inProgressCount,
    required int completedCount,
    required int verifiedCount,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          _buildStatBox('แผนงานทั้งหมด', '$totalCount', 'แผน', Icons.list_alt_rounded, Colors.blue),
          const SizedBox(width: 12),
          _buildStatBox('กำลังดำเนินการ', '$inProgressCount', 'แผน', Icons.pending_actions_rounded, Colors.orange),
          const SizedBox(width: 12),
          _buildStatBox('เสร็จสมบูรณ์ / ปิดแผน', '$completedCount', 'แผน', Icons.task_alt_rounded, Colors.green),
          const SizedBox(width: 12),
          _buildStatBox('สอบทานผลแล้ว (V&V)', '$verifiedCount', 'รายการ', Icons.verified_outlined, Colors.purple),
        ],
      ),
    );
  }

  Widget _buildStatBox(String title, String value, String unit, IconData icon, Color color) {
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
                ? 'แผนปฏิบัติการจะถูกสร้างและส่งต่อมาจากโมดูล Problem Solving & RCA'
                : 'ลองเปลี่ยนคำค้นหาหรือตัวกรองสถานะด้านบน',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildActionPlanRowCard(BuildContext context, ThemeData theme, ActionPlanRecord plan) {
    final isCompleted = plan.status == 'completed' || plan.status == 'closed';
    final progressPct = (plan.progress * 100).toStringAsFixed(0);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isCompleted ? Colors.green.withValues(alpha: 0.3) : theme.dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => context.push('/action-plans/${plan.rcaId}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // Source icon/badge
              _buildSourceBadge(plan.sourceType),
              const SizedBox(width: 14),

              // Title and Info
              Expanded(
                flex: 4,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.problemTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (plan.rootCause != null && plan.rootCause!.isNotEmpty) ...[
                          Flexible(
                            child: Text(
                              'สาเหตุ: ${plan.rootCause}',
                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('•', style: TextStyle(color: Colors.grey.shade400)),
                          const SizedBox(width: 8),
                        ],
                        if (plan.createdAt != null)
                          Text(
                            'วันที่: ${plan.createdAt}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Verification badge if present
              if (plan.targetMetric != null && plan.targetMetric!.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed_rounded, size: 13, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        plan.targetMetric!,
                        style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold),
                      ),
                      if (plan.reductionPercentage != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          plan.reductionPercentage! > 0
                              ? '(-${plan.reductionPercentage!.toStringAsFixed(0)}%)'
                              : '(+${plan.reductionPercentage!.abs().toStringAsFixed(0)}%)',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: plan.reductionPercentage! > 0 ? Colors.green.shade800 : Colors.red.shade800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              // Attachments badge if present
              if (plan.attachments.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.attach_file, size: 12, color: Colors.grey),
                      Text('${plan.attachments.length}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),

              // Progress bar
              SizedBox(
                width: 140,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${plan.completedStepsCount}/${plan.totalStepsCount} ขั้นตอน',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                        Text(
                          '$progressPct%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isCompleted ? Colors.green : Colors.blueAccent,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: plan.progress,
                        minHeight: 5,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isCompleted ? Colors.green : Colors.blueAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),

              // Status badge
              _buildStatusPill(plan.status),
              const SizedBox(width: 8),

              IconButton(
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.redAccent),
                tooltip: 'ออกรายงาน (PDF / Browser)',
                onPressed: () => ActionPlanPdfService.generateAndOpen(plan: plan),
              ),

              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
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
        label = 'WO';
        icon = Icons.build_circle_outlined;
        break;
      case 'line_balancing':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        label = 'Line';
        icon = Icons.account_tree_outlined;
        break;
      case 'sop_step':
        bg = Colors.teal.shade50;
        fg = Colors.teal.shade800;
        label = 'SOP';
        icon = Icons.format_list_numbered_rounded;
        break;
      default:
        bg = Colors.purple.shade50;
        fg = Colors.purple.shade800;
        label = 'Custom';
        icon = Icons.flag_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: fg)),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String status) {
    Color color;
    String text;
    switch (status) {
      case 'completed':
        color = Colors.green;
        text = 'เสร็จสมบูรณ์';
        break;
      case 'closed':
        color = Colors.blueGrey;
        text = 'ปิดแผนแล้ว';
        break;
      case 'in_progress':
        color = Colors.orange;
        text = 'กำลังทำ';
        break;
      default:
        color = Colors.blue;
        text = 'รอดำเนินการ';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
