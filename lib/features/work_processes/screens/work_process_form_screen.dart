import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../../core/database/db_helper.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/ai/vector_db_service.dart';
import '../models/work_process_model.dart';
import '../models/work_process_step_model.dart';
import '../providers/work_process_provider.dart';
import '../../settings/settings_provider.dart';

class WorkProcessFormScreen extends ConsumerStatefulWidget {
  final String? processId;
  final String? initialMachineId;
  const WorkProcessFormScreen({super.key, this.processId, this.initialMachineId});

  @override
  ConsumerState<WorkProcessFormScreen> createState() =>
      _WorkProcessFormScreenState();
}

class _WorkProcessFormScreenState extends ConsumerState<WorkProcessFormScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _processNoCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  final _companyCtrl = TextEditingController();
  final _factoryCtrl = TextEditingController();
  final _deptCtrl = TextEditingController();
  final _preparedByCtrl = TextEditingController();
  final _preparedDateCtrl = TextEditingController();
  final _approvedByCtrl = TextEditingController();
  final _approvedDateCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  WorkProcessMethodType _methodType = WorkProcessMethodType.current;
  WorkTypeCategory _workType = WorkTypeCategory.man;
  String? _selectedMachineId;
  String? _parentProcessId;

  List<WorkProcessStep> _steps = [];
  List<Map<String, dynamic>> _machines = [];
  bool _loading = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _processNoCtrl.dispose();
    _titleCtrl.dispose();
    _companyCtrl.dispose();
    _factoryCtrl.dispose();
    _deptCtrl.dispose();
    _preparedByCtrl.dispose();
    _preparedDateCtrl.dispose();
    _approvedByCtrl.dispose();
    _approvedDateCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _loading = true);
    try {
      final machines = await DbHelper.query(
        'SELECT machine_id, machine_no, machine_name FROM machines WHERE is_active = 1 ORDER BY machine_no ASC',
      );
      setState(() => _machines = machines);

      if (widget.processId != null && widget.processId!.isNotEmpty) {
        final process = await ref
            .read(workProcessListProvider.notifier)
            .getProcessById(widget.processId!);

        if (process != null) {
          _processNoCtrl.text = process.processNo;
          _titleCtrl.text = process.title;
          _companyCtrl.text = process.company ?? '';
          _factoryCtrl.text = process.factory ?? '';
          _deptCtrl.text = process.department ?? '';
          _preparedByCtrl.text = process.preparedBy ?? '';
          _preparedDateCtrl.text = process.preparedDate ?? '';
          _approvedByCtrl.text = process.approvedBy ?? '';
          _approvedDateCtrl.text = process.approvedDate ?? '';
          _notesCtrl.text = process.notes ?? '';
          _methodType = process.methodType;
          _workType = process.workType;
          _selectedMachineId = process.machineId;
          _parentProcessId = process.parentProcessId;
          _steps = List.from(process.steps);
        }
      } else {
        // Default new record from organization settings
        final settings = ref.read(appSettingsProvider).valueOrNull;
        final orgName = settings?.get(AppSettingKeys.orgName, defaultValue: 'บริษัท บอส คาร์ตัน จำกัด') ?? 'บริษัท บอส คาร์ตัน จำกัด';
        final orgPlant = settings?.get(AppSettingKeys.orgPlant, defaultValue: 'โรงงานลาดหลุมแก้ว') ?? 'โรงงานลาดหลุมแก้ว';
        final orgDept = settings?.get(AppSettingKeys.orgDepartment, defaultValue: 'หน่วยงานซ่อมบำรุง (Maintenance)') ?? 'หน่วยงานซ่อมบำรุง (Maintenance)';

        _companyCtrl.text = orgName;
        _factoryCtrl.text = orgPlant;
        _deptCtrl.text = orgDept;

        if (widget.initialMachineId != null) {
          _selectedMachineId = widget.initialMachineId;
          final matchMc = machines.where((m) => m['machine_id'].toString() == widget.initialMachineId).firstOrNull;
          if (matchMc != null) {
            _titleCtrl.text = 'ขั้นตอนการปฏิบัติงาน ${matchMc['machine_name'] ?? ''} (${matchMc['machine_no']})';
          }
        }

        final nowStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
        _processNoCtrl.text = 'PROC-${DateFormat('yyMMdd-HHmm').format(DateTime.now())}';
        _preparedDateCtrl.text = nowStr;
        _steps = [
          WorkProcessStep(
            stepId: const Uuid().v4(),
            processId: '',
            stepNo: 1,
            description: 'เตรียมชิ้นงานและเครื่องมือ',
            eventType: ProcessEventType.operation,
            durationMinutes: 5.0,
            valueType: LeanValueType.va,
            createdAt: DateTime.now(),
          ),
          WorkProcessStep(
            stepId: const Uuid().v4(),
            processId: '',
            stepNo: 2,
            description: 'ตรวจสอบความพร้อมและเริ่มเดินเครื่อง',
            eventType: ProcessEventType.operation,
            durationMinutes: 10.0,
            valueType: LeanValueType.va,
            createdAt: DateTime.now(),
          ),
          WorkProcessStep(
            stepId: const Uuid().v4(),
            processId: '',
            stepNo: 3,
            description: 'รอคอยการตรวจสอบคุณภาพ',
            eventType: ProcessEventType.delay,
            durationMinutes: 10.0,
            valueType: LeanValueType.nva,
            problemCause: 'ไม่มีพนักงานตรวจสอบประจำจุด',
            improvementIdea: 'รวมขั้นตอนตรวจสอบเข้ากับผู้ปฏิบัติงาน (Self-inspection)',
            createdAt: DateTime.now(),
          ),
        ];
      }
    } catch (e) {
      debugPrint('Error loading process: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addStep() {
    setState(() {
      final nextNo = _steps.length + 1;
      _steps.add(
        WorkProcessStep(
          stepId: const Uuid().v4(),
          processId: widget.processId ?? '',
          stepNo: nextNo,
          description: '',
          eventType: ProcessEventType.operation,
          durationMinutes: 1.0,
          valueType: LeanValueType.va,
          createdAt: DateTime.now(),
        ),
      );
    });
  }

  void _removeStep(int index) {
    setState(() {
      _steps.removeAt(index);
    });
  }

  void _moveStep(int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= _steps.length) return;
    setState(() {
      final item = _steps.removeAt(index);
      _steps.insert(newIndex, item);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('กรุณาเพิ่มขั้นตอนการทำงานอย่างน้อย 1 ขั้นตอน'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final selectedMc = _machines
          .where((m) => m['machine_id'].toString() == _selectedMachineId)
          .firstOrNull;

      final autoTitle = _titleCtrl.text.trim().isNotEmpty
          ? _titleCtrl.text.trim()
          : (selectedMc != null
              ? 'ขั้นตอนการปฏิบัติงาน ${selectedMc['machine_name'] ?? ''} (${selectedMc['machine_no']})'
              : 'ขั้นตอนการปฏิบัติงานประจำเครื่องจักร');

      final autoNo = _processNoCtrl.text.trim().isNotEmpty
          ? _processNoCtrl.text.trim()
          : (selectedMc != null
              ? 'SOP-${(selectedMc['machine_no'] ?? '').toString().replaceAll(' ', '')}'
              : 'SOP-${DateFormat('yyMMdd-HHmm').format(now)}');

      final autoDate = _preparedDateCtrl.text.trim().isNotEmpty
          ? _preparedDateCtrl.text.trim()
          : DateFormat('yyyy-MM-dd').format(now);

      final process = WorkProcess(
        processId: widget.processId ?? const Uuid().v4(),
        processNo: autoNo,
        title: autoTitle,
        company: _companyCtrl.text.trim(),
        factory: _factoryCtrl.text.trim(),
        department: _deptCtrl.text.trim(),
        methodType: _methodType,
        parentProcessId: _parentProcessId,
        workType: _workType,
        machineId: _selectedMachineId,
        preparedBy: _preparedByCtrl.text.trim(),
        preparedDate: autoDate,
        approvedBy: _approvedByCtrl.text.trim(),
        approvedDate: _approvedDateCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
        status: 'active',
        createdAt: now,
        updatedAt: now,
      );

      final savedId = await ref.read(workProcessListProvider.notifier).saveProcess(
        process: process,
        steps: _steps,
      );

      // Auto-sync Work Process & Machine SOP to Vector DB RAG
      unawaited(VectorDbService.syncWorkProcess(savedId));
      if (_selectedMachineId != null && _selectedMachineId!.isNotEmpty) {
        unawaited(VectorDbService.syncMachine(_selectedMachineId!));
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกขั้นตอนการทำงานและอัปเดตลง RAG/Vector DB เรียบร้อยแล้ว'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เกิดข้อผิดพลาดในการบันทึก: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.processId != null
              ? 'แก้ไขขั้นตอนการปฏิบัติงานประจำเครื่องจักร (SOP)'
              : 'บันทึกขั้นตอนการปฏิบัติงานประจำเครื่องจักร (SOP)',
        ),
        actions: [
          if (widget.processId != null)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.analytics_rounded, size: 18),
              label: const Text('วิเคราะห์ Lean / VSM'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade100,
                foregroundColor: Colors.amber.shade900,
              ),
              onPressed: () => context.push(
                '/lean-analysis?processId=${widget.processId}',
              ),
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('บันทึก'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  _buildHeaderCard(theme),
                  const SizedBox(height: AppSpacing.lg),
                  _buildStepsTable(theme),
                ],
              ),
            ),
            _buildBottomSummaryBar(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme) {
    final selectedMc = _machines
        .where((m) => m['machine_id'].toString() == _selectedMachineId)
        .firstOrNull;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: DropdownButtonFormField<String>(
                initialValue: _selectedMachineId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'เครื่องจักรที่กำหนด SOP',
                  prefixIcon: Icon(Icons.precision_manufacturing_rounded, size: 20),
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('-- เลือกเครื่องจักร --', overflow: TextOverflow.ellipsis),
                  ),
                  ..._machines.map((m) {
                    return DropdownMenuItem(
                      value: m['machine_id'].toString(),
                      child: Text(
                        '${m['machine_no']} - ${m['machine_name'] ?? ""}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    );
                  }),
                ],
                onChanged: (val) {
                  setState(() {
                    _selectedMachineId = val;
                    if (val != null) {
                      final mc = _machines
                          .where((m) => m['machine_id'].toString() == val)
                          .firstOrNull;
                      if (mc != null) {
                        _titleCtrl.text =
                            'ขั้นตอนการปฏิบัติงาน ${mc['machine_name'] ?? ''} (${mc['machine_no']})';
                        _processNoCtrl.text =
                            'SOP-${(mc['machine_no'] ?? '').toString().replaceAll(' ', '')}';
                      }
                    }
                  });
                },
              ),
            ),
            const SizedBox(width: 16),
            // Auto Generated Doc Code Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tag_rounded, size: 16, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    _processNoCtrl.text.isNotEmpty
                        ? _processNoCtrl.text
                        : (selectedMc != null
                            ? 'SOP-${selectedMc['machine_no']}'
                            : 'Auto-SOP'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    _preparedDateCtrl.text.isNotEmpty
                        ? _preparedDateCtrl.text
                        : DateFormat('yyyy-MM-dd').format(DateTime.now()),
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepsTable(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.format_list_bulleted_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'รายการขั้นตอนการปฏิบัติงาน (${_steps.length} ขั้นตอน)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _addStep,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('เพิ่มขั้นตอน'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            ...List.generate(_steps.length, (idx) => _buildStepRow(idx, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildStepRow(int index, ThemeData theme) {
    final step = _steps[index];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 13,
                backgroundColor: theme.colorScheme.primary,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextFormField(
                  initialValue: step.description,
                  decoration: InputDecoration(
                    labelText: 'ขั้นตอนที่ ${index + 1} (รายละเอียดสิ่งที่ต้องปฏิบัติ) *',
                    hintText: 'เช่น ตรวจเช็กระดับน้ำมันหล่อลื่น และเปิดสวิตช์เครื่อง',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'กรุณากรอกขั้นตอน' : null,
                  onChanged: (val) {
                    _steps[index] = step.copyWith(description: val);
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 140,
                child: TextFormField(
                  initialValue: step.durationMinutes > 0 ? step.durationMinutes.toString() : '',
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'เวลา (นาที) *',
                    hintText: '5.0',
                    suffixText: 'นาที',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (val) {
                    final d = double.tryParse(val) ?? 0.0;
                    _steps[index] = step.copyWith(durationMinutes: d);
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                tooltip: 'เลื่อนขึ้น',
                onPressed: index > 0 ? () => _moveStep(index, -1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward_rounded, size: 20),
                tooltip: 'เลื่อนลง',
                onPressed: index < _steps.length - 1 ? () => _moveStep(index, 1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
                tooltip: 'ลบขั้นตอน',
                onPressed: () => _removeStep(index),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: step.toolsUsed ?? '',
            decoration: const InputDecoration(
              labelText: 'เครื่องมือ / อุปกรณ์ / ข้อควรระวังด้านความปลอดภัย (Tools & Safety Notes)',
              hintText: 'เช่น สวมถุงมือกันบาด, ประแจเบอร์ 14, ตรวจสัญญาณไฟเขียว (ไม่บังคับ)',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(),
            ),
            onChanged: (val) => _steps[index] = step.copyWith(toolsUsed: val),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSummaryBar(ThemeData theme) {
    final totalMinutes = _steps.fold(0.0, (sum, s) => sum + s.durationMinutes);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Row(
            children: [
              const Icon(Icons.format_list_numbered_rounded, size: 20),
              const SizedBox(width: 6),
              Text(
                'ทั้งหมด: ',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              Text(
                '${_steps.length} ขั้นตอน',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(width: 24),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 20),
              const SizedBox(width: 6),
              Text(
                'เวลารวมมาตรฐาน: ',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
              ),
              Text(
                '${totalMinutes.toStringAsFixed(1)} นาที',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.primary),
              ),
            ],
          ),
          const Spacer(),
          if (widget.processId != null)
            FilledButton.tonalIcon(
              icon: const Icon(Icons.analytics_rounded, size: 18),
              label: const Text('วิเคราะห์ Lean / VSM'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.amber.shade100,
                foregroundColor: Colors.amber.shade900,
              ),
              onPressed: () => context.push(
                '/lean-analysis?processId=${widget.processId}',
              ),
            ),
        ],
      ),
    );
  }
}
