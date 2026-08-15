# -*- coding: utf-8 -*-
import codecs

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

trend_widget = """
class _OeeTrendChart extends ConsumerWidget {
  const _OeeTrendChart();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trendAsync = ref.watch(oeeTrendProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'OEE Trend (30 วันล่าสุด)',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          height: 300,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withAlpha(100),
            ),
          ),
          child: trendAsync.when(
            data: (data) {
              if (data.isEmpty) {
                return const Center(child: Text('ไม่มีข้อมูล OEE สำหรับช่วงเวลานี้'));
              }
              
              // Sort data by date
              data.sort((a, b) => a.date.compareTo(b.date));
              
              double minY = 0;
              double maxY = 100;
              
              final spots = data.asMap().entries.map((e) {
                return FlSpot(e.key.toDouble(), e.value.value);
              }).toList();

              return LineChart(
                LineChartData(
                  minY: minY,
                  maxY: maxY,
                  minX: 0,
                  maxX: (data.length - 1).toDouble(),
                  lineBarsData: [
                    LineChartBarData(
                      spots: spots,
                      isCurved: true,
                      color: Colors.green,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.green.withAlpha(30),
                      ),
                    ),
                  ],
                  titlesData: FlTitlesData(
                    show: true,
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        getTitlesWidget: (value, meta) {
                          return Text('${value.toInt()}%', style: const TextStyle(fontSize: 12));
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < 0 || value.toInt() >= data.length) {
                            return const SizedBox.shrink();
                          }
                          // Show title every 3-4 days to prevent crowding
                          if (data.length > 10 && value.toInt() % (data.length ~/ 6) != 0 && value.toInt() != data.length - 1) {
                            return const SizedBox.shrink();
                          }
                          final date = data[value.toInt()].date;
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${date.day}/${date.month}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 20,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: theme.colorScheme.outlineVariant.withAlpha(50),
                        strokeWidth: 1,
                      );
                    },
                  ),
                  borderData: FlBorderData(show: false),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }
}
"""

content = content.replace("class _CostBreakdownChart extends ConsumerWidget {", trend_widget + "\nclass _CostBreakdownChart extends ConsumerWidget {")

# Add the widget to the column in the main build method
old_build = """                        const SizedBox(height: 32),
                        const _ParetoChart(),
                        const SizedBox(height: 32),
                        const _CostBreakdownChart(),"""
new_build = """                        const SizedBox(height: 32),
                        const _OeeTrendChart(),
                        const SizedBox(height: 32),
                        const _ParetoChart(),
                        const SizedBox(height: 32),
                        const _CostBreakdownChart(),"""

content = content.replace(old_build, new_build)

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Added OEE Trend Chart to UI")
