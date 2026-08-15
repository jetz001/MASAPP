import codecs

with codecs.open('lib/features/analytics/analytics_provider.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace the broken print statement
content = content.replace(
    "      print('ERROR in getParetoAnalysis: \n');",
    "      print('ERROR in getParetoAnalysis: $e, $stack');"
)

with codecs.open('lib/features/analytics/analytics_provider.dart', 'w', encoding='utf-8') as f:
    f.write(content)
