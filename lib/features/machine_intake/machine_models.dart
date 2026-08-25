import 'dart:convert';
import 'package:flutter/material.dart';

enum MachineStatus { normal, breakdown, pm, am, offline, decommissioned }

extension MachineStatusColor on MachineStatus {
  Color get color {
    switch (this) {
      case MachineStatus.normal:
        return Colors.green;
      case MachineStatus.breakdown:
        return Colors.red;
      case MachineStatus.pm:
        return Colors.orange;
      case MachineStatus.am:
        return Colors.blue;
      case MachineStatus.offline:
        return Colors.grey;
      case MachineStatus.decommissioned:
        return Colors.black54;
    }
  }
}

enum HandoverStage { stage1, stage2, stage3 }

enum HandoverStatus { pending, inProgress, passed, failed, approved }

extension HandoverStageLabel on HandoverStage {
  String get label {
    switch (this) {
      case HandoverStage.stage1:
        return 'Stage 1: การติดตั้ง';
      case HandoverStage.stage2:
        return 'Stage 2: การทดสอบเดินเครื่อง';
      case HandoverStage.stage3:
        return 'Stage 3: การตรวจรับ & อนุมัติ';
    }
  }

  String get shortLabel {
    switch (this) {
      case HandoverStage.stage1:
        return 'ติดตั้ง';
      case HandoverStage.stage2:
        return 'ทดสอบ';
      case HandoverStage.stage3:
        return 'ตรวจรับ';
    }
  }

  String get dbValue {
    switch (this) {
      case HandoverStage.stage1:
        return 'stage1';
      case HandoverStage.stage2:
        return 'stage2';
      case HandoverStage.stage3:
        return 'stage3';
    }
  }

  static HandoverStage fromDb(String v) {
    switch (v) {
      case 'stage2':
        return HandoverStage.stage2;
      case 'stage3':
        return HandoverStage.stage3;
      default:
        return HandoverStage.stage1;
    }
  }
}

class MachineModel {
  final String? machineId;
  final String machineNo;
  final String? machineName;
  final String? assetNo;
  final String? brand;
  final String? model;
  final String? serialNo;
  final String? categoryId;
  final String? categoryName;
  final String? deptId;
  final String? deptName;
  final String? location;
  final MachineStatus status;
  final DateTime? installationDate;
  final DateTime? warrantyExpiry;
  final double? purchaseCost;
  final String? supplierId;
  final String? supplierName;
  final bool handoverCompleted;
  final bool isEditUnlocked;
  final bool isActive;
  final String? notes;
  final String? handoverConclusion; // accepted, rejected
  final DateTime? createdAt;

  // Specs (joined)
  final MachineSpecs? specs;

  // Handover stages
  final HandoverInfo? stage1;
  final HandoverInfo? stage2;
  final HandoverInfo? stage3;
  final HandoverStatus stage3Status;

  // Running hours
  final double? totalRunningHours;

  // Attachments
  final List<Map<String, dynamic>> attachments;

  const MachineModel({
    this.machineId,
    required this.machineNo,
    this.machineName,
    this.assetNo,
    this.brand,
    this.model,
    this.serialNo,
    this.categoryId,
    this.categoryName,
    this.deptId,
    this.deptName,
    this.location,
    this.status = MachineStatus.normal,
    this.installationDate,
    this.warrantyExpiry,
    this.purchaseCost,
    this.supplierId,
    this.supplierName,
    this.handoverCompleted = false,
    this.isEditUnlocked = false,
    this.isActive = true,
    this.notes,
    this.handoverConclusion,
    this.createdAt,
    this.specs,
    this.stage1,
    this.stage2,
    this.stage3,
    this.stage3Status = HandoverStatus.pending,
    this.totalRunningHours,
    this.attachments = const [],
  });

