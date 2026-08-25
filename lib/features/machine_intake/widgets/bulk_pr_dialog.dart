import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/database/db_helper.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../machine_models.dart';

class BulkPRDialog extends ConsumerStatefulWidget {
  final List<MachineBomItem> selectedItems;
  final String machineId;

  const BulkPRDialog({
    super.key,
    required this.selectedItems,
    required this.machineId,
  });

  @override
  ConsumerState<BulkPRDialog> createState() => _BulkPRDialogState();
}

class _BulkPRDialogState extends ConsumerState<BulkPRDialog> {
  final _remarkCtrl = TextEditingController();
  
  // Map of partId to quantity controller
  final Map<String, TextEditingController> _qtyControllers = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    for (var item in widget.selectedItems) {
      // Default request quantity is QPA minus available stock
      int defaultQty = item.quantity - item.quantityOnHand;
      if (defaultQty <= 0) defaultQty = 1; // Default to at least 1 for PR
      
      _qtyControllers[item.partId] = TextEditingController(text: defaultQty.toString());
    }
  }

  @override
  void dispose() {
    _remarkCtrl.dispose();
    for (var ctrl in _qtyControllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    
    try {
      await DbHelper.transaction((tx) async {
        final prId = const Uuid().v4();
        // Generate a simple PR number like PR-YYYYMMDD-HHMMSS
        final now = DateTime.now();
        final prNo = "PR-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}";
        
        // 1. Insert Purchase Request
        await DbHelper.txExecute(tx, '''
          INSERT INTO purchase_requests
            (pr_id, pr_no, requested_by, status, remarks)
          VALUES (@id, @no, NULL, 'draft', @remarks)
        ''', params: {
          'id': prId,
          'no': prNo,
          'remarks': _remarkCtrl.text.isEmpty ? null : _remarkCtrl.text,
        });

        // 2. Insert Items
        for (var item in widget.selectedItems) {
          final text = _qtyControllers[item.partId]?.text ?? '0';
          final qty = int.tryParse(text) ?? 0;
          
          if (qty <= 0) continue; // Skip zero quantities

          // Try to get unit_cost and supplier_id from spare_parts
          final partRow = await DbHelper.txQueryOne(tx, '''
            SELECT unit_cost, supplier_id FROM spare_parts WHERE part_id = @pid
          ''', params: {'pid': item.partId});

          final prItemId = const Uuid().v4();
          
          await DbHelper.txExecute(tx, '''
            INSERT INTO purchase_request_items
              (pr_item_id, pr_id, part_id, quantity, unit_cost, supplier_id)
            VALUES (@itemId, @prId, @partId, @qty, @cost, @supp)
          ''', params: {
            'itemId': prItemId,
            'prId': prId,
            'partId': item.partId,
            'qty': qty,
            'cost': partRow?['unit_cost'],
            'supp': partRow?['supplier_id'],
          });
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('สร้างใบขอซื้อ (Draft) สำเร็จ')),
        );
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
      title: const Text('ออกใบขอซื้อ (Purchase Request)'),
      content: SizedBox(
        width: 800,
        height: 500,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(Theme.of(context).colorScheme.surfaceContainerHighest),
                  columns: const [
                    DataColumn(label: Text('รหัสอะไหล่')),
                    DataColumn(label: Text('ชื่ออะไหล่')),
                    DataColumn(label: Text('คงเหลือ')),
                    DataColumn(label: Text('จำนวนขอซื้อ')),
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
            TextField(
              controller: _remarkCtrl,
              decoration: const InputDecoration(
                labelText: 'หมายเหตุ PR',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
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
              : const Text('สร้างใบขอซื้อ'),
        ),
      ],
    );
  }
}
