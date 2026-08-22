import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'line_balancing_provider.dart';
import 'add_station_dialog.dart';
import 'line_graph_canvas.dart';

class LineBalancingScreen extends ConsumerWidget {
  const LineBalancingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lineBalancingProvider);
    final notifier = ref.read(lineBalancingProvider.notifier);
    final linesAsync = ref.watch(allProductionLinesProvider);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 12,
          title: Row(
            children: [
              const Icon(Icons.account_tree_outlined, color: Colors.blueAccent, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Line Balancing',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(width: 12),
              // Production Line Switcher Dropdown (Expanded with isExpanded)
              Expanded(
                child: linesAsync.when(
                  data: (lines) {
                    final lineItems = lines.map((l) {
                      final lid = l['line_id'].toString();
                      final lname = l['line_name']?.toString() ?? 'สายการผลิต';
                      final scnt = (l['station_count'] as num?)?.toInt() ?? 0;
                      return DropdownMenuItem<String>(
                        value: lid,
                        child: Text(
                          '🏭 $lname ($scnt สถานี)',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList();

                    final hasCurrent = lines.any((l) => l['line_id'].toString() == state.lineId);

                    return Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: hasCurrent ? state.lineId : (lines.isNotEmpty ? lines.first['line_id'].toString() : null),
                          hint: const Text('เลือกสายการผลิต', style: TextStyle(fontSize: 12)),
                          isDense: true,
                          isExpanded: true,
                          items: lineItems,
                          onChanged: (selectedLineId) async {
                            if (selectedLineId != null && selectedLineId != state.lineId) {
                              await notifier.loadLine(selectedLineId);
                              ref.invalidate(allProductionLinesProvider);
                            }
                          },
                        ),
                      ),
                    );
                  },
                  loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ),
            ],
          ),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
              Tab(
                icon: Icon(Icons.account_tree),
                text: 'Line Management (Graph)',
              ),
            ],
          ),
          actions: [
            // Button: เพิ่มไลน์ใหม่
            IconButton.filledTonal(
              icon: const Icon(Icons.add_box_outlined, size: 18),
              tooltip: 'เพิ่มสายการผลิตใหม่',
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(36, 36),
              ),
              onPressed: () => _showCreateLineDialog(context, ref, notifier),
            ),
            const SizedBox(width: 6),

            // Button: บันทึกไลน์
            IconButton.outlined(
              icon: const Icon(Icons.save_outlined, size: 18),
              tooltip: 'บันทึกข้อมูลสายการผลิต (${state.lineName})',
              style: IconButton.styleFrom(
                padding: const EdgeInsets.all(8),
                minimumSize: const Size(36, 36),
              ),
              onPressed: () async {
                await notifier.saveCurrentLine();
                ref.invalidate(allProductionLinesProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.check_circle, color: Colors.white),
                          const SizedBox(width: 8),
                          Text('บันทึกข้อมูล "${state.lineName}" สำเร็จ (${state.stations.length} สถานี)'),
                        ],
                      ),
                      backgroundColor: Colors.teal.shade700,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
            const SizedBox(width: 4),

            // More Line Options Menu (Rename, Duplicate, Delete)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: 'จัดการสายการผลิต',
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'rename',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18, color: Colors.blue),
                      SizedBox(width: 8),
                      Text('เปลี่ยนชื่อไลน์'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Row(
                    children: [
                      Icon(Icons.copy_outlined, size: 18, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('คัดลอกไลน์นี้'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('ลบไลน์นี้', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (action) {
                if (action == 'rename') {
                  _showRenameLineDialog(context, ref, notifier, state.lineId, state.lineName);
                } else if (action == 'duplicate') {
                  _handleDuplicateLine(context, ref, notifier, state.lineName);
                } else if (action == 'delete') {
                  _showDeleteLineDialog(context, ref, notifier, state.lineId, state.lineName);
                }
              },
            ),
            const SizedBox(width: 8),

            // Button: เพิ่มสถานี
            Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: FilledButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มสถานี'),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => AddStationDialog(notifier: notifier),
                  );
                },
              ),
            ),
          ],
        ),
        body: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: [
            SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Current Active Line Header Banner
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.factory, color: theme.colorScheme.primary, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                state.lineName,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              Text(
                                'สถานีงานทั้งหมด: ${state.stations.length} สถานี | Takt Time: ${state.taktTimeSec.toStringAsFixed(1)}s | ประสิทธิภาพ: ${state.lineEfficiency.toStringAsFixed(1)}%',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('เปลี่ยนชื่อ'),
                          onPressed: () => _showRenameLineDialog(context, ref, notifier, state.lineId, state.lineName),
                        ),
                      ],
                    ),
                  ),

                  // KPI Row 1
                  Row(
                    children: [
                      _buildKPI(
                        theme,
                        'Takt Time',
                        '${state.taktTimeSec.toStringAsFixed(1)}s',
                        'เป้าหมายความเร็วต่อชิ้น',
                        Colors.blue,
                      ),
                      const SizedBox(width: 16),
                      _buildKPI(
                        theme,
                        'Line Efficiency',
                        '${state.lineEfficiency.toStringAsFixed(1)}%',
                        'ประสิทธิภาพของสายการผลิต',
                        Colors.green,
                      ),
                      const SizedBox(width: 16),
                      _buildKPI(
                        theme,
                        'Balance Delay',
                        '${state.balanceDelay.toStringAsFixed(1)}%',
                        'ความสูญเปล่าในสายการผลิต',
                        Colors.orange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // KPI Row 2 (New Metrics)
                  Row(
                    children: [
                      _buildKPI(
                        theme,
                        'Lead Time',
                        '${state.leadTimeSec.toStringAsFixed(1)}s',
                        'เวลาการผลิตรวมต่อชิ้น',
                        Colors.purple,
                      ),
                      const SizedBox(width: 16),
                      _buildKPI(
                        theme,
                        'Operational Cost',
                        '฿${state.totalOperationalCost.toStringAsFixed(2)}',
                        'ต้นทุนดำเนินการรวม (ต่อรอบเวลาทำงาน)',
                        Colors.red,
                      ),
                      const SizedBox(width: 16),
                      _buildKPI(
                        theme,
                        'Total Workers',
                        '${state.totalWorkers} คน',
                        'จำนวนพนักงานทั้งหมดในไลน์',
                        Colors.teal,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  // Layout Row (Parameters & Chart)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Parameters Input
                      Expanded(
                        flex: 1,
                        child: Card(
                          elevation: 0,
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.2),
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'พารามิเตอร์การผลิต',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  initialValue: state.availableTimeMin
                                      .toString(),
                                  decoration: const InputDecoration(
                                    labelText:
                                        'ระยะเวลาที่ลูกค้าต้องการ (นาที)',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) {
                                    final val = double.tryParse(v);
                                    if (val != null) {
                                      notifier.updateAvailableTime(val);
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  initialValue: state.demandQuantity.toString(),
                                  decoration: const InputDecoration(
                                    labelText: 'ยอดผลิตเป้าหมาย (ชิ้น)',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) {
                                    final val = double.tryParse(v);
                                    if (val != null) {
                                      notifier.updateDemand(val);
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  initialValue: state.electricityRate
                                      .toString(),
                                  decoration: const InputDecoration(
                                    labelText: 'ค่าไฟ/หน่วย (บาท)',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) {
                                    final val = double.tryParse(v);
                                    if (val != null) {
                                      notifier.updateRates(val, state.fuelRate);
                                    }
                                  },
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  initialValue: state.fuelRate.toString(),
                                  decoration: const InputDecoration(
                                    labelText: 'ค่าน้ำมัน/ก๊าซ/หน่วย (บาท)',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  onChanged: (v) {
                                    final val = double.tryParse(v);
                                    if (val != null) {
                                      notifier.updateRates(
                                        state.electricityRate,
                                        val,
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Chart
                      Expanded(
                        flex: 2,
                        child: Card(
                          elevation: 0,
                          color: theme.colorScheme.surface,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Cycle Time vs Takt Time (Bottleneck Analysis)',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                SizedBox(
                                  height: 300,
                                  child: BarChart(
                                    BarChartData(
                                      alignment: BarChartAlignment.spaceAround,
                                      maxY:
                                          (state.maxCycleTime >
                                                  state.taktTimeSec
                                              ? state.maxCycleTime
                                              : state.taktTimeSec) *
                                          1.2,
                                      barTouchData: BarTouchData(enabled: true),
                                      titlesData: FlTitlesData(
                                        show: true,
                                        bottomTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            getTitlesWidget: (value, meta) {
                                              if (value.toInt() >= 0 &&
                                                  value.toInt() <
                                                      state.stations.length) {
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 8,
                                                      ),
                                                  child: Text(
                                                    'St.${value.toInt() + 1}',
                                                    style: const TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                );
                                              }
                                              return const SizedBox.shrink();
                                            },
                                          ),
                                        ),
                                        leftTitles: AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: true,
                                            reservedSize: 40,
                                          ),
                                        ),
                                        topTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: false,
                                          ),
                                        ),
                                        rightTitles: const AxisTitles(
                                          sideTitles: SideTitles(
                                            showTitles: false,
                                          ),
                                        ),
                                      ),
                                      gridData: FlGridData(
                                        show: true,
                                        drawVerticalLine: false,
                                      ),
                                      borderData: FlBorderData(show: false),
                                      extraLinesData: ExtraLinesData(
                                        horizontalLines: [
                                          HorizontalLine(
                                            y: state.taktTimeSec,
                                            color: Colors.red,
                                            strokeWidth: 2,
                                            dashArray: [5, 5],
                                            label: HorizontalLineLabel(
                                              show: true,
                                              alignment: Alignment.topRight,
                                              padding: const EdgeInsets.only(
                                                right: 5,
                                                bottom: 5,
                                              ),
                                              style: const TextStyle(
                                                color: Colors.red,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              labelResolver: (line) =>
                                                  'Takt: ${line.y.toStringAsFixed(1)}s',
                                            ),
                                          ),
                                        ],
                                      ),
                                      barGroups: state.stations
                                          .asMap()
                                          .entries
                                          .map((e) {
                                            final isBottleneck =
                                                e.value.cycleTime >
                                                state.taktTimeSec;
                                            return BarChartGroupData(
                                              x: e.key,
                                              barRods: [
                                                BarChartRodData(
                                                  toY: e.value.cycleTime,
                                                  color: isBottleneck
                                                      ? Colors.red.shade400
                                                      : Colors.blue.shade400,
                                                  width: 40,
                                                  borderRadius:
                                                      const BorderRadius.vertical(
                                                        top: Radius.circular(6),
                                                      ),
                                                ),
                                              ],
                                            );
                                          })
                                          .toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Tab 2: Canvas Node Graph
            const LineGraphCanvas(),
          ],
        ),
      ),
    );
  }

  Widget _buildKPI(
    ThemeData theme,
    String label,
    String value,
    String subtitle,
    Color color,
  ) {
    return Expanded(
      child: Card(
        elevation: 0,
        color: color.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: color.withValues(alpha: 0.2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showCreateLineDialog(BuildContext context, WidgetRef ref, LineBalancingNotifier notifier) {
    final nameCtrl = TextEditingController(text: 'สายการผลิตที่ ${DateTime.now().second % 10 + 1}');
    final deptCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_business_outlined, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('สร้างสายการผลิตใหม่'),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'ชื่อสายการผลิต (เช่น Line 1, Line 2, สายการผลิตที่ 3)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.precision_manufacturing),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: deptCtrl,
                decoration: const InputDecoration(
                  labelText: 'แผนก / แผนกงาน (ไม่บังคับ)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.business_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () async {
              final lineName = nameCtrl.text.trim();
              if (lineName.isNotEmpty) {
                Navigator.pop(ctx);
                await notifier.createNewLine(
                  lineName: lineName,
                  department: deptCtrl.text.trim().isNotEmpty ? deptCtrl.text.trim() : null,
                );
                ref.invalidate(allProductionLinesProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('สร้างสายการผลิต "$lineName" เรียบร้อยแล้ว'),
                      backgroundColor: Colors.green.shade700,
                    ),
                  );
                }
              }
            },
            child: const Text('สร้างสายการผลิต'),
          ),
        ],
      ),
    );
  }

  static void _showRenameLineDialog(
    BuildContext context,
    WidgetRef ref,
    LineBalancingNotifier notifier,
    String lineId,
    String currentName,
  ) {
    final nameCtrl = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_outlined, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('เปลี่ยนชื่อสายการผลิต'),
          ],
        ),
        content: TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: 'ชื่อสายการผลิตใหม่',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = nameCtrl.text.trim();
              if (newName.isNotEmpty) {
                Navigator.pop(ctx);
                await notifier.renameLine(lineId, newName);
                ref.invalidate(allProductionLinesProvider);
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }

  static void _handleDuplicateLine(
    BuildContext context,
    WidgetRef ref,
    LineBalancingNotifier notifier,
    String currentName,
  ) async {
    await notifier.duplicateCurrentLine(newName: '$currentName (สำเนา)');
    ref.invalidate(allProductionLinesProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('คัดลอกสายการผลิตเป็น "$currentName (สำเนา)" เรียบร้อยแล้ว'),
          backgroundColor: Colors.orange.shade700,
        ),
      );
    }
  }

  static void _showDeleteLineDialog(
    BuildContext context,
    WidgetRef ref,
    LineBalancingNotifier notifier,
    String lineId,
    String lineName,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('ยืนยันการลบสายการผลิต'),
          ],
        ),
        content: Text('คุณต้องการลบ "$lineName" และสถานีงานทั้งหมดในไลน์นี้ใช่หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              await notifier.deleteLine(lineId);
              ref.invalidate(allProductionLinesProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('ลบสายการผลิต "$lineName" เรียบร้อยแล้ว'),
                    backgroundColor: Colors.red.shade700,
                  ),
                );
              }
            },
            child: const Text('ลบสายการผลิต'),
          ),
        ],
      ),
    );
  }
}
