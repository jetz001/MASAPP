import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:collection/collection.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../../../core/ai/ai_service.dart';
import '../../../core/database/db_helper.dart';
import '../../../core/theme/app_spacing.dart';
import '../../work_processes/models/work_process_model.dart';
import '../../work_processes/models/work_process_step_model.dart';
import '../../work_processes/providers/work_process_provider.dart';
import '../../line_balancing/line_balancing_provider.dart';

/// Item in a Multi-step Action Plan
class ActionStepItem {
  String id;
  String title;
  String assignee;
  String dueDate;
  String status; // pending, in_progress, completed
  String? note;

  ActionStepItem({
    required this.id,
    required this.title,
    this.assignee = '',
    this.dueDate = '',
    this.status = 'pending',
    this.note,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'assignee': assignee,
        'due_date': dueDate,
        'status': status,
        'note': note,
      };

  factory ActionStepItem.fromJson(Map<String, dynamic> json) => ActionStepItem(
        id: json['id']?.toString() ?? const Uuid().v4(),
        title: json['title']?.toString() ?? '',
        assignee: json['assignee']?.toString() ?? '',
        dueDate: json['due_date']?.toString() ?? '',
        status: json['status']?.toString() ?? 'pending',
        note: json['note']?.toString(),
      );
}

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
  bool _isGeneratingAiSteps = false;
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

  // Multi-step Action Plan
  final List<ActionStepItem> _actionSteps = [];

  // Verification & Validation / Before-After Tracker
  final _targetMetricCtrl = TextEditingController(text: 'Cycle Time / เวลาการทำงาน');
  final _unitCtrl = TextEditingController(text: 'วินาที');
  final _beforeValCtrl = TextEditingController();
  final _targetValCtrl = TextEditingController();
  final _actualValCtrl = TextEditingController();
  final _verifiedByCtrl = TextEditingController();
  final _verificationDateCtrl = TextEditingController();
  String _verificationResult = 'achieved'; // achieved, partial, pending, failed
  final _standardizationNotesCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    _verificationDateCtrl.text = DateFormat('dd/MM/yyyy').format(DateTime.now());

    if (widget.initialProblemTitle != null) {
      _problemTitleCtrl.text = widget.initialProblemTitle!;
      _sourceMode = 3;
    }

