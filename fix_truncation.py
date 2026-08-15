import codecs
import re

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix Tooltip string wrapping
old_tooltip = r"""                  return BarTooltipItem(
                    '${cat.category}\n',
                    TextStyle("""
new_tooltip = r"""                  String catName = cat.category;
                  if (catName.contains('(')) {
                    catName = catName.replaceFirst(' (', '\n(');
                  }
                  return BarTooltipItem(
                    '$catName\n',
                    TextStyle("""
content = content.replace(old_tooltip, new_tooltip)


# Fix the truncation at 20 chars
# Find the line: category.category.length > 20
old_text_trunc = r"""                        child: Text(
                          category.category.length > 20
                              ? '${category.category.substring(0, 20)}...'
                              : category.category,"""
new_text_trunc = r"""                        child: Text(
                          category.category.length > 30 
                              ? category.category.replaceFirst(' (', '\n(')
                              : category.category,"""

if old_text_trunc in content:
    content = content.replace(old_text_trunc, new_text_trunc)
else:
    # Let's do a more robust regex if the exact string wasn't found
    pattern = r'category\.category\.length > 20\s*\?\s*\'\$\{category\.category\.substring\(0, 20\)\}\.\.\.\'\s*:\s*category\.category,'
    new_text = "category.category.length > 30 ? category.category.replaceFirst(' (', '\\n(') : category.category,"
    content = re.sub(pattern, new_text, content)

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('Fixed truncation!')
