import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/ai/ai_service.dart';
import '../models/action_plan_model.dart';
import '../providers/action_plan_provider.dart';

class ActionPlanFormScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initialData;
  final String? editRcaId;

  const ActionPlanFormScreen({
    super.key,
    this.initialData,
    this.editRcaId,
  });

  @override
  ConsumerState<ActionPlanFormScreen> createState() => _ActionPlanFormScreenState();
}

class _ActionPlanFormScreenState extends ConsumerState<ActionPlanFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late String _rcaId;
  late String _sourceType;
  String? _sourceId;

  final _titleCtrl = TextEditingController();
  final _rootCauseCtrl = TextEditingController();
  final _why1Ctrl = TextEditingController();
  final _why2Ctrl = TextEditingController();
  final _why3Ctrl = TextEditingController();
  final _why4Ctrl = TextEditingController();
  final _why5Ctrl = TextEditingController();

  final _fishboneManCtrl = TextEditingController();
  final _fishboneMachineCtrl = TextEditingController();
  final _fishboneMaterialCtrl = TextEditingController();
  final _fishboneMethodCtrl = TextEditingController();
  final _fishboneEnvCtrl = TextEditingController();

  final _targetMetricCtrl = TextEditingController();
  final _beforeValCtrl = TextEditingController();
  final _targetValCtrl = TextEditingController();
  final _unitCtrl = TextEditingController();

  final List<ActionStepItem> _actionSteps = [];
  bool _isSaving = false;
  bool _isGeneratingAiSteps = false;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData ?? {};

    _rcaId = data['rca_id']?.toString() ?? widget.editRcaId ?? 'rca_${const Uuid().v4().substring(0, 8)}';
    _sourceType = data['source_type']?.toString() ?? 'custom';
    _sourceId = data['source_id']?.toString();

    _titleCtrl.text = data['problem_title']?.toString() ?? data['title']?.toString() ?? '';
    _rootCauseCtrl.text = data['root_cause']?.toString() ?? '';
    _why1Ctrl.text = data['why_1']?.toString() ?? '';
    _why2Ctrl.text = data['why_2']?.toString() ?? '';
    _why3Ctrl.text = data['why_3']?.toString() ?? '';
    _why4Ctrl.text = data['why_4']?.toString() ?? '';
    _why5Ctrl.text = data['why_5']?.toString() ?? '';

    _fishboneManCtrl.text = data['fishbone_man']?.toString() ?? '';
    _fishboneMachineCtrl.text = data['fishbone_machine']?.toString() ?? '';
    _fishboneMaterialCtrl.text = data['fishbone_material']?.toString() ?? '';
    _fishboneMethodCtrl.text = data['fishbone_method']?.toString() ?? '';
    _fishboneEnvCtrl.text = data['fishbone_env']?.toString() ?? '';

    _targetMetricCtrl.text = data['target_metric']?.toString() ?? '';
    if (data['before_value'] != null) _beforeValCtrl.text = data['before_value'].toString();
    if (data['target_value'] != null) _targetValCtrl.text = data['target_value'].toString();
    _unitCtrl.text = data['metric_unit']?.toString() ?? '';

    // Action steps if passed
    if (data['action_steps'] is List) {
      for (final s in data['action_steps'] as List) {
        if (s is ActionStepItem) {
          _actionSteps.add(s);
        } else if (s is Map<String, dynamic>) {
          _actionSteps.add(ActionStepItem.fromJson(s));
        }
      }
    }

    if (_actionSteps.isEmpty) {
      _actionSteps.add(
        ActionStepItem(
          id: const Uuid().v4(),
          title: '1. ตรวจสอบและแก้ไขสาเหตุหน้างาน',
          status: 'pending',
        ),
      );
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _rootCauseCtrl.dispose();
    _why1Ctrl.dispose();
    _why2Ctrl.dispose();
    _why3Ctrl.dispose();
    _why4Ctrl.dispose();
    _why5Ctrl.dispose();
    _fishboneManCtrl.dispose();
    _fishboneMachineCtrl.dispose();
    _fishboneMaterialCtrl.dispose();
    _fishboneMethodCtrl.dispose();
    _fishboneEnvCtrl.dispose();
    _targetMetricCtrl.dispose();
    _beforeValCtrl.dispose();
    _targetValCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.editRcaId != null ? 'แก้ไขแผนปฏิบัติการ (Action Plan)' : 'สร้างแผนปฏิบัติการ (Action Plan)',
        ),
        actions: [
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade700),
            icon: _isSaving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('บันทึกแผนงาน'),
            onPressed: _isSaving ? null : _saveActionPlan,
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Problem Information Card
              _buildProblemInfoCard(theme),
              const SizedBox(height: 16),

              // 2. Action Steps Checklist Builder Card
              _buildActionStepsCard(theme),
              const SizedBox(height: 16),

              // 3. Target Metric & Baseline Setting Card
              _buildMetricCard(theme),
              const SizedBox(height: 32),

              // Bottom Save Button
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    backgroundColor: Colors.blue.shade700,
                  ),
                  icon: const Icon(Icons.save_rounded, size: 20),
                  label: const Text('บันทึกแผนปฏิบัติการ & เข้าสู่หน้ารายละเอียด', style: TextStyle(fontSize: 14)),
                  onPressed: _isSaving ? null : _saveActionPlan,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProblemInfoCard(ThemeData theme) {
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
            const Row(
              children: [
                Icon(Icons.assignment_outlined, size: 18, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text('1. ข้อมูลหัวข้อปัญหา และแหล่งที่มา', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<String>(
                    value: _sourceType,
                    decoration: const InputDecoration(labelText: 'แหล่งที่มาของปัญหา *', border: OutlineInputBorder()),
                    items: const [
                      DropdownMenuItem(value: 'work_order', child: Text('🔧 งานซ่อมบำรุง (Work Order)')),
                      DropdownMenuItem(value: 'line_balancing', child: Text('⚙️ สายการผลิต (Line Balancing)')),
                      DropdownMenuItem(value: 'sop_step', child: Text('📋 ขั้นตอนการทำงาน (SOP)')),
                      DropdownMenuItem(value: 'custom', child: Text('🎯 ปัญหากำหนดเอง (Custom Issue)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _sourceType = val);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                if (_sourceId != null && _sourceId!.isNotEmpty)
                  Expanded(
                    flex: 1,
                    child: TextFormField(
                      initialValue: _sourceId,
                      decoration: const InputDecoration(labelText: 'รหัสอ้างอิง', border: OutlineInputBorder()),
                      readOnly: true,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(
                labelText: 'หัวข้อปัญหา / แผนงานที่ต้องการปรับปรุง *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.title_rounded),
              ),
              validator: (val) => val == null || val.trim().isEmpty ? 'กรุณาระบุหัวข้อปัญหา' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _rootCauseCtrl,
              decoration: const InputDecoration(
                labelText: 'สาเหตุรากเหง้า (Root Cause) จากการวิเคราะห์ RCA',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.crisis_alert_rounded, color: Colors.redAccent),
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionStepsCard(ThemeData theme) {
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
                const Icon(Icons.checklist_rounded, size: 20, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text(
                  '2. ขั้นตอนการดำเนินงาน (${_actionSteps.length} ขั้นตอน)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.purple.shade700),
                  icon: _isGeneratingAiSteps
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('🤖 AI ช่วยแตกขั้นตอน'),
                  onPressed: _isGeneratingAiSteps ? null : _generateAiSteps,
                ),
                const SizedBox(width: 8),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('+ เพิ่มขั้นตอน'),
                  onPressed: _addStep,
                ),
              ],
            ),
            const Divider(height: 20),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _actionSteps.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, idx) {
                final step = _actionSteps[idx];
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.blue.shade700,
                        child: Text('${idx + 1}', style: const TextStyle(fontSize: 11, color: Colors.white)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          children: [
                            TextFormField(
                              initialValue: step.title,
                              decoration: InputDecoration(
                                labelText: 'ขั้นตอนที่ ${idx + 1} *',
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (val) => step.title = val,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    initialValue: step.assignee,
                                    decoration: const InputDecoration(
                                      labelText: 'ผู้รับผิดชอบ',
                                      isDense: true,
                                      prefixIcon: Icon(Icons.person_outline, size: 16),
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) => step.assignee = val,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextFormField(
                                    initialValue: step.dueDate,
                                    decoration: const InputDecoration(
                                      labelText: 'กำหนดเสร็จ',
                                      isDense: true,
                                      prefixIcon: Icon(Icons.access_time, size: 16),
                                      border: OutlineInputBorder(),
                                    ),
                                    onChanged: (val) => step.dueDate = val,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                        onPressed: () {
                          setState(() {
                            _actionSteps.removeAt(idx);
                          });
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

  Widget _buildMetricCard(ThemeData theme) {
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
            const Row(
              children: [
                Icon(Icons.speed_rounded, size: 18, color: Colors.green),
                SizedBox(width: 8),
                Text('3. การตั้งเป้าหมายตัวชี้วัด (Target Metric Baseline)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _targetMetricCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ตัวชี้วัด (เช่น Cycle Time, Downtime, Defect Rate)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _beforeValCtrl,
                    decoration: const InputDecoration(labelText: 'ค่าก่อนปรับปรุง', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _targetValCtrl,
                    decoration: const InputDecoration(labelText: 'ค่าเป้าหมาย', border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: _unitCtrl,
                    decoration: const InputDecoration(labelText: 'หน่วย', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _addStep() {
    setState(() {
      _actionSteps.add(
        ActionStepItem(
          id: const Uuid().v4(),
          title: '',
          status: 'pending',
        ),
      );
    });
  }

  Future<void> _generateAiSteps() async {
    setState(() => _isGeneratingAiSteps = true);
    try {
      final prompt = '''
คุณคือผู้เชี่ยวชาญด้าน TPM, Lean และ Industrial Engineering
ข้อมูลปัญหาและการวิเคราะห์ RCA:
- ปัญหา: ${_titleCtrl.text.trim()}
- สาเหตุรากเหง้า: ${_rootCauseCtrl.text.trim()}

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

          setState(() {
            _actionSteps.clear();
            _actionSteps.addAll(newSteps);
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI ช่วยแตกขั้นตอนไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingAiSteps = false);
    }
  }

  Future<void> _saveActionPlan() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      final validSteps = _actionSteps.where((s) => s.title.trim().isNotEmpty).toList();

      await ref.read(actionPlanListProvider.notifier).savePlan(
            rcaId: _rcaId,
            problemTitle: _titleCtrl.text.trim(),
            sourceType: _sourceType,
            sourceId: _sourceId,
            rootCause: _rootCauseCtrl.text.trim(),
            why1: _why1Ctrl.text.trim(),
            why2: _why2Ctrl.text.trim(),
            why3: _why3Ctrl.text.trim(),
            why4: _why4Ctrl.text.trim(),
            why5: _why5Ctrl.text.trim(),
            fishboneMan: _fishboneManCtrl.text.trim(),
            fishboneMachine: _fishboneMachineCtrl.text.trim(),
            fishboneMaterial: _fishboneMaterialCtrl.text.trim(),
            fishboneMethod: _fishboneMethodCtrl.text.trim(),
            fishboneEnv: _fishboneEnvCtrl.text.trim(),
            actionSteps: validSteps,
            targetMetric: _targetMetricCtrl.text.trim(),
            beforeValue: double.tryParse(_beforeValCtrl.text.trim()),
            targetValue: double.tryParse(_targetValCtrl.text.trim()),
            metricUnit: _unitCtrl.text.trim(),
          );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('บันทึกแผนปฏิบัติการสำเร็จ!'),
            backgroundColor: Colors.green,
          ),
        );
        // Replace with detail screen
        context.pushReplacement('/action-plans/$_rcaId');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกล้มเหลว: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
