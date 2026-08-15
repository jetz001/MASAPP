# -*- coding: utf-8 -*-
import codecs

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

old_kpi = """class _KPICards extends StatelessWidget {
  final MaintenanceMetrics metrics;

  const _KPICards({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _KPICard(
          label: 'MTBF',
          value: '${metrics.mtbf.toStringAsFixed(0)}h',
          subtitle: 'Mean Time Between Failures',
          tooltip: 'Mean Time Between Failures\\n\\nสูตรคำนวณ:\\nเวลาเดินเครื่องทั้งหมด (Total Uptime)\\n÷ จำนวนครั้งที่เครื่องเสีย (Breakdown Count)',
          color: Colors.blue.shade600,
          icon: Icons.timer_outlined,
        ),
        _KPICard(
          label: 'MTTR',
          value: '${metrics.mttr.toStringAsFixed(1)}h',
          subtitle: 'Mean Time To Repair',
          tooltip: 'Mean Time To Repair\\n\\nสูตรคำนวณ:\\nเวลาที่ใช้ซ่อมทั้งหมด (Total Downtime)\\n÷ จำนวนครั้งที่เครื่องเสีย (Breakdown Count)',
          color: Colors.orange.shade600,
          icon: Icons.build_circle_outlined,
        ),
        _KPICard(
          label: 'OEE',
          value: '${metrics.oee.toStringAsFixed(1)}%',
          subtitle: 'Overall Equipment Effectiveness',
          tooltip: 'Overall Equipment Effectiveness\\n\\nสูตรคำนวณ (อย่างง่าย):\\nAvailability × Performance × Quality\\n(ในระบบตอนนี้ใช้ Availability อย่างเดียวชั่วคราว)',
          color: Colors.green.shade600,
          icon: Icons.trending_up,
        ),
        _KPICard(
          label: 'Availability',
          value: '${(metrics.availability * 100).toStringAsFixed(1)}%',
          subtitle: 'Equipment Availability',
          tooltip: 'Equipment Availability\\n\\nสูตรคำนวณ:\\nเวลาเดินเครื่อง (Uptime)\\n÷ (เวลาเดินเครื่อง + เวลาหยุดเครื่อง)',
          color: Colors.purple.shade600,
          icon: Icons.check_circle_outline,
        ),
      ],
    );
  }
}"""

new_kpi = """class _KPICards extends StatelessWidget {
  final MaintenanceMetrics metrics;

  const _KPICards({required this.metrics});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.8,
      children: [
        _KPICard(
          label: 'MTBF',
          value: '${metrics.mtbf.toStringAsFixed(0)}h',
          subtitle: 'Mean Time Between Failures',
          tooltip: 'Mean Time Between Failures\\n\\nสูตรคำนวณ:\\nเวลาเดินเครื่องทั้งหมด (Total Uptime)\\n÷ จำนวนครั้งที่เครื่องเสีย (Breakdown Count)',
          color: Colors.blue.shade600,
          icon: Icons.timer_outlined,
        ),
        _KPICard(
          label: 'MTTR',
          value: '${metrics.mttr.toStringAsFixed(1)}h',
          subtitle: 'Mean Time To Repair',
          tooltip: 'Mean Time To Repair\\n\\nสูตรคำนวณ:\\nเวลาที่ใช้ซ่อมทั้งหมด (Total Downtime)\\n÷ จำนวนครั้งที่เครื่องเสีย (Breakdown Count)',
          color: Colors.orange.shade600,
          icon: Icons.build_circle_outlined,
        ),
        _KPICard(
          label: 'OEE',
          value: '${metrics.oee.toStringAsFixed(1)}%',
          subtitle: 'Overall Equipment Effectiveness',
          tooltip: 'Overall Equipment Effectiveness\\n\\nสูตรคำนวณ:\\nAvailability × Performance × Quality',
          color: Colors.green.shade600,
          icon: Icons.trending_up,
        ),
        _KPICard(
          label: 'Availability',
          value: '${(metrics.availability * 100).toStringAsFixed(1)}%',
          subtitle: 'Equipment Availability',
          tooltip: 'Equipment Availability\\n\\nสูตรคำนวณ:\\nเวลาเดินเครื่อง (Uptime)\\n÷ (เวลาเดินเครื่อง + เวลาหยุดเครื่อง)',
          color: Colors.purple.shade600,
          icon: Icons.check_circle_outline,
        ),
        _KPICard(
          label: 'Performance',
          value: '${(metrics.performance * 100).toStringAsFixed(1)}%',
          subtitle: 'Production Performance',
          tooltip: 'Performance\\n\\nสูตรคำนวณ:\\nยอดผลิตจริง (Actual Production)\\n÷ ยอดเป้าหมาย (Target Production)',
          color: Colors.teal.shade600,
          icon: Icons.speed,
        ),
        _KPICard(
          label: 'Quality',
          value: '${(metrics.quality * 100).toStringAsFixed(1)}%',
          subtitle: 'Production Quality',
          tooltip: 'Quality\\n\\nสูตรคำนวณ:\\nยอดของดี (Good Production)\\n÷ ยอดผลิตทั้งหมด (Actual Production)',
          color: Colors.indigo.shade600,
          icon: Icons.verified_user_outlined,
        ),
      ],
    );
  }
}"""

content = content.replace(old_kpi, new_kpi)

with codecs.open('lib/features/analytics/analytics_dashboard_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print("Updated KPI Cards UI")
