import 'package:flutter/material.dart';
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
      // Adjust end date to the end of the day to ensure we include records created on that day
      var end = endDate ?? DateTime.now();
      end = DateTime(end.year, end.month, end.day, 23, 59, 59);

      // Get breakdown counts
      final breakdownsResult = await DbHelper.queryOne(
        '''SELECT COUNT(*) as count FROM work_orders 
           WHERE status = 'completed' AND created_at BETWEEN @start AND @end''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );
      final totalBreakdowns = (breakdownsResult?['count'] as int?) ?? 0;

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

      // Get total downtime (actual_hours from work orders)
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

      // Get labor cost
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

      // Get total running hours and production data
      final runningHoursResult = await DbHelper.queryOne(
        '''SELECT 
            COALESCE(SUM(cumulative_hours), 0) as total_hrs,
            COALESCE(SUM(target_production), 0) as total_target,
            COALESCE(SUM(actual_production), 0) as total_actual,
            COALESCE(SUM(good_production), 0) as total_good
           FROM machine_running_hours
           WHERE recorded_date BETWEEN @start AND @end''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        }
      );
      var totalRunningHours = (runningHoursResult?['total_hrs'] as num?)?.toDouble() ?? 0;
      var totalTarget = (runningHoursResult?['total_target'] as num?)?.toDouble() ?? 0;
      var totalActual = (runningHoursResult?['total_actual'] as num?)?.toDouble() ?? 0;
      var totalGood = (runningHoursResult?['total_good'] as num?)?.toDouble() ?? 0;

      // Fallback: If no running hours are logged, estimate them to show meaningful KPIs
      if (totalRunningHours <= 0) {
        final machinesResult = await DbHelper.queryOne(
          '''SELECT COUNT(*) as count FROM machines WHERE is_active = 1''',
        );
        final totalMachines = (machinesResult?['count'] as int?) ?? 1;
        final daysInPeriod = end.difference(start).inDays > 0 ? end.difference(start).inDays : 1;
        // Estimate: Machines run 8 hours a day
        totalRunningHours = totalMachines * daysInPeriod * 8.0;
      }

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
      
      // Calculate Performance and Quality
      double performance = 1.0;
      if (totalTarget > 0) {
        performance = totalActual / totalTarget;
      }
      double quality = 1.0;
      if (totalActual > 0) {
        quality = totalGood / totalActual;
      }
      
      final oee = MaintenanceMetrics.calculateOEE(availability, performance, quality);

      return MaintenanceMetrics(
        mtbf: mtbf,
        mttr: mttr,
        oee: oee,
        availability: availability,
        performance: performance,
        quality: quality,
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
        performance: 0,
        quality: 0,
        totalBreakdowns: 0,
        totalWorkOrders: 0,
        totalDowntimeHours: 0,
        totalMaintenanceCost: 0,
        period: startDate ?? DateTime.now().subtract(const Duration(days: 30)),
      );
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
      var end = endDate ?? DateTime.now();
      end = DateTime(end.year, end.month, end.day, 23, 59, 59);

      // Get PM cost (placeholder, could query work_orders with PM title)
      const pmCost = 0.0; 

      // Get CM cost (from work_order_labor)
      final cmResult = await DbHelper.queryOne(
        '''SELECT COALESCE(SUM(l.hours * 500), 0) as total 
           FROM work_order_labor l
           JOIN work_orders w ON l.wo_id = w.wo_id
           WHERE w.created_at BETWEEN @start AND @end''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );
      final cmCost = (cmResult?['total'] as num?)?.toDouble() ?? 0;

      // Get spare parts cost
      final partsResult = await DbHelper.queryOne(
        '''SELECT COALESCE(SUM(wp.quantity * sp.unit_cost), 0) as total 
           FROM work_order_parts wp
           JOIN spare_parts sp ON wp.part_id = sp.part_id
           JOIN work_orders w ON wp.wo_id = w.wo_id
           WHERE w.created_at BETWEEN @start AND @end''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );
      final sparePartsCost = (partsResult?['total'] as num?)?.toDouble() ?? 0;

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

/// Date range state for Analytics
final analyticsDateRangeProvider = StateProvider<DateTimeRange?>((ref) {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, 1, 1),
    end: now,
  );
});

final analyticsServiceProvider = Provider((ref) => AnalyticsService());

/// Main maintenance metrics
final maintenanceMetricsProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  final dateRange = ref.watch(analyticsDateRangeProvider);
  return await service.getMaintenanceMetrics(
    startDate: dateRange?.start,
    endDate: dateRange?.end,
  );
});

/// Pareto grouping option
final paretoGroupByProvider = StateProvider<String>((ref) => 'failureType');

/// Pareto analysis
final paretoAnalysisProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  final dateRange = ref.watch(analyticsDateRangeProvider);
  final groupBy = ref.watch(paretoGroupByProvider);
  return await service.getParetoAnalysis(
    startDate: dateRange?.start,
    endDate: dateRange?.end,
    groupBy: groupBy,
  );
});

/// Cost analysis
final costAnalysisProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  final dateRange = ref.watch(analyticsDateRangeProvider);
  return await service.getCostAnalysis(
    startDate: dateRange?.start,
    endDate: dateRange?.end,
  );
});

/// Failure predictions (Doesn't use date range currently, but kept for consistency)
final failurePredictionsProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  return await service.getFailurePredictions();
});
