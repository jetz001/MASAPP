import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:masapp/core/theme/app_colors.dart';
import 'package:masapp/core/theme/app_spacing.dart';
import 'package:masapp/core/theme/app_text_styles.dart';
import 'package:masapp/features/auth/auth_provider.dart';
import 'package:masapp/core/database/db_helper.dart';
import 'package:masapp/features/work_orders/work_order_models.dart';
import 'package:masapp/features/work_orders/work_order_provider.dart';
import 'package:masapp/features/work_orders/widgets/add_wo_part_dialog.dart';
import 'package:masapp/features/work_orders/work_order_gate_pass_pdf_service.dart';
import 'package:masapp/features/work_orders/work_order_pdf_service.dart';

class WorkOrderDetailScreen extends ConsumerWidget {
  final String woId;
  const WorkOrderDetailScreen({super.key, required this.woId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final woAsync = ref.watch(workOrderProvider(woId));
    final user = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('รายละเอียดใบแจ้งซ่อม'),
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          if (woAsync.hasValue && woAsync.value != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'แก้ไขใบแจ้งซ่อม',
              onPressed: () =>
                  context.push('/work-orders/new', extra: woAsync.value),
            ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'พิมพ์ใบแจ้งซ่อม',
            onPressed: () => WorkOrderPdfService.generateAndOpen(woId: woId),
          ),
        ],
      ),
      body: woAsync.when(
        data: (wo) {
          if (wo == null) {
            return const Center(child: Text('ไม่พบข้อมูลใบแจ้งซ่อม'));
          }
          return _buildContent(context, ref, wo, user);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => Center(child: Text('Error: $err')),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    WorkOrder wo,
    UserSession? user,
  ) {
    final fmt = DateFormat('dd MMM yyyy, HH:mm', 'th');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            wo.woNo,
                            style: AppTextStyles.headlineMedium.copyWith(
                              color: AppColors.primary,
                            ),
                          ),
                          _buildStatusBadge(wo.status),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        wo.description ?? 'ไม่มีหัวข้อ',
                        style: AppTextStyles.titleLarge,
                      ),
                      if (wo.failureSymptom != null &&
                          wo.failureSymptom!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'อาการเบื้องต้น: ${wo.failureSymptom}',
                          style: AppTextStyles.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.md),
                      const Divider(),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('ไฟล์แนบ:', style: AppTextStyles.labelMedium),
                          TextButton.icon(
                            onPressed: () async {
                              final result = await FilePicker.platform
                                  .pickFiles(allowMultiple: true);
                              if (result != null && result.paths.isNotEmpty) {
                                final validPaths = result.paths
                                    .whereType<String>()
                                    .toList();
                                final current = List<String>.from(
                                  wo.attachments ?? [],
                                );
                                current.addAll(validPaths);

                                final saved = await ref
                                    .read(workOrderRepositoryProvider)
                                    .updateAttachments(wo.woId, current);
                                if (saved != null && context.mounted) {
                                  ref.invalidate(workOrderProvider(woId));
                                }
                              }
                            },
                            icon: const Icon(
                              Icons.add_circle_outline,
                              size: 18,
                            ),
                            label: const Text('เพิ่มไฟล์แนบ'),
                          ),
                        ],
                      ),
                      if (wo.attachments != null &&
                          wo.attachments!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: wo.attachments!.map((path) {
                            final fileName = p.basename(path);
                            return InputChip(
                              avatar: const Icon(Icons.attach_file, size: 16),
                              label: Text(
                                fileName,
                                style: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () {
                                OpenFilex.open(path);
                              },
                              onDeleted: () async {
                                final current = List<String>.from(
                                  wo.attachments!,
                                );
                                current.remove(path);
                                final saved = await ref
                                    .read(workOrderRepositoryProvider)
                                    .updateAttachments(wo.woId, current);
                                if (saved != null && context.mounted) {
                                  ref.invalidate(workOrderProvider(woId));
                                }
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column
                  Expanded(
                    flex: 2,
                    child: Column(
                      children: [
                        _buildInfoCard(
                          title: 'ข้อมูลเครื่องจักร',
                          icon: HugeIcons.strokeRoundedSettings01,
                          onEdit: () =>
                              context.push('/work-orders/new', extra: wo),
                          children: [
                            _InfoRow(
                              label: 'เครื่องจักร',
                              value: wo.machineNo != null
                                  ? '${wo.machineNo} - ${wo.machineBrand ?? ''}'
                                  : 'งานอาคาร / ทั่วไป',
                            ),
                            if (wo.zone != null)
                              _InfoRow(label: 'พื้นที่', value: wo.zone!),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _buildInfoCard(
                          title: 'ผู้เกี่ยวข้อง',
                          icon: HugeIcons.strokeRoundedUserGroup,
                          onEdit: () =>
                              context.push('/work-orders/new', extra: wo),
                          children: [
                            _InfoRow(
                              label: 'ผู้แจ้ง',
                              value: wo.reportedByName ?? 'SYSTEM',
                            ),
                            _InfoRow(
                              label: 'วันที่แจ้ง',
                              value: fmt.format(wo.createdAt),
                            ),
                            _InfoRow(
                              label: 'ช่างผู้รับผิดชอบ',
                              value: wo.assignedToName ?? '-',
                            ),
                            if (wo.approvedBy != null)
                              _InfoRow(
                                label: 'ผู้อนุมัติ',
                                value: wo.approvedByName ?? wo.approvedBy!,
                              ),
                          ],
                        ),
                        if (wo.rca != null ||
                            (wo.closureNotes != null &&
                                wo.closureNotes!.isNotEmpty)) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _buildInfoCard(
                            title: 'บันทึกการซ่อม (ช่างซ่อมบำรุง)',
                            icon: HugeIcons.strokeRoundedWrench01,
                            onEdit: () =>
                                _showEditRepairLogDialog(context, ref, wo),
                            children: [
                              if (wo.rca?.rootCause != null &&
                                  wo.rca!.rootCause!.isNotEmpty)
                                _InfoRow(
                                  label: 'สาเหตุของปัญหา',
                                  value: wo.rca!.rootCause!,
                                ),
                              if (wo.closureNotes != null &&
                                  wo.closureNotes!.isNotEmpty)
                                _InfoRow(
                                  label: 'รายละเอียดการซ่อม',
                                  value: wo.closureNotes!,
                                ),
                            ],
                          ),
                        ],
                        if (wo.outsource != null) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _buildInfoCard(
                            title: 'ข้อมูลการส่งซ่อมภายนอก',
                            icon: Icons.local_shipping,
                            onEdit: () =>
                                _showEditOutsourceDialog(context, ref, wo),
                            children: [
                              _InfoRow(
                                label: 'ผู้รับเหมา',
                                value: wo.outsource!.vendorName,
                              ),
                              if (wo.outsource!.createdAt != null)
                                _InfoRow(
                                  label: 'วันเวลาที่ส่งซ่อม',
                                  value: DateFormat(
                                    'dd MMM yyyy HH:mm',
                                    'th',
                                  ).format(wo.outsource!.createdAt!),
                                ),
                              if (wo.outsource!.repairDetails != null &&
                                  wo.outsource!.repairDetails!.isNotEmpty)
                                _InfoRow(
                                  label: 'อาการ/รายการซ่อม',
                                  value: _formatRepairDetailsForView(
                                    wo.outsource!.repairDetails!,
                                  ),
                                ),
                              if (wo.outsource!.expectedReturnDate != null)
                                _InfoRow(
                                  label: 'วันที่คาดว่าจะเสร็จ',
                                  value: DateFormat(
                                    'dd MMM yyyy',
                                    'th',
                                  ).format(wo.outsource!.expectedReturnDate!),
                                ),
                              if (wo.outsource!.notes != null &&
                                  wo.outsource!.notes!.isNotEmpty)
                                _InfoRow(
                                  label: 'หมายเหตุการตรวจรับ',
                                  value: wo.outsource!.notes!,
                                ),
                              if (wo.outsource!.gatePassNo != null &&
                                  wo.outsource!.gatePassNo!.isNotEmpty)
                                _InfoRow(
                                  label: 'ใบนำของออก (Gate Pass)',
                                  value: wo.outsource!.gatePassNo!,
                                ),
                              if (wo.status == WorkOrderStatus.completed &&
                                  wo.outsource!.actualReturnDate != null)
                                _InfoRow(
                                  label: 'วันที่รับกลับ',
                                  value: fmt.format(
                                    wo.outsource!.actualReturnDate!,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  // Right Column
                  Expanded(
                    flex: 1,
                    child: Column(
                      children: [
                        _buildInfoCard(
                          title: 'ความสำคัญ',
                          icon: HugeIcons.strokeRoundedAlert02,
                          onEdit: () =>
                              context.push('/work-orders/new', extra: wo),
                          children: [
                            _InfoRow(
                              label: 'ระดับ',
                              value: _priorityLabel(wo.priority),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _buildInfoCard(
                          title: 'เวลาดำเนินการ',
                          icon: HugeIcons.strokeRoundedTime04,
                          onEdit: () =>
                              context.push('/work-orders/new', extra: wo),
                          children: [
                            _InfoRow(
                              label: 'เริ่มซ่อม',
                              value: wo.startedAt != null
                                  ? fmt.format(wo.startedAt!)
                                  : '-',
                            ),
                            _InfoRow(
                              label: 'เสร็จสิ้น',
                              value: wo.completedAt != null
                                  ? fmt.format(wo.completedAt!)
                                  : '-',
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        _WorkOrderPartsCard(
                          woId: wo.woId,
                          machineId: wo.machineId,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppSpacing.xl),
              // Action Buttons
              _buildActionButtons(context, ref, wo, user),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(WorkOrderStatus status) {
    Color bg;
    Color fg;
    switch (status) {
      case WorkOrderStatus.pending:
        bg = Colors.orange.withOpacity(0.1);
        fg = Colors.orange.shade800;
        break;
      case WorkOrderStatus.approved:
        bg = Colors.blue.withOpacity(0.1);
        fg = Colors.blue.shade800;
        break;
      case WorkOrderStatus.inProgress:
        bg = Colors.purple.withOpacity(0.1);
        fg = Colors.purple.shade800;
        break;
      case WorkOrderStatus.completed:
        bg = Colors.green.withOpacity(0.1);
        fg = Colors.green.shade800;
        break;
      case WorkOrderStatus.cancelled:
      case WorkOrderStatus.rejected:
        bg = Colors.red.withOpacity(0.1);
        fg = Colors.red.shade800;
        break;
      case WorkOrderStatus.outsourced:
        bg = Colors.deepOrange.withOpacity(0.1);
        fg = Colors.deepOrange.shade800;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: AppTextStyles.labelMedium.copyWith(
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatRepairDetailsForView(String details) {
    try {
      final decoded = jsonDecode(details);
      if (decoded is List) {
        return decoded
            .map((e) {
              final item = e['item'] ?? '';
              final qty = e['qty']?.toString().trim() ?? '';
              final note = e['note']?.toString().trim() ?? '';
              final parts = <String>[item];
              if (qty.isNotEmpty) parts.add('($qty)');
              if (note.isNotEmpty) parts.add('- $note');
              return parts.join(' ');
            })
            .join('\n');
      }
    } catch (_) {}
    return details;
  }

  String _priorityLabel(WorkOrderPriority p) {
    switch (p) {
      case WorkOrderPriority.low:
        return 'ต่ำ';
      case WorkOrderPriority.normal:
        return 'ปกติ';
      case WorkOrderPriority.high:
        return 'สูง';
      case WorkOrderPriority.urgent:
        return 'ด่วน';
    }
  }

  Widget _buildInfoCard({
    required String title,
    required dynamic icon,
    required List<Widget> children,
    VoidCallback? onEdit,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                icon is IconData
                    ? Icon(icon, color: AppColors.primary, size: 20)
                    : HugeIcon(icon: icon, color: AppColors.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text(title, style: AppTextStyles.titleMedium),
                const Spacer(),
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: onEdit,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    color: AppColors.primary,
                  ),
              ],
            ),
            const Divider(height: AppSpacing.xl),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    WidgetRef ref,
    WorkOrder wo,
    UserSession? user,
  ) {
    final actions = <Widget>[];

    // Status transitions
    if (wo.status == WorkOrderStatus.pending &&
        (user?.isTechnicianOrAbove == true)) {
      actions.add(
        OutlinedButton(
          onPressed: () => _updateStatus(context, ref, wo.woId, 'reject'),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('ปฏิเสธ'),
        ),
      );
      actions.add(const SizedBox(width: AppSpacing.sm));
      actions.add(
        ElevatedButton(
          onPressed: () => _updateStatus(context, ref, wo.woId, 'approve'),
          child: const Text('อนุมัติ / รับงาน'),
        ),
      );
    }

    if (wo.status == WorkOrderStatus.approved &&
        (user?.isTechnicianOrAbove == true)) {
      actions.add(
        ElevatedButton(
          onPressed: () => _updateStatus(context, ref, wo.woId, 'start'),
          child: const Text('เริ่มดำเนินการซ่อม'),
        ),
      );
    }

    if (wo.status == WorkOrderStatus.inProgress &&
        (user?.isTechnicianOrAbove == true)) {
      if (wo.outsource != null) {
        actions.add(
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _showAcceptOutsourceDialog(context, ref, wo.woId),
            child: const Text('รับเครื่องจักร'),
          ),
        );
      } else {
        actions.add(
          OutlinedButton(
            onPressed: () => _showOutsourceDialog(context, ref, wo),
            style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning),
            child: const Text('ส่งซ่อมภายนอก'),
          ),
        );
        actions.add(
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _showCloseJobDialog(context, ref, wo),
            child: const Text('บันทึกปิดงานซ่อม'),
          ),
        );
      }
    }

    if (wo.status == WorkOrderStatus.outsourced &&
        (user?.isTechnicianOrAbove == true)) {
      actions.add(
        OutlinedButton.icon(
          onPressed: () => _printGatePass(context, wo.woId),
          icon: const Icon(Icons.print, size: 18),
          label: const Text('พิมพ์ Gate Pass'),
        ),
      );
      actions.add(
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
          ),
          onPressed: () => _showAcceptOutsourceDialog(context, ref, wo.woId),
          child: const Text('รับเครื่องจักร'),
        ),
      );
    }

    if (actions.isEmpty) return const SizedBox();

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: actions
          .map(
            (w) => Padding(
              padding: const EdgeInsets.only(left: AppSpacing.md),
              child: w,
            ),
          )
          .toList(),
    );
  }

  Future<void> _printGatePass(BuildContext context, String woId) async {
    final row = await DbHelper.queryOne(
      'SELECT vendor_name, repair_details, gate_pass_no, expected_return_date FROM work_order_outsource WHERE wo_id = @id ORDER BY created_at DESC LIMIT 1',
      params: {'id': woId},
    );
    if (row != null) {
      await WorkOrderGatePassPdfService.generateAndOpen(
        woId: woId,
        vendorName: row['vendor_name'] as String? ?? '-',
        repairDetails: row['repair_details'] as String? ?? '-',
        gatePassNo: row['gate_pass_no'] as String?,
        expectedReturnDate: row['expected_return_date'] != null
            ? DateTime.tryParse(row['expected_return_date'] as String)
            : null,
      );
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่พบข้อมูลการส่งซ่อมภายนอก')),
        );
      }
    }
  }

  Future<void> _updateStatus(
    BuildContext context,
    WidgetRef ref,
    String woId,
    String action,
  ) async {
    final repo = ref.read(workOrderRepositoryProvider);
    bool success = false;

    // Show loading indicator in a real app, but for now simple await
    if (action == 'approve') {
      final selectedUserId = await _showAssignDialog(context, ref);
      if (selectedUserId == null) return; // User cancelled

      // Approve and Assign
      success = await repo.approveWorkOrder(
        woId,
        approvedBy: ref.read(authProvider)?.userId,
      );
      if (success) {
        success = await repo.assignWorkOrder(woId, selectedUserId);
      }
    } else if (action == 'reject') {
      success = await repo.rejectWorkOrder(woId);
    } else if (action == 'start') {
      success = await repo.startWorkOrder(woId);
    }

    if (success && context.mounted) {
      ref.invalidate(workOrderProvider(woId));
      // Invalidate list providers
      ref.invalidate(workOrderListProvider);
      ref.invalidate(pendingWorkOrdersCountProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('อัปเดตสถานะสำเร็จ')));
    }
  }

  Future<String?> _showAssignDialog(BuildContext context, WidgetRef ref) async {
    final currentUser = ref.read(authProvider);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('เลือกช่างผู้รับผิดชอบ'),
          content: SizedBox(
            width: 400,
            height: 300,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: DbHelper.query('''SELECT user_id, full_name, role 
                   FROM users 
                   WHERE is_active = 1 
                     AND role IN ('technician', 'engineer')
                   ORDER BY full_name'''),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }

                final users = snapshot.data ?? [];
                if (users.isEmpty) {
                  return const Center(child: Text('ไม่พบช่างในระบบ'));
                }

                return ListView.builder(
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    final u = users[index];
                    final isSelf = u['user_id'] == currentUser?.userId;
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(u['full_name'][0].toUpperCase()),
                      ),
                      title: Text(u['full_name']),
                      subtitle: Text(u['role']),
                      trailing: isSelf
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'ตัวเอง',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 12,
                                ),
                              ),
                            )
                          : null,
                      onTap: () {
                        Navigator.of(context).pop(u['user_id'].toString());
                      },
                    );
                  },
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('ยกเลิก'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showCloseJobDialog(
    BuildContext context,
    WidgetRef ref,
    WorkOrder wo,
  ) async {
    final rootCauseCtrl = TextEditingController();
    final correctionCtrl = TextEditingController();
    final preventiveCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Text('บันทึกปิดงานซ่อม / วิเคราะห์ปัญหา (RCA)'),
          content: SizedBox(
            width: 500,
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: rootCauseCtrl,
                      decoration: const InputDecoration(
                        labelText: 'สาเหตุของปัญหา (Cause) *',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 3,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'กรุณาระบุสาเหตุรากเหง้า'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: correctionCtrl,
                      decoration: const InputDecoration(
                        labelText:
                            'วิธีการแก้ไข / รายละเอียดการซ่อม (Repair Details)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: preventiveCtrl,
                      decoration: const InputDecoration(
                        labelText: 'การป้องกัน (Preventive Action)',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('ยกเลิก'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(context).pop(true);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                foregroundColor: Colors.white,
              ),
              child: const Text('บันทึกข้อมูล'),
            ),
          ],
        );
      },
    );

    if (result == true && context.mounted) {
      final repo = ref.read(workOrderRepositoryProvider);

      // Save RCA
      final rcaSuccess = await repo.saveRCA(
        woId: wo.woId,
        why1: '',
        why2: '',
        why3: '',
        why4: '',
        why5: '', // Simplify 5 whys for now
        rootCause: rootCauseCtrl.text,
        correctionAction: correctionCtrl.text,
        preventiveAction: preventiveCtrl.text,
      );

      if (rcaSuccess) {
        // Complete Job
        double hours = 1.0;
        if (wo.startedAt != null) {
          hours = DateTime.now().difference(wo.startedAt!).inMinutes / 60.0;
          if (hours <= 0) hours = 0.1;
        }

        final completeSuccess = await repo.completeWorkOrder(
          wo.woId,
          closureNotes: correctionCtrl.text,
          actualHours: hours,
          isBreakdown: true,
        );

        if (completeSuccess && context.mounted) {
          ref.invalidate(workOrderProvider(woId));
          ref.invalidate(workOrderListProvider);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('ปิดงานสำเร็จ')));
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก RCA')),
          );
        }
      }
    }
  }

  Future<void> _showOutsourceDialog(
    BuildContext context,
    WidgetRef ref,
    WorkOrder wo,
  ) async {
    final woId = wo.woId;
    final vendors = await DbHelper.query(
      '''SELECT supplier_id, supplier_code, name, service_scope
        FROM suppliers WHERE is_outsource_vendor = 1 AND vendor_type = 'repair'
        AND is_active = 1 AND is_approved = 1 ORDER BY name''',
    );
    if (!context.mounted) return;
    String? selectedVendorId;
    final rootCauseCtrl = TextEditingController(text: wo.rca?.rootCause ?? '');
    List<Map<String, String>> outsourceItems = [
      {'item': '', 'qty': '', 'note': ''},
    ];
    final partsCtrl = TextEditingController();
    DateTime? selectedExpectedDate;
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('ข้อมูลการส่งซ่อมภายนอก'),
              content: SizedBox(
                width: 500,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedVendorId,
                          decoration: const InputDecoration(
                            labelText: 'ผู้รับเหมาซ่อมภายนอก *',
                            border: OutlineInputBorder(),
                          ),
                          hint: Text(
                            vendors.isEmpty
                                ? 'ยังไม่มีผู้รับเหมาที่อนุมัติแล้ว'
                                : 'เลือกจากทะเบียนผู้รับเหมา',
                          ),
                          items: vendors
                              .map(
                                (vendor) => DropdownMenuItem<String>(
                                  value: vendor['supplier_id'] as String,
                                  child: Text(
                                    '${vendor['supplier_code']} - ${vendor['name']}',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: vendors.isEmpty
                              ? null
                              : (value) =>
                                    setState(() => selectedVendorId = value),
                          validator: (v) =>
                              v == null ? 'กรุณาเลือกผู้รับเหมา' : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: rootCauseCtrl,
                          decoration: const InputDecoration(
                            labelText: 'สาเหตุของอาการที่เสีย *',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'กรุณาระบุสาเหตุของอาการที่เสีย'
                              : null,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const SizedBox(height: AppSpacing.md),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'รายการที่ส่งซ่อม *',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ...outsourceItems.asMap().entries.map((e) {
                          final index = e.key;
                          final item = e.value;
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    initialValue: item['item'],
                                    decoration: const InputDecoration(
                                      labelText: 'รายการ *',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) => item['item'] = val,
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                        ? 'ระบุรายการ'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  flex: 1,
                                  child: TextFormField(
                                    initialValue: item['qty'],
                                    decoration: const InputDecoration(
                                      labelText: 'จำนวน',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) => item['qty'] = val,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    initialValue: item['note'],
                                    decoration: const InputDecoration(
                                      labelText: 'หมายเหตุ',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) => item['note'] = val,
                                  ),
                                ),
                                if (outsourceItems.length > 1)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => outsourceItems.removeAt(index),
                                      );
                                    },
                                  )
                                else
                                  const SizedBox(width: 48),
                              ],
                            ),
                          );
                        }),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () {
                              setState(
                                () => outsourceItems.add({
                                  'item': '',
                                  'qty': '',
                                  'note': '',
                                }),
                              );
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('เพิ่มรายการ'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: partsCtrl,
                          decoration: const InputDecoration(
                            labelText: 'อะไหล่ที่เปลี่ยน (ถ้าทราบ)',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate:
                                  selectedExpectedDate ?? DateTime.now(),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (date != null) {
                              setState(() => selectedExpectedDate = date);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'วันที่คาดว่าจะเสร็จ',
                              border: OutlineInputBorder(),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  selectedExpectedDate != null
                                      ? DateFormat(
                                          'dd MMM yyyy',
                                          'th',
                                        ).format(selectedExpectedDate!)
                                      : 'ยังไม่กำหนด',
                                ),
                                const Icon(Icons.calendar_today, size: 18),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  child: const Text('บันทึกส่งซ่อม'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && context.mounted) {
      final repo = ref.read(workOrderRepositoryProvider);

      final validItems = outsourceItems
          .where((e) => e['item']!.trim().isNotEmpty)
          .toList();
      final repairDetailsJson = jsonEncode(validItems);

      final success = await repo.outsourceWorkOrder(
        woId: woId,
        vendorName:
            vendors.firstWhere(
                  (vendor) => vendor['supplier_id'] == selectedVendorId,
                )['name']
                as String,
        repairDetails: repairDetailsJson,
        replacedParts: partsCtrl.text,
        rootCause: rootCauseCtrl.text,
        gatePassNo: null,
        expectedReturnDate: selectedExpectedDate,
      );

      if (success && context.mounted) {
        ref.invalidate(workOrderProvider(woId));
        ref.invalidate(workOrderListProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกการส่งซ่อมภายนอกสำเร็จ')),
        );
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก')),
          );
        }
      }
    }
  }

  Future<void> _showEditRepairLogDialog(
    BuildContext context,
    WidgetRef ref,
    WorkOrder wo,
  ) async {
    final rootCauseCtrl = TextEditingController(text: wo.rca?.rootCause ?? '');
    final correctionCtrl = TextEditingController(text: wo.closureNotes ?? '');
    final formKey = GlobalKey<FormState>();

    String? selectedFailureType = wo.rca?.failureType;
    String? selectedCauseCategory = wo.rca?.causeCategory;

    final failureCategories = [
      'ระบบไฟฟ้า/อิเล็กทรอนิกส์ (Electrical)',
      'ระบบเครื่องกล/กลไก (Mechanical)',
      'ระบบท่อ/ของเหลว/ลม (Hydraulic/Pneumatic)',
      'ระบบซอฟต์แวร์/เซนเซอร์ (Control/Software)',
      'โครงสร้าง/ตัวถังภายนอก (Structural)',
      'อะไหล่สิ้นเปลือง/วัสดุสิ้นเปลือง (Consumables)',
      'บำรุงรักษาเชิงป้องกัน (PM)',
      'อื่นๆ (Others)',
    ];

    if (selectedFailureType != null &&
        selectedFailureType.isNotEmpty &&
        !failureCategories.contains(selectedFailureType)) {
      failureCategories.add(selectedFailureType);
    }

    final causeCategories = [
      'เสื่อมสภาพตามอายุ (Normal Wear & Tear)',
      'ขาดการบำรุงรักษา (Lack of Maintenance)',
      'ใช้งานผิดวิธี (Misuse / Operator Error)',
      'วัสดุ/ชิ้นส่วนไม่ได้มาตรฐาน (Substandard Parts)',
      'ปัจจัยภายนอก/อุบัติเหตุ (External/Accident)',
      'อื่นๆ (Others)',
    ];

    if (selectedCauseCategory != null &&
        selectedCauseCategory.isNotEmpty &&
        !causeCategories.contains(selectedCauseCategory)) {
      causeCategories.add(selectedCauseCategory);
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('บันทึกผลการซ่อม (Repair Log)'),
              content: SizedBox(
                width: 600,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          value: selectedFailureType,
                          decoration: const InputDecoration(
                            labelText: 'หมวดหมู่อาการเสีย (Failure Category)',
                            border: OutlineInputBorder(),
                          ),
                          items: failureCategories
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => selectedFailureType = v),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DropdownButtonFormField<String>(
                          value: selectedCauseCategory,
                          decoration: const InputDecoration(
                            labelText:
                                'หมวดหมู่สาเหตุหลัก (Root Cause Category)',
                            border: OutlineInputBorder(),
                          ),
                          items: causeCategories
                              .map(
                                (c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(
                                    c,
                                    style: const TextStyle(fontSize: 14),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setState(() => selectedCauseCategory = v),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        TextFormField(
                          controller: rootCauseCtrl,
                          decoration: const InputDecoration(
                            labelText: 'รายละเอียดเพิ่มเติม (Remarks)',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: correctionCtrl,
                          decoration: const InputDecoration(
                            labelText: 'วิธีการแก้ไข / การซ่อม',
                            border: OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('บันทึกข้อมูล'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && context.mounted) {
      final repo = ref.read(workOrderRepositoryProvider);

      final rcaSuccess = await repo.saveRCA(
        woId: wo.woId,
        why1: '',
        why2: '',
        why3: '',
        why4: '',
        why5: '',
        rootCause: rootCauseCtrl.text,
        failureType: selectedFailureType,
        causeCategory: selectedCauseCategory,
      );

      if (rcaSuccess) {
        await repo.updateRepairLog(
          wo.woId,
          rootCauseCtrl.text,
          correctionCtrl.text,
        );
        ref.invalidate(workOrderProvider(wo.woId));
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('บันทึกการซ่อมสำเร็จ')));
        }
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก RCA')),
          );
        }
      }
    }
  }

  Future<void> _showEditOutsourceDialog(
    BuildContext context,
    WidgetRef ref,
    WorkOrder wo,
  ) async {
    final formKey = GlobalKey<FormState>();
    List<Map<String, dynamic>> outsourceItems = [
      {'item': '', 'qty': '', 'note': ''},
    ];
    DateTime? selectedExpectedDate = wo.outsource?.expectedReturnDate;
    final notesCtrl = TextEditingController(text: wo.outsource?.notes ?? '');

    if (wo.outsource?.repairDetails != null &&
        wo.outsource!.repairDetails!.isNotEmpty) {
      try {
        final decoded = jsonDecode(wo.outsource!.repairDetails!);
        if (decoded is List) {
          outsourceItems = decoded
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
          if (outsourceItems.isEmpty)
            outsourceItems = [
              {'item': '', 'qty': '', 'note': ''},
            ];
        }
      } catch (_) {}
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('แก้ไขข้อมูลการส่งซ่อมภายนอก'),
              content: SizedBox(
                width: 600,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'รายการที่ส่งซ่อม',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        ...List.generate(outsourceItems.length, (index) {
                          final item = outsourceItems[index];
                          return Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    initialValue: item['item'],
                                    decoration: const InputDecoration(
                                      labelText: 'รายการ *',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) => item['item'] = val,
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                        ? 'ระบุรายการ'
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  flex: 1,
                                  child: TextFormField(
                                    initialValue: item['qty'],
                                    decoration: const InputDecoration(
                                      labelText: 'จำนวน',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) => item['qty'] = val,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  flex: 2,
                                  child: TextFormField(
                                    initialValue: item['note'],
                                    decoration: const InputDecoration(
                                      labelText: 'หมายเหตุ',
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) => item['note'] = val,
                                  ),
                                ),
                                if (outsourceItems.length > 1)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: () {
                                      setState(
                                        () => outsourceItems.removeAt(index),
                                      );
                                    },
                                  )
                                else
                                  const SizedBox(width: 48),
                              ],
                            ),
                          );
                        }),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: () {
                              setState(
                                () => outsourceItems.add({
                                  'item': '',
                                  'qty': '',
                                  'note': '',
                                }),
                              );
                            },
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('เพิ่มรายการ'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        InkWell(
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate:
                                  selectedExpectedDate ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(
                                const Duration(days: 30),
                              ),
                              lastDate: DateTime.now().add(
                                const Duration(days: 365),
                              ),
                            );
                            if (date != null) {
                              setState(() => selectedExpectedDate = date);
                            }
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'วันที่คาดว่าจะเสร็จ',
                              border: OutlineInputBorder(),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  selectedExpectedDate != null
                                      ? DateFormat(
                                          'dd MMM yyyy',
                                          'th',
                                        ).format(selectedExpectedDate!)
                                      : 'ยังไม่กำหนด',
                                ),
                                const Icon(Icons.calendar_today, size: 18),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: notesCtrl,
                          decoration: const InputDecoration(
                            labelText: 'หมายเหตุเพิ่มเติม',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Navigator.of(context).pop(true);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('บันทึกข้อมูล'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true &&
        context.mounted &&
        wo.outsource?.outsourceId != null) {
      final repo = ref.read(workOrderRepositoryProvider);
      final validItems = outsourceItems
          .where((e) => e['item']!.trim().isNotEmpty)
          .toList();
      final repairDetailsJson = jsonEncode(validItems);

      final success = await repo.updateOutsourceInfo(
        wo.outsource!.outsourceId,
        repairDetailsJson,
        selectedExpectedDate,
        notesCtrl.text,
      );

      if (success && context.mounted) {
        ref.invalidate(workOrderProvider(wo.woId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('แก้ไขข้อมูลส่งซ่อมสำเร็จ')),
        );
      } else if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก')),
        );
      }
    }
  }

  Future<void> _showAcceptOutsourceDialog(
    BuildContext context,
    WidgetRef ref,
    String woId,
  ) async {
    final notesCtrl = TextEditingController();
    DateTime? selectedDate = DateTime.now();
    bool isPassed = true;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('ตรวจรับงานซ่อมภายนอก'),
              content: SizedBox(
                width: 400,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: selectedDate ?? DateTime.now(),
                            firstDate: DateTime.now().subtract(
                              const Duration(days: 30),
                            ),
                            lastDate: DateTime.now(),
                          );
                          if (date != null) {
                            setState(() => selectedDate = date);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'วันที่ได้รับของ/ตรวจรับ',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            selectedDate != null
                                ? '${selectedDate!.day}/${selectedDate!.month}/${selectedDate!.year}'
                                : 'เลือกวันที่',
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<bool>(
                              title: const Text(
                                'ใช้งานได้ปกติ (ซ่อมเสร็จสิ้น)',
                              ),
                              value: true,
                              groupValue: isPassed,
                              onChanged: (val) {
                                if (val != null) setState(() => isPassed = val);
                              },
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<bool>(
                              title: const Text(
                                'ใช้งานไม่ได้ (ตีกลับซ่อมใหม่)',
                              ),
                              value: false,
                              groupValue: isPassed,
                              onChanged: (val) {
                                if (val != null) setState(() => isPassed = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextFormField(
                        controller: notesCtrl,
                        decoration: InputDecoration(
                          labelText: isPassed
                              ? 'หมายเหตุการตรวจรับ'
                              : 'ระบุอาการที่ยังเสียอยู่',
                          border: const OutlineInputBorder(),
                        ),
                        maxLines: 3,
                        validator: (val) {
                          if (!isPassed &&
                              (val == null || val.trim().isEmpty)) {
                            return 'กรุณาระบุอาการที่ยังเสียอยู่';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('ยกเลิก'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (selectedDate == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('กรุณาระบุวันที่ได้รับของ'),
                        ),
                      );
                      return;
                    }
                    if (!isPassed && notesCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('กรุณาระบุอาการที่ยังเสียอยู่'),
                        ),
                      );
                      return;
                    }
                    Navigator.of(
                      context,
                    ).pop({'date': selectedDate, 'isPassed': isPassed});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isPassed
                        ? AppColors.success
                        : AppColors.error,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    isPassed
                        ? 'ยืนยันรับของและปิดงาน'
                        : 'บันทึกและตีกลับซ่อมใหม่',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (result != null && context.mounted) {
      final selectedDate = result['date'] as DateTime;
      final isPassed = result['isPassed'] as bool;
      final repo = ref.read(workOrderRepositoryProvider);

      final success = await repo.acceptOutsourceWorkOrder(
        woId: woId,
        actualReturnDate: selectedDate,
        notes: notesCtrl.text,
        isPassed: isPassed,
      );

      if (success && context.mounted) {
        ref.invalidate(workOrderProvider(woId));
        ref.invalidate(workOrderListProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isPassed
                  ? 'ตรวจรับและปิดงานสำเร็จ'
                  : 'บันทึกตีกลับซ่อมใหม่สำเร็จ (สถานะ: ส่งซ่อมภายนอก)',
            ),
          ),
        );
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก')),
          );
        }
      }
    }
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTextStyles.bodyMedium.copyWith(
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTextStyles.bodyMedium.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkOrderPartsCard extends ConsumerWidget {
  final String woId;
  final String? machineId;

  const _WorkOrderPartsCard({required this.woId, this.machineId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partsAsync = ref.watch(workOrderPartsProvider(woId));

    return Card(
      elevation: 0,
      color: Colors.grey.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 20,
                  color: AppColors.primary,
                ),
                const SizedBox(width: AppSpacing.sm),
                const Text(
                  'รายการอะไหล่ที่ใช้',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(
                    Icons.add_circle_outline,
                    size: 20,
                    color: AppColors.primary,
                  ),
                  tooltip: 'เบิกอะไหล่เพิ่ม',
                  onPressed: () async {
                    if (machineId == null || machineId!.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'กรุณาระบุเครื่องจักรในใบแจ้งซ่อมก่อนเบิกอะไหล่',
                          ),
                        ),
                      );
                      return;
                    }
                    final res = await showDialog(
                      context: context,
                      builder: (c) =>
                          AddWoPartDialog(woId: woId, machineId: machineId!),
                    );
                    if (res == true) {
                      ref.invalidate(workOrderPartsProvider(woId));
                    }
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.print_outlined, size: 20),
                  tooltip: 'พิมพ์ใบเบิกอะไหล่',
                  onPressed: () {
                    WorkOrderPdfService.generateSparePartRequisition(
                      woId: woId,
                    );
                  },
                ),
              ],
            ),
            const Divider(),
            partsAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (e, st) => Text('Error: $e'),
              data: (parts) {
                if (parts.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'ยังไม่มีการเบิกอะไหล่',
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  );
                }
                return Column(
                  children: parts.asMap().entries.map((e) {
                    final index = e.key + 1;
                    final p = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$index. ${p.partName ?? "-"}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                Text(
                                  '(${p.partCode ?? "-"})',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${p.quantity} ชิ้น',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (c) => AlertDialog(
                                  title: const Text('ยืนยันการคืนอะไหล่?'),
                                  content: Text(
                                    'คุณต้องการคืน ${p.partName} จำนวน ${p.quantity} ชิ้น กลับเข้าคลังใช่หรือไม่?',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, false),
                                      child: const Text('ยกเลิก'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(c, true),
                                      child: const Text(
                                        'ยืนยันคืนอะไหล่',
                                        style: TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                final success = await ref
                                    .read(workOrderRepositoryProvider)
                                    .removePartFromWorkOrder(p.woPartId);
                                if (success) {
                                  ref.invalidate(workOrderPartsProvider(woId));
                                } else {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'เกิดข้อผิดพลาดในการคืนอะไหล่',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              }
                            },
                            child: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