  factory MachineModel.fromMap(Map<String, dynamic> m) {
    return MachineModel(
      machineId: m['machine_id']?.toString(),
      machineNo: m['machine_no']?.toString() ?? '',
      machineName: m['machine_name']?.toString(),
      assetNo: m['asset_no']?.toString(),
      brand: m['brand']?.toString(),
      model: m['model']?.toString(),
      serialNo: m['serial_no']?.toString(),
      categoryId: m['category_id']?.toString(),
      categoryName: m['category_name']?.toString(),
      deptId: m['dept_id']?.toString(),
      deptName: m['dept_name']?.toString(),
      location: m['location']?.toString(),
      status: _parseStatus(m['status']?.toString()),
      installationDate: m['installation_date'] != null
          ? DateTime.tryParse(m['installation_date'].toString())
          : null,
      warrantyExpiry: m['warranty_expiry'] != null
          ? DateTime.tryParse(m['warranty_expiry'].toString())
          : null,
      purchaseCost: (m['purchase_cost'] as num?)?.toDouble(),
      supplierId: m['supplier_id']?.toString(),
      supplierName: m['supplier_name']?.toString(),
      handoverCompleted:
          m['handover_completed'] == true || m['handover_completed'] == 1,
      isEditUnlocked:
          m['is_edit_unlocked'] == true || m['is_edit_unlocked'] == 1,
      isActive:
          m['is_active'] == true ||
          m['is_active'] == 1 ||
          m['is_active'] == null,
      notes: m['notes']?.toString(),
      handoverConclusion: m['handover_conclusion']?.toString(),
      createdAt: m['created_at'] != null
          ? DateTime.tryParse(m['created_at'].toString())
          : null,
      totalRunningHours: (m['total_running_hours'] as num?)?.toDouble(),
      stage3Status: m['stage3_status'] != null
          ? HandoverInfo.parseStatus(m['stage3_status'].toString())
          : HandoverStatus.pending,
    );
  }

  static MachineStatus _parseStatus(String? s) {
    switch (s) {
      case 'breakdown':
        return MachineStatus.breakdown;
      case 'pm':
        return MachineStatus.pm;
      case 'am':
        return MachineStatus.am;
      case 'offline':
        return MachineStatus.offline;
      case 'decommissioned':
        return MachineStatus.decommissioned;
      default:
        return MachineStatus.normal;
    }
  }

  String get statusLabel {
    switch (status) {
      case MachineStatus.normal:
        return 'ปกติ';
      case MachineStatus.breakdown:
        return 'เสีย';
      case MachineStatus.pm:
        return 'กำลัง PM';
      case MachineStatus.am:
        return 'กำลัง AM';
      case MachineStatus.offline:
        return 'หยุดเดิน';
      case MachineStatus.decommissioned:
        return 'ปลดระวาง';
    }
  }

  MachineModel copyWithDetails({
    MachineSpecs? specs,
    HandoverInfo? stage1,
    HandoverInfo? stage2,
    HandoverInfo? stage3,
    List<Map<String, dynamic>>? attachments,
  }) {
    return MachineModel(
      machineId: machineId,
      machineNo: machineNo,
      machineName: machineName,
      assetNo: assetNo,
      brand: brand,
      model: model,
      serialNo: serialNo,
      categoryId: categoryId,
      categoryName: categoryName,
      deptId: deptId,
      deptName: deptName,
      location: location,
      status: status,
      installationDate: installationDate,
      warrantyExpiry: warrantyExpiry,
      purchaseCost: purchaseCost,
      supplierId: supplierId,
      supplierName: supplierName,
      handoverCompleted: handoverCompleted,
      isEditUnlocked: isEditUnlocked,
      isActive: isActive,
      notes: notes,
      handoverConclusion: handoverConclusion,
      createdAt: createdAt,
      specs: specs ?? this.specs,
      stage1: stage1 ?? this.stage1,
      stage2: stage2 ?? this.stage2,
      stage3: stage3 ?? this.stage3,
      stage3Status: stage3Status,
      totalRunningHours: totalRunningHours,
      attachments: attachments ?? this.attachments,
    );
  }
}

class MachineSpecs {
  final double? powerKw;
  final double? voltageV;
  final double? currentA;
  final double? frequencyHz;
  final double? capacity;
  final String? capacityUnit;
  final double? weightKg;
  final double? dimLengthMm;
  final double? dimWidthMm;
  final double? dimHeightMm;
  final double? rpm;
  final double? fuelConsumptionRate;
  final String? fuelType;
  final int? defaultWorkers;
  final Map<String, dynamic> extraSpecs;

  const MachineSpecs({
    this.powerKw,
    this.voltageV,
    this.currentA,
    this.frequencyHz,
    this.capacity,
    this.capacityUnit,
    this.weightKg,
    this.dimLengthMm,
    this.dimWidthMm,
    this.dimHeightMm,
    this.rpm,
    this.fuelConsumptionRate,
    this.fuelType,
    this.defaultWorkers,
    this.extraSpecs = const {},
  });

