import codecs

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Update _KPICard fields
old_kpi_fields = """class _KPICard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  const _KPICard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });"""

new_kpi_fields = """class _KPICard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final String tooltip;
  final Color color;
  final IconData icon;

  const _KPICard({
    required this.label,
    required this.value,
    required this.subtitle,
    required this.tooltip,
    required this.color,
    required this.icon,
  });"""

content = content.replace(old_kpi_fields, new_kpi_fields)

# Update _KPICard UI
old_kpi_ui = """            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Icon(icon, color: color.withAlpha(150), size: 24),
              ],
            ),"""

new_kpi_ui = """            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Tooltip(
                      message: tooltip,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      textStyle: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade800 : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                      ),
                      child: const Icon(Icons.help_outline, size: 16, color: Colors.grey),
                    ),
                  ],
                ),
                Icon(icon, color: color.withAlpha(150), size: 24),
              ],
            ),"""

content = content.replace(old_kpi_ui, new_kpi_ui)

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated _KPICard definition")
