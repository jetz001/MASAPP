# -*- coding: utf-8 -*-
import codecs

content = """import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'line_balancing_provider.dart';

class LineBalancingScreen extends ConsumerWidget {
  const LineBalancingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lineBalancingProvider);
    final notifier = ref.read(lineBalancingProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Line Balancing Calculator'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Row
            Row(
              children: [
                _buildKPI(theme, 'Takt Time', '${state.taktTimeSec.toStringAsFixed(1)}s', 'เป้าหมายความเร็วต่อชิ้น', Colors.blue),
                const SizedBox(width: 16),
                _buildKPI(theme, 'Line Efficiency', '${state.lineEfficiency.toStringAsFixed(1)}%', 'ประสิทธิภาพของสายการผลิต', Colors.green),
                const SizedBox(width: 16),
                _buildKPI(theme, 'Balance Delay', '${state.balanceDelay.toStringAsFixed(1)}%', 'ความสูญเปล่าในสายการผลิต', Colors.orange),
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
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('พารามิเตอร์การผลิต', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          TextFormField(
                            initialValue: state.availableTimeMin.toString(),
                            decoration: const InputDecoration(labelText: 'เวลาทำงานที่ใช้ได้ (นาที)', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final val = double.tryParse(v);
                              if (val != null) notifier.updateAvailableTime(val);
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            initialValue: state.demandQuantity.toString(),
                            decoration: const InputDecoration(labelText: 'ยอดผลิตเป้าหมาย (ชิ้น)', border: OutlineInputBorder()),
                            keyboardType: TextInputType.number,
                            onChanged: (v) {
                              final val = double.tryParse(v);
                              if (val != null) notifier.updateDemand(val);
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
                          Text('Cycle Time vs Takt Time (Bottleneck Analysis)', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 24),
                          SizedBox(
                            height: 300,
                            child: BarChart(
                              BarChartData(
                                alignment: BarChartAlignment.spaceAround,
                                maxY: (state.maxCycleTime > state.taktTimeSec ? state.maxCycleTime : state.taktTimeSec) * 1.2,
                                barTouchData: BarTouchData(enabled: true),
                                titlesData: FlTitlesData(
                                  show: true,
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      getTitlesWidget: (value, meta) {
                                        if (value.toInt() >= 0 && value.toInt() < state.stations.length) {
                                          return Padding(
                                            padding: const EdgeInsets.only(top: 8),
                                            child: Text('St.${value.toInt() + 1}', style: const TextStyle(fontSize: 12)),
                                          );
                                        }
                                        return const SizedBox.shrink();
                                      },
                                    ),
                                  ),
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                                  ),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                ),
                                gridData: FlGridData(show: true, drawVerticalLine: false),
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
                                        padding: const EdgeInsets.only(right: 5, bottom: 5),
                                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                                        labelResolver: (line) => 'Takt: ${line.y.toStringAsFixed(1)}s',
                                      ),
                                    ),
                                  ],
                                ),
                                barGroups: state.stations.asMap().entries.map((e) {
                                  final isBottleneck = e.value.cycleTime > state.taktTimeSec;
                                  return BarChartGroupData(
                                    x: e.key,
                                    barRods: [
                                      BarChartRodData(
                                        toY: e.value.cycleTime,
                                        color: isBottleneck ? Colors.red.shade400 : Colors.blue.shade400,
                                        width: 40,
                                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                                      ),
                                    ],
                                  );
                                }).toList(),
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
            const SizedBox(height: 32),
            
            // Workstations Table
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('สถานีทำงาน (Workstations)', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  onPressed: () {
                    _showAddStationDialog(context, notifier);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('เพิ่มสถานี'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: state.stations.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final st = state.stations[index];
                  final isBottleneck = st.cycleTime > state.taktTimeSec;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isBottleneck ? Colors.red.withValues(alpha: 0.1) : Colors.blue.withValues(alpha: 0.1),
                      child: Text('${index + 1}', style: TextStyle(color: isBottleneck ? Colors.red : Colors.blue)),
                    ),
                    title: Text(st.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Cycle Time: ${st.cycleTime}s'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isBottleneck)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)),
                            child: const Text('Bottleneck', style: TextStyle(color: Colors.red, fontSize: 12)),
                          ),
                        const SizedBox(width: 16),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.grey),
                          onPressed: () => notifier.removeStation(st.id),
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
    );
  }

  Widget _buildKPI(ThemeData theme, String label, String value, String subtitle, Color color) {
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
              Text(label, style: theme.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(value, style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }

  void _showAddStationDialog(BuildContext context, LineBalancingNotifier notifier) {
    String name = 'Station';
    double cycleTime = 20.0;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('เพิ่มสถานีใหม่'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                decoration: const InputDecoration(labelText: 'ชื่อสถานี'),
                onChanged: (v) => name = v,
              ),
              const SizedBox(height: 16),
              TextFormField(
                decoration: const InputDecoration(labelText: 'Cycle Time (วินาที)'),
                keyboardType: TextInputType.number,
                onChanged: (v) => cycleTime = double.tryParse(v) ?? 20.0,
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () {
                notifier.addStation(name, cycleTime);
                Navigator.pop(context);
              },
              child: const Text('บันทึก'),
            ),
          ],
        );
      },
    );
  }
}
"""

with codecs.open('lib/features/line_balancing/line_balancing_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Rewrote line balancing screen with correct utf-8 encoding")
