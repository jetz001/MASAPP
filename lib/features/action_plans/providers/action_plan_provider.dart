import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';
import 'package:logger/logger.dart';
import '../../../core/database/db_helper.dart';
import '../../../core/storage/attachment_storage_service.dart';
import '../../../core/ai/vector_db_service.dart';
import '../models/action_plan_model.dart';

final _log = Logger();

class ActionPlanFilterState {
  final String statusFilter; // all, in_progress, completed, closed, pending
  final String sourceFilter; // all, work_order, line_balancing, sop_step, custom
  final String searchQuery;

  const ActionPlanFilterState({
    this.statusFilter = 'all',
    this.sourceFilter = 'all',
    this.searchQuery = '',
  });

  ActionPlanFilterState copyWith({
    String? statusFilter,
    String? sourceFilter,
    String? searchQuery,
  }) {
    return ActionPlanFilterState(
      statusFilter: statusFilter ?? this.statusFilter,
      sourceFilter: sourceFilter ?? this.sourceFilter,
      searchQuery: searchQuery ?? this.searchQuery,
    );
  }
}

final actionPlanFilterProvider =
    StateProvider<ActionPlanFilterState>((ref) => const ActionPlanFilterState());

class ActionPlanNotifier extends AsyncNotifier<List<ActionPlanRecord>> {
  @override
  Future<List<ActionPlanRecord>> build() async {
    return _fetchRecords();
  }

  Future<List<ActionPlanRecord>> _fetchRecords() async {
    try {
      // Ensure table exists
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
          status TEXT DEFAULT 'in_progress',
          created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
          updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      // Fetch all records
      final rows = await DbHelper.query('''
        SELECT * FROM problem_solving_records
        ORDER BY updated_at DESC, created_at DESC
      ''');

      // Fetch attachments for all action plans
      final assetRows = await DbHelper.query('''
        SELECT asset_id, entity_id, display_name, source_path, storage_path, thumbnail_path,
               preview_path, file_size, mime_type, category, is_primary, created_at
        FROM file_assets
        WHERE module_type = 'action_plan'
      ''');

      final Map<String, List<Map<String, dynamic>>> attachmentsByRca = {};
      for (final a in assetRows) {
        final entityId = a['entity_id']?.toString() ?? '';
        if (entityId.isNotEmpty) {
          attachmentsByRca.putIfAbsent(entityId, () => []).add(a);
        }
      }

      return rows.map((r) {
        final rcaId = r['rca_id']?.toString() ?? '';
        final attachList = attachmentsByRca[rcaId] ?? [];
        return ActionPlanRecord.fromMap(r, attachments: attachList);
      }).toList();
    } catch (e) {
      _log.e('Error loading action plans: $e');
      return [];
    }
  }

