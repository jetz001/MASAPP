import codecs

with codecs.open('lib/features/analytics/analytics_provider.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix for getMaintenanceMetrics
old_metrics = """      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();"""

new_metrics = """      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      var end = endDate ?? DateTime.now();
      if (endDate != null) {
        end = DateTime(end.year, end.month, end.day, 23, 59, 59);
      }"""

content = content.replace(old_metrics, new_metrics)

# Fix for getParetoAnalysis
old_pareto = """      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();"""

new_pareto = """      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      var end = endDate ?? DateTime.now();
      if (endDate != null) {
        end = DateTime(end.year, end.month, end.day, 23, 59, 59);
      }"""

content = content.replace(old_pareto, new_pareto)

# Fix for getCostAnalysis
old_cost = """      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final end = endDate ?? DateTime.now();"""

new_cost = """      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      var end = endDate ?? DateTime.now();
      if (endDate != null) {
        end = DateTime(end.year, end.month, end.day, 23, 59, 59);
      }"""

content = content.replace(old_cost, new_cost)

with codecs.open('lib/features/analytics/analytics_provider.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated endDate logic")
