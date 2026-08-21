import 'package:flutter/material.dart';
import '../../../core/theme/app_spacing.dart';
import '../../work_processes/models/work_process_model.dart';
import '../../work_processes/models/work_process_step_model.dart';
import '../models/vsm_model.dart';

class VsmVisualizerCard extends StatelessWidget {
  final WorkProcess process;
  final void Function(WorkProcessStep step)? onSelectStepForRca;

  const VsmVisualizerCard({
    super.key,
    required this.process,
    this.onSelectStepForRca,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final summary = VsmSummary.fromProcess(process);

    if (summary.nodes.isEmpty) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: const Padding(
          padding: EdgeInsets.all(AppSpacing.xl),
          child: Center(
            child: Text('ไม่มีขั้นตอนงานสำหรับการสร้างแผนผัง Value Stream Mapping'),
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header & KPI
            _buildHeader(summary, theme, isDark),
            const Divider(height: 32),

            // 2. Information Flow Banner
            _buildInformationFlowBanner(theme, isDark),
            const SizedBox(height: 20),

            // 3. Process Stream with Boxes & Buffers
            _buildHorizontalProcessStream(summary, theme, isDark),
            const SizedBox(height: 28),

            // 4. Stepped VSM Ladder Timeline
            _buildVsmTimelineLadder(summary, theme, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(VsmSummary summary, ThemeData theme, bool isDark) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.indigo.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.alt_route_rounded,
            color: Colors.indigo,
            size: 24,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'แผนผังสายธารคุณค่า (Value Stream Map - VSM)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: process.methodType == WorkProcessMethodType.improved
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.blue.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: process.methodType == WorkProcessMethodType.improved
                            ? Colors.green
                            : Colors.blue,
                      ),
                    ),
                    child: Text(
                      process.methodType == WorkProcessMethodType.improved
                          ? 'Future State (ปรับปรุง)'
                          : 'Current State (ปัจจุบัน)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: process.methodType == WorkProcessMethodType.improved
                            ? Colors.green.shade700
                            : Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'จำลองการไหลของข้อมูล (Information Flow) และวัสดุ (Material Flow) พร้อมสถิติเวลา Cycle Time & คอขวด',
                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        // KPI Badges
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildKpiChip(
              'Lead Time (L/T)',
              '${summary.totalLeadTimeMinutes.toStringAsFixed(1)} m',
              Icons.timer_outlined,
              Colors.blue,
              isDark,
            ),
            const SizedBox(width: 8),
            _buildKpiChip(
              'Processing (VA)',
              '${summary.totalProcessingTimeMinutes.toStringAsFixed(1)} m',
              Icons.check_circle_outline,
              Colors.green,
              isDark,
            ),
            const SizedBox(width: 8),
            _buildKpiChip(
              'PCE Efficiency',
              '${summary.processCycleEfficiency.toStringAsFixed(1)}%',
              Icons.speed_rounded,
              summary.processCycleEfficiency >= 50 ? Colors.green : Colors.orange,
              isDark,
            ),
            if (summary.kaizenCount > 0) ...[
              const SizedBox(width: 8),
              _buildKpiChip(
                'จุด Kaizen 💥',
                '${summary.kaizenCount} จุด',
                Icons.auto_awesome,
                Colors.amber.shade800,
                isDark,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildKpiChip(
    String label,
    String value,
    IconData icon,
    Color color,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.2 : 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 9,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade700,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInformationFlowBanner(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.indigo.shade50.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.settings_suggest_rounded, color: Colors.indigo, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'สายธารข้อมูล (Information Flow): การวางแผนและควบคุมการผลิต/บำรุงรักษา (Production & Maintenance Control)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo),
                ),
                Text(
                  'ส่งคำสั่งงาน (Work Dispatch) ➔ กำหนดลำดับงาน (Sequencing) ➔ ควบคุมรอบเวลา (Takt Control)',
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.indigo,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flash_on, color: Colors.white, size: 12),
                SizedBox(width: 4),
                Text('Electronic Signals (Push/Pull)', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalProcessStream(VsmSummary summary, ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Supplier Node
          _buildSupplierNode(theme, isDark),
          _buildFlowArrow(isDark, label: 'ส่งมอบ\nวัตถุดิบ'),

          // Process Nodes & Buffer Triangles
          for (var i = 0; i < summary.nodes.length; i++) ...[
            _buildProcessBox(summary.nodes[i], theme, isDark),
            if (i < summary.nodes.length - 1)
              _buildBufferTriangle(summary.nodes[i], summary.nodes[i + 1], theme, isDark),
          ],

          _buildFlowArrow(isDark, label: 'ส่งมอบ\nผลผลิต'),
          // Customer Node
          _buildCustomerNode(theme, isDark),
        ],
      ),
    );
  }

  Widget _buildSupplierNode(ThemeData theme, bool isDark) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.factory_rounded, color: Colors.blueGrey, size: 28),
          const SizedBox(height: 6),
          const Text(
            'ซัพพลายเออร์\n/ คลังวัตถุดิบ',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            'Raw Material',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerNode(ThemeData theme, bool isDark) {
    return Container(
      width: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_shipping_rounded, color: Colors.teal, size: 28),
          const SizedBox(height: 6),
          const Text(
            'ลูกค้า\n/ กระบวนการถัดไป',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Text(
            'Finished Goods',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowArrow(bool isDark, {String? label}) {
    return Container(
      width: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (label != null)
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 8, color: Colors.grey.shade600),
            ),
          const SizedBox(height: 4),
          Icon(Icons.arrow_forward_rounded, color: isDark ? Colors.grey.shade500 : Colors.grey.shade400, size: 20),
        ],
      ),
    );
  }

  Widget _buildBufferTriangle(VsmStepNode current, VsmStepNode next, ThemeData theme, bool isDark) {
    final hasDelay = next.step.eventType == ProcessEventType.delay || next.step.valueType != LeanValueType.va;
    final waitMinutes = next.step.eventType == ProcessEventType.delay ? next.step.durationMinutes : 0.0;
    final distance = next.step.distanceMeters;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Inventory / Buffer triangle icon
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: hasDelay ? Colors.orange.withValues(alpha: 0.15) : (isDark ? Colors.grey.shade800 : Colors.grey.shade100),
              shape: BoxShape.circle,
              border: Border.all(
                color: hasDelay ? Colors.orange : Colors.grey.shade400,
              ),
            ),
            child: Icon(
              Icons.change_history_rounded, // ASME Storage / Buffer Triangle
              size: 16,
              color: hasDelay ? Colors.orange.shade800 : Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 4),
          if (waitMinutes > 0)
            Text(
              'รอ ${waitMinutes.toStringAsFixed(0)}m',
              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.orange),
            ),
          if (distance > 0)
            Text(
              '${distance.toStringAsFixed(0)}ม.',
              style: TextStyle(fontSize: 9, color: Colors.blue.shade700),
            ),
          const SizedBox(height: 2),
          Icon(Icons.arrow_forward_rounded, color: isDark ? Colors.grey.shade500 : Colors.grey.shade400, size: 16),
        ],
      ),
    );
  }

  Widget _buildProcessBox(VsmStepNode node, ThemeData theme, bool isDark) {
    final s = node.step;
    final isBottleneck = node.isBottleneck;
    final isWaste = node.isPureWaste;

    Color borderColor = Colors.grey.shade300;
    Color headerColor = isDark ? Colors.grey.shade800 : Colors.grey.shade200;

    if (isBottleneck) {
      borderColor = Colors.red.shade400;
      headerColor = Colors.red.withValues(alpha: 0.15);
    } else if (isWaste) {
      borderColor = Colors.amber.shade600;
      headerColor = Colors.amber.withValues(alpha: 0.15);
    } else if (node.isValueAdd) {
      borderColor = Colors.green.shade400;
      headerColor = Colors.green.withValues(alpha: 0.12);
    }

    return Container(
      width: 170,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: isBottleneck ? 2 : 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Box Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Row(
              children: [
                Text(
                  s.eventIcon,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '#${node.index} ${s.description}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // Data Grid (VSM Standard)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                _buildVsmDataRow('Cycle Time (C/T)', '${s.durationMinutes.toStringAsFixed(1)} นาที', isHighlight: isBottleneck),
                _buildVsmDataRow('ระยะทาง (Dist)', '${s.distanceMeters.toStringAsFixed(0)} ม.'),
                _buildVsmDataRow('ประเภทคุณค่า', s.valueLabel, color: s.valueType == LeanValueType.va ? Colors.green : (s.valueType == LeanValueType.nva ? Colors.red : Colors.orange)),
                _buildVsmDataRow('สัญลักษณ์ ASME', s.eventName),
                if (s.problemCause?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '⚠️ ${s.problemCause}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9, color: Colors.red.shade800),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Kaizen Burst or RCA Action button
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800.withValues(alpha: 0.4) : Colors.grey.shade50,
              border: Border(top: BorderSide(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                if (isBottleneck)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('💥 คอขวด', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                  )
                else if (isWaste)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade800,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('💥 สูญเปล่า', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                  ),
                const Spacer(),
                InkWell(
                  onTap: () => onSelectStepForRca?.call(s),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.manage_search_rounded, size: 12, color: theme.colorScheme.primary),
                        const SizedBox(width: 2),
                        Text(
                          'ทำ RCA',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVsmDataRow(String label, String value, {bool isHighlight = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.w600,
              color: color ?? (isHighlight ? Colors.red : null),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVsmTimelineLadder(VsmSummary summary, ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.linear_scale_rounded, size: 18, color: Colors.indigo),
              const SizedBox(width: 8),
              const Text(
                'บันไดเวลา VSM (Timeline Ladder) — จำแนกเวลาที่สร้างคุณค่า (VA) vs เวลาสูญเปล่า (Non-VA)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              Text(
                'Total Lead Time: ${summary.totalLeadTimeMinutes.toStringAsFixed(1)} min',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Stepped Line Graph
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final node in summary.nodes) ...[
                  _buildLadderStep(node, isDark),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Summary Footer
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '🔺 ระดับบน (Non-VA / Delay Time): ${summary.totalDelayTimeMinutes.toStringAsFixed(1)} นาที',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red),
              ),
              Text(
                '🔻 ระดับล่าง (VA / Processing Time): ${summary.totalProcessingTimeMinutes.toStringAsFixed(1)} นาที',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
              ),
              Text(
                '🎯 Process Cycle Efficiency: ${summary.processCycleEfficiency.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: summary.processCycleEfficiency >= 50 ? Colors.green : Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLadderStep(VsmStepNode node, bool isDark) {
    final isVa = node.isValueAdd;
    final dur = node.step.durationMinutes;

    return Container(
      width: 90,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Upper Level (Non-VA delay/waiting)
          if (!isVa) ...[
            Container(
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: isDark ? 0.3 : 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.red.shade300),
              ),
              child: Text(
                '${dur.toStringAsFixed(1)}m',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red),
              ),
            ),
            Container(width: 2, height: 16, color: Colors.grey.shade400),
            Container(
              height: 24,
              alignment: Alignment.center,
              child: Text('#${node.index}', style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
            ),
          ] else ...[
            // Lower Level (VA processing)
            Container(
              height: 24,
              alignment: Alignment.center,
              child: Text('#${node.index}', style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
            ),
            Container(width: 2, height: 16, color: Colors.grey.shade400),
            Container(
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: isDark ? 0.3 : 0.15),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Text(
                '${dur.toStringAsFixed(1)}m',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
