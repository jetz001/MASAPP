import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/database/db_helper.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class TechnicianProfile {
  final String userId;
  final String employeeNo;
  final String fullName;
  final String role;
  final String? deptName;
  final String? email;
  final String? phone;
  final bool isActive;
  final List<String> skills;
  final int openWorkOrders;

  const TechnicianProfile({
    required this.userId,
    required this.employeeNo,
    required this.fullName,
    required this.role,
    this.deptName,
    this.email,
    this.phone,
    required this.isActive,
    required this.skills,
    required this.openWorkOrders,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final workforceProvider =
    FutureProvider<List<TechnicianProfile>>((ref) async {
  try {
    final rows = await DbHelper.query(
      '''SELECT u.user_id, u.employee_no, u.full_name, u.role,
                u.email, u.phone, u.is_active,
                d.dept_name
         FROM users u
         LEFT JOIN departments d ON d.dept_id = u.dept_id
         WHERE u.role IN ('technician','engineer','safety')
         ORDER BY u.role, u.full_name''',
    );

    final profiles = <TechnicianProfile>[];
    for (final row in rows) {
      final uid = row['user_id'] as String;

      // Get skills
      final skillRows = await DbHelper.query(
        'SELECT skill_name FROM technician_skills WHERE technician_id = @uid',
        params: {'uid': uid},
      );
      final skills =
          skillRows.map((s) => s['skill_name'] as String).toList();

      // Open WO count
      final woResult = await DbHelper.queryOne(
        '''SELECT COUNT(*) as c FROM work_orders
           WHERE assigned_to = @uid AND status NOT IN ('completed','cancelled')''',
        params: {'uid': uid},
      );

      profiles.add(TechnicianProfile(
        userId: uid,
        employeeNo: row['employee_no'] as String? ?? '-',
        fullName: row['full_name'] as String,
        role: row['role'] as String,
        deptName: row['dept_name'] as String?,
        email: row['email'] as String?,
        phone: row['phone'] as String?,
        isActive: row['is_active'] == 1,
        skills: skills,
        openWorkOrders: woResult?['c'] as int? ?? 0,
      ));
    }

    return profiles;
  } catch (_) {
    return [];
  }
});

// ─────────────────────────────────────────────────────────────────────────────
// Workforce Screen
// ─────────────────────────────────────────────────────────────────────────────

class WorkforceScreen extends ConsumerWidget {
  const WorkforceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workforceAsync = ref.watch(workforceProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Container(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xl),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.groups_rounded,
                        color: AppColors.primary, size: 24),
                    const SizedBox(width: AppSpacing.sm),
                    Text('ทีมช่างและบุคลากร',
                        style: AppTextStyles.headlineLarge),
                  ]),
                  const SizedBox(height: 4),
                  Text('Workforce Directory · Skill Matrix · Workload',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                onPressed: () => ref.invalidate(workforceProvider),
                tooltip: 'รีเฟรช',
              ),
            ],
          ),
        ),

        // Cards grid
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.xxl),
            child: workforceAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (staff) => staff.isEmpty
                  ? const Center(child: Text('ไม่มีข้อมูลทีมช่าง'))
                  : GridView.builder(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 340,
                        mainAxisSpacing: AppSpacing.lg,
                        crossAxisSpacing: AppSpacing.lg,
                        childAspectRatio: 1.2,
                      ),
                      itemCount: staff.length,
                      itemBuilder: (ctx, i) =>
                          _TechCard(profile: staff[i]),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Technician Card
// ─────────────────────────────────────────────────────────────────────────────

class _TechCard extends StatefulWidget {
  final TechnicianProfile profile;
  const _TechCard({required this.profile});

  @override
  State<_TechCard> createState() => _TechCardState();
}

class _TechCardState extends State<_TechCard> {
  bool _hovered = false;

  Color get _roleColor {
    switch (widget.profile.role) {
      case 'engineer': return AppColors.primary;
      case 'safety': return AppColors.success;
      default: return AppColors.machinePM;
    }
  }

  String get _roleName {
    switch (widget.profile.role) {
      case 'engineer': return 'วิศวกร';
      case 'safety': return 'จป.';
      default: return 'ช่างเทคนิค';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final workloadPct = (p.openWorkOrders / 5.0).clamp(0.0, 1.0);
    final workloadColor = workloadPct >= 0.8
        ? AppColors.error
        : workloadPct >= 0.5
            ? AppColors.warning
            : AppColors.success;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: _hovered
                ? _roleColor.withValues(alpha: 0.5)
                : Theme.of(context).colorScheme.outline,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: _roleColor.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar + Name
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: _roleColor.withValues(alpha: 0.15),
                  child: Text(
                    p.fullName.substring(0, 1),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: _roleColor,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.fullName,
                          style: AppTextStyles.titleSmall,
                          overflow: TextOverflow.ellipsis),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _roleColor.withValues(alpha: 0.12),
                              borderRadius:
                                  BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(_roleName,
                                style: TextStyle(
                                    fontSize: 10,
                                    color: _roleColor,
                                    fontWeight: FontWeight.w600)),
                          ),
                          const SizedBox(width: 6),
                          Text(p.employeeNo,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  )),
                        ],
                      ),
                    ],
                  ),
                ),
                if (!p.isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Text('หยุด',
                        style: TextStyle(
                            fontSize: 9, color: AppColors.error)),
                  ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            // Department
            if (p.deptName != null)
              Row(
                children: [
                  const Icon(Icons.business_rounded,
                      size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(p.deptName!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          )),
                ],
              ),

            const SizedBox(height: AppSpacing.md),

            // Workload bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('ภาระงาน',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            )),
                    Text('${p.openWorkOrders} ใบ',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: workloadColor,
                              fontWeight: FontWeight.bold,
                            )),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(AppRadius.full),
                  child: LinearProgressIndicator(
                    value: workloadPct,
                    backgroundColor:
                        workloadColor.withValues(alpha: 0.15),
                    color: workloadColor,
                    minHeight: 6,
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.md),

            // Skills
            if (p.skills.isNotEmpty)
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: p.skills
                    .take(3)
                    .map((s) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                            border: Border.all(
                              color:
                                  Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          child: Text(s,
                              style: const TextStyle(fontSize: 10)),
                        ))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}
