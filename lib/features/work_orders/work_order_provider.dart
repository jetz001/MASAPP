import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/db_helper.dart';
import '../../core/auth/auth_service.dart';
import '../../core/audit/audit_service.dart';
import 'work_order_models.dart';

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
  }) async {
    return await DbHelper.transaction((tx) async {
      final woId = uuid.v4();
      final woNo = await getNextWoNo();
      final userId = AuthService.currentUser?.userId ?? 'SYSTEM';
      final now = DateTime.now().toIso8601String();

      await DbHelper.txExecute(
        tx,
        '''INSERT INTO work_orders
           (wo_id, wo_no, machine_id, description, failure_symptom,
            priority, status, reported_by, reported_at, created_at, updated_at)
           VALUES (@wo_id, @wo_no, @machine_id, @description, @failure_symptom,
                   @priority, 'pending', @reported_by, @reported_at, @created_at, @updated_at)''',
        params: {
          'wo_id': woId,
          'wo_no': woNo,
          'machine_id': machineId,
          'description': description,
          'failure_symptom': failureSymptom,
          'priority': priority.dbValue,
          'reported_by': userId,
          'reported_at': now,
          'created_at': now,
          'updated_at': now,
        },
      );

      // Audit log
      await AuditService.logInsert('work_orders', woId, {
        'wo_no': woNo,
        'machine_id': machineId,
        'status': 'pending',
        'priority': priority.label,
      });

      return woId;
    });
  }

  /// Get work order by ID with related data
  Future<WorkOrder?> getWorkOrder(String woId) async {
    try {
      final row = await DbHelper.queryOne(
        '''SELECT wo.*, m.machine_no, m.brand as machine_brand, m.model as machine_model,
                  u1.full_name as reported_by_name, u2.full_name as assigned_to_name
           FROM work_orders wo
           LEFT JOIN machines m ON m.machine_id = wo.machine_id
           LEFT JOIN users u1 ON u1.user_id = wo.reported_by
           LEFT JOIN users u2 ON u2.user_id = wo.assigned_to
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
        'SELECT * FROM root_cause_analysis WHERE wo_id = @wo_id',
        params: {'wo_id': woId},
      );
      final rca = rcaRow != null ? RootCauseAnalysis.fromMap(rcaRow) : null;

      return WorkOrder.fromMap(row).copyWith(laborEntries: labors, rca: rca);
    } catch (e) {
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
        '''SELECT wo.*, m.machine_no, m.brand, m.model,
                  u1.full_name as reported_by_name, u2.full_name as assigned_to_name
           FROM work_orders wo
           LEFT JOIN machines m ON m.machine_id = wo.machine_id
           LEFT JOIN users u1 ON u1.user_id = wo.reported_by
           LEFT JOIN users u2 ON u2.user_id = wo.assigned_to
           WHERE ${where.join(' AND ')}
           ORDER BY wo.reported_at DESC
           LIMIT @limit''',
        params: {...params, 'limit': limit},
      );

      return rows.map((r) => WorkOrder.fromMap(r)).toList();
    } catch (e) {
      return [];
    }
  }

  /// Approve work order
  Future<bool> approveWorkOrder(String woId) async {
    try {
      final userId = AuthService.currentUser?.userId;
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
    try {
      final now = DateTime.now().toIso8601String();
      await DbHelper.execute(
        '''UPDATE work_orders
           SET status = 'in_progress', started_at = @started_at, updated_at = @updated_at
           WHERE wo_id = @wo_id''',
        params: {'wo_id': woId, 'started_at': now, 'updated_at': now},
      );

      return true;
    } catch (e) {
      return false;
    }
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
            '''INSERT INTO root_cause_analysis
               (rca_id, wo_id, why_1, why_2, why_3, why_4, why_5)
               VALUES (@rca_id, @wo_id, '', '', '', '', '')''',
            params: {'rca_id': uuid.v4(), 'wo_id': woId},
          );
        }

        return true;
      } catch (e) {
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

      await DbHelper.execute(
        '''UPDATE root_cause_analysis
           SET why_1 = @why_1, why_2 = @why_2, why_3 = @why_3, why_4 = @why_4, why_5 = @why_5,
               root_cause = @root_cause, correction_action = @correction_action,
               preventive_action = @preventive_action, completed_by = @completed_by,
               completed_at = @completed_at
           WHERE wo_id = @wo_id''',
        params: {
          'wo_id': woId,
          'why_1': why1,
          'why_2': why2,
          'why_3': why3,
          'why_4': why4,
          'why_5': why5,
          'root_cause': rootCause,
          'correction_action': correctionAction,
          'preventive_action': preventiveAction,
          'completed_by': userId,
          'completed_at': now,
        },
      );

      return true;
    } catch (e) {
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
