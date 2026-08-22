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
import '../analytics/analytics_provider.dart';
import '../analytics/analytics_dashboard_screen.dart';
import 'widgets/oee_excel_import_dialog.dart';
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
    try {
      final machines = await DbHelper.queryOne(
        "SELECT COUNT(*) as c FROM machines WHERE is_active = 1 OR is_active IS NULL OR is_active = '1' OR is_active = 'true'",
      );
      final pendingReview = await DbHelper.queryOne(
        "SELECT COUNT(*) as c FROM work_orders WHERE status IN ('pending', 'pending_review')",
      );
      final inProgress = await DbHelper.queryOne(
        "SELECT COUNT(*) as c FROM work_orders WHERE status IN ('in_progress', 'approved')",
      );
      final pendingPermit = await DbHelper.queryOne(
        "SELECT COUNT(*) as c FROM work_permits WHERE status IN ('pending', 'draft', 'submitted')",
      );
      final lowStock = await DbHelper.queryOne(
        '''SELECT COUNT(*) as c FROM spare_parts_inventory i
           JOIN spare_parts p ON p.part_id = i.part_id
           WHERE CAST(i.quantity_on_hand AS REAL) <= CAST(COALESCE(p.reorder_level, 0) AS REAL)''',
      );

      final recentWo = await DbHelper.query(
        '''SELECT w.wo_no, w.title, w.status, w.priority, w.created_at,
                  COALESCE(m.machine_no, '-') as machine_no,
                  COALESCE(u.full_name, 'ยังไม่ระบุ') as technician
           FROM work_orders w
           LEFT JOIN machines m ON m.machine_id = w.machine_id
           LEFT JOIN users u ON u.user_id = w.assigned_to
           ORDER BY w.created_at DESC LIMIT 6''',
      );

      // Load real machine statuses
      final statusRows = await DbHelper.query(
        "SELECT COALESCE(status, 'normal') as status, COUNT(*) as c "
        "FROM machines "
        "WHERE is_active = 1 OR is_active IS NULL OR is_active = '1' OR is_active = 'true' "
        "GROUP BY status",
      );
      final statusMap = <String, int>{
        'normal': 0,
        'breakdown': 0,
        'pm': 0,
        'offline': 0,
      };
      for (final row in statusRows) {
        final st = row['status']?.toString().toLowerCase() ?? 'normal';
        final count = (row['c'] as num?)?.toInt() ?? 0;
        statusMap[st] = count;
      }

      // Real WO trend (last 7 days values)
      final now = DateTime.now();
      final List<double> trendValues = List.filled(7, 0.0);

      try {
        final trendRows = await DbHelper.query(
          '''SELECT substr(created_at, 1, 10) as d, COUNT(*) as c 
             FROM work_orders 
             GROUP BY substr(created_at, 1, 10)''',
        );

        for (int i = 0; i < 7; i++) {
          final date = now.subtract(Duration(days: 6 - i));
          final dateStr = DateFormat('yyyy-MM-dd').format(date);

          final match = trendRows.firstWhere(
            (r) => r['d']?.toString() == dateStr,
            orElse: () => <String, dynamic>{},
          );
          if (match.isNotEmpty) {
            trendValues[i] = ((match['c'] as num?)?.toDouble()) ?? 0.0;
          }
        }
      } catch (_) {}

      return DashboardStats(
        totalMachines: (machines?['c'] as num?)?.toInt() ?? 0,
        pendingReview: (pendingReview?['c'] as num?)?.toInt() ?? 0,
        inProgress: (inProgress?['c'] as num?)?.toInt() ?? 0,
        pendingPermits: (pendingPermit?['c'] as num?)?.toInt() ?? 0,
        lowStockParts: (lowStock?['c'] as num?)?.toInt() ?? 0,
        recentWorkOrders: recentWo,
        woTrendValues: trendValues,
        machineStatuses: statusMap,
      );
    } catch (e) {
      debugPrint('[Dashboard] Error loading stats: $e');
      return const DashboardStats(
        totalMachines: 0,
        pendingReview: 0,
        inProgress: 0,
        pendingPermits: 0,
        lowStockParts: 0,
        recentWorkOrders: [],
        woTrendValues: [0, 0, 0, 0, 0, 0, 0],
        machineStatuses: {'normal': 0, 'breakdown': 0, 'pm': 0, 'offline': 0},
      );
    }
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
    final dateRange = ref.watch(analyticsDateRangeProvider);
    final metricsAsync = ref.watch(maintenanceMetricsProvider);
    final paretoAsync = ref.watch(paretoAnalysisProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with Greeting & Date Range Selector
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('แดชบอร์ดบริหารจัดการโรงงาน',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
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
              // Date Range Picker Button for KPIs
              FilledButton.tonalIcon(
                icon: const Icon(Icons.date_range_rounded, size: 16),
                label: Text(
                  dateRange == null
                      ? '30 วันล่าสุด (Default)'
                      : '${dateRange.start.day}/${dateRange.start.month}/${dateRange.start.year} - ${dateRange.end.day}/${dateRange.end.month}/${dateRange.end.year}',
                  style: const TextStyle(fontSize: 12.5),
                ),
                onPressed: () async {
                  final picked = await showDateRangePicker(
                    context: context,
                    locale: const Locale('th', 'TH'),
                    initialDateRange: dateRange ??
                        DateTimeRange(
                          start: DateTime.now().subtract(const Duration(days: 30)),
                          end: DateTime.now(),
                        ),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    ref.read(analyticsDateRangeProvider.notifier).state = picked;
                  }
                },
              ),
              const SizedBox(width: AppSpacing.md),
              IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedRefresh,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onPressed: () {
                  ref.invalidate(dashboardStatsProvider);
                  ref.invalidate(maintenanceMetricsProvider);
                  ref.invalidate(paretoAnalysisProvider);
                  ref.invalidate(oeeTrendProvider);
                },
                tooltip: 'รีเฟรชข้อมูลทั้งหมด',
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // 1. Maintenance Status Row
          statsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => Text('Error loading stats: $e'),
            data: (stats) => Row(
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
          ),

          const SizedBox(height: AppSpacing.xxl),

          // 2. Plant Reliability & OEE Section Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.speed_rounded, color: Colors.green, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'ตัวชี้วัดประสิทธิภาพโรงงาน & OEE (Plant Reliability & OEE KPIs)',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              FilledButton.icon(
                icon: const Icon(Icons.hub_rounded, size: 16),
                label: const Text('นำเข้ายอดผลิต / เชื่อมต่อ SQL (OEE)', style: TextStyle(fontSize: 12.5)),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: () => OeeExcelImportDialog.show(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // 3. 6 KPI Cards (MTBF, MTTR, OEE, Availability, Performance, Quality)
          metricsAsync.when(
            data: (metrics) => KPICards(metrics: metrics),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, _) => Text('คำนวณ KPI ล้มเหลว: $err'),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // 4. Failure Analysis (Pareto) & Machine Status Distribution
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pareto Failure Analysis
              Expanded(
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(Icons.bar_chart_rounded, color: Colors.redAccent, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              'วิเคราะห์สาเหตุเครื่องเสีย (Pareto Analysis)',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isDense: true,
                            value: ref.watch(paretoGroupByProvider),
                            items: const [
                              DropdownMenuItem(value: 'failureType', child: Text('หมวดหมู่อาการเสีย', style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: 'causeCategory', child: Text('สาเหตุหลัก (Root Cause)', style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: 'machine', child: Text('เครื่องจักร (Machine)', style: TextStyle(fontSize: 12))),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                ref.read(paretoGroupByProvider.notifier).state = val;
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    paretoAsync.when(
                      data: (pareto) => ParetoChart(analysis: pareto),
                      loading: () => const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator())),
                      error: (err, _) => Text('Error loading Pareto: $err'),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: AppSpacing.lg),

              // Machine Status Distribution
              Expanded(
                flex: 3,
                child: statsAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                  data: (stats) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(Icons.pie_chart_outline_rounded, color: Colors.blue, size: 18),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'สถานะเครื่องจักร',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _MachineStatusCard(stats: stats),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: AppSpacing.xxl),

          // 5. WO 7-Day Trend Chart
          statsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (stats) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _WoTrendCard(values: stats.woTrendValues),
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
    final now = DateTime.now();
    final dayNames = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
    final days = List.generate(7, (i) {
      final d = now.subtract(Duration(days: 6 - i));
      return dayNames[d.weekday - 1];
    });
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('ใบแจ้งซ่อม 7 วันล่าสุด',
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
                 Text('ใบแจ้งซ่อมล่าสุด', style: AppTextStyles.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => context.push('/work-orders'),
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
              child: Text('ไม่มีข้อมูลใบแจ้งซ่อม'),
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
                  InkWell(
                    onTap: () => context.push('/work-orders'),
                    child: Padding(
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

