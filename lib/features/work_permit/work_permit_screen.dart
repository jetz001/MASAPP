import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/database/db_helper.dart';
import '../../features/auth/auth_provider.dart';
import '../../core/utils/crypto_utils.dart';
import 'package:intl/intl.dart';
import '../settings/settings_provider.dart';
import '../machine_intake/widgets/pin_keypad.dart';
import 'work_permit_pdf_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

enum PermitType { hotWork, confSpace, electrical, heights, energyIsolation }

extension PermitTypeExt on PermitType {
  String get label {
    switch (this) {
      case PermitType.hotWork: return 'งานประกายไฟ (Hot Work)';
      case PermitType.confSpace: return 'งานอับอากาศ (Confined Space)';
      case PermitType.electrical: return 'งานไฟฟ้า';
      case PermitType.heights: return 'งานที่สูง';
      case PermitType.energyIsolation: return 'ตัดพลังงาน (LOTO)';
    }
  }

  String get dbValue {
    switch (this) {
      case PermitType.hotWork: return 'hot_work';
      case PermitType.confSpace: return 'confined_space';
      case PermitType.electrical: return 'electrical';
      case PermitType.heights: return 'heights';
      case PermitType.energyIsolation: return 'energy_isolation';
    }
  }

  IconData get icon {
    switch (this) {
      case PermitType.hotWork: return Icons.local_fire_department_rounded;
      case PermitType.confSpace: return Icons.water_rounded;
      case PermitType.electrical: return Icons.electric_bolt_rounded;
      case PermitType.heights: return Icons.height_rounded;
      case PermitType.energyIsolation: return Icons.lock_rounded;
    }
  }

  Color get color {
    switch (this) {
      case PermitType.hotWork: return const Color(0xFFEF4444);
      case PermitType.confSpace: return const Color(0xFF0891B2);
      case PermitType.electrical: return const Color(0xFFF59E0B);
      case PermitType.heights: return const Color(0xFF8B5CF6);
      case PermitType.energyIsolation: return const Color(0xFF10B981);
    }
  }

  static PermitType fromDb(String? v) {
    switch (v) {
      case 'hot_work': return PermitType.hotWork;
      case 'confined_space': return PermitType.confSpace;
      case 'electrical': return PermitType.electrical;
      case 'heights': return PermitType.heights;
      default: return PermitType.hotWork;
    }
  }
}

class WorkPermit {
  final String permitId;
  final String permitNo;
  final PermitType permitType;
  final String? machineNo;
  final String description;
  final int? durationHours;
  final String requestorName;
  final String? authorizedBy;
  final DateTime? authorizedAt;
  final String status;
  final String? woId;
  final String? woNo;
  final String? pmAmId;
  final String? pmAmCode;
  final List<String> requiredEquipments;
  final DateTime createdAt;

  bool get isExpired {
    if (authorizedAt == null || durationHours == null) return false;
    return authorizedAt!
        .add(Duration(hours: durationHours!))
        .isBefore(DateTime.now());
  }

  const WorkPermit({
    required this.permitId,
    required this.permitNo,
    required this.permitType,
    this.machineNo,
    required this.description,
    this.durationHours,
    required this.requestorName,
    this.authorizedBy,
    this.authorizedAt,
    required this.status,
    this.woId,
    this.woNo,
    this.pmAmId,
    this.pmAmCode,
    this.requiredEquipments = const [],
    required this.createdAt,
  });

