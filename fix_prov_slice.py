# -*- coding: utf-8 -*-
import codecs

with codecs.open('lib/features/analytics/analytics_provider.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

start_idx = -1
end_idx = -1
for i, line in enumerate(lines):
    if 'Future<MaintenanceMetrics> getMaintenanceMetrics({' in line:
        start_idx = i
    if start_idx != -1 and i > start_idx + 10 and 'Future<CostAnalysis> getCostAnalysis({' in line:
        end_idx = i - 1
        break

if start_idx != -1 and end_idx != -1:
    new_method = """  Future<MaintenanceMetrics> getMaintenanceMetrics({
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
"""
    new_lines = lines[:start_idx] + [new_method] + lines[end_idx:]
    with codecs.open('lib/features/analytics/analytics_provider.dart', 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    print("Replaced getMaintenanceMetrics correctly!")
else:
    print("Could not find start/end")
