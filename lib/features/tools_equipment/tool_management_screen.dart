import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import '../../features/auth/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/widgets/hover_image_tooltip.dart';
import 'tool_models.dart';
import 'tool_provider.dart';

class ToolManagementScreen extends ConsumerWidget {
  const ToolManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toolsAsync = ref.watch(toolsProvider);
    final user = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const HugeIcon(icon: HugeIcons.strokeRoundedWrench01, size: 32, color: AppColors.primary),
                const SizedBox(width: AppSpacing.md),
                Text('เครื่องมือช่าง (Tools & Equipment)', style: AppTextStyles.displaySmall),
                const Spacer(),
                if (user?.isTechnicianOrAbove ?? false)
                  FilledButton.icon(
                    onPressed: () {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => const _ToolFormDialog(),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มเครื่องมือ'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Expanded(
              child: toolsAsync.when(
                data: (tools) {
                  if (tools.isEmpty) {
                    return const Center(child: Text('ไม่มีข้อมูลเครื่องมือ'));
                  }
                  return _ToolsTable(
                    tools: tools,
                    onCheckOut: (t) => _showTransactionDialog(context, ref, t, 'check_out'),
                    onCheckIn: (t) => _showTransactionDialog(context, ref, t, 'check_in'),
                    onRepair: (t) => _showTransactionDialog(context, ref, t, 'send_repair'),
                    onRepairDone: (t) => _showTransactionDialog(context, ref, t, 'receive_repair'),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(child: Text('Error: $err', style: const TextStyle(color: AppColors.error))),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showTransactionDialog(BuildContext context, WidgetRef ref, ToolItem tool, String action) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ToolTransactionDialog(tool: tool, actionType: action),
    );
  }
}

class _ToolsTable extends ConsumerWidget {
  final List<ToolItem> tools;
  final void Function(ToolItem) onCheckOut;
  final void Function(ToolItem) onCheckIn;
  final void Function(ToolItem) onRepair;
  final void Function(ToolItem) onRepairDone;

  const _ToolsTable({
    required this.tools,
    required this.onCheckOut,
    required this.onCheckIn,
    required this.onRepair,
    required this.onRepairDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppSpacing.sm),
                topRight: Radius.circular(AppSpacing.sm),
              ),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('รหัสเครื่องมือ', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 3, child: Text('ชื่อเครื่องมือ', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('หมวดหมู่', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('สถานะ', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('ราคา', style: TextStyle(fontWeight: FontWeight.bold))),
                Expanded(flex: 3, child: Text('', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          Container(height: 1, color: Theme.of(context).colorScheme.outline),
          Expanded(
            child: ListView.separated(
              itemCount: tools.length,
              separatorBuilder: (context, index) => Container(
                height: 1,
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
              ),
              itemBuilder: (context, i) {
                final tool = tools[i];
                return _ToolRow(
                  tool: tool,
                  onCheckOut: () => onCheckOut(tool),
                  onCheckIn: () => onCheckIn(tool),
                  onRepair: () => onRepair(tool),
                  onRepairDone: () => onRepairDone(tool),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolRow extends ConsumerWidget {
  final ToolItem tool;
  final VoidCallback onCheckOut;
  final VoidCallback onCheckIn;
  final VoidCallback onRepair;
  final VoidCallback onRepairDone;

  const _ToolRow({
    required this.tool,
    required this.onCheckOut,
    required this.onCheckIn,
    required this.onRepair,
    required this.onRepairDone,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);

    Color statusColor;
    String statusText;
    switch (tool.status) {
      case 'available':
        statusColor = AppColors.success;
        statusText = 'พร้อมใช้งาน';
        break;
      case 'in_use':
        statusColor = AppColors.warning;
        statusText = 'ถูกยืม';
        break;
      case 'repair':
        statusColor = AppColors.error;
        statusText = 'ส่งซ่อม';
        break;
      case 'lost':
        statusColor = AppColors.textSecondary;
        statusText = 'สูญหาย';
        break;
      default:
        statusColor = AppColors.textSecondary;
        statusText = tool.status;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            flex: 2, 
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    tool.toolCode, 
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (tool.imagePath != null && tool.imagePath!.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  HoverImageTooltip(imagePath: tool.imagePath),
                ],
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tool.toolName, style: const TextStyle(fontWeight: FontWeight.w500)),
                if (tool.notes != null && tool.notes!.isNotEmpty)
                  Text(tool.notes!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(tool.category ?? '-', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: statusColor.withValues(alpha: 0.5)),
              ),
              child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(tool.price != null ? NumberFormat('#,##0.00').format(tool.price) : '-', style: AppTextStyles.bodySmall),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (tool.status == 'available')
                  TextButton(
                    onPressed: onCheckOut,
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), foregroundColor: AppColors.primary),
                    child: const Text('ยืม', style: TextStyle(fontSize: 12)),
                  ),
                if (tool.status == 'in_use')
                  TextButton(
                    onPressed: onCheckIn,
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), foregroundColor: AppColors.success),
                    child: const Text('คืน', style: TextStyle(fontSize: 12)),
                  ),
                if (tool.status == 'available' || tool.status == 'in_use')
                  TextButton(
                    onPressed: onRepair,
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), foregroundColor: AppColors.error),
                    child: const Text('ส่งซ่อม', style: TextStyle(fontSize: 12)),
                  ),
                if (tool.status == 'repair')
                  TextButton(
                    onPressed: onRepairDone,
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), foregroundColor: AppColors.success),
                    child: const Text('ซ่อมเสร็จ', style: TextStyle(fontSize: 12)),
                  ),
                const SizedBox(width: 4),
                _ToolImageHover(imagePath: tool.imagePath),
                if (user?.isTechnicianOrAbove ?? false) ...[
                  IconButton(
                    onPressed: () {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => _ToolFormDialog(tool: tool),
                      );
                    },
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: 16, color: AppColors.textSecondary),
                    tooltip: 'แก้ไข',
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('ยืนยันการลบ'),
                          content: Text('คุณต้องการลบเครื่องมือ ${tool.toolCode} ใช่หรือไม่?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ยกเลิก')),
                            FilledButton(
                              onPressed: () => Navigator.pop(c, true),
                              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                              child: const Text('ลบข้อมูล'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await ref.read(toolsRepoProvider).deleteTool(tool.toolId);
                        ref.invalidate(toolsProvider);
                      }
                    },
                    icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete01, size: 16, color: AppColors.error),
                    tooltip: 'ลบ',
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolImageHover extends StatelessWidget {
  final String? imagePath;
  const _ToolImageHover({this.imagePath});

  @override
  Widget build(BuildContext context) {
    if (imagePath == null) return const SizedBox.shrink();

    return Tooltip(
      preferBelow: false,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))],
      ),
      richMessage: WidgetSpan(
        child: Container(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 200),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8)),
          clipBehavior: Clip.antiAlias,
          child: Image.file(
            File(imagePath!),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Padding(
              padding: const EdgeInsets.all(8.0),
              child: const Text('Image not found', style: TextStyle(color: AppColors.error)),
            ),
          ),
        ),
      ),
      child: IconButton(
        icon: const HugeIcon(icon: HugeIcons.strokeRoundedImage01, size: 16, color: AppColors.primary),
        onPressed: () {},
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        tooltip: '',
      ),
    );
  }
}