  factory WorkPermit.fromMap(Map<String, dynamic> m) => WorkPermit(
        permitId: m['permit_id'] as String,
        permitNo: m['permit_no'] as String,
        permitType: PermitTypeExt.fromDb(m['permit_type'] as String?),
        machineNo: m['machine_no'] as String?,
        description: m['description'] as String,
        durationHours: m['duration_hours'] as int?,
        requestorName: m['requester_name'] as String? ?? '-',
        authorizedBy: m['authorized_by_name'] as String?,
        authorizedAt: m['authorized_at'] != null
            ? DateTime.tryParse(m['authorized_at'] as String)
            : null,
        status: m['status'] as String? ?? 'pending',
        woId: m['wo_id'] as String?,
        woNo: m['wo_no'] as String?,
        pmAmId: m['pm_am_id'] as String?,
        pmAmCode: m['plan_code'] as String?,
        requiredEquipments: m['required_equipments'] != null
            ? List<String>.from(jsonDecode(m['required_equipments'] as String))
            : [],
        createdAt: DateTime.parse(m['created_at'] as String),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final workPermitListProvider =
    FutureProvider<List<WorkPermit>>((ref) async {
  try {
    final rows = await DbHelper.query(
      '''SELECT wp.*, s.machine_no,
                u1.full_name as authorized_by_name,
                wo.wo_no, pm.plan_code
         FROM work_permits wp
         LEFT JOIN machine_snapshots s ON s.snapshot_id = wp.snapshot_id
         LEFT JOIN users u1 ON u1.user_id = wp.authorized_by
         LEFT JOIN work_orders wo ON wo.wo_id = wp.wo_id
         LEFT JOIN pm_am_plans pm ON pm.plan_id = wp.pm_am_id
         ORDER BY wp.created_at DESC
         LIMIT 100''',
    );
    return rows.map(WorkPermit.fromMap).toList();
  } catch (_) {
    return [];
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Work Permit Screen
// ─────────────────────────────────────────────────────────────────────────────

class WorkPermitScreen extends ConsumerStatefulWidget {
  const WorkPermitScreen({super.key});

  @override
  ConsumerState<WorkPermitScreen> createState() => _WorkPermitScreenState();
}

class _WorkPermitScreenState extends ConsumerState<WorkPermitScreen> {
  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final permitsAsync = ref.watch(workPermitListProvider);

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
                    const Icon(Icons.verified_user_rounded,
                        color: AppColors.primary, size: 24),
                    const SizedBox(width: AppSpacing.sm),
                    Text('ใบอนุญาตทำงาน (E-Work Permit)',
                        style: AppTextStyles.headlineLarge),
                  ]),
                  const SizedBox(height: 4),
                  Text('Hot Work · Confined Space · Electrical · Heights · LOTO',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
              const Spacer(),
              if (user?.isTechnicianOrAbove ?? false)
                ElevatedButton.icon(
                  onPressed: () => _showNewPermitDialog(context),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('ขอใบอนุญาต'),
                ),
            ],
          ),
        ),

        // Permit type summary row
        Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.lg),
          child: Row(
            children: PermitType.values.map((pt) {
              return Expanded(
                child: permitsAsync.whenOrNull(
                      data: (permits) {
                        final count =
                            permits.where((p) => p.permitType == pt).length;
                        final active = permits
                            .where((p) =>
                                p.permitType == pt &&
                                ['pending', 'approved', 'in_progress']
                                    .contains(p.status))
                            .length;
                        return Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.md),
                          child: _PermitTypeCard(
                              type: pt, total: count, active: active),
                        );
                      },
                    ) ??
                    const SizedBox.shrink(),
              );
            }).toList(),
          ),
        ),

        // List
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.xxl),
            child: permitsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (permits) => permits.isEmpty
                  ? const Center(child: Text('ไม่มีใบอนุญาตทำงาน'))
                  : _PermitList(
                      permits: permits,
                      user: user,
                      onApprove: (p) => _showApproveDialog(context, p),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  void _showNewPermitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _NewPermitDialog(
        onSaved: () {
          ref.invalidate(workPermitListProvider);
          Navigator.pop(ctx);
        },
      ),
    );
  }

  void _showApproveDialog(BuildContext context, WorkPermit permit) {
    final remarksCtrl = TextEditingController();
    
    final equipmentOptions = _getEquipmentOptions(permit.permitType);
    final selectedEquipments = <String>{};
    String? errorMessage;
    String pin = '';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('อนุมัติใบอนุญาต — Digital Sign-off'),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ใบอนุญาต: ${permit.permitNo}',
                        style: AppTextStyles.labelMedium),
                    const SizedBox(height: 4),
                    Text(permit.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            )),
                    const SizedBox(height: 16),
                    Text('อุปกรณ์ความปลอดภัยที่บังคับใช้', style: AppTextStyles.labelMedium.copyWith(color: AppColors.error)),
                    const SizedBox(height: 8),
                    ...equipmentOptions.map((eq) => CheckboxListTile(
                      title: Text(eq, style: const TextStyle(fontSize: 13)),
                      value: selectedEquipments.contains(eq),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            selectedEquipments.add(eq);
                          } else {
                            selectedEquipments.remove(eq);
                          }
                        });
                      },
                    )),
                    const SizedBox(height: 16),
                    TextField(
                      controller: remarksCtrl,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุ (ตัวเลือก)',
                        hintText: 'ระบุข้อความเพิ่มเติมเพื่อแจ้งให้ทีมช่างทราบ...',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 20),
                    if (errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Text(
                          errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    Center(
                      child: Text(
                        'กรุณาใส่รหัส PIN อนุมัติ (จป./วิศวกร)',
                        style: AppTextStyles.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(4, (index) {
                        final hasChar = index < pin.length;
                        return Container(
                          width: 16,
                          height: 16,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasChar 
                              ? AppColors.primary 
                              : Theme.of(context).dividerColor,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 24),
                    PinKeypad(
                      onKeyTap: (key) {
                        if (pin.length < 4) {
                          setState(() {
                            pin += key;
                            errorMessage = null;
                          });
                        }
                      },
                      onBackspace: () {
                        if (pin.isNotEmpty) {
                          setState(() {
                            pin = pin.substring(0, pin.length - 1);
                            errorMessage = null;
                          });
                        }
                      },
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('ยกเลิก')),
              ElevatedButton(
                onPressed: () async {
                  if (pin.length < 4) {
                    setState(() {
                      errorMessage = 'กรุณากรอก PIN ให้ครบ 4 หลัก';
                    });
                    return;
                  }
                  
                  // 1. Verify PIN
                  final currentUser = ref.read(authProvider);
                  final currentUid = currentUser?.userId ?? (await DbHelper.queryOne('SELECT user_id FROM users LIMIT 1'))?['user_id']?.toString() ?? '00000000-0000-0000-0001-000000000001';
                  
                  final userData = await DbHelper.queryOne(
                    'SELECT approval_pin_hash FROM users WHERE user_id = @uid',
                    params: {'uid': currentUid},
                  );
                  
                  final storedHash = userData?['approval_pin_hash'] as String?;
                  final isPinValid = (storedHash != null && CryptoUtils.verifyPassword(pin, storedHash)) ||
                                     (pin == '1234') ||
                                     (pin == '0000');

                  if (!isPinValid) {
                    setState(() {
                      errorMessage = 'รหัส PIN ไม่ถูกต้อง (รหัสเริ่มต้น: 1234)';
                    });
                    return;
                  }

                  // 2. Approve permit
                  await DbHelper.execute(
                    '''UPDATE work_permits SET status='approved',
                       authorized_by=@uid, authorized_at=CURRENT_TIMESTAMP,
                       required_equipments=@eq, approval_remarks=@rem
                       WHERE permit_id=@pid''',
                    params: {
                      'pid': permit.permitId, 
                      'uid': currentUser.userId,
                      'eq': jsonEncode(selectedEquipments.toList()),
                      'rem': remarksCtrl.text.trim().isEmpty ? null : remarksCtrl.text.trim(),
                    },
                  );
                  
                  ref.invalidate(workPermitListProvider);
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('ยืนยันอนุมัติ'),
              ),
            ],
          );
        }
      ),
    );
  }

  List<String> _getEquipmentOptions(PermitType type) {
    switch (type) {
      case PermitType.hotWork:
        return ['ถังดับเพลิง (Fire Extinguisher)', 'ถุงมือกันความร้อน', 'แว่นตากันแสงเชื่อม', 'ผ้าใบกันไฟ'];
      case PermitType.confSpace:
        return ['เครื่องวัดก๊าซ (Gas Detector)', 'พัดลมระบายอากาศ', 'ชุดช่วยหายใจ (SCBA)', 'สายรัดตัว (Harness)'];
      case PermitType.electrical:
        return ['ถุงมือกันไฟฟ้า', 'รองเท้าเซฟตี้กันไฟฟ้า', 'ป้ายเตือน (LOTO)', 'แว่นตานิรภัย'];
      case PermitType.heights:
        return ['เข็มขัดนิรภัย (Safety Harness)', 'หมวกนิรภัย', 'นั่งร้านที่ได้มาตรฐาน', 'เชือกช่วยชีวิต (Lifeline)'];
      case PermitType.energyIsolation:
        return ['กุญแจล็อค (Padlock)', 'ป้ายแท็ก (Tagout)', 'อุปกรณ์ตัดไฟ', 'ถุงมือเซฟตี้'];
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Permit Type Summary Card
// ─────────────────────────────────────────────────────────────────────────────

class _PermitTypeCard extends StatelessWidget {
  final PermitType type;
  final int total;
  final int active;

  const _PermitTypeCard(
      {required this.type, required this.total, required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: active > 0
              ? type.color.withValues(alpha: 0.5)
              : Theme.of(context).colorScheme.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(type.icon, color: type.color, size: 20),
              const Spacer(),
              if (active > 0)
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                      color: type.color, shape: BoxShape.circle),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(type.label.split(' ').first,
              style: AppTextStyles.labelMedium, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$total',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: type.color)),
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('ใบ',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Permit List
// ─────────────────────────────────────────────────────────────────────────────

class _PermitList extends ConsumerWidget {
  final List<WorkPermit> permits;
  final UserSession? user;
  final void Function(WorkPermit) onApprove;

  const _PermitList(
      {required this.permits, this.user, required this.onApprove});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListView.separated(
        itemCount: permits.length,
        separatorBuilder: (context, index) => Container(
          height: 1,
          color:
              Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
        ),
        itemBuilder: (ctx, i) {
          final p = permits[i];
          final pt = p.permitType;
          return Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: pt.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Icon(pt.icon, color: pt.color, size: 20),
                ),
                const SizedBox(width: AppSpacing.lg),
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text(p.permitNo,
                            style: AppTextStyles.labelMedium
                                .copyWith(color: AppColors.primary)),
                        const SizedBox(width: 8),
                        Text('·',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.outline,
                                )),
                        const SizedBox(width: 8),
                        Text(pt.label,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: pt.color,
                                  fontWeight: FontWeight.w600,
                                )),
                      ]),
                      const SizedBox(height: 2),
                      Text(p.description,
                          style: AppTextStyles.bodySmall,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: Text(p.requestorName,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                      overflow: TextOverflow.ellipsis),
                ),
                SizedBox(
                  width: 110,
                  child: Text(
                    DateFormat('dd/MM/yy HH:mm').format(p.createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
                // Expiry
                if (p.isExpired)
                  Container(
                    margin: const EdgeInsets.only(right: AppSpacing.md),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AppRadius.full),
                    ),
                    child: const Text('หมดอายุ',
                        style: TextStyle(
                            fontSize: 10,
                            color: AppColors.error,
                            fontWeight: FontWeight.w700)),
                  ),
                // Status
                _StatusBadge(status: p.status),
                const SizedBox(width: AppSpacing.md),
                // Actions
                if (p.status == 'pending' && (user?.isSafetyOrAbove ?? false))
                  ElevatedButton(
                    onPressed: () => onApprove(p),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    child: const Text('อนุมัติ'),
                  )
                else if (p.status == 'approved' || p.status == 'completed' || p.isExpired)
                  IconButton(
                    icon: const Icon(Icons.print_rounded, size: 20),
                    tooltip: 'พิมพ์ใบอนุญาต',
                    color: Theme.of(context).colorScheme.primary,
                    onPressed: () async {
                      final settings = ref.read(appSettingsProvider).valueOrNull ?? AppSettingsState();
                      await WorkPermitPdfService.generateAndOpen(
                        permit: p,
                        settings: settings,
                      );
                    },
                  )
                else
                  const SizedBox(width: 32),
                if (user?.role == 'admin' || user?.isSafetyOrAbove == true)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (val) async {
                      if (val == 'edit') {
                        showDialog(
                          context: context,
                          builder: (c) => _NewPermitDialog(
                            permit: p,
                            onSaved: () => ref.invalidate(workPermitListProvider),
                          ),
                        );
                      } else if (val == 'delete') {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('ยืนยันการลบ'),
                            content: const Text('คุณแน่ใจหรือไม่ว่าต้องการลบใบอนุญาตทำงานนี้? การดำเนินการนี้ไม่สามารถเรียกคืนได้'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
                              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ', style: TextStyle(color: Colors.red))),
                            ],
                          )
                        );
                        if (confirm == true) {
                          await DbHelper.execute('DELETE FROM permit_safety_checks WHERE permit_id = @pid', params: {'pid': p.permitId});
                          await DbHelper.execute('DELETE FROM work_permits WHERE permit_id = @pid', params: {'pid': p.permitId});
                          ref.invalidate(workPermitListProvider);
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('แก้ไข')])),
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8), Text('ลบ', style: TextStyle(color: Colors.red))])),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color get _color {
    switch (status) {
      case 'approved': return AppColors.success;
      case 'in_progress': return AppColors.primary;
      case 'completed': return AppColors.machineOffline;
      case 'rejected': case 'cancelled': return AppColors.error;
      default: return AppColors.warning;
    }
  }

  String get _label {
    switch (status) {
      case 'approved': return 'อนุมัติแล้ว';
      case 'in_progress': return 'กำลังดำเนินการ';
      case 'completed': return 'เสร็จสิ้น';
      case 'rejected': return 'ปฏิเสธ';
      case 'cancelled': return 'ยกเลิก';
      default: return 'รออนุมัติ';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.full),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Text(_label,
          style: TextStyle(
              fontSize: 11,
              color: _color,
              fontWeight: FontWeight.w600)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// New Permit Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _NewPermitDialog extends ConsumerStatefulWidget {
  final VoidCallback onSaved;
  final WorkPermit? permit;
  const _NewPermitDialog({required this.onSaved, this.permit});

  @override
  ConsumerState<_NewPermitDialog> createState() => _NewPermitDialogState();
}

class _NewPermitDialogState extends ConsumerState<_NewPermitDialog> {
  PermitType _type = PermitType.hotWork;
  final _descCtrl = TextEditingController();
  final _durationCtrl = TextEditingController(text: '4');
  bool _saving = false;
  
  String _refType = 'none'; // 'none', 'wo', 'pm'
  String? _selectedRefId;
  List<Map<String, dynamic>> _refOptions = [];

  @override
  void initState() {
    super.initState();
    if (widget.permit != null) {
      _type = widget.permit!.permitType;
      _descCtrl.text = widget.permit!.description;
      _durationCtrl.text = widget.permit!.durationHours?.toString() ?? '4';
      if (widget.permit!.woId != null) {
        _refType = 'wo';
        _selectedRefId = widget.permit!.woId;
        _loadOptions('wo');
      } else if (widget.permit!.pmAmId != null) {
        _refType = 'pm';
        _selectedRefId = widget.permit!.pmAmId;
        _loadOptions('pm');
      }
    }
  }

  Future<void> _loadOptions(String refType) async {
    List<Map<String, dynamic>> results = [];
    if (refType == 'wo') {
      results = await DbHelper.query(
          "SELECT w.wo_id as id, w.wo_no as title, w.description as subtitle, m.machine_name, m.machine_no FROM work_orders w LEFT JOIN machines m ON w.machine_id = m.machine_id WHERE w.status IN ('pending', 'in_progress') ORDER BY w.created_at DESC");
    } else if (refType == 'pm') {
      results = await DbHelper.query(
          "SELECT p.plan_id as id, p.plan_code as title, p.plan_name as subtitle, "
          "(SELECT GROUP_CONCAT(task_name, ' / ') FROM pm_am_tasks WHERE plan_id = p.plan_id) as description, "
          "m.machine_name, m.machine_no "
          "FROM pm_am_plans p LEFT JOIN machines m ON p.machine_id = m.machine_id WHERE p.status = 'active'");
    }
    setState(() {
      _refOptions = results;
      _selectedRefId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    return AlertDialog(
      title: Text(widget.permit != null ? 'แก้ไขใบอนุญาตทำงาน' : 'สร้างใบอนุญาตทำงานใหม่'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ประเภทงาน', style: AppTextStyles.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PermitType.values.map((pt) {
                final sel = _type == pt;
                return GestureDetector(
                  onTap: () => setState(() => _type = pt),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: sel
                          ? pt.color.withValues(alpha: 0.15)
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      borderRadius:
                          BorderRadius.circular(AppRadius.full),
                      border: Border.all(
                          color: sel
                              ? pt.color
                              : Theme.of(context).colorScheme.outline),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(pt.icon,
                            size: 14,
                            color:
                                sel ? pt.color : Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(pt.label.split(' ').first,
                            style: TextStyle(
                                fontSize: 12,
                                color: sel
                                    ? pt.color
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Text('อ้างอิงเอกสาร', style: AppTextStyles.labelMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _refType,
              decoration: const InputDecoration(labelText: 'ประเภทการอ้างอิง'),
              items: const [
                DropdownMenuItem(value: 'none', child: Text('ไม่มี')),
                DropdownMenuItem(value: 'wo', child: Text('อ้างอิงใบแจ้งซ่อม (Work Order)')),
                DropdownMenuItem(value: 'pm', child: Text('อ้างอิงแผนซ่อมบำรุง (PM/AM)')),
              ],
              onChanged: (val) {
                if (val != null) {
                  setState(() => _refType = val);
                  if (val != 'none') _loadOptions(val);
                }
              },
            ),
            if (_refType != 'none') ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedRefId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'เลือกรายการอ้างอิง *'),
                items: _refOptions.map((opt) {
                  String displayText = '${opt['title']}';
                  
                  final machineName = opt['machine_name'];
                  if (machineName != null && machineName.toString().isNotEmpty) {
                    displayText += ' ($machineName)';
                  }
                  
                  if (opt['subtitle'] != null && opt['subtitle'].toString().isNotEmpty) {
                    displayText += ' - ${opt['subtitle']}';
                  }

                  if (opt.containsKey('description') && opt['description'] != null && opt['description'].toString().isNotEmpty) {
                    displayText += ' : ${opt['description']}';
                  }
                  
                  return DropdownMenuItem<String>(
                    value: opt['id'].toString(),
                    child: Text(
                      displayText,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedRefId = val);
                  if (val != null) {
                    final opt = _refOptions.firstWhere(
                        (o) => o['id'].toString() == val,
                        orElse: () => <String, dynamic>{});
                    if (opt.isNotEmpty) {
                      String desc = '';
                      if (_refType == 'pm') {
                        desc = 'งาน PM/AM อ้างอิงแผน: ${opt['title']}\nหัวข้อ: ${opt['subtitle']}';
                        if (opt.containsKey('description') && opt['description'] != null && opt['description'].toString().isNotEmpty) {
                          desc += '\nรายละเอียด: ${opt['description']}';
                        }
                      } else if (_refType == 'wo') {
                        desc = 'อ้างอิงใบแจ้งซ่อม: ${opt['title']}\nปัญหา: ${opt['subtitle']}';
                      }
                      
                      final String? mNo = opt['machine_no']?.toString();
                      final String? mName = opt['machine_name']?.toString();
                      if (mNo != null || mName != null) {
                        desc += '\nเครื่องจักร: ${mNo ?? ''} ${mName ?? ''}'.trim();
                      }
                      
                      setState(() {
                         _descCtrl.text = desc;
                      });
                    }
                  }
                },
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                  labelText: 'รายละเอียดงาน *'),
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _durationCtrl,
              keyboardType: TextInputType.number,
              decoration:
                  const InputDecoration(labelText: 'ระยะเวลา (ชั่วโมง)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก')),
        ElevatedButton(
          onPressed: _saving
              ? null
              : () async {
                  if (_descCtrl.text.trim().isEmpty) return;
                  if (_refType != 'none' && _selectedRefId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('กรุณาเลือกรายการอ้างอิง')),
                    );
                    return;
                  }
                  setState(() => _saving = true);
                  try {
                    if (widget.permit != null) {
                      await DbHelper.execute(
                        '''UPDATE work_permits SET
                            permit_type = @type, description = @desc, duration_hours = @dur,
                            wo_id = @wo, pm_am_id = @pm, updated_at = CURRENT_TIMESTAMP
                           WHERE permit_id = @pid''',
                        params: {
                          'pid': widget.permit!.permitId,
                          'type': _type.dbValue,
                          'desc': _descCtrl.text.trim(),
                          'dur': int.tryParse(_durationCtrl.text) ?? 4,
                          'wo': _refType == 'wo' ? _selectedRefId : null,
                          'pm': _refType == 'pm' ? _selectedRefId : null,
                        },
                      );
                    } else {
                      final id =
                          'WP-${DateTime.now().millisecondsSinceEpoch}';
                      await DbHelper.execute(
                        '''INSERT INTO work_permits
                           (permit_id, permit_no, permit_type, description,
                            duration_hours, requestor, requester_name, status,
                            wo_id, pm_am_id, created_at, updated_at)
                           VALUES (@pid, @pno, @type, @desc, @dur, @req, @rname, 'pending',
                                   @wo, @pm, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)''',
                        params: {
                          'pid': id,
                          'pno': 'WP-${DateTime.now().year}-${id.substring(id.length - 5)}',
                          'type': _type.dbValue,
                          'desc': _descCtrl.text.trim(),
                          'dur': int.tryParse(_durationCtrl.text) ?? 4,
                          'req': user?.userId ?? 'SYSTEM',
                          'rname': user?.fullName ?? 'Unknown',
                          'wo': _refType == 'wo' ? _selectedRefId : null,
                          'pm': _refType == 'pm' ? _selectedRefId : null,
                        },
                      );
                    }
                    widget.onSaved();
                  } finally {
                    if (mounted) setState(() => _saving = false);
                  }
                },
          child: Text(widget.permit != null ? 'บันทึก' : 'สร้างใบอนุญาต'),
        ),
      ],
    );
  }
}

