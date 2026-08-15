import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

import '../machine_provider.dart';
import 'dart:async';
import 'bulk_issue_dialog.dart';
import 'bulk_pr_dialog.dart';

class MachineBomStep extends ConsumerStatefulWidget {
  final String machineId;
  final bool enabled;

  const MachineBomStep({
    super.key,
    required this.machineId,
    required this.enabled,
  });

  @override
  ConsumerState<MachineBomStep> createState() => _MachineBomStepState();
}

class _MachineBomStepState extends ConsumerState<MachineBomStep> {
  final Set<String> _selectedMapIds = {};

  Future<void> _addPart() async {
    if (!widget.enabled) return;

    final selected = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _AddPartDialog(),
    );

    if (selected != null) {
      final partId = selected['part_id'] as String;
      final quantity = selected['quantity'] as int? ?? 1;

      try {
        await ref.read(machineRepositoryProvider).addMachineBomItem(
              machineId: widget.machineId,
              partId: partId,
              quantity: quantity,
            );
        ref.invalidate(machineBomProvider(widget.machineId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('เพิ่มอะไหล่ประจำเครื่องแล้ว')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
          );
        }
      }
    }
  }

  Future<void> _removePart(String mapId) async {
    if (!widget.enabled) return;
    try {
      await ref.read(machineRepositoryProvider).removeMachineBomItem(mapId);
      setState(() => _selectedMapIds.remove(mapId));
      ref.invalidate(machineBomProvider(widget.machineId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    }
  }
  
  Future<void> _updateQuantity(String mapId, int currentQty) async {
    if (!widget.enabled) return;
    
    final ctrl = TextEditingController(text: currentQty.toString());
    final newQtyStr = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('แก้ไขจำนวน (Quantity)'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'จำนวนที่ใช้ในเครื่องนี้'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('บันทึก')),
        ],
      ),
    );
    
    if (newQtyStr != null && int.tryParse(newQtyStr) != null) {
      final q = int.parse(newQtyStr);
      if (q > 0) {
         await ref.read(machineRepositoryProvider).updateMachineBomItemQuantity(mapId, q);
         ref.invalidate(machineBomProvider(widget.machineId));
      }
    }
  }

  void _toggleSelection(String mapId, bool? value) {
    setState(() {
      if (value == true) {
        _selectedMapIds.add(mapId);
      } else {
        _selectedMapIds.remove(mapId);
      }
    });
  }

  Future<void> _issueParts() async {
    final bomItems = ref.read(machineBomProvider(widget.machineId)).valueOrNull;
    if (bomItems == null) return;
    
    final selectedParts = bomItems.where((item) => _selectedMapIds.contains(item.mapId)).toList();
    if (selectedParts.isEmpty) return;

    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BulkIssueDialog(
        machineId: widget.machineId,
        selectedItems: selectedParts,
      ),
    );

    if (result == true) {
      setState(() {
        _selectedMapIds.clear();
      });
    }
  }

  Future<void> _createPurchaseRequest() async {
    final bomItems = ref.read(machineBomProvider(widget.machineId)).valueOrNull;
    if (bomItems == null) return;
    
    final selectedParts = bomItems.where((item) => _selectedMapIds.contains(item.mapId)).toList();
    if (selectedParts.isEmpty) return;

    final result = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => BulkPRDialog(
        machineId: widget.machineId,
        selectedItems: selectedParts,
      ),
    );

    if (result == true) {
      setState(() {
        _selectedMapIds.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bomAsync = ref.watch(machineBomProvider(widget.machineId));

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('รายการอะไหล่ประจำเครื่อง (Machine BOM)',
                          style: AppTextStyles.titleLarge),
                      const SizedBox(height: 4),
                      Text('อะไหล่ที่ใช้กับเครื่องจักรนี้ เพื่อความสะดวกในการเบิกหรือขอซื้อ',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              )),
                    ],
                  ),
                ),
                if (widget.enabled)
                  FilledButton.icon(
                    onPressed: _addPart,
                    icon: const Icon(Icons.add_rounded, size: 20),
                    label: const Text('เพิ่มอะไหล่'),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            
            if (_selectedMapIds.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Text('เลือกไว้ ${_selectedMapIds.length} รายการ', 
                      style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: _issueParts,
                      icon: const Icon(Icons.outbox_rounded, size: 18),
                      label: const Text('เบิกอะไหล่'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _createPurchaseRequest,
                      icon: const Icon(Icons.shopping_cart_rounded, size: 18),
                      label: const Text('ออกใบขอซื้อ'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            bomAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(48.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          Text('ยังไม่มีอะไหล่ประจำเครื่อง', style: AppTextStyles.titleMedium),
                          const SizedBox(height: 8),
                          Text('กด "เพิ่มอะไหล่" เพื่อเพิ่มรายการอะไหล่ที่ใช้กับเครื่องจักรนี้', 
                            style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  );
                }

                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Material(
                    type: MaterialType.transparency,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(Theme.of(context).colorScheme.surfaceContainerHighest),
                      columns: const [
                        DataColumn(label: Text('')),
                        DataColumn(label: Text('รหัสอะไหล่')),
                        DataColumn(label: Text('ชื่ออะไหล่')),
                        DataColumn(label: Text('QPA'), tooltip: 'Quantity Per Assembly (จำนวนที่ใช้)'),
                        DataColumn(label: Text('คงเหลือ')),
                        DataColumn(label: Text('จัดการ')),
                      ],
                      rows: items.map((item) {
                        final isSelected = _selectedMapIds.contains(item.mapId);
                        final stockColor = item.quantityOnHand > 0 ? AppColors.success : AppColors.error;
                        
                        return DataRow(
                          selected: isSelected,
                          onSelectChanged: (val) => _toggleSelection(item.mapId, val),
                          cells: [
                            DataCell(
                              Checkbox(
                                value: isSelected,
                                onChanged: (val) => _toggleSelection(item.mapId, val),
                              ),
                            ),
                            DataCell(Text(item.partCode, style: AppTextStyles.labelLarge)),
                            DataCell(Text(item.partName)),
                            DataCell(
                              InkWell(
                                onTap: () => _updateQuantity(item.mapId, item.quantity),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('${item.quantity}'),
                                      if (widget.enabled) ...[
                                        const SizedBox(width: 4),
                                        const Icon(Icons.edit, size: 14, color: Colors.grey),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            DataCell(
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: stockColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text('${item.quantityOnHand}', 
                                  style: TextStyle(color: stockColor, fontWeight: FontWeight.bold)),
                              ),
                            ),
                            DataCell(
                              IconButton(
                                icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete02, color: AppColors.error, size: 20),
                                onPressed: widget.enabled ? () => _removePart(item.mapId) : null,
                                tooltip: 'ลบออกจากเครื่องจักรนี้',
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error: $e')),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPartDialog extends ConsumerStatefulWidget {
  @override
  ConsumerState<_AddPartDialog> createState() => _AddPartDialogState();
}

class _AddPartDialogState extends ConsumerState<_AddPartDialog> {
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  List<Map<String, dynamic>> _searchResults = [];
  Map<String, dynamic>? _selectedPart;
  bool _searching = false;
  Timer? _debounce;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (query.isEmpty) {
        setState(() {
          _searchResults = [];
          _selectedPart = null;
        });
        return;
      }
      setState(() => _searching = true);
      try {
        final res = await ref.read(machineRepositoryProvider).searchSpareParts(query);
        setState(() {
          _searchResults = res;
          _searching = false;
        });
      } catch (e) {
        setState(() => _searching = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เพิ่มอะไหล่ประจำเครื่อง'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _searchCtrl,
              decoration: const InputDecoration(
                labelText: 'ค้นหาอะไหล่ (รหัส หรือ ชื่อ)',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: _onSearchChanged,
            ),
            const SizedBox(height: 16),
            if (_searching)
              const Center(child: CircularProgressIndicator())
            else if (_searchResults.isNotEmpty)
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _searchResults.length,
                  itemBuilder: (ctx, i) {
                    final p = _searchResults[i];
                    final isSelected = _selectedPart?['part_id'] == p['part_id'];
                    return ListTile(
                      title: Text(p['part_code'] ?? ''),
                      subtitle: Text(p['part_name'] ?? ''),
                      selected: isSelected,
                      selectedTileColor: AppColors.primary.withOpacity(0.1),
                      onTap: () => setState(() => _selectedPart = p),
                    );
                  },
                ),
              )
            else if (_searchCtrl.text.isNotEmpty)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(child: Text('ไม่พบอะไหล่')),
              ),
              
            if (_selectedPart != null) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _qtyCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'จำนวนที่ใช้ต่อ 1 เครื่อง (QPA)',
                  border: OutlineInputBorder(),
                ),
              ),
            ]
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: _selectedPart == null
              ? null
              : () {
                  final qty = int.tryParse(_qtyCtrl.text) ?? 1;
                  Navigator.pop(context, {
                    'part_id': _selectedPart!['part_id'],
                    'quantity': qty > 0 ? qty : 1,
                  });
                },
          child: const Text('ตกลง'),
        ),
      ],
    );
  }
}
