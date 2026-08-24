import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/ai/ai_service.dart';
import '../action_plan_pdf_service.dart';
import '../kaizen_certificate_pdf_service.dart';
import '../models/action_plan_model.dart';
import '../providers/action_plan_provider.dart';

class ActionPlanDetailScreen extends ConsumerStatefulWidget {
  final String rcaId;

  const ActionPlanDetailScreen({super.key, required this.rcaId});

  @override
  ConsumerState<ActionPlanDetailScreen> createState() => _ActionPlanDetailScreenState();
}

class _ActionPlanDetailScreenState extends ConsumerState<ActionPlanDetailScreen> {
  bool _isGeneratingAiSteps = false;
  bool _isExportingPdf = false;
  bool _isExportingCert = false;
  String? _activeRcaMethod;

  Future<void> _exportPdf(ActionPlanRecord plan) async {
    setState(() => _isExportingPdf = true);
    try {
      await ActionPlanPdfService.generateAndOpen(plan: plan);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการสร้างเอกสาร PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingPdf = false);
    }
  }

  Future<void> _exportCertificate(ActionPlanRecord plan) async {
    setState(() => _isExportingCert = true);
    try {
      await KaizenCertificatePdfService.generateAndOpen(plan: plan);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการสร้างใบประกาศนียบัตร: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExportingCert = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final planAsync = ref.watch(actionPlanDetailProvider(widget.rcaId));

    return planAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('รายละเอียด Action Plan')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (err, _) => Scaffold(
        appBar: AppBar(title: const Text('รายละเอียด Action Plan')),
        body: Center(child: Text('เกิดข้อผิดพลาดในการโหลด: $err')),
      ),
      data: (plan) {
        if (plan == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('รายละเอียด Action Plan')),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_off_rounded, size: 64, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('ไม่พบข้อมูล Action Plan นี้ในระบบ'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.pop(),
                    child: const Text('กลับหน้ารายการ'),
                  ),
                ],
              ),
            ),
          );
        }

        final isCompleted = plan.status == 'completed' || plan.status == 'closed';
        final progressPct = (plan.progress * 100).toStringAsFixed(0);

        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
            ),
            title: Row(
              children: [
                _buildSourceBadge(plan.sourceType),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    plan.problemTitle,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            actions: [
              _buildStatusDropdown(plan),
              const SizedBox(width: 8),
              if (plan.status == 'completed' || plan.status == 'closed' || plan.verificationResult == 'achieved') ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.amber.shade800,
                    foregroundColor: Colors.white,
                  ),
                  icon: _isExportingCert
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.workspace_premium_rounded, size: 18),
                  label: Text(_isExportingCert ? 'กำลังสร้างใบประกาศ...' : '📜 ใบประกาศ (Cert)'),
                  onPressed: _isExportingCert ? null : () => _exportCertificate(plan),
                ),
                const SizedBox(width: 8),
              ],
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white,
                ),
                icon: _isExportingPdf
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: Text(_isExportingPdf ? 'กำลังสร้าง PDF...' : 'ออกรายงาน (PDF)'),
                onPressed: _isExportingPdf ? null : () => _exportPdf(plan),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: const Text('แก้ไขแผน'),
                onPressed: () => _showEditPlanDialog(context, plan),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (val) async {
                  if (val == 'export_pdf') {
                    await _exportPdf(plan);
                  } else if (val == 'open_rca') {
                    context.push('/problem-solving');
                  } else if (val == 'delete') {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('ยืนยันการลบ Action Plan'),
                        content: Text('คุณต้องการลบ "${plan.problemTitle}" หรือไม่?'),
                        actions: [
                          TextButton(onPressed: () => ctx.pop(false), child: const Text('ยกเลิก')),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => ctx.pop(true),
                            child: const Text('ลบ'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref.read(actionPlanListProvider.notifier).deleteActionPlan(plan.rcaId);
                      if (context.mounted) {
                        context.pop();
                      }
                    }
                  }
                },
                itemBuilder: (ctx) => const [
                  PopupMenuItem(
                    value: 'export_pdf',
                    child: Row(
                      children: [
                        Icon(Icons.picture_as_pdf_rounded, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('ออกรายงาน (PDF / Browser)', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'open_rca',
                    child: Row(
                      children: [
                        Icon(Icons.troubleshoot_rounded, size: 16, color: Colors.purple),
                        SizedBox(width: 8),
                        Text('เปิดใน Problem Solving & RCA', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                        SizedBox(width: 8),
                        Text('ลบแผนงานนี้', style: TextStyle(fontSize: 12, color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Problem Overview & Root Cause Card
                _buildOverviewCard(theme, plan),
                const SizedBox(height: 16),

                // 2. Action Steps Checklist Card
                _buildChecklistCard(context, theme, plan, progressPct, isCompleted),
                const SizedBox(height: 16),

                // 3. Verification & Validation Card
                _buildVerificationCard(context, theme, plan),
                const SizedBox(height: 16),

                // 4. Attachments & Photos Card
                _buildAttachmentsCard(context, theme, plan),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverviewCard(ThemeData theme, ActionPlanRecord plan) {
    final has5Why = (plan.why1 != null && plan.why1!.isNotEmpty) ||
        (plan.why2 != null && plan.why2!.isNotEmpty) ||
        (plan.why3 != null && plan.why3!.isNotEmpty);

    final has4M1E = (plan.fishboneMan != null && plan.fishboneMan!.isNotEmpty) ||
        (plan.fishboneMachine != null && plan.fishboneMachine!.isNotEmpty) ||
        (plan.fishboneMaterial != null && plan.fishboneMaterial!.isNotEmpty) ||
        (plan.fishboneMethod != null && plan.fishboneMethod!.isNotEmpty) ||
        (plan.fishboneEnv != null && plan.fishboneEnv!.isNotEmpty);

    final effectiveMethod = _activeRcaMethod ?? (has5Why && plan.rcaMethod == '5why' ? '5why' : (has4M1E ? 'fishbone' : '5why'));

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.troubleshoot_rounded, size: 18, color: Colors.blueAccent),
                ),
                const SizedBox(width: 8),
                const Text(
                  'ข้อมูลปัญหาและการวิเคราะห์สาเหตุ (Root Cause Analysis)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                if (has5Why && has4M1E) ...[
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: '5why',
                        label: Text('5-Why Analysis', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      ButtonSegment(
                        value: 'fishbone',
                        label: Text('ผังก้างปลา (4M1E)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                    selected: {effectiveMethod},
                    onSelectionChanged: (val) {
                      setState(() => _activeRcaMethod = val.first);
                    },
                  ),
                  const SizedBox(width: 12),
                ],
                if (plan.createdAt != null)
                  Text(
                    'บันทึกเมื่อ: ${plan.createdAt}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
              ],
            ),
            const Divider(height: 20),

            // Problem Title
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'หัวข้อปัญหา: ',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Expanded(
                  child: Text(
                    plan.problemTitle,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                  ),
                ),
              ],
            ),

            // Root Cause Banner
            if (plan.rootCause != null && plan.rootCause!.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.crisis_alert_rounded, color: Colors.white, size: 13),
                              SizedBox(width: 4),
                              Text(
                                'สาเหตุรากเหง้าที่แท้จริง (Root Cause)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      plan.rootCause!,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],

            // Display ONLY the chosen RCA Method: 5-Why OR Fishbone 4M1E
            if (effectiveMethod == '5why' && has5Why) ...[
              const SizedBox(height: 14),
              _build5WhyTimeline(theme, plan),
            ] else if (effectiveMethod == 'fishbone' && has4M1E) ...[
              const SizedBox(height: 14),
              _build4M1EGrid(theme, plan),
            ] else if (has5Why) ...[
              const SizedBox(height: 14),
              _build5WhyTimeline(theme, plan),
            ] else if (has4M1E) ...[
              const SizedBox(height: 14),
              _build4M1EGrid(theme, plan),
            ],
          ],
        ),
      ),
    );
  }

  Widget _build5WhyTimeline(ThemeData theme, ActionPlanRecord plan) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline_rounded, size: 16, color: Colors.indigo),
              const SizedBox(width: 6),
              const Text(
                'การวิเคราะห์เจาะลึก 5-Why Analysis',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.indigo),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (plan.why1 != null && plan.why1!.isNotEmpty)
            _buildWhyStepItem(1, 'ปรากฏการณ์หน้างาน', plan.why1!, Colors.blue, false),
          if (plan.why2 != null && plan.why2!.isNotEmpty)
            _buildWhyStepItem(2, 'ทำไมต่อเนื่อง #2', plan.why2!, Colors.indigo, false),
          if (plan.why3 != null && plan.why3!.isNotEmpty)
            _buildWhyStepItem(3, 'ทำไมต่อเนื่อง #3', plan.why3!, Colors.teal, false),
          if (plan.why4 != null && plan.why4!.isNotEmpty)
            _buildWhyStepItem(4, 'ทำไมต่อเนื่อง #4', plan.why4!, Colors.orange, false),
          if (plan.why5 != null && plan.why5!.isNotEmpty)
            _buildWhyStepItem(5, 'สาเหตุรากเหง้า (Root Cause)', plan.why5!, Colors.red, true),
        ],
      ),
    );
  }

  Widget _buildWhyStepItem(int step, String label, String text, Color color, bool isLast) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 11,
                backgroundColor: color,
                child: Text(
                  '$step',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Why #$step ($label):',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      text,
                      style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isLast)
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.grey.shade400),
              ),
            ),
        ],
      ),
    );
  }

  Widget _build4M1EGrid(ThemeData theme, ActionPlanRecord plan) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.alt_route_rounded, size: 16, color: Colors.deepOrange),
              SizedBox(width: 6),
              Text(
                'การวิเคราะห์ผังก้างปลา (Fishbone 4M1E)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.deepOrange),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (plan.fishboneMan != null && plan.fishboneMan!.isNotEmpty)
                _build4M1ECard('👨 คน / ช่าง (Man)', plan.fishboneMan!, Colors.blue),
              if (plan.fishboneMachine != null && plan.fishboneMachine!.isNotEmpty)
                _build4M1ECard('⚙️ เครื่องจักร (Machine)', plan.fishboneMachine!, Colors.orange),
              if (plan.fishboneMaterial != null && plan.fishboneMaterial!.isNotEmpty)
                _build4M1ECard('📦 วัตถุดิบ/อะไหล่ (Material)', plan.fishboneMaterial!, Colors.teal),
              if (plan.fishboneMethod != null && plan.fishboneMethod!.isNotEmpty)
                _build4M1ECard('📋 วิธีการ/คู่มือ (Method)', plan.fishboneMethod!, Colors.purple),
              if (plan.fishboneEnv != null && plan.fishboneEnv!.isNotEmpty)
                _build4M1ECard('🌡️ สภาพแวดล้อม (Environment)', plan.fishboneEnv!, Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _build4M1ECard(String label, String content, Color color) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 3),
          Text(
            content,
            style: const TextStyle(fontSize: 11.5, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistCard(
    BuildContext context,
    ThemeData theme,
    ActionPlanRecord plan,
    String progressPct,
    bool isCompleted,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isCompleted ? Colors.green.withValues(alpha: 0.3) : theme.dividerColor.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.checklist_rounded, size: 20, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text(
                  'ขั้นตอนการปฏิบัติงาน (${plan.completedStepsCount}/${plan.totalStepsCount} ขั้นตอนเสร็จสิ้น)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '$progressPct%',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isCompleted ? Colors.green : Colors.blueAccent,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.purple.shade700,
                  ),
                  icon: _isGeneratingAiSteps
                      ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 14),
                  label: const Text('AI ช่วยแตกขั้นตอน', style: TextStyle(fontSize: 11)),
                  onPressed: _isGeneratingAiSteps ? null : () => _generateAiSteps(plan),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('เพิ่มขั้นตอน', style: TextStyle(fontSize: 11)),
                  onPressed: () => _showAddStepDialog(context, plan),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: plan.progress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isCompleted ? Colors.green : Colors.blueAccent,
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (plan.actionSteps.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text('ยังไม่มีขั้นตอนการปฏิบัติงาน กดปุ่ม "เพิ่มขั้นตอน" หรือ "AI ช่วยแตกขั้นตอน"',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: plan.actionSteps.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.3)),
                itemBuilder: (context, idx) {
                  final step = plan.actionSteps[idx];
                  final isStepDone = step.status == 'completed';

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Checkbox(
                          value: isStepDone,
                          onChanged: (val) {
                            final newStatus = (val == true) ? 'completed' : 'pending';
                            ref.read(actionPlanListProvider.notifier).updateStepStatus(plan.rcaId, step.id, newStatus);
                          },
                        ),
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: isStepDone ? Colors.green : Colors.blue.shade700,
                          child: Text('${idx + 1}', style: const TextStyle(fontSize: 10, color: Colors.white)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                step.title,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  decoration: isStepDone ? TextDecoration.lineThrough : null,
                                  color: isStepDone ? Colors.grey : null,
                                ),
                              ),
                              if (step.note != null && step.note!.isNotEmpty)
                                Text(
                                  step.note!,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                            ],
                          ),
                        ),
                        if (step.assignee.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.person_outline, size: 13, color: Colors.blueAccent),
                                const SizedBox(width: 4),
                                Text(step.assignee, style: const TextStyle(fontSize: 11, color: Colors.blueAccent)),
                              ],
                            ),
                          ),
                        if (step.dueDate.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.access_time, size: 13, color: Colors.orange),
                                const SizedBox(width: 4),
                                Text(step.dueDate, style: const TextStyle(fontSize: 11, color: Colors.orange)),
                              ],
                            ),
                          ),
                        DropdownButton<String>(
                          value: step.status,
                          underline: const SizedBox(),
                          isDense: true,
                          style: const TextStyle(fontSize: 11.5, color: Colors.black),
                          items: const [
                            DropdownMenuItem(value: 'pending', child: Text('⏳ รอดำเนินการ')),
                            DropdownMenuItem(value: 'in_progress', child: Text('🔄 กำลังทำ')),
                            DropdownMenuItem(value: 'completed', child: Text('✅ เสร็จแล้ว')),
                          ],
                          onChanged: (newStatus) {
                            if (newStatus != null) {
                              ref.read(actionPlanListProvider.notifier).updateStepStatus(plan.rcaId, step.id, newStatus);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          onPressed: () {
                            final updated = List<ActionStepItem>.from(plan.actionSteps)..removeAt(idx);
                            _updateSteps(plan, updated);
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationCard(BuildContext context, ThemeData theme, ActionPlanRecord plan) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.green.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_outlined, size: 20, color: Colors.green),
                const SizedBox(width: 8),
                const Text(
                  'การสอบทานและประเมินผลสำเร็จ (Verification & Validation)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.green),
                ),
                const Spacer(),
                if (plan.verificationResult != null && plan.verificationResult!.isNotEmpty)
                  _buildVerificationResultBadge(plan.verificationResult!),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.edit, size: 14),
                  label: const Text('บันทึกผลสอบทาน', style: TextStyle(fontSize: 11)),
                  onPressed: () => _showVerificationDialog(context, plan),
                ),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    'ตัวชี้วัดเป้าหมาย',
                    plan.targetMetric?.isNotEmpty == true ? plan.targetMetric! : 'ยังไม่ระบุ',
                    Icons.speed_rounded,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    'ก่อนปรับปรุง (Before)',
                    '${plan.beforeValue?.toStringAsFixed(1) ?? "-"} ${plan.metricUnit ?? ""}',
                    Icons.history_rounded,
                    Colors.redAccent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    'เป้าหมาย (Target)',
                    '${plan.targetValue?.toStringAsFixed(1) ?? "-"} ${plan.metricUnit ?? ""}',
                    Icons.flag_rounded,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricTile(
                    'ผลจริงหลังปรับปรุง (Actual)',
                    '${plan.actualValue?.toStringAsFixed(1) ?? "-"} ${plan.metricUnit ?? ""}',
                    Icons.check_circle_outline,
                    Colors.green,
                  ),
                ),
              ],
            ),
            if (plan.reductionPercentage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: plan.reductionPercentage! > 0 ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: plan.reductionPercentage! > 0 ? Colors.green.shade300 : Colors.red.shade300,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      plan.reductionPercentage! > 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                      color: plan.reductionPercentage! > 0 ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      plan.reductionPercentage! > 0
                          ? 'ความสำเร็จ: ค่าตัวชี้วัดลดลงได้จริง ${plan.reductionPercentage!.toStringAsFixed(1)}% บรรลุตามเป้าหมาย!'
                          : 'ผลตรวจวัด: ค่าตัวชี้วัดเปลี่ยนแปลง ${plan.reductionPercentage!.abs().toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        color: plan.reductionPercentage! > 0 ? Colors.green.shade900 : Colors.red.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (plan.verifiedBy != null && plan.verifiedBy!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'ผู้ตรวจสอบ: ${plan.verifiedBy} | วันที่ตรวจสอบ: ${plan.verificationDate ?? "-"} | แผนคงสภาพ (Standardization): ${plan.standardizationNotes ?? "-"}',
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentsCard(BuildContext context, ThemeData theme, ActionPlanRecord plan) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.attach_file_rounded, size: 20, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  'รูปภาพและเอกสารแนบ (${plan.attachments.length} ไฟล์)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                  label: const Text('+ แนบรูป/เอกสาร', style: TextStyle(fontSize: 11)),
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles(
                      allowMultiple: true,
                      type: FileType.custom,
                      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'xlsx', 'docx'],
                    );
                    if (result != null && result.files.isNotEmpty) {
                      for (final f in result.files) {
                        if (f.path != null) {
                          await ref.read(actionPlanListProvider.notifier).addAttachment(
                                plan.rcaId,
                                f.path!,
                                displayName: f.name,
                              );
                        }
                      }
                      ref.invalidate(actionPlanDetailProvider(plan.rcaId));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('แนบไฟล์สำเร็จ!')),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
            const Divider(height: 20),
            if (plan.attachments.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text('ยังไม่มีเอกสารหรือรูปภาพแนบ', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: plan.attachments.map((asset) {
                  final fileName = asset['display_name'] ?? asset['file_name'] ?? 'เอกสารแนบ';
                  final filePath = asset['storage_path'] ?? asset['source_path'] ?? asset['file_path'] ?? '';
                  final isImg = fileName.toLowerCase().endsWith('.png') ||
                      fileName.toLowerCase().endsWith('.jpg') ||
                      fileName.toLowerCase().endsWith('.jpeg');
                  final isPdf = fileName.toLowerCase().endsWith('.pdf');

                  return InkWell(
                    onTap: () {
                      if (filePath.isNotEmpty) {
                        OpenFilex.open(filePath);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isImg ? Icons.image_rounded : (isPdf ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded),
                            size: 18,
                            color: isImg ? Colors.teal : (isPdf ? Colors.red : Colors.blue),
                          ),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 200),
                            child: Text(
                              fileName,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () async {
                              final assetId = asset['asset_id']?.toString();
                              if (assetId != null) {
                                await ref.read(actionPlanListProvider.notifier).removeAttachment(assetId);
                                ref.invalidate(actionPlanDetailProvider(plan.rcaId));
                              }
                            },
                            child: const Icon(Icons.close, size: 16, color: Colors.redAccent),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceBadge(String sourceType) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    switch (sourceType) {
      case 'work_order':
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        label = 'งานซ่อม (WO)';
        icon = Icons.build_circle_outlined;
        break;
      case 'line_balancing':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        label = 'Line Balancing';
        icon = Icons.account_tree_outlined;
        break;
      case 'sop_step':
        bg = Colors.teal.shade50;
        fg = Colors.teal.shade800;
        label = 'SOP ขั้นตอนงาน';
        icon = Icons.format_list_numbered_rounded;
        break;
      default:
        bg = Colors.purple.shade50;
        fg = Colors.purple.shade800;
        label = 'ปัญหากำหนดเอง';
        icon = Icons.flag_outlined;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg)),
        ],
      ),
    );
  }

  Widget _buildStatusDropdown(ActionPlanRecord plan) {
    Color color;
    switch (plan.status) {
      case 'completed':
      case 'closed':
        color = Colors.green;
        break;
      case 'in_progress':
        color = Colors.orange;
        break;
      default:
        color = Colors.blueGrey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: plan.status,
          isDense: true,
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: color),
          items: const [
            DropdownMenuItem(value: 'pending', child: Text('⏳ รอดำเนินการ')),
            DropdownMenuItem(value: 'in_progress', child: Text('🔄 กำลังดำเนินการ')),
            DropdownMenuItem(value: 'completed', child: Text('✅ เสร็จสมบูรณ์')),
            DropdownMenuItem(value: 'closed', child: Text('🔒 ปิดแผนงานแล้ว')),
          ],
          onChanged: (newStatus) {
            if (newStatus != null) {
              ref.read(actionPlanListProvider.notifier).updatePlanStatus(plan.rcaId, newStatus);
              ref.invalidate(actionPlanDetailProvider(plan.rcaId));
            }
          },
        ),
      ),
    );
  }

  Widget _buildVerificationResultBadge(String res) {
    Color color;
    String text;
    switch (res) {
      case 'achieved':
        color = Colors.green;
        text = '✅ สำเร็จตามเป้า';
        break;
      case 'partial':
        color = Colors.orange;
        text = '🔄 ดีขึ้นแต่ยังไม่ถึงเป้า';
        break;
      case 'failed':
        color = Colors.red;
        text = '⚠️ ไม่สำเร็จ';
        break;
      default:
        color = Colors.blue;
        text = '⏳ อยู่ระหว่างตรวจวัด';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Future<void> _updateSteps(ActionPlanRecord plan, List<ActionStepItem> steps) async {
    await ref.read(actionPlanListProvider.notifier).savePlan(
          rcaId: plan.rcaId,
          problemTitle: plan.problemTitle,
          sourceType: plan.sourceType,
          sourceId: plan.sourceId,
          rootCause: plan.rootCause,
          why1: plan.why1,
          why2: plan.why2,
          why3: plan.why3,
          why4: plan.why4,
          why5: plan.why5,
          fishboneMan: plan.fishboneMan,
          fishboneMachine: plan.fishboneMachine,
          fishboneMaterial: plan.fishboneMaterial,
          fishboneMethod: plan.fishboneMethod,
          fishboneEnv: plan.fishboneEnv,
          actionSteps: steps,
          targetMetric: plan.targetMetric,
          beforeValue: plan.beforeValue,
          targetValue: plan.targetValue,
          actualValue: plan.actualValue,
          metricUnit: plan.metricUnit,
          verifiedBy: plan.verifiedBy,
          verificationDate: plan.verificationDate,
          verificationResult: plan.verificationResult,
          standardizationNotes: plan.standardizationNotes,
          status: plan.status,
        );
    ref.invalidate(actionPlanDetailProvider(plan.rcaId));
  }

  Future<void> _generateAiSteps(ActionPlanRecord plan) async {
    setState(() => _isGeneratingAiSteps = true);
    try {
      final prompt = '''
คุณคือผู้เชี่ยวชาญด้าน TPM, Lean และ Industrial Engineering
ข้อมูลปัญหาและการวิเคราะห์ RCA:
- ปัญหา: ${plan.problemTitle}
- สาเหตุรากเหง้า: ${plan.rootCause ?? "-"}

กรุณาช่วยแตกแผนปฏิบัติการ (Action Plan) ออกเป็นขั้นตอนการดำเนินงานย่อย 3 - 5 ขั้นตอนแบบเป็นลำดับขั้นตอน (Phase/Milestones) ที่ทีมงานสามารถนำไปปฏิบัติได้จริงในโรงงาน พร้อมกำหนดผู้รับผิดชอบและระยะเวลาที่เหมาะสม
ตอบเป็น JSON Array ในรูปแบบนี้เท่านั้น:
[
  {
    "title": "1. ตรวจสอบและแก้ไขสาเหตุหน้างาน...",
    "assignee": "ช่างซ่อมบำรุง / วิศวกร",
    "due_date": "ภายใน 3 วัน",
    "status": "pending"
  }
]
''';
      final res = await AiService.chat(history: [], userMessage: prompt);
      final raw = res.text.trim();
      final start = raw.indexOf('[');
      final end = raw.lastIndexOf(']');
      if (start != -1 && end != -1) {
        final jsonStr = raw.substring(start, end + 1);
        final dynamic parsed = jsonDecode(jsonStr);
        if (parsed is List) {
          final newSteps = parsed.map((item) {
            final map = item as Map<String, dynamic>;
            return ActionStepItem(
              id: const Uuid().v4(),
              title: map['title']?.toString() ?? '',
              assignee: map['assignee']?.toString() ?? '',
              dueDate: map['due_date']?.toString() ?? '',
              status: map['status']?.toString() ?? 'pending',
            );
          }).toList();

          await _updateSteps(plan, newSteps);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('AI ช่วยแตกขั้นตอนปฏิบัติการสำเร็จ!')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingAiSteps = false);
    }
  }

  void _showAddStepDialog(BuildContext context, ActionPlanRecord plan) {
    final titleCtrl = TextEditingController();
    final assigneeCtrl = TextEditingController();
    final dueDateCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เพิ่มขั้นตอนการปฏิบัติงาน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'รายละเอียดขั้นตอนการทำงาน *',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: assigneeCtrl,
              decoration: const InputDecoration(
                labelText: 'ผู้รับผิดชอบ',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dueDateCtrl,
              decoration: const InputDecoration(
                labelText: 'กำหนดเสร็จ (เช่น ภายใน 3 วัน หรือ 28/08/2026)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => ctx.pop(), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty) return;
              final newStep = ActionStepItem(
                id: const Uuid().v4(),
                title: titleCtrl.text.trim(),
                assignee: assigneeCtrl.text.trim(),
                dueDate: dueDateCtrl.text.trim(),
                status: 'pending',
              );
              final updated = List<ActionStepItem>.from(plan.actionSteps)..add(newStep);
              await _updateSteps(plan, updated);
              if (ctx.mounted) ctx.pop();
            },
            child: const Text('เพิ่ม'),
          ),
        ],
      ),
    );
  }

  void _showVerificationDialog(BuildContext context, ActionPlanRecord plan) {
    final metricCtrl = TextEditingController(text: plan.targetMetric ?? '');
    final beforeCtrl = TextEditingController(text: plan.beforeValue?.toString() ?? '');
    final targetCtrl = TextEditingController(text: plan.targetValue?.toString() ?? '');
    final actualCtrl = TextEditingController(text: plan.actualValue?.toString() ?? '');
    final unitCtrl = TextEditingController(text: plan.metricUnit ?? '');
    final verifiedByCtrl = TextEditingController(text: plan.verifiedBy ?? '');
    final dateCtrl = TextEditingController(
      text: plan.verificationDate ?? DateFormat('dd/MM/yyyy').format(DateTime.now()),
    );
    final notesCtrl = TextEditingController(text: plan.standardizationNotes ?? '');
    String result = plan.verificationResult ?? 'achieved';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('บันทึกผลการสอบทาน & ตรวจวัดผลสำเร็จ'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: metricCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ตัวชี้วัด (Target Metric เช่น Cycle Time, Downtime)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: beforeCtrl,
                          decoration: const InputDecoration(labelText: 'ก่อนปรับปรุง', border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: targetCtrl,
                          decoration: const InputDecoration(labelText: 'เป้าหมาย', border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: actualCtrl,
                          decoration: const InputDecoration(labelText: 'ผลจริง', border: OutlineInputBorder()),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 80,
                        child: TextField(
                          controller: unitCtrl,
                          decoration: const InputDecoration(labelText: 'หน่วย', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: result,
                    decoration: const InputDecoration(labelText: 'ผลการประเมิน', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'achieved', child: Text('✅ บรรลุตามเป้าหมาย (Achieved)')),
                      DropdownMenuItem(value: 'partial', child: Text('🔄 ดีขึ้นแต่ยังไม่ถึงเป้า (Partial)')),
                      DropdownMenuItem(value: 'failed', child: Text('⚠️ ไม่บรรลุเป้าหมาย (Failed)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDlgState(() => result = val);
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: verifiedByCtrl,
                          decoration: const InputDecoration(labelText: 'ผู้ตรวจสอบ', border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: dateCtrl,
                          decoration: const InputDecoration(labelText: 'วันที่ตรวจสอบ', border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'แผนคงสภาพ / อัปเดตมาตรฐาน (Standardization Notes)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => ctx.pop(), child: const Text('ยกเลิก')),
            FilledButton(
              onPressed: () async {
                await ref.read(actionPlanListProvider.notifier).updateVerification(
                      rcaId: plan.rcaId,
                      targetMetric: metricCtrl.text.trim(),
                      beforeValue: double.tryParse(beforeCtrl.text.trim()),
                      targetValue: double.tryParse(targetCtrl.text.trim()),
                      actualValue: double.tryParse(actualCtrl.text.trim()),
                      metricUnit: unitCtrl.text.trim(),
                      verifiedBy: verifiedByCtrl.text.trim(),
                      verificationDate: dateCtrl.text.trim(),
                      verificationResult: result,
                      standardizationNotes: notesCtrl.text.trim(),
                    );
                ref.invalidate(actionPlanDetailProvider(plan.rcaId));
                if (ctx.mounted) ctx.pop();
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPlanDialog(BuildContext context, ActionPlanRecord plan) {
    final titleCtrl = TextEditingController(text: plan.problemTitle);
    final rootCauseCtrl = TextEditingController(text: plan.rootCause ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('แก้ไขหัวข้อ Action Plan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(labelText: 'หัวข้อปัญหา / แผนงาน', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: rootCauseCtrl,
              decoration: const InputDecoration(labelText: 'สาเหตุรากเหง้า (Root Cause)', border: OutlineInputBorder()),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => ctx.pop(), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () async {
              await ref.read(actionPlanListProvider.notifier).savePlan(
                    rcaId: plan.rcaId,
                    problemTitle: titleCtrl.text.trim(),
                    sourceType: plan.sourceType,
                    sourceId: plan.sourceId,
                    rootCause: rootCauseCtrl.text.trim(),
                    why1: plan.why1,
                    why2: plan.why2,
                    why3: plan.why3,
                    why4: plan.why4,
                    why5: plan.why5,
                    fishboneMan: plan.fishboneMan,
                    fishboneMachine: plan.fishboneMachine,
                    fishboneMaterial: plan.fishboneMaterial,
                    fishboneMethod: plan.fishboneMethod,
                    fishboneEnv: plan.fishboneEnv,
                    actionSteps: plan.actionSteps,
                    targetMetric: plan.targetMetric,
                    beforeValue: plan.beforeValue,
                    targetValue: plan.targetValue,
                    actualValue: plan.actualValue,
                    metricUnit: plan.metricUnit,
                    verifiedBy: plan.verifiedBy,
                    verificationDate: plan.verificationDate,
                    verificationResult: plan.verificationResult,
                    standardizationNotes: plan.standardizationNotes,
                    status: plan.status,
                  );
              ref.invalidate(actionPlanDetailProvider(plan.rcaId));
              if (ctx.mounted) ctx.pop();
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}
