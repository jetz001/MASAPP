import 'work_process_step_model.dart';

enum WorkProcessMethodType {
  current('current', 'ปัจจุบัน (Current / As-Is)'),
  improved('improved', 'ปรับปรุง (Improved / To-Be)');

  final String code;
  final String label;
  const WorkProcessMethodType(this.code, this.label);

  static WorkProcessMethodType fromCode(String? code) {
    return WorkProcessMethodType.values.firstWhere(
      (e) => e.code == (code ?? '').toLowerCase().trim(),
      orElse: () => WorkProcessMethodType.current,
    );
  }
}

enum WorkTypeCategory {
  man('man', 'คน (Man / Operator)'),
  product('product', 'ผลิตภัณฑ์ (Product / Material)');

  final String code;
  final String label;
  const WorkTypeCategory(this.code, this.label);

  static WorkTypeCategory fromCode(String? code) {
    return WorkTypeCategory.values.firstWhere(
      (e) => e.code == (code ?? '').toLowerCase().trim(),
      orElse: () => WorkTypeCategory.man,
    );
  }
}

class WorkProcess {
  final String processId;
  final String processNo;
  final String title;
  final String? company;
  final String? factory;
  final String? department;
  final WorkProcessMethodType methodType;
  final String? parentProcessId;
  final WorkTypeCategory workType;
  final String? machineId;
  final String? machineNo;
  final String? machineName;
  final String? lineId;
  final String? preparedBy;
  final String? preparedDate;
  final String? approvedBy;
  final String? approvedDate;
  final String? notes;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<WorkProcessStep> steps;

  const WorkProcess({
    required this.processId,
    required this.processNo,
    required this.title,
    this.company,
    this.factory,
    this.department,
    this.methodType = WorkProcessMethodType.current,
    this.parentProcessId,
    this.workType = WorkTypeCategory.man,
    this.machineId,
    this.machineNo,
    this.machineName,
    this.lineId,
    this.preparedBy,
    this.preparedDate,
    this.approvedBy,
    this.approvedDate,
    this.notes,
    this.status = 'draft',
    required this.createdAt,
    required this.updatedAt,
    this.steps = const [],
  });

  factory WorkProcess.fromMap(
    Map<String, dynamic> map, {
    List<WorkProcessStep> steps = const [],
  }) {
    return WorkProcess(
      processId: map['process_id']?.toString() ?? '',
      processNo: map['process_no']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      company: map['company']?.toString(),
      factory: map['factory']?.toString(),
      department: map['department']?.toString(),
      methodType: WorkProcessMethodType.fromCode(map['method_type']?.toString()),
      parentProcessId: map['parent_process_id']?.toString(),
      workType: WorkTypeCategory.fromCode(map['work_type']?.toString()),
      machineId: map['machine_id']?.toString(),
      machineNo: map['machine_no']?.toString(),
      machineName: map['machine_name']?.toString(),
      lineId: map['line_id']?.toString(),
      preparedBy: map['prepared_by']?.toString(),
      preparedDate: map['prepared_date']?.toString(),
      approvedBy: map['approved_by']?.toString(),
      approvedDate: map['approved_date']?.toString(),
      notes: map['notes']?.toString(),
      status: map['status']?.toString() ?? 'draft',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      steps: steps,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'process_id': processId,
      'process_no': processNo,
      'title': title,
      'company': company,
      'factory': factory,
      'department': department,
      'method_type': methodType.code,
      'parent_process_id': parentProcessId,
      'work_type': workType.code,
      'machine_id': machineId,
      'line_id': lineId,
      'prepared_by': preparedBy,
      'prepared_date': preparedDate,
      'approved_by': approvedBy,
      'approved_date': approvedDate,
      'notes': notes,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // Helper summary calculations
  double get totalDurationMinutes =>
      steps.fold(0.0, (sum, s) => sum + s.durationMinutes);

  double get totalDistanceMeters =>
      steps.fold(0.0, (sum, s) => sum + s.distanceMeters);

  double get vaDurationMinutes => steps
      .where((s) => s.valueType == LeanValueType.va)
      .fold(0.0, (sum, s) => sum + s.durationMinutes);

  double get nvaDurationMinutes => steps
      .where((s) => s.valueType == LeanValueType.nva)
      .fold(0.0, (sum, s) => sum + s.durationMinutes);

  double get nnvaDurationMinutes => steps
      .where((s) => s.valueType == LeanValueType.nnva)
      .fold(0.0, (sum, s) => sum + s.durationMinutes);

  double get processCycleEfficiency => totalDurationMinutes > 0
      ? (vaDurationMinutes / totalDurationMinutes) * 100.0
      : 0.0;

  double get wasteRatio => totalDurationMinutes > 0
      ? ((nvaDurationMinutes + nnvaDurationMinutes) / totalDurationMinutes) * 100.0
      : 0.0;

  int countByEvent(ProcessEventType type) =>
      steps.where((s) => s.eventType == type).length;

  double durationByEvent(ProcessEventType type) => steps
      .where((s) => s.eventType == type)
      .fold(0.0, (sum, s) => sum + s.durationMinutes);

  WorkProcess copyWith({
    String? processId,
    String? processNo,
    String? title,
    String? company,
    String? factory,
    String? department,
    WorkProcessMethodType? methodType,
    String? parentProcessId,
    WorkTypeCategory? workType,
    String? machineId,
    String? machineNo,
    String? machineName,
    String? lineId,
    String? preparedBy,
    String? preparedDate,
    String? approvedBy,
    String? approvedDate,
    String? notes,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<WorkProcessStep>? steps,
  }) {
    return WorkProcess(
      processId: processId ?? this.processId,
      processNo: processNo ?? this.processNo,
      title: title ?? this.title,
      company: company ?? this.company,
      factory: factory ?? this.factory,
      department: department ?? this.department,
      methodType: methodType ?? this.methodType,
      parentProcessId: parentProcessId ?? this.parentProcessId,
      workType: workType ?? this.workType,
      machineId: machineId ?? this.machineId,
      machineNo: machineNo ?? this.machineNo,
      machineName: machineName ?? this.machineName,
      lineId: lineId ?? this.lineId,
      preparedBy: preparedBy ?? this.preparedBy,
      preparedDate: preparedDate ?? this.preparedDate,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedDate: approvedDate ?? this.approvedDate,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      steps: steps ?? this.steps,
    );
  }
}
