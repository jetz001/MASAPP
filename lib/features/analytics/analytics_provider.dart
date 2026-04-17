import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/db_helper.dart';
import 'analytics_models.dart';

/// Analytics computation service
class AnalyticsService {
  /// Get maintenance metrics for a period
  Future<MaintenanceMetrics> getMaintenanceMetrics({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();

      // Get breakdown count
      final breakdownResult = await DbHelper.queryOne(
        '''SELECT COUNT(*) as count FROM work_orders
           WHERE status = 'completed' AND created_at BETWEEN @start AND @end''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );
      final totalBreakdowns = (breakdownResult?['count'] as int?) ?? 0;

      // Get total work orders
      final woResult = await DbHelper.queryOne(
        '''SELECT COUNT(*) as count FROM work_orders
           WHERE created_at BETWEEN @start AND @end''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );
      final totalWorkOrders = (woResult?['count'] as int?) ?? 0;

      // Get total downtime hours
      final downtimeResult = await DbHelper.queryOne(
        '''SELECT COALESCE(SUM(actual_hours), 0) as total FROM work_orders
           WHERE status = 'completed' AND created_at BETWEEN @start AND @end''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );
      final totalDowntimeHours =
          (downtimeResult?['total'] as num?)?.toDouble() ?? 0;

      // Get total maintenance cost (assuming labor cost only for now)
      // In real scenario, would also include spare parts
      final laborCostResult = await DbHelper.queryOne(
        '''SELECT COALESCE(SUM(hours * 500), 0) as total FROM work_order_labor
           WHERE start_time BETWEEN @start AND @end''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );
      final totalMaintenanceCost =
          (laborCostResult?['total'] as num?)?.toDouble() ?? 0;

      // Get total running hours (from all machines)
      final runningHoursResult = await DbHelper.queryOne(
        '''SELECT COALESCE(SUM(cumulative_hours), 0) as total FROM machine_running_hours''',
      );
      final totalRunningHours =
          (runningHoursResult?['total'] as num?)?.toDouble() ?? 0;

      // Calculate metrics
      final mtbf = MaintenanceMetrics.calculateMTBF(
        totalRunningHours,
        totalBreakdowns,
      );
      final mttr = MaintenanceMetrics.calculateMTTR(
        totalDowntimeHours,
        totalBreakdowns,
      );
      final availability = MaintenanceMetrics.calculateAvailability(
        totalRunningHours,
        totalRunningHours + totalDowntimeHours,
      );
      final oee = MaintenanceMetrics.calculateOEE(availability);

      return MaintenanceMetrics(
        mtbf: mtbf,
        mttr: mttr,
        oee: oee,
        availability: availability,
        totalBreakdowns: totalBreakdowns,
        totalWorkOrders: totalWorkOrders,
        totalDowntimeHours: totalDowntimeHours,
        totalMaintenanceCost: totalMaintenanceCost,
        period: start,
      );
    } catch (e) {
      // Return default metrics on error
      return MaintenanceMetrics(
        mtbf: 0,
        mttr: 0,
        oee: 0,
        availability: 0,
        totalBreakdowns: 0,
        totalWorkOrders: 0,
        totalDowntimeHours: 0,
        totalMaintenanceCost: 0,
        period: DateTime.now(),
      );
    }
  }

