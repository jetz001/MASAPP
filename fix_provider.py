import codecs

with codecs.open('lib/features/analytics/analytics_provider.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_query = """      // Get total running hours (from all machines)
      final runningHoursResult = await DbHelper.queryOne(
        '''SELECT COALESCE(SUM(cumulative_hours), 0) as total FROM machine_running_hours''',
      );
      var totalRunningHours =
          (runningHoursResult?['total'] as num?)?.toDouble() ?? 0;"""

new_query = """      // Get total running hours and production data
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
      var totalRunningHours =
          (runningHoursResult?['total_hrs'] as num?)?.toDouble() ?? 0;
      var totalTarget = (runningHoursResult?['total_target'] as num?)?.toDouble() ?? 0;
      var totalActual = (runningHoursResult?['total_actual'] as num?)?.toDouble() ?? 0;
      var totalGood = (runningHoursResult?['total_good'] as num?)?.toDouble() ?? 0;"""

content = content.replace(old_query, new_query)

old_calc = """      final oee = MaintenanceMetrics.calculateOEE(availability);

      return MaintenanceMetrics(
        mtbf: mtbf,
        mttr: mttr,
        oee: oee,
        availability: availability,"""

new_calc = """      // Calculate Performance and Quality
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
        quality: quality,"""
content = content.replace(old_calc, new_calc)

old_catch = """      return MaintenanceMetrics(
        mtbf: 0,
        mttr: 0,
        oee: 0,
        availability: 0,"""

new_catch = """      return MaintenanceMetrics(
        mtbf: 0,
        mttr: 0,
        oee: 0,
        availability: 0,
        performance: 0,
        quality: 0,"""
content = content.replace(old_catch, new_catch)

with codecs.open('lib/features/analytics/analytics_provider.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated provider logic")
