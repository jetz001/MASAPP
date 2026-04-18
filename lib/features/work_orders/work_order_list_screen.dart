import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:empty_view/empty_view.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/app_utils.dart';
import '../../features/auth/auth_provider.dart';
import 'work_order_models.dart';
import 'work_order_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Work Order List Screen
// ─────────────────────────────────────────────────────────────────────────────

class WorkOrderListScreen extends ConsumerStatefulWidget {
  const WorkOrderListScreen({super.key});

  @override
  ConsumerState<WorkOrderListScreen> createState() =>
      _WorkOrderListScreenState();
}

class _WorkOrderListScreenState extends ConsumerState<WorkOrderListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _search = '';
  final _searchCtrl = TextEditingController();

  static const _tabs = [
    ('ทั้งหมด', null),
    ('รอดำเนินการ', 'pending'),
    ('อนุมัติแล้ว', 'approved'),
    ('กำลังซ่อม', 'in_progress'),
    ('เสร็จสิ้น', 'completed'),
    ('ยกเลิก', 'cancelled'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String? get _statusFilter => _tabs[_tabController.index].$2;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final woAsync = ref.watch(workOrderListProvider(
      WorkOrderFilter(status: _statusFilter, search: _search.isEmpty ? null : _search),
    ));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        _WoPageHeader(
          user: user,
          onNew: () => context.go('/work-orders/new'),
        ),

        // Tabs
        Container(
          color: Theme.of(context).cardTheme.color,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabs: _tabs.map((t) => Tab(text: t.$1)).toList(),
            tabAlignment: TabAlignment.start,
          ),
        ),

        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl, AppSpacing.lg, AppSpacing.xxl, 0),
          child: Row(
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'ค้นหาใบสั่งงาน...',
                    prefixIcon: Padding(
                      padding: EdgeInsets.all(12),
                      child: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    contentPadding: EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const Spacer(),
              woAsync.whenOrNull(
                    data: (list) => Text('${list.length} รายการ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            )),
                  ) ??
                  const SizedBox.shrink(),
              const SizedBox(width: AppSpacing.md),
              IconButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                onPressed: () => ref.invalidate(workOrderListProvider),
                tooltip: 'รีเฟรช',
              ),
            ],
          ),
        ),

        // Table
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: woAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (orders) => orders.isEmpty
                  ? _EmptyWoState(onNew: () => context.go('/work-orders/new'))
                  : _WoTable(
                      orders: orders,
                      user: user,
                      onTap: (id) => context.go('/work-orders/$id'),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _WoPageHeader extends StatelessWidget {
  final UserSession? user;
  final VoidCallback onNew;
  const _WoPageHeader({this.user, required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.lg),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const HugeIcon(icon: HugeIcons.strokeRoundedTask01,
                      color: AppColors.primary, size: 24),
                  const SizedBox(width: AppSpacing.sm),
                  Text('ใบสั่งงานซ่อมบำรุง',
                      style: AppTextStyles.headlineLarge),
                ],
              ),
              const SizedBox(height: 4),
              Text('Work Order Management — ติดตามและจัดการงานซ่อม',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
            ],
          ),
          const Spacer(),
          if (user?.isTechnicianOrAbove ?? false)
            ElevatedButton.icon(
              onPressed: onNew,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedPlusSign, size: 18, color: Colors.white),
              label: const Text('สร้างใบสั่งงาน'),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Table
// ─────────────────────────────────────────────────────────────────────────────

class _WoTable extends StatelessWidget {
  final List<WorkOrder> orders;
  final UserSession? user;
  final void Function(String id) onTap;

  const _WoTable({
    required this.orders,
    this.user,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          // Header row
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                topRight: Radius.circular(AppRadius.lg),
              ),
            ),
            child: Row(
              children: [
                _H('เลขที่ใบงาน', flex: 2),
                _H('เครื่องจักร', flex: 2),
                _H('หัวข้อ', flex: 4),
                _H('ความสำคัญ', flex: 2),
                _H('ช่างผู้รับผิดชอบ', flex: 3),
                _H('วันที่แจ้ง', flex: 2),
                _H('สถานะ', flex: 2),
              ],
            ),
          ),
          Container(height: 1, color: Theme.of(context).colorScheme.outline),
          Expanded(
            child: ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (context, index) => Container(
                  height: 1,
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.3)),
              itemBuilder: (context, i) {
                final wo = orders[i];
                return _WoRow(wo: wo, onTap: () => onTap(wo.woId));
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  final String label;
  final int flex;
  const _H(this.label, {this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
        flex: flex,
        child: Text(label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                )));
  }
}

class _WoRow extends StatelessWidget {
  final WorkOrder wo;
  final VoidCallback onTap;
  const _WoRow({required this.wo, required this.onTap});

  Color get _statusColor {
    switch (wo.status) {
      case WorkOrderStatus.completed:
        return AppColors.success;
      case WorkOrderStatus.inProgress:
        return AppColors.primary;
      case WorkOrderStatus.pending:
        return AppColors.warning;
      case WorkOrderStatus.rejected:
      case WorkOrderStatus.cancelled:
        return AppColors.machineOffline;
      case WorkOrderStatus.approved:
        return AppColors.info;
    }
  }

  Color get _priorityColor {
    switch (wo.priority) {
      case WorkOrderPriority.urgent:
        return AppColors.error;
      case WorkOrderPriority.high:
        return AppColors.severityHigh;
      case WorkOrderPriority.low:
        return AppColors.severityLow;
      default:
        return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg, vertical: AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: Text(wo.woNo,
                    style: AppTextStyles.labelMedium
                        .copyWith(color: AppColors.primary)),
              ),
              Expanded(
                flex: 2,
                child: Text(wo.machineNo, style: AppTextStyles.bodySmall),
              ),
              Expanded(
                flex: 4,
                child: Text(
                  wo.description ?? '-',
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _priorityColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Text(wo.priority.label,
                          style: TextStyle(
                              fontSize: 11,
                              color: _priorityColor,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  wo.assignedToName ?? 'ยังไม่มอบหมาย',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  DateFormatters.formatDateTime(wo.reportedAt),
                  style: AppTextStyles.labelSmall,
                ),
              ),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    border: Border.all(
                        color: _statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(wo.status.label,
                      style: TextStyle(
                          fontSize: 11,
                          color: _statusColor,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyWoState extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyWoState({required this.onNew});

  @override
  Widget build(BuildContext context) {
    return EmptyView(
      title: 'ไม่มีใบสั่งงาน',
      description: 'กดปุ่ม "สร้างใบสั่งงาน" เพื่อแจ้งซ่อม',
      onButtonTap: onNew,
      buttonText: 'สร้างใบสั่งงาน',
    );
  }
}
