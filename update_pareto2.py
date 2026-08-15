import re
import codecs

with codecs.open('lib/features/analytics/analytics_provider.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the getParetoAnalysis function
old_func_pattern = r'  /// Get Pareto analysis of failures\s+Future<ParetoAnalysis> getParetoAnalysis\(\{.*?return const ParetoAnalysis\(categories: \[\], total: 0\);\s+\}\s+\}'

new_func = '''  /// Get Pareto analysis of failures
  Future<ParetoAnalysis> getParetoAnalysis({
    DateTime? startDate,
    DateTime? endDate,
    String groupBy = 'failureType',
  }) async {
    try {
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();
      
      String selectField = '';
      String joinClause = '';
      
      if (groupBy == 'machine') {
        selectField = "COALESCE(s.machine_name, 'Unknown')";
        joinClause = 'LEFT JOIN machine_snapshots s ON s.snapshot_id = wo.snapshot_id';
      } else if (groupBy == 'failureType') {
        selectField = "COALESCE(rca.failure_type, 'Unknown')";
        joinClause = 'LEFT JOIN work_order_rca rca ON rca.wo_id = wo.wo_id';
      } else if (groupBy == 'causeCategory') {
        selectField = "COALESCE(rca.cause_category, 'Unknown')";
        joinClause = 'LEFT JOIN work_order_rca rca ON rca.wo_id = wo.wo_id';
      } else {
        selectField = "COALESCE(NULLIF(wo.failure_symptom, ''), NULLIF(wo.title, ''), 'Unknown')";
        joinClause = '';
      }

      final results = await DbHelper.query(
        """SELECT 
             as failure, 
            COUNT(*) as count
           FROM work_orders wo
           
           WHERE wo.status = 'completed' AND wo.created_at BETWEEN @start AND @end
           GROUP BY 
           ORDER BY count DESC
           LIMIT 15""",
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );

      final failureCounts = <String, int>{};
      for (final row in results) {
        failureCounts[row['failure'] as String? ?? 'Unknown'] = (row['count'] as int);
      }

      return ParetoAnalysis.calculate(failureCounts);
    } catch (e, stack) {
      print('ERROR in getParetoAnalysis: \\n');
      return const ParetoAnalysis(categories: [], total: 0);
    }
  }'''

content = re.sub(old_func_pattern, new_func, content, flags=re.DOTALL)

# Replace the provider
provider_old = '''final paretoAnalysisProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  final dateRange = ref.watch(analyticsDateRangeProvider);
  return await service.getParetoAnalysis(
    startDate: dateRange?.start,
    endDate: dateRange?.end,
  );
});'''

provider_new = '''final paretoAnalysisProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  final dateRange = ref.watch(analyticsDateRangeProvider);
  final groupBy = ref.watch(paretoGroupByProvider);
  return await service.getParetoAnalysis(
    startDate: dateRange?.start,
    endDate: dateRange?.end,
    groupBy: groupBy,
  );
});'''

content = content.replace(provider_old, provider_new)

with codecs.open('lib/features/analytics/analytics_provider.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('Updated getParetoAnalysis')
