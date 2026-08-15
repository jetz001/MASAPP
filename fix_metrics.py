import codecs
import re

with codecs.open('lib/features/analytics/analytics_models.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_metrics_class = r"""class MaintenanceMetrics {
  final double mtbf;
  final double mttr;
  final double oee;
  final double availability;

  const MaintenanceMetrics({
    required this.mtbf,
    required this.mttr,
    required this.oee,
    required this.availability,
  });"""

new_metrics_class = r"""class MaintenanceMetrics {
  final double mtbf;
  final double mttr;
  final double oee;
  final double availability;
  final double performance;
  final double quality;

  const MaintenanceMetrics({
    required this.mtbf,
    required this.mttr,
    required this.oee,
    required this.availability,
    required this.performance,
    required this.quality,
  });"""

content = content.replace(old_metrics_class, new_metrics_class)

old_oee = r"""  static double calculateOEE(double availability) {
    // Simplified OEE (Availability only for now)
    return availability * 100;
  }"""

new_oee = r"""  static double calculateOEE(double availability, double performance, double quality) {
    return availability * performance * quality * 100;
  }"""

content = content.replace(old_oee, new_oee)

with codecs.open('lib/features/analytics/analytics_models.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated analytics_models.dart")
