import 'package:flutter/material.dart';

enum ProcessEventType {
  operation('operation', 'ทำงาน / ดำเนินการ', '⭕', Colors.blue),
  transportation('transportation', 'ขนส่ง / เคลื่อนย้าย', '⇨', Colors.orange),
  inspection('inspection', 'ตรวจสอบ / ตรวจนับ', '◻', Colors.purple),
  delay('delay', 'รอคอย / หน่วง', 'D', Colors.red),
  storage('storage', 'จัดเก็บ / พักของ', '▽', Colors.green);

  final String code;
  final String label;
  final String symbol;
  final MaterialColor color;

  const ProcessEventType(this.code, this.label, this.symbol, this.color);

  static ProcessEventType fromCode(String? code) {
    return ProcessEventType.values.firstWhere(
      (e) => e.code == (code ?? '').toLowerCase().trim(),
      orElse: () => ProcessEventType.operation,
    );
  }
}

enum LeanValueType {
  va('va', 'จำเป็น / มีประโยชน์ (VA)', 'มีประโยชน์', Color(0xFF10B981)),
  nva('nva', 'สูญเปล่า / ไม่มีประโยชน์ (NVA)', 'ไม่ปกติ / สูญเปล่า', Color(0xFFEF4444)),
  nnva('nnva', 'สูญเปล่าแต่จำเป็น (NNVA)', 'ไม่สมควร / สูญเปล่าจำเป็น', Color(0xFFF59E0B));

  final String code;
  final String label;
  final String shortLabel;
  final Color color;

  const LeanValueType(this.code, this.label, this.shortLabel, this.color);

  static LeanValueType fromCode(String? code) {
    return LeanValueType.values.firstWhere(
      (v) => v.code == (code ?? '').toLowerCase().trim(),
      orElse: () => LeanValueType.va,
    );
  }
}

class WorkProcessStep {
  final String stepId;
  final String processId;
  final int stepNo;
  final String description;
  final ProcessEventType eventType;
  final double distanceMeters;
  final String? partsQuantity;
  final String? toolsUsed;
  final double durationMinutes;
  final LeanValueType valueType;
  final String? problemCause;
  final String? improvementIdea;
  final DateTime createdAt;

  const WorkProcessStep({
    required this.stepId,
    required this.processId,
    required this.stepNo,
    required this.description,
    required this.eventType,
    this.distanceMeters = 0.0,
    this.partsQuantity,
    this.toolsUsed,
    this.durationMinutes = 0.0,
    this.valueType = LeanValueType.va,
    this.problemCause,
    this.improvementIdea,
    required this.createdAt,
  });

  String get eventIcon => eventType.symbol;
  String get eventName => eventType.label;
  String get valueLabel => valueType.label;

  factory WorkProcessStep.fromMap(Map<String, dynamic> map) {
    return WorkProcessStep(
      stepId: map['step_id']?.toString() ?? '',
      processId: map['process_id']?.toString() ?? '',
      stepNo: (map['step_no'] as num?)?.toInt() ?? 1,
      description: map['description']?.toString() ?? '',
      eventType: ProcessEventType.fromCode(map['event_type']?.toString()),
      distanceMeters: (map['distance_meters'] as num?)?.toDouble() ?? 0.0,
      partsQuantity: map['parts_quantity']?.toString(),
      toolsUsed: map['tools_used']?.toString(),
      durationMinutes: (map['duration_minutes'] as num?)?.toDouble() ?? 0.0,
      valueType: LeanValueType.fromCode(map['value_type']?.toString()),
      problemCause: map['problem_cause']?.toString(),
      improvementIdea: map['improvement_idea']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'step_id': stepId,
      'process_id': processId,
      'step_no': stepNo,
      'description': description,
      'event_type': eventType.code,
      'distance_meters': distanceMeters,
      'parts_quantity': partsQuantity,
      'tools_used': toolsUsed,
      'duration_minutes': durationMinutes,
      'value_type': valueType.code,
      'problem_cause': problemCause,
      'improvement_idea': improvementIdea,
      'created_at': createdAt.toIso8601String(),
    };
  }

  WorkProcessStep copyWith({
    String? stepId,
    String? processId,
    int? stepNo,
    String? description,
    ProcessEventType? eventType,
    double? distanceMeters,
    String? partsQuantity,
    String? toolsUsed,
    double? durationMinutes,
    LeanValueType? valueType,
    String? problemCause,
    String? improvementIdea,
    DateTime? createdAt,
  }) {
    return WorkProcessStep(
      stepId: stepId ?? this.stepId,
      processId: processId ?? this.processId,
      stepNo: stepNo ?? this.stepNo,
      description: description ?? this.description,
      eventType: eventType ?? this.eventType,
      distanceMeters: distanceMeters ?? this.distanceMeters,
      partsQuantity: partsQuantity ?? this.partsQuantity,
      toolsUsed: toolsUsed ?? this.toolsUsed,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      valueType: valueType ?? this.valueType,
      problemCause: problemCause ?? this.problemCause,
      improvementIdea: improvementIdea ?? this.improvementIdea,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
