# -*- coding: utf-8 -*-
import codecs
import re

with codecs.open('lib/features/analytics/analytics_provider.dart', 'r', encoding='utf-8') as f:
    content = f.read()

trend_method = """  /// Get OEE Trend analysis (last 30 days)
  Future<List<TrendDataPoint>> getOeeTrend({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final end = endDate ?? DateTime.now();
      final start = startDate ?? end.subtract(const Duration(days: 30));
      
      final results = await DbHelper.query(
        '''SELECT 
            date(recorded_date) as d,
            COALESCE(SUM(cumulative_hours), 0) as total_hrs,
            COALESCE(SUM(target_production), 0) as total_target,
            COALESCE(SUM(actual_production), 0) as total_actual,
            COALESCE(SUM(good_production), 0) as total_good
           FROM machine_running_hours
           WHERE recorded_date BETWEEN @start AND @end
           GROUP BY d
           ORDER BY d ASC''',
        params: {
          'start': start.toIso8601String(),
          'end': DateTime(end.year, end.month, end.day, 23, 59, 59).toIso8601String(),
        }
      );
      
      final trend = <TrendDataPoint>[];
      for (final row in results) {
        final dateStr = row['d'] as String;
        final date = DateTime.tryParse(dateStr) ?? DateTime.now();
        
        final hrs = (row['total_hrs'] as num?)?.toDouble() ?? 0;
        final target = (row['total_target'] as num?)?.toDouble() ?? 0;
        final actual = (row['total_actual'] as num?)?.toDouble() ?? 0;
        final good = (row['total_good'] as num?)?.toDouble() ?? 0;
        
        // Very basic mock calculation for daily OEE based on recorded hours
        // Availability
        final availability = hrs > 0 ? (hrs / (hrs + 1)) : 0.0; // Mock downtime
        // Performance
        final performance = target > 0 ? (actual / target) : (hrs > 0 ? 0.9 : 0.0);
        // Quality
        final quality = actual > 0 ? (good / actual) : (hrs > 0 ? 0.95 : 0.0);
        
        double oee = availability * performance * quality * 100;
        if (oee > 100) oee = 100;
        
        trend.add(TrendDataPoint(date: date, value: oee));
      }
      
      return trend;
    } catch (e) {
      return [];
    }
  }
"""

# Insert before '}' of AnalyticsService class
content = content.replace("class AnalyticsService {", "class AnalyticsService {\n" + trend_method, 1)

# Add the provider
provider_code = """
final oeeTrendProvider = FutureProvider((ref) async {
  final service = ref.watch(analyticsServiceProvider);
  final dateRange = ref.watch(analyticsDateRangeProvider);
  return await service.getOeeTrend(
    startDate: dateRange?.start,
    endDate: dateRange?.end,
  );
});
"""
content += provider_code

with codecs.open('lib/features/analytics/analytics_provider.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Added trend provider")
