import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/auth/auth_service.dart';
import '../../features/auth/auth_provider.dart';
import '../work_orders/work_order_models.dart';
import 'technician_profile_provider.dart';

class TechnicianProfileScreen extends ConsumerStatefulWidget {
  final String userId;
  const TechnicianProfileScreen({super.key, required this.userId});

  @override
  ConsumerState<TechnicianProfileScreen> createState() => _TechnicianProfileScreenState();
}

class _TechnicianProfileScreenState extends ConsumerState<TechnicianProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    // 4 tabs: Overview, History, Documents, Skills
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _isSupervisor(String role) {
    return ['engineer', 'admin', 'executive', 'safety', 'manager'].contains(role);
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(technicianDetailsProvider(widget.userId));
    final currentUser = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: const Text('โปรไฟล์บุคลากร'),
      ),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text('Error: $err')),
        data: (profile) {
          if (profile == null) return const Center(child: Text('ไม่พบข้อมูลช่าง'));

          final isSuper = currentUser != null && _isSupervisor(currentUser.role);
          // If not supervisor and looking at own profile, they shouldn't see skills tab
          final showSkills = isSuper;

          if (!showSkills && _tabController.length == 4) {
             _tabController = TabController(length: 3, vsync: this);
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

  Widget _buildHeader(profile) {
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
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
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
          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) {
            final t = historyTasks[index];
            return _TaskTile(task: t);
          },
        );
      },
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(skill.skillName, style: AppTextStyles.labelLarge)),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: Slider(
                    value: (skill.score ?? 0).toDouble(),
                    min: 0,
                    max: 10,
                    divisions: 10,
                    label: skill.score?.toString() ?? '0',
                    onChanged: onScoreChanged,
                  ),
                ),
                Text('${skill.score ?? 0} / 10', style: AppTextStyles.labelMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
