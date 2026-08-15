import codecs
import re

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = re.sub(
    r'class _KPICard extends StatelessWidget \{\s*final String label;\s*final String value;\s*final String subtitle;\s*final Color color;\s*final IconData icon;\s*const _KPICard\(\{\s*required this\.label,\s*required this\.value,\s*required this\.subtitle,\s*required this\.color,\s*required this\.icon,\s*\}\);',
    r'''class _KPICard extends StatelessWidget {
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
  });''',
    content
)

old_ui = r'''            Row(
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
            ),'''
new_ui = r'''            Row(
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
            ),'''

if old_ui in content:
    content = content.replace(old_ui, new_ui)
else:
    print("Warning: old UI not found")

# Update callers
c1 = r"""        _KPICard(
          label: 'MTBF',
          value: '${metrics.mtbf.toStringAsFixed(0)}h',
          subtitle: 'Mean Time Between Failures',
          color: Colors.blue.shade600,
          icon: Icons.timer_outlined,
        ),"""
n1 = r"""        _KPICard(
          label: 'MTBF',
          value: '${metrics.mtbf.toStringAsFixed(0)}h',
          subtitle: 'Mean Time Between Failures',
          tooltip: 'Mean Time Between Failures\n\nสูตรคำนวณ:\nเวลาเดินเครื่องทั้งหมด (Total Uptime)\n? จำนวนครั้งที่เครื่องเสีย (Breakdown Count)',
          color: Colors.blue.shade600,
          icon: Icons.timer_outlined,
        ),"""
if c1 in content: content = content.replace(c1, n1)

c2 = r"""        _KPICard(
          label: 'MTTR',
          value: '${metrics.mttr.toStringAsFixed(1)}h',
          subtitle: 'Mean Time To Repair',
          color: Colors.orange.shade600,
          icon: Icons.build_circle_outlined,
        ),"""
n2 = r"""        _KPICard(
          label: 'MTTR',
          value: '${metrics.mttr.toStringAsFixed(1)}h',
          subtitle: 'Mean Time To Repair',
          tooltip: 'Mean Time To Repair\n\nสูตรคำนวณ:\nเวลาที่ใช้ซ่อมทั้งหมด (Total Downtime)\n? จำนวนครั้งที่เครื่องเสีย (Breakdown Count)',
          color: Colors.orange.shade600,
          icon: Icons.build_circle_outlined,
        ),"""
if c2 in content: content = content.replace(c2, n2)

c3 = r"""        _KPICard(
          label: 'OEE',
          value: '${metrics.oee.toStringAsFixed(1)}%',
          subtitle: 'Overall Equipment Effectiveness',
          color: Colors.green.shade600,
          icon: Icons.trending_up,
        ),"""
n3 = r"""        _KPICard(
          label: 'OEE',
          value: '${metrics.oee.toStringAsFixed(1)}%',
          subtitle: 'Overall Equipment Effectiveness',
          tooltip: 'Overall Equipment Effectiveness\n\nสูตรคำนวณ (อย่างง่าย):\nAvailability ? Performance ? Quality\n(ในระบบตอนนี้ใช้ Availability อย่างเดียวชั่วคราว)',
          color: Colors.green.shade600,
          icon: Icons.trending_up,
        ),"""
if c3 in content: content = content.replace(c3, n3)

c4 = r"""        _KPICard(
          label: 'Availability',
          value: '${(metrics.availability * 100).toStringAsFixed(1)}%',
          subtitle: 'Equipment Availability',
          color: Colors.purple.shade600,
          icon: Icons.check_circle_outline,
        ),"""
n4 = r"""        _KPICard(
          label: 'Availability',
          value: '${(metrics.availability * 100).toStringAsFixed(1)}%',
          subtitle: 'Equipment Availability',
          tooltip: 'Equipment Availability\n\nสูตรคำนวณ:\nเวลาเดินเครื่อง (Uptime)\n? (เวลาเดินเครื่อง + เวลาหยุดเครื่อง)',
          color: Colors.purple.shade600,
          icon: Icons.check_circle_outline,
        ),"""
if c4 in content: content = content.replace(c4, n4)

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated all KPIs")