  Future<void> reload() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchRecords());
  }

  Future<ActionPlanRecord?> getById(String rcaId) async {
    try {
      final rows = await DbHelper.query(
        'SELECT * FROM problem_solving_records WHERE rca_id = @id',
        params: {'id': rcaId},
      );
      if (rows.isEmpty) return null;

      final assetRows = await DbHelper.query(
        "SELECT * FROM file_assets WHERE module_type = 'action_plan' AND entity_id = @id",
        params: {'id': rcaId},
      );

      return ActionPlanRecord.fromMap(rows.first, attachments: assetRows);
    } catch (e) {
      _log.e('Error fetching plan by ID: $e');
      return null;
    }
  }

  Future<void> savePlan({
    required String rcaId,
    required String problemTitle,
    required String sourceType,
    String? sourceId,
    String? rootCause,
    String? why1,
    String? why2,
    String? why3,
    String? why4,
    String? why5,
    String? fishboneMan,
    String? fishboneMachine,
    String? fishboneMaterial,
    String? fishboneMethod,
    String? fishboneEnv,
    required List<ActionStepItem> actionSteps,
    String? targetMetric,
    double? beforeValue,
    double? targetValue,
    double? actualValue,
    String? metricUnit,
    String? verifiedBy,
    String? verificationDate,
    String? verificationResult,
    String? standardizationNotes,
    String status = 'in_progress',
  }) async {
    try {
      final allDone = actionSteps.isNotEmpty && actionSteps.every((s) => s.status == 'completed');
      final finalStatus = allDone ? 'completed' : status;
      final stepsJson = jsonEncode(actionSteps.map((s) => s.toJson()).toList());

      await DbHelper.execute('''
        INSERT OR REPLACE INTO problem_solving_records (
          rca_id, source_type, source_id, problem_title,
          why_1, why_2, why_3, why_4, why_5,
          root_cause, fishbone_man, fishbone_machine, fishbone_material, fishbone_method, fishbone_env,
          action_steps_json, target_metric, before_value, target_value, actual_value, metric_unit,
          verified_by, verification_date, verification_result, standardization_notes,
          status, updated_at
        ) VALUES (
          @id, @stype, @sid, @title,
          @w1, @w2, @w3, @w4, @w5,
          @rc, @fman, @fmach, @fmat, @fmet, @fenv,
          @sjson, @tmetric, @bval, @tval, @aval, @munit,
          @vby, @vdate, @vres, @snotes,
          @status, CURRENT_TIMESTAMP
        )
      ''', params: {
        'id': rcaId,
        'stype': sourceType,
        'sid': sourceId,
        'title': problemTitle,
        'w1': why1,
        'w2': why2,
        'w3': why3,
        'w4': why4,
        'w5': why5,
        'rc': rootCause,
        'fman': fishboneMan,
        'fmach': fishboneMachine,
        'fmat': fishboneMaterial,
        'fmet': fishboneMethod,
        'fenv': fishboneEnv,
        'sjson': stepsJson,
        'tmetric': targetMetric,
        'bval': beforeValue,
        'tval': targetValue,
        'aval': actualValue,
        'munit': metricUnit,
        'vby': verifiedBy,
        'vdate': verificationDate,
        'vres': verificationResult,
        'snotes': standardizationNotes,
        'status': finalStatus,
      });

      // Auto-sync to Vector DB
      VectorDbService.syncProblemSolvingAndActionPlan(rcaId);

      await reload();
    } catch (e) {
      _log.e('Error saving action plan: $e');
      rethrow;
    }
  }

  Future<void> updateStepStatus(
    String rcaId,
    String stepId,
    String newStatus,
  ) async {
    try {
      final currentList = state.valueOrNull ?? [];
      final plan = currentList.firstWhereOrNull((p) => p.rcaId == rcaId);
      List<ActionStepItem> steps = [];

      if (plan != null) {
        steps = plan.actionSteps;
        for (final step in steps) {
          if (step.id == stepId) {
            step.status = newStatus;
          }
        }
      } else {
        final r = await getById(rcaId);
        if (r != null) {
          steps = r.actionSteps;
          for (final step in steps) {
            if (step.id == stepId) {
              step.status = newStatus;
            }
          }
        }
      }

      final allCompleted = steps.isNotEmpty && steps.every((s) => s.status == 'completed');
      final newPlanStatus = allCompleted ? 'completed' : 'in_progress';
      final stepsJson = jsonEncode(steps.map((s) => s.toJson()).toList());

      await DbHelper.execute('''
        UPDATE problem_solving_records
        SET action_steps_json = @sjson,
            status = @status,
            updated_at = CURRENT_TIMESTAMP
        WHERE rca_id = @id
      ''', params: {
        'sjson': stepsJson,
        'status': newPlanStatus,
        'id': rcaId,
      });

      // Auto-sync to Vector DB in background
      VectorDbService.syncProblemSolvingAndActionPlan(rcaId);

      await reload();
    } catch (e) {
      _log.e('Error updating step status: $e');
    }
  }

  Future<void> updatePlanStatus(String rcaId, String newStatus) async {
    try {
      await DbHelper.execute('''
        UPDATE problem_solving_records
        SET status = @status,
            updated_at = CURRENT_TIMESTAMP
        WHERE rca_id = @id
      ''', params: {
        'status': newStatus,
        'id': rcaId,
      });

      VectorDbService.syncProblemSolvingAndActionPlan(rcaId);
      await reload();
    } catch (e) {
      _log.e('Error updating plan status: $e');
    }
  }

  Future<void> updateVerification({
    required String rcaId,
    required String targetMetric,
    double? beforeValue,
    double? targetValue,
    double? actualValue,
    String? metricUnit,
    String? verifiedBy,
    String? verificationDate,
    String? verificationResult,
    String? standardizationNotes,
  }) async {
    try {
      await DbHelper.execute('''
        UPDATE problem_solving_records
        SET target_metric = @tmetric,
            before_value = @bval,
            target_value = @tval,
            actual_value = @aval,
            metric_unit = @munit,
            verified_by = @vby,
            verification_date = @vdate,
            verification_result = @vres,
            standardization_notes = @snotes,
            updated_at = CURRENT_TIMESTAMP
        WHERE rca_id = @id
      ''', params: {
        'tmetric': targetMetric,
        'bval': beforeValue,
        'tval': targetValue,
        'aval': actualValue,
        'munit': metricUnit,
        'vby': verifiedBy,
        'vdate': verificationDate,
        'vres': verificationResult,
        'snotes': standardizationNotes,
        'id': rcaId,
      });

      VectorDbService.syncProblemSolvingAndActionPlan(rcaId);
      await reload();
    } catch (e) {
      _log.e('Error updating verification: $e');
      rethrow;
    }
  }

  Future<void> deleteActionPlan(String rcaId) async {
    try {
      await DbHelper.execute(
        'DELETE FROM problem_solving_records WHERE rca_id = @id',
        params: {'id': rcaId},
      );
      await DbHelper.execute(
        "DELETE FROM file_assets WHERE module_type = 'action_plan' AND entity_id = @id",
        params: {'id': rcaId},
      );
      await DbHelper.execute(
        "DELETE FROM knowledge_vectors WHERE source_type = 'action_plan' AND source_id = @id",
        params: {'id': rcaId},
      );

      await reload();
    } catch (e) {
      _log.e('Error deleting action plan: $e');
    }
  }

  Future<void> addAttachment(String rcaId, String sourcePath, {String? displayName}) async {
    try {
      await AttachmentStorageService.instance.ingestFile(
        moduleType: 'action_plan',
        entityId: rcaId,
        sourcePath: sourcePath,
        displayName: displayName,
      );
      await reload();
    } catch (e) {
      _log.e('Error adding attachment to action plan: $e');
      rethrow;
    }
  }

  Future<void> removeAttachment(String assetId) async {
    try {
      await DbHelper.execute(
        'DELETE FROM file_assets WHERE asset_id = @id',
        params: {'id': assetId},
      );
      await reload();
    } catch (e) {
      _log.e('Error removing attachment: $e');
    }
  }
}

