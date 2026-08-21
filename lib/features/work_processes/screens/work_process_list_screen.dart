import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/theme/app_spacing.dart';
import '../models/work_process_model.dart';
import '../providers/work_process_provider.dart';

class WorkProcessListScreen extends ConsumerStatefulWidget {
  const WorkProcessListScreen({super.key});

  @override
  ConsumerState<WorkProcessListScreen> createState() =>
      _WorkProcessListScreenState();
}

class _WorkProcessListScreenState extends ConsumerState<WorkProcessListScreen> {
  String _searchQuery = '';
  int _viewMode = 0; // 0: Machine-Centric View (Default), 1: All Processes List
  String _filterStatus = 'all'; // all, configured, unconfigured

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final machineProcessesAsync = ref.watch(machineProcessListProvider);
    final allProcessesAsync = ref.watch(workProcessListProvider);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: HugeIcon(
                icon: HugeIcons.strokeRoundedFlowSquare,
                size: 20,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            const Flexible(
              child: Text(
                'ขั้นตอนการทำงานประจำเครื่องจักร (SOP)',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          FilledButton.tonalIcon(
            icon: const Icon(Icons.analytics_rounded, size: 18),
            label: const Text('Lean Analysis & VSM'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber.shade100,
              foregroundColor: Colors.amber.shade900,
            ),
            onPressed: () => context.push('/lean-analysis'),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'รีเฟรช',
            onPressed: () {
              ref.read(machineProcessListProvider.notifier).refresh();
            },
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.add_rounded),
            label: const Text('เพิ่มขั้นตอนงาน'),
            onPressed: () => context.push('/work-processes/new'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: machineProcessesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48, color: Colors.red),
              const SizedBox(height: 12),
              Text('เกิดข้อผิดพลาดในการโหลดข้อมูล: $err'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () =>
                    ref.read(machineProcessListProvider.notifier).refresh(),
                child: const Text('ลองใหม่'),
              ),
            ],
          ),
        ),
        data: (machineItems) {
          final allProcesses = allProcessesAsync.valueOrNull ?? [];

          return Column(
            children: [
              _buildTopViewSelector(theme, machineItems, allProcesses),
              _buildSearchBar(theme, machineItems),
              Expanded(
                child: _viewMode == 0
                    ? _buildMachineListView(machineItems, theme)
                    : _buildAllProcessesListView(allProcesses, theme),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopViewSelector(
    ThemeData theme,
    List<MachineProcessItem> machineItems,
    List<WorkProcess> allProcesses,
  ) {
    final configuredCount = machineItems.where((m) => m.hasProcess).length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            SegmentedButton<int>(
              segments: [
                ButtonSegment(
                  value: 0,
                  icon: const Icon(Icons.precision_manufacturing_rounded, size: 18),
                  label: Text('รายเครื่องจักร (${machineItems.length})'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: const Icon(Icons.format_list_bulleted_rounded, size: 18),
                  label: Text('รายการขั้นตอนทั้งหมด (${allProcesses.length})'),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (val) {
                setState(() => _viewMode = val.first);
              },
            ),
            const SizedBox(width: 16),
            if (_viewMode == 0) ...[
              FilterChip(
                label: Text('ทั้งหมด (${machineItems.length})'),
                selected: _filterStatus == 'all',
                onSelected: (_) => setState(() => _filterStatus = 'all'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                avatar: const Icon(Icons.check_circle_rounded, size: 16, color: Colors.green),
                label: Text('บันทึกแล้ว ($configuredCount)'),
                selected: _filterStatus == 'configured',
                onSelected: (_) => setState(() => _filterStatus = 'configured'),
              ),
              const SizedBox(width: 8),
              FilterChip(
                avatar: const Icon(Icons.radio_button_unchecked_rounded, size: 16, color: Colors.grey),
                label: Text('ยังไม่มีขั้นตอน (${machineItems.length - configuredCount})'),
                selected: _filterStatus == 'unconfigured',
                onSelected: (_) => setState(() => _filterStatus = 'unconfigured'),
              ),
            ],
            const SizedBox(width: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '💡 บันทึก SOP ประจำเครื่อง แล้วส่งต่อวิเคราะห์ที่ Lean Analysis',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, List<MachineProcessItem> machineItems) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: TextField(
        decoration: InputDecoration(
          hintText: _viewMode == 0
              ? 'ค้นหารหัสเครื่อง, ชื่อเครื่องจักร, ยี่ห้อ, รุ่น, หรือแผนก...'
              : 'ค้นหาชื่องาน, รหัสเอกสาร, เครื่องจักร, แผนก...',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
      ),
    );
  }

  Widget _buildMachineListView(List<MachineProcessItem> items, ThemeData theme) {
    final filtered = items.where((m) {
      final q = _searchQuery.toLowerCase();
      final matchSearch = _searchQuery.isEmpty ||
          m.machineNo.toLowerCase().contains(q) ||
          m.machineName.toLowerCase().contains(q) ||
          (m.brand?.toLowerCase().contains(q) ?? false) ||
          (m.model?.toLowerCase().contains(q) ?? false) ||
          (m.department?.toLowerCase().contains(q) ?? false) ||
          (m.location?.toLowerCase().contains(q) ?? false);

      final matchStatus = _filterStatus == 'all' ||
          (_filterStatus == 'configured' && m.hasProcess) ||
          (_filterStatus == 'unconfigured' && !m.hasProcess);

      return matchSearch && matchStatus;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.precision_manufacturing_outlined, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'ไม่พบเครื่องจักรที่ตรงกับคำค้นหา "$_searchQuery"'
                  : 'ยังไม่มีข้อมูลเครื่องจักรในระบบ',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: filtered.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = filtered[index];
        final curProcess = item.currentProcess;

        return Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: item.hasProcess
                  ? Colors.green.shade400.withValues(alpha: 0.5)
                  : theme.colorScheme.outlineVariant,
              width: item.hasProcess ? 1.2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: item.hasProcess && curProcess != null
                ? () => context.push('/work-processes/${curProcess.processId}')
                : () => context.push('/work-processes/new?machineId=${item.machineId}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // 1. Machine Code
                  Container(
                    width: 120,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.machineNo,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 2. Machine Name & Model
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          item.machineName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        if ((item.brand?.isNotEmpty ?? false) || (item.model?.isNotEmpty ?? false)) ...[
                          const SizedBox(height: 2),
                          Text(
                            [if (item.brand?.isNotEmpty ?? false) item.brand!, if (item.model?.isNotEmpty ?? false) item.model!].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // 3. Department & Location
                  Expanded(
                    flex: 2,
                    child: (item.department?.isNotEmpty ?? false) || (item.location?.isNotEmpty ?? false)
                        ? Row(
                            children: [
                              Icon(Icons.business_rounded, size: 14, color: theme.colorScheme.outline),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  [if (item.department?.isNotEmpty ?? false) item.department!, if (item.location?.isNotEmpty ?? false) item.location!].join(' - '),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),

                  // 4. SOP Status Badge
                  Container(
                    width: 180,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: item.hasProcess ? Colors.green.shade50 : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: item.hasProcess ? Colors.green.shade400 : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.hasProcess ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 14,
                          color: item.hasProcess ? Colors.green.shade700 : Colors.grey.shade600,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            item.hasProcess
                                ? '${item.stepCount} ขั้น (${item.totalDuration.toStringAsFixed(0)} นาที)'
                                : 'ยังไม่มีขั้นตอน (SOP)',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: item.hasProcess ? Colors.green.shade800 : Colors.grey.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // 5. Actions Buttons
                  if (item.hasProcess && curProcess != null) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.edit_note_rounded, size: 16),
                      label: const Text('แก้ไข SOP'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () => context.push('/work-processes/${curProcess.processId}'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.analytics_rounded, size: 16),
                      label: const Text('Lean VSM'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.amber.shade100,
                        foregroundColor: Colors.amber.shade900,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () => context.push('/lean-analysis?processId=${curProcess.processId}'),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: const Text('บันทึกขั้นตอน SOP'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      ),
                      onPressed: () => context.push('/work-processes/new?machineId=${item.machineId}'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAllProcessesListView(List<WorkProcess> list, ThemeData theme) {
    final filtered = list.where((p) {
      final matchSearch = _searchQuery.isEmpty ||
          p.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          p.processNo.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (p.department?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
          (p.machineNo?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);

      return matchSearch;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_outlined, size: 64, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'ไม่พบรายการขั้นตอนการทำงาน',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final process = filtered[index];
        final isCurrent = process.methodType == WorkProcessMethodType.current;

        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isCurrent
                  ? theme.colorScheme.outlineVariant
                  : Colors.green.shade400.withValues(alpha: 0.5),
              width: isCurrent ? 1 : 1.5,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => context.push('/work-processes/${process.processId}'),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? Colors.blue.shade500.withValues(alpha: 0.15)
                              : Colors.green.shade500.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isCurrent ? Colors.blue : Colors.green,
                          ),
                        ),
                        child: Text(
                          process.methodType.label,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isCurrent ? Colors.blue.shade700 : Colors.green.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        process.processNo,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.analytics_rounded, size: 20),
                        tooltip: 'วิเคราะห์ Lean & ความสูญเปล่า',
                        onPressed: () => context.push(
                          '/lean-analysis?processId=${process.processId}',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        tooltip: 'ทำซ้ำเป็นฉบับปรับปรุง (Create Improved Version)',
                        onPressed: () => _handleDuplicate(process),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                        tooltip: 'ลบ',
                        onPressed: () => _handleDelete(process),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    process.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (process.machineNo != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      'เครื่องจักร: ${process.machineNo} ${process.machineName ?? ""}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${process.steps.length} ขั้นตอน', style: const TextStyle(fontSize: 12)),
                      Text('เวลารวม: ${process.totalDurationMinutes.toStringAsFixed(1)} นาที', style: const TextStyle(fontSize: 12)),
                      Text('PCE: ${process.processCycleEfficiency.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleDuplicate(WorkProcess process) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('สร้างฉบับปรับปรุง (Improved Version)?'),
        content: Text(
          'ระบบจะคัดลอกขั้นตอนจาก "${process.title}" ไปเป็นฉบับปรับปรุง เพื่อเปรียบเทียบ Before vs After',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('สร้างฉบับปรับปรุง'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        final newId = await ref
            .read(workProcessListProvider.notifier)
            .duplicateAsImproved(process.processId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('สร้างฉบับปรับปรุงเรียบร้อยแล้ว')),
          );
          context.push('/work-processes/$newId');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เกิดข้อผิดพลาด: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _handleDelete(WorkProcess process) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ?'),
        content: Text('คุณต้องการลบแบบวิเคราะห์ "${process.title}" หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref
          .read(workProcessListProvider.notifier)
          .deleteProcess(process.processId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบรายการเรียบร้อยแล้ว')),
        );
      }
    }
  }
}
