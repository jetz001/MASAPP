import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/db_helper.dart';
import '../../core/auth/auth_service.dart';
import '../../core/audit/audit_service.dart';
import 'work_order_models.dart';
import '../machine_intake/machine_provider.dart';
import 'package:intl/intl.dart';

/// Repository for work order operations
class WorkOrderRepository {
  static const uuid = Uuid();

  /// Get next work order number
  Future<String> getNextWoNo() async {
    try {
      final result = await DbHelper.queryOne(
        'SELECT MAX(CAST(SUBSTR(wo_no, -4) AS INTEGER)) as max_no FROM work_orders',
      );
      final maxNo = (result?['max_no'] as num?)?.toInt() ?? 0;
      final nextNo = (maxNo + 1).toString().padLeft(5, '0');
      return 'WO-${DateTime.now().year}-$nextNo';
    } catch (e) {
      return 'WO-${DateTime.now().year}-00001';
    }
  }

  /// Create new work order
  Future<String> createWorkOrder({
    required String machineId,
    required String machineNo,
    required String? description,
    required String? failureSymptom,
    required WorkOrderPriority priority,
    double? estimatedHours,
    List<String>? attachments,
  }) async {
    final woId = uuid.v4();
    final woNo = await getNextWoNo();
    final userId = AuthService.currentUser?.userId ?? 'SYSTEM';
    final now = DateTime.now().toIso8601String();

    // 1. Get/Create Machine Snapshot (Clone to Dummy)
    String? snapshotId;
    if (machineId.isNotEmpty) {
      snapshotId = await MachineRepository().getOrCreateSnapshot(machineId);
    }

    // Process attachments
    List<String>? savedAttachments;
    if (attachments != null && attachments.isNotEmpty) {
      savedAttachments = [];
      final baseDir = Directory(p.join(File(DbHelper.dbPath).parent.path, 'attachments', woId));
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }
      for (final path in attachments) {
        final file = File(path);
        if (await file.exists()) {
          final fileName = p.basename(path);
          final destPath = p.join(baseDir.path, fileName);
          await file.copy(destPath);
          savedAttachments.add(destPath);
        }
      }
    }

    await DbHelper.transaction((tx) async {
      await DbHelper.txExecute(
        tx,
        '''INSERT INTO work_orders
           (wo_id, wo_no, machine_id, snapshot_id, title, description, failure_symptom,
            priority, status, created_by, created_at, updated_at, attachments)
           VALUES (@wo_id, @wo_no, @machine_id, @snapshot_id, @title, @description, @failure_symptom,
                   @priority, 'pending', @created_by, @created_at, @updated_at, @attachments)''',
        params: {
          'wo_id': woId,
          'wo_no': woNo,
          'machine_id': machineId.isNotEmpty ? machineId : null,
          'snapshot_id': snapshotId,
          'title': description ?? 'Untitled',
          'description': description,
          'failure_symptom': failureSymptom,
          'priority': priority.dbValue,
          'created_by': userId,
          'created_at': now,
          'updated_at': now,
          'attachments': savedAttachments != null ? jsonEncode(savedAttachments) : null,
        },
      );
    });

    // Audit log
    await AuditService.logInsert('work_orders', woId, {
      'wo_no': woNo,
      'machine_id': machineId,
      'status': 'pending',
      'priority': priority.label,
    });

