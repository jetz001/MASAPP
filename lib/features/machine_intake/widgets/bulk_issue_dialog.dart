import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/db_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../machine_provider.dart';
import '../machine_models.dart';

class BulkIssueDialog extends ConsumerStatefulWidget {
  final List<MachineBomItem> selectedItems;
  final String machineId;

  const BulkIssueDialog({
    super.key,
    required this.selectedItems,
    required this.machineId,
  });

  @override
  ConsumerState<BulkIssueDialog> createState() => _BulkIssueDialogState();
}

class _BulkIssueDialogState extends ConsumerState<BulkIssueDialog> {
  final _refCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();
  
  // Map of partId to quantity controller
  final Map<String, TextEditingController> _qtyControllers = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (var item in widget.selectedItems) {
      // Default issue quantity is min of QPA and available stock, min 1 if QPA is 0? 
      // Actually if stock is 0, default to 0.
      int defaultQty = item.quantity;
      if (item.quantityOnHand < defaultQty) {
        defaultQty = item.quantityOnHand;
      }
      if (defaultQty < 0) defaultQty = 0;
      
      _qtyControllers[item.partId] = TextEditingController(text: defaultQty.toString());
    }
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    _remarkCtrl.dispose();
    for (var ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    // Validate quantities
    bool hasError = false;
    for (var item in widget.selectedItems) {
      final text = _qtyControllers[item.partId]?.text ?? '0';
      final qty = int.tryParse(text) ?? 0;
      if (qty > item.quantityOnHand) {
        hasError = true;
        break;
      }
    }

    if (hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('จำนวนที่เบิกต้องไม่เกินจำนวนคงเหลือ')),
      );
      return;
    }

    setState(() => _saving = true);
    
    try {
      await DbHelper.transaction((tx) async {
        final now = DateTime.now().toIso8601String();
        
        for (var item in widget.selectedItems) {
          final text = _qtyControllers[item.partId]?.text ?? '0';
          final qty = int.tryParse(text) ?? 0;
          
          if (qty <= 0) continue; // Skip zero quantities

          final transId = const Uuid().v4();
          
          // 1. Insert transaction
          await DbHelper.txExecute(tx, '''
            INSERT INTO spare_parts_transactions
              (trans_id, part_id, trans_type, quantity, reference_id, remarks, trans_date)
            VALUES (@tid, @pid, 'ISSUE', @qty, @ref, @remarks, @date)
          ''', params: {
            'tid': transId,
            'pid': item.partId,
            'qty': qty,
            'ref': _refCtrl.text.isEmpty ? null : _refCtrl.text,
            'remarks': _remarkCtrl.text.isEmpty ? null : _remarkCtrl.text,
            'date': now,
          });

          // 2. Update inventory
          await DbHelper.txExecute(tx, '''
            UPDATE spare_parts_inventory
            SET quantity_on_hand = quantity_on_hand - @qty
            WHERE part_id = @pid
          ''', params: {
            'qty': qty,
            'pid': item.partId,
          });
        }
      });
      
      if (mounted) {
        ref.invalidate(machineBomProvider(widget.machineId));
        // Need to invalidate spare parts provider if we had one here, but machineBomProvider fetches onHand anyway.
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เบิกอะไหล่แบบกลุ่ม (Bulk Issue)'),
      content: SizedBox(
        width: 800,
        height: 500,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(AppColors.bgElevated),
                  columns: const [
                    DataColumn(label: Text('รหัสอะไหล่')),
                    DataColumn(label: Text('ชื่ออะไหล่')),
                    DataColumn(label: Text('คงเหลือ')),
                    DataColumn(label: Text('จำนวนเบิก (ชิ้น)')),
                  ],
                  rows: widget.selectedItems.map((item) {
                    return DataRow(
                      cells: [
                        DataCell(Text(item.partCode, style: AppTextStyles.labelLarge)),
                        DataCell(Text(item.partName)),
                        DataCell(
                          Text('${item.quantityOnHand}', 
                            style: TextStyle(
                              color: item.quantityOnHand > 0 ? AppColors.success : AppColors.error,
                              fontWeight: FontWeight.bold,
                            )
                          )
                        ),
                        DataCell(
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: SizedBox(
                              width: 100,
                              child: TextField(
                                controller: _qtyControllers[item.partId],
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
            const Divider(height: 32),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _refCtrl,
                    decoration: const InputDecoration(
                      labelText: 'อ้างอิง (เลขที่ใบงาน / PO)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _remarkCtrl,
                    decoration: const InputDecoration(
                      labelText: 'หมายเหตุ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('ยืนยันการเบิก'),
        ),
      ],
    );
  }
}
