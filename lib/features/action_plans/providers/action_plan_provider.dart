import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  Future<void> updateStepStatus(
    String rcaId,
    String stepId,
    String newStatus,
  ) async {
    try {
      final currentList = state.valueOrNull ?? [];
      final plan = currentList.firstWhere((p) => p.rcaId == rcaId);

      for (final step in plan.actionSteps) {
        if (step.id == stepId) {
          step.status = newStatus;
        }
      }

      final allCompleted = plan.actionSteps.isNotEmpty &&
          plan.actionSteps.every((s) => s.status == 'completed');
      final newPlanStatus = allCompleted ? 'completed' : 'in_progress';
      final stepsJson = jsonEncode(plan.actionSteps.map((s) => s.toJson()).toList());

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
