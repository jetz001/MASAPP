import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/database/db_helper.dart';
import '../auth/auth_provider.dart';

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
  final int kaizenPoints;
  final int completedWorkOrders;

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
    this.kaizenPoints = 0,
    this.completedWorkOrders = 0,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final workforceProvider =
    FutureProvider<List<TechnicianProfile>>((ref) async {
  try {
    final user = ref.watch(authProvider);
    if (user == null) return [];

    String extraWhere = '';
    Map<String, dynamic> params = {};

    // Technicians can only see their own work.
    // Higher roles (engineer, safety, admin, etc.) can see everyone.
    if (user.role == 'technician') {
      extraWhere = ' AND u.user_id = @uid';
      params['uid'] = user.userId;
    }

    final rows = await DbHelper.query(
      '''SELECT u.user_id, u.employee_no, u.full_name, u.role,
                u.email, u.phone, u.is_active,
                d.dept_name
         FROM users u
         LEFT JOIN departments d ON d.dept_id = u.dept_id
         WHERE u.role IN ('technician','engineer','safety')$extraWhere
         ORDER BY u.role, u.full_name''',
      params: params,
    );

    // Fetch all Action Plans for real point computation
    final planRows = await DbHelper.query('SELECT * FROM problem_solving_records');

    final profiles = <TechnicianProfile>[];
    for (final row in rows) {
      final uid = row['user_id'] as String;
      final fullName = row['full_name'] as String;
      final empNo = row['employee_no'] as String? ?? '';

      // Get skills
      final skillRows = await DbHelper.query(
        'SELECT skill_name FROM technician_skills WHERE technician_id = @uid',
        params: {'uid': uid},
      );
      final skills =
          skillRows.map((s) => s['skill_name'] as String).toList();

      // Open WO count
      final openWoResult = await DbHelper.queryOne(
        '''SELECT COUNT(*) as c FROM work_orders
           WHERE assigned_to = @uid AND status NOT IN ('completed','cancelled')''',
        params: {'uid': uid},
      );
      final openWos = openWoResult?['c'] as int? ?? 0;

      // Completed WO count
      final doneWoResult = await DbHelper.queryOne(
        '''SELECT COUNT(*) as c FROM work_orders
           WHERE assigned_to = @uid AND status = 'completed' ''',
        params: {'uid': uid},
      );
      final doneWos = doneWoResult?['c'] as int? ?? 0;

      // Real Kaizen Points Calculation from DB
      int kPoints = (doneWos * 20) + (skills.length * 15);
      for (final pRow in planRows) {
        final stepsJson = pRow['action_steps_json']?.toString() ?? '';
        final verifiedBy = pRow['verified_by']?.toString() ?? '';
        final status = pRow['status']?.toString() ?? '';
        final vRes = pRow['verification_result']?.toString() ?? '';

        final isAssignee = stepsJson.contains(fullName) || (empNo.isNotEmpty && stepsJson.contains(empNo));
        final isVerifier = verifiedBy.contains(fullName);

        if (isAssignee || isVerifier) {
          if (status == 'completed' || status == 'closed') {
            kPoints += 100;
          }
          if (vRes == 'achieved') {
            kPoints += 200;
          }
        }
      }

      profiles.add(TechnicianProfile(
        userId: uid,
        employeeNo: empNo.isEmpty ? '-' : empNo,
        fullName: fullName,
        role: row['role'] as String,
        deptName: row['dept_name'] as String?,
        email: row['email'] as String?,
        phone: row['phone'] as String?,
        isActive: row['is_active'] == 1,
        skills: skills,
        openWorkOrders: openWos,
        completedWorkOrders: doneWos,
        kaizenPoints: kPoints,
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

        // Main Content
        Expanded(
          child: workforceAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (staff) {
              if (staff.isEmpty) {
                return const Center(child: Text('ไม่มีข้อมูลทีมช่าง'));
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.xxl),
                children: [
                  // 1. Leaderboard & Innovators Banner
                  _buildLeaderboardBanner(context, staff),
                  const SizedBox(height: AppSpacing.xl),

                  // 2. Section Title
                  Row(
                    children: [
                      const Icon(Icons.badge_rounded, size: 20, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text('รายชื่อบุคลากรทั้งหมด (${staff.length} ท่าน)', style: AppTextStyles.headlineSmall),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),

                  // 3. Grid of cards
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 340,
                      mainAxisSpacing: AppSpacing.lg,
                      crossAxisSpacing: AppSpacing.lg,
                      childAspectRatio: 1.2,
                    ),
                    itemCount: staff.length,
                    itemBuilder: (ctx, i) => _TechCard(profile: staff[i]),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildLeaderboardBanner(BuildContext context, List<TechnicianProfile> staff) {
    final sortedStaff = [...staff]..sort((a, b) => b.kaizenPoints.compareTo(a.kaizenPoints));
    final topStaff = sortedStaff.take(3).toList();
    final medals = ['🥇 อันดับ 1', '🥈 อันดับ 2', '🥉 อันดับ 3'];
    final medalColors = [Colors.amber.shade700, Colors.blueGrey.shade600, Colors.brown.shade600];
    final medalBgs = [Colors.amber.shade50, Colors.blueGrey.shade50, Colors.brown.shade50];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: Colors.amber, size: 24),
              const SizedBox(width: 8),
              Text(
                '🏆 ทำเนียบช่างดีเด่น & Kaizen Leaderboard ประจำเดือน',
                style: AppTextStyles.headlineSmall.copyWith(color: Colors.amber.shade900),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('คำนวณจากผลงานและ Action Plan จริงในระบบ', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: topStaff.asMap().entries.map((entry) {
              final idx = entry.key;
              final p = entry.value;
              final isFirst = idx == 0;

              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: idx < topStaff.length - 1 ? 10 : 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: medalBgs[idx],
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: medalColors[idx].withValues(alpha: 0.5), width: isFirst ? 1.5 : 1),
                  ),
                  child: InkWell(
                    onTap: () => context.push('/workforce/${p.userId}'),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: medalColors[idx].withValues(alpha: 0.2),
                          child: Text(
                            p.fullName.substring(0, 1),
                            style: TextStyle(fontWeight: FontWeight.bold, color: medalColors[idx]),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    medals[idx],
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: medalColors[idx]),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: medalColors[idx].withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${p.kaizenPoints} แต้ม',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: medalColors[idx]),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                p.fullName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                '${p.role} · ซ่อมสำเร็จ ${p.completedWorkOrders} งาน',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.push('/workforce/${p.userId}'),
        borderRadius: BorderRadius.circular(12),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hovered
                    ? AppColors.primary.withValues(alpha: 0.5)
                    : Theme.of(context).dividerColor,
                width: _hovered ? 2 : 1,
              ),
              boxShadow: [
                if (_hovered)
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  )
              ],
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
      ),
      ),
    );
  }
}
