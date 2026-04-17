import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'analytics_models.dart';
import 'analytics_provider.dart';

class AnalyticsDashboardScreen extends ConsumerWidget {
  const AnalyticsDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(maintenanceMetricsProvider);
    final paretoAsync = ref.watch(paretoAnalysisProvider);
    final costAsync = ref.watch(costAnalysisProvider);
    final predictionsAsync = ref.watch(failurePredictionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics Dashboard'), elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Cards
            metricsAsync.when(
              data: (metrics) => _KPICards(metrics: metrics),
              loading: () => const _SkeletonLoader(),
              error: (err, _) => Text('Error loading metrics: $err'),
            ),

            const SizedBox(height: 32),

            // Pareto Chart
            const Text(
              'Failure Analysis (Pareto)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            paretoAsync.when(
              data: (pareto) => _ParetoChart(analysis: pareto),
              loading: () => const _SkeletonLoader(),
              error: (err, _) => Text('Error loading Pareto: $err'),
            ),

            const SizedBox(height: 32),

            // Cost Breakdown
            const Text(
              'Cost Breakdown (PM vs CM)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            costAsync.when(
              data: (cost) => _CostBreakdownChart(analysis: cost),
              loading: () => const _SkeletonLoader(),
              error: (err, _) => Text('Error loading cost data: $err'),
            ),

            const SizedBox(height: 32),

            // Risk Predictions
            const Text(
              'Equipment Risk Predictions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            predictionsAsync.when(
              data: (predictions) =>
                  _RiskPredictionsList(predictions: predictions),
              loading: () => const _SkeletonLoader(),
              error: (err, _) => Text('Error loading predictions: $err'),
            ),
          ],
        ),
      ),
    );
  }
}

/// KPI Cards
class _KPICards extends StatelessWidget {
  final MaintenanceMetrics metrics;

  const _KPICards({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        _KPICard(
          label: 'MTBF',
          value: '${metrics.mtbf.toStringAsFixed(0)}h',
          subtitle: 'Mean Time Between Failures',
          color: Colors.blue,
        ),
        _KPICard(
          label: 'MTTR',
          value: '${metrics.mttr.toStringAsFixed(1)}h',
          subtitle: 'Mean Time To Repair',
          color: Colors.orange,
        ),
        _KPICard(
          label: 'OEE',
          value: '${metrics.oee.toStringAsFixed(1)}%',
          subtitle: 'Overall Equipment Effectiveness',
          color: Colors.green,
        ),
        _KPICard(
          label: 'Availability',
          value: '${(metrics.availability * 100).toStringAsFixed(1)}%',
          subtitle: 'Equipment Availability',
          color: Colors.purple,
        ),
      ],
    );
  }
}

class _KPICard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color color;

  const _KPICard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        border: Border.all(color: color.withAlpha(100)),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

/// Pareto Chart
class _ParetoChart extends StatelessWidget {
  final ParetoAnalysis analysis;

  const _ParetoChart({required this.analysis});

  @override
  Widget build(BuildContext context) {
    if (analysis.categories.isEmpty) {
      return const SizedBox(
        height: 300,
        child: Center(child: Text('No failure data available')),
      );
    }

    return Container(
      height: 300,
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: BarChart(
        BarChartData(
          barGroups: List.generate(
            analysis.categories.length,
            (index) => BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: analysis.categories[index].percentage.toDouble(),
                  color: Colors.blue,
                  width: 20,
                ),
              ],
            ),
          ),
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final category = analysis.categories[value.toInt()];
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      category.category.length > 10
                          ? '${category.category.substring(0, 10)}...'
                          : category.category,
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) => Text(
                  '${value.toInt()}%',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Cost Breakdown Chart
class _CostBreakdownChart extends StatelessWidget {
  final CostAnalysis analysis;

  const _CostBreakdownChart({required this.analysis});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: PieChart(
              PieChartData(
                sections: List.generate(
                  analysis.breakdown.length,
                  (index) => PieChartSectionData(
                    value: analysis.breakdown[index].amount,
                    title:
                        '${analysis.breakdown[index].percentage.toStringAsFixed(1)}%',
                    radius: 60,
                    color: [Colors.blue, Colors.orange, Colors.green][index],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: List.generate(
              analysis.breakdown.length,
              (index) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: [Colors.blue, Colors.orange, Colors.green][index],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${analysis.breakdown[index].category}: \$${analysis.breakdown[index].amount.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Risk Predictions List
class _RiskPredictionsList extends StatelessWidget {
  final List<FailurePrediction> predictions;

  const _RiskPredictionsList({required this.predictions});

  @override
  Widget build(BuildContext context) {
    if (predictions.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(child: Text('No machines to predict')),
      );
    }

    // Show only high risk and above
    final highRisk = predictions.where((p) => p.riskScore >= 50).toList();

    if (highRisk.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green.withAlpha(30),
          border: Border.all(color: Colors.green),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'All equipment operating normally - no high-risk predictions',
          style: TextStyle(color: Colors.greenAccent),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: highRisk.length,
      itemBuilder: (context, index) {
        final pred = highRisk[index];
        final color = _getRiskColor(pred.riskScore);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withAlpha(30),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    pred.machineNo,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      pred.riskLevel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: pred.riskScore / 100,
                backgroundColor: Colors.grey.withAlpha(100),
                valueColor: AlwaysStoppedAnimation(color),
              ),
              const SizedBox(height: 8),
              if (pred.reason != null)
                Text(
                  pred.reason!,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
            ],
          ),
        );
      },
    );
  }

  Color _getRiskColor(double score) {
    if (score >= 75) return Colors.red;
    if (score >= 50) return Colors.orange;
    return Colors.yellow;
  }
}

/// Skeleton loader for loading state
class _SkeletonLoader extends StatelessWidget {
  const _SkeletonLoader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
