/// Work order domain models
library;

enum WorkOrderStatus {
  pending, // Created, waiting for approval
  approved, // Approved by supervisor
  inProgress, // Technician started work
  completed, // Work finished
  cancelled, // Cancelled
  rejected, // Rejected by supervisor
}

extension WorkOrderStatusExt on WorkOrderStatus {
  String get label {
    switch (this) {
      case WorkOrderStatus.pending:
        return 'รอการอนุมัติ';
      case WorkOrderStatus.approved:
        return 'อนุมัติแล้ว';
      case WorkOrderStatus.inProgress:
        return 'กำลังดำเนินการ';
      case WorkOrderStatus.completed:
        return 'เสร็จสิ้น';
      case WorkOrderStatus.cancelled:
        return 'ยกเลิก';
      case WorkOrderStatus.rejected:
        return 'ปฏิเสธ';
    }
  }

  String get dbValue {
    switch (this) {
      case WorkOrderStatus.pending:
        return 'pending';
      case WorkOrderStatus.approved:
        return 'approved';
      case WorkOrderStatus.inProgress:
        return 'in_progress';
      case WorkOrderStatus.completed:
        return 'completed';
      case WorkOrderStatus.cancelled:
        return 'cancelled';
      case WorkOrderStatus.rejected:
        return 'rejected';
    }
  }

  static WorkOrderStatus fromDb(String? value) {
    switch (value?.toLowerCase()) {
      case 'approved':
        return WorkOrderStatus.approved;
      case 'in_progress':
        return WorkOrderStatus.inProgress;
      case 'completed':
        return WorkOrderStatus.completed;
      case 'cancelled':
        return WorkOrderStatus.cancelled;
      case 'rejected':
        return WorkOrderStatus.rejected;
      default:
        return WorkOrderStatus.pending;
    }
  }
}

enum WorkOrderPriority { low, normal, high, urgent }

extension WorkOrderPriorityExt on WorkOrderPriority {
  String get label {
    switch (this) {
      case WorkOrderPriority.low:
        return 'ต่ำ';
      case WorkOrderPriority.normal:
        return 'ปกติ';
      case WorkOrderPriority.high:
        return 'สูง';
      case WorkOrderPriority.urgent:
        return 'ด่วน';
    }
  }

  String get dbValue {
    switch (this) {
      case WorkOrderPriority.low:
        return 'low';
      case WorkOrderPriority.normal:
        return 'normal';
      case WorkOrderPriority.high:
        return 'high';
      case WorkOrderPriority.urgent:
        return 'urgent';
    }
  }

  static WorkOrderPriority fromDb(String? value) {
    switch (value?.toLowerCase()) {
      case 'high':
        return WorkOrderPriority.high;
      case 'urgent':
        return WorkOrderPriority.urgent;
      case 'low':
        return WorkOrderPriority.low;
      default:
        return WorkOrderPriority.normal;
    }
  }
}

/// Main work order model
class WorkOrder {
  final String woId;
  final String woNo; // Sequential work order number
  final String machineId;
  final String machineNo;
  final String? machineBrand;
  final String? machineModel;
  final String? zone;
  final String? description; // Problem description
  final String? failureSymptom; // How machine failed
  final String? reportedBy; // User ID who reported
  final String? reportedByName;
  final DateTime reportedAt;
  final WorkOrderStatus status;
  final WorkOrderPriority priority;
  final String? approvedBy; // Supervisor user ID
  final DateTime? approvedAt;
  final String? assignedTo; // Technician user ID
  final String? assignedToName;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final double? estimatedHours;
  final double? actualHours;
  final String? notes;
  final String? closureNotes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Related data
  final List<WorkOrderLabor>? laborEntries;
  final RootCauseAnalysis? rca;

  const WorkOrder({
    required this.woId,
    required this.woNo,
    required this.machineId,
    required this.machineNo,
    this.machineBrand,
    this.machineModel,
    this.zone,
    this.description,
    this.failureSymptom,
    this.reportedBy,
    this.reportedByName,
    required this.reportedAt,
    this.status = WorkOrderStatus.pending,
    this.priority = WorkOrderPriority.normal,
    this.approvedBy,
    this.approvedAt,
    this.assignedTo,
    this.assignedToName,
    this.startedAt,
    this.completedAt,
    this.estimatedHours,
    this.actualHours,
    this.notes,
    this.closureNotes,
    required this.createdAt,
    required this.updatedAt,
    this.laborEntries,
    this.rca,
  });

