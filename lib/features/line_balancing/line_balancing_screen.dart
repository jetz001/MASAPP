import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'line_balancing_provider.dart';
import 'add_station_dialog.dart'; // Add this import

import 'line_graph_canvas.dart';

class LineBalancingScreen extends ConsumerWidget {
  const LineBalancingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(lineBalancingProvider);
    final notifier = ref.read(lineBalancingProvider.notifier);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Line Balancing Calculator'),
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
                                    if (val != null)
                                      notifier.updateAvailableTime(val);
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
                                    if (val != null) notifier.updateDemand(val);
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
                                    if (val != null)
                                      notifier.updateRates(val, state.fuelRate);
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
                                    if (val != null)
                                      notifier.updateRates(
                                        state.electricityRate,
                                        val,
                                      );
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
            ), // Closes SingleChildScrollView
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
}
