import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:open_filex/open_filex.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../auth/auth_provider.dart';
import 'machine_models.dart';
import 'machine_provider.dart';
import 'utils/machine_form_utils.dart';
import 'utils/asset_tag_utils.dart';
import 'widgets/approval_dialog.dart';
import '../dashboard/dashboard_screen.dart';

/// 3-stage machine intake stepper form
class MachineIntakeFormScreen extends ConsumerStatefulWidget {
  final String? machineId;
  const MachineIntakeFormScreen({super.key, this.machineId});

  @override
  ConsumerState<MachineIntakeFormScreen> createState() =>
      _MachineIntakeFormScreenState();
}

class _MachineIntakeFormScreenState
    extends ConsumerState<MachineIntakeFormScreen> {
  int _currentStep = 0;
  bool _saving = false;
  bool _isEditUnlocked = false;
  String? _savedMachineId;
  final List<Map<String, dynamic>> _attachments = [];

  // Initial State for dirty tracking (only for machines already received)
  MachineModel? _initialMachine;
  final List<Map<String, dynamic>> _initialAttachments = [];
  final List<int> _initialStage1Results = [];
  final List<int> _initialStage2Results = [];
  final List<int> _initialStage3Results = [];

  bool get _isReceivedMachine => _initialMachine?.handoverCompleted == true;
  bool get _canEdit => !_isReceivedMachine || _isEditUnlocked || (ref.watch(authProvider)?.isAdmin ?? false);

  // Step 0 — Basic Info controllers
  final _machineNoCtrl = TextEditingController();
  final _machineNameCtrl = TextEditingController();
  final _assetNoCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _modelCtrl = TextEditingController();
  final _serialNoCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _costCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _installDate;
  DateTime? _warrantyExpiry;
  String? _selectedCategoryId;
  String? _selectedDeptId;
  String? _selectedSupplierId;
  String? _handoverConclusion; // pass, fail

  // Step 1 — Technical Specs (Now mostly integrated or as Step 1)
  final _powerCtrl = TextEditingController();
  final _voltCtrl = TextEditingController();
  final _currentCtrl = TextEditingController();
  final _freqCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _capacityUnitCtrl = TextEditingController(text: 'หน่วย/ชม.');
  final _weightCtrl = TextEditingController();
  final _lenCtrl = TextEditingController();
  final _widCtrl = TextEditingController();
  final _htCtrl = TextEditingController();
  final _rpmCtrl = TextEditingController();

  // Step 2-4 — Handover checklists (stage 1, 2, 3)
  List<_ChecklistItem> _stage1Items = _defaultStage1Checklist();
  List<_ChecklistItem> _stage2Items = _defaultStage2Checklist();
  List<_ChecklistItem> _stage3Items = _defaultStage3Checklist();
  final _stage1NotesCtrl = TextEditingController();
  final _stage2NotesCtrl = TextEditingController();
  final _stage3NotesCtrl = TextEditingController();

  final _formKey0 = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.machineId != null) {
      _savedMachineId = widget.machineId;
      Future.microtask(_loadExistingMachine);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _machineNoCtrl, _machineNameCtrl, _assetNoCtrl, _brandCtrl, _modelCtrl, _serialNoCtrl,
      _locationCtrl, _costCtrl, _notesCtrl, _powerCtrl, _voltCtrl, _currentCtrl,
      _freqCtrl, _capacityCtrl, _capacityUnitCtrl, _weightCtrl, _lenCtrl,
      _widCtrl, _htCtrl, _rpmCtrl, _stage1NotesCtrl, _stage2NotesCtrl,
      _stage3NotesCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadExistingMachine() async {
    final machine =
        await ref.read(machineRepositoryProvider).fetchById(_savedMachineId!);
    if (machine != null && mounted) {
      setState(() {
        _machineNoCtrl.text = machine.machineNo;
        _machineNameCtrl.text = machine.machineName ?? '';
        _assetNoCtrl.text = machine.assetNo ?? '';
        _brandCtrl.text = machine.brand ?? '';
        _modelCtrl.text = machine.model ?? '';
        _serialNoCtrl.text = machine.serialNo ?? '';
        _locationCtrl.text = machine.location ?? '';
        _costCtrl.text = machine.purchaseCost?.toString() ?? '';
        _notesCtrl.text = machine.notes ?? '';
        _installDate = machine.installationDate;
        _warrantyExpiry = machine.warrantyExpiry;
        _selectedCategoryId = machine.categoryId;
        _selectedDeptId = machine.deptId;
        _selectedSupplierId = machine.supplierId;
        _handoverConclusion = machine.handoverConclusion;

        // Technical specs
        if (machine.specs != null) {
          _powerCtrl.text = machine.specs!.powerKw?.toString() ?? '';
          _voltCtrl.text = machine.specs!.voltageV?.toString() ?? '';
          _currentCtrl.text = machine.specs!.currentA?.toString() ?? '';
          _freqCtrl.text = machine.specs!.frequencyHz?.toString() ?? '';
          _capacityCtrl.text = machine.specs!.capacity?.toString() ?? '';
          _capacityUnitCtrl.text = machine.specs!.capacityUnit ?? 'หน่วย/ชม.';
          _weightCtrl.text = machine.specs!.weightKg?.toString() ?? '';
          _lenCtrl.text = machine.specs!.dimLengthMm?.toString() ?? '';
          _widCtrl.text = machine.specs!.dimWidthMm?.toString() ?? '';
          _htCtrl.text = machine.specs!.dimHeightMm?.toString() ?? '';
          _rpmCtrl.text = machine.specs!.rpm?.toString() ?? '';
        }

        _initialMachine = machine;
        _isEditUnlocked = machine.isEditUnlocked;

        // Fetch attachments
        _loadingAttachments(machine);

        // Fetch Checklist Results
        _loadHandoverResults(machine);
      });
    }
  }

  Future<void> _selectDate(BuildContext context, bool isInstallation) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: (isInstallation ? _installDate : _warrantyExpiry) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isInstallation) {
          _installDate = picked;
        } else {
          _warrantyExpiry = picked;
        }
      });
    }
  }

  Widget _buildDatePickerField(String label, DateTime? value, IconData icon, {required bool enabled, required VoidCallback onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
              color: enabled ? null : Theme.of(context).disabledColor.withValues(alpha: 0.1),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(
                  value != null ? value.toString().split(' ').first : 'เลือกวันที่',
                  style: TextStyle(
                    color: value != null ? null : Theme.of(context).disabledColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _loadHandoverResults(MachineModel machine) async {
    final repo = ref.read(machineRepositoryProvider);
    
    // Load for each stage if handoverId exists
    if (machine.stage1?.handoverId != null) {
      final results = await repo.fetchHandoverResults(machine.stage1!.handoverId!);
      _updateLocalChecklist(_stage1Items, results);
      _stage1NotesCtrl.text = machine.stage1?.notes ?? '';
    }
    if (machine.stage2?.handoverId != null) {
      final results = await repo.fetchHandoverResults(machine.stage2!.handoverId!);
      _updateLocalChecklist(_stage2Items, results);
      _stage2NotesCtrl.text = machine.stage2?.notes ?? '';
    }
    if (machine.stage3?.handoverId != null) {
      final results = await repo.fetchHandoverResults(machine.stage3!.handoverId!);
      _updateLocalChecklist(_stage3Items, results);
      _stage3NotesCtrl.text = machine.stage3?.notes ?? '';
    }
    
    if (mounted) {
      setState(() {
        if (machine.stage1?.handoverId != null) {
          _initialStage1Results.clear();
          _initialStage1Results.addAll(_stage1Items.map((e) => e.status));
        }
        if (machine.stage2?.handoverId != null) {
          _initialStage2Results.clear();
          _initialStage2Results.addAll(_stage2Items.map((e) => e.status));
        }
        if (machine.stage3?.handoverId != null) {
          _initialStage3Results.clear();
          _initialStage3Results.addAll(_stage3Items.map((e) => e.status));
        }
      });
    }
  }

  void _updateLocalChecklist(List<_ChecklistItem> localItems, List<ChecklistResult> dbResults) {
    for (final dbResult in dbResults) {
      // Find matching item in local checklist template by name
      final index = localItems.indexWhere((item) => item.title == dbResult.itemName);
      if (index != -1) {
        final status = dbResult.result == 'pass' ? 1 : (dbResult.result == 'fail' ? 2 : (dbResult.result == 'na' ? 3 : 0));
        localItems[index].status = status;
        localItems[index].comment = dbResult.remarks;
      }
    }
  }

  Future<void> _loadingAttachments(MachineModel machine) async {
    final docs = await ref.read(machineRepositoryProvider).fetchAttachments(machine.machineId!);
    if (mounted) {
      setState(() {
        _attachments.clear();
        _initialAttachments.clear();
        for (final doc in docs) {
          final item = {
            'attachment_id': doc['attachment_id'],
            'name': doc['file_name'],
            'path': doc['file_path'],
            'size': doc['file_size'],
            'type': doc['mime_type'],
          };
          _attachments.add(item);
          _initialAttachments.add(Map.from(item));
        }
      });
    }
  }

  Future<void> _saveBasicInfo() async {
    if (!_formKey0.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      final user = ref.read(authProvider);
      final repo = ref.read(machineRepositoryProvider);

      // Check for duplicates before saving
      final machineNoDup = await repo.isDuplicate('machine_no', _machineNoCtrl.text, excludeId: _savedMachineId);
      if (machineNoDup) {
        throw 'รหัสเครื่องจักร (${_machineNoCtrl.text}) นี้มีอยู่ในระบบแล้ว';
      }

      if (_assetNoCtrl.text.isNotEmpty) {
        final assetDup = await repo.isDuplicate('asset_no', _assetNoCtrl.text, excludeId: _savedMachineId);
        if (assetDup) {
          throw 'รหัสทรัพย์สิน (${_assetNoCtrl.text}) นี้มีอยู่ในระบบแล้ว';
        }
      }

      final machineData = {
        'machine_no': _machineNoCtrl.text,
        'machine_name': _machineNameCtrl.text,
        'asset_no': _assetNoCtrl.text,
        'brand': _brandCtrl.text,
        'model': _modelCtrl.text,
        'serial_no': _serialNoCtrl.text,
        'category_id': _selectedCategoryId,
        'dept_id': _selectedDeptId,
        'location': _locationCtrl.text,
        'installation_date': _installDate?.toIso8601String(),
        'warranty_expiry': _warrantyExpiry?.toIso8601String(),
         'purchase_cost': double.tryParse(_costCtrl.text),
         'notes': _notesCtrl.text,
         'supplier_id': _selectedSupplierId,
         'handover_conclusion': _handoverConclusion,
       };

      final specsData = {
        'power_kw': double.tryParse(_powerCtrl.text),
        'voltage_v': double.tryParse(_voltCtrl.text),
        'current_a': double.tryParse(_currentCtrl.text),
        'frequency_hz': double.tryParse(_freqCtrl.text),
        'capacity': double.tryParse(_capacityCtrl.text),
        'capacity_unit': _capacityUnitCtrl.text,
        'weight_kg': double.tryParse(_weightCtrl.text),
        'dim_length_mm': double.tryParse(_lenCtrl.text),
        'dim_width_mm': double.tryParse(_widCtrl.text),
        'dim_height_mm': double.tryParse(_htCtrl.text),
        'rpm': double.tryParse(_rpmCtrl.text),
      };

      String id;
      if (_savedMachineId != null) {
        // UPDATE Mode
        id = _savedMachineId!;
        await repo.updateMachine(
          machineId: id,
          machineData: machineData,
          specsData: specsData,
        );
      } else {
        // CREATE Mode
        id = await repo.createMachine(
          machineData: machineData,
          specsData: specsData,
          createdBy: user?.userId ?? 'system',
        );
      }

      await _saveAttachments(id);
      
      // Update initial state after successful save to clear wrench icons
      _initialMachine = await repo.fetchById(id);

      if (mounted) {
        setState(() {
          _savedMachineId = id;
          _saving = false;
          _currentStep = 1; // Move to Documents step
        });
        ref.invalidate(dashboardStatsProvider);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        String message = e.toString();
        
        // Handle specific SQLite unique constraint error if it still slips through
        if (message.contains('UNIQUE constraint failed')) {
          if (message.contains('machine_no')) {
            message = 'รหัสเครื่องจักรนี้มีอยู่ในระบบแล้ว';
          } else if (message.contains('asset_no')) {
            message = 'รหัสทรัพย์สินนี้มีอยู่ในระบบแล้ว';
          } else {
            message = 'ข้อมูลบางอย่างซ้ำกับที่มีอยู่ในระบบแล้ว';
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      setState(() {
        for (final file in result.files) {
          _attachments.add({
            'file_name': file.name,
            'file_path': file.path,
            'file_size': file.size,
            'mime_type': file.extension,
          });
        }
      });
    }
  }

  void _removeFile(int index) async {
    final file = _attachments[index];
    if (file['attachment_id'] != null) {
      // If it exists in DB, delete it
      await ref.read(machineRepositoryProvider).deleteAttachment(file['attachment_id']);
    }
    setState(() => _attachments.removeAt(index));
  }

  Future<void> _downloadAttachment(Map<String, dynamic> file) async {
    try {
      final path = file['path'] as String?;
      if (path == null || path.isEmpty) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ไม่พบที่อยู่ไฟล์')));
        return;
      }

      final originalFile = File(path);
      if (!await originalFile.exists()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ไฟล์ต้นฉบับไม่อยู่ในตำแหน่งเดิมแล้ว')));
        return;
      }

      // Allow user to pick a folder on Windows
      final String? selectedDirectory = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'เลือกโฟลเดอร์สำหรับบันทึกไฟล์: ${file['name']}',
      );

      if (selectedDirectory == null) return; // User canceled

      final newPath = '$selectedDirectory\\${file['name']}';
      await originalFile.copy(newPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('บันทึกไฟล์เรียบร้อยแล้วที่: $newPath'),
            backgroundColor: AppColors.success,
            action: SnackBarAction(
              label: 'เปิดโฟลเดอร์',
              textColor: Colors.white,
              onPressed: () => OpenFilex.open(selectedDirectory),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการดาวน์โหลด: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _saveAttachments(String machineId) async {
    final repo = ref.read(machineRepositoryProvider);
    final user = ref.read(authProvider);
    
    // We link attachments to Stage 1 (Installation) by default in this intake flow
    final machine = await repo.fetchById(machineId);
    final handoverId = machine?.stage1?.handoverId;
    
    if (handoverId == null) return;

    for (final file in _attachments) {
      // Only save if it's new (no attachment_id yet)
      if (file['attachment_id'] == null) {
        await repo.saveAttachment(
          handoverId: handoverId,
          fileName: file['file_name'] ?? 'unknown',
          filePath: file['file_path'] ?? '',
          fileSize: file['file_size'] ?? 0,
          mimeType: file['mime_type'] ?? 'application/octet-stream',
          userId: user?.userId ?? 'system',
        );
      }
    }
    
    // Refresh initial attachments after saving
    final docs = await repo.fetchAttachments(machineId);
    if (mounted) {
      setState(() {
        _initialAttachments.clear();
        for (final doc in docs) {
          _initialAttachments.add({
            'attachment_id': doc['attachment_id'],
            'file_name': doc['file_name'],
            'file_path': doc['file_path'],
            'file_size': doc['file_size'],
            'mime_type': doc['mime_type'],
          });
        }
      });
    }
  }

  Future<void> _saveStage(int currentStep) async {
    if (_savedMachineId == null) return;
    
    setState(() => _saving = true);
    try {
      final repo = ref.read(machineRepositoryProvider);
      final user = ref.read(authProvider);
      final machine = await repo.fetchById(_savedMachineId!);
      
      HandoverInfo? stageInfo;
      List<_ChecklistItem>? items;
      TextEditingController? notes;
      HandoverStage stageEnum;
      
      if (currentStep == 2) {
        stageInfo = machine?.stage1;
        items = _stage1Items;
        notes = _stage1NotesCtrl;
        stageEnum = HandoverStage.stage1;
      } else if (currentStep == 3) {
        stageInfo = machine?.stage2;
        items = _stage2Items;
        notes = _stage2NotesCtrl;
        stageEnum = HandoverStage.stage2;
      } else {
        stageInfo = machine?.stage3;
        items = _stage3Items;
        notes = _stage3NotesCtrl;
        stageEnum = HandoverStage.stage3;
      }
      
      if (stageInfo?.handoverId == null) return;

      // 1. Save results
      final results = items.map((item) => {
        'item_name': item.title,
        'result': item.status == 1 ? 'pass' : (item.status == 2 ? 'fail' : (item.status == 3 ? 'na' : 'none')),
        'actual_value': '',
        'remarks': item.comment ?? '',
      }).toList();
      
      await repo.saveChecklistResults(
        handoverId: stageInfo!.handoverId!,
        results: results,
      );
      
      // 2. Update stage status
      final allPassed = items.every((item) => item.status == 1 || item.status == 3);
      await repo.updateHandoverStage(
        machineId: _savedMachineId!,
        stage: stageEnum,
         status: allPassed ? HandoverStatus.passed : HandoverStatus.failed,
         performedBy: user?.userId ?? 'system',
         notes: notes.text,
         handoverConclusion: currentStep == 4 ? _handoverConclusion : null,
       );
      
      // Update initial results for this stage
      if (currentStep == 2) {
        _initialStage1Results.clear();
        _initialStage1Results.addAll(_stage1Items.map((e) => e.status));
      } else if (currentStep == 3) {
        _initialStage2Results.clear();
        _initialStage2Results.addAll(_stage2Items.map((e) => e.status));
      } else {
        _initialStage3Results.clear();
        _initialStage3Results.addAll(_stage3Items.map((e) => e.status));
      }

      if (mounted) {
        setState(() {
          _saving = false;
          if (currentStep < 4) {
             _currentStep++;
          }
        });
        ref.invalidate(dashboardStatsProvider);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกผิดพลาด: $e')),
        );
      }
    }
  }

  Future<void> _toggleEditUnlock() async {
    if (_savedMachineId == null) return;
    
    final repo = ref.read(machineRepositoryProvider);
    final nextStatus = !_isEditUnlocked;
    
    setState(() => _saving = true);
    try {
      await repo.updateEditUnlock(_savedMachineId!, nextStatus);
      if (mounted) {
        setState(() {
          _isEditUnlocked = nextStatus;
          _saving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(nextStatus ? 'ปลดล็อกการแก้ไขสำเร็จ (Editable)' : 'ล็อกการแก้ไขแล้ว (Read-only)'),
            backgroundColor: nextStatus ? AppColors.success : AppColors.textSecondary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    }
  }

  Future<void> _printIntakeReport() async {
    if (_savedMachineId == null) return;
    
    final repo = ref.read(machineRepositoryProvider);
    final machine = await repo.fetchById(_savedMachineId!);
    if (machine != null) {
      await MachineFormUtils.generateIntakeReport(machine);
    }
  }

  Future<void> _printAssetTag() async {
    if (_savedMachineId == null) return;
    
    final repo = ref.read(machineRepositoryProvider);
    final machine = await repo.fetchById(_savedMachineId!);
    if (machine != null) {
      await AssetTagUtils.generateAndPrintTag(machine);
    }
  }

  Future<void> _printManualForm() async {
    // Create a temporary model from current form state
    final tempMachine = MachineModel(
      machineNo: _machineNoCtrl.text,
      machineName: _machineNameCtrl.text,
      assetNo: _assetNoCtrl.text,
      brand: _brandCtrl.text,
      model: _modelCtrl.text,
      serialNo: _serialNoCtrl.text,
      location: _locationCtrl.text,
      installationDate: _installDate,
      specs: MachineSpecs(
        powerKw: double.tryParse(_powerCtrl.text),
        voltageV: double.tryParse(_voltCtrl.text),
        capacity: double.tryParse(_capacityCtrl.text),
        capacityUnit: _capacityUnitCtrl.text,
      ),
    );

    await MachineFormUtils.generateManualChecklist(tempMachine);
  }

  bool _isStepDirty(int step) {
    if (!_isReceivedMachine) return false;

    switch (step) {
      case 0: // Basic Info
        if (_initialMachine == null) return false;
        return _machineNoCtrl.text != _initialMachine!.machineNo ||
            _machineNameCtrl.text != (_initialMachine!.machineName ?? '') ||
            _assetNoCtrl.text != (_initialMachine!.assetNo ?? '') ||
            _brandCtrl.text != (_initialMachine!.brand ?? '') ||
            _modelCtrl.text != (_initialMachine!.model ?? '') ||
            _serialNoCtrl.text != (_initialMachine!.serialNo ?? '') ||
            _locationCtrl.text != (_initialMachine!.location ?? '') ||
            _notesCtrl.text != (_initialMachine!.notes ?? '') ||
            _powerCtrl.text != (_initialMachine!.specs?.powerKw?.toString() ?? '') ||
            _voltCtrl.text != (_initialMachine!.specs?.voltageV?.toString() ?? '') ||
            _capacityCtrl.text != (_initialMachine!.specs?.capacity?.toString() ?? '');
      
      case 1: // Documents
        if (_attachments.length != _initialAttachments.length) return true;
        for (int i = 0; i < _attachments.length; i++) {
          if (_attachments[i]['file_name'] != _initialAttachments[i]['file_name']) return true;
        }
        return false;

      case 2: // Stage 1
        return !_listsEqual(_stage1Items.map((e) => e.status).toList(), _initialStage1Results);
      case 3: // Stage 2
        return !_listsEqual(_stage2Items.map((e) => e.status).toList(), _initialStage2Results);
      case 4: // Stage 3
        return !_listsEqual(_stage3Items.map((e) => e.status).toList(), _initialStage3Results);
      
      default:
        return false;
    }
  }

  bool _listsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          _buildHeader(),
          _StepIndicator(
            currentStep: _currentStep,
            isReceived: _isReceivedMachine,
            isStepDirty: _isStepDirty,
            onStepTapped: (index) {
              if (index < _currentStep || _savedMachineId != null) {
                setState(() => _currentStep = index);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('กรุณาบันทึกข้อมูลทั่วไปก่อนข้ามไปขั้นตอนอื่น'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _buildCurrentStep(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.machineId == null ? 'เพิ่มเครื่องจักรใหม่' : 'แก้ไขข้อมูล',
                style: AppTextStyles.displayMedium,
              ),
              Text(
                'กระบวนการรับมอบเครื่องจักรดิจิทัล',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _printManualForm,
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('พิมพ์ฟอร์ม Manual'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          if (_isReceivedMachine && (ref.read(authProvider)?.isAdmin ?? false))
            Container(
              margin: const EdgeInsets.only(right: AppSpacing.md),
              child: Tooltip(
                message: _isEditUnlocked ? 'ล็อกการแก้ไข' : 'ปลดล็อกการแก้ไข',
                child: InkWell(
                  onTap: _saving ? null : _toggleEditUnlock,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isEditUnlocked ? AppColors.warning.withValues(alpha: 0.1) : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                        color: _isEditUnlocked ? AppColors.warning : Theme.of(context).dividerColor,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isEditUnlocked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                          size: 18,
                          color: _isEditUnlocked ? AppColors.warning : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isEditUnlocked ? 'UNLOCKED' : 'LOCKED',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: _isEditUnlocked ? AppColors.warning : Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_saving && _currentStep != 5)
            const CircularProgressIndicator()
          else if (_currentStep != 5)
            Text(
              'ขั้นตอนที่ ${_currentStep + 1} / 6',
              style: AppTextStyles.headlineSmall.copyWith(color: AppColors.primary),
            ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case 0:
        return _buildBasicInfoStep(enabled: _canEdit);
      case 1:
        return _buildDocumentsStep(enabled: _canEdit);
      case 2:
        return _buildChecklistStep('ระยะที่ 1: การติดตั้งและเตรียมเครื่อง', _stage1Items, _stage1NotesCtrl, (val) => setState(() => _stage1Items = val), enabled: _canEdit);
      case 3:
        return _buildChecklistStep('ระยะที่ 2: การทดสอบเดินเครื่อง', _stage2Items, _stage2NotesCtrl, (val) => setState(() => _stage2Items = val), enabled: _canEdit);
      case 4:
        return _buildChecklistStep('ระยะที่ 3: การตรวจรับขั้นตอนสุดท้าย', _stage3Items, _stage3NotesCtrl, (val) => setState(() => _stage3Items = val), enabled: _canEdit);
      case 5:
        return _buildCompletionStep();
      default:
        return const Center(child: Text('Invalid Step'));
    }
  }

  Widget _buildBasicInfoStep({bool enabled = true}) {
    return Form(
      key: _formKey0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(Icons.info_outline, 'ข้อมูลทั่วไป'),
          const SizedBox(height: AppSpacing.md),
          _buildTextField(_machineNameCtrl, 'ชื่อเครื่องจักร *', Icons.precision_manufacturing, enabled: enabled),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _buildTextField(_machineNoCtrl, 'รหัสเครื่องจักร *', Icons.tag, enabled: enabled),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildTextField(_assetNoCtrl, 'รหัสทรัพย์สิน', Icons.qr_code, enabled: enabled),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _buildTextField(_brandCtrl, 'ยี่ห้อ *', Icons.business, enabled: enabled),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildTextField(_modelCtrl, 'รุ่น *', Icons.settings, enabled: enabled),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _buildTextField(_serialNoCtrl, 'เลขซีเรียล (Serial No.)', Icons.tag_outlined, enabled: enabled),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildTextField(_locationCtrl, 'สถานที่ติดตั้ง / ไลน์ผลิต *', Icons.location_on, enabled: enabled),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _buildDatePickerField(
                  'วันที่ติดตั้ง *', 
                  _installDate, 
                  Icons.calendar_today,
                  enabled: enabled,
                  onTap: () => _selectDate(context, true),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildDatePickerField(
                  'วันหมดประกัน', 
                  _warrantyExpiry, 
                  Icons.verified_user_outlined,
                  enabled: enabled,
                  onTap: () => _selectDate(context, false),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const SizedBox(height: AppSpacing.lg),
          _buildSectionHeader(Icons.settings_input_component, 'ข้อมูลทางเทคนิค'),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _buildTextField(_powerCtrl, 'กำลังไฟฟ้า (kW)', Icons.bolt, enabled: enabled)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _buildTextField(_voltCtrl, 'แรงดันไฟฟ้า (V)', Icons.electrical_services, enabled: enabled)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _buildTextField(_capacityCtrl, 'ความสามารถในการผลิต', Icons.speed, enabled: enabled)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _buildTextField(_capacityUnitCtrl, 'หน่วย (เช่น ชิ้น/นาที)', null, enabled: enabled)),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton(
                onPressed: () => context.pop(),
                child: const Text('ยกเลิก'),
              ),
              const SizedBox(width: AppSpacing.md),
              ElevatedButton(
                onPressed: _saving ? null : _saveBasicInfo,
                child: const Text('ถัดไป'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentsStep({bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.folder_open, 'เอกสาร & สื่อประกอบ'),
        const SizedBox(height: AppSpacing.sm),
        Text('อัปโหลดคู่มือเครื่องจักร, เอกสารการเทรนนิ่ง หรือรูปภาพหน้างาน', style: AppTextStyles.secondary),
        const SizedBox(height: AppSpacing.lg),
        InkWell(
          onTap: enabled ? _pickFiles : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Opacity(
            opacity: enabled ? 1.0 : 0.6,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                  style: BorderStyle.solid,
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.cloud_upload_outlined, size: 48, color: AppColors.primary),
                  const SizedBox(height: AppSpacing.md),
                  Text(enabled ? 'เลือกไฟล์ หรือ ลากมาที่นี่' : 'ไม่สามารถอัปโหลดได้ในสถานะนี้',
                      style: AppTextStyles.headlineSmall.copyWith(color: AppColors.primary)),
                  Text('PDF, ไฟล์เอกสาร, รูปภาพ (สูงสุด 10MB)',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_attachments.isNotEmpty) ...[
          Text('ไฟล์ที่แนบแล้ว (${_attachments.length})', style: AppTextStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _attachments.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.xs),
            itemBuilder: (context, i) {
              final file = _attachments[i];
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Row(
                  children: [
                    Icon(Icons.description_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(file['file_name'] ?? '', style: AppTextStyles.headlineSmall),
                          Text('${((file['file_size'] ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  )),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.download_outlined, color: AppColors.primary),
                      onPressed: () => _downloadAttachment(file),
                      tooltip: 'ดาวน์โหลดลงเครื่อง',
                    ),
                    if (enabled)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: AppColors.error),
                        onPressed: () => _removeFile(i),
                        tooltip: 'ลบ',
                      ),
                  ],
                ),
              );
            },
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _currentStep = 0),
              child: const Text('ย้อนกลับ'),
            ),
            const SizedBox(width: AppSpacing.md),
            ElevatedButton(
              onPressed: _saving ? null : () async {
                setState(() => _saving = true);
                if (_savedMachineId != null) {
                  await _saveAttachments(_savedMachineId!);
                }
                if (mounted) {
                  setState(() {
                    _saving = false;
                    _currentStep = 2;
                  });
                }
              },
              child: _saving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_isReceivedMachine ? 'บันทึกการแก้ไข' : 'ถัดไป — เริ่มตรวจสอบ'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChecklistStep(String title, List<_ChecklistItem> items, TextEditingController notes, Function(List<_ChecklistItem>) onUpdate, {bool enabled = true}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.checklist_rtl, title),
        const SizedBox(height: AppSpacing.md),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          itemBuilder: (context, i) {
            final item = items[i];
            return _ChecklistRow(
              index: i,
              item: item,
              enabled: enabled,
              onChanged: (updated) {
                final newItems = List<_ChecklistItem>.from(items);
                newItems[i] = updated;
                onUpdate(newItems);
              },
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        if (_currentStep == 4) ...[
          Text('ผลสรุปการตรวจรับ', style: AppTextStyles.headlineSmall),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _ConclusionButton(
                label: 'ผ่านรับเข้า (Pass)',
                color: AppColors.success,
                isSelected: _handoverConclusion == 'pass',
                enabled: enabled,
                onTap: () => setState(() => _handoverConclusion = 'pass'),
              ),
              const SizedBox(width: AppSpacing.md),
              _ConclusionButton(
                label: 'ไม่รับ (Fail)',
                color: AppColors.error,
                isSelected: _handoverConclusion == 'fail',
                enabled: enabled,
                onTap: () => setState(() => _handoverConclusion = 'fail'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
        _buildTextField(notes, 'หมายเหตุเพิ่มเติม', Icons.comment, maxLines: 3, enabled: enabled),
        const SizedBox(height: AppSpacing.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _currentStep--),
              child: const Text('ย้อนกลับ'),
            ),
            const SizedBox(width: AppSpacing.md),
            ElevatedButton(
              onPressed: _saving ? null : () async {
                if (_currentStep == 4 && ref.read(authProvider)?.isEngineerOrAbove == true) {
                  await _saveStage(4);
                  _showApprovalDialog();
                } else {
                  await _saveStage(_currentStep);
                }
              },
              child: _saving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_currentStep == 4 && ref.read(authProvider)?.isEngineerOrAbove == true) ...[
                        const HugeIcon(icon: HugeIcons.strokeRoundedStamp, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                      ],
                      Text((_isReceivedMachine && _currentStep == 4)
                        ? 'ส่งตรวจรับใหม่'
                        : (_currentStep == 4 && ref.read(authProvider)?.isEngineerOrAbove == true ? 'ยืนยันการตรวจรับขั้นตอนที่ 3' : 'ถัดไป')),
                    ],
                  ),
            ),
          ],
        ),
      ],
    );
  }

  void _showApprovalDialog() async {
    final success = await showDialog<bool>(
      context: context,
      builder: (ctx) => ApprovalDialog(
        machineId: _savedMachineId!,
        title: _isReceivedMachine ? 'การขออนุมัติใหม่ (Re-approval)' : 'การอนุมัติขั้นตอนสุดท้าย (Stage 3)',
      ),
    );
    if (success == true) {
      if (mounted) {
        setState(() {
          _currentStep = 5; // Move to completion
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('อนุมัติเรียบร้อยแล้ว')),
        );
      }
    }
  }

  Widget _buildCompletionStep() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_outline, size: 80, color: AppColors.success),
          const SizedBox(height: AppSpacing.lg),
          Text('ดำเนินการเสร็จสิ้น!', style: AppTextStyles.displayMedium),
          const SizedBox(height: AppSpacing.sm),
          Text('ข้อมูลเครื่องจักรถูกบันทึกเข้าระบบเรียบร้อยแล้ว',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _printIntakeReport,
                icon: const Icon(Icons.description_outlined),
                label: const Text('พิมพ์รายงานตรวจรับ'),
              ),
              const SizedBox(width: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _printAssetTag,
                icon: const Icon(Icons.qr_code_2),
                label: const Text('พิมพ์ป้าย QR Tag'),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: () => context.pop(),
                icon: const Icon(Icons.home),
                label: const Text('กลับหน้าหลัก'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(width: AppSpacing.sm),
        Text(title, style: AppTextStyles.headlineMedium),
      ],
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label, IconData? icon, {int maxLines = 1, bool enabled = true}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      enabled: enabled,
      style: AppTextStyles.bodyMedium,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, size: 20) : null,
      ),
      validator: (v) => (v == null || v.isEmpty) && label.contains('*') ? 'กรุณากรอกข้อมูล' : null,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Components & Data Models
// ─────────────────────────────────────────────────────────────────────────────

class _ChecklistItem {
  final String title;
  final String description;
  int status; // 0=none, 1=pass, 2=fail, 3=n/a
  String? comment;

  _ChecklistItem({required this.title, this.description = '', this.status = 0, this.comment});
}

class _ChecklistRow extends StatelessWidget {
  final int index;
  final _ChecklistItem item;
  final bool enabled;
  final void Function(_ChecklistItem) onChanged;

  const _ChecklistRow({
    required this.index,
    required this.item,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Center(child: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary))),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: AppTextStyles.headlineSmall),
                    if (item.description.isNotEmpty)
                      Text(item.description,
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              )),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _ResultButton(
                label: 'ผ่าน',
                color: AppColors.success,
                isSelected: item.status == 1,
                enabled: enabled,
                onTap: () => onChanged(_ChecklistItem(title: item.title, description: item.description, status: 1, comment: item.comment)),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ResultButton(
                label: 'ไม่ผ่าน',
                color: AppColors.error,
                isSelected: item.status == 2,
                enabled: enabled,
                onTap: () => onChanged(_ChecklistItem(title: item.title, description: item.description, status: 2, comment: item.comment)),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ResultButton(
                label: 'N/A',
                color: AppColors.textSecondary,
                isSelected: item.status == 3,
                enabled: enabled,
                onTap: () => onChanged(_ChecklistItem(title: item.title, description: item.description, status: 3, comment: item.comment)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  style: AppTextStyles.labelMedium,
                  enabled: enabled,
                  decoration: const InputDecoration(
                    hintText: 'ความเห็น...',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 8),
                    border: UnderlineInputBorder(),
                  ),
                  onChanged: (v) => onChanged(_ChecklistItem(title: item.title, description: item.description, status: item.status, comment: v)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResultButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  const _ResultButton({
    required this.label,
    required this.color,
    required this.isSelected,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: isSelected ? color : Theme.of(context).dividerColor),
        ),
        child: Text(label,
            style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _ConclusionButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  const _ConclusionButton({
    required this.label,
    required this.color,
    required this.isSelected,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: BoxDecoration(
            color: isSelected ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
                color: isSelected ? color : Theme.of(context).dividerColor,
                width: isSelected ? 2 : 1),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  final bool isReceived;
  final bool Function(int) isStepDirty;
  final Function(int)? onStepTapped;
  const _StepIndicator({
    required this.currentStep,
    this.isReceived = false,
    required this.isStepDirty,
    this.onStepTapped,
  });

  @override
  Widget build(BuildContext context) {
    final steps = ['ข้อมูล', 'เอกสาร', 'ติดตั้ง', 'ทดสอบ', 'ผ่านรับ', 'เสร็จสิ้น'];
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(steps.length, (i) {
          final isDone = i < currentStep;
          final isCurrent = i == currentStep;
          
          return InkWell(
            onTap: onStepTapped != null ? () => onStepTapped!(i) : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? AppColors.primary
                          : (isDone
                              ? AppColors.success
                              : Theme.of(context).colorScheme.surfaceContainerHighest),
                      shape: BoxShape.circle,
                      border: isCurrent ? null : Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: Center(
                      child: isReceived
                          ? (isStepDirty(i)
                              ? const HugeIcon(icon: HugeIcons.strokeRoundedWrench01, size: 16, color: Colors.white)
                              : const Icon(Icons.check, size: 16, color: Colors.white))
                          : (isDone
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : Text('${i + 1}',
                                  style: TextStyle(
                                      color: isCurrent
                                          ? Colors.white
                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.bold))),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(steps[i],
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isCurrent
                                ? AppColors.primary
                                : Theme.of(context).colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          )),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

List<_ChecklistItem> _defaultStage1Checklist() => [
      _ChecklistItem(title: 'การวางเครื่องจักร (Positioning)', description: 'ตรวจสอบตำแหน่งตามแผนผังโรงงาน'),
      _ChecklistItem(title: 'การติดตั้งลม/ไฟฟ้า (Utilities)', description: 'ตรวจสอบความเรียบร้อยของสายและท่อ'),
      _ChecklistItem(title: 'ความปลอดภัย (Safety Guard)', description: 'ตรวจสอบเซนเซอร์และฝาครอบป้องกัน'),
    ];

List<_ChecklistItem> _defaultStage2Checklist() => [
      _ChecklistItem(title: 'ระบบไฟฟ้า (Electric System)', description: 'ตรวจสอบแรงดันและกระแสไฟฟ้าขณะเดินเครื่อง'),
      _ChecklistItem(title: 'ระบบลม (Pneumatic System)', description: 'ตรวจสอบการรั่วซึมของลม'),
      _ChecklistItem(title: 'ความเร็ว (Operation Speed)', description: 'ทดสอบการทำงานที่ความเร็วสูงสุด'),
    ];

List<_ChecklistItem> _defaultStage3Checklist() => [
      _ChecklistItem(title: 'คุณภาพชิ้นงาน (Target Quality)', description: 'ตรวจสอบชิ้นงานที่ผลิตได้ตามตัวอย่าง'),
      _ChecklistItem(title: 'ความสะอาด (Housekeeping)', description: 'ทำความสะอาดเครื่องจักรและบริเวณโดยรอบ'),
      _ChecklistItem(title: 'การส่งมอบเอกสาร (Doc Handover)', description: 'ส่งมอบ Manual และ Certificate ให้ฝ่ายผลิต'),
    ];