  factory WorkOrder.fromMap(Map<String, dynamic> map) {
    final reportedAtStr =
        (map['reported_at'] ?? map['created_at']) as String?;
    final createdAtStr = map['created_at'] as String?;
    final updatedAtStr = map['updated_at'] as String?;
    final now = DateTime.now().toIso8601String();

    return WorkOrder(
      woId: map['wo_id'] as String,
      woNo: map['wo_no'] as String,
      machineId: map['machine_id'] as String,
      machineNo: (map['machine_no'] ?? '') as String,
      machineBrand: map['machine_brand'] as String?,
      machineModel: map['machine_model'] as String?,
      zone: map['zone'] as String?,
      description: (map['title'] ?? map['description']) as String?,
      failureSymptom: map['failure_symptom'] as String?,
      reportedBy: (map['reported_by'] ?? map['created_by']) as String?,
      reportedByName: map['reported_by_name'] as String?,
      reportedAt: DateTime.parse(reportedAtStr ?? now),
      status: WorkOrderStatusExt.fromDb(map['status'] as String?),
      priority: WorkOrderPriorityExt.fromDb(map['priority'] as String?),
      approvedBy: map['approved_by'] as String?,
      approvedAt: map['approved_at'] != null
          ? DateTime.tryParse(map['approved_at'] as String)
          : null,
      assignedTo: map['assigned_to'] as String?,
      assignedToName: map['assigned_to_name'] as String?,
      startedAt: map['started_at'] != null
          ? DateTime.tryParse(map['started_at'] as String)
          : null,
      completedAt: map['completed_at'] != null
          ? DateTime.tryParse(map['completed_at'] as String)
          : null,
      estimatedHours: (map['estimated_hours'] as num?)?.toDouble(),
      actualHours: (map['actual_hours'] as num?)?.toDouble(),
      notes: map['notes'] as String?,
      closureNotes: map['closure_notes'] as String?,
      createdAt: DateTime.parse(createdAtStr ?? now),
      updatedAt: DateTime.parse(updatedAtStr ?? now),
    );
  }

  WorkOrder copyWith({
    String? woId,
    String? woNo,
    String? machineId,
    String? machineNo,
    String? machineBrand,
    String? machineModel,
    String? zone,
    String? description,
    String? failureSymptom,
    String? reportedBy,
    String? reportedByName,
    DateTime? reportedAt,
    WorkOrderStatus? status,
    WorkOrderPriority? priority,
    String? approvedBy,
    DateTime? approvedAt,
    String? assignedTo,
    String? assignedToName,
    DateTime? startedAt,
    DateTime? completedAt,
    double? estimatedHours,
    double? actualHours,
    String? notes,
    String? closureNotes,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<WorkOrderLabor>? laborEntries,
    RootCauseAnalysis? rca,
  }) {
    return WorkOrder(
      woId: woId ?? this.woId,
      woNo: woNo ?? this.woNo,
      machineId: machineId ?? this.machineId,
      machineNo: machineNo ?? this.machineNo,
      machineBrand: machineBrand ?? this.machineBrand,
      machineModel: machineModel ?? this.machineModel,
      zone: zone ?? this.zone,
      description: description ?? this.description,
      failureSymptom: failureSymptom ?? this.failureSymptom,
      reportedBy: reportedBy ?? this.reportedBy,
      reportedByName: reportedByName ?? this.reportedByName,
      reportedAt: reportedAt ?? this.reportedAt,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToName: assignedToName ?? this.assignedToName,
      startedAt: startedAt ?? this.startedAt,
      completedAt: completedAt ?? this.completedAt,
      estimatedHours: estimatedHours ?? this.estimatedHours,
      actualHours: actualHours ?? this.actualHours,
      notes: notes ?? this.notes,
      closureNotes: closureNotes ?? this.closureNotes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      laborEntries: laborEntries ?? this.laborEntries,
      rca: rca ?? this.rca,
    );
  }
}

/// Labor entry (time tracking per technician)
class WorkOrderLabor {
  final String laborId;
  final String woId;
  final String technicianId;
  final String technicianName;
  final DateTime startTime;
  final DateTime endTime;
  final double hours; // Calculated duration
  final String? taskDescription;
  final String? notes;

  const WorkOrderLabor({
    required this.laborId,
    required this.woId,
    required this.technicianId,
    required this.technicianName,
    required this.startTime,
    required this.endTime,
    required this.hours,
    this.taskDescription,
    this.notes,
  });

  factory WorkOrderLabor.fromMap(Map<String, dynamic> map) {
    return WorkOrderLabor(
      laborId: map['labor_id'] as String,
      woId: map['wo_id'] as String,
      technicianId: map['technician_id'] as String,
      technicianName: map['technician_name'] as String,
      startTime: DateTime.parse(map['start_time'] as String),
      endTime: DateTime.parse(map['end_time'] as String),
      hours: (map['hours'] as num).toDouble(),
      taskDescription: map['task_description'] as String?,
      notes: map['notes'] as String?,
    );
  }
}

/// Root Cause Analysis (5 Whys) for breakdown
class RootCauseAnalysis {
  final String rcaId;
  final String woId;
  final String why1; // Why did it fail?
  final String why2; // Why did that happen?
  final String why3; // Why did that happen?
  final String why4; // Why did that happen?
  final String why5; // Why did that happen?
  final String? rootCause; // Final root cause
  final String? correctionAction; // Action to prevent recurrence
  final String? preventiveAction; // Long-term prevention
  final DateTime? completedAt;
  final String? completedBy;

  const RootCauseAnalysis({
    required this.rcaId,
    required this.woId,
    required this.why1,
    required this.why2,
    required this.why3,
    required this.why4,
    required this.why5,
    this.rootCause,
    this.correctionAction,
    this.preventiveAction,
    this.completedAt,
    this.completedBy,
  });

  factory RootCauseAnalysis.fromMap(Map<String, dynamic> map) {
    return RootCauseAnalysis(
      rcaId: map['rca_id'] as String,
      woId: map['wo_id'] as String,
      why1: map['why_1'] as String,
      why2: map['why_2'] as String,
      why3: map['why_3'] as String,
      why4: map['why_4'] as String,
      why5: map['why_5'] as String,
      rootCause: map['root_cause'] as String?,
      correctionAction: map['correction_action'] as String?,
      preventiveAction: map['preventive_action'] as String?,
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'] as String)
          : null,
      completedBy: map['completed_by'] as String?,
    );
  }
}
