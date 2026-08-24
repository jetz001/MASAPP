import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';
import '../../../core/ai/ai_service.dart';
import '../../../core/ai/vector_db_service.dart';
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
  final String? initialWoId;

  const ProblemSolvingScreen({
    super.key,
    this.initialProcessId,
    this.initialStepId,
    this.initialProblemTitle,
    this.initialWoId,
  });

  @override
  ConsumerState<ProblemSolvingScreen> createState() =>
      _ProblemSolvingScreenState();
}

class _ProblemSolvingScreenState extends ConsumerState<ProblemSolvingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _sourceMode = 0; // 0: Line Balancing, 1: Machine SOPs, 2: Maintenance / WO, 3: Custom Problem

  WorkProcessStep? _selectedStep;
  WorkstationData? _selectedStation;
  Map<String, dynamic>? _selectedWo;
  List<Map<String, dynamic>> _workOrders = [];
  bool _isLoadingWo = false;

  bool _isGeneratingAi = false;
  bool _isSaving = false;

  // Problem & 5-Why Controllers
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (widget.initialProblemTitle != null) {
      _problemTitleCtrl.text = widget.initialProblemTitle!;
      _sourceMode = 3;
    }

    _loadWorkOrders();
  }

  Future<void> _loadWorkOrders() async {
    setState(() => _isLoadingWo = true);
    try {
      final rows = await DbHelper.query('''
        SELECT wo_id, wo_no, title, description, failure_symptom, machine_id, priority, status, created_at
        FROM work_orders
        ORDER BY created_at DESC
        LIMIT 60
      ''');
      setState(() {
        _workOrders = rows;
        if (widget.initialWoId != null) {
          final match = rows.firstWhereOrNull((r) => r['wo_id'] == widget.initialWoId);
          if (match != null) {
            _sourceMode = 2;
            _populateFromWorkOrder(match);
          }
        }
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingWo = false);
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
    super.dispose();
  }

  void _populateFromStep(WorkProcessStep step) {
    setState(() {
      _selectedStep = step;
      _selectedStation = null;
      _selectedWo = null;
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
      _selectedStep = null;
      _selectedWo = null;
      _problemTitleCtrl.text =
          'ปัญหาคอขวดประจำสถานี: ${station.name} (${station.cycleTime.toStringAsFixed(1)}s)';
      _why1Ctrl.text = 'เวลารอบการทำงาน (Cycle Time) สูงเกิน Takt Time';
      _rootCauseCtrl.text = 'เครื่องจักรทำงานช้า หรือขั้นตอนการทำงานไม่สมดุล';
    });
  }

  Future<void> _populateFromWorkOrder(Map<String, dynamic> wo) async {
    setState(() {
      _selectedWo = wo;
      _selectedStep = null;
      _selectedStation = null;
      final woNo = wo['wo_no'] ?? '';
      final title = wo['title'] ?? wo['description'] ?? 'งานซ่อมบำรุง';
      final symptom = wo['failure_symptom'] != null && wo['failure_symptom'].toString().isNotEmpty
          ? ' (อาการ: ${wo['failure_symptom']})'
          : '';
      _problemTitleCtrl.text = '[$woNo] $title$symptom';
    });

    try {
      final rca = await DbHelper.queryOne(
        'SELECT * FROM work_order_rca WHERE wo_id = @id',
        params: {'id': wo['wo_id']},
      );
      if (rca != null) {
        setState(() {
          if (rca['why_1'] != null) _why1Ctrl.text = rca['why_1'].toString();
          if (rca['why_2'] != null) _why2Ctrl.text = rca['why_2'].toString();
          if (rca['why_3'] != null) _why3Ctrl.text = rca['why_3'].toString();
          if (rca['why_4'] != null) _why4Ctrl.text = rca['why_4'].toString();
          if (rca['why_5'] != null) _why5Ctrl.text = rca['why_5'].toString();
          if (rca['root_cause'] != null) _rootCauseCtrl.text = rca['root_cause'].toString();
          if (rca['correction_action'] != null) {
            _correctiveCtrl.text = rca['correction_action'].toString();
          }
          if (rca['preventive_action'] != null) {
            _preventiveCtrl.text = rca['preventive_action'].toString();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _generateAiRca() async {
    final problemDesc = _problemTitleCtrl.text.trim().isNotEmpty
        ? _problemTitleCtrl.text.trim()
        : (_selectedStep?.description ??
            _selectedStation?.name ??
            _selectedWo?['title'] ??
            'ปัญหาในโรงงาน');

    setState(() => _isGeneratingAi = true);

    try {
      final isMaintenance = _sourceMode == 2 || _selectedWo != null;
      final prompt = '''
คุณคือผู้เชี่ยวชาญด้าน ${isMaintenance ? "วิศวกรรมซ่อมบำรุงและ Reliability Centered Maintenance (RCM / TPM)" : "Lean Manufacturing, 5-Why Problem Solving และการวิเคราะห์สาเหตุรากเหง้า (RCA)"}
ช่วยวิเคราะห์ปัญหาต่อไปนี้อย่างละเอียดและเป็นมืออาชีพ:
"หัวข้อปัญหา: $problemDesc"
${_selectedStep != null ? "บริบทขั้นตอน: ${_selectedStep!.description}, ประเภทคุณค่า: ${_selectedStep!.valueType.label}" : ""}
${_selectedStation != null ? "บริบทสถานีงาน: ${_selectedStation!.name}, เครื่องจักร: ${_selectedStation!.machineName ?? '-'}, Cycle Time: ${_selectedStation!.cycleTime}s" : ""}
${_selectedWo != null ? "ใบแจ้งซ่อม: ${_selectedWo!['wo_no']}, อาการเสีย: ${_selectedWo!['failure_symptom'] ?? '-'}, ความเร่งด่วน: ${_selectedWo!['priority']}" : ""}

กรุณาวิเคราะห์ 5-Why, สรุป Root Cause, มาตรการแก้ไขชั่วคราว, มาตรการป้องกันเกิดซ้ำ และแจกแจงปัจจัย 4M1E
ส่งคำตอบกลับมาเป็น JSON ตามโครงสร้างนี้เท่านั้น:
{
  "why1": "ทำไมที่ 1...",
  "why2": "ทำไมที่ 2...",
  "why3": "ทำไมที่ 3...",
  "why4": "ทำไมที่ 4...",
  "why5": "ทำไมที่ 5 (สาเหตุรากเหง้า)...",
  "rootCause": "สรุปสาเหตุที่แท้จริง...",
  "correctiveAction": "มาตรการแก้ไขชั่วคราว/เร่งด่วน...",
  "preventiveAction": "มาตรการป้องกันการเกิดซ้ำ (Kaizen/Poka-Yoke/PM Standard)...",
  "fishbone": {
    "man": "สาเหตุด้านคน/ช่าง...",
    "machine": "สาเหตุด้านเครื่องจักร/ชิ้นส่วนสึกหรอ...",
    "material": "สาเหตุด้านวัตถุดิบ/สารหล่อลื่น/อะไหล่...",
    "method": "สาเหตุด้านวิธีการทำงาน/คู่มือ PM...",
    "environment": "สาเหตุด้านสภาพแวดล้อม/ความร้อน/ฝุ่น..."
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
        final Map<String, dynamic> data = jsonDecode(rawJson);

        setState(() {
          _why1Ctrl.text = data['why1'] ?? '';
          _why2Ctrl.text = data['why2'] ?? '';
          _why3Ctrl.text = data['why3'] ?? '';
          _why4Ctrl.text = data['why4'] ?? '';
          _why5Ctrl.text = data['why5'] ?? '';
          _rootCauseCtrl.text = data['rootCause'] ?? '';
          _correctiveCtrl.text = data['correctiveAction'] ?? '';
          _preventiveCtrl.text = data['preventiveAction'] ?? '';

          final fish = data['fishbone'] as Map<String, dynamic>?;
          if (fish != null) {
            _fishboneManCtrl.text = fish['man'] ?? '';
            _fishboneMachineCtrl.text = fish['machine'] ?? '';
            _fishboneMaterialCtrl.text = fish['material'] ?? '';
            _fishboneMethodCtrl.text = fish['method'] ?? '';
            _fishboneEnvCtrl.text = fish['environment'] ?? '';
          }
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

  Future<void> _saveAndNavigateToActionPlan(String method) async {
    final problemDesc = _problemTitleCtrl.text.trim();
    if (problemDesc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาระบุหัวข้อปัญหาก่อนวางแผนดำเนินการ')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final rootCause = _rootCauseCtrl.text.isNotEmpty ? _rootCauseCtrl.text : _why1Ctrl.text;
      final preventive = _preventiveCtrl.text.isNotEmpty ? _preventiveCtrl.text : _correctiveCtrl.text;

      final rcaId = _selectedWo != null
          ? 'rca_wo_${_selectedWo!['wo_id']}'
          : (_selectedStep != null
              ? 'rca_step_${_selectedStep!.stepId}'
              : (_selectedStation != null ? 'rca_st_${_selectedStation!.id}' : 'rca_${const Uuid().v4().substring(0, 8)}'));

      String sourceType = 'custom';
      String? sourceId;
      if (_sourceMode == 0 && _selectedStation != null) {
        sourceType = 'line_balancing';
        sourceId = _selectedStation!.id;
      } else if (_sourceMode == 1 && _selectedStep != null) {
        sourceType = 'sop_step';
        sourceId = _selectedStep!.stepId;
      } else if (_sourceMode == 2 && _selectedWo != null) {
        sourceType = 'work_order';
        sourceId = _selectedWo!['wo_id']?.toString();
      }

      // 1. Save to problem_solving_records
      await DbHelper.execute('''
        INSERT OR REPLACE INTO problem_solving_records (
          rca_id, source_type, source_id, problem_title,
          why_1, why_2, why_3, why_4, why_5, root_cause,
          fishbone_man, fishbone_machine, fishbone_material, fishbone_method, fishbone_env,
          status, rca_method, updated_at
        ) VALUES (
          @id, @stype, @sid, @title,
          @w1, @w2, @w3, @w4, @w5, @rc,
          @fman, @fmach, @fmat, @fmet, @fenv,
          'in_progress', @rmethod, CURRENT_TIMESTAMP
        )
      ''', params: {
        'id': rcaId,
        'stype': sourceType,
        'sid': sourceId,
        'title': problemDesc,
        'w1': _why1Ctrl.text.trim(),
        'w2': _why2Ctrl.text.trim(),
        'w3': _why3Ctrl.text.trim(),
        'w4': _why4Ctrl.text.trim(),
        'w5': _why5Ctrl.text.trim(),
        'rc': rootCause,
        'fman': _fishboneManCtrl.text.trim(),
        'fmach': _fishboneMachineCtrl.text.trim(),
        'fmat': _fishboneMaterialCtrl.text.trim(),
        'fmet': _fishboneMethodCtrl.text.trim(),
        'fenv': _fishboneEnvCtrl.text.trim(),
        'rmethod': method,
      });

      // 2. If Work Order, also update work_order_rca
      if (_selectedWo != null) {
        final woId = _selectedWo!['wo_id'];
        await DbHelper.execute('''
          INSERT OR REPLACE INTO work_order_rca (
            rca_id, wo_id, why_1, why_2, why_3, why_4, why_5,
            root_cause, correction_action, preventive_action,
            failure_type, cause_category, updated_at
          ) VALUES (
            @rca_id, @wo_id, @w1, @w2, @w3, @w4, @w5,
            @rc, @corr, @prev,
            'breakdown', 'maintenance_rca', CURRENT_TIMESTAMP
          )
        ''', params: {
          'rca_id': rcaId,
          'wo_id': woId,
          'w1': _why1Ctrl.text.trim(),
          'w2': _why2Ctrl.text.trim(),
          'w3': _why3Ctrl.text.trim(),
          'w4': _why4Ctrl.text.trim(),
          'w5': _why5Ctrl.text.trim(),
          'rc': rootCause,
          'corr': _correctiveCtrl.text.trim(),
          'prev': preventive,
        });
      }

      // 3. If SOP Step, also update work_process_steps
      if (_selectedStep != null) {
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

      // 4. Sync to Vector DB
      VectorDbService.syncProblemSolvingAndActionPlan(rcaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('บันทึกผลวิเคราะห์ด้วย ${method == "5why" ? "5-Why" : "ผังก้างปลา"} สำเร็จ! กำลังนำไปยัง Action Plan...'),
            backgroundColor: Colors.teal,
          ),
        );

        // Jump to Action Plan creation screen with prefilled data
        context.push('/action-plans/new', extra: {
          'rca_id': rcaId,
          'problem_title': problemDesc,
          'source_type': sourceType,
          'source_id': sourceId,
          'root_cause': rootCause,
          'rca_method': method,
          'why_1': _why1Ctrl.text.trim(),
          'why_2': _why2Ctrl.text.trim(),
          'why_3': _why3Ctrl.text.trim(),
          'why_4': _why4Ctrl.text.trim(),
          'why_5': _why5Ctrl.text.trim(),
          'fishbone_man': _fishboneManCtrl.text.trim(),
          'fishbone_machine': _fishboneMachineCtrl.text.trim(),
          'fishbone_material': _fishboneMaterialCtrl.text.trim(),
          'fishbone_method': _fishboneMethodCtrl.text.trim(),
          'fishbone_env': _fishboneEnvCtrl.text.trim(),
        });
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
            icon: const Icon(Icons.checklist_rounded),
            tooltip: 'ไปที่ ทะเบียนแผนปฏิบัติการ (Action Plan)',
            onPressed: () => context.push('/action-plans'),
          ),
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
            Tab(icon: Icon(Icons.help_outline_rounded), text: '5-Why Analysis & AI'),
            Tab(icon: Icon(Icons.alt_route_rounded), text: 'ผังก้างปลา (Fishbone 4M1E)'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildProblemScopeBar(theme, lineState, processes),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _build5WhyTab(theme),
                _buildFishboneTab(theme),
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gps_fixed, size: 16, color: Colors.redAccent),
              const SizedBox(width: 6),
              const Text(
                'เป้าหมายการแก้ปัญหา:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(width: 12),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                segments: const [
                  ButtonSegment(value: 0, label: Text('สถานี Line Balancing', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: 1, label: Text('ขั้นตอนงาน SOP', style: TextStyle(fontSize: 11))),
                  ButtonSegment(value: 2, label: Text('🔧 งานซ่อมบำรุง (WO)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                  ButtonSegment(value: 3, label: Text('ปัญหากำหนดเอง', style: TextStyle(fontSize: 11))),
                ],
                selected: {_sourceMode},
                onSelectionChanged: (val) {
                  setState(() {
                    _sourceMode = val.first;
                    if (_sourceMode == 3) {
                      _selectedStep = null;
                      _selectedStation = null;
                      _selectedWo = null;
                    }
                  });
                },
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildScopeSelector(lineState, processes),
              ),
            ],
          ),
          if (_sourceMode == 3) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _problemTitleCtrl,
              decoration: const InputDecoration(
                labelText: 'ระบุหัวข้อปัญหาที่ต้องการวิเคราะห์ (Problem Statement)',
                hintText: 'เช่น ปั๊มลมแรงดันตกบ่อย, มีรอยแตกชิ้นงาน, เวลาเซ็ตอัพนานเกินกำหนด...',
                isDense: true,
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.edit_note_rounded),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScopeSelector(
    LineBalancingState lineState,
    List<WorkProcess> processes,
  ) {
    if (_sourceMode == 0) {
      final stations = lineState.stations;
      final maxCt = stations.isNotEmpty
          ? stations.map((s) => s.cycleTime).reduce((a, b) => a > b ? a : b)
          : 0.0;
      return DropdownButtonFormField<WorkstationData>(
        isExpanded: true,
        value: _selectedStation,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(),
          hintText: 'เลือกสถานีงานในสายการผลิต...',
        ),
        items: stations.map((st) {
          final isBottleneck = maxCt > 0 && st.cycleTime == maxCt;
          return DropdownMenuItem(
            value: st,
            child: Text(
              '${st.name} (CT: ${st.cycleTime}s) ${isBottleneck ? "🔥 BOTTLENECK" : ""}',
              style: TextStyle(
                fontSize: 12,
                color: isBottleneck ? Colors.red : null,
                fontWeight: isBottleneck ? FontWeight.bold : null,
              ),
            ),
          );
        }).toList(),
        onChanged: (val) {
          if (val != null) _populateFromStation(val);
        },
      );
    } else if (_sourceMode == 1) {
      final allSteps = processes.expand((p) => p.steps).toList();
      return DropdownButtonFormField<WorkProcessStep>(
        isExpanded: true,
        value: _selectedStep,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(),
          hintText: 'เลือกขั้นตอนการทำงานจาก SOP...',
        ),
        items: allSteps.map((st) {
          return DropdownMenuItem(
            value: st,
            child: Text(
              '#${st.stepNo} ${st.description} (${st.valueType.label})',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (val) {
          if (val != null) _populateFromStep(val);
        },
      );
    } else if (_sourceMode == 2) {
      if (_isLoadingWo) {
        return const SizedBox(height: 32, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
      }
      return DropdownButtonFormField<Map<String, dynamic>>(
        isExpanded: true,
        value: _selectedWo,
        decoration: const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          border: OutlineInputBorder(),
          hintText: 'เลือกใบแจ้งซ่อม (Work Order)...',
        ),
        items: _workOrders.map((wo) {
          final no = wo['wo_no'] ?? '';
          final title = wo['title'] ?? wo['description'] ?? 'งานซ่อม';
          final prio = wo['priority'] == 'urgent' ? '🔴 ด่วนที่สุด' : (wo['priority'] == 'high' ? '🟠 ด่วน' : '🟢 ปกติ');
          return DropdownMenuItem(
            value: wo,
            child: Text(
              '[$no] $title - $prio',
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (val) {
          if (val != null) _populateFromWorkOrder(val);
        },
      );
    }
    return const SizedBox();
  }

  // 1. Tab 5-Why Analysis & AI
  Widget _build5WhyTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.help_outline_rounded, color: Colors.redAccent, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'การเจาะลึก 5-Why Analysis & AI Co-pilot',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _isGeneratingAi ? null : _generateAiRca,
                      icon: _isGeneratingAi
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome, size: 18),
                      label: Text(_isGeneratingAi ? 'กำลังวิเคราะห์...' : 'AI ช่วยวิเคราะห์ 5-Why & 4M1E'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildWhyRow(1, _why1Ctrl, 'ทำไมที่ 1 (ปรากฏการณ์หน้างานที่เกิดขึ้น)', Colors.blue),
                _buildWhyRow(2, _why2Ctrl, 'ทำไมที่ 2 (ทำไมถึงเกิดเหตุการณ์ที่ 1)', Colors.indigo),
                _buildWhyRow(3, _why3Ctrl, 'ทำไมที่ 3 (เจาะลึกต่อเนื่อง)', Colors.teal),
                _buildWhyRow(4, _why4Ctrl, 'ทำไมที่ 4 (ใกล้ถึงสาเหตุหลัก)', Colors.orange),
                _buildWhyRow(5, _why5Ctrl, 'ทำไมที่ 5 (สาเหตุรากเหง้าที่แท้จริง - Root Cause)', Colors.red),
                const Divider(height: 32),
                TextField(
                  controller: _rootCauseCtrl,
                  decoration: const InputDecoration(
                    labelText: 'สรุปสาเหตุรากเหง้าที่แท้จริง (Root Cause Statement)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.crisis_alert_rounded, color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _correctiveCtrl,
                  decoration: const InputDecoration(
                    labelText: 'มาตรการแก้ไขชั่วคราว / เร่งด่วน (Corrective Action)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.build_outlined, color: Colors.orange),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _preventiveCtrl,
                  decoration: const InputDecoration(
                    labelText: 'มาตรการป้องกันการเกิดซ้ำ (Preventive Action / Kaizen)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.shield_outlined, color: Colors.green),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: _isSaving ? null : () => _saveAndNavigateToActionPlan('5why'),
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.playlist_add_check_circle_rounded, size: 20),
                    label: const Text('💾 วางแผนดำเนินการด้วย 5-Why (สร้าง Action Plan)', style: TextStyle(fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWhyRow(int step, TextEditingController ctrl, String subtitle, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color,
            child: Text('$step', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: ctrl,
              decoration: InputDecoration(
                labelText: 'Why #$step',
                helperText: subtitle,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 2. Tab ผังก้างปลา (Fishbone 4M1E)
  Widget _buildFishboneTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.alt_route_rounded, color: Colors.deepOrange, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'ผังก้างปลา (Ishikawa Diagram - 4M1E)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _isGeneratingAi ? null : _generateAiRca,
                      icon: const Icon(Icons.auto_awesome, size: 18),
                      label: const Text('AI วิเคราะห์ 4M1E'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _buildFishboneCategoryRow('👨 คน / พนักงาน / ช่าง (Man / Operator)', _fishboneManCtrl, Colors.blue),
                _buildFishboneCategoryRow('⚙️ เครื่องจักร / อุปกรณ์ (Machine)', _fishboneMachineCtrl, Colors.orange),
                _buildFishboneCategoryRow('📦 วัตถุดิบ / อะไหล่ / สารหล่อลื่น (Material)', _fishboneMaterialCtrl, Colors.teal),
                _buildFishboneCategoryRow('📋 วิธีการทำงาน / มาตรฐาน PM (Method)', _fishboneMethodCtrl, Colors.purple),
                _buildFishboneCategoryRow('🌡️ สภาพแวดล้อม / หน้างาน (Environment)', _fishboneEnvCtrl, Colors.green),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: _isSaving ? null : () => _saveAndNavigateToActionPlan('fishbone'),
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.playlist_add_check_circle_rounded, size: 20),
                    label: const Text('💾 วางแผนดำเนินการด้วย ผังก้างปลา (สร้าง Action Plan)', style: TextStyle(fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFishboneCategoryRow(String title, TextEditingController ctrl, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13)),
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
}