  factory MachineSpecs.fromMap(Map<String, dynamic> map) {
    final extraSpecs = _parseExtraSpecs(map['extra_specs']);
    return MachineSpecs(
      powerKw: (map['power_kw'] as num?)?.toDouble(),
      voltageV: (map['voltage_v'] as num?)?.toDouble(),
      currentA: (map['current_a'] as num?)?.toDouble(),
      frequencyHz: (map['frequency_hz'] as num?)?.toDouble(),
      capacity: (map['capacity'] as num?)?.toDouble(),
      capacityUnit: map['capacity_unit'] as String?,
      weightKg: (map['weight_kg'] as num?)?.toDouble(),
      dimLengthMm: (map['dim_length_mm'] as num?)?.toDouble(),
      dimWidthMm: (map['dim_width_mm'] as num?)?.toDouble(),
      dimHeightMm: (map['dim_height_mm'] as num?)?.toDouble(),
      rpm: (map['rpm'] as num?)?.toDouble(),
      fuelConsumptionRate: (map['fuel_consumption_rate'] as num?)?.toDouble(),
      fuelType: map['fuel_type'] as String?,
      defaultWorkers: map['default_workers'] as int?,
      extraSpecs: extraSpecs,
    );
  }

  String? get statusReason {
    final value = extraSpecs['status_reason'];
    if (value == null) {
      return null;
    }
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  Map<String, dynamic> toMap() {
    return {
      'power_kw': powerKw,
      'voltage_v': voltageV,
      'current_a': currentA,
      'frequency_hz': frequencyHz,
      'capacity': capacity,
      'capacity_unit': capacityUnit,
      'weight_kg': weightKg,
      'dim_length_mm': dimLengthMm,
      'dim_width_mm': dimWidthMm,
      'dim_height_mm': dimHeightMm,
      'rpm': rpm,
      'fuel_consumption_rate': fuelConsumptionRate,
      'fuel_type': fuelType,
      'default_workers': defaultWorkers,
      'extra_specs': extraSpecs.isEmpty ? null : jsonEncode(extraSpecs),
    };
  }

  static Map<String, dynamic> _parseExtraSpecs(dynamic rawValue) {
    if (rawValue == null) {
      return const {};
    }

    if (rawValue is Map<String, dynamic>) {
      return Map<String, dynamic>.from(rawValue);
    }

    if (rawValue is Map) {
      return rawValue.map((key, value) => MapEntry(key.toString(), value));
    }

    if (rawValue is String && rawValue.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawValue);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }
      } catch (_) {
        return const {};
      }
    }

    return const {};
  }
}

class HandoverInfo {
  final String? handoverId;
  final HandoverStage stage;
  final HandoverStatus status;
  final String? performedBy;
  final String? approvedBy;
  final String? performerName;
  final String? approverName;
  final DateTime? performedAt;
  final DateTime? approvedAt;
  final String? notes;
  final List<ChecklistResult> results;

  const HandoverInfo({
    this.handoverId,
    required this.stage,
    this.status = HandoverStatus.pending,
    this.performedBy,
    this.approvedBy,
    this.performerName,
    this.approverName,
    this.performedAt,
    this.approvedAt,
    this.notes,
    this.results = const [],
  });

  HandoverInfo copyWith({
    String? handoverId,
    HandoverStage? stage,
    HandoverStatus? status,
    String? performedBy,
    String? approvedBy,
    String? performerName,
    String? approverName,
    DateTime? performedAt,
    DateTime? approvedAt,
    String? notes,
    List<ChecklistResult>? results,
  }) => HandoverInfo(
    handoverId: handoverId ?? this.handoverId,
    stage: stage ?? this.stage,
    status: status ?? this.status,
    performedBy: performedBy ?? this.performedBy,
    approvedBy: approvedBy ?? this.approvedBy,
    performerName: performerName ?? this.performerName,
    approverName: approverName ?? this.approverName,
    performedAt: performedAt ?? this.performedAt,
    approvedAt: approvedAt ?? this.approvedAt,
    notes: notes ?? this.notes,
    results: results ?? this.results,
  );

