import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/app_utils.dart';
import '../../features/auth/auth_provider.dart';
import 'machine_models.dart';
import 'machine_provider.dart';

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
        _PageHeader(user: user, onNew: () => context.go('/machine-intake/new')),

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
                  decoration: const InputDecoration(
                    hintText: 'ค้นหาเครื่องจักร...',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
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
                icon: const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => ref.invalidate(machineListProvider(_filter)),
                tooltip: 'รีเฟรช',
              ),
              Text(
                machineAsync.whenOrNull(data: (l) => '${l.length} รายการ') ??
                    '',
                style: AppTextStyles.secondary,
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
                      onEdit: (id) => context.go('/machine-intake/$id'),
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
        title: const Text('ยืนยันการลบ'),
        content: const Text(
          'ต้องการลบเครื่องจักรนี้ออกจากระบบหรือไม่?\nข้อมูลจะถูกซ่อน แต่ยังคงอยู่ในฐานข้อมูล',
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
      await ref.read(machineRepositoryProvider).deleteMachine(machineId);
      ref.invalidate(machineListProvider(_filter));
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
                    Icons.add_business_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text('การรับเครื่องจักร', style: AppTextStyles.headlineLarge),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Digital Handover — ทะเบียนรับเครื่องจักรใหม่',
                style: AppTextStyles.secondary,
              ),
            ],
          ),
          const Spacer(),
          if (user?.canWrite('machine_intake') ?? false)
            ElevatedButton.icon(
              onPressed: onNew,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('รับเครื่องจักรใหม่'),
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
              : AppColors.bgElevated,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: selected ? (color ?? AppColors.primary) : AppColors.border,
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
                    : AppColors.textSecondary,
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
            decoration: const BoxDecoration(
              color: AppColors.bgElevated,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                topRight: Radius.circular(AppRadius.lg),
              ),
            ),
            child: Row(
              children: [
                _HeaderCell('รหัสเครื่อง', flex: 2),
                _HeaderCell('ยี่ห้อ / รุ่น', flex: 3),
                _HeaderCell('Serial No.', flex: 2),
                _HeaderCell('ตำแหน่ง', flex: 2),
                _HeaderCell('สถานะ', flex: 2),
                _HeaderCell('Handover', flex: 2),
                _HeaderCell('วันติดตั้ง', flex: 2),
                _HeaderCell('ชม.สะสม', flex: 1),
                _HeaderCell('', flex: 1),
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
        style: AppTextStyles.labelMedium.copyWith(
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _MachineRow extends StatelessWidget {
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
  Widget build(BuildContext context) {
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
                        style: AppTextStyles.secondary,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              // Serial No
              Expanded(
                flex: 2,
                child: Text(
                  machine.serialNo ?? '-',
                  style: AppTextStyles.secondary,
                ),
              ),
              // Location
              Expanded(
                flex: 2,
                child: Text(
                  machine.location ?? '-',
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Status
              Expanded(flex: 2, child: _StatusBadge(status: machine.status)),
              // Handover
              Expanded(
                flex: 2,
                child: machine.handoverCompleted
                    ? const Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: AppColors.success,
                            size: 16,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'สมบูรณ์',
                            style: TextStyle(
                              color: AppColors.success,
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
                      ),
              ),
              // Install Date
              Expanded(
                flex: 2,
                child: Text(
                  DateFormatters.formatDate(machine.installationDate),
                  style: AppTextStyles.secondary,
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
                  style: AppTextStyles.secondary,
                ),
              ),
              // Actions
              Expanded(
                flex: 1,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      onPressed: onEdit,
                      tooltip: 'แก้ไข',
                      color: AppColors.textSecondary,
                      padding: const EdgeInsets.all(4),
                    ),
                    if (user?.isAdmin ?? false)
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                        ),
                        onPressed: onDelete,
                        tooltip: 'ลบ',
                        color: AppColors.error,
                        padding: const EdgeInsets.all(4),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.precision_manufacturing_outlined,
            size: 64,
            color: AppColors.textDisabled,
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'ยังไม่มีเครื่องจักรในระบบ',
            style: AppTextStyles.headlineSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'กดปุ่ม "รับเครื่องจักรใหม่" เพื่อเริ่มต้น',
            style: AppTextStyles.secondary,
          ),
        ],
      ),
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
              style: AppTextStyles.secondary,
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
