/// Machine Intake domain models
library;

import 'package:flutter/material.dart';

enum MachineStatus { normal, breakdown, pm, am, offline, decommissioned }

extension MachineStatusColor on MachineStatus {
  Color get color {
    switch (this) {
      case MachineStatus.normal: return Colors.green;
      case MachineStatus.breakdown: return Colors.red;
      case MachineStatus.pm: return Colors.orange;
      case MachineStatus.am: return Colors.blue;
      case MachineStatus.offline: return Colors.grey;
      case MachineStatus.decommissioned: return Colors.black54;
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
  });

  factory MachineSpecs.fromMap(Map<String, dynamic> m) => MachineSpecs(
    powerKw: (m['power_kw'] as num?)?.toDouble(),
    voltageV: (m['voltage_v'] as num?)?.toDouble(),
    currentA: (m['current_a'] as num?)?.toDouble(),
    frequencyHz: (m['frequency_hz'] as num?)?.toDouble(),
    capacity: (m['capacity'] as num?)?.toDouble(),
    capacityUnit: m['capacity_unit']?.toString(),
    weightKg: (m['weight_kg'] as num?)?.toDouble(),
    dimLengthMm: (m['dim_length_mm'] as num?)?.toDouble(),
    dimWidthMm: (m['dim_width_mm'] as num?)?.toDouble(),
    dimHeightMm: (m['dim_height_mm'] as num?)?.toDouble(),
    rpm: (m['rpm'] as num?)?.toDouble(),
  );
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
  }) =>
      HandoverInfo(
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
