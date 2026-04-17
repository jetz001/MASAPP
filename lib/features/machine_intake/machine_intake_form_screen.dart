import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/auth/auth_provider.dart';
import 'machine_provider.dart';
import 'utils/asset_tag_utils.dart';

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
  String? _savedMachineId;
  final List<Map<String, dynamic>> _attachments = [];

  // Step 0 — Basic Info controllers
  final _machineNoCtrl = TextEditingController();
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

  // Step 1 — Technical Specs (Now mostly integrated or as Step 1)
  final _powerCtrl = TextEditingController();
  final _voltCtrl = TextEditingController();
  final _currentCtrl = TextEditingController();
  final _freqCtrl = TextEditingController();
  final _capacityCtrl = TextEditingController();
  final _capacityUnitCtrl = TextEditingController(text: 'Units/hr');
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
      _machineNoCtrl, _assetNoCtrl, _brandCtrl, _modelCtrl, _serialNoCtrl,
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

        // Technical specs
        if (machine.specs != null) {
          _powerCtrl.text = machine.specs!.powerKw?.toString() ?? '';
          _voltCtrl.text = machine.specs!.voltageV?.toString() ?? '';
          _currentCtrl.text = machine.specs!.currentA?.toString() ?? '';
          _freqCtrl.text = machine.specs!.frequencyHz?.toString() ?? '';
          _capacityCtrl.text = machine.specs!.capacity?.toString() ?? '';
          _capacityUnitCtrl.text = machine.specs!.capacityUnit ?? 'Units/hr';
          _weightCtrl.text = machine.specs!.weightKg?.toString() ?? '';
          _lenCtrl.text = machine.specs!.dimLengthMm?.toString() ?? '';
          _widCtrl.text = machine.specs!.dimWidthMm?.toString() ?? '';
          _htCtrl.text = machine.specs!.dimHeightMm?.toString() ?? '';
          _rpmCtrl.text = machine.specs!.rpm?.toString() ?? '';
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

      final machineData = {
        'machine_no': _machineNoCtrl.text,
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

      final id = await repo.createMachine(
        machineData: machineData,
        specsData: specsData,
        createdBy: user?.userId ?? 'system',
      );

      await _saveAttachments(id);

      if (mounted) {
        setState(() {
          _savedMachineId = id;
          _saving = false;
          _currentStep = 1; // Move to Documents step
        });
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

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      setState(() {
        for (final file in result.files) {
          _attachments.add({
            'name': file.name,
            'path': file.path,
            'size': file.size,
            'type': file.extension,
          });
        }
      });
    }
  }

  void _removeFile(int index) {
    setState(() => _attachments.removeAt(index));
  }

  Future<void> _saveAttachments(String machineId) async {
    final repo = ref.read(machineRepositoryProvider);
    final user = ref.read(authProvider);
    for (final file in _attachments) {
      await repo.saveAttachment(
        handoverId: machineId,
        fileName: file['name'] ?? 'unknown',
        filePath: file['path'] ?? '',
        fileSize: file['size'] ?? 0,
        mimeType: file['type'] ?? 'application/octet-stream',
        userId: user?.userId ?? 'system',
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      body: Column(
        children: [
          _buildHeader(),
          _StepIndicator(currentStep: _currentStep),
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
      decoration: const BoxDecoration(
        color: AppColors.bgSurface,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
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
                'Digital Machine Handover Process',
                style: AppTextStyles.secondary,
              ),
            ],
          ),
          const Spacer(),
          if (_saving)
            const CircularProgressIndicator()
          else
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
        return _buildBasicInfoStep();
      case 1:
        return _buildDocumentsStep();
      case 2:
        return _buildChecklistStep('Stage 1: Install & Set-up', _stage1Items, _stage1NotesCtrl, (val) => setState(() => _stage1Items = val));
      case 3:
        return _buildChecklistStep('Stage 2: Machine Test Run', _stage2Items, _stage2NotesCtrl, (val) => setState(() => _stage2Items = val));
      case 4:
        return _buildChecklistStep('Stage 3: Final Acceptance', _stage3Items, _stage3NotesCtrl, (val) => setState(() => _stage3Items = val));
      case 5:
        return _buildCompletionStep();
      default:
        return const Center(child: Text('Invalid Step'));
    }
  }

  Widget _buildBasicInfoStep() {
    return Form(
      key: _formKey0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(Icons.info_outline, 'ข้อมูลทั่วไป'),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _buildTextField(_machineNoCtrl, 'Machine No. *', Icons.tag),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildTextField(_assetNoCtrl, 'Asset Tag No.', Icons.qr_code),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _buildTextField(_brandCtrl, 'Brand *', Icons.business),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildTextField(_modelCtrl, 'Model *', Icons.settings),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _buildTextField(_locationCtrl, 'Location / Line *', Icons.location_on),
          const SizedBox(height: AppSpacing.lg),
          _buildSectionHeader(Icons.settings_input_component, 'Technical Specifications'),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _buildTextField(_powerCtrl, 'Power (kW)', Icons.bolt)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _buildTextField(_voltCtrl, 'Voltage (V)', Icons.electrical_services)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: _buildTextField(_capacityCtrl, 'Capacity', Icons.speed)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: _buildTextField(_capacityUnitCtrl, 'Unit (e.g. pcs/min)', null)),
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

  Widget _buildDocumentsStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(Icons.folder_open, 'เอกสาร & สื่อประกอบ'),
        const SizedBox(height: AppSpacing.sm),
        Text('อัปโหลดคู่มือเครื่องจักร, เอกสารการเทรนนิ่ง หรือรูปภาพหน้างาน', style: AppTextStyles.secondary),
        const SizedBox(height: AppSpacing.lg),
        InkWell(
          onTap: _pickFiles,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.bgSurface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.divider,
                style: BorderStyle.solid,
              ),
            ),
            child: Column(
              children: [
                const Icon(Icons.cloud_upload_outlined, size: 48, color: AppColors.primary),
                const SizedBox(height: AppSpacing.md),
                Text('เลือกไฟล์ หรือ ลากมาที่นี่', style: AppTextStyles.headlineSmall.copyWith(color: AppColors.primary)),
                Text('PDF, Files, Images (Max 10MB)', style: AppTextStyles.labelMedium),
              ],
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
                  color: AppColors.bgSurface,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.description_outlined, color: AppColors.textSecondary),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(file['name'] ?? '', style: AppTextStyles.headlineSmall),
                          Text('${(file['size'] / 1024 / 1024).toStringAsFixed(2)} MB', style: AppTextStyles.labelMedium),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: AppColors.error),
                      onPressed: () => _removeFile(i),
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
              onPressed: () => setState(() => _currentStep = 2),
              child: const Text('ถัดไป — เริ่มตรวจสอบ'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChecklistStep(String title, List<_ChecklistItem> items, TextEditingController notes, Function(List<_ChecklistItem>) onUpdate) {
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
              onChanged: (updated) {
                final newItems = List<_ChecklistItem>.from(items);
                newItems[i] = updated;
                onUpdate(newItems);
              },
            );
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        _buildTextField(notes, 'หมายเหตุเพิ่มเติม', Icons.comment, maxLines: 3),
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
              onPressed: () => setState(() => _currentStep++),
              child: const Text('ถัดไป'),
            ),
          ],
        ),
      ],
    );
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
          Text('ข้อมูลเครื่องจักรถูกบันทึกเข้าระบบเรียบร้อยแล้ว', style: AppTextStyles.secondary),
          const SizedBox(height: AppSpacing.xl),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: _printAssetTag,
                icon: const Icon(Icons.print),
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

  Widget _buildTextField(TextEditingController ctrl, String label, IconData? icon, {int maxLines = 1}) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
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
  final void Function(_ChecklistItem) onChanged;

  const _ChecklistRow({required this.index, required this.item, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
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
                      Text(item.description, style: AppTextStyles.labelMedium.copyWith(color: AppColors.textSecondary)),
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
                onTap: () => onChanged(_ChecklistItem(title: item.title, description: item.description, status: 1, comment: item.comment)),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ResultButton(
                label: 'ไม่ผ่าน',
                color: AppColors.error,
                isSelected: item.status == 2,
                onTap: () => onChanged(_ChecklistItem(title: item.title, description: item.description, status: 2, comment: item.comment)),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ResultButton(
                label: 'N/A',
                color: AppColors.textSecondary,
                isSelected: item.status == 3,
                onTap: () => onChanged(_ChecklistItem(title: item.title, description: item.description, status: 3, comment: item.comment)),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextField(
                  style: AppTextStyles.labelMedium,
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
  final VoidCallback onTap;

  const _ResultButton({required this.label, required this.color, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(color: isSelected ? color : AppColors.divider),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final int currentStep;
  const _StepIndicator({required this.currentStep});

  @override
  Widget build(BuildContext context) {
    final steps = ['ข้อมูล', 'เอกสาร', 'ติดตั้ง', 'ทดสอบ', 'ผ่านรับ', 'เสร็จสิ้น'];
    return Container(
      color: AppColors.bgSurface,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(steps.length, (i) {
          final isDone = i < currentStep;
          final isCurrent = i == currentStep;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: isCurrent ? AppColors.primary : (isDone ? AppColors.success : AppColors.bgSurface),
                  shape: BoxShape.circle,
                  border: isCurrent ? null : Border.all(color: AppColors.divider),
                ),
                child: Center(
                  child: isDone
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text('${i + 1}', style: TextStyle(color: isCurrent ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 4),
              Text(steps[i], style: AppTextStyles.labelMedium.copyWith(color: isCurrent ? AppColors.primary : AppColors.textSecondary)),
            ],
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
