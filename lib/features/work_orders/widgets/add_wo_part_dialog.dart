import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../core/theme/app_spacing.dart';
import '../../spare_parts/spare_parts_screen.dart';
import '../../machine_intake/machine_provider.dart';
import '../work_order_provider.dart';

class AddWoPartDialog extends ConsumerStatefulWidget {
  final String woId;
  final String machineId;

  const AddWoPartDialog({super.key, required this.woId, required this.machineId});

  @override
  ConsumerState<AddWoPartDialog> createState() => _AddWoPartDialogState();
}

class _AddWoPartDialogState extends ConsumerState<AddWoPartDialog> {
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  
  String _searchQuery = '';
  String? _selectedPartId;
  double _availableQty = 0;
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    final partsAsync = ref.watch(machineBomProvider(widget.machineId));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 600,
        height: 600,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('เบิกอะไหล่ (Spare Part Requisition)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: AppSpacing.lg),
            
            // Search Box
            ShadInput(
              controller: _searchCtrl,
              placeholder: const Text('ค้นหาอะไหล่ (รหัส หรือ ชื่อ)'),
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            ),
            const SizedBox(height: AppSpacing.md),
            
            // Results List
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: partsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, st) => Center(child: Text('Error: $e')),
                  data: (allParts) {
                    final parts = allParts.where((p) {
                      if (_searchQuery.isEmpty) return true;
                      final q = _searchQuery.toLowerCase();
                      return (p.partCode.toLowerCase().contains(q)) || 
                             (p.partName.toLowerCase().contains(q));
                    }).toList();

                    if (parts.isEmpty) {
                      return Center(
                        child: Text(
                          allParts.isEmpty 
                              ? 'เครื่องจักรนี้ยังไม่ได้ลงทะเบียน BOM (รายการอะไหล่ประจำเครื่อง)' 
                              : 'ไม่พบรายการอะไหล่ใน BOM ที่ค้นหา'
                        )
                      );
                    }
                    return ListView.separated(
                      itemCount: parts.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final p = parts[index];
                        final isSelected = _selectedPartId == p.partId;
                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: Colors.blue.shade50,
                          title: Text('${p.partCode} - ${p.partName}'),
                          subtitle: Text('คงเหลือ: ${p.quantityOnHand} ชิ้น'),
                          trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                          onTap: () {
                            setState(() {
                              _selectedPartId = p.partId;
                              _availableQty = p.quantityOnHand.toDouble();
                            });
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ),
            
            const SizedBox(height: AppSpacing.lg),
            
            // Quantity Input
            if (_selectedPartId != null) ...[
              const Text('ระบุจำนวนที่เบิก', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  SizedBox(
                    width: 150,
                    child: ShadInput(
                      controller: _qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text('จากยอดคงเหลือ $_availableQty ชิ้น', style: TextStyle(color: Colors.grey.shade600)),
                ],
              ),
            ],

            const SizedBox(height: AppSpacing.xl),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ShadButton.outline(
                  child: const Text('ยกเลิก'),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: AppSpacing.sm),
                ShadButton(
                  onPressed: _selectedPartId == null || _isSaving ? null : _save,
                  child: _isSaving 
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('ยืนยันการเบิก'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final qty = double.tryParse(_qtyCtrl.text) ?? 0;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('กรุณาระบุจำนวนให้ถูกต้อง')));
      return;
    }
    if (qty > _availableQty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('จำนวนเบิกเกินสต็อกที่มี (มี $_availableQty)')));
      return;
    }

    setState(() => _isSaving = true);
    
    final success = await ref.read(workOrderRepositoryProvider).addPartToWorkOrder(
      woId: widget.woId,
      partId: _selectedPartId!,
      quantity: qty,
    );

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        ref.invalidate(workOrderPartsProvider(widget.woId));
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เกิดข้อผิดพลาดในการบันทึก')));
      }
    }
  }
}
