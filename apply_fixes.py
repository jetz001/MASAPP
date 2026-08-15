# -*- coding: utf-8 -*-
import codecs
import re

with codecs.open('lib/features/analytics/analytics_provider.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Fix getMaintenanceMetrics running hours
content = re.sub(
    r"""// Get total running hours \(from all machines\)\s*final runningHoursResult = await DbHelper\.queryOne\(\s*'''SELECT COALESCE\(SUM\(cumulative_hours\), 0\) as total FROM machine_running_hours''',\s*\);\s*var totalRunningHours =\s*\(runningHoursResult\?\['total'\] as num\?\)\?\.toDouble\(\) \?\? 0;""",
    r"""// Get total running hours and production data
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
      var totalGood = (runningHoursResult?['total_good'] as num?)?.toDouble() ?? 0;""",
    content, flags=re.MULTILINE
)

# 2. Fix getMaintenanceMetrics return
content = re.sub(
    r"""final oee = MaintenanceMetrics\.calculateOEE\(availability\);\s*return MaintenanceMetrics\(\s*mtbf: mtbf,\s*mttr: mttr,\s*oee: oee,\s*availability: availability,""",
    r"""// Calculate Performance and Quality
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
        quality: quality,""",
    content, flags=re.MULTILINE
)

# 3. Fix catch block return
content = re.sub(
    r"""return MaintenanceMetrics\(\s*mtbf: 0,\s*mttr: 0,\s*oee: 0,\s*availability: 0,""",
    r"""return MaintenanceMetrics(
        mtbf: 0,
        mttr: 0,
        oee: 0,
        availability: 0,
        performance: 0,
        quality: 0,""",
    content, flags=re.MULTILINE
)

# 4. Fix getCostAnalysis
content = re.sub(
    r"""// Get CM cost \(from work orders\)\s*final cmResult = await DbHelper\.queryOne\(\s*'''SELECT COALESCE\(SUM\(hours \* 500\), 0\) as total FROM work_order_labor\s*WHERE start_time BETWEEN @start AND @end''',\s*params: \{\s*'start': start\.toIso8601String\(\),\s*'end': end\.toIso8601String\(\),\s*\},\s*\);\s*final cmCost = \(cmResult\?\['total'\] as num\?\)\?\.toDouble\(\) \?\? 0;\s*// Get spare parts cost \(placeholder\)\s*const sparePartsCost = 0\.0;""",
    r"""// Get CM cost (from work_order_labor)
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
      final sparePartsCost = (partsResult?['total'] as num?)?.toDouble() ?? 0;""",
    content, flags=re.MULTILINE
)

with codecs.open('lib/features/analytics/analytics_provider.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Applied all fixes using regex")
