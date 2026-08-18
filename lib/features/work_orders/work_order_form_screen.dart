import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/database/db_helper.dart';
import '../../features/auth/auth_provider.dart';
import '../machine_intake/machine_provider.dart';
import 'work_order_models.dart';
import 'work_order_provider.dart';

enum _WorkType { machine, facility }

class WorkOrderFormScreen extends ConsumerStatefulWidget {
  final WorkOrder? workOrder;

  const WorkOrderFormScreen({super.key, this.workOrder});

  @override
  ConsumerState<WorkOrderFormScreen> createState() =>
      _WorkOrderFormScreenState();
}

class _WorkOrderFormScreenState extends ConsumerState<WorkOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _symptomCtrl = TextEditingController();

  _WorkType _workType = _WorkType.machine;
  String? _selectedMachineId;
  WorkOrderPriority _priority = WorkOrderPriority.normal;
  bool _isSaving = false;
  List<Map<String, dynamic>> _machines = [];
  final List<String> _attachments = [];

  @override
  void initState() {
    super.initState();
    _loadMachines();

    if (widget.workOrder != null) {
      _workType = widget.workOrder!.machineId == null
          ? _WorkType.facility
          : _WorkType.machine;
      _selectedMachineId = widget.workOrder!.machineId;
      _descCtrl.text = widget.workOrder!.description ?? '';
      _symptomCtrl.text = widget.workOrder!.failureSymptom ?? '';
      _priority = widget.workOrder!.priority;
    }
  }

  Future<void> _loadMachines() async {
    final results = await DbHelper.query(
      'SELECT machine_id, machine_no, machine_name as name FROM machines ORDER BY machine_no',
    );
    setState(() {
      _machines = results;
    });
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _symptomCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx'],
    );
    if (result != null) {
      setState(() {
        for (final file in result.files) {
          if (file.path != null && !_attachments.contains(file.path!)) {
            _attachments.add(file.path!);
          }
        }
      });
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      _attachments.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_workType == _WorkType.machine && _selectedMachineId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณาเลือกเครื่องจักร')));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final user = ref.read(authProvider);
      if (user == null) throw Exception('User not logged in');
      final workOrderRepo = WorkOrderRepository();

      String createdId;
      if (widget.workOrder != null) {
        // Update existing
        createdId = widget.workOrder!.woId;

        // Process attachments for update
        List<String>? currentAttachments =
            widget.workOrder!.attachments?.toList() ?? [];
        if (_attachments.isNotEmpty) {
          for (final path in _attachments) {
            if (!currentAttachments.contains(path)) {
              currentAttachments.add(path);
            }
          }
        }
        final savedAttachments = await workOrderRepo.updateAttachments(
          createdId,
          currentAttachments,
        );
        final attachmentsJson =
            savedAttachments != null && savedAttachments.isNotEmpty
            ? jsonEncode(savedAttachments)
            : null;

        String? snapshotId;
        if (_workType == _WorkType.machine && _selectedMachineId != null) {
          snapshotId = await MachineRepository().getOrCreateSnapshot(
            _selectedMachineId!,
          );
        }
        await DbHelper.execute(
          '''
          UPDATE work_orders SET 
            machine_id = @mid,
            snapshot_id = @sid,
            title = @desc,
            description = @desc,
            failure_symptom = @sym,
            priority = @prio,
            updated_at = CURRENT_TIMESTAMP,
            attachments = @atts
          WHERE wo_id = @id
          ''',
          params: {
            'id': createdId,
            'mid': _workType == _WorkType.machine ? _selectedMachineId : null,
            'sid': snapshotId,
            'desc': _descCtrl.text,
            'sym': _symptomCtrl.text,
            'prio': _priority.dbValue,
            'atts': attachmentsJson,
          },
        );
      } else {
        // Insert new
        final user = ref.read(authProvider);
        if (user == null) {
          throw Exception('ไม่พบข้อมูลผู้ใช้งาน (Session Expired)');
        }

        createdId = await workOrderRepo.createWorkOrder(
          machineId: _workType == _WorkType.machine ? _selectedMachineId! : '',
          machineNo: _workType == _WorkType.machine
              ? _selectedMachineId!
              : '', // createWorkOrder will get proper snapshot
          description: _descCtrl.text,
          failureSymptom: _symptomCtrl.text,
          priority: _priority,
          attachments: _attachments,
          userId: user.userId,
        );
      }

      ref.invalidate(workOrderListProvider);
      if (mounted) {
        context.go('/work-orders/$createdId');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกใบแจ้งซ่อมเรียบร้อยแล้ว')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.workOrder != null
              ? 'แก้ไขใบแจ้งซ่อม ${widget.workOrder!.woNo}'
              : 'สร้างใบแจ้งซ่อม (Work Order)',
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<_WorkType>(
                segments: const [
                  ButtonSegment(
                    value: _WorkType.machine,
                    label: Text('งานเครื่องจักร'),
                    icon: Icon(Icons.precision_manufacturing, size: 18),
                  ),
                  ButtonSegment(
                    value: _WorkType.facility,
                    label: Text('งานอาคาร / ทั่วไป'),
                    icon: Icon(Icons.domain, size: 18),
                  ),
                ],
                selected: {_workType},
                onSelectionChanged: (Set<_WorkType> newSelection) {
                  setState(() {
                    _workType = newSelection.first;
                    if (_workType == _WorkType.facility) {
                      _selectedMachineId = null;
                    }
                  });
                },
              ),
              const SizedBox(height: AppSpacing.lg),

              if (_workType == _WorkType.machine) ...[
                Text(
                  'เครื่องจักรที่ต้องการแจ้งซ่อม *',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String>(
                  value: _selectedMachineId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  hint: const Text('เลือกเครื่องจักร'),
                  items: _machines.map((m) {
                    return DropdownMenuItem<String>(
                      value: m['machine_id'] as String,
                      child: Text('${m['machine_no']} - ${m['name']}'),
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedMachineId = val),
                  validator: (val) =>
                      val == null ? 'กรุณาเลือกเครื่องจักร' : null,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              Text(
                'อาการเบื้องต้น / ปัญหาที่พบ *',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _symptomCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'เช่น มอเตอร์มีเสียงดัง, เครื่องไม่ทำงาน',
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'กรุณาระบุอาการเสีย' : null,
              ),
              const SizedBox(height: AppSpacing.lg),

              Text(
                'รายละเอียดเพิ่มเติม (ถ้ามี)',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'รายละเอียดเพิ่มเติมเกี่ยวกับการซ่อมบำรุง',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              Text(
                'ความเร่งด่วน',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.md,
                children: WorkOrderPriority.values.map((prio) {
                  return ChoiceChip(
                    label: Text(prio.label),
                    selected: _priority == prio,
                    onSelected: (selected) {
                      if (selected) setState(() => _priority = prio);
                    },
                    selectedColor: prio == WorkOrderPriority.urgent
                        ? AppColors.error.withValues(alpha: 0.1)
                        : (prio == WorkOrderPriority.high
                              ? AppColors.warning.withValues(alpha: 0.1)
                              : AppColors.primary.withValues(alpha: 0.1)),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.lg),

              Text(
                'แนบไฟล์ / รูปภาพ (ถ้ามี)',
                style: AppTextStyles.labelMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.attach_file),
                label: const Text('เลือกไฟล์'),
              ),
              if (_attachments.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _attachments.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final path = _attachments[index];
                      final fileName = p.basename(path);
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.insert_drive_file, size: 20),
                        title: Text(
                          fileName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => _removeAttachment(index),
                          color: AppColors.error,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 40),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('บันทึกใบแจ้งซ่อม'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
