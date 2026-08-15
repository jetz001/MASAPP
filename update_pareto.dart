import 'dart:io';

void main() {
  final file = File('lib/features/analytics/analytics_provider.dart');
  var content = file.readAsStringSync();
  
  final regex = RegExp(r'Future<ParetoAnalysis> getParetoAnalysis.*?\}\n  \}', dotAll: true);
  final oldFunc = regex.firstMatch(content)?.group(0);
  
  final newFunc = r'''  Future<ParetoAnalysis> getParetoAnalysis({
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
            \ as failure, 
            COUNT(*) as count
           FROM work_orders wo
           \
           WHERE wo.status = 'completed' AND wo.created_at BETWEEN @start AND @end
           GROUP BY \
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
      print('ERROR in getParetoAnalysis: \\\n\');
      rethrow;
    }
  }''';

  content = content.replaceAll(RegExp(r'Future<ParetoAnalysis> getParetoAnalysis\(\{.*?rethrow;\n    \}\n  \}', dotAll: true), newFunc);
  
  final stateProviderCode = '''
/// Pareto grouping option
final paretoGroupByProvider = StateProvider<String>((ref) => 'failureType');
''';
  if (!content.contains('paretoGroupByProvider')) {
    content = content.replaceAll('/// Pareto analysis', stateProviderCode + '\n/// Pareto analysis');
  }
  
  final providerOld = '''final paretoAnalysisProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  final dateRange = ref.watch(analyticsDateRangeProvider);
  return await service.getParetoAnalysis(
    startDate: dateRange?.start,
    endDate: dateRange?.end,
  );
});''';

  final providerNew = '''final paretoAnalysisProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  final dateRange = ref.watch(analyticsDateRangeProvider);
  final groupBy = ref.watch(paretoGroupByProvider);
  return await service.getParetoAnalysis(
    startDate: dateRange?.start,
    endDate: dateRange?.end,
    groupBy: groupBy,
  );
});''';

  content = content.replaceAll(providerOld, providerNew);
  
  file.writeAsStringSync(content);
  print('Updated analytics_provider.dart');
}
