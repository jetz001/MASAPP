# -*- coding: utf-8 -*-
import codecs

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_kpi_class = """class _KPICard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final String tooltip;
  final Color color;
  final IconData icon;

  const _KPICard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.tooltip,
    required this.color,
    required this.icon,
  });"""

new_kpi_class = """class _KPICard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final String tooltip;
  final Color color;
  final IconData icon;
  final List<double>? trendData;

  const _KPICard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.tooltip,
    required this.color,
    required this.icon,
    this.trendData,
  });"""

content = content.replace(old_kpi_class, new_kpi_class)

old_kpi_build = """            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
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
    );
  }
}"""

new_kpi_build = """            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                          height: 1.2,
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
                if (trendData != null && trendData!.isNotEmpty)
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 40,
                      child: LineChart(
                        LineChartData(
                          minX: 0,
                          maxX: (trendData!.length - 1).toDouble(),
                          minY: trendData!.reduce((a, b) => a < b ? a : b) * 0.9,
                          maxY: trendData!.reduce((a, b) => a > b ? a : b) * 1.1,
                          lineBarsData: [
                            LineChartBarData(
                              spots: trendData!.asMap().entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                              isCurved: true,
                              color: color,
                              barWidth: 2,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: color.withAlpha(30),
                              ),
                            ),
                          ],
                          titlesData: const FlTitlesData(show: false),
                          gridData: const FlGridData(show: false),
                          borderData: FlBorderData(show: false),
                          lineTouchData: const LineTouchData(enabled: false),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}"""

content = content.replace(old_kpi_build, new_kpi_build)

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated KPI card to include sparkline")
