import 'dart:convert';
import 'package:uuid/uuid.dart';

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

class ActionPlanRecord {
  final String rcaId;
  final String sourceType; // work_order, line_balancing, sop_step, custom
  final String? sourceId;
  final String problemTitle;
  final String? why1;
  final String? why2;
  final String? why3;
  final String? why4;
  final String? why5;
  final String? rootCause;
  final String? fishboneMan;
  final String? fishboneMachine;
  final String? fishboneMaterial;
  final String? fishboneMethod;
  final String? fishboneEnv;
  final String rcaMethod; // '5why', 'fishbone', or 'both'
  final List<ActionStepItem> actionSteps;
  final String? targetMetric;
  final double? beforeValue;
  final double? targetValue;
  final double? actualValue;
  final String? metricUnit;
  final String? verifiedBy;
  final String? verificationDate;
  final String? verificationResult; // achieved, partial, pending, failed
  final String? standardizationNotes;
  final String status; // in_progress, completed, closed, pending
  final String? createdAt;
  final String? updatedAt;
  final List<Map<String, dynamic>> attachments;

  ActionPlanRecord({
    required this.rcaId,
    required this.sourceType,
    this.sourceId,
    required this.problemTitle,
    this.why1,
    this.why2,
    this.why3,
    this.why4,
    this.why5,
    this.rootCause,
    this.fishboneMan,
    this.fishboneMachine,
    this.fishboneMaterial,
    this.fishboneMethod,
    this.fishboneEnv,
    this.rcaMethod = '5why',
    required this.actionSteps,
    this.targetMetric,
    this.beforeValue,
    this.targetValue,
    this.actualValue,
    this.metricUnit,
    this.verifiedBy,
    this.verificationDate,
    this.verificationResult,
    this.standardizationNotes,
    this.status = 'in_progress',
    this.createdAt,
    this.updatedAt,
    this.attachments = const [],
  });

  int get completedStepsCount =>
      actionSteps.where((s) => s.status == 'completed').length;
  int get totalStepsCount => actionSteps.length;
  double get progress =>
      totalStepsCount > 0 ? completedStepsCount / totalStepsCount : 0.0;

  double? get reductionPercentage {
    if (beforeValue != null &&
        actualValue != null &&
        beforeValue! > 0 &&
        actualValue! > 0) {
      return ((beforeValue! - actualValue!) / beforeValue!) * 100.0;
    }
    return null;
  }

  factory ActionPlanRecord.fromMap(
    Map<String, dynamic> map, {
    List<Map<String, dynamic>> attachments = const [],
  }) {
    List<ActionStepItem> steps = [];
    if (map['action_steps_json'] != null &&
        map['action_steps_json'].toString().isNotEmpty) {
      try {
        final decoded = jsonDecode(map['action_steps_json'].toString());
        if (decoded is List) {
          steps = decoded
              .map((item) =>
                  ActionStepItem.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }

    return ActionPlanRecord(
      rcaId: map['rca_id']?.toString() ?? '',
      sourceType: map['source_type']?.toString() ?? 'custom',
      sourceId: map['source_id']?.toString(),
      problemTitle: map['problem_title']?.toString() ?? 'ไม่มีหัวข้อปัญหา',
      why1: map['why_1']?.toString(),
      why2: map['why_2']?.toString(),
      why3: map['why_3']?.toString(),
      why4: map['why_4']?.toString(),
      why5: map['why_5']?.toString(),
      rootCause: map['root_cause']?.toString(),
      fishboneMan: map['fishbone_man']?.toString(),
      fishboneMachine: map['fishbone_machine']?.toString(),
      fishboneMaterial: map['fishbone_material']?.toString(),
      fishboneMethod: map['fishbone_method']?.toString(),
      fishboneEnv: map['fishbone_env']?.toString(),
      rcaMethod: map['rca_method']?.toString() ??
          ((map['fishbone_man']?.toString().isNotEmpty == true ||
                  map['fishbone_machine']?.toString().isNotEmpty == true ||
                  map['fishbone_material']?.toString().isNotEmpty == true ||
                  map['fishbone_method']?.toString().isNotEmpty == true ||
                  map['fishbone_env']?.toString().isNotEmpty == true) &&
                  (map['why_1'] == null || map['why_1'].toString().isEmpty)
              ? 'fishbone'
              : '5why'),
      actionSteps: steps,
      targetMetric: map['target_metric']?.toString(),
      beforeValue: map['before_value'] != null
          ? double.tryParse(map['before_value'].toString())
          : null,
      targetValue: map['target_value'] != null
          ? double.tryParse(map['target_value'].toString())
          : null,
      actualValue: map['actual_value'] != null
          ? double.tryParse(map['actual_value'].toString())
          : null,
      metricUnit: map['metric_unit']?.toString(),
      verifiedBy: map['verified_by']?.toString(),
      verificationDate: map['verification_date']?.toString(),
      verificationResult: map['verification_result']?.toString(),
      standardizationNotes: map['standardization_notes']?.toString(),
      status: map['status']?.toString() ?? 'in_progress',
      createdAt: map['created_at']?.toString(),
      updatedAt: map['updated_at']?.toString(),
      attachments: attachments,
    );
  }
}
