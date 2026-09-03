import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:file_picker/file_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../features/auth/auth_provider.dart';
import '../work_orders/work_order_models.dart';
import 'technician_portfolio_pdf_service.dart';
import 'workforce_screen.dart';
import 'technician_profile_provider.dart';

class TechnicianProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  const TechnicianProfileScreen({super.key, required this.userId});

  @override
  ConsumerState<TechnicianProfileScreen> createState() => _TechnicianProfileScreenState();
}

class _TechnicianProfileScreenState extends ConsumerState<TechnicianProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isExportingPortfolio = false;

  @override
  void initState() {
    super.initState();
    // 5 tabs: Overview, History, Kaizen Portfolio, Documents, Skills
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isSupervisor(String role) {
    return ['engineer', 'admin', 'executive', 'safety', 'manager'].contains(role);
  }

  Future<void> _exportPortfolio(TechnicianProfile profile, KaizenPortfolioData portfolio) async {
    setState(() => _isExportingPortfolio = true);
    try {
      final attachments = ref.read(technicianAttachmentsProvider(widget.userId)).value ?? [];
      final certs = attachments.where((a) => a.documentType == 'certificate').toList();

      await TechnicianPortfolioPdfService.generateAndOpen(
        profile: profile,
        plans: portfolio.plans,
        kaizenPoints: portfolio.totalPoints,
        badges: portfolio.badges,
        certificates: certs,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการสร้างเอกสาร Portfolio: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingPortfolio = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(technicianDetailsProvider(widget.userId));
    final portfolioAsync = ref.watch(technicianKaizenPortfolioProvider(widget.userId));
    final currentUser = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('โปรไฟล์บุคลากร & ผลงาน'),
        actions: [
          if (profileAsync.valueOrNull != null && portfolioAsync.valueOrNull != null) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blue.shade700,
                foregroundColor: Colors.white,
              ),
              icon: _isExportingPortfolio
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.picture_as_pdf_rounded, size: 18),
              label: Text(_isExportingPortfolio ? 'กำลังพิมพ์...' : '📄 พิมพ์ Portfolio (PDF)'),
              onPressed: _isExportingPortfolio
                  ? null
                  : () => _exportPortfolio(profileAsync.valueOrNull!, portfolioAsync.valueOrNull!),
            ),
            const SizedBox(width: 16),
          ],
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (profile) {
          if (profile == null) return const Center(child: Text('ไม่พบข้อมูลช่าง'));

          final isSuper = currentUser != null && _isSupervisor(currentUser.role);
          final showSkills = isSuper;

          if (!showSkills && _tabController.length == 5) {
             _tabController = TabController(length: 4, vsync: this);
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(profile),

              // Tabs
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabs: [
                  const Tab(text: 'ภาระงานปัจจุบัน'),
                  const Tab(text: 'ประวัติงานซ่อม'),
                  const Tab(text: '🏆 ผลงาน Kaizen & Action Plan'),
                  const Tab(text: 'เอกสารและคู่มือ'),
                  if (showSkills) const Tab(text: 'ทักษะและการประเมิน'),
                ],
              ),

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCurrentTasksTab(),
                    _buildHistoryTab(),
                    _buildKaizenPortfolioTab(profile),
                    _buildDocumentsTab(),
                    if (showSkills) _buildSkillsTab(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(TechnicianProfile profile) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      color: Theme.of(context).colorScheme.surface,
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            child: Text(
              profile.fullName.substring(0, 1),
              style: AppTextStyles.headlineLarge.copyWith(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: AppSpacing.xl),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.fullName, style: AppTextStyles.headlineMedium),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.machinePM.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        profile.role,
                        style: const TextStyle(fontSize: 12, color: AppColors.machinePM),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'รหัส: ${profile.employeeNo}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentTasksTab() {
    final tasksAsync = ref.watch(technicianTasksProvider(widget.userId));
    return tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (tasks) {
        final activeTasks = tasks.where((t) => t.status != WorkOrderStatus.completed && t.status != WorkOrderStatus.cancelled).toList();
        if (activeTasks.isEmpty) return const Center(child: Text('ไม่มีภาระงานปัจจุบัน'));

        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.xl),
          itemCount: activeTasks.length,
          separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            final t = activeTasks[index];
            return _TaskTile(task: t);
          },
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    final tasksAsync = ref.watch(technicianTasksProvider(widget.userId));
    return tasksAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (tasks) {
        final historyTasks = tasks.where((t) => t.status == WorkOrderStatus.completed).toList();
        if (historyTasks.isEmpty) return const Center(child: Text('ไม่มีประวัติงานซ่อม'));

        return ListView.separated(
          padding: const EdgeInsets.all(AppSpacing.xl),
          itemCount: historyTasks.length,
          separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            final t = historyTasks[index];
            return _TaskTile(task: t);
          },
        );
      },
    );
  }

  Widget _buildKaizenPortfolioTab(TechnicianProfile profile) {
    final portfolioAsync = ref.watch(technicianKaizenPortfolioProvider(widget.userId));
    return portfolioAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (portfolio) {
        final plans = portfolio.plans;

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            // 1. KPI Stats Summary Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  _buildPortfolioStatItem('🏆 คะแนน Kaizen', '${portfolio.totalPoints}', 'แต้ม', Colors.amber.shade700, Colors.amber.shade50),
                  const SizedBox(width: 12),
                  _buildPortfolioStatItem('🎯 แผนงานสำเร็จ', '${portfolio.completedProjects}', 'โครงการ', Colors.green.shade700, Colors.green.shade50),
                  const SizedBox(width: 12),
                  _buildPortfolioStatItem('⚡ ขั้นตอนที่ปฏิบัติการ', '${portfolio.completedSteps}', 'ขั้นตอน', Colors.blue.shade700, Colors.blue.shade50),
                  const SizedBox(width: 12),
                  _buildPortfolioStatItem('🚀 ลดสูญเปล่าสูงสุด', portfolio.maxReductionPercent != null ? '${portfolio.maxReductionPercent!.toStringAsFixed(1)}%' : '-', '', Colors.purple.shade700, Colors.purple.shade50),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // 2. Badges Section
            Text('🎖️ เหรียญเกียรติยศและทักษะความเชี่ยวชาญ (Earned Badges)', style: AppTextStyles.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            if (portfolio.badges.isEmpty)
              const Text('กำลังสะสมผลงานการแก้ปัญหา', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: portfolio.badges.map((b) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.blue.shade300),
                    ),
                    child: Text(
                      b,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.blue.shade900),
                    ),
                  );
                }).toList(),
              ),
            const SizedBox(height: AppSpacing.xl),

            // 3. Projects List
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('📋 ประวัติโครงการ Action Plan & การแก้ปัญหา (${plans.length})', style: AppTextStyles.headlineSmall),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (plans.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: const Center(
                  child: Text('ยังไม่มีประวัติการร่วมดำเนินการใน Action Plan', style: TextStyle(color: AppColors.textSecondary)),
                ),
              )
            else
              ...plans.map((p) {
                final isDone = p.status == 'completed' || p.status == 'closed';
                final redStr = p.reductionPercentage != null ? '${p.reductionPercentage!.toStringAsFixed(1)}%' : null;

                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: isDone ? Colors.green.withValues(alpha: 0.3) : Theme.of(context).dividerColor),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: CircleAvatar(
                      backgroundColor: isDone ? Colors.green.shade100 : Colors.blue.shade100,
                      child: Icon(
                        isDone ? Icons.task_alt_rounded : Icons.pending_actions_rounded,
                        color: isDone ? Colors.green.shade800 : Colors.blue.shade800,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      p.problemTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (p.rootCause != null && p.rootCause!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('สาเหตุ: ${p.rootCause}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                        if (redStr != null) ...[
                          const SizedBox(height: 2),
                          Text('ผลลัพธ์ลดได้จริง: $redStr', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.teal)),
                        ],
                      ],
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/action-plans/${p.rcaId}'),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  Widget _buildPortfolioStatItem(String title, String val, String unit, Color textColor, Color bgColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: textColor.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textColor)),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  Text(unit, style: TextStyle(fontSize: 10.5, color: textColor.withValues(alpha: 0.8))),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentsTab() {
    final attachmentsAsync = ref.watch(technicianAttachmentsProvider(widget.userId));
    return attachmentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (attachments) {
        final certs = attachments.where((a) => a.documentType == 'certificate').toList();
        final manuals = attachments.where((a) => a.documentType == 'manual').toList();

        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            _buildDocSection('ใบเซอร์ / อบรม (Certificates)', 'certificate', certs),
            const SizedBox(height: AppSpacing.xxl),
            _buildDocSection('คู่มือการทำงาน (Manuals)', 'manual', manuals),
          ],
        );
      },
    );
  }

  Widget _buildDocSection(String title, String docType, List<TechnicianAttachment> docs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: AppTextStyles.headlineSmall),
            ShadButton.outline(
              child: const Text('อัปโหลด'),
              onPressed: () => _uploadDocument(docType),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (docs.isEmpty)
          const Text('ยังไม่มีเอกสาร', style: TextStyle(color: AppColors.textSecondary))
        else
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: docs.map((d) => _DocCard(doc: d)).toList(),
          ),
      ],
    );
  }

  Future<void> _uploadDocument(String docType) async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      await TechnicianRepository.uploadAttachment(
        technicianId: widget.userId,
        documentType: docType,
        fileName: file.name,
        filePath: file.path!,
      );
      ref.invalidate(technicianAttachmentsProvider(widget.userId));
    }
  }

  Widget _buildSkillsTab() {
    final skillsAsync = ref.watch(technicianSkillsProvider(widget.userId));
    return skillsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (skills) {
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ประเมินทักษะความสามารถ', style: AppTextStyles.headlineSmall),
                ShadButton.outline(
                  child: const Text('เพิ่มทักษะ'),
                  onPressed: () => _addSkillDialog(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (skills.isEmpty) const Text('ยังไม่มีข้อมูลทักษะ')
            else ...skills.map((s) => _SkillTile(
              skill: s,
              onScoreChanged: (val) async {
                await TechnicianRepository.updateSkillScore(skillId: s.skillId, score: val.toInt());
                ref.invalidate(technicianSkillsProvider(widget.userId));
              },
            )),
          ],
        );
      },
    );
  }

  Future<void> _addSkillDialog() async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เพิ่มทักษะ'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'ชื่อทักษะ'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          ShadButton(
            child: const Text('บันทึก'),
            onPressed: () async {
              if (ctrl.text.isNotEmpty) {
                await TechnicianRepository.addSkill(technicianId: widget.userId, skillName: ctrl.text);
                ref.invalidate(technicianSkillsProvider(widget.userId));
                if (ctx.mounted) Navigator.pop(ctx);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  final WorkOrder task;
  const _TaskTile({required this.task});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const HugeIcon(icon: HugeIcons.strokeRoundedWrench01, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(task.woNo, style: AppTextStyles.labelLarge),
                if (task.description != null) Text(task.description!, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: task.status == WorkOrderStatus.completed ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              task.status.name.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                color: task.status == WorkOrderStatus.completed ? AppColors.success : AppColors.warning,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocCard extends StatelessWidget {
  final TechnicianAttachment doc;
  const _DocCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final isPdf = doc.fileName.toLowerCase().endsWith('.pdf');
    return Container(
      width: 140,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        children: [
          Icon(isPdf ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded, size: 40, color: isPdf ? AppColors.error : AppColors.primary),
          const SizedBox(height: AppSpacing.sm),
          Text(doc.fileName, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _SkillTile extends StatelessWidget {
  final TechnicianSkill skill;
  final ValueChanged<double> onScoreChanged;
  const _SkillTile({required this.skill, required this.onScoreChanged});

  @override
  Widget build(BuildContext context) {
    final rawScore = (skill.score ?? 80).toDouble();
    final normalized = (rawScore <= 10 && rawScore > 0) ? rawScore * 10 : rawScore;
    final displayScore = normalized.clamp(0.0, 100.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(skill.skillName, style: AppTextStyles.labelLarge),
                Text(
                  'ระดับ: ${skill.proficiencyLevel}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    value: displayScore,
                    min: 0.0,
                    max: 100.0,
                    divisions: 20,
                    label: '${displayScore.toInt()}',
                    onChanged: onScoreChanged,
                  ),
                ),
                SizedBox(
                  width: 65,
                  child: Text(
                    '${displayScore.toInt()} / 100',
                    style: AppTextStyles.labelMedium,
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