  factory HandoverInfo.fromMap(Map<String, dynamic> m) => HandoverInfo(
    handoverId: m['handover_id']?.toString(),
    stage: HandoverStageLabel.fromDb(m['stage'].toString()),
    status: parseStatus(m['status'].toString()),
    performedBy: m['performed_by']?.toString(),
    approvedBy: m['approved_by']?.toString(),
    performerName: m['performer_name']?.toString(),
    approverName: m['approver_name']?.toString(),
    performedAt: m['performed_at'] != null
        ? DateTime.tryParse(m['performed_at'].toString())
        : null,
    approvedAt: m['approved_at'] != null
        ? DateTime.tryParse(m['approved_at'].toString())
        : null,
    notes: m['notes']?.toString(),
  );

  static HandoverStatus parseStatus(String s) {
    switch (s) {
      case 'in_progress':
        return HandoverStatus.inProgress;
      case 'passed':
        return HandoverStatus.passed;
      case 'failed':
        return HandoverStatus.failed;
      case 'approved':
        return HandoverStatus.approved;
      default:
        return HandoverStatus.pending;
    }
  }

  String get statusLabel {
    switch (status) {
      case HandoverStatus.pending:
        return 'รอดำเนินการ';
      case HandoverStatus.inProgress:
        return 'กำลังดำเนินการ';
      case HandoverStatus.passed:
        return 'ผ่าน';
      case HandoverStatus.failed:
        return 'ไม่ผ่าน';
      case HandoverStatus.approved:
        return 'อนุมัติแล้ว';
    }
  }
}

class ChecklistResult {
  final String? resultId;
  final String itemName;
  final String? result; // pass | fail | na
  final String? actualValue;
  final String? remarks;

  const ChecklistResult({
    this.resultId,
    required this.itemName,
    this.result,
    this.actualValue,
    this.remarks,
  });

  factory ChecklistResult.fromMap(Map<String, dynamic> m) => ChecklistResult(
    resultId: m['result_id']?.toString(),
    itemName: m['item_name']?.toString() ?? '',
    result: m['result']?.toString(),
    actualValue: m['actual_value']?.toString(),
    remarks: m['remarks']?.toString(),
  );
}

class MachineBomItem {
  final String mapId;
  final String machineId;
  final String partId;
  final String partCode;
  final String partName;
  final int quantity;
  final int quantityOnHand;
  final String? notes;

  const MachineBomItem({
    required this.mapId,
    required this.machineId,
    required this.partId,
    required this.partCode,
    required this.partName,
    required this.quantity,
    required this.quantityOnHand,
    this.notes,
  });

  factory MachineBomItem.fromMap(Map<String, dynamic> m) {
    return MachineBomItem(
      mapId: m['map_id'] as String,
      machineId: m['machine_id'] as String,
      partId: m['part_id'] as String,
      partCode: m['part_code'] as String,
      partName: m['part_name'] as String,
      quantity: m['quantity'] as int? ?? 1,
      quantityOnHand: m['quantity_on_hand'] as int? ?? 0,
      notes: m['notes'] as String?,
    );
  }
}

class MachineToolItem {
  final String mapId;
  final String machineId;
  final String toolId;
  final String toolCode;
  final String toolName;
  final String? category;
  final String status;
  final int quantity;
  final String? notes;

  const MachineToolItem({
    required this.mapId,
    required this.machineId,
    required this.toolId,
    required this.toolCode,
    required this.toolName,
    this.category,
    this.status = 'available',
    required this.quantity,
    this.notes,
  });

  factory MachineToolItem.fromMap(Map<String, dynamic> m) {
    return MachineToolItem(
      mapId: m['map_id'] as String,
      machineId: m['machine_id'] as String,
      toolId: m['tool_id'] as String,
      toolCode: m['tool_code'] as String? ?? '',
      toolName: m['tool_name'] as String? ?? '',
      category: m['category'] as String?,
      status: m['status'] as String? ?? 'available',
      quantity: m['quantity'] as int? ?? 1,
      notes: m['notes'] as String?,
    );
  }
}

class MachineRepairRecord {
  final String woId;
  final String woNo;
  final String title;
  final String? description;
  final String? failureSymptom;
  final String? actionTaken;
  final String status;
  final String priority;
  final DateTime? createdAt;
  final DateTime? completedAt;
  final DateTime? actualStartTime;
  final DateTime? actualEndTime;
  final int downtimeMinutes;
  final double totalCost;
  final double partsCost;
  final double laborCost;
  final String? reportedByName;
  final String? assignedToName;
  final String? failureType;
  final String? causeCategory;
  final String? rootCause;
  final String? why1;
  final String? why2;
  final String? why3;
  final String? why4;
  final String? why5;
  final String? outsourceVendorName;
  final String? outsourceRepairDetails;
  final List<Map<String, dynamic>> partsUsed;

