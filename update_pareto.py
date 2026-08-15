import re

with open('lib/features/analytics/analytics_provider.dart', 'r', encoding='utf8') as f:
    content = f.read()

old_func = re.search(r'Future<ParetoAnalysis> getParetoAnalysis.*?\}\n  \}', content, re.DOTALL).group()

new_func = \"\"\"  Future<ParetoAnalysis> getParetoAnalysis({
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
        selectField = 'COALESCE(s.machine_name, \\'Unknown\\')';
        joinClause = 'LEFT JOIN machine_snapshots s ON s.snapshot_id = wo.snapshot_id';
      } else if (groupBy == 'failureType') {
        selectField = 'COALESCE(rca.failure_type, \\'Unknown\\')';
        joinClause = 'LEFT JOIN work_order_rca rca ON rca.wo_id = wo.wo_id';
      } else if (groupBy == 'causeCategory') {
        selectField = 'COALESCE(rca.cause_category, \\'Unknown\\')';
        joinClause = 'LEFT JOIN work_order_rca rca ON rca.wo_id = wo.wo_id';
      } else {
        selectField = 'COALESCE(NULLIF(wo.failure_symptom, \\'\\'), NULLIF(wo.title, \\'\\'), \\'Unknown\\')';
        joinClause = '';
      }

      final results = await DbHelper.query(
        '''SELECT 
            \ as failure, 
            COUNT(*) as count
           FROM work_orders wo
           \
           WHERE wo.status = 'completed' AND wo.created_at BETWEEN @start AND @end
           GROUP BY \
           ORDER BY count DESC
           LIMIT 15''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );

      final total = results.fold<int>(
        0,
        (sum, row) => sum + (row['count'] as int? ?? 0),
      );

      int cumulative = 0;
      final paretoData =
          results.map((row) {
            final count = row['count'] as int? ?? 0;
            cumulative += count;
            final cumulativePct = total > 0 ? (cumulative / total) * 100 : 0.0;
            return ParetoData(
              category: row['failure'] as String? ?? 'Unknown',
              count: count,
              cumulativePercentage: cumulativePct,
            );
          }).toList();

      return ParetoAnalysis(items: paretoData, totalFailures: total);
    } catch (e, stack) {
      print('ERROR in getParetoAnalysis: \\\n\');
      rethrow;
    }
  }\"\"\"

content = content.replace(old_func, new_func)

state_provider_code = '''
/// Pareto grouping option
final paretoGroupByProvider = StateProvider<String>((ref) => 'failureType');
'''
content = content.replace('/// Pareto analysis', state_provider_code + '\n/// Pareto analysis')

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

with open('lib/features/analytics/analytics_provider.dart', 'w', encoding='utf8') as f:
    f.write(content)
print('Updated analytics_provider.dart')