final actionPlanListProvider =
    AsyncNotifierProvider<ActionPlanNotifier, List<ActionPlanRecord>>(
  ActionPlanNotifier.new,
);

final actionPlanDetailProvider =
    FutureProvider.family<ActionPlanRecord?, String>((ref, rcaId) async {
  // Watch actionPlanListProvider to automatically re-fetch when list updates
  ref.watch(actionPlanListProvider);
  return ref.read(actionPlanListProvider.notifier).getById(rcaId);
});

final filteredActionPlanListProvider = Provider<List<ActionPlanRecord>>((ref) {
  final allPlans = ref.watch(actionPlanListProvider).valueOrNull ?? [];
  final filter = ref.watch(actionPlanFilterProvider);

  return allPlans.where((plan) {
    // 1. Status Filter
    if (filter.statusFilter != 'all') {
      if (filter.statusFilter == 'completed' && plan.status != 'completed' && plan.status != 'closed') {
        return false;
      } else if (filter.statusFilter == 'in_progress' && plan.status != 'in_progress') {
        return false;
      } else if (filter.statusFilter == 'pending' && plan.status != 'pending') {
        return false;
      }
    }

    // 2. Source Filter
    if (filter.sourceFilter != 'all') {
      if (plan.sourceType != filter.sourceFilter) {
        return false;
      }
    }

    // 3. Search Query
    if (filter.searchQuery.trim().isNotEmpty) {
      final q = filter.searchQuery.toLowerCase();
      final matchTitle = plan.problemTitle.toLowerCase().contains(q);
      final matchRoot = plan.rootCause?.toLowerCase().contains(q) ?? false;
      final matchAssignee = plan.actionSteps.any((s) => s.assignee.toLowerCase().contains(q));
      final matchSteps = plan.actionSteps.any((s) => s.title.toLowerCase().contains(q));
      if (!matchTitle && !matchRoot && !matchAssignee && !matchSteps) {
        return false;
      }
    }

    return true;
  }).toList();
});
