import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:masapp/core/theme/app_colors.dart';
import 'package:masapp/core/theme/app_spacing.dart';
import 'package:masapp/core/theme/app_text_styles.dart';
import 'package:masapp/features/auth/auth_provider.dart';
import 'package:masapp/core/database/db_helper.dart';
import 'package:masapp/features/work_orders/work_order_models.dart';
import 'package:masapp/features/work_orders/work_order_provider.dart';
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
                      if (wo.attachments != null && wo.attachments!.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.md),
                        const Divider(),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'ไฟล์แนบ:',
                          style: AppTextStyles.labelMedium,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: wo.attachments!.map((path) {
                            final fileName = p.basename(path);
                            return ActionChip(
                              avatar: const Icon(Icons.attach_file, size: 16),
                              label: Text(fileName, style: const TextStyle(fontSize: 12)),
                              onPressed: () {
                                OpenFilex.open(path);
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
                        if (wo.rca != null || (wo.closureNotes != null && wo.closureNotes!.isNotEmpty)) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _buildInfoCard(
                            title: 'บันทึกการซ่อม (ช่างซ่อมบำรุง)',
                            icon: HugeIcons.strokeRoundedWrench01,
                            children: [
                              if (wo.rca?.rootCause != null && wo.rca!.rootCause!.isNotEmpty)
                                _InfoRow(
                                  label: 'สาเหตุของปัญหา',
                                  value: wo.rca!.rootCause!,
                                ),
                              if (wo.closureNotes != null && wo.closureNotes!.isNotEmpty)
                                _InfoRow(
                                  label: 'รายละเอียดการซ่อม',
                                  value: wo.closureNotes!,
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
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                HugeIcon(icon: icon, color: AppColors.primary, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Text(title, style: AppTextStyles.titleMedium),
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
        OutlinedButton(
          onPressed: () => _showOutsourceDialog(context, ref, wo),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.warning),
          child: const Text('ส่งซ่อมภายนอก'),
        ),
      );
      actions.add(
        ElevatedButton(
          onPressed: () => _updateStatus(context, ref, wo.woId, 'start'),
          child: const Text('เริ่มดำเนินการซ่อม'),
        ),
      );
    }

    if (wo.status == WorkOrderStatus.inProgress &&
        (user?.isTechnicianOrAbove == true)) {
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
          child: const Text('ตรวจรับงานซ่อม'),
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
                     AND role IN ('technician', 'engineer', 'safety', 'admin')
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
                        labelText: 'วิธีการแก้ไข / รายละเอียดการซ่อม (Repair Details)',
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
    final repairCtrl = TextEditingController();
    final partsCtrl = TextEditingController();
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
                        TextFormField(
                          controller: repairCtrl,
                          decoration: const InputDecoration(
                            labelText: 'อาการเสีย/รายการที่ซ่อม *',
                            border: OutlineInputBorder(),
                          ),
                          maxLines: 2,
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'กรุณาระบุรายการซ่อม'
                              : null,
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

      final success = await repo.outsourceWorkOrder(
        woId: woId,
        vendorName:
            vendors.firstWhere(
                  (vendor) => vendor['supplier_id'] == selectedVendorId,
                )['name']
                as String,
        repairDetails: repairCtrl.text,
        replacedParts: partsCtrl.text,
        rootCause: rootCauseCtrl.text,
        gatePassNo: null,
        expectedReturnDate: null,
      );

      if (success && context.mounted) {
        await WorkOrderGatePassPdfService.generateAndOpen(
          woId: woId,
          vendorName:
              vendors.firstWhere(
                    (vendor) => vendor['supplier_id'] == selectedVendorId,
                  )['name']
                  as String,
          repairDetails: repairCtrl.text,
          gatePassNo: null,
          expectedReturnDate: null,
        );
        if (!context.mounted) return;
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

  Future<void> _showAcceptOutsourceDialog(
    BuildContext context,
    WidgetRef ref,
    String woId,
  ) async {
    final notesCtrl = TextEditingController();
    DateTime? selectedDate = DateTime.now();

    final result = await showDialog<bool>(
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
                      TextFormField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'หมายเหตุการตรวจรับ',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
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
                    if (selectedDate != null) {
                      Navigator.of(context).pop(true);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('กรุณาระบุวันที่ได้รับของ'),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('ยืนยันรับของและปิดงาน'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && context.mounted && selectedDate != null) {
      final repo = ref.read(workOrderRepositoryProvider);

      final success = await repo.acceptOutsourceWorkOrder(
        woId: woId,
        actualReturnDate: selectedDate!,
        notes: notesCtrl.text,
      );

      if (success && context.mounted) {
        ref.invalidate(workOrderProvider(woId));
        ref.invalidate(workOrderListProvider);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ตรวจรับและปิดงานสำเร็จ')));
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

