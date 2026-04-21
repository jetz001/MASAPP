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
import 'machine_models.dart';
import 'machine_provider.dart';
import 'widgets/approval_dialog.dart';
import 'utils/machine_form_utils.dart';
import '../dashboard/dashboard_screen.dart';

class MachineIntakeListScreen extends ConsumerStatefulWidget {
  const MachineIntakeListScreen({super.key});

  @override
  ConsumerState<MachineIntakeListScreen> createState() =>
      _MachineIntakeListScreenState();
}

class _MachineIntakeListScreenState
    extends ConsumerState<MachineIntakeListScreen> {
  final _searchCtrl = TextEditingController();
  String? _statusFilter;
  String? _categoryFilter;
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  MachineListFilter get _filter => MachineListFilter(
    searchQuery: _searchQuery.isEmpty ? null : _searchQuery,
    status: _statusFilter,
    categoryId: _categoryFilter,
  );

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final machineAsync = ref.watch(machineListProvider(_filter));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Page header
        _PageHeader(user: user, onNew: () => context.go('/machine-registry/new')),

        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            0,
            AppSpacing.xxl,
            AppSpacing.lg,
          ),
          child: Row(
            children: [
              // Search
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _searchCtrl,
                  style: AppTextStyles.bodyMedium,
                  decoration: InputDecoration(
                    hintText: 'ค้นหาเครื่องจักร...',
                    prefixIcon: Padding(
                      padding: EdgeInsets.all(12),
                      child: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 12,
                    ),
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                ),
              ),
              const SizedBox(width: AppSpacing.md),

              // Status filter
              _FilterChip(
                label: 'ทั้งหมด',
                selected: _statusFilter == null,
                onTap: () => setState(() => _statusFilter = null),
              ),
              const SizedBox(width: AppSpacing.xs),
              _FilterChip(
                label: 'ปกติ',
                selected: _statusFilter == 'normal',
                color: AppColors.machineNormal,
                onTap: () => setState(
                  () => _statusFilter = _statusFilter == 'normal'
                      ? null
                      : 'normal',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _FilterChip(
                label: 'เสีย',
                selected: _statusFilter == 'breakdown',
                color: AppColors.machineBreakdown,
                onTap: () => setState(
                  () => _statusFilter = _statusFilter == 'breakdown'
                      ? null
                      : 'breakdown',
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _FilterChip(
                label: 'PM',
                selected: _statusFilter == 'pm',
                color: AppColors.machinePM,
                onTap: () => setState(
                  () => _statusFilter = _statusFilter == 'pm' ? null : 'pm',
                ),
              ),

              const Spacer(),
              // Refresh
              IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedRefresh,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                onPressed: () => ref.invalidate(machineListProvider(_filter)),
                tooltip: 'รีเฟรช',
              ),
              Text(
                machineAsync.whenOrNull(data: (l) => '${l.length} รายการ') ??
                    '',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),

        // Table
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl,
              0,
              AppSpacing.xxl,
              AppSpacing.xxl,
            ),
            child: machineAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(
                error: e.toString(),
                onRetry: () => ref.invalidate(machineListProvider(_filter)),
              ),
              data: (machines) => machines.isEmpty
                  ? const _EmptyState()
                  : _MachineTable(
                      machines: machines,
                      user: user,
                      onEdit: (id) => context.go('/machine-registry/$id'),
                      onDelete: (id) => _confirmDelete(context, id),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, String machineId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบแบบถาวร'),
        content: const Text(
          'ต้องการลบเครื่องจักรนี้ออกจากระบบ "ถาวร" หรือไม่?\nข้อมูลเครื่อง ข้อมูลการตรวจรับ และประวัติการซ่อมทั้งหมดจะถูกลบและไม่สามารถกู้คืนได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(machineRepositoryProvider).deleteMachine(machineId);
        ref.invalidate(machineListProvider(_filter));
        ref.invalidate(dashboardStatsProvider);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ลบข้อมูลเครื่องจักรเรียบร้อยแล้ว'),
            backgroundColor: AppColors.success,
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('ไม่สามารถลบข้อมูลได้: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}

// ─── Page Header ─────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final UserSession? user;
  final VoidCallback onNew;
  const _PageHeader({this.user, required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.xxl,
        AppSpacing.lg,
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.library_books_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('ทะเบียนเครื่องจักร', style: AppTextStyles.headlineLarge),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Machine Registry — ข้อมูลหลักเครื่องจักรทั้งหมดและการรับมอบ',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const Spacer(),
          if (user?.canWrite('machine_intake') ?? false)
            ElevatedButton.icon(
              onPressed: onNew,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedPlusSign, size: 18, color: Colors.white),
              label: const Text('เพิ่มเครื่องจักรใหม่'),
            ),
        ],
      ),
    );
  }
}

// ─── Filter Chip ─────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (color ?? AppColors.primary).withValues(alpha: 0.2)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected
                ? (color ?? AppColors.primary)
                : Theme.of(context).dividerColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null && selected) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: AppTextStyles.labelMedium.copyWith(
                color: selected
                    ? (color ?? AppColors.primary)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Machine Table ────────────────────────────────────────────────────────────

class _MachineTable extends StatelessWidget {
  final List<MachineModel> machines;
  final UserSession? user;
  final void Function(String id) onEdit;
  final void Function(String id) onDelete;

  const _MachineTable({
    required this.machines,
    this.user,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                topRight: Radius.circular(AppRadius.lg),
              ),
            ),
            child: Row(
              children: [
                _HeaderCell('รหัสเครื่อง', flex: 2),
                _HeaderCell('ยี่ห้อ / รุ่น', flex: 3),
                _HeaderCell('Serial', flex: 1),
                _HeaderCell('ตำแหน่ง', flex: 1),
                _HeaderCell('สถานะ', flex: 2),
                _HeaderCell('Handover', flex: 2),
                _HeaderCell('ติดตั้ง', flex: 2),
                _HeaderCell('Hrs', flex: 1),
                _HeaderCell('Actions', flex: 2),
              ],
            ),
          ),

          Container(height: 1, color: AppColors.divider),

          // Table rows
          Expanded(
            child: ListView.separated(
              itemCount: machines.length,
              separatorBuilder: (_, _) =>
                  Container(height: 1, color: AppColors.divider),
              itemBuilder: (context, index) {
                final m = machines[index];
                return _MachineRow(
                  machine: m,
                  user: user,
                  onEdit: () => onEdit(m.machineId ?? ''),
                  onDelete: () => onDelete(m.machineId ?? ''),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  final int flex;
  const _HeaderCell(this.label, {this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _MachineRow extends ConsumerWidget {
  final MachineModel machine;
  final UserSession? user;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MachineRow({
    required this.machine,
    this.user,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              // Machine No
              Expanded(
                flex: 2,
                child: Text(
                  machine.machineNo,
                  style: AppTextStyles.titleMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              // Brand/Model
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(machine.brand ?? '-', style: AppTextStyles.bodyMedium),
                    if (machine.model != null)
                      Text(
                        machine.model!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Serial No
              Expanded(
                flex: 1,
                child: Text(
                  machine.serialNo ?? '-',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Location
              Expanded(
                flex: 1,
                child: Text(
                  machine.location ?? '-',
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Status
              Expanded(flex: 2, child: _StatusBadge(status: machine.status)),
              Expanded(
                flex: 2,
                child: machine.stage3Status == HandoverStatus.approved
                    ? const Row(
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            color: AppColors.success,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'อนุมัติแล้ว',
                            style: TextStyle(
                              color: AppColors.success,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : (machine.stage3Status == HandoverStatus.passed
                        ? const Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline_rounded,
                                color: AppColors.primary,
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'ตรวจรับแล้ว',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )
                        : const Row(
                            children: [
                              Icon(
                                Icons.pending_outlined,
                                color: AppColors.warning,
                                size: 16,
                              ),
                              SizedBox(width: 4),
                              Text(
                                'รอดำเนินการ',
                                style: TextStyle(
                                  color: AppColors.warning,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          )),
              ),
              // Install Date
              Expanded(
                flex: 2,
                child: Text(
                  DateFormatters.formatDate(machine.installationDate),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              // Running Hours
              Expanded(
                flex: 1,
                child: Text(
                  machine.totalRunningHours != null
                      ? NumberFormatters.formatDecimal(
                          machine.totalRunningHours,
                          decimals: 0,
                        )
                      : '-',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              // Actions
              Expanded(
                flex: 2,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: 16, color: AppColors.textSecondary),
                      onPressed: onEdit,
                      tooltip: 'แก้ไข',
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    if (user?.isEngineerOrAbove == true && 
                        machine.stage3Status != HandoverStatus.approved)
                      IconButton(
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedStamp01,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        onPressed: () => _showQuickApproval(context, ref),
                        tooltip: 'ลงนามอนุมัติ (Approver)',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.print_outlined, size: 18, color: AppColors.primary),
                        onPressed: () async {
                          final fullMachine = await ref.read(machineRepositoryProvider).fetchById(machine.machineId!);
                          if (fullMachine != null) {
                            MachineFormUtils.generateIntakeReport(fullMachine);
                          }
                        },
                        tooltip: 'พิมพ์รายงานการรับมอบ',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    if (user?.isAdmin ?? false)
                      IconButton(
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedDelete02,
                          size: 16,
                          color: AppColors.error,
                        ),
                        onPressed: onDelete,
                        tooltip: 'ลบ',
                        color: AppColors.error,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showQuickApproval(BuildContext context, WidgetRef ref) async {
    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) => ApprovalDialog(
        machineId: machine.machineId!,
        title: 'การอนุมัติ (Approver Sign-off)',
        isApprover: true,
      ),
    );
    if (success == true) {
      ref.invalidate(machineListProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อนุมัติเครื่องจักรเรียบร้อยแล้ว')),
        );
      }
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final MachineStatus status;
  const _StatusBadge({required this.status});

  Color get _color {
    switch (status) {
      case MachineStatus.normal:
        return AppColors.machineNormal;
      case MachineStatus.breakdown:
        return AppColors.machineBreakdown;
      case MachineStatus.pm:
        return AppColors.machinePM;
      case MachineStatus.am:
        return AppColors.machineAM;
      case MachineStatus.offline:
        return AppColors.machineOffline;
      case MachineStatus.decommissioned:
        return AppColors.machineOffline;
    }
  }

  String get _label {
    switch (status) {
      case MachineStatus.normal:
        return 'ปกติ';
      case MachineStatus.breakdown:
        return 'เสีย';
      case MachineStatus.pm:
        return 'PM';
      case MachineStatus.am:
        return 'AM';
      case MachineStatus.offline:
        return 'หยุด';
      case MachineStatus.decommissioned:
        return 'ปลดระวาง';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: _color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            _label,
            style: TextStyle(
              fontSize: 11,
              color: _color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty / Error States ─────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return EmptyView(
      title: 'ยังไม่มีเครื่องจักรในระบบ',
      description: 'กดปุ่ม "รับเครื่องจักรใหม่" เพื่อเริ่มต้น',
      onButtonTap: () {}, // Optional: refresh action
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 48,
            color: AppColors.error,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('เกิดข้อผิดพลาด', style: AppTextStyles.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: 400,
            child: Text(
              error,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              maxLines: 5,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('ลองใหม่'),
          ),
        ],
      ),
    );
  }
}