  /// Get Pareto analysis of failures
  Future<ParetoAnalysis> getParetoAnalysis({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();

      final results = await DbHelper.query(
        '''SELECT COALESCE(failure_symptom, 'Unknown') as failure, COUNT(*) as count
           FROM work_orders
           WHERE status = 'completed' AND created_at BETWEEN @start AND @end
           GROUP BY failure_symptom
           ORDER BY count DESC''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );

      final failureCounts = <String, int>{};
      for (final row in results) {
        failureCounts[row['failure'] as String] = (row['count'] as int);
      }

      return ParetoAnalysis.calculate(failureCounts);
    } catch (e) {
      return const ParetoAnalysis(categories: [], total: 0);
    }
  }

  /// Get cost analysis (PM vs CM)
  Future<CostAnalysis> getCostAnalysis({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();

      // Get PM cost (from PM records - placeholder, needs PM module)
      const pmCost = 0.0; // Would be calculated from PM records

      // Get CM cost (from work orders)
      final cmResult = await DbHelper.queryOne(
        '''SELECT COALESCE(SUM(hours * 500), 0) as total FROM work_order_labor
           WHERE start_time BETWEEN @start AND @end''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );
      final cmCost = (cmResult?['total'] as num?)?.toDouble() ?? 0;

      // Get spare parts cost (placeholder)
      const sparePartsCost = 0.0;

      final totalCost = pmCost + cmCost + sparePartsCost;

      final breakdown = <CostBreakdown>[
        CostBreakdown(
          category: 'PM (Preventive)',
          amount: pmCost,
          percentage: totalCost > 0 ? (pmCost / totalCost) * 100 : 0,
        ),
        CostBreakdown(
          category: 'CM (Corrective)',
          amount: cmCost,
          percentage: totalCost > 0 ? (cmCost / totalCost) * 100 : 0,
        ),
        CostBreakdown(
          category: 'Spare Parts',
          amount: sparePartsCost,
          percentage: totalCost > 0 ? (sparePartsCost / totalCost) * 100 : 0,
        ),
      ];

      return CostAnalysis(
        breakdown: breakdown,
        totalCost: totalCost,
        pmCost: pmCost,
        cmCost: cmCost,
        sparePartsCost: sparePartsCost,
      );
    } catch (e) {
      return const CostAnalysis(
        breakdown: [],
        totalCost: 0,
        pmCost: 0,
        cmCost: 0,
        sparePartsCost: 0,
      );
    }
  }

  /// Get failure predictions for all machines
  Future<List<FailurePrediction>> getFailurePredictions() async {
    try {
      // Get all machines with their recent failure data
      final machines = await DbHelper.query('''SELECT m.machine_id, m.machine_no
           FROM machines m WHERE m.is_active = 1''');

      final predictions = <FailurePrediction>[];

      for (final machineRow in machines) {
        final machineId = machineRow['machine_id'] as String;
        final machineNo = machineRow['machine_no'] as String;

        // Get MTBF data
        final mtbfResult = await DbHelper.queryOne(
          '''SELECT 
              COALESCE(SUM(rh.cumulative_hours), 0) / MAX(1, COUNT(wo.wo_id)) as avg_mtbf,
              COUNT(wo.wo_id) as failures
           FROM machines m
           LEFT JOIN machine_running_hours rh ON rh.machine_id = m.machine_id
           LEFT JOIN work_orders wo ON wo.machine_id = m.machine_id
           WHERE m.machine_id = @id''',
          params: {'id': machineId},
        );

        final avgMTBF = (mtbfResult?['avg_mtbf'] as num?)?.toDouble() ?? 0;
        final recentFailures = (mtbfResult?['failures'] as int?) ?? 0;

        // Get current MTBF (last 30 days)
        final currentResult = await DbHelper.queryOne(
          '''SELECT 
              COALESCE(SUM(rh.cumulative_hours), 0) / MAX(1, COUNT(wo.wo_id)) as current_mtbf
           FROM machines m
           LEFT JOIN machine_running_hours rh ON rh.machine_id = m.machine_id AND rh.recorded_date > datetime('now', '-30 days')
           LEFT JOIN work_orders wo ON wo.machine_id = m.machine_id AND wo.created_at > datetime('now', '-30 days')
           WHERE m.machine_id = @id''',
          params: {'id': machineId},
        );

        final currentMTBF =
            (currentResult?['current_mtbf'] as num?)?.toDouble() ?? avgMTBF;

        predictions.add(
          FailurePrediction.fromCalculation(
            machineId: machineId,
            machineNo: machineNo,
            currentMTBF: currentMTBF,
            averageMTBF: avgMTBF,
            recentFailures: recentFailures,
          ),
        );
      }

      // Sort by risk score (highest first)
      predictions.sort((a, b) => b.riskScore.compareTo(a.riskScore));
      return predictions;
    } catch (e) {
      return [];
    }
  }
}

/// Riverpod providers

final analyticsServiceProvider = Provider((ref) => AnalyticsService());

/// Main maintenance metrics
final maintenanceMetricsProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  return await service.getMaintenanceMetrics();
});

/// Pareto analysis
final paretoAnalysisProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  return await service.getParetoAnalysis();
});

/// Cost analysis
final costAnalysisProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  return await service.getCostAnalysis();
});

/// Failure predictions
final failurePredictionsProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  return await service.getFailurePredictions();
});
