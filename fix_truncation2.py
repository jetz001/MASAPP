import codecs

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad_tooltip_str = """                  String catName = cat.category;
                  if (catName.contains('(')) {
                    catName = catName.replaceFirst(' (', '
(');
                  }
                  return BarTooltipItem(
                    '$catName
',
                    TextStyle("""

good_tooltip_str = """                  String catName = cat.category;
                  if (catName.contains('(')) {
                    catName = catName.replaceFirst(' (', '\\n(');
                  }
                  return BarTooltipItem(
                    '$catName\\n',
                    TextStyle("""

if bad_tooltip_str in content:
    content = content.replace(bad_tooltip_str, good_tooltip_str)

bad_label_str = """                        child: Text(
                          category.category.length > 30 ? category.category.replaceFirst(' (', '
(') : category.category,"""

good_label_str = """                        child: Text(
                          category.category.length > 30 ? category.category.replaceFirst(' (', '\\n(') : category.category,"""

if bad_label_str in content:
    content = content.replace(bad_label_str, good_label_str)

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('Fixed dart strings!')
