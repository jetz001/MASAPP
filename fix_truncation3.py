import codecs

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad_label_str1 = """                        child: Text(
                          category.category.length > 30 ? category.category.replaceFirst(' (', '
(') : category.category,"""

bad_label_str2 = """                        child: Text(
                          category.category.length > 30 
                              ? category.category.replaceFirst(' (', '
(')
                              : category.category,"""

good_label_str = """                        child: Text(
                          category.category.length > 30 ? category.category.replaceFirst(' (', '\\n(') : category.category,"""

if bad_label_str1 in content:
    content = content.replace(bad_label_str1, good_label_str)
elif bad_label_str2 in content:
    content = content.replace(bad_label_str2, good_label_str)
else:
    # Let's just blindly replace the broken literal using simple string split/replace if possible
    import re
    content = re.sub(r"replaceFirst\(' \(', '\n\('\)", r"replaceFirst(' (', '\\n(')", content)


# Let's fix the Tooltip too, since it might be broken as well
bad_tooltip = """                  return BarTooltipItem(
                    '$catName
',"""
good_tooltip = """                  return BarTooltipItem(
                    '$catName\\n',"""
if bad_tooltip in content:
    content = content.replace(bad_tooltip, good_tooltip)

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('Fixed dart strings completely!')