    _loadWorkOrders();
    _initActionSteps();
  }

  void _initActionSteps() {
    if (_actionSteps.isEmpty) {
      _actionSteps.add(
        ActionStepItem(
          id: const Uuid().v4(),
          title: 'วิเคราะห์และดำเนินการแก้ไขปัญหาหน้างานเร่งด่วน',
          status: 'pending',
        ),
      );
    }
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
    _targetMetricCtrl.dispose();
    _unitCtrl.dispose();
    _beforeValCtrl.dispose();
    _targetValCtrl.dispose();
    _actualValCtrl.dispose();
    _verifiedByCtrl.dispose();
    _verificationDateCtrl.dispose();
    _standardizationNotesCtrl.dispose();
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

      _targetMetricCtrl.text = 'ระยะเวลาขั้นตอนการทำงาน (Duration)';
      _unitCtrl.text = 'นาที';
      _beforeValCtrl.text = step.durationMinutes.toStringAsFixed(1);
      _targetValCtrl.text = (step.durationMinutes * 0.7).toStringAsFixed(1);
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

      _targetMetricCtrl.text = 'เวลารอบการผลิต (Cycle Time)';
      _unitCtrl.text = 'วินาที';
      _beforeValCtrl.text = station.cycleTime.toStringAsFixed(1);
      _targetValCtrl.text = (station.cycleTime * 0.75).toStringAsFixed(1);
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

      _targetMetricCtrl.text = 'เวลาหยุดเครื่อง (Downtime / MTTR)';
      _unitCtrl.text = 'นาที';
      _beforeValCtrl.text = '60';
      _targetValCtrl.text = '15';
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

  Future<void> _generateAiActionStepsBreakdown() async {
    final problemDesc = _problemTitleCtrl.text.trim();
    final rootCause = _rootCauseCtrl.text.trim().isNotEmpty ? _rootCauseCtrl.text.trim() : _why5Ctrl.text.trim();
    final preventive = _preventiveCtrl.text.trim();

    if (problemDesc.isEmpty && rootCause.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาระบุหัวข้อปัญหาหรือสาเหตุรากเหง้าก่อนให้ AI ช่วยแตกขั้นตอน')),
      );
      return;
    }

    setState(() => _isGeneratingAiSteps = true);

    try {
      final prompt = '''
คุณคือผู้เชี่ยวชาญด้าน Kaizen, Project Management และ Industrial Engineering
จากปัญหาและสาเหตุรากเหง้าต่อไปนี้:
- ปัญหา: $problemDesc
- สาเหตุรากเหง้า: $rootCause
- มาตรการแก้ไข/ป้องกัน: $preventive

กรุณาช่วยแตกแผนปฏิบัติการ (Action Plan) ออกเป็นขั้นตอนการดำเนินงานย่อย 3 - 5 ขั้นตอนแบบเป็นลำดับขั้นตอน (Phase/Milestones) ที่ทีมงานสามารถนำไปปฏิบัติได้จริงในโรงงาน พร้อมกำหนดผู้รับผิดชอบและระยะเวลาที่เหมาะสม
ตอบเป็น JSON Array ในรูปแบบนี้เท่านั้น:
[
  {
    "title": "1. ตรวจสอบและเปลี่ยนอะไหล่/ปรับจูนระบบ...",
    "assignee": "ช่างซ่อมบำรุง / วิศวกร",
    "due_date": "ภายใน 3 วัน",
    "status": "pending"
  },
  {
    "title": "2. จัดทำคู่มือมาตรฐานการทำงาน (SOP/WI) และอบรมพนักงาน...",
    "assignee": "หัวหน้างานฝ่ายผลิต / QA",
    "due_date": "ภายใน 1 สัปดาห์",
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
          SnackBar(content: Text('AI แตกขั้นตอนไม่สำเร็จ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isGeneratingAiSteps = false);
    }
  }

  Future<void> _saveProblemResolution() async {
    setState(() => _isSaving = true);
    try {
      final rootCause = _rootCauseCtrl.text.isNotEmpty ? _rootCauseCtrl.text : _why1Ctrl.text;
      final preventive = _preventiveCtrl.text.isNotEmpty ? _preventiveCtrl.text : _correctiveCtrl.text;
      final stepsJson = jsonEncode(_actionSteps.map((s) => s.toJson()).toList());

      await DbHelper.execute('''
        CREATE TABLE IF NOT EXISTS problem_solving_records (
          rca_id TEXT PRIMARY KEY,
          source_type TEXT NOT NULL,
          source_id TEXT,
          problem_title TEXT NOT NULL,
          why_1 TEXT,
          why_2 TEXT,
          why_3 TEXT,
          why_4 TEXT,
          why_5 TEXT,
          root_cause TEXT,
          fishbone_man TEXT,
          fishbone_machine TEXT,
          fishbone_material TEXT,
          fishbone_method TEXT,
          fishbone_env TEXT,
          action_steps_json TEXT,
          target_metric TEXT,
          before_value REAL,
          target_value REAL,
          actual_value REAL,
          metric_unit TEXT,
          verified_by TEXT,
          verification_date TEXT,
          verification_result TEXT,
          standardization_notes TEXT,
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      final rcaId = _selectedWo != null
          ? 'rca_wo_${_selectedWo!['wo_id']}'
          : (_selectedStep != null
              ? 'rca_step_${_selectedStep!.stepId}'
              : (_selectedStation != null ? 'rca_st_${_selectedStation!.id}' : 'rca_${const Uuid().v4().substring(0, 8)}'));

      await DbHelper.execute('''
        INSERT OR REPLACE INTO problem_solving_records (
          rca_id, source_type, source_id, problem_title,
          why_1, why_2, why_3, why_4, why_5, root_cause,
          fishbone_man, fishbone_machine, fishbone_material, fishbone_method, fishbone_env,
          action_steps_json, target_metric, before_value, target_value, actual_value, metric_unit,
          verified_by, verification_date, verification_result, standardization_notes, updated_at
        ) VALUES (
          @id, @stype, @sid, @title,
          @w1, @w2, @w3, @w4, @w5, @rc,
          @fman, @fmach, @fmat, @fmet, @fenv,
          @sjson, @tmetric, @bval, @tval, @aval, @munit,
          @vby, @vdate, @vres, @snotes, CURRENT_TIMESTAMP
        )
      ''', params: {
        'id': rcaId,
        'stype': _sourceMode == 0
            ? 'line_balancing'
            : (_sourceMode == 1 ? 'sop_step' : (_sourceMode == 2 ? 'work_order' : 'custom')),
        'sid': _selectedStation?.id ?? _selectedStep?.stepId ?? _selectedWo?['wo_id'],
        'title': _problemTitleCtrl.text.trim(),
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
        'sjson': stepsJson,
        'tmetric': _targetMetricCtrl.text.trim(),
        'bval': double.tryParse(_beforeValCtrl.text.trim()),
        'tval': double.tryParse(_targetValCtrl.text.trim()),
        'aval': double.tryParse(_actualValCtrl.text.trim()),
        'munit': _unitCtrl.text.trim(),
        'vby': _verifiedByCtrl.text.trim(),
        'vdate': _verificationDateCtrl.text.trim(),
        'vres': _verificationResult,
        'snotes': _standardizationNotesCtrl.text.trim(),
      });

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

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('บันทึกผลการวิเคราะห์ RCA, แผนปฏิบัติการ และผลการตรวจสอบสำเร็จ!'),
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
            Tab(icon: Icon(Icons.help_outline_rounded), text: '5-Why Analysis & AI'),
            Tab(icon: Icon(Icons.alt_route_rounded), text: 'ผังก้างปลา (Fishbone 4M1E)'),
            Tab(icon: Icon(Icons.checklist_rounded), text: 'แผนปฏิบัติการ & สอบทานผล (Action Plan)'),
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
                _buildActionPlanAndVerificationTab(theme),
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
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
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

          SegmentedButton<int>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            segments: const [
              ButtonSegment(
                value: 0,
                label: Text('สถานี Line Balancing', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: 1,
                label: Text('ขั้นตอนงาน SOP', style: TextStyle(fontSize: 11)),
              ),
              ButtonSegment(
                value: 2,
                label: Text('🔧 งานซ่อมบำรุง (WO)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              ButtonSegment(
                value: 3,
                label: Text('ปัญหากำหนดเอง', style: TextStyle(fontSize: 11)),
              ),
            ],
            selected: {_sourceMode},
            onSelectionChanged: (val) {
              setState(() => _sourceMode = val.first);
            },
          ),
          const SizedBox(width: 16),

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
                    final found = lineState.stations.firstWhereOrNull((s) => s.id == id);
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
                  hint: const Text('เลือกขั้นตอนงานที่มีปัญหา', style: TextStyle(fontSize: 12)),
                  value: _selectedStep?.stepId,
                  items: processes.expand((p) => p.steps).map((st) {
                    return DropdownMenuItem(
                      value: st.stepId,
                      child: Text(
                        '#${st.stepNo} ${st.description} [${st.valueType.label}]',
                        style: TextStyle(
                          fontSize: 12,
                          color: st.valueType == LeanValueType.nva ? Colors.redAccent : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (id) {
                    final found = processes.expand((p) => p.steps).firstWhereOrNull((st) => st.stepId == id);
                    if (found != null) _populateFromStep(found);
                  },
                ),
              ),
            ),
          ] else if (_sourceMode == 2) ...[
            Expanded(
              child: _isLoadingWo
                  ? const Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                  : DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        isDense: true,
                        hint: const Text('เลือกใบแจ้งซ่อม / ปัญหาเครื่องจักรชำรุด', style: TextStyle(fontSize: 12)),
                        value: _selectedWo?['wo_id'] ?? (_workOrders.isNotEmpty ? _workOrders.first['wo_id'] : null),
                        items: _workOrders.map((wo) {
                          final woNo = wo['wo_no'] ?? 'WO';
                          final title = wo['title'] ?? wo['description'] ?? 'งานซ่อม';
                          final priority = wo['priority'] ?? 'normal';
                          return DropdownMenuItem(
                            value: wo['wo_id'] as String,
                            child: Text(
                              '🔧 [$woNo] $title (ความเร่งด่วน: $priority)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: priority == 'urgent' || priority == 'emergency' ? FontWeight.bold : FontWeight.normal,
                                color: priority == 'urgent' || priority == 'emergency' ? Colors.red : null,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (woId) {
                          final found = _workOrders.firstWhereOrNull((w) => w['wo_id'] == woId);
                          if (found != null) _populateFromWorkOrder(found);
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
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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

  Widget _build5WhyTab(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
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
                const Icon(Icons.report_problem_rounded, color: Colors.redAccent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'หัวข้อปัญหาที่กำลังวิเคราะห์ (Problem Statement):',
                        style: TextStyle(fontSize: 11.5, color: Colors.redAccent, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      TextField(
                        controller: _problemTitleCtrl,
                        decoration: const InputDecoration(
                          hintText: 'กรอกปัญหาที่ต้องการวิเคราะห์...',
                          isDense: true,
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
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
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, size: 16),
                  label: Text(_isGeneratingAi ? 'กำลังวิเคราะห์...' : 'AI ช่วยวิเคราะห์ 5-Why'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        _buildWhyRow(1, _why1Ctrl, 'ทำไมที่ 1 (ระดับอาการที่มองเห็น)', Colors.amber.shade700),
        _buildWhyRow(2, _why2Ctrl, 'ทำไมที่ 2 (ทำไมถึงเกิดอาการดังกล่าว)', Colors.orange.shade700),
        _buildWhyRow(3, _why3Ctrl, 'ทำไมที่ 3 (เจาะลึกระบบ/การทำงาน/ชิ้นส่วน)', Colors.deepOrange.shade700),
        _buildWhyRow(4, _why4Ctrl, 'ทำไมที่ 4 (ทำไมมาตรฐาน/การบำรุงรักษาถึงไม่รองรับ)', Colors.red.shade600),
        _buildWhyRow(5, _why5Ctrl, 'ทำไมที่ 5 (สาเหตุรากเหง้า - Root Cause)', Colors.red.shade900),

        const SizedBox(height: AppSpacing.lg),

        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🎯 สรุปสาเหตุรากเหง้า & มาตรการแก้ไขเบื้องต้น',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _rootCauseCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'สาเหตุที่แท้จริง (Root Cause)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.crisis_alert_rounded, color: Colors.redAccent),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _correctiveCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'มาตรการแก้ไขเร่งด่วน (Corrective Action)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.flash_on_rounded, color: Colors.orange),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _preventiveCtrl,
                  maxLines: 2,
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
                    onPressed: _isSaving ? null : _saveProblemResolution,
                    icon: _isSaving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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

  Widget _buildWhyRow(int step, TextEditingController ctrl, String subtitle, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Center(
              child: Text(
                'W$step',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subtitle,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    hintText: 'ทำไมที่ $step...',
                    isDense: true,
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: color.withValues(alpha: 0.03),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

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
                    const Text(
                      '🐟 แผนผังก้างปลา (Ishikawa / Fishbone Diagram 4M1E)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: _isGeneratingAi ? null : _generateAiRca,
                      icon: const Icon(Icons.auto_awesome, size: 15),
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

  // 3. Tab Action Plan & Post-Improvement Verification Tracker
  Widget _buildActionPlanAndVerificationTab(ThemeData theme) {
    final completedCount = _actionSteps.where((s) => s.status == 'completed').length;
    final totalCount = _actionSteps.length;
    final progress = totalCount > 0 ? completedCount / totalCount : 0.0;

    // Calculation for Before-After Reduction
    final beforeVal = double.tryParse(_beforeValCtrl.text.trim()) ?? 0.0;
    final actualVal = double.tryParse(_actualValCtrl.text.trim()) ?? 0.0;

    double? reductionPct;
    if (beforeVal > 0 && actualVal > 0) {
      reductionPct = ((beforeVal - actualVal) / beforeVal) * 100.0;
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // Card 1: Multi-Step Action Plan List
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.playlist_add_check_rounded, color: Colors.blueAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📋 แผนปฏิบัติการดำเนินงานหลายขั้นตอน (Multi-Step Action Plan)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            'ความคืบหน้า: $completedCount/$totalCount ขั้นตอนเสร็จสิ้น (${(progress * 100).toStringAsFixed(0)}%)',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: _isGeneratingAiSteps ? null : _generateAiActionStepsBreakdown,
                      icon: _isGeneratingAiSteps
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.auto_awesome, size: 16),
                      label: Text(_isGeneratingAiSteps ? 'กำลังแตกขั้นตอน...' : 'AI แตกขั้นตอนแผนปฏิบัติการ'),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'เพิ่มขั้นตอนย่อย',
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: () {
                        setState(() {
                          _actionSteps.add(
                            ActionStepItem(
                              id: const Uuid().v4(),
                              title: '',
                              status: 'pending',
                            ),
                          );
                        });
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress >= 1.0 ? Colors.green : (progress > 0 ? Colors.blue : Colors.orange),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Action Step Items
                if (_actionSteps.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('ยังไม่มีขั้นตอนแผนงาน กดปุ่ม "+ เพิ่มขั้นตอน" ด้านบน', style: TextStyle(color: Colors.grey.shade600)),
                    ),
                  )
                else
                  ..._actionSteps.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final step = entry.value;
                    return _buildActionStepCard(idx, step, theme);
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Card 2: Post-Improvement Verification & Validation Tracker
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.verified_outlined, color: Colors.green, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🧪 การสอบทานและตรวจสอบผลสำเร็จหลังการปรับปรุง (Verification & Validation)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            'วัดผลจริงว่าสามารถลดเวลา / ลดของเสีย / แก้ปัญหาได้จริงตามเป้าหมายหรือไม่',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Divider(height: 28),

                // Metrics Row (Target Metric, Unit)
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _targetMetricCtrl,
                        decoration: const InputDecoration(
                          labelText: 'ตัวชี้วัดที่ต้องการปรับปรุง (Target KPI / Metric)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.speed),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: TextField(
                        controller: _unitCtrl,
                        decoration: const InputDecoration(
                          labelText: 'หน่วยวัด',
                          border: OutlineInputBorder(),
                          hintText: 'วินาที / นาที / % / ครั้ง',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // 3-Box Comparison (Before vs Target vs Actual)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('1. ก่อนปรับปรุง (Before)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 12)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _beforeValCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                hintText: 'เช่น 1980',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('2. เป้าหมาย (Target)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 12)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _targetValCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                hintText: 'เช่น 1200',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('3. ผลจริงหลังปรับปรุง (Actual)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _actualValCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                hintText: 'เช่น 1150',
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // Reduction Summary Badge
                if (reductionPct != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: reductionPct > 0 ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: reductionPct > 0 ? Colors.green.shade300 : Colors.red.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          reductionPct > 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                          color: reductionPct > 0 ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            reductionPct > 0
                                ? 'ลดลงได้จริง ${reductionPct.abs().toStringAsFixed(1)}% (${beforeVal - actualVal > 0 ? "ลดลง ${(beforeVal - actualVal).toStringAsFixed(1)} ${_unitCtrl.text}" : ""})'
                                : 'ค่าเพิ่มขึ้น ${reductionPct.abs().toStringAsFixed(1)}% (ยังไม่บรรลุเป้าหมาย)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: reductionPct > 0 ? Colors.green.shade800 : Colors.red.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),

                // Verifier & Standardization Notes
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _verifiedByCtrl,
                        decoration: const InputDecoration(
                          labelText: 'ผู้สอบทาน / ผู้ประเมิน (Verifier / Auditor)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_pin_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _verificationDateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'วันที่ตรวจสอบ (Verification Date)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.calendar_today_rounded),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _verificationResult,
                        decoration: const InputDecoration(
                          labelText: 'ผลการประเมิน (Result)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'achieved',
                            child: Text(
                              '✅ สำเร็จตามเป้าหมาย (Achieved)',
                              style: TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'partial',
                            child: Text(
                              '🔄 ดีขึ้นแต่ยังไม่ถึงเป้า (Partial)',
                              style: TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'pending',
                            child: Text(
                              '⏳ อยู่ระหว่างตรวจวัด (In Progress)',
                              style: TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'failed',
                            child: Text(
                              '⚠️ ไม่สำเร็จ/ต้องทบทวนใหม่ (Failed)',
                              style: TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _verificationResult = val);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _standardizationNotesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'การจัดทำมาตรฐานใหม่ & แผนคงสภาพ (Standardization / SOP / PM Plan Update)',
                    hintText: 'ระบุการอัปเดตคู่มือ SOP, Work Instruction, แผน PM ป้องกันการเกิดซ้ำ หรือการฝึกอบรม...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.menu_book_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Save All Button
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    ),
                    onPressed: _isSaving ? null : _saveProblemResolution,
                    icon: _isSaving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_rounded, size: 20),
                    label: const Text('บันทึกแผนปฏิบัติการและผลการตรวจสอบทั้งหมด', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionStepCard(int index, ActionStepItem step, ThemeData theme) {
    final isDone = step.status == 'completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDone ? Colors.green.withValues(alpha: 0.04) : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDone ? Colors.green.withValues(alpha: 0.3) : theme.dividerColor.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: isDone,
                onChanged: (val) {
                  setState(() {
                    step.status = (val == true) ? 'completed' : 'pending';
                  });
                },
              ),
              CircleAvatar(
                radius: 12,
                backgroundColor: isDone ? Colors.green : Colors.blue.shade700,
                child: Text('${index + 1}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: step.title,
                  decoration: const InputDecoration(
                    hintText: 'รายละเอียดขั้นตอนการดำเนินงาน (Action Step)...',
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13.5,
                    decoration: isDone ? TextDecoration.lineThrough : null,
                    color: isDone ? Colors.grey : null,
                  ),
                  onChanged: (v) => step.title = v,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                tooltip: 'ลบขั้นตอนนี้',
                onPressed: () {
                  setState(() {
                    _actionSteps.removeAt(index);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const SizedBox(width: 48),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: step.assignee,
                  decoration: const InputDecoration(
                    labelText: 'ผู้รับผิดชอบ',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (v) => step.assignee = v,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextFormField(
                  initialValue: step.dueDate,
                  decoration: const InputDecoration(
                    labelText: 'กำหนดเสร็จ',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (v) => step.dueDate = v,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: step.status,
                  decoration: const InputDecoration(
                    labelText: 'สถานะ',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontSize: 11, color: Colors.black),
                  items: const [
                    DropdownMenuItem(value: 'pending', child: Text('⏳ รอดำเนินการ')),
                    DropdownMenuItem(value: 'in_progress', child: Text('🔄 กำลังทำ')),
                    DropdownMenuItem(value: 'completed', child: Text('✅ เสร็จแล้ว')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => step.status = val);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