    return woId;
  }

  /// Update attachments for a work order
  Future<bool> updateAttachments(String woId, List<String> filePaths) async {
    try {
      final baseDir = Directory(p.join(File(DbHelper.dbPath).parent.path, 'attachments', woId));
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }
      
      final savedAttachments = <String>[];
      for (final path in filePaths) {
        if (path.startsWith(baseDir.path)) {
          // Already saved in attachments dir
          savedAttachments.add(path);
        } else {
          // New file
          final ext = p.extension(path);
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4()}$ext';
          final destPath = p.join(baseDir.path, fileName);
          await File(path).copy(destPath);
          savedAttachments.add(destPath);
        }
      }
      
      await DbHelper.execute(
        'UPDATE work_orders SET attachments = @attachments, updated_at = @updated_at WHERE wo_id = @wo_id',
        params: {
          'wo_id': woId,
          'attachments': jsonEncode(savedAttachments),
          'updated_at': DateTime.now().toIso8601String(),
        },
      );
      return true;
    } catch (e) {
      print('Error updating attachments: $e');
      return false;
    }
  }

  /// Get work order by ID with related data
  Future<WorkOrder?> getWorkOrder(String woId) async {
    try {
      final row = await DbHelper.queryOne(
        '''SELECT wo.*, s.machine_no, s.brand as machine_brand, s.model as machine_model,
                  u1.full_name as reported_by_name, u2.full_name as assigned_to_name, u3.full_name as approved_by_name
           FROM work_orders wo
           LEFT JOIN machine_snapshots s ON s.snapshot_id = wo.snapshot_id
           LEFT JOIN users u1 ON u1.user_id = wo.created_by
           LEFT JOIN users u2 ON u2.user_id = wo.assigned_to
           LEFT JOIN users u3 ON u3.user_id = wo.approved_by
           WHERE wo.wo_id = @wo_id''',
        params: {'wo_id': woId},
      );

      if (row == null) return null;

      // Get labor entries
      final laborRows = await DbHelper.query(
        '''SELECT * FROM work_order_labor
           WHERE wo_id = @wo_id
           ORDER BY start_time''',
        params: {'wo_id': woId},
      );
      final labors = laborRows.map((r) => WorkOrderLabor.fromMap(r)).toList();

      // Get RCA if exists
      final rcaRow = await DbHelper.queryOne(
        'SELECT * FROM work_order_rca WHERE wo_id = @wo_id',
        params: {'wo_id': woId},
      );
      final rca = rcaRow != null ? RootCauseAnalysis.fromMap(rcaRow) : null;

      // Get Outsource if exists
      final outsourceRow = await DbHelper.queryOne(
        '''SELECT o.*, v.name as vendor_name_from_db 
           FROM work_order_outsource o 
           LEFT JOIN suppliers v ON o.vendor_name = v.supplier_id OR o.vendor_name = v.name
           WHERE o.wo_id = @wo_id
           ORDER BY o.created_at DESC LIMIT 1''',
        params: {'wo_id': woId},
      );
      WorkOrderOutsource? outsource;
      if (outsourceRow != null) {
         final map = Map<String, dynamic>.from(outsourceRow);
         // Ensure vendor name resolves correctly if it was storing ID vs name
         if (map['vendor_name_from_db'] != null) {
           map['vendor_name'] = map['vendor_name_from_db'];
         }
         outsource = WorkOrderOutsource.fromMap(map);
      }

      return WorkOrder.fromMap(row).copyWith(
        laborEntries: labors, 
        rca: rca,
        outsource: outsource,
      );
    } catch (e, stack) {
      print('ERROR in getWorkOrder: $e\n$stack');
      return null;
    }
  }

  /// Get work orders list with filters
  Future<List<WorkOrder>> listWorkOrders({
    String? status,
    String? machineId,
    String? assignedTo,
    bool activeOnly = true,
    int limit = 100,
  }) async {
    try {
      final where = <String>['1=1'];
      final params = <String, dynamic>{};

      if (status != null) {
        where.add('wo.status = @status');
        params['status'] = status;
      }
      if (machineId != null) {
        where.add('wo.machine_id = @machine_id');
        params['machine_id'] = machineId;
      }
      if (assignedTo != null) {
        where.add('wo.assigned_to = @assigned_to');
        params['assigned_to'] = assignedTo;
      }

      final rows = await DbHelper.query(
        '''SELECT wo.*, s.machine_no, s.brand, s.model,
                  u1.full_name as reported_by_name, u2.full_name as assigned_to_name, u3.full_name as approved_by_name
           FROM work_orders wo
           LEFT JOIN machine_snapshots s ON s.snapshot_id = wo.snapshot_id
           LEFT JOIN users u1 ON u1.user_id = wo.created_by
           LEFT JOIN users u2 ON u2.user_id = wo.assigned_to
           LEFT JOIN users u3 ON u3.user_id = wo.approved_by
           WHERE ${where.join(' AND ')}
           ORDER BY wo.created_at DESC
           LIMIT @limit''',
        params: {...params, 'limit': limit},
      );

      return rows.map((r) => WorkOrder.fromMap(r)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Approve work order
  Future<bool> approveWorkOrder(String woId, {String? approvedBy}) async {
    try {
      final userId = approvedBy ?? AuthService.currentUser?.userId;
      if (userId == null) return false;

      final now = DateTime.now().toIso8601String();
      await DbHelper.execute(
        '''UPDATE work_orders
           SET status = 'approved', approved_by = @approved_by, approved_at = @approved_at,
               updated_at = @updated_at
           WHERE wo_id = @wo_id''',
        params: {
          'wo_id': woId,
          'approved_by': userId,
          'approved_at': now,
          'updated_at': now,
        },
      );

      await AuditService.logUpdate(
        'work_orders',
        woId,
        {'status': 'pending'},
        {'status': 'approved'},
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Reject work order
  Future<bool> rejectWorkOrder(String woId) async {
    try {
      final now = DateTime.now().toIso8601String();
      await DbHelper.execute(
        '''UPDATE work_orders
           SET status = 'rejected', updated_at = @updated_at
           WHERE wo_id = @wo_id''',
        params: {
          'wo_id': woId,
          'updated_at': now,
        },
      );
      
      await AuditService.logUpdate(
        'work_orders',
        woId,
        {'status': 'pending'},
        {'status': 'rejected'},
      );

      return true;
    } catch (e) {
      print('Error rejecting work order: $e');
      return false;
    }
  }

  /// Assign work order to technician
  Future<bool> assignWorkOrder(String woId, String technicianId) async {
    try {
      final now = DateTime.now().toIso8601String();
      await DbHelper.execute(
        '''UPDATE work_orders
           SET assigned_to = @tech_id, updated_at = @updated_at
           WHERE wo_id = @wo_id''',
        params: {'wo_id': woId, 'tech_id': technicianId, 'updated_at': now},
      );

      await AuditService.logUpdate('work_orders', woId, {}, {
        'assigned_to': technicianId,
      });

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Start work on work order
  Future<bool> startWorkOrder(String woId) async {
    return await DbHelper.transaction((tx) async {
      try {
        final now = DateTime.now().toIso8601String();
        
        // 1. Update work order status
        await DbHelper.txExecute(
          tx,
          '''UPDATE work_orders
             SET status = 'in_progress', started_at = @started_at, updated_at = @updated_at
             WHERE wo_id = @wo_id''',
          params: {'wo_id': woId, 'started_at': now, 'updated_at': now},
        );

        // 2. Sync machine status to 'breakdown' if this was a repair job
        // (For PM jobs, it might be 'pm', but 'breakdown' is the priority visual)
        await DbHelper.txExecute(
          tx,
          '''UPDATE machines
             SET status = 'breakdown', updated_at = @updated_at
             WHERE machine_id = (SELECT machine_id FROM work_orders WHERE wo_id = @wo_id)''',
          params: {'wo_id': woId, 'updated_at': now},
        );

        return true;
      } catch (e, stack) {
        print('ERROR in startWorkOrder: $e\n$stack');
        return false;
      }
    });
  }

  /// Complete work order and require RCA if breakdown
  Future<bool> completeWorkOrder(
    String woId, {
    required String closureNotes,
    required double actualHours,
    required bool isBreakdown,
  }) async {
    return await DbHelper.transaction((tx) async {
      try {
        final now = DateTime.now().toIso8601String();

        // Update work order
        await DbHelper.txExecute(
          tx,
          '''UPDATE work_orders
             SET status = @status, completed_at = @completed_at,
                 actual_hours = @actual_hours, closure_notes = @closure_notes,
                 updated_at = @updated_at
             WHERE wo_id = @wo_id''',
          params: {
            'wo_id': woId,
            'status': isBreakdown
                ? 'completed'
                : 'completed', // Breakdown WO requires RCA
            'completed_at': now,
            'actual_hours': actualHours,
            'closure_notes': closureNotes,
            'updated_at': now,
          },
        );

        // If breakdown, create empty RCA template
        if (isBreakdown) {
          await DbHelper.txExecute(
            tx,
            '''INSERT OR IGNORE INTO work_order_rca
               (rca_id, wo_id, why_1, why_2, why_3, why_4, why_5, root_cause)
               VALUES (@rca_id, @wo_id, '', '', '', '', '', 'N/A')''',
            params: {'rca_id': uuid.v4(), 'wo_id': woId},
          );
        }

        // 3. Sync machine status back to 'normal'
        await DbHelper.txExecute(
          tx,
          '''UPDATE machines
             SET status = 'normal', updated_at = @updated_at
             WHERE machine_id = (SELECT machine_id FROM work_orders WHERE wo_id = @wo_id)''',
          params: {'wo_id': woId, 'updated_at': now},
        );

        return true;
      } catch (e) {
        return false;
      }
    });
  }

  /// Mark work order as outsourced and save details
  Future<bool> outsourceWorkOrder({
    required String woId,
    required String vendorName,
    required String repairDetails,
    required String replacedParts,
    required String rootCause,
    String? gatePassNo,
    DateTime? expectedReturnDate,
  }) async {
    return await DbHelper.transaction((tx) async {
      try {
        final userId = AuthService.currentUser?.userId ?? 'SYSTEM';
        final now = DateTime.now().toIso8601String();
        const uuidInstance = Uuid();

        // 0. Upsert RCA
        final existingRca = await DbHelper.txQueryOne(tx, 'SELECT rca_id FROM work_order_rca WHERE wo_id = @id', params: {'id': woId});
        if (existingRca != null) {
          await DbHelper.txExecute(
            tx,
            'UPDATE work_order_rca SET root_cause = @rc, updated_at = @updated_at WHERE wo_id = @id',
            params: {'rc': rootCause, 'updated_at': now, 'id': woId},
          );
        } else {
          await DbHelper.txExecute(
            tx,
            '''INSERT INTO work_order_rca
               (rca_id, wo_id, why_1, why_2, why_3, why_4, why_5, root_cause, created_at, updated_at)
               VALUES (@rca_id, @wo_id, '', '', '', '', '', @rc, @created_at, @updated_at)''',
            params: {'rca_id': uuidInstance.v4(), 'wo_id': woId, 'rc': rootCause, 'created_at': now, 'updated_at': now},
          );
        }

        // 1. Insert outsource record
        await DbHelper.txExecute(
          tx,
          '''INSERT INTO work_order_outsource 
             (outsource_id, wo_id, vendor_name, repair_details, replaced_parts, 
              gate_pass_no, expected_return_date, created_by, created_at)
             VALUES (@id, @wo_id, @vendor, @repair, @parts, @gate_pass, @expected_date, @created_by, @created_at)''',
          params: {
            'id': uuidInstance.v4(),
            'wo_id': woId,
            'vendor': vendorName,
            'repair': repairDetails,
            'parts': replacedParts,
            'gate_pass': gatePassNo ?? '',
            'expected_date': expectedReturnDate?.toIso8601String(),
            'created_by': userId,
            'created_at': now,
          },
        );

        // 2. Update status
        await DbHelper.txExecute(
          tx,
          '''UPDATE work_orders
             SET status = 'outsourced', updated_at = @updated_at
             WHERE wo_id = @wo_id''',
          params: {'wo_id': woId, 'updated_at': now},
        );

        return true;
      } catch (e) {
        print('Error in outsourceWorkOrder: $e');
        return false;
      }
    });
  }

  /// Accept outsourced work order
  Future<bool> acceptOutsourceWorkOrder({
    required String woId,
    required DateTime actualReturnDate,
    required String notes,
    required bool isPassed,
  }) async {
    return await DbHelper.transaction((tx) async {
      try {
        final userId = AuthService.currentUser?.userId ?? 'SYSTEM';
        final now = DateTime.now().toIso8601String();

        final latestOutsource = await DbHelper.txQueryOne(tx, 'SELECT * FROM work_order_outsource WHERE wo_id = @wo_id ORDER BY created_at DESC LIMIT 1', params: {'wo_id': woId});
        if (latestOutsource != null) {
          final existingNotes = latestOutsource['notes'] as String? ?? '';
          final passText = isPassed ? "ผ่าน" : "ตีกลับ";
          final dateStr = DateFormat('dd/MM/yyyy').format(actualReturnDate);
          final formattedNote = '[$passText][$dateStr] $notes';
          final appendedNotes = existingNotes.isNotEmpty ? '$existingNotes\n$formattedNote' : formattedNote;

          await DbHelper.txExecute(
            tx,
            '''UPDATE work_order_outsource
               SET actual_return_date = @actual_date, inspector_id = @inspector_id, notes = @notes, is_passed_inspection = @is_passed
               WHERE outsource_id = @outsource_id''',
            params: {
              'actual_date': actualReturnDate.toIso8601String(),
              'inspector_id': userId,
              'notes': appendedNotes,
              'is_passed': isPassed ? 1 : 0,
              'outsource_id': latestOutsource['outsource_id'],
            },
          );
        }

        // 2. Update status (if passed -> completed, if not -> outsourced)
        final newStatus = isPassed ? 'completed' : 'outsourced';
        final completedAtQuery = isPassed ? ", completed_at = @actual_date" : "";
        
        // If not passed, we append the failure notes to closure_notes or just let them use failure_symptom.
        // Changing status back to outsourced so they can inspect again when it comes back.
        await DbHelper.txExecute(
          tx,
          '''UPDATE work_orders
             SET status = @status, updated_at = @updated_at$completedAtQuery
             WHERE wo_id = @wo_id''',
          params: {
             'wo_id': woId, 
             'updated_at': now, 
             'status': newStatus,
             if (isPassed) 'actual_date': actualReturnDate.toIso8601String(),
          },
        );

        return true;
      } catch (e) {
        print('Error in acceptOutsourceWorkOrder: $e');
        return false;
      }
    });
  }

  /// Record labor entry (time tracking)
  Future<bool> addLaborEntry({
    required String woId,
    required DateTime startTime,
    required DateTime endTime,
    String? taskDescription,
  }) async {
    try {
      final userId = AuthService.currentUser?.userId;
      if (userId == null) return false;

      final hours = endTime.difference(startTime).inMinutes / 60.0;
      const uuidInstance = Uuid();

      await DbHelper.execute(
        '''INSERT INTO work_order_labor
           (labor_id, wo_id, technician_id, start_time, end_time, hours, task_description)
           VALUES (@labor_id, @wo_id, @tech_id, @start_time, @end_time, @hours, @task_desc)''',
        params: {
          'labor_id': uuidInstance.v4(),
          'wo_id': woId,
          'tech_id': userId,
          'start_time': startTime.toIso8601String(),
          'end_time': endTime.toIso8601String(),
          'hours': hours,
          'task_desc': taskDescription,
        },
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Save RCA (Root Cause Analysis)
  Future<bool> saveRCA({
    required String woId,
    required String why1,
    required String why2,
    required String why3,
    required String why4,
    required String why5,
    String? rootCause,
    String? correctionAction,
    String? preventiveAction,
  }) async {
    try {
      final userId = AuthService.currentUser?.userId ?? 'SYSTEM';
      final now = DateTime.now().toIso8601String();
      const uuid = Uuid();

      final existingRca = await DbHelper.queryOne('SELECT rca_id FROM work_order_rca WHERE wo_id = @id', params: {'id': woId});

      if (existingRca != null) {
        await DbHelper.execute(
          '''UPDATE work_order_rca
             SET why_1 = @why_1, why_2 = @why_2, why_3 = @why_3, why_4 = @why_4, why_5 = @why_5,
                 root_cause = @root_cause, correction_action = @correction_action,
                 preventive_action = @preventive_action, analyzed_by = @analyzed_by,
                 analyzed_at = @analyzed_at, updated_at = @updated_at
             WHERE wo_id = @wo_id''',
          params: {
            'wo_id': woId,
            'why_1': why1,
            'why_2': why2,
            'why_3': why3,
            'why_4': why4,
            'why_5': why5,
            'root_cause': rootCause ?? 'N/A',
            'correction_action': correctionAction,
            'preventive_action': preventiveAction,
            'analyzed_by': userId,
            'analyzed_at': now,
            'updated_at': now,
          },
        );
      } else {
        await DbHelper.execute(
          '''INSERT INTO work_order_rca
             (rca_id, wo_id, why_1, why_2, why_3, why_4, why_5, root_cause, 
              correction_action, preventive_action, analyzed_by, analyzed_at, created_at, updated_at)
             VALUES (@rca_id, @wo_id, @why_1, @why_2, @why_3, @why_4, @why_5, @root_cause,
                     @correction_action, @preventive_action, @analyzed_by, @analyzed_at, @created_at, @updated_at)''',
          params: {
            'rca_id': uuid.v4(),
            'wo_id': woId,
            'why_1': why1,
            'why_2': why2,
            'why_3': why3,
            'why_4': why4,
            'why_5': why5,
            'root_cause': rootCause ?? 'N/A',
            'correction_action': correctionAction,
            'preventive_action': preventiveAction,
            'analyzed_by': userId,
            'analyzed_at': now,
            'created_at': now,
            'updated_at': now,
          },
        );
      }

      return true;
    } catch (e) {
      print('Error saving RCA: $e');
      return false;
    }
  }

  /// Consume a spare part for a work order
  Future<bool> consumeSparePart({
    required String woId,
    required String partId,
    required int quantity,
    String? remarks,
  }) async {
    return await DbHelper.transaction((tx) async {
      try {
        final userId = AuthService.currentUser?.userId ?? 'SYSTEM';
        final now = DateTime.now().toIso8601String();
        final transId = 'TXN-${uuid.v4().substring(0, 8)}';

        // 1. Record transaction
        await DbHelper.txExecute(
          tx,
          '''INSERT INTO spare_parts_transactions
             (trans_id, part_id, trans_type, quantity, reference_id, trans_by, remarks, trans_date)
             VALUES (@tid, @pid, 'out', @qty, @wo_id, @uid, @remarks, @date)''',
          params: {
            'tid': transId,
            'pid': partId,
            'qty': -quantity,
            'wo_id': woId,
            'uid': userId,
            'remarks': remarks ?? 'Used in Work Order',
            'date': now,
          },
        );

        // 2. Update inventory
        await DbHelper.txExecute(
          tx,
          '''UPDATE spare_parts_inventory
             SET quantity_on_hand = quantity_on_hand - @qty,
                 updated_at = @now
             WHERE part_id = @pid''',
          params: {
            'pid': partId,
            'qty': quantity,
            'now': now,
          },
        );

        return true;
      } catch (e) {
        return false;
      }
    });
  }

  Future<bool> updateRepairLog(String woId, String rootCause, String closureNotes) async {
    try {
      final now = DateTime.now().toIso8601String();
      
      await DbHelper.transaction((tx) async {
        // Update RCA
        final existingRca = await DbHelper.txQuery(tx, 'SELECT rca_id FROM work_order_rca WHERE wo_id = @id', params: {'id': woId});
        if (existingRca.isNotEmpty) {
          await DbHelper.txExecute(tx, 
            'UPDATE work_order_rca SET root_cause = @rc, updated_at = @now WHERE wo_id = @id', 
            params: {'rc': rootCause, 'now': now, 'id': woId});
        } else {
          await DbHelper.txExecute(tx,
            '''INSERT INTO work_order_rca (rca_id, wo_id, root_cause, created_at, updated_at) 
               VALUES (@rid, @wid, @rc, @now, @now)''',
            params: {'rid': const Uuid().v4(), 'wid': woId, 'rc': rootCause, 'now': now});
        }
        
        // Update WO closure notes
        await DbHelper.txExecute(tx, 
          'UPDATE work_orders SET closure_notes = @cn, updated_at = @now WHERE wo_id = @id', 
          params: {'cn': closureNotes, 'now': now, 'id': woId});
      });
      return true;
    } catch (e) {
      print('Error updating repair log: $e');
      return false;
    }
  }

  Future<bool> updateOutsourceInfo(String outsourceId, String repairDetails, DateTime? expectedReturnDate, String? notes) async {
    try {
      final now = DateTime.now().toIso8601String();
      await DbHelper.execute(
        '''UPDATE work_order_outsource 
           SET repair_details = @details, 
               expected_return_date = @date, 
               notes = @notes, 
               updated_at = @now 
           WHERE outsource_id = @id''',
        params: {
          'details': repairDetails,
          'date': expectedReturnDate?.toIso8601String(),
          'notes': notes,
          'now': now,
          'id': outsourceId,
        }
      );
      return true;
    } catch (e) {
      print('Error updating outsource info: $e');
      return false;
    }
  }
}

/// Riverpod providers

final workOrderRepositoryProvider = Provider((ref) => WorkOrderRepository());

/// Work orders list
final workOrdersListProvider =
    FutureProvider.family<
      List<WorkOrder>,
      ({String? status, String? machineId, String? assignedTo, bool activeOnly})
    >((ref, params) async {
      final repo = ref.watch(workOrderRepositoryProvider);
      return await repo.listWorkOrders(
        status: params.status,
        machineId: params.machineId,
        assignedTo: params.assignedTo,
        activeOnly: params.activeOnly,
      );
    });

/// Single work order
final workOrderProvider = FutureProvider.family<WorkOrder?, String>((
  ref,
  woId,
) async {
  final repo = ref.watch(workOrderRepositoryProvider);
  return await repo.getWorkOrder(woId);
});

/// Pending work orders count
final pendingWorkOrdersCountProvider = FutureProvider((ref) async {
  final repo = ref.watch(workOrderRepositoryProvider);
  final workOrders = await repo.listWorkOrders(status: 'pending');
  return workOrders.length;
});

// ─────────────────────────────────────────────────────────────────────────────
// Filter model + provider for list screen
// ─────────────────────────────────────────────────────────────────────────────

class WorkOrderFilter {
  final String? status;
  final String? search;
  final String? machineId;

  const WorkOrderFilter({this.status, this.search, this.machineId});

  @override
  bool operator ==(Object other) =>
      other is WorkOrderFilter &&
      other.status == status &&
      other.search == search &&
      other.machineId == machineId;

  @override
  int get hashCode => Object.hash(status, search, machineId);
}

final workOrderListProvider =
    FutureProvider.family<List<WorkOrder>, WorkOrderFilter>(
        (ref, filter) async {
  try {
    final where = <String>['1=1'];
    final params = <String, dynamic>{};

    if (filter.status != null) {
      if (filter.status!.contains(',')) {
        final statuses = filter.status!.split(',');
        final placeholders = List.generate(statuses.length, (i) => '@status$i').join(', ');
        where.add('wo.status IN ($placeholders)');
        for (int i = 0; i < statuses.length; i++) {
          params['status$i'] = statuses[i];
        }
      } else {
        where.add('wo.status = @status');
        params['status'] = filter.status;
      }
    }
    if (filter.machineId != null) {
      where.add('wo.machine_id = @machine_id');
      params['machine_id'] = filter.machineId;
    }
    if (filter.search != null && filter.search!.isNotEmpty) {
      where.add(
          '(wo.wo_no LIKE @search OR wo.title LIKE @search OR s.machine_no LIKE @search)');
      params['search'] = '%${filter.search}%';
    }

    final rows = await DbHelper.query(
      '''SELECT wo.wo_id, wo.wo_no, wo.machine_id, wo.snapshot_id, wo.status, wo.priority,
                wo.title, wo.description, wo.failure_symptom,
                wo.created_by, wo.assigned_to,
                wo.approved_by, wo.estimated_hours, wo.actual_hours,
                wo.started_at, wo.completed_at, wo.approved_at,
                wo.created_at, wo.updated_at,
                s.machine_no, s.brand as machine_brand, s.model as machine_model,
                u1.full_name as reported_by_name,
                u2.full_name as assigned_to_name
         FROM work_orders wo
         LEFT JOIN machine_snapshots s ON s.snapshot_id = wo.snapshot_id
         LEFT JOIN users u1 ON u1.user_id = wo.created_by
         LEFT JOIN users u2 ON u2.user_id = wo.assigned_to
         WHERE ${where.join(' AND ')}
         ORDER BY wo.created_at DESC
         LIMIT 200''',
      params: params,
    );

    return rows.map((r) {
      // Ensure required fields default gracefully
      final map = {
        ...r,
        'reported_at': r['created_at'] ?? DateTime.now().toIso8601String(),
      };
      return WorkOrder.fromMap(map);
    }).toList();
  } catch (e) {
    return [];
  }
});
