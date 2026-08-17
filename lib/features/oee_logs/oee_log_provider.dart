import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/db_helper.dart';
import 'package:uuid/uuid.dart';

class OeeLog {
  final String hoursId;
  final String machineId;
  final double cumulativeHours;
  final double targetProduction;
  final double actualProduction;
  final double goodProduction;
  final DateTime recordedDate;
  final String dataSource; // 'manual' or 'plc'
  final String machineName; // Joined from machines table

  OeeLog({
    required this.hoursId,
    required this.machineId,
    required this.cumulativeHours,
    required this.targetProduction,
    required this.actualProduction,
    required this.goodProduction,
    required this.recordedDate,
    required this.dataSource,
    this.machineName = '',
  });

  factory OeeLog.fromMap(Map<String, dynamic> map) {
    return OeeLog(
      hoursId: map['hours_id'],
      machineId: map['machine_id'],
      cumulativeHours: (map['cumulative_hours'] as num).toDouble(),
      targetProduction: (map['target_production'] as num?)?.toDouble() ?? 0,
      actualProduction: (map['actual_production'] as num?)?.toDouble() ?? 0,
      goodProduction: (map['good_production'] as num?)?.toDouble() ?? 0,
      recordedDate: DateTime.parse(map['recorded_date']),
      dataSource: map['data_source'] ?? 'manual',
      machineName: map['machine_name'] ?? '',
    );
  }
}

class OeeLogNotifier extends StateNotifier<AsyncValue<List<OeeLog>>> {
  OeeLogNotifier() : super(const AsyncValue.loading()) {
    loadLogs();
  }

  Future<void> loadLogs() async {
    state = const AsyncValue.loading();
    try {
      final results = await DbHelper.query(
        '''SELECT o.*, m.machine_name 
           FROM machine_running_hours o
           LEFT JOIN machines m ON o.machine_id = m.machine_id
           ORDER BY o.recorded_date DESC
           LIMIT 50'''
      );
      final logs = results.map((e) => OeeLog.fromMap(e)).toList();
      state = AsyncValue.data(logs);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> addLog({
    required String machineId,
    required double hours,
    required double target,
    required double actual,
    required double good,
    required String dataSource,
    required DateTime date,
  }) async {
    final id = const Uuid().v4();
    await DbHelper.execute(
      '''INSERT INTO machine_running_hours (
          hours_id, machine_id, cumulative_hours, target_production, actual_production, good_production, recorded_date, data_source
         ) VALUES (
          @id, @mId, @hrs, @tgt, @act, @good, @date, @src
         )''',
      params: {
        'id': id,
        'mId': machineId,
        'hrs': hours,
        'tgt': target,
        'act': actual,
        'good': good,
        'date': date.toIso8601String(),
        'src': dataSource,
      }
    );
    await loadLogs();
  }
}

final oeeLogProvider = StateNotifierProvider<OeeLogNotifier, AsyncValue<List<OeeLog>>>((ref) {
  return OeeLogNotifier();
});
