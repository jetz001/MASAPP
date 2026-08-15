# -*- coding: utf-8 -*-
import codecs
import re

with codecs.open('lib/features/analytics/analytics_models.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = re.sub(
    r'final double availability; // Equipment availability \(%\)',
    r'final double availability; // Equipment availability (%)\n  final double performance;\n  final double quality;',
    content
)

content = re.sub(
    r'required this\.availability,',
    r'required this.availability,\n    this.performance = 1.0,\n    this.quality = 1.0,',
    content
)

content = re.sub(
    r'static double calculateOEE\(double availability\) \{[^\}]*\}',
    r'''static double calculateOEE(double availability, double performance, double quality) {
    return availability * performance * quality * 100;
  }''',
    content
)

with codecs.open('lib/features/analytics/analytics_models.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Fixed models properly")
