import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:empty_view/empty_view.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/database/db_helper.dart';
import '../../features/auth/auth_provider.dart';
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
              if (user?.isTechnicianOrAbove ?? false)
                ElevatedButton.icon(
                  onPressed: () => _showTransactionDialog(context, null, true),
                  icon: const HugeIcon(icon: HugeIcons.strokeRoundedPackageAdd, size: 18, color: Colors.white),
                  label: const Text('รับของเข้า'),
                ),
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
                      );
              },
            ),
          ),
        ),
      ],
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

class _PartsTable extends StatelessWidget {
  final List<SparePart> parts;
  final UserSession? user;
  final void Function(SparePart) onIssue;
  final void Function(SparePart) onReceive;

  const _PartsTable({
    required this.parts,
    this.user,
    required this.onIssue,
    required this.onReceive,
  });

  @override
  Widget build(BuildContext context) {
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
                _H('หมวดหมู่', flex: 2),
                _H('คงเหลือ', flex: 1),
                _H('จอง', flex: 1),
                _H('พร้อมใช้', flex: 1),
                _H('Min Stock', flex: 1),
                _H('ราคา/หน่วย', flex: 2),
                _H('ตำแหน่ง', flex: 2),
                _H('', flex: 2),
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

class _PartRow extends StatelessWidget {
  final SparePart part;
  final UserSession? user;
  final VoidCallback onIssue;
  final VoidCallback onReceive;

  const _PartRow({
    required this.part,
    this.user,
    required this.onIssue,
    required this.onReceive,
  });

  @override
  Widget build(BuildContext context) {
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
              flex: 2,
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
              flex: 2,
              child: Text(
                part.unitCost != null
                    ? NumberFormat('#,##0.00').format(part.unitCost)
                    : '-',
                style: AppTextStyles.bodySmall,
              ),
            ),
            Expanded(
                flex: 2,
                child: Text(part.location ?? '-',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ))),
            Expanded(
              flex: 2,
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
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const HugeIcon(icon: HugeIcons.strokeRoundedPackage, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          '${widget.part!.partCode} — ${widget.part!.partName}',
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
              decoration:
                  const InputDecoration(labelText: 'หมายเหตุ'),
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
        ElevatedButton(
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
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(widget.isReceive ? 'ยืนยันรับเข้า' : 'ยืนยันเบิก'),
        ),
      ],
    );
  }
}
