# -*- coding: utf-8 -*-
import codecs

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_kpi = """                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Icon(icon, color: color.withAlpha(150), size: 24),"""

new_kpi = """                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    if (tooltip.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Tooltip(
                        message: tooltip,
                        textStyle: const TextStyle(fontSize: 14, color: Colors.white),
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.symmetric(horizontal: 20),
                        showDuration: const Duration(seconds: 5),
                        child: Icon(
                          Icons.help_outline,
                          size: 16,
                          color: color.withAlpha(150),
                        ),
                      ),
                    ],
                  ],
                ),
                Icon(icon, color: color.withAlpha(150), size: 24),"""

content = content.replace(old_kpi, new_kpi)

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Added tooltip icon to KPI card")
