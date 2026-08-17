import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'spare_parts_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:empty_view/empty_view.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/database/db_helper.dart';
import '../../features/auth/auth_provider.dart';
import '../../core/widgets/hover_image_tooltip.dart';
import 'package:intl/intl.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class SparePart {
  final String partId;
  final String partCode;
  final String partName;
  final String? category;
  final double? unitCost;
  final int reorderLevel;
  final int quantityOnHand;
  final int quantityReserved;
  final String? location;
  final String? supplierName;
  final String? imagePath;

  int get available => quantityOnHand - quantityReserved;
  bool get isLowStock => quantityOnHand <= reorderLevel;

  const SparePart({
    required this.partId,
    required this.partCode,
    required this.partName,
    this.category,
    this.unitCost,
    required this.reorderLevel,
    required this.quantityOnHand,
    required this.quantityReserved,
    this.location,
    this.supplierName,
    this.imagePath,
  });

  factory SparePart.fromMap(Map<String, dynamic> m) => SparePart(
        partId: m['part_id'] as String,
        partCode: m['part_code'] as String,
        partName: m['part_name'] as String,
        category: m['category'] as String?,
        unitCost: (m['unit_cost'] as num?)?.toDouble(),
        reorderLevel: m['reorder_level'] as int? ?? 5,
        quantityOnHand: m['quantity_on_hand'] as int? ?? 0,
        quantityReserved: m['quantity_reserved'] as int? ?? 0,
        location: m['location'] as String?,
        supplierName: m['supplier_name'] as String?,
        imagePath: m['image_path'] as String?,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final sparePartsProvider =
    FutureProvider.family<List<SparePart>, String?>((ref, search) async {
  try {
    final where = <String>['1=1'];
    final params = <String, dynamic>{};
    if (search != null && search.isNotEmpty) {
      where.add(
          '(p.part_code LIKE @s OR p.part_name LIKE @s OR p.category LIKE @s)');
      params['s'] = '%$search%';
    }
    final rows = await DbHelper.query(
      '''SELECT p.*, i.quantity_on_hand, i.quantity_reserved, i.location,
                sup.name as supplier_name
         FROM spare_parts p
         LEFT JOIN spare_parts_inventory i ON i.part_id = p.part_id
         LEFT JOIN suppliers sup ON sup.supplier_id = p.supplier_id
         WHERE p.is_active = 1 AND ${where.join(' AND ')}
         ORDER BY p.part_code''',
      params: params,
    );
    return rows.map(SparePart.fromMap).toList();
  } catch (_) {
    return [];
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Spare Parts List Screen
// ─────────────────────────────────────────────────────────────────────────────

class SparePartsListScreen extends ConsumerStatefulWidget {
  const SparePartsListScreen({super.key});

  @override
  ConsumerState<SparePartsListScreen> createState() =>
      _SparePartsListScreenState();
}

class _SparePartsListScreenState extends ConsumerState<SparePartsListScreen> {
  String _search = '';
  final _searchCtrl = TextEditingController();
  bool _showLowOnly = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final partsAsync = ref.watch(sparePartsProvider(_search.isEmpty ? null : _search));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.lg),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const HugeIcon(icon: HugeIcons.strokeRoundedArchive02,
                        color: AppColors.primary, size: 24),
                    const SizedBox(width: AppSpacing.sm),
                    Text('คลังอะไหล่', style: AppTextStyles.headlineLarge),
                  ]),
                  const SizedBox(height: 4),
                  Text('Spare Parts & Inventory Management',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
              const Spacer(),
              if (user?.isTechnicianOrAbove ?? false) ...[
                OutlinedButton.icon(
                  onPressed: () {
                    partsAsync.whenData((parts) => _exportPdf(parts));
                  },
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedFileExport, size: 18, color: Colors.black),
                  label: const Text('Export PDF'),
                ),
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: () => _showAddSparePartDialog(context),
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedAdd01, size: 18, color: AppColors.primary),
                  label: const Text('เพิ่มอะไหล่ใหม่'),
                ),
              ],
            ],
          ),
        ),

        // Toolbar
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.lg),
          child: Row(
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'ค้นหารหัส / ชื่ออะไหล่...',
                    prefixIcon: Padding(
                      padding: EdgeInsets.all(12),
                      child: HugeIcon(icon: HugeIcons.strokeRoundedSearch01, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Low stock toggle
              partsAsync.whenOrNull(
                    data: (parts) {
                      final lowCount =
                          parts.where((p) => p.isLowStock).length;
                      return lowCount > 0
                          ? GestureDetector(
                              onTap: () =>
                                  setState(() => _showLowOnly = !_showLowOnly),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _showLowOnly
                                      ? AppColors.error.withValues(alpha: 0.15)
                                      : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.full),
                                  border: Border.all(
                                    color: _showLowOnly
                                        ? AppColors.error
                                        : Theme.of(context)
                                            .colorScheme
                                            .outline,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle,
                                        size: 14,
                                        color: _showLowOnly
                                            ? AppColors.error
                                            : Theme.of(context).colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 6),
                                    Text(
                                      'สต็อกต่ำ ($lowCount)',
                                      style: AppTextStyles.labelMedium.copyWith(
                                        color: _showLowOnly
                                            ? AppColors.error
                                            : Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink();
                    },
                  ) ??
                  const SizedBox.shrink(),
              const Spacer(),
              partsAsync.whenOrNull(
                    data: (p) => Text('${p.length} รายการ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            )),
                  ) ??
                  const SizedBox.shrink(),
              const SizedBox(width: AppSpacing.md),
              IconButton(
                icon: HugeIcon(icon: HugeIcons.strokeRoundedRefresh, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                onPressed: () => ref.invalidate(sparePartsProvider),
                tooltip: 'รีเฟรช',
              ),
            ],
          ),
        ),

        // Table
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.xxl),
            child: partsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (parts) {
                final filtered = _showLowOnly
                    ? parts.where((p) => p.isLowStock).toList()
                    : parts;
                return filtered.isEmpty
                    ? _EmptyParts()
                    : _PartsTable(
                        parts: filtered,
                        user: user,
                        onIssue: (p) =>
                            _showTransactionDialog(context, p, false),
                        onReceive: (p) =>
                            _showTransactionDialog(context, p, true),
                        onStockCard: (p) => showDialog(
                          context: context,
                          barrierDismissible: true,
                          builder: (_) => _SparePartStockCardDialog(part: p),
                        ),
                      );
              },
            ),
          ),
        ),
      ],
    );
  }
  void _showAddSparePartDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SparePartFormDialog(),
    );
  }


  void _showTransactionDialog(
      BuildContext context, SparePart? part, bool isReceive) {
    showDialog(
      context: context,
      builder: (ctx) => _TransactionDialog(
        part: part,
        isReceive: isReceive,
        onConfirm: (partId, qty, refId, remarks) async {
          await DbHelper.transaction((tx) async {
            final now = DateTime.now().toIso8601String();
            await DbHelper.txExecute(tx, '''
              INSERT INTO spare_parts_transactions
                (trans_id, part_id, trans_type, quantity, reference_id, remarks, trans_date)
              VALUES (@tid, @pid, @type, @qty, @ref, @remarks, @date)
            ''', params: {
              'tid':
                  'TXN-${DateTime.now().millisecondsSinceEpoch}',
              'pid': partId,
              'type': isReceive ? 'in' : 'out',
              'qty': isReceive ? qty : -qty,
              'ref': refId,
              'remarks': remarks,
              'date': now,
            });
            final delta = isReceive ? qty : -qty;
            await DbHelper.txExecute(tx, '''
              UPDATE spare_parts_inventory
              SET quantity_on_hand = MAX(0, quantity_on_hand + @delta),
                  updated_at = @now
              WHERE part_id = @pid
            ''', params: {'delta': delta, 'now': now, 'pid': partId});
            return true;
          });
          ref.invalidate(sparePartsProvider);
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Table
// ─────────────────────────────────────────────────────────────────────────────

class _PartsTable extends ConsumerWidget {
  final List<SparePart> parts;
  final UserSession? user;
  final void Function(SparePart) onIssue;
  final void Function(SparePart) onReceive;
  final void Function(SparePart) onStockCard;

  const _PartsTable({
    required this.parts,
    this.user,
    required this.onIssue,
    required this.onReceive,
    required this.onStockCard,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppRadius.lg),
                topRight: Radius.circular(AppRadius.lg),
              ),
            ),
            child: const Row(
              children: [
                _H('รหัสอะไหล่', flex: 2),
                _H('ชื่ออะไหล่', flex: 4),
                _H('หมวดหมู่', flex: 1),
                _H('คงเหลือ', flex: 1),
                _H('จอง', flex: 1),
                _H('พร้อมใช้', flex: 1),
                _H('Min Stock', flex: 1),
                _H('ราคา/หน่วย', flex: 1),
                _H('ตำแหน่ง', flex: 1),
                _H('', flex: 5),
              ],
            ),
          ),
          Container(
              height: 1,
              color: Theme.of(context).colorScheme.outline),
          Expanded(
            child: ListView.separated(
              itemCount: parts.length,
              separatorBuilder: (context, index) => Container(
                height: 1,
                color: Theme.of(context)
                    .colorScheme
                    .outline
                    .withValues(alpha: 0.3),
              ),
              itemBuilder: (context, i) {
                final p = parts[i];
                return _PartRow(
                  part: p,
                  user: user,
                  onIssue: () => onIssue(p),
                  onReceive: () => onReceive(p),
                  onStockCard: () => onStockCard(p),
                  onEdit: () {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => _SparePartFormDialog(part: p),
                    );
                  },
                  onDelete: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (c) => AlertDialog(
                        title: const Text('ยืนยันการลบ'),
                        content: Text('คุณต้องการลบอะไหล่ \${p.partCode} ใช่หรือไม่?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('ยกเลิก'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(c, true),
                            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                            child: const Text('ลบข้อมูล'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref.read(sparePartsRepoProvider).deleteSparePart(p.partId);
                      ref.invalidate(sparePartsProvider);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _H extends StatelessWidget {
  final String label;
  final int flex;
  const _H(this.label, {this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold,
              )),
    );
  }
}

class _PartRow extends ConsumerWidget {
  final SparePart part;
  final UserSession? user;
  final VoidCallback onIssue;
  final VoidCallback onReceive;
  final VoidCallback onStockCard;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PartRow({
    required this.part,
    this.user,
    required this.onIssue,
    required this.onReceive,
    required this.onStockCard,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLow = part.isLowStock;
    return Container(
      color: isLow
          ? AppColors.error.withValues(alpha: 0.04)
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  if (isLow)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle,
                          size: 14, color: AppColors.error),
                    ),
                  Text(part.partCode,
                      style: AppTextStyles.labelMedium
                          .copyWith(color: AppColors.primary)),
                  if (part.imagePath != null && part.imagePath!.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    HoverImageTooltip(imagePath: part.imagePath),
                  ],
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(part.partName,
                  style: AppTextStyles.bodySmall,
                  overflow: TextOverflow.ellipsis),
            ),
            Expanded(
              flex: 1,
              child: Text(part.category ?? '-',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )),
            ),
            Expanded(
                flex: 1,
                child: Text('${part.quantityOnHand}',
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: isLow ? AppColors.error : null,
                        fontWeight:
                            isLow ? FontWeight.w700 : FontWeight.w400))),
            Expanded(
                flex: 1,
                child: Text('${part.quantityReserved}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ))),
            Expanded(
                flex: 1,
                child: Text('${part.available}',
                    style: AppTextStyles.bodyMedium.copyWith(
                        color: part.available <= 0
                            ? AppColors.error
                            : AppColors.success))),
            Expanded(
                flex: 1,
                child: Text('${part.reorderLevel}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ))),
            Expanded(
              flex: 1,
              child: Text(
                part.unitCost != null
                    ? NumberFormat('#,##0.00').format(part.unitCost)
                    : '-',
                style: AppTextStyles.bodySmall,
              ),
            ),
            Expanded(
                flex: 1,
                child: Text(part.location ?? '-',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ))),
            Expanded(
              flex: 5,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                    if (user?.isTechnicianOrAbove ?? false) ...[
                      TextButton(
                        onPressed: onReceive,
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            foregroundColor: AppColors.success),
                        child: const Text('รับเข้า', style: TextStyle(fontSize: 12)),
                      ),
                      TextButton(
                        onPressed: onIssue,
                        style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            foregroundColor: AppColors.warning),
                        child: const Text('เบิก', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      _SparePartImageHover(imagePath: part.imagePath),
                      IconButton(
                        onPressed: onStockCard,
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedCardExchange01, size: 16, color: Colors.blue),
                        tooltip: 'Stock Card',
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: onEdit,
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedEdit01, size: 16, color: AppColors.textSecondary),
                        tooltip: 'แก้ไข',
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: onDelete,
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
      ),
    );
  }
}

class _EmptyParts extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return EmptyView(
      title: 'ไม่มีข้อมูลอะไหล่',
      description: 'ยังไม่มีรายการอะไหล่ในระบบ',
      onButtonTap: () {},
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _TransactionDialog extends StatefulWidget {
  final SparePart? part;
  final bool isReceive;
  final Future<void> Function(
      String partId, int qty, String? refId, String? remarks) onConfirm;

  const _TransactionDialog({
    this.part,
    required this.isReceive,
    required this.onConfirm,
  });

  @override
  State<_TransactionDialog> createState() => _TransactionDialogState();
}

class _TransactionDialogState extends State<_TransactionDialog> {
  final _qtyCtrl = TextEditingController(text: '1');
  final _refCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isReceive ? 'รับของเข้าคลัง' : 'เบิกของออกจากคลัง'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.part != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const HugeIcon(icon: HugeIcons.strokeRoundedPackage, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          '${widget.part!.partCode} - ${widget.part!.partName}',
                          style: AppTextStyles.labelMedium),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                  labelText: 'จำนวน',
                  suffixText: widget.part?.partName != null ? 'ชิ้น' : null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _refCtrl,
              decoration: const InputDecoration(
                  labelText: 'อ้างอิง (เลขที่ใบงาน / PO)'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _remarkCtrl,
              decoration: const InputDecoration(labelText: 'หมายเหตุ'),
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
          onPressed: _saving
              ? null
              : () async {
                  final qty = int.tryParse(_qtyCtrl.text) ?? 0;
                  if (qty <= 0 || widget.part == null) return;
                  setState(() => _saving = true);
                  await widget.onConfirm(
                    widget.part!.partId,
                    qty,
                    _refCtrl.text.isEmpty ? null : _refCtrl.text,
                    _remarkCtrl.text.isEmpty ? null : _remarkCtrl.text,
                  );
                },
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(widget.isReceive ? 'ยืนยันรับของ' : 'ยืนยันเบิกของ'),
        ),
      ],
    );
  }
}


class _SparePartImageHover extends StatelessWidget {
  final String? imagePath;
  const _SparePartImageHover({this.imagePath});

  @override
  Widget build(BuildContext context) {
    if (imagePath == null) return const SizedBox.shrink();

    return Tooltip(
      preferBelow: false,
      decoration: BoxDecoration(
        color: AppColors.bgSurface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      richMessage: WidgetSpan(
        child: Container(
          constraints: const BoxConstraints(maxHeight: 200, maxWidth: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
          ),
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

class _SparePartFormDialog extends ConsumerStatefulWidget {
  final SparePart? part;
  const _SparePartFormDialog({this.part});

  @override
  ConsumerState<_SparePartFormDialog> createState() => _SparePartFormDialogState();
}

class _SparePartFormDialogState extends ConsumerState<_SparePartFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _codeCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _categoryCtrl;
  late TextEditingController _unitCostCtrl;
  late TextEditingController _reorderLevelCtrl;
  String? _imagePath;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _codeCtrl = TextEditingController(text: widget.part?.partCode);
    _nameCtrl = TextEditingController(text: widget.part?.partName);
    _categoryCtrl = TextEditingController(text: widget.part?.category);
    _unitCostCtrl = TextEditingController(text: widget.part?.unitCost?.toString() ?? '');
    _reorderLevelCtrl = TextEditingController(text: widget.part?.reorderLevel.toString() ?? '5');
    _imagePath = widget.part?.imagePath;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _unitCostCtrl.dispose();
    _reorderLevelCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result != null && result.files.single.path != null) {
        setState(() {
          _imagePath = result.files.single.path;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    
    try {
      final repo = ref.read(sparePartsRepoProvider);
      if (widget.part == null) {
        await repo.addSparePart(
          partCode: _codeCtrl.text.trim(),
          partName: _nameCtrl.text.trim(),
          category: _categoryCtrl.text.trim(),
          unitCost: double.tryParse(_unitCostCtrl.text.trim()),
          reorderLevel: int.tryParse(_reorderLevelCtrl.text.trim()) ?? 5,
          imagePath: _imagePath,
        );
      } else {
        await repo.updateSparePart(
          partId: widget.part!.partId,
          partCode: _codeCtrl.text.trim(),
          partName: _nameCtrl.text.trim(),
          category: _categoryCtrl.text.trim(),
          unitCost: double.tryParse(_unitCostCtrl.text.trim()),
          reorderLevel: int.tryParse(_reorderLevelCtrl.text.trim()) ?? 5,
          imagePath: _imagePath,
        );
      }
      
      if (mounted) {
        ref.invalidate(sparePartsProvider);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.part == null ? 'เพิ่มอะไหล่ใหม่' : 'แก้ไขอะไหล่'),
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
                  controller: _codeCtrl,
                  decoration: const InputDecoration(labelText: 'รหัสอะไหล่ (Part Code) *'),
                  validator: (v) => v == null || v.isEmpty ? 'กรุณากรอกข้อมูล' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(labelText: 'ชื่ออะไหล่ (Part Name) *'),
                  validator: (v) => v == null || v.isEmpty ? 'กรุณากรอกข้อมูล' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  controller: _categoryCtrl,
                  decoration: const InputDecoration(labelText: 'หมวดหมู่ (Category)'),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _unitCostCtrl,
                        decoration: const InputDecoration(labelText: 'ราคาต่อหน่วย (Unit Cost)'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextFormField(
                        controller: _reorderLevelCtrl,
                        decoration: const InputDecoration(labelText: 'จุดสั่งซื้อ (Reorder Level)'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('บันทึก'),
        ),
      ],
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Stock Card Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _SparePartStockCardDialog extends StatefulWidget {
  final SparePart part;
  const _SparePartStockCardDialog({required this.part});

  @override
  State<_SparePartStockCardDialog> createState() => _SparePartStockCardDialogState();
}

class _SparePartStockCardDialogState extends State<_SparePartStockCardDialog> {
  late Future<List<Map<String, dynamic>>> _transactionsFuture;

  @override
  void initState() {
    super.initState();
    _transactionsFuture = _fetchTransactions();
  }

  Future<List<Map<String, dynamic>>> _fetchTransactions() async {
    return await DbHelper.query(
      'SELECT * FROM spare_parts_transactions WHERE part_id = @pid ORDER BY trans_date DESC',
      params: {'pid': widget.part.partId},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 800,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const HugeIcon(icon: HugeIcons.strokeRoundedCardExchange01, size: 28, color: AppColors.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stock Card: ', style: AppTextStyles.titleLarge),
                      Text('', style: AppTextStyles.bodyMedium.copyWith(color: Colors.grey)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const Divider(height: 32),
            Expanded(
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: _transactionsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(child: Text('Error: '));
                  }
                  final txs = snapshot.data ?? [];
                  if (txs.isEmpty) {
                    return const Center(child: Text('ไม่มีประวัติการทำรายการ'));
                  }
                  
                  int currentBalance = widget.part.quantityOnHand;
                  List<Map<String, dynamic>> enrichedTxs = [];
                  for (final tx in txs) {
                    final qty = (tx['quantity'] as num).toInt();
                    final enriched = Map<String, dynamic>.from(tx);
                    enriched['running_balance'] = currentBalance;
                    enrichedTxs.add(enriched);
                    currentBalance -= qty;
                  }
                  
                  return SingleChildScrollView(
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2), // Date
                        1: FlexColumnWidth(1), // Type
                        2: FlexColumnWidth(1), // Qty
                        3: FlexColumnWidth(1), // Balance
                        4: FlexColumnWidth(2), // Ref
                        5: FlexColumnWidth(2), // Remarks
                      },
                      border: TableBorder(
                        horizontalInside: BorderSide(color: Colors.grey.shade200),
                        bottom: BorderSide(color: Colors.grey.shade200),
                      ),
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: Colors.grey.shade100),
                          children: [
                            _th('วันที่/เวลา'),
                            _th('ประเภท'),
                            _th('จำนวน'),
                            _th('คงเหลือ'),
                            _th('อ้างอิง'),
                            _th('หมายเหตุ'),
                          ],
                        ),
                        for (final tx in enrichedTxs)
                          TableRow(
                            children: [
                              _td(DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(tx['trans_date']))),
                              _tdType(tx['trans_type']),
                              _td((tx['quantity'] as num) > 0 ? '+${tx['quantity']}' : tx['quantity'].toString(), bold: true),
                              _td(tx['running_balance'].toString(), bold: true),
                              _td(tx['reference_id']?.toString() ?? '-'),
                              _td(tx['remarks']?.toString() ?? '-'),
                            ],
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _th(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }

  Widget _td(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Text(text, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
    );
  }

  Widget _tdType(String type) {
    final isRecv = type == 'in';
    final color = isRecv ? Colors.green : Colors.orange;
    final text = isRecv ? 'รับเข้า' : 'เบิกออก';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Text(text, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      ),
    );
  }
}  Future<void> _exportPdf(List<SparePart> parts) async {
    final fontData = await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf');
    final fontBoldData = await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf');
    final ttf = pw.Font.ttf(fontData);
    final ttfBold = pw.Font.ttf(fontBoldData);

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        theme: pw.ThemeData(defaultTextStyle: pw.TextStyle(font: ttf, fontSize: 10)),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('รายงานทะเบียนคลังอะไหล่ (Spare Parts Inventory)', style: pw.TextStyle(font: ttfBold, fontSize: 18)),
            pw.SizedBox(height: 10),
          ]
        ),
        build: (context) => [
          pw.TableHelper.fromTextArray(
            headers: ['รหัสอะไหล่', 'ชื่ออะไหล่', 'หมวดหมู่', 'คงเหลือ', 'จอง', 'พร้อมใช้', 'Min Stock', 'ราคา/หน่วย', 'ตำแหน่ง'],
            headerStyle: pw.TextStyle(font: ttfBold, fontSize: 10),
            cellStyle: pw.TextStyle(font: ttf, fontSize: 9),
            headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
            data: parts.map((p) => [
              p.partCode,
              p.partName,
              p.category ?? 'Others',
              p.quantityOnHand.toString(),
              p.quantityReserved.toString(),
              p.available.toString(),
              p.reorderLevel.toString(),
              p.unitCost?.toStringAsFixed(2) ?? '-',
              p.location ?? '-',
            ]).toList(),
          ),
        ],
      ),
    );

    final bytes = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}\\Spare_Parts_Inventory_Report_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(bytes);
    
    if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', file.path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [file.path]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [file.path]);
    }
  }


