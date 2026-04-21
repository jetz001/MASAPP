import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/database/db_helper.dart';
import '../../features/auth/auth_provider.dart';
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data Provider
// ─────────────────────────────────────────────────────────────────────────────

final dashboardStatsProvider = FutureProvider<DashboardStats>((ref) async {
  return DashboardStats.load();
});

class DashboardStats {
  final int totalMachines;
  final int pendingReview;
  final int inProgress;
  final int pendingPermits;
  final int lowStockParts;
  final List<Map<String, dynamic>> recentWorkOrders;
  final List<double> woTrendValues;
  final Map<String, int> machineStatuses;

  const DashboardStats({
    required this.totalMachines,
    required this.pendingReview,
    required this.inProgress,
    required this.pendingPermits,
    required this.lowStockParts,
    required this.recentWorkOrders,
    required this.woTrendValues,
    required this.machineStatuses,
  });

  static Future<DashboardStats> load() async {
    final machines = await DbHelper.queryOne(
        'SELECT COUNT(*) as c FROM machines WHERE is_active=1');
    final pendingReview = await DbHelper.queryOne(
        "SELECT COUNT(*) as c FROM work_orders WHERE status = 'pending_review'");
    final inProgress = await DbHelper.queryOne(
        "SELECT COUNT(*) as c FROM work_orders WHERE status = 'in_progress'");
    final pendingPermit = await DbHelper.queryOne(
        "SELECT COUNT(*) as c FROM work_permits WHERE status='pending'");
    final lowStock = await DbHelper.queryOne(
        '''SELECT COUNT(*) as c FROM spare_parts_inventory i
           JOIN spare_parts p ON p.part_id = i.part_id
           WHERE i.quantity_on_hand <= p.reorder_level''');

    final recentWo = await DbHelper.query(
      '''SELECT w.wo_no, w.title, w.status, w.priority, w.created_at,
                m.machine_no, u.full_name as technician
         FROM work_orders w
         JOIN machines m ON m.machine_id = w.machine_id
         LEFT JOIN users u ON u.user_id = w.assigned_to
         ORDER BY w.created_at DESC LIMIT 6''',
    );

    // Load real machine statuses
    final statusRows = await DbHelper.query(
      'SELECT status, COUNT(*) as c FROM machines WHERE is_active=1 GROUP BY status'
    );
    final statusMap = <String, int>{
      'normal': 0,
      'breakdown': 0,
      'pm': 0,
      'offline': 0,
    };
    for (final row in statusRows) {
      statusMap[row['status'] as String? ?? 'normal'] = row['c'] as int? ?? 0;
    }

    // Simulated WO trend (last 7 days values)
    final trendValues = List.generate(7, (i) => (2 + (i * 1.3) % 5).toDouble());

    return DashboardStats(
      totalMachines: machines?['c'] as int? ?? 0,
      pendingReview: pendingReview?['c'] as int? ?? 0,
      inProgress: inProgress?['c'] as int? ?? 0,
      pendingPermits: pendingPermit?['c'] as int? ?? 0,
      lowStockParts: lowStock?['c'] as int? ?? 0,
      recentWorkOrders: recentWo,
      woTrendValues: trendValues,
      machineStatuses: statusMap,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dashboard Screen
// ─────────────────────────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final statsAsync = ref.watch(dashboardStatsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('แดชบอร์ด', style: Theme.of(context).textTheme.headlineLarge),
                  const SizedBox(height: 4),
                  Text(
                    'ยินดีต้อนรับ, ${user?.fullName ?? ''} · ${_greeting()}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                DateFormat('EEEE d MMMM yyyy', 'th').format(DateTime.now()),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(width: AppSpacing.md),
              IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedRefresh,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onPressed: () => ref.invalidate(dashboardStatsProvider),
                tooltip: 'รีเฟรช',
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // KPI Cards
          statsAsync.when(
            loading: () => const Center(
                child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            )),
            error: (e, _) => Text('Error: $e'),
            data: (stats) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // KPI row
                Row(
                  children: [
                    _KpiCard(
                      label: 'เครื่องจักรทั้งหมด',
                      value: '${stats.totalMachines}',
                      unit: 'เครื่อง',
                      icon: HugeIcons.strokeRoundedFactory,
                      color: AppColors.primary,
                      onTap: () => context.go('/machine-registry'),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    _KpiCard(
                      label: 'งานที่รอนายตรวจ',
                      value: '${stats.pendingReview}',
                      unit: 'ใบ',
                      icon: HugeIcons.strokeRoundedTask01,
                      color: AppColors.warning,
                      onTap: () => context.go('/work-orders'),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    _KpiCard(
                      label: 'กำลังดำเนินการ',
                      value: '${stats.inProgress}',
                      unit: 'รายการ',
                      icon: HugeIcons.strokeRoundedSettings01,
                      color: AppColors.primary,
                      onTap: () => context.go('/pm-am'),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    _KpiCard(
                      label: 'ใบอนุญาตรออนุมัติ',
                      value: '${stats.pendingPermits}',
                      unit: 'ใบ',
                      icon: HugeIcons.strokeRoundedAgreement01,
                      color: AppColors.info,
                      onTap: () => context.go('/work-permit'),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    _KpiCard(
                      label: 'สต็อกต่ำกว่ากำหนด',
                      value: '${stats.lowStockParts}',
                      unit: 'รายการ',
                      icon: HugeIcons.strokeRoundedArchive02,
                      color: AppColors.severityHigh,
                      onTap: () => context.go('/spare-parts'),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.xxl),

                // Charts + Recent WOs
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // WO Trend Chart
                    Expanded(
                      flex: 5,
                      child: _WoTrendCard(values: stats.woTrendValues),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    // Machine Status Distribution
                    Expanded(
                      flex: 3,
                      child: _MachineStatusCard(
                        stats: stats,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.xxl),

                // Recent Work Orders
                _RecentWorkOrdersCard(orders: stats.recentWorkOrders),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'สวัสดีตอนเช้า';
    if (hour < 17) return 'สวัสดีตอนบ่าย';
    return 'สวัสดีตอนเย็น';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KPI Card
// ─────────────────────────────────────────────────────────────────────────────

class _KpiCard extends StatefulWidget {
  final String label;
  final String value;
  final String unit;
  final dynamic icon;
  final Color color;
  final VoidCallback? onTap;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  State<_KpiCard> createState() => _KpiCardState();
}

class _KpiCardState extends State<_KpiCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 160, // Fixed height to prevent unbounded constraint error
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: _hovered
                    ? widget.color.withValues(alpha: 0.5)
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
              boxShadow: _hovered
                  ? [
                      BoxShadow(
                        color: widget.color.withValues(alpha: 0.15),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ]
                  : [],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Stack(
                children: [
                  // Subtle background gradient for hover
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 300),
                    top: _hovered ? -20 : -100,
                    right: _hovered ? -20 : -100,
                    child: Container(
                      width: 150,
                      height: 150,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            widget.color.withValues(alpha: 0.08),
                            widget.color.withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: widget.color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(AppRadius.md),
                              ),
                              child: HugeIcon(
                                  icon: widget.icon, color: widget.color, size: 22),
                            ),
                            const Spacer(),
                            if (widget.onTap != null)
                              HugeIcon(
                                icon: HugeIcons.strokeRoundedArrowUpRight01,
                                size: 16,
                                color: _hovered ? widget.color : Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                              ),
                          ],
                        ),
                        const Spacer(),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              widget.value,
                              style: AppTextStyles.headlineLarge.copyWith(
                                color: widget.color,
                                fontWeight: FontWeight.w800,
                                fontSize: 32,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Text(widget.unit,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      )),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(widget.label,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WO Trend Bar Chart Card
// ─────────────────────────────────────────────────────────────────────────────

class _WoTrendCard extends StatelessWidget {
  final List<double> values;
  const _WoTrendCard({required this.values});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('ใบสั่งงาน 7 วันล่าสุด',
                    style: AppTextStyles.titleMedium),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Text('Work Orders',
                      style: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(color: Theme.of(context).colorScheme.primary)),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  barGroups: List.generate(values.length, (i) {
                    return BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: values[i],
                          color: Theme.of(context).colorScheme.primary,
                          width: 14,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    );
                  }),
                  gridData: FlGridData(
                    horizontalInterval: 2,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: theme.colorScheme.outline.withValues(alpha: 0.3),
                      strokeWidth: 1,
                    ),
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 2,
                        reservedSize: 28,
                        getTitlesWidget: (v, _) => Text(
                          '${v.toInt()}',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) => Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            days[v.toInt() % 7],
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                      ),
                    ),
                    rightTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles:
                        const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => theme.colorScheme.surface,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                        '${rod.toY.toInt()} ใบ',
                        Theme.of(context).textTheme.labelMedium!,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Machine Status Donut Card
// ─────────────────────────────────────────────────────────────────────────────

class _MachineStatusCard extends StatefulWidget {
  final DashboardStats stats;
  const _MachineStatusCard({required this.stats});

  @override
  State<_MachineStatusCard> createState() => _MachineStatusCardState();
}

class _MachineStatusCardState extends State<_MachineStatusCard> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final s = widget.stats;
    
    final sections = [
      PieChartSectionData(
        value: s.machineStatuses['normal']?.toDouble() ?? 0,
        color: AppColors.machineNormal,
        title: 'ปกติ',
        radius: _touched == 0 ? 60 : 52,
        titleStyle: AppTextStyles.labelSmall
            .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
        showTitle: (s.machineStatuses['normal'] ?? 0) > 0,
      ),
      PieChartSectionData(
        value: s.machineStatuses['breakdown']?.toDouble() ?? 0,
        color: AppColors.machineBreakdown,
        title: 'เสีย',
        radius: _touched == 1 ? 60 : 52,
        titleStyle: AppTextStyles.labelSmall
            .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
        showTitle: (s.machineStatuses['breakdown'] ?? 0) > 0,
      ),
      PieChartSectionData(
        value: s.machineStatuses['pm']?.toDouble() ?? 0,
        color: AppColors.machinePM,
        title: 'PM',
        radius: _touched == 2 ? 60 : 52,
        titleStyle: AppTextStyles.labelSmall
            .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
        showTitle: (s.machineStatuses['pm'] ?? 0) > 0,
      ),
      PieChartSectionData(
        value: s.machineStatuses['offline']?.toDouble() ?? 0,
        color: AppColors.machineOffline,
        title: 'หยุด',
        radius: _touched == 3 ? 60 : 52,
        titleStyle: AppTextStyles.labelSmall
            .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
        showTitle: (s.machineStatuses['offline'] ?? 0) > 0,
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('สถานะเครื่องจักร', style: AppTextStyles.titleMedium),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: 180,
              child: PieChart(
                PieChartData(
                  sections: sections,
                  centerSpaceRadius: 40,
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      setState(() {
                        _touched =
                            response?.touchedSection?.touchedSectionIndex ??
                                -1;
                      });
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _Legend('ปกติ', AppColors.machineNormal),
                _Legend('เสีย', AppColors.machineBreakdown),
                _Legend('PM', AppColors.machinePM),
                _Legend('หยุด', AppColors.machineOffline),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final Color color;
  const _Legend(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent Work Orders Card
// ─────────────────────────────────────────────────────────────────────────────

class _RecentWorkOrdersCard extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  const _RecentWorkOrdersCard({required this.orders});

  Color _statusColor(String? status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'in_progress':
        return AppColors.primary;
      case 'pending':
        return AppColors.warning;
      case 'cancelled':
        return AppColors.machineOffline;
      default:
        return AppColors.textSecondary;
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'completed':
        return 'เสร็จสิ้น';
      case 'in_progress':
        return 'กำลังซ่อม';
      case 'pending':
        return 'รอดำเนินการ';
      case 'approved':
        return 'อนุมัติแล้ว';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return status ?? '-';
    }
  }

  Color _priorityColor(String? p) {
    switch (p) {
      case 'urgent':
        return AppColors.error;
      case 'high':
        return AppColors.severityHigh;
      case 'low':
        return AppColors.severityLow;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.md),
            child: Row(
              children: [
                HugeIcon(icon: HugeIcons.strokeRoundedTask01,
                     size: 18, color: Theme.of(context).colorScheme.primary),
                 const SizedBox(width: AppSpacing.sm),
                 Text('ใบสั่งงานล่าสุด', style: AppTextStyles.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () {},
                  icon: HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      size: 14,
                      color: Theme.of(context).colorScheme.primary),
                  label: const Text('ดูทั้งหมด'),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6)),
                ),
              ],
            ),
          ),
          Container(height: 1, color: Theme.of(context).colorScheme.outline),
          if (orders.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Text('ไม่มีข้อมูลใบสั่งงาน'),
            )
          else
            ...orders.map((o) {
              final status = o['status'] as String?;
              final priority = o['priority'] as String?;
              final createdAt = o['created_at'] as String?;
              DateTime? dt;
              try {
                dt = createdAt != null ? DateTime.parse(createdAt) : null;
              } catch (_) {}
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl, vertical: AppSpacing.md),
                    child: Row(
                      children: [
                        // Priority indicator
                        Container(
                          width: 4,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _priorityColor(priority),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        // WO info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                o['wo_no'] as String? ?? '-',
                                style: AppTextStyles.labelMedium.copyWith(
                                    color: Theme.of(context).colorScheme.primary),
                              ),
                              Text(
                                o['title'] as String? ?? '-',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        // Machine
                        Text(
                          o['machine_no'] as String? ?? '-',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xl),
                        // Technician
                        SizedBox(
                          width: 120,
                          child: Text(
                            o['technician'] as String? ?? 'ยังไม่มอบหมาย',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xl),
                        // Date
                        SizedBox(
                          width: 90,
                          child: Text(
                            dt != null
                                ? DateFormat('dd/MM/yy HH:mm').format(dt)
                                : '-',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(status)
                                .withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppRadius.full),
                            border: Border.all(
                              color: _statusColor(status)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            _statusLabel(status),
                            style: TextStyle(
                              fontSize: 11,
                              color: _statusColor(status),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                      height: 1,
                      color: Theme.of(context)
                          .colorScheme
                          .outline
                          .withValues(alpha: 0.3)),
                ],
              );
            }),
        ],
      ),
    );
  }
}