  const MachineRepairRecord({
    required this.woId,
    required this.woNo,
    required this.title,
    this.description,
    this.failureSymptom,
    this.actionTaken,
    required this.status,
    required this.priority,
    this.createdAt,
    this.completedAt,
    this.actualStartTime,
    this.actualEndTime,
    this.downtimeMinutes = 0,
    this.totalCost = 0.0,
    this.partsCost = 0.0,
    this.laborCost = 0.0,
    this.reportedByName,
    this.assignedToName,
    this.failureType,
    this.causeCategory,
    this.rootCause,
    this.why1,
    this.why2,
    this.why3,
    this.why4,
    this.why5,
    this.outsourceVendorName,
    this.outsourceRepairDetails,
    this.partsUsed = const [],
  });

  factory MachineRepairRecord.fromMap(
    Map<String, dynamic> map, {
    List<Map<String, dynamic>>? parts,
  }) {
    List<Map<String, dynamic>> partsList = parts ?? [];
    if (partsList.isEmpty && map['parts_used_json'] != null) {
      try {
        final decoded = jsonDecode(map['parts_used_json'].toString());
        if (decoded is List) {
          partsList = decoded.whereType<Map<String, dynamic>>().toList();
        }
      } catch (_) {}
    }

    final startedAt = map['started_at'] != null
        ? DateTime.tryParse(map['started_at'].toString())
        : (map['actual_start_time'] != null
              ? DateTime.tryParse(map['actual_start_time'].toString())
              : null);
    final completedAt = map['completed_at'] != null
        ? DateTime.tryParse(map['completed_at'].toString())
        : (map['actual_end_time'] != null
              ? DateTime.tryParse(map['actual_end_time'].toString())
              : null);

    int downtime = (map['downtime_minutes'] as num?)?.toInt() ?? 0;
    if (downtime == 0) {
      if (map['actual_hours'] != null) {
        downtime = ((map['actual_hours'] as num).toDouble() * 60).round();
      } else if (startedAt != null && completedAt != null) {
        downtime = completedAt.difference(startedAt).inMinutes;
      }
    }

    double totalCost = (map['total_cost'] as num?)?.toDouble() ?? 0.0;
    if (totalCost == 0.0 && partsList.isNotEmpty) {
      for (final p in partsList) {
        final q = (p['quantity'] as num?)?.toDouble() ?? 1.0;
        final c =
            (p['unit_cost'] as num?)?.toDouble() ??
            (p['unit_price'] as num?)?.toDouble() ??
            0.0;
        totalCost += (q * c);
      }
    }

    final rootCause = (map['root_cause'] as String?)?.isNotEmpty == true
        ? map['root_cause'] as String?
        : map['failure_cause'] as String?;

    return MachineRepairRecord(
      woId: map['wo_id'] as String? ?? '',
      woNo: map['wo_no'] as String? ?? '',
      title: map['title'] as String? ?? '',
      description: map['description'] as String?,
      failureSymptom: map['failure_symptom'] as String?,
      actionTaken:
          map['action_taken'] as String? ??
          map['correction_action'] as String? ??
          map['preventive_action'] as String?,
      status: map['status'] as String? ?? 'pending',
      priority: map['priority'] as String? ?? 'normal',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      completedAt: completedAt,
      actualStartTime: startedAt,
      actualEndTime: completedAt,
      downtimeMinutes: downtime,
      totalCost: totalCost,
      partsCost: (map['parts_cost'] as num?)?.toDouble() ?? 0.0,
      laborCost: (map['labor_cost'] as num?)?.toDouble() ?? 0.0,
      reportedByName: map['reported_by_name'] as String?,
      assignedToName: map['assigned_to_name'] as String?,
      failureType: map['failure_type'] as String?,
      causeCategory: map['cause_category'] as String?,
      rootCause: rootCause,
      why1: map['why_1'] as String?,
      why2: map['why_2'] as String?,
      why3: map['why_3'] as String?,
      why4: map['why_4'] as String?,
      why5: map['why_5'] as String?,
      outsourceVendorName: map['outsource_vendor_name'] as String?,
      outsourceRepairDetails: map['outsource_repair_details'] as String?,
      partsUsed: partsList,
    );
  }
}
