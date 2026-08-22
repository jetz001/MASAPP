import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:collection/collection.dart';
import '../../../core/ai/ai_service.dart';
import '../../../core/database/db_helper.dart';
import '../../../core/theme/app_spacing.dart';
import '../../work_processes/models/work_process_model.dart';
import '../../work_processes/models/work_process_step_model.dart';
import '../../work_processes/providers/work_process_provider.dart';
import '../../line_balancing/line_balancing_provider.dart';

class ProblemSolvingScreen extends ConsumerStatefulWidget {
  final String? initialProcessId;
  final String? initialStepId;
  final String? initialProblemTitle;

  const ProblemSolvingScreen({
    super.key,
    this.initialProcessId,
    this.initialStepId,
    this.initialProblemTitle,
  });

  @override
  ConsumerState<ProblemSolvingScreen> createState() =>
      _ProblemSolvingScreenState();
}

class _ProblemSolvingScreenState extends ConsumerState<ProblemSolvingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _sourceMode = 0; // 0: Line Balancing, 1: Machine SOPs, 2: Custom Problem

  WorkProcessStep? _selectedStep;
  WorkstationData? _selectedStation;
  bool _isGeneratingAi = false;
  bool _isSaving = false;

  // Controllers
  final _problemTitleCtrl = TextEditingController();
  final _why1Ctrl = TextEditingController();
  final _why2Ctrl = TextEditingController();
  final _why3Ctrl = TextEditingController();
  final _why4Ctrl = TextEditingController();
  final _why5Ctrl = TextEditingController();
  final _rootCauseCtrl = TextEditingController();
  final _correctiveCtrl = TextEditingController();
  final _preventiveCtrl = TextEditingController();

  // Fishbone 4M1E
  final _fishboneManCtrl = TextEditingController();
  final _fishboneMachineCtrl = TextEditingController();
  final _fishboneMaterialCtrl = TextEditingController();
  final _fishboneMethodCtrl = TextEditingController();
  final _fishboneEnvCtrl = TextEditingController();

  // Action Plan
  final _actionOwnerCtrl = TextEditingController();
  final _actionDueDateCtrl = TextEditingController();
  String _actionStatus = 'pending'; // pending, in_progress, completed

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    if (widget.initialProblemTitle != null) {
      _problemTitleCtrl.text = widget.initialProblemTitle!;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _problemTitleCtrl.dispose();
    _why1Ctrl.dispose();
    _why2Ctrl.dispose();
    _why3Ctrl.dispose();
    _why4Ctrl.dispose();
    _why5Ctrl.dispose();
    _rootCauseCtrl.dispose();
    _correctiveCtrl.dispose();
    _preventiveCtrl.dispose();
    _fishboneManCtrl.dispose();
    _fishboneMachineCtrl.dispose();
    _fishboneMaterialCtrl.dispose();
    _fishboneMethodCtrl.dispose();
    _fishboneEnvCtrl.dispose();
    _actionOwnerCtrl.dispose();
    _actionDueDateCtrl.dispose();
    super.dispose();
  }

  void _populateFromStep(WorkProcessStep step) {
    setState(() {
      _selectedStep = step;
      _problemTitleCtrl.text = step.problemCause?.isNotEmpty == true
          ? step.problemCause!
          : 'ปัญหาคอขวด/สูญเปล่าในขั้นตอน: ${step.description}';
      _why1Ctrl.text = step.problemCause ?? '';
      _rootCauseCtrl.text = step.problemCause ?? '';
      _preventiveCtrl.text = step.improvementIdea ?? '';
    });
  }

  void _populateFromStation(WorkstationData station) {
    setState(() {
      _selectedStation = station;
      _problemTitleCtrl.text =
          'ปัญหาคอขวดประจำสถานี: ${station.name} (${station.cycleTime.toStringAsFixed(1)}s)';
      _why1Ctrl.text = 'เวลารอบการทำงาน (Cycle Time) สูงเกิน Takt Time';
      _rootCauseCtrl.text = 'เครื่องจักรทำงานช้า หรือขั้นตอนการทำงานไม่สมดุล';
    });
  }

  Future<void> _generateAiRca() async {
    final problemDesc = _problemTitleCtrl.text.trim().isNotEmpty
        ? _problemTitleCtrl.text.trim()
        : (_selectedStep?.description ??
            _selectedStation?.name ??
            'ปัญหาในสายการผลิต');

    setState(() => _isGeneratingAi = true);

    try {
      final prompt = '''
คุณคือผู้เชี่ยวชาญด้าน Lean Manufacturing, Root Cause Analysis (RCA) และ 5-Why Problem Solving
ช่วยวิเคราะห์ปัญหาการผลิตต่อไปนี้:
"หัวข้อปัญหา: $problemDesc"
รายละเอียดเพิ่มเติม: ${_selectedStep != null ? "ขั้นตอน: ${_selectedStep!.description}, ประเภทคุณค่า: ${_selectedStep!.valueType.label}" : ""}
${_selectedStation != null ? "สถานี: ${_selectedStation!.name}, เครื่องจักร: ${_selectedStation!.machineName ?? '-'}, Cycle Time: ${_selectedStation!.cycleTime}s" : ""}

กรุณาตอบเป็น JSON ในรูปแบบนี้เท่านั้น:
{
  "why1": "ทำไมที่ 1...",
  "why2": "ทำไมที่ 2...",
  "why3": "ทำไมที่ 3...",
  "why4": "ทำไมที่ 4...",
  "why5": "ทำไมที่ 5 (สาเหตุรากเหง้า)...",
  "rootCause": "สรุปสาเหตุที่แท้จริง...",
  "correctiveAction": "มาตรการแก้ไขชั่วคราว/เร่งด่วน...",
  "preventiveAction": "มาตรการป้องกันการเกิดซ้ำ (Kaizen/Poka-Yoke)...",
  "fishbone": {
    "man": "สาเหตุด้านคน...",
    "machine": "สาเหตุด้านเครื่องจักร...",
    "material": "สาเหตุด้านวัตถุดิบ...",
    "method": "สาเหตุด้านวิธีการทำงาน...",
    "environment": "สาเหตุด้านสภาพแวดล้อม..."
  }
}
''';

      final result = await AiService.chat(
        history: [],
        userMessage: prompt,
      );

      final rawText = result.text.trim();
      final jsonStart = rawText.indexOf('{');
      final jsonEnd = rawText.lastIndexOf('}');
      if (jsonStart != -1 && jsonEnd != -1) {
        final rawJson = rawText.substring(jsonStart, jsonEnd + 1);
        String extractKey(String key) {
          final reg = RegExp('"$key"\\s*:\\s*"([^"]+)"');
          final match = reg.firstMatch(rawJson);
          return match?.group(1) ?? '';
        }

        setState(() {
          _why1Ctrl.text = extractKey('why1').isNotEmpty ? extractKey('why1') : extractKey('why_1');
          _why2Ctrl.text = extractKey('why2').isNotEmpty ? extractKey('why2') : extractKey('why_2');
          _why3Ctrl.text = extractKey('why3').isNotEmpty ? extractKey('why3') : extractKey('why_3');
          _why4Ctrl.text = extractKey('why4').isNotEmpty ? extractKey('why4') : extractKey('why_4');
          _why5Ctrl.text = extractKey('why5').isNotEmpty ? extractKey('why5') : extractKey('why_5');
          _rootCauseCtrl.text = extractKey('rootCause').isNotEmpty ? extractKey('rootCause') : extractKey('root_cause');
          _correctiveCtrl.text = extractKey('correctiveAction').isNotEmpty ? extractKey('correctiveAction') : extractKey('corrective_action');
          _preventiveCtrl.text = extractKey('preventiveAction').isNotEmpty ? extractKey('preventiveAction') : extractKey('preventive_action');

          _fishboneManCtrl.text = extractKey('man').isNotEmpty ? extractKey('man') : extractKey('fishbone_man');
          _fishboneMachineCtrl.text = extractKey('machine').isNotEmpty ? extractKey('machine') : extractKey('fishbone_machine');
          _fishboneMaterialCtrl.text = extractKey('material').isNotEmpty ? extractKey('material') : extractKey('fishbone_material');
          _fishboneMethodCtrl.text = extractKey('method').isNotEmpty ? extractKey('method') : extractKey('fishbone_method');
          _fishboneEnvCtrl.text = extractKey('environment').isNotEmpty ? extractKey('environment') : extractKey('fishbone_environment');
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI วิเคราะห์ไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingAi = false);
    }
  }

  Future<void> _saveProblemResolution() async {
    setState(() => _isSaving = true);
    try {
      // If attached to a step, update SQLite work_process_steps
      if (_selectedStep != null) {
        final rootCause = _rootCauseCtrl.text.isNotEmpty ? _rootCauseCtrl.text : _why1Ctrl.text;
        final preventive = _preventiveCtrl.text.isNotEmpty ? _preventiveCtrl.text : _correctiveCtrl.text;

        await DbHelper.execute('''
          UPDATE work_process_steps
          SET problem_cause = @pc,
              improvement_idea = @ii,
              updated_at = CURRENT_TIMESTAMP
          WHERE step_id = @id
        ''', params: {
          'pc': rootCause,
          'ii': preventive,
          'id': _selectedStep!.stepId,
        });
        ref.invalidate(workProcessListProvider);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('บันทึกผลการวิเคราะห์ RCA และมาตรการแก้ไขสำเร็จ!'),
              ],
            ),
            backgroundColor: Colors.teal,
            behavior: SnackBarBehavior.floating,
          ),
        );
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lineState = ref.watch(lineBalancingProvider);
    final processListAsync = ref.watch(workProcessListProvider);
    final processes = processListAsync.valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.troubleshoot_rounded,
                size: 20,
                color: Colors.redAccent,
              ),
            ),
            const SizedBox(width: 12),
            const Text('Problem Solving & RCA (การแก้ปัญหา & วิเคราะห์สาเหตุ)'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'กลับไปที่หน้า Lean & VSM Analysis',
            onPressed: () => context.push('/lean-analysis'),
          ),
          IconButton(
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'ไปที่ Line Balancing',
            onPressed: () => context.push('/line_balancing'),
          ),
          const SizedBox(width: 12),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(
                icon: Icon(Icons.help_outline_rounded),
                text: '5-Why Analysis & AI'),
            Tab(
                icon: Icon(Icons.alt_route_rounded),
                text: 'ผังก้างปลา (Fishbone 4M1E)'),
            Tab(
                icon: Icon(Icons.checklist_rounded),
                text: 'แผนปฏิบัติการ (Action Plan)'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Top Scope & Target Problem Selector Bar
          _buildProblemScopeBar(theme, lineState, processes),

          // Tab Body Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: 5-Why
                _build5WhyTab(theme),

                // Tab 2: Fishbone 4M1E
                _buildFishboneTab(theme),

                // Tab 3: Action Plan
                _buildActionPlanTab(theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProblemScopeBar(
    ThemeData theme,
    LineBalancingState lineState,
    List<WorkProcess> processes,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.gps_fixed, size: 18, color: Colors.redAccent),
          const SizedBox(width: 8),
          const Text(
            'เป้าหมายการแก้ปัญหา:',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(width: 12),

          // Source Type Segmented
          SegmentedButton<int>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            segments: const [
              ButtonSegment(
                  value: 0,
                  label: Text('สถานี Line Balancing',
                      style: TextStyle(fontSize: 11.5))),
              ButtonSegment(
                  value: 1,
                  label:
                      Text('ขั้นตอนงาน SOP', style: TextStyle(fontSize: 11.5))),
              ButtonSegment(
                  value: 2,
                  label: Text('ปัญหากำหนดเอง',
                      style: TextStyle(fontSize: 11.5))),
            ],
            selected: {_sourceMode},
            onSelectionChanged: (val) {
              setState(() => _sourceMode = val.first);
            },
          ),
          const SizedBox(width: 16),

          // Target Item Dropdown
          if (_sourceMode == 0 && lineState.stations.isNotEmpty) ...[
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  isDense: true,
                  value: _selectedStation?.id ?? lineState.stations.first.id,
                  items: lineState.stations.map((s) {
                    return DropdownMenuItem(
                      value: s.id,
                      child: Text(
                        '⚙️ [${s.name}] Cycle: ${s.cycleTime.toStringAsFixed(1)}s (${s.machineName ?? "ไม่ระบุ"})',
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (id) {
                    final found = lineState.stations
                        .firstWhereOrNull((s) => s.id == id);
                    if (found != null) _populateFromStation(found);
                  },
                ),
              ),
            ),
          ] else if (_sourceMode == 1 && processes.isNotEmpty) ...[
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  isDense: true,
                  hint: const Text('เลือกขั้นตอนงานที่มีปัญหา',
                      style: TextStyle(fontSize: 12)),
                  value: _selectedStep?.stepId,
                  items: processes.expand((p) => p.steps).map((st) {
                    return DropdownMenuItem(
                      value: st.stepId,
                      child: Text(
                        '#${st.stepNo} ${st.description} [${st.valueType.label}]',
                        style: TextStyle(
                          fontSize: 12,
                          color: st.valueType == LeanValueType.nva
                              ? Colors.redAccent
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (id) {
                    final found = processes
                        .expand((p) => p.steps)
                        .firstWhereOrNull((st) => st.stepId == id);
                    if (found != null) _populateFromStep(found);
                  },
                ),
              ),
            ),
          ] else ...[
            Expanded(
              child: TextField(
                controller: _problemTitleCtrl,
                decoration: const InputDecoration(
                  hintText: 'ระบุหัวข้อปัญหาที่พบหน้างาน...',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 1. Tab 5-Why
  Widget _build5WhyTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // Problem Header Card
        Card(
          elevation: 0,
          color: Colors.red.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.red.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.report_problem_rounded,
                    color: Colors.redAccent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'หัวข้อปัญหาที่กำลังวิเคราะห์ (Problem Statement):',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.redAccent,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      TextField(
                        controller: _problemTitleCtrl,
                        decoration: const InputDecoration(
                          hintText: 'กรอกปัญหาที่ต้องการวิเคราะห์...',
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.purple.withValues(alpha: 0.15),
                    foregroundColor: Colors.purple,
                  ),
                  onPressed: _isGeneratingAi ? null : _generateAiRca,
                  icon: _isGeneratingAi
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 16),
                  label: Text(_isGeneratingAi
                      ? 'กำลังวิเคราะห์...'
                      : 'AI ช่วยวิเคราะห์ 5-Why'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // 5-Why Ladder List
        _buildWhyRow(1, _why1Ctrl, 'ทำไมที่ 1 (ระดับอาการที่มองเห็น)',
            Colors.amber.shade700),
        _buildWhyRow(2, _why2Ctrl, 'ทำไมที่ 2 (ทำไมถึงเกิดอาการดังกล่าว)',
            Colors.orange.shade700),
        _buildWhyRow(3, _why3Ctrl, 'ทำไมที่ 3 (เจาะลึกระบบ/การทำงาน)',
            Colors.deepOrange.shade700),
        _buildWhyRow(4, _why4Ctrl, 'ทำไมที่ 4 (ทำไมมาตรฐานถึงไม่รองรับ)',
            Colors.red.shade600),
        _buildWhyRow(5, _why5Ctrl, 'ทำไมที่ 5 (สาเหตุรากเหง้า - Root Cause)',
            Colors.red.shade900),

        const SizedBox(height: AppSpacing.lg),

        // Summary Root Cause & Countermeasures
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '💡 สรุปสาเหตุรากเหง้า & มาตรการแก้ไข (Root Cause & Countermeasures)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _rootCauseCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'สาเหตุรากเหง้าแท้จริง (Root Cause)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _correctiveCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText:
                              'มาตรการแก้ไขเร่งด่วน (Corrective Action)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextField(
                        controller: _preventiveCtrl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText:
                              'มาตรการป้องกันเกิดซ้ำ / Kaizen (Preventive Action)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveProblemResolution,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_rounded, size: 18),
                    label: const Text('บันทึกผลการวิเคราะห์ RCA'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWhyRow(
      int step, TextEditingController ctrl, String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Text(
                '$step',
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: color, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: label,
                isDense: true,
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Theme.of(context).cardColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 2. Tab Fishbone 4M1E
  Widget _buildFishboneTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '🐟 แผนผังก้างปลา (Ishikawa / Fishbone Diagram 4M1E)',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                      onPressed: _isGeneratingAi ? null : _generateAiRca,
                      icon: const Icon(Icons.auto_awesome, size: 15),
                      label: const Text('AI วิเคราะห์ 4M1E'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _buildFishboneCategoryRow(
                    '👨 คน (Man / Operator)', _fishboneManCtrl, Colors.blue),
                _buildFishboneCategoryRow('⚙️ เครื่องจักร (Machine)',
                    _fishboneMachineCtrl, Colors.orange),
                _buildFishboneCategoryRow('📦 วัตถุดิบ (Material)',
                    _fishboneMaterialCtrl, Colors.teal),
                _buildFishboneCategoryRow('📋 วิธีการทำงาน (Method)',
                    _fishboneMethodCtrl, Colors.purple),
                _buildFishboneCategoryRow('🌡️ สภาพแวดล้อม (Environment)',
                    _fishboneEnvCtrl, Colors.green),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveProblemResolution,
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text('บันทึกข้อมูลผังก้างปลา'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFishboneCategoryRow(
      String title, TextEditingController ctrl, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: color, fontSize: 13)),
          const SizedBox(height: 4),
          TextField(
            controller: ctrl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'ระบุปัจจัยและสาเหตุที่เป็นไปได้ในหมวดนี้...',
              isDense: true,
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: color.withValues(alpha: 0.04),
            ),
          ),
        ],
      ),
    );
  }

  // 3. Tab Action Plan
  Widget _buildActionPlanTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Card(
          elevation: 2,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📋 แผนปฏิบัติการปรับปรุงแก้ไข (Action Plan & Kaizen Tracker)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _correctiveCtrl,
                  decoration: const InputDecoration(
                    labelText: 'งานที่ต้องดำเนินการ (Action Item)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _actionOwnerCtrl,
                        decoration: const InputDecoration(
                          labelText: 'ผู้รับผิดชอบ (Assignee)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextField(
                        controller: _actionDueDateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'กำหนดเสร็จ (Due Date)',
                          border: OutlineInputBorder(),
                          hintText: 'เช่น 25 ส.ค. 2026',
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _actionStatus,
                        decoration: const InputDecoration(
                          labelText: 'สถานะ (Status)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'pending',
                              child: Text('⏳ รอดำเนินการ (Pending)')),
                          DropdownMenuItem(
                              value: 'in_progress',
                              child: Text('🔄 กำลังดำเนินการ (In Progress)')),
                          DropdownMenuItem(
                              value: 'completed',
                              child: Text('✅ เสร็จสมบูรณ์ (Completed)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _actionStatus = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _saveProblemResolution,
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('บันทึกแผนปฏิบัติการ'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
