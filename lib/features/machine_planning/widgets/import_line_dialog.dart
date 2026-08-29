import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../line_balancing/line_balancing_provider.dart';
import '../providers/machine_planning_provider.dart';

class ImportLineDialog extends ConsumerStatefulWidget {
  const ImportLineDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (ctx) => const ImportLineDialog(),
    );
  }

  @override
  ConsumerState<ImportLineDialog> createState() => _ImportLineDialogState();
}

class _ImportLineDialogState extends ConsumerState<ImportLineDialog> {
  String? _selectedLineId;
  bool _overwrite = false;
  String _defaultTime = '08:00-17:00';
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final linesAsync = ref.watch(allProductionLinesProvider);

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.account_tree_outlined, color: Colors.teal),
          SizedBox(width: 8),
          Text('ดึงเครื่องจักรจาก Line Balancing', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'เลือกรุ่นสินค้าหรือสายการผลิตที่ได้จัดทำผังกระบวนการไว้ ระบบจะดึงเครื่องจักรทั้งหมดลงตารางประจำสัปดาห์ให้อัตโนมัติ:',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 14),

              linesAsync.when(
                data: (lines) {
                  if (lines.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.amber),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'ยังไม่มีสายการผลิตที่บันทึกไว้ใน Line Balancing กรุณาสร้างสายการผลิตก่อน',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  if (_selectedLineId == null && lines.isNotEmpty) {
                    _selectedLineId = lines.first['line_id'].toString();
                  }

                  return DropdownButtonFormField<String>(
                    initialValue: _selectedLineId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'สายการผลิต / สูตรสินค้า (Production Line)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.factory_outlined),
                    ),
                    items: lines.map((l) {
                      final lid = l['line_id'].toString();
                      final lname = l['line_name']?.toString() ?? 'สายการผลิต';
                      final scnt = (l['station_count'] as num?)?.toInt() ?? 0;
                      return DropdownMenuItem<String>(
                        value: lid,
                        child: Text('🏭 $lname ($scnt สถานี)'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedLineId = val),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
              ),

              const SizedBox(height: 16),

              // Default weekday time
              TextField(
                decoration: const InputDecoration(
                  labelText: 'กำหนดช่วงเวลาเริ่มต้นวันทำงาน (จันทร์-ศุกร์)',
                  hintText: '08:00-17:00',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.timer_outlined, size: 18),
                  helperText: 'สามารถเว้นว่างได้หากต้องการระบุเองทีหลัง',
                ),
                controller: TextEditingController(text: _defaultTime)
                  ..selection = TextSelection.collapsed(offset: _defaultTime.length),
                onChanged: (val) => _defaultTime = val,
              ),

              const SizedBox(height: 12),

              // Overwrite checkbox
              CheckboxListTile(
                value: _overwrite,
                title: const Text('ล้างข้อมูลเดิมในสัปดาห์นี้ทั้งหมด (Overwrite)', style: TextStyle(fontSize: 13)),
                subtitle: const Text('หากไม่เลือก ระบบจะเพิ่มเครื่องจักรต่อท้ายรายการเดิม (Append)', style: TextStyle(fontSize: 11)),
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => _overwrite = val ?? false),
              ),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text('กำลังประมวลผลและนำเข้าเครื่องจักร...', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('นำเข้าเครื่องจักร'),
          onPressed: (_selectedLineId == null || _isLoading)
              ? null
              : () async {
                  setState(() => _isLoading = true);
                  await ref.read(machinePlanningProvider.notifier).importFromLineBalancing(
                        _selectedLineId!,
                        overwrite: _overwrite,
                        defaultTime: _defaultTime.trim(),
                      );
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('นำเข้าเครื่องจักรจาก Line Balancing สำเร็จ'),
                        backgroundColor: Colors.teal,
                      ),
                    );
                  }
                },
        ),
      ],
    );
  }
}
