import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/database/db_helper.dart';
import '../../../core/ai/vector_db_service.dart';
import '../models/work_process_model.dart';
import '../models/work_process_step_model.dart';

final workProcessListProvider =
    AsyncNotifierProvider<WorkProcessListNotifier, List<WorkProcess>>(
  WorkProcessListNotifier.new,
);

class WorkProcessListNotifier extends AsyncNotifier<List<WorkProcess>> {
  static bool _schemaEnsured = false;

  static Future<void> ensureSchema() async {
    if (_schemaEnsured) return;
    try {
      await DbHelper.execute('''
        CREATE TABLE IF NOT EXISTS work_processes (
          process_id        TEXT PRIMARY KEY,
          process_no        TEXT NOT NULL,
          title             TEXT NOT NULL,
          company           TEXT,
          factory           TEXT,
          department        TEXT,
          method_type       TEXT NOT NULL DEFAULT 'current',
          parent_process_id TEXT REFERENCES work_processes(process_id) ON DELETE SET NULL,
          work_type         TEXT NOT NULL DEFAULT 'man',
          machine_id        TEXT REFERENCES machines(machine_id) ON DELETE SET NULL,
          line_id           TEXT,
          prepared_by       TEXT,
          prepared_date     TEXT,
          approved_by       TEXT,
          approved_date     TEXT,
          notes             TEXT,
          status            TEXT NOT NULL DEFAULT 'draft',
          created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      await DbHelper.execute('''
        CREATE TABLE IF NOT EXISTS work_process_steps (
          step_id          TEXT PRIMARY KEY,
          process_id       TEXT NOT NULL REFERENCES work_processes(process_id) ON DELETE CASCADE,
          step_no          INTEGER NOT NULL,
          description      TEXT NOT NULL,
          event_type       TEXT NOT NULL,
          distance_meters  REAL NOT NULL DEFAULT 0.0,
          parts_quantity   TEXT,
          tools_used       TEXT,
          duration_minutes REAL NOT NULL DEFAULT 0.0,
          value_type       TEXT NOT NULL,
          problem_cause    TEXT,
          improvement_idea TEXT,
          created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      await DbHelper.execute(
        'CREATE INDEX IF NOT EXISTS idx_work_process_steps_process ON work_process_steps(process_id, step_no)',
      );
      await DbHelper.execute(
        'CREATE INDEX IF NOT EXISTS idx_work_processes_method ON work_processes(method_type, parent_process_id)',
      );
      _schemaEnsured = true;
    } catch (_) {}
  }

  @override
  Future<List<WorkProcess>> build() async {
    await ensureSchema();
    return _fetchProcesses();
  }

  Future<List<WorkProcess>> _fetchProcesses() async {
    await ensureSchema();
    final rows = await DbHelper.query('''
      SELECT wp.*, m.machine_no, m.machine_name
      FROM work_processes wp
      LEFT JOIN machines m ON wp.machine_id = m.machine_id
      ORDER BY wp.updated_at DESC
    ''');

    final List<WorkProcess> list = [];
    for (final row in rows) {
      final processId = row['process_id'].toString();
      final stepRows = await DbHelper.query(
        'SELECT * FROM work_process_steps WHERE process_id = @process_id ORDER BY step_no ASC',
        params: {'process_id': processId},
      );
      final steps = stepRows.map((s) => WorkProcessStep.fromMap(s)).toList();
      list.add(WorkProcess.fromMap(row, steps: steps));
    }
    return list;
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _fetchProcesses());
  }

  Future<WorkProcess?> getProcessById(String processId) async {
    await ensureSchema();
    final rows = await DbHelper.query('''
      SELECT wp.*, m.machine_no, m.machine_name
      FROM work_processes wp
      LEFT JOIN machines m ON wp.machine_id = m.machine_id
      WHERE wp.process_id = @process_id
    ''', params: {'process_id': processId});

    if (rows.isEmpty) return null;
    final stepRows = await DbHelper.query(
      'SELECT * FROM work_process_steps WHERE process_id = @process_id ORDER BY step_no ASC',
      params: {'process_id': processId},
    );
    final steps = stepRows.map((s) => WorkProcessStep.fromMap(s)).toList();
    return WorkProcess.fromMap(rows.first, steps: steps);
  }

  Future<String> saveProcess({
    required WorkProcess process,
    required List<WorkProcessStep> steps,
  }) async {
    await ensureSchema();
    final processId = process.processId.isNotEmpty
        ? process.processId
        : const Uuid().v4();

    final now = DateTime.now().toIso8601String();

    await DbHelper.transaction((txn) async {
      // Upsert process
      await txn.rawInsert('''
        INSERT INTO work_processes (
          process_id, process_no, title, company, factory, department,
          method_type, parent_process_id, work_type, machine_id, line_id,
          prepared_by, prepared_date, approved_by, approved_date, notes,
          status, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(process_id) DO UPDATE SET
          process_no = excluded.process_no,
          title = excluded.title,
          company = excluded.company,
          factory = excluded.factory,
          department = excluded.department,
          method_type = excluded.method_type,
          parent_process_id = excluded.parent_process_id,
          work_type = excluded.work_type,
          machine_id = excluded.machine_id,
          line_id = excluded.line_id,
          prepared_by = excluded.prepared_by,
          prepared_date = excluded.prepared_date,
          approved_by = excluded.approved_by,
          approved_date = excluded.approved_date,
          notes = excluded.notes,
          status = excluded.status,
          updated_at = excluded.updated_at
      ''', [
        processId,
        process.processNo,
        process.title,
        process.company,
        process.factory,
        process.department,
        process.methodType.code,
        process.parentProcessId,
        process.workType.code,
        process.machineId,
        process.lineId,
        process.preparedBy,
        process.preparedDate,
        process.approvedBy,
        process.approvedDate,
        process.notes,
        process.status,
        process.createdAt.toIso8601String(),
        now,
      ]);

      // Delete existing steps
      await txn.rawDelete(
        'DELETE FROM work_process_steps WHERE process_id = ?',
        [processId],
      );

      // Insert new steps
      for (int i = 0; i < steps.length; i++) {
        final step = steps[i];
        final stepId = step.stepId.isNotEmpty ? step.stepId : const Uuid().v4();
        await txn.rawInsert('''
          INSERT INTO work_process_steps (
            step_id, process_id, step_no, description, event_type,
            distance_meters, parts_quantity, tools_used, duration_minutes,
            value_type, problem_cause, improvement_idea, created_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', [
          stepId,
          processId,
          i + 1,
          step.description,
          step.eventType.code,
          step.distanceMeters,
          step.partsQuantity,
          step.toolsUsed,
          step.durationMinutes,
          step.valueType.code,
          step.problemCause,
          step.improvementIdea,
          now,
        ]);
      }
    });

    await refresh();
    unawaited(VectorDbService.syncWorkProcess(processId));
    return processId;
  }

  Future<void> deleteProcess(String processId) async {
    await DbHelper.transaction((txn) async {
      await txn.rawDelete(
        'DELETE FROM work_process_steps WHERE process_id = ?',
        [processId],
      );
      await txn.rawDelete(
        'DELETE FROM work_processes WHERE process_id = ?',
        [processId],
      );
      await txn.rawDelete(
        'DELETE FROM knowledge_vectors WHERE vector_id = ?',
        ['vec_wp_$processId'],
      );
    });
    await refresh();
  }

  Future<String> duplicateAsImproved(String originalProcessId) async {
    final original = await getProcessById(originalProcessId);
    if (original == null) throw Exception('ไม่พบข้อมูลขั้นตอนงานต้นฉบับ');

    final newId = const Uuid().v4();
    final newNo = '${original.processNo}-IMP';
    final newTitle = '${original.title} (ฉบับปรับปรุง)';
    final now = DateTime.now();

    final newProcess = original.copyWith(
      processId: newId,
      processNo: newNo,
      title: newTitle,
      methodType: WorkProcessMethodType.improved,
      parentProcessId: original.processId,
      status: 'draft',
      createdAt: now,
      updatedAt: now,
    );

    final copiedSteps = original.steps
        .map(
          (s) => s.copyWith(
            stepId: const Uuid().v4(),
            processId: newId,
            createdAt: now,
          ),
        )
        .toList();

    return saveProcess(process: newProcess, steps: copiedSteps);
  }
}

class MachineProcessItem {
  final String machineId;
  final String machineNo;
  final String machineName;
  final String? brand;
  final String? model;
  final String? department;
  final String? location;
  final String? status;
  final List<WorkProcess> processes;

  MachineProcessItem({
    required this.machineId,
    required this.machineNo,
    required this.machineName,
    this.brand,
    this.model,
    this.department,
    this.location,
    this.status,
    this.processes = const [],
  });

  bool get hasProcess => processes.isNotEmpty;
  WorkProcess? get currentProcess =>
      processes.where((p) => p.methodType == WorkProcessMethodType.current).firstOrNull ??
      processes.firstOrNull;
  WorkProcess? get improvedProcess =>
      processes.where((p) => p.methodType == WorkProcessMethodType.improved).firstOrNull;
  int get stepCount => currentProcess?.steps.length ?? 0;
  double get totalDuration => currentProcess?.totalDurationMinutes ?? 0.0;
  int get vaCount =>
      currentProcess?.steps.where((s) => s.valueType == LeanValueType.va).length ?? 0;
  int get nvaCount =>
      currentProcess?.steps.where((s) => s.valueType == LeanValueType.nva).length ?? 0;
}

final machineProcessListProvider =
    AsyncNotifierProvider<MachineProcessListNotifier, List<MachineProcessItem>>(
  MachineProcessListNotifier.new,
);

class MachineProcessListNotifier extends AsyncNotifier<List<MachineProcessItem>> {
  @override
  Future<List<MachineProcessItem>> build() async {
    final processes = await ref.watch(workProcessListProvider.future);
    return _fetchMachineProcesses(processes);
  }

  Future<List<MachineProcessItem>> _fetchMachineProcesses(
    List<WorkProcess> allProcesses,
  ) async {
    await WorkProcessListNotifier.ensureSchema();
    final machines = await DbHelper.query('''
      SELECT m.machine_id, m.machine_no, m.machine_name, m.brand, m.model, m.location, m.status,
             COALESCE(d.dept_name, '') AS department
      FROM machines m
      LEFT JOIN departments d ON m.dept_id = d.dept_id
      WHERE m.is_active = 1
      ORDER BY m.machine_no ASC
    ''');

    final List<MachineProcessItem> result = [];
    for (final m in machines) {
      final mId = m['machine_id'].toString();
      final machineProcesses =
          allProcesses.where((p) => p.machineId == mId).toList();
      result.add(
        MachineProcessItem(
          machineId: mId,
          machineNo: m['machine_no']?.toString() ?? '',
          machineName: m['machine_name']?.toString() ?? '',
          brand: m['brand']?.toString(),
          model: m['model']?.toString(),
          department: m['department']?.toString(),
          location: m['location']?.toString(),
          status: m['status']?.toString(),
          processes: machineProcesses,
        ),
      );
    }
    return result;
  }

  Future<void> refresh() async {
    await ref.read(workProcessListProvider.notifier).refresh();
  }
}