class _ToolFormDialog extends ConsumerStatefulWidget {
  final ToolItem? tool;
  const _ToolFormDialog({this.tool});

  @override
  ConsumerState<_ToolFormDialog> createState() => _ToolFormDialogState();
}

class _ToolFormDialogState extends ConsumerState<_ToolFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _categoryCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _notesCtrl;
  String? _imagePath;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.tool?.toolName);
    _categoryCtrl = TextEditingController(text: widget.tool?.category);
    _priceCtrl = TextEditingController(text: widget.tool?.price?.toString() ?? '');
    _notesCtrl = TextEditingController(text: widget.tool?.notes ?? '');
    _imagePath = widget.tool?.imagePath;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
      if (result != null && result.files.single.path != null) {
        setState(() => _imagePath = result.files.single.path);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking image: $e')));
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    
    try {
      final repo = ref.read(toolsRepoProvider);
      if (widget.tool == null) {
        final generatedCode = 'TL-${DateFormat('yyMMddHHmmss').format(DateTime.now())}';
        await repo.addTool(
          toolCode: generatedCode,
          toolName: _nameCtrl.text.trim(),
          category: _categoryCtrl.text.trim(),
          price: double.tryParse(_priceCtrl.text.trim()),
          notes: _notesCtrl.text.trim(),
          imagePath: _imagePath,
          purchaseDate: DateTime.now(), // Simplified
        );
      } else {
        await repo.updateTool(
          toolId: widget.tool!.toolId,
          toolCode: widget.tool!.toolCode,
          toolName: _nameCtrl.text.trim(),
          category: _categoryCtrl.text.trim(),
          price: double.tryParse(_priceCtrl.text.trim()),
          notes: _notesCtrl.text.trim(),
          imagePath: _imagePath,
          purchaseDate: widget.tool!.purchaseDate,
        );
      }
      
      if (mounted) {
        ref.invalidate(toolsProvider);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.tool == null ? 'เพิ่มเครื่องมือใหม่' : 'แก้ไขเครื่องมือ'),
      content: SizedBox(
        width: 500,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _pickImage,
                  child: Container(
                    height: 160,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _imagePath != null
                        ? Image.file(
                            File(_imagePath!),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Center(
                              child: Text('ไม่สามารถโหลดรูปภาพได้', style: TextStyle(color: AppColors.error)),
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              HugeIcon(icon: HugeIcons.strokeRoundedCamera01, size: 32, color: AppColors.textSecondary),
                              const SizedBox(height: 8),
                              Text('คลิกเพื่อเพิ่มรูปภาพ', style: AppTextStyles.bodySmall),
                            ],
                          ),
                  ),
                ),
                if (_imagePath != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() => _imagePath = null),
                    icon: const Icon(Icons.delete_outline, size: 16, color: AppColors.error),
                    label: const Text('ลบรูปภาพ', style: TextStyle(color: AppColors.error)),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'ชื่อเครื่องมือ *'),
                  validator: (v) => v == null || v.isEmpty ? 'กรุณากรอกชื่อเครื่องมือ' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _categoryCtrl,
                  decoration: const InputDecoration(labelText: 'หมวดหมู่'),
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _priceCtrl,
                  decoration: const InputDecoration(labelText: 'ราคา (บาท)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'หมายเหตุ'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _isSaving ? null : () => Navigator.of(context).pop(), child: const Text('ยกเลิก')),
        FilledButton(onPressed: _isSaving ? null : _save, child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('บันทึก')),
      ],
    );
  }
}

