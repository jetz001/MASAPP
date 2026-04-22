import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'layout_provider.dart';
import 'layout_models.dart';
import '../auth/auth_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../dashboard/dashboard_screen.dart';

class LayoutListScreen extends ConsumerWidget {
  const LayoutListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final layoutListAsync = ref.watch(layoutListProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.go('/dashboard'),
        ),
        title: const Text('พื้นที่โรงงาน (Areas Registry)'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add Area'),
              onPressed: () => _showAddLayoutDialog(context, ref),
            ),
          ),
        ],
      ),
      body: layoutListAsync.when(
        data: (layouts) {
          if (layouts.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.map_outlined, size: 64, color: Theme.of(context).disabledColor),
                  const SizedBox(height: 16),
                  Text('ยังไม่มีข้อมูลพื้นที่โรงงาน', style: AppTextStyles.headlineSmall),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () => _showAddLayoutDialog(context, ref),
                    child: const Text('สร้างพื้นที่แรก'),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FixedColumnWidth(100),
                  2: FixedColumnWidth(100),
                  3: FixedColumnWidth(120),
                  4: FixedColumnWidth(120),
                  5: FixedColumnWidth(100),
                },
                children: [
                  // Header
                  _buildHeaderRow(context),
                  // Data Rows
                  ...layouts.map((l) => _buildDataRow(context, ref, l)),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
      ),
    );
  }

  TableRow _buildHeaderRow(BuildContext context) {
    return TableRow(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(128),
      ),
      children: const [
        _HeaderCell('ชื่อพื้นที่ (Area Name)'),
        _HeaderCell('ขนาด (กว้าง)'),
        _HeaderCell('ขนาด (ยาว)'),
        _HeaderCell('สถานะ (Status)'),
        _HeaderCell('อัปเดตล่าสุด'),
        _HeaderCell('จัดการ'),
      ],
    );
  }

  TableRow _buildDataRow(BuildContext context, WidgetRef ref, dynamic layout) {
    return TableRow(
      children: [
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: InkWell(
              onTap: () {
                ref.read(selectedLayoutIdProvider.notifier).state = layout.layoutId;
                context.go('/factory-layout');
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.layers_outlined, size: 18, color: AppColors.primary),
                    const SizedBox(width: 12),
                    Text(layout.name, style: AppTextStyles.headlineSmall),
                  ],
                ),
              ),
            ),
          ),
        ),
        _DataCell('${layout.widthM.toStringAsFixed(1)} m'),
        _DataCell('${layout.heightM.toStringAsFixed(1)} m'),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: layout.isApproved ? Colors.green.withAlpha(40) : Colors.orange.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: layout.isApproved ? Colors.green : Colors.orange, width: 0.5),
              ),
              child: Text(
                layout.isApproved ? 'อนุมัติแล้ว' : 'รอการจัดผัง',
                style: TextStyle(
                  color: layout.isApproved ? Colors.green[900] : Colors.orange[900],
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
        _DataCell(layout.lastUpdated != null 
          ? '${layout.lastUpdated!.day}/${layout.lastUpdated!.month}/${layout.lastUpdated!.year}'
          : 'N/A'),
        TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blue),
                onPressed: () => _showEditLayoutDialog(context, ref, layout as FactoryLayout),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red),
                onPressed: () => _confirmDelete(context, ref, layout),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _showEditLayoutDialog(BuildContext context, WidgetRef ref, FactoryLayout layout) {
    final nameCtrl = TextEditingController(text: layout.name);
    final widthCtrl = TextEditingController(text: layout.widthM.toString());
    final heightCtrl = TextEditingController(text: layout.heightM.toString());
    String? selectedFilePath;
    String? selectedFileName = layout.backgroundPath != null ? p.basename(layout.backgroundPath!) : null;
    bool backgroundCleared = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('แก้ไขพื้นที่โรงงาน'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'ชื่อพื้นที่',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: widthCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Width (m)',
                          suffixText: 'm',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: heightCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Length (m)',
                          suffixText: 'm',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('รูปผังพื้น (Floor Plan)', 
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                  ),
                  child: Column(
                    children: [
                      if (selectedFileName != null && !backgroundCleared)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.file_present_rounded, size: 16, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(selectedFileName!, 
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () => setState(() {
                                  selectedFilePath = null;
                                  selectedFileName = null;
                                  backgroundCleared = true;
                                }),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file_rounded, size: 18),
                          label: Text(selectedFileName == null || backgroundCleared ? 'เลือกไฟล์ PDF หรือรูปภาพ' : 'เปลี่ยนไฟล์'),
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
                            );
                            if (result != null && result.files.single.path != null) {
                              setState(() {
                                selectedFilePath = result.files.single.path;
                                selectedFileName = result.files.single.name;
                                backgroundCleared = false;
                              });
                            }
                          },
                        ),
                       ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty) return;

                final repo = ref.read(layoutRepositoryProvider);
                
                String? finalBgPath = layout.backgroundPath;
                if (backgroundCleared) {
                  finalBgPath = null;
                }
                
                if (selectedFilePath != null) {
                  final appDir = await getApplicationDocumentsDirectory();
                  final layoutsDir = Directory(p.join(appDir.path, 'layouts'));
                  if (!await layoutsDir.exists()) await layoutsDir.create();
                  
                  final extension = p.extension(selectedFilePath!);
                  final newFileName = 'bg_${DateTime.now().millisecondsSinceEpoch}$extension';
                  final targetPath = p.join(layoutsDir.path, newFileName);
                  
                  await File(selectedFilePath!).copy(targetPath);
                  finalBgPath = targetPath;
                }
                
                await repo.updateLayout(
                  layoutId: layout.layoutId,
                  name: nameCtrl.text,
                  widthM: double.tryParse(widthCtrl.text) ?? layout.widthM,
                  heightM: double.tryParse(heightCtrl.text) ?? layout.heightM,
                  backgroundPath: finalBgPath,
                );

                ref.invalidate(layoutListProvider);

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('อัปเดตพื้นที่: ${nameCtrl.text}')),
                  );
                }
              },
              child: const Text('บันทึกการแก้ไข'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, dynamic layout) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยืนยันการลบพื้นที่'),
        content: Text('คุณต้องการลบพื้นที่ "${layout.name}" ใช่หรือไม่?\n\n* ข้อมูลมาร์กเกอร์เครื่องจักรในพื้นที่นี้จะถูกลบออกทั้งหมด'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await ref.read(layoutRepositoryProvider).deleteLayout(layout.layoutId);
              ref.invalidate(layoutListProvider);
              ref.invalidate(dashboardStatsProvider);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('ลบข้อมูล'),
          ),
        ],
      ),
    );
  }

  void _showAddLayoutDialog(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    final widthCtrl = TextEditingController(text: '32.0');
    final heightCtrl = TextEditingController(text: '20.0');
    String? selectedFilePath;
    String? selectedFileName;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('สร้างพื้นที่โรงงานใหม่'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Area Name',
                    hintText: 'e.g., Assembly Line A, Warehouse 1',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: widthCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Width (m)',
                          suffixText: 'm',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: heightCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Length (m)',
                          suffixText: 'm',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Floor Plan Background (Optional)', 
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(8),
                    color: Theme.of(context).colorScheme.surfaceContainerLow,
                  ),
                  child: Column(
                    children: [
                      if (selectedFileName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.file_present_rounded, size: 16, color: Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(selectedFileName!, 
                                  style: const TextStyle(fontSize: 12),
                                  overflow: TextOverflow.ellipsis),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () => setState(() {
                                  selectedFilePath = null;
                                  selectedFileName = null;
                                }),
                              ),
                            ],
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.upload_file_rounded, size: 18),
                          label: Text(selectedFileName == null ? 'Select PDF or Image' : 'Change File'),
                          onPressed: () async {
                            final result = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
                            );
                            if (result != null && result.files.single.path != null) {
                              setState(() {
                                selectedFilePath = result.files.single.path;
                                selectedFileName = result.files.single.name;
                              });
                            }
                          },
                        ),
                       ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isEmpty) return;

                final repo = ref.read(layoutRepositoryProvider);
                final user = ref.read(authProvider);

                String? finalBgPath;
                if (selectedFilePath != null) {
                  final appDir = await getApplicationDocumentsDirectory();
                  final layoutsDir = Directory(p.join(appDir.path, 'layouts'));
                  if (!await layoutsDir.exists()) await layoutsDir.create();
                  
                  final extension = p.extension(selectedFilePath!);
                  final newFileName = 'bg_${DateTime.now().millisecondsSinceEpoch}$extension';
                  final targetPath = p.join(layoutsDir.path, newFileName);
                  
                  await File(selectedFilePath!).copy(targetPath);
                  finalBgPath = targetPath;
                }
                
                final id = await repo.createLayout(
                  name: nameCtrl.text,
                  widthM: double.tryParse(widthCtrl.text) ?? 32.0,
                  heightM: double.tryParse(heightCtrl.text) ?? 20.0,
                  backgroundPath: finalBgPath,
                  createdBy: user?.userId,
                );

                ref.read(selectedLayoutIdProvider.notifier).state = id;
                ref.invalidate(layoutListProvider);

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Created area: ${nameCtrl.text}')),
                  );
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;
  const _HeaderCell(this.label);

  @override
  Widget build(BuildContext context) {
    return TableCell(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String label;
  const _DataCell(this.label);

  @override
  Widget build(BuildContext context) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(label, style: const TextStyle(fontSize: 14)),
      ),
    );
  }
}
