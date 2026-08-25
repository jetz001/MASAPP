import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/app_utils.dart';
import '../machine_models.dart';
import '../machine_provider.dart';

class MachineRepairHistoryDialog extends ConsumerStatefulWidget {
  final MachineModel machine;

  const MachineRepairHistoryDialog({
    super.key,
    required this.machine,
  });

  static Future<void> show(BuildContext context, MachineModel machine) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => MachineRepairHistoryDialog(machine: machine),
    );
  }

  @override
  ConsumerState<MachineRepairHistoryDialog> createState() =>
      _MachineRepairHistoryDialogState();
}

class _MachineRepairHistoryDialogState
    extends ConsumerState<MachineRepairHistoryDialog> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String? _statusFilter;
  String? _expandedWoId;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final machineId = widget.machine.machineId ?? '';
    final historyAsync = ref.watch(machineRepairHistoryProvider(machineId));

    return Dialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 1040,
          maxHeight: 840,
          minWidth: 700,
        ),
        child: Column(
          children: [
            // ─── Header ──────────────────────────────────────────
            _buildDialogHeader(context),

            const Divider(height: 1),

            // ─── Content ─────────────────────────────────────────
            Expanded(
              child: historyAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            size: 48, color: AppColors.error),
                        const SizedBox(height: 12),
                        Text('เกิดข้อผิดพลาดในการโหลดประวัติซ่อม: $e',
                            style: AppTextStyles.bodyMedium),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () => ref.invalidate(
                              machineRepairHistoryProvider(machineId)),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: const Text('ลองใหม่อีกครั้ง'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (records) {
                  return _buildHistoryContent(context, records);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader(BuildContext context) {
    final m = widget.machine;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 20, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
            ),
            child: const Icon(
              Icons.history_rounded,
              color: AppColors.primary,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        m.machineNo,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        m.machineName ?? m.brand ?? 'ไม่ระบุชื่อเครื่อง',
                        style: AppTextStyles.titleLarge.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (m.brand != null || m.model != null)
                      _buildHeaderMetaItem(
                        Icons.precision_manufacturing_outlined,
                        '${m.brand ?? ''} ${m.model ?? ''}'.trim(),
                      ),
                    if (m.serialNo != null && m.serialNo!.isNotEmpty)
                      _buildHeaderMetaItem(
                        Icons.tag_rounded,
                        'S/N: ${m.serialNo}',
                      ),
                    if (m.location != null && m.location!.isNotEmpty)
                      _buildHeaderMetaItem(
                        Icons.location_on_outlined,
                        m.location!,
                      ),
                    if (m.deptName != null && m.deptName!.isNotEmpty)
                      _buildHeaderMetaItem(
                        Icons.business_rounded,
                        m.deptName!,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
            tooltip: 'ปิด',
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderMetaItem(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTextStyles.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryContent(
    BuildContext context,
    List<MachineRepairRecord> allRecords,
  ) {
    // KPI summary calculations
    final totalRepairs = allRecords.length;
    final breakdownCount = allRecords.where((r) {
      final p = r.priority.toLowerCase();
      final f = r.failureType?.toLowerCase() ?? '';
      return p == 'urgent' || p == 'high' || f == 'breakdown';
    }).length;

    final totalDowntimeMinutes = allRecords.fold<int>(
      0,
      (sum, r) => sum + r.downtimeMinutes,
    );
    final totalCost = allRecords.fold<double>(
      0.0,
      (sum, r) => sum + r.totalCost,
    );

    // Filter records
    final filtered = allRecords.where((r) {
      if (_statusFilter != null && _statusFilter!.isNotEmpty) {
        if (_statusFilter == 'in_progress') {
          if (r.status != 'in_progress' && r.status != 'approved') return false;
        } else if (r.status != _statusFilter) {
          return false;
        }
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchWo = r.woNo.toLowerCase().contains(q);
        final matchTitle = r.title.toLowerCase().contains(q);
        final matchDesc = (r.description ?? '').toLowerCase().contains(q);
        final matchSymptom = (r.failureSymptom ?? '').toLowerCase().contains(q);
        final matchRca = (r.rootCause ?? '').toLowerCase().contains(q);
        final matchTech = (r.assignedToName ?? '').toLowerCase().contains(q);
        final matchVendor = (r.outsourceVendorName ?? '').toLowerCase().contains(q);

        if (!matchWo &&
            !matchTitle &&
            !matchDesc &&
            !matchSymptom &&
            !matchRca &&
            !matchTech &&
            !matchVendor) {
          return false;
        }
      }

      return true;
    }).toList();

    return Column(
      children: [
        // ─── KPI Cards Row ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
          child: Row(
            children: [
              _buildKpiCard(
                title: 'ประวัติซ่อมทั้งหมด',
                value: '$totalRepairs',
                unit: 'ครั้ง',
                icon: Icons.build_circle_outlined,
                color: AppColors.primary,
              ),
              const SizedBox(width: 12),
              _buildKpiCard(
                title: 'Breakdown / ด่วน',
                value: '$breakdownCount',
                unit: 'ครั้ง',
                icon: Icons.warning_amber_rounded,
                color: breakdownCount > 0 ? AppColors.error : AppColors.success,
              ),
              const SizedBox(width: 12),
              _buildKpiCard(
                title: 'เวลารวมเครื่องหยุด',
                value: _formatDowntime(totalDowntimeMinutes),
                unit: '',
                icon: Icons.timer_outlined,
                color: const Color(0xFFF59E0B),
              ),
              const SizedBox(width: 12),
              _buildKpiCard(
                title: 'ค่าใช้จ่ายซ่อมสะสม',
                value: NumberFormat('#,##0').format(totalCost),
                unit: 'บาท',
                icon: Icons.monetization_on_outlined,
                color: const Color(0xFF10B981),
              ),
            ],
          ),
        ),

        // ─── Filter & Search Bar ──────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchCtrl,
                    style: AppTextStyles.bodyMedium,
                    decoration: InputDecoration(
                      hintText: 'ค้นหาตามเลขที่ WO, อาการเสีย, สาเหตุ RCA, ช่างซ่อม...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: Theme.of(context).dividerColor),
                      ),
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surface,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Filter chips
              _buildStatusFilterChip('ทั้งหมด', null),
              const SizedBox(width: 6),
              _buildStatusFilterChip('เสร็จสิ้น', 'completed', color: AppColors.success),
              const SizedBox(width: 6),
              _buildStatusFilterChip('กำลังซ่อม', 'in_progress', color: AppColors.primary),
              const SizedBox(width: 6),
              _buildStatusFilterChip('ส่งซ่อมภายนอก', 'outsourced', color: const Color(0xFF8B5CF6)),
              const SizedBox(width: 6),
              _buildStatusFilterChip('รอดำเนินการ', 'pending', color: AppColors.warning),
            ],
          ),
        ),

        const SizedBox(height: 4),

        // ─── List of Work Orders ──────────────────────────────
        Expanded(
          child: filtered.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, idx) {
                    final r = filtered[idx];
                    final isExpanded = _expandedWoId == r.woId;
                    return _buildRepairCard(context, r, isExpanded);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String unit,
    required IconData icon,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    textBaseline: TextBaseline.alphabetic,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    children: [
                      Text(
                        value,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      if (unit.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          unit,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
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

  Widget _buildStatusFilterChip(String label, String? status, {Color? color}) {
    final selected = _statusFilter == status;
    final effectiveColor = color ?? AppColors.primary;

    return InkWell(
      onTap: () => setState(() => _statusFilter = selected ? null : status),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? effectiveColor.withValues(alpha: 0.18)
              : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? effectiveColor : Theme.of(context).dividerColor,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected
                ? effectiveColor
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildRepairCard(
    BuildContext context,
    MachineRepairRecord r,
    bool isExpanded,
  ) {
    final isCompleted = r.status == 'completed';
    final isOutsourced = r.status == 'outsourced';
    final isBreakdown = r.priority == 'urgent' || r.failureType == 'breakdown';

    Color cardBorderColor = Theme.of(context).dividerColor;
    if (isBreakdown) {
      cardBorderColor = AppColors.error.withValues(alpha: 0.4);
    } else if (isCompleted) {
      cardBorderColor = AppColors.success.withValues(alpha: 0.3);
    } else if (isOutsourced) {
      cardBorderColor = const Color(0xFF8B5CF6).withValues(alpha: 0.4);
    }

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorderColor, width: isBreakdown ? 1.5 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Row ──
          InkWell(
            onTap: () => setState(() {
              _expandedWoId = isExpanded ? null : r.woId;
            }),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // WO Icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isBreakdown
                          ? AppColors.error.withValues(alpha: 0.12)
                          : AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isBreakdown
                          ? Icons.warning_rounded
                          : (isOutsourced
                              ? Icons.handshake_outlined
                              : Icons.build_rounded),
                      color: isBreakdown ? AppColors.error : AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),

                  // WO Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              r.woNo,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildStatusBadge(r.status),
                            const SizedBox(width: 6),
                            _buildPriorityBadge(r.priority),
                            if (r.failureType != null && r.failureType!.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              _buildFailureTypeBadge(r.failureType!),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.title,
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Date & Cost
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        r.createdAt != null
                            ? DateFormatters.formatDate(r.createdAt)
                            : '-',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (r.totalCost > 0)
                        Text(
                          '${NumberFormat('#,##0').format(r.totalCost)} ฿',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        )
                      else if (r.downtimeMinutes > 0)
                        Text(
                          'Downtime: ${r.downtimeMinutes} นาที',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(width: 8),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded Details ──
          if (isExpanded) ...[
            const Divider(height: 1),
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Symptom & Description
                  if (r.failureSymptom != null && r.failureSymptom!.isNotEmpty) ...[
                    _buildDetailSection(
                      title: 'อาการเสียที่ตรวจพบ (Symptom):',
                      content: r.failureSymptom!,
                      icon: Icons.report_problem_outlined,
                      iconColor: AppColors.warning,
                    ),
                    const SizedBox(height: 10),
                  ],

                  if (r.description != null && r.description!.isNotEmpty && r.description != r.failureSymptom) ...[
                    _buildDetailSection(
                      title: 'รายละเอียดงาน:',
                      content: r.description!,
                      icon: Icons.notes_rounded,
                      iconColor: AppColors.textSecondary,
                    ),
                    const SizedBox(height: 10),
                  ],

                  // RCA (Root Cause)
                  if (r.rootCause != null && r.rootCause!.isNotEmpty) ...[
                    _buildDetailSection(
                      title: 'สาเหตุที่แท้จริง (Root Cause RCA):',
                      content: r.rootCause!,
                      icon: Icons.psychology_outlined,
                      iconColor: const Color(0xFF8B5CF6),
                      tag: r.causeCategory != null ? 'หมวด: ${r.causeCategory}' : null,
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Action Taken
                  if (r.actionTaken != null && r.actionTaken!.isNotEmpty) ...[
                    _buildDetailSection(
                      title: 'วิธีแก้ไขและการดำเนินการ (Action Taken):',
                      content: r.actionTaken!,
                      icon: Icons.check_circle_outline,
                      iconColor: AppColors.success,
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Outsource Details
                  if (r.outsourceVendorName != null && r.outsourceVendorName!.isNotEmpty) ...[
                    _buildDetailSection(
                      title: 'ผู้รับเหมาซ่อมภายนอก:',
                      content: '${r.outsourceVendorName!} ${r.outsourceRepairDetails != null ? '— ${r.outsourceRepairDetails}' : ''}',
                      icon: Icons.business_outlined,
                      iconColor: const Color(0xFF8B5CF6),
                    ),
                    const SizedBox(height: 10),
                  ],

                  // Parts Used
                  if (r.partsUsed.isNotEmpty) ...[
                    Row(
                      children: [
                        const Icon(Icons.inventory_2_outlined, size: 16, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text('อะไหล่ที่เปลี่ยน (${r.partsUsed.length} รายการ):',
                            style: AppTextStyles.labelMedium.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: r.partsUsed.map((p) {
                        final code = p['part_code']?.toString() ?? '';
                        final name = p['part_name']?.toString() ?? '';
                        final qty = p['quantity']?.toString() ?? '1';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surface,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Theme.of(context).dividerColor),
                          ),
                          child: Text(
                            '$code $name (x$qty)',
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Meta Footer (Technician, Times, Button to Full WO)
                  Row(
                    children: [
                      if (r.assignedToName != null) ...[
                        const Icon(Icons.person_outline, size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text('ช่าง: ${r.assignedToName}',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                        const SizedBox(width: 16),
                      ],
                      if (r.completedAt != null) ...[
                        const Icon(Icons.task_alt_rounded, size: 14, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text('เสร็จสิ้น: ${DateFormatters.formatDate(r.completedAt)}',
                            style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary)),
                      ],
                      const Spacer(),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          context.go('/work-orders/${r.woId}');
                        },
                        icon: const Icon(Icons.open_in_new_rounded, size: 14),
                        label: const Text('ดูใบแจ้งซ่อมเต็ม'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailSection({
    required String title,
    required String content,
    required IconData icon,
    required Color iconColor,
    String? tag,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 6),
            Text(title, style: AppTextStyles.labelMedium.copyWith(fontWeight: FontWeight.bold)),
            if (tag != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(tag, style: TextStyle(fontSize: 10, color: iconColor, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Padding(
          padding: const EdgeInsets.only(left: 21),
          child: Text(
            content,
            style: AppTextStyles.bodySmall.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = AppColors.textSecondary;
    String label = status;

    switch (status.toLowerCase()) {
      case 'completed':
        color = AppColors.success;
        label = 'เสร็จสิ้น';
        break;
      case 'in_progress':
        color = AppColors.primary;
        label = 'กำลังซ่อม';
        break;
      case 'approved':
        color = const Color(0xFF0EA5E9);
        label = 'อนุมัติแล้ว';
        break;
      case 'outsourced':
        color = const Color(0xFF8B5CF6);
        label = 'ส่งซ่อมภายนอก';
        break;
      case 'pending':
        color = AppColors.warning;
        label = 'รอดำเนินการ';
        break;
      case 'cancelled':
        color = AppColors.error;
        label = 'ยกเลิก';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPriorityBadge(String priority) {
    Color color = AppColors.textSecondary;
    String label = priority;

    switch (priority.toLowerCase()) {
      case 'urgent':
        color = AppColors.error;
        label = 'ด่วนมาก';
        break;
      case 'high':
        color = const Color(0xFFF97316);
        label = 'สูง';
        break;
      case 'normal':
        color = AppColors.primary;
        label = 'ปกติ';
        break;
      case 'low':
        color = AppColors.textSecondary;
        label = 'ต่ำ';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildFailureTypeBadge(String type) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF64748B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type.toUpperCase(),
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.build_circle_outlined,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'ไม่พบประวัติการแจ้งซ่อมสำหรับเครื่องจักรนี้',
              style: AppTextStyles.titleMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'เครื่องจักรนี้ยังไม่เคยมีบันทึกการซ่อม หรือเงื่อนไขการค้นหาไม่ตรงกับข้อมูล',
              style: AppTextStyles.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDowntime(int minutes) {
    if (minutes <= 0) return '0 นาที';
    if (minutes < 60) return '$minutes นาที';
    final hrs = minutes ~/ 60;
    final mins = minutes % 60;
    return mins > 0 ? '$hrs ชม. $mins นาที' : '$hrs ชม.';
  }
}