class _ToolTransactionDialog extends ConsumerStatefulWidget {
  final ToolItem tool;
  final String actionType;
  const _ToolTransactionDialog({required this.tool, required this.actionType});

  @override
  ConsumerState<_ToolTransactionDialog> createState() => _ToolTransactionDialogState();
}

class _ToolTransactionDialogState extends ConsumerState<_ToolTransactionDialog> {
  final _refNoCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _refNoCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _isSaving = true);
    try {
      final user = ref.read(authProvider);
      await ref.read(toolsRepoProvider).recordTransaction(
        toolId: widget.tool.toolId,
        actionType: widget.actionType,
        userId: user?.userId,
        referenceNo: _refNoCtrl.text.trim(),
        notes: _notesCtrl.text.trim(),
      );
      if (mounted) {
        ref.invalidate(toolsProvider);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    String title;
    switch (widget.actionType) {
      case 'check_out': title = 'ยืมเครื่องมือ'; break;
      case 'check_in': title = 'คืนเครื่องมือ'; break;
      case 'send_repair': title = 'ส่งซ่อม'; break;
      case 'receive_repair': title = 'รับคืนจากซ่อม'; break;
      default: title = 'ทำรายการ';
    }

    return AlertDialog(
      title: Text('$title - ${widget.tool.toolCode}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('เครื่องมือ: ${widget.tool.toolName}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.md),
            if (widget.actionType == 'check_out' || widget.actionType == 'send_repair') ...[
              TextFormField(
                controller: _refNoCtrl,
                decoration: const InputDecoration(labelText: 'หมายเลขอ้างอิง (เช่น WO-1234, Job No.)'),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            TextFormField(
              controller: _notesCtrl,
              decoration: const InputDecoration(labelText: 'หมายเหตุ'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _isSaving ? null : () => Navigator.of(context).pop(), child: const Text('ยกเลิก')),
        FilledButton(onPressed: _isSaving ? null : _submit, child: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Text('ยืนยัน')),
      ],
    );
  }
}
