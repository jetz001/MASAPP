import codecs

with codecs.open('lib/features/analytics/analytics_provider.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_provider = "final analyticsDateRangeProvider = StateProvider<DateTimeRange?>((ref) => null);"

new_provider = """final analyticsDateRangeProvider = StateProvider<DateTimeRange?>((ref) {
  final now = DateTime.now();
  return DateTimeRange(
    start: DateTime(now.year, 1, 1),
    end: now,
  );
});"""

content = content.replace(old_provider, new_provider)

with codecs.open('lib/features/analytics/analytics_provider.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated default date range")
