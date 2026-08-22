import 'dart:convert';
import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/db_helper.dart';
import '../../core/ai/vector_db_service.dart';

class MachineBalancingData {
  final double cycleTime;
  final double energyCost;
  final int workers;

  MachineBalancingData({
    required this.cycleTime,
    required this.energyCost,
    this.workers = 1,
  });
}

class WorkstationData {
  final String id;
  final String name;
  final double cycleTime; // in seconds
  final String? machineId;
  final String? machineName;
  final int workers; // number of workers

  // Lean Classification
  final String eventType; // 'operation', 'transportation', 'inspection', 'delay', 'storage'
  final String valueType; // 'va', 'nva', 'nnva'
  final double waitingTimeSec; // Buffer / wait time before this station
  final int bufferQuantity; // WIP pieces

  // Detailed Costs (per hour)
  final double laborCost;
  final double energyCost;
  final double materialCost;
  final double otherCost;

  // Graph Properties
  final List<String> prevStationIds;
  final List<String> nextStationIds;
  final Offset position;

  WorkstationData({
    required this.id,
    required this.name,
    required this.cycleTime,
    this.machineId,
    this.machineName,
    this.workers = 1,
    this.eventType = 'operation',
    this.valueType = 'va',
    this.waitingTimeSec = 0.0,
    this.bufferQuantity = 0,
    this.laborCost = 300.0,
    this.energyCost = 0.0,
    this.materialCost = 0.0,
    this.otherCost = 0.0,
    this.prevStationIds = const [],
    this.nextStationIds = const [],
    this.position = Offset.zero,
  });

  double get totalHourlyCost =>
      laborCost + energyCost + materialCost + otherCost;

  WorkstationData copyWith({
    String? name,
    double? cycleTime,
    String? machineId,
    String? machineName,
    int? workers,
    String? eventType,
    String? valueType,
    double? waitingTimeSec,
    int? bufferQuantity,
    double? laborCost,
    double? energyCost,
    double? materialCost,
    double? otherCost,
    List<String>? prevStationIds,
    List<String>? nextStationIds,
    Offset? position,
  }) {
    return WorkstationData(
      id: id,
      name: name ?? this.name,
      cycleTime: cycleTime ?? this.cycleTime,
      machineId: machineId ?? this.machineId,
      machineName: machineName ?? this.machineName,
      workers: workers ?? this.workers,
      eventType: eventType ?? this.eventType,
      valueType: valueType ?? this.valueType,
      waitingTimeSec: waitingTimeSec ?? this.waitingTimeSec,
      bufferQuantity: bufferQuantity ?? this.bufferQuantity,
      laborCost: laborCost ?? this.laborCost,
      energyCost: energyCost ?? this.energyCost,
      materialCost: materialCost ?? this.materialCost,
      otherCost: otherCost ?? this.otherCost,
      prevStationIds: prevStationIds ?? this.prevStationIds,
      nextStationIds: nextStationIds ?? this.nextStationIds,
      position: position ?? this.position,
    );
  }
}

class LineConnection {
  final String id; // unique connection id e.g. "fromId->toId"
  final String fromStationId;
  final String toStationId;
  final int colorValue; // ARGB integer e.g. 0xFFFB8C00
  final List<Offset> waypoints; // draggable bend points
  final bool isCurved; // false = 90 deg orthogonal (Wokwi), true = curved

  LineConnection({
    required this.id,
    required this.fromStationId,
    required this.toStationId,
    this.colorValue = 0xFFFB8C00, // Wokwi Orange default
    this.waypoints = const [],
    this.isCurved = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': fromStationId,
    'to': toStationId,
    'color': colorValue,
    'isCurved': isCurved,
    'waypoints': waypoints.map((w) => {'x': w.dx, 'y': w.dy}).toList(),
  };

  factory LineConnection.fromJson(Map<String, dynamic> json) {
    return LineConnection(
      id: json['id'] as String? ?? '${json['from']}->${json['to']}',
      fromStationId: json['from'] as String,
      toStationId: json['to'] as String,
      colorValue: json['color'] as int? ?? 0xFFFB8C00,
      isCurved: json['isCurved'] as bool? ?? false,
      waypoints: (json['waypoints'] as List<dynamic>?)
              ?.map((w) => Offset(
                    (w['x'] as num).toDouble(),
                    (w['y'] as num).toDouble(),
                  ))
              .toList() ??
          const [],
    );
  }

  LineConnection copyWith({
    int? colorValue,
    List<Offset>? waypoints,
    bool? isCurved,
  }) {
    return LineConnection(
      id: id,
      fromStationId: fromStationId,
      toStationId: toStationId,
      colorValue: colorValue ?? this.colorValue,
      waypoints: waypoints ?? this.waypoints,
      isCurved: isCurved ?? this.isCurved,
    );
  }
}

class LineBalancingState {
  final String lineId;
  final String lineName;
  final String? department;
  final double availableTimeMin;
  final double demandQuantity;
  final double electricityRate;
  final double fuelRate;
  final List<WorkstationData> stations;
  final List<LineConnection> connections;

  LineBalancingState({
    this.lineId = 'default_line',
    this.lineName = 'สายการผลิตหลัก (Main Line)',
    this.department,
    required this.availableTimeMin,
    required this.demandQuantity,
    this.electricityRate = 4.0, // Default 4 THB/kWh
    this.fuelRate = 30.0, // Default 30 THB/L
    required this.stations,
    this.connections = const [],
  });

  List<LineConnection> get resolvedConnections {
    final Map<String, LineConnection> existingMap = {
      for (final c in connections) c.id: c
    };
    final List<LineConnection> result = [];
    for (final s in stations) {
      for (final nextId in s.nextStationIds) {
        final id = '${s.id}->$nextId';
        if (existingMap.containsKey(id)) {
          result.add(existingMap[id]!);
        } else {
          result.add(LineConnection(
            id: id,
            fromStationId: s.id,
            toStationId: nextId,
            colorValue: 0xFFFB8C00,
          ));
        }
      }
    }
    return result;
  }

  double get taktTimeSec =>
      demandQuantity > 0 ? (availableTimeMin * 60) / demandQuantity : 0;

  double get totalCycleTime =>
      stations.fold(0.0, (sum, st) => sum + st.cycleTime);

  double get maxCycleTime {
    if (stations.isEmpty) return 0;
    return stations.map((e) => e.cycleTime).reduce((a, b) => a > b ? a : b);
  }

  double get lineEfficiency {
    if (stations.isEmpty || maxCycleTime == 0) return 0;
    return (totalCycleTime / (stations.length * maxCycleTime)) * 100;
  }

  double get balanceDelay => 100 - lineEfficiency;

  // Total VA Time (Value Added) in seconds
  double get totalVaTimeSec => stations
      .where((s) => s.valueType == 'va')
      .fold(0.0, (sum, s) => sum + s.cycleTime);

  // Total NVA Time (Non-Value Added / Waste / Waiting) in seconds
  double get totalNvaTimeSec {
    final nvaCycle = stations
        .where((s) => s.valueType != 'va')
        .fold(0.0, (sum, s) => sum + s.cycleTime);
    final totalWait =
        stations.fold(0.0, (sum, s) => sum + s.waitingTimeSec);
    return nvaCycle + totalWait;
  }

  // Process Cycle Efficiency (PCE %)
  double get processCycleEfficiency {
    final totalLead = totalVaTimeSec + totalNvaTimeSec;
    if (totalLead == 0) return 0;
    return (totalVaTimeSec / totalLead) * 100;
  }

  // Lead time calculation
  double get leadTimeSec {
    if (stations.isEmpty) return 0.0;

    final Map<String, WorkstationData> nodeMap = {
      for (var s in stations) s.id: s
    };
    final Map<String, double> maxPath = {};

    double findLongestPath(String nodeId) {
      if (maxPath.containsKey(nodeId)) return maxPath[nodeId]!;

      final node = nodeMap[nodeId];
      if (node == null) return 0.0;

      double maxChildPath = 0.0;
      for (final nextId in node.nextStationIds) {
        final childPath = findLongestPath(nextId);
        if (childPath > maxChildPath) maxChildPath = childPath;
      }

      final result = node.cycleTime + node.waitingTimeSec + maxChildPath;
      maxPath[nodeId] = result;
      return result;
    }

    final roots = stations.where((s) => s.prevStationIds.isEmpty).toList();
    if (roots.isEmpty) return totalCycleTime;

    double maxLeadTime = 0.0;
    for (final root in roots) {
      final pathTime = findLongestPath(root.id);
      if (pathTime > maxLeadTime) maxLeadTime = pathTime;
    }

    return maxLeadTime;
  }

  double get totalLaborCost =>
      stations.fold(0.0, (sum, st) => sum + st.laborCost) *
      (availableTimeMin / 60);
  double get totalEnergyCost =>
      stations.fold(0.0, (sum, st) => sum + st.energyCost) *
      (availableTimeMin / 60);
  double get totalMaterialCost =>
      stations.fold(0.0, (sum, st) => sum + st.materialCost) *
      (availableTimeMin / 60);
  double get totalOtherCost =>
      stations.fold(0.0, (sum, st) => sum + st.otherCost) *
      (availableTimeMin / 60);

  double get totalOperationalCost =>
      totalLaborCost + totalEnergyCost + totalMaterialCost + totalOtherCost;

  int get totalWorkers => stations.fold(0, (sum, st) => sum + st.workers);

  LineBalancingState copyWith({
    String? lineId,
    String? lineName,
    String? department,
    double? availableTimeMin,
    double? demandQuantity,
    double? electricityRate,
    double? fuelRate,
    List<WorkstationData>? stations,
    List<LineConnection>? connections,
  }) {
    return LineBalancingState(
      lineId: lineId ?? this.lineId,
      lineName: lineName ?? this.lineName,
      department: department ?? this.department,
      availableTimeMin: availableTimeMin ?? this.availableTimeMin,
      demandQuantity: demandQuantity ?? this.demandQuantity,
      electricityRate: electricityRate ?? this.electricityRate,
      fuelRate: fuelRate ?? this.fuelRate,
      stations: stations ?? this.stations,
      connections: connections ?? this.connections,
    );
  }
}

class LineBalancingNotifier extends StateNotifier<LineBalancingState> {
  LineBalancingNotifier()
      : super(LineBalancingState(
          lineId: 'main_line',
          lineName: 'สายการผลิตหลัก (Main Line)',
          availableTimeMin: 480, // 8 hours
          demandQuantity: 1000,
          stations: [],
          connections: [],
        )) {
    _initAndLoad();
  }

  static Future<void> ensureTables() async {
    try {
      await DbHelper.execute('''
        CREATE TABLE IF NOT EXISTS production_lines (
          line_id             TEXT PRIMARY KEY,
          line_name           TEXT NOT NULL,
          department          TEXT,
          available_time_min  REAL NOT NULL DEFAULT 480,
          demand_quantity     REAL NOT NULL DEFAULT 1000,
          electricity_rate    REAL NOT NULL DEFAULT 4.0,
          fuel_rate           REAL NOT NULL DEFAULT 30.0,
          connections_json    TEXT,
          created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      try {
        await DbHelper.execute('ALTER TABLE production_lines ADD COLUMN connections_json TEXT;');
      } catch (_) {}

      await DbHelper.execute('''
        CREATE TABLE IF NOT EXISTS production_line_stations (
          station_id          TEXT PRIMARY KEY,
          line_id             TEXT NOT NULL,
          station_no          INTEGER NOT NULL,
          station_name        TEXT NOT NULL,
          machine_id          TEXT,
          machine_name        TEXT,
          cycle_time_sec      REAL NOT NULL DEFAULT 0.0,
          workers             INTEGER NOT NULL DEFAULT 1,
          labor_cost          REAL NOT NULL DEFAULT 300.0,
          energy_cost         REAL NOT NULL DEFAULT 0.0,
          material_cost       REAL NOT NULL DEFAULT 0.0,
          other_cost          REAL NOT NULL DEFAULT 0.0,
          event_type          TEXT NOT NULL DEFAULT 'operation',
          value_type          TEXT NOT NULL DEFAULT 'va',
          waiting_time_sec    REAL NOT NULL DEFAULT 0.0,
          buffer_quantity     INTEGER NOT NULL DEFAULT 0,
          pos_x               REAL NOT NULL DEFAULT 0.0,
          pos_y               REAL NOT NULL DEFAULT 0.0,
          prev_station_ids    TEXT,
          next_station_ids    TEXT,
          created_at          DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');
    } catch (_) {}
  }

  Future<void> _initAndLoad() async {
    await ensureTables();
    await loadFirstAvailableLine();
  }

  Future<void> loadFirstAvailableLine() async {
    try {
      final lines = await DbHelper.query(
        'SELECT * FROM production_lines ORDER BY created_at ASC LIMIT 1',
      );
      if (lines.isNotEmpty) {
        await loadLine(lines.first['line_id'].toString());
        if (state.stations.isEmpty) {
          await _seedDefaultStations();
        }
      } else {
        await _seedDefaultLine();
      }
    } catch (e) {
      // Fallback seed
      await _seedDefaultLine();
    }
  }

  Future<void> _seedDefaultLine() async {
    state = LineBalancingState(
      lineId: 'main_line',
      lineName: 'สายการผลิตหลัก (Main Line)',
      availableTimeMin: 480,
      demandQuantity: 1000,
      electricityRate: 4.0,
      fuelRate: 30.0,
      stations: [],
    );
    await _seedDefaultStations();
  }

  Future<void> _seedDefaultStations() async {
    final s1 = WorkstationData(
      id: 'st_1',
      name: '1. ตัดและเตรียมวัตถุดิบ (Cutting)',
      cycleTime: 25.0,
      workers: 1,
      eventType: 'operation',
      valueType: 'va',
      position: const Offset(1600, 1850),
      nextStationIds: ['st_2'],
    );
    final s2 = WorkstationData(
      id: 'st_2',
      name: '2. ขึ้นรูปและกลึง (Machining)',
      cycleTime: 35.0,
      workers: 2,
      eventType: 'operation',
      valueType: 'va',
      position: const Offset(1920, 1850),
      prevStationIds: ['st_1'],
      nextStationIds: ['st_3'],
    );
    final s3 = WorkstationData(
      id: 'st_3',
      name: '3. ประกอบชิ้นงาน (Assembly)',
      cycleTime: 40.0,
      workers: 2,
      eventType: 'operation',
      valueType: 'va',
      position: const Offset(2240, 1850),
      prevStationIds: ['st_2'],
      nextStationIds: ['st_4'],
    );
    final s4 = WorkstationData(
      id: 'st_4',
      name: '4. ตรวจสอบคุณภาพและบรรจุ (QC & Pack)',
      cycleTime: 20.0,
      workers: 1,
      eventType: 'inspection',
      valueType: 'va',
      position: const Offset(2560, 1850),
      prevStationIds: ['st_3'],
    );

    final conn1 = LineConnection(id: 'st_1->st_2', fromStationId: 'st_1', toStationId: 'st_2', colorValue: 0xFFFB8C00);
    final conn2 = LineConnection(id: 'st_2->st_3', fromStationId: 'st_2', toStationId: 'st_3', colorValue: 0xFFFB8C00);
    final conn3 = LineConnection(id: 'st_3->st_4', fromStationId: 'st_3', toStationId: 'st_4', colorValue: 0xFFFB8C00);

    state = state.copyWith(
      stations: [s1, s2, s3, s4],
      connections: [conn1, conn2, conn3],
    );
    await saveCurrentLine();
  }

  Future<void> loadLine(String lineId) async {
    try {
      await ensureTables();
      final lineRes = await DbHelper.queryOne(
        'SELECT * FROM production_lines WHERE line_id = @id',
        params: {'id': lineId},
      );
      if (lineRes == null) return;

      final stationRows = await DbHelper.query(
        'SELECT * FROM production_line_stations WHERE line_id = @id ORDER BY station_no ASC',
        params: {'id': lineId},
      );

      final loadedStations = stationRows.map((s) {
        List<String> prevs = [];
        List<String> nexts = [];
        try {
          if (s['prev_station_ids'] != null &&
              s['prev_station_ids'].toString().isNotEmpty) {
            prevs = List<String>.from(jsonDecode(s['prev_station_ids']));
          }
          if (s['next_station_ids'] != null &&
              s['next_station_ids'].toString().isNotEmpty) {
            nexts = List<String>.from(jsonDecode(s['next_station_ids']));
          }
        } catch (_) {}

        return WorkstationData(
          id: s['station_id'].toString(),
          name: s['station_name'] ?? 'สถานีงาน',
          cycleTime: (s['cycle_time_sec'] as num?)?.toDouble() ?? 0.0,
          machineId: s['machine_id']?.toString(),
          machineName: s['machine_name']?.toString(),
          workers: (s['workers'] as num?)?.toInt() ?? 1,
          eventType: s['event_type'] ?? 'operation',
          valueType: s['value_type'] ?? 'va',
          waitingTimeSec: (s['waiting_time_sec'] as num?)?.toDouble() ?? 0.0,
          bufferQuantity: (s['buffer_quantity'] as num?)?.toInt() ?? 0,
          laborCost: (s['labor_cost'] as num?)?.toDouble() ?? 300.0,
          energyCost: (s['energy_cost'] as num?)?.toDouble() ?? 0.0,
          materialCost: (s['material_cost'] as num?)?.toDouble() ?? 0.0,
          otherCost: (s['other_cost'] as num?)?.toDouble() ?? 0.0,
          position: Offset(
            (s['pos_x'] as num?)?.toDouble() ?? 0.0,
            (s['pos_y'] as num?)?.toDouble() ?? 0.0,
          ),
          prevStationIds: prevs,
          nextStationIds: nexts,
        );
      }).toList();

      List<LineConnection> loadedConnections = [];
      try {
        if (lineRes['connections_json'] != null &&
            lineRes['connections_json'].toString().isNotEmpty) {
          final rawList = jsonDecode(lineRes['connections_json']) as List<dynamic>;
          loadedConnections = rawList
              .map((item) => LineConnection.fromJson(item as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}

      state = LineBalancingState(
        lineId: lineId,
        lineName: lineRes['line_name'] ?? 'สายการผลิต',
        department: lineRes['department']?.toString(),
        availableTimeMin:
            (lineRes['available_time_min'] as num?)?.toDouble() ?? 480.0,
        demandQuantity:
            (lineRes['demand_quantity'] as num?)?.toDouble() ?? 1000.0,
        electricityRate:
            (lineRes['electricity_rate'] as num?)?.toDouble() ?? 4.0,
        fuelRate: (lineRes['fuel_rate'] as num?)?.toDouble() ?? 30.0,
        stations: loadedStations,
        connections: loadedConnections,
      );
    } catch (_) {}
  }

  Future<void> saveCurrentLine({String? newName}) async {
    try {
      await ensureTables();
      final lineId = state.lineId.isNotEmpty ? state.lineId : const Uuid().v4();
      final name = newName ?? state.lineName;
      final connectionsJson = jsonEncode(
        state.resolvedConnections.map((c) => c.toJson()).toList(),
      );

      await DbHelper.execute('''
        INSERT INTO production_lines (line_id, line_name, department, available_time_min, demand_quantity, electricity_rate, fuel_rate, connections_json, updated_at)
        VALUES (@id, @name, @dept, @avail, @demand, @elec, @fuel, @conn, CURRENT_TIMESTAMP)
        ON CONFLICT(line_id) DO UPDATE SET
          line_name = excluded.line_name,
          department = excluded.department,
          available_time_min = excluded.available_time_min,
          demand_quantity = excluded.demand_quantity,
          electricity_rate = excluded.electricity_rate,
          fuel_rate = excluded.fuel_rate,
          connections_json = excluded.connections_json,
          updated_at = CURRENT_TIMESTAMP
      ''', params: {
        'id': lineId,
        'name': name,
        'dept': state.department,
        'avail': state.availableTimeMin,
        'demand': state.demandQuantity,
        'elec': state.electricityRate,
        'fuel': state.fuelRate,
        'conn': connectionsJson,
      });

      // Delete old stations and re-insert
      await DbHelper.execute(
        'DELETE FROM production_line_stations WHERE line_id = @id',
        params: {'id': lineId},
      );

      for (int i = 0; i < state.stations.length; i++) {
        final s = state.stations[i];
        await DbHelper.execute('''
          INSERT INTO production_line_stations (
            station_id, line_id, station_no, station_name, machine_id, machine_name,
            cycle_time_sec, workers, labor_cost, energy_cost, material_cost, other_cost,
            event_type, value_type, waiting_time_sec, buffer_quantity,
            pos_x, pos_y, prev_station_ids, next_station_ids
          ) VALUES (
            @id, @lineId, @no, @name, @mcId, @mcName,
            @ct, @wk, @labor, @energy, @mat, @other,
            @evt, @val, @wait, @buf,
            @x, @y, @prev, @next
          )
        ''', params: {
          'id': s.id,
          'lineId': lineId,
          'no': i + 1,
          'name': s.name,
          'mcId': s.machineId,
          'mcName': s.machineName,
          'ct': s.cycleTime,
          'wk': s.workers,
          'labor': s.laborCost,
          'energy': s.energyCost,
          'mat': s.materialCost,
          'other': s.otherCost,
          'evt': s.eventType,
          'val': s.valueType,
          'wait': s.waitingTimeSec,
          'buf': s.bufferQuantity,
          'x': s.position.dx,
          'y': s.position.dy,
          'prev': jsonEncode(s.prevStationIds),
          'next': jsonEncode(s.nextStationIds),
        });
      }

      state = state.copyWith(lineId: lineId, lineName: name);

      // Auto sync to Vector DB
      await VectorDbService.syncLineBalancing(lineId);
    } catch (_) {}
  }

  void updateDemand(double demand) {
    state = state.copyWith(demandQuantity: demand);
    saveCurrentLine();
  }

  void updateAvailableTime(double minutes) {
    state = state.copyWith(availableTimeMin: minutes);
    saveCurrentLine();
  }

  void updateRates(double elecRate, double fRate) {
    state = state.copyWith(electricityRate: elecRate, fuelRate: fRate);
    saveCurrentLine();
  }

  void addStation(
    String name,
    double cycleTime, {
    String? machineId,
    String? machineName,
    int workers = 1,
    String eventType = 'operation',
    String valueType = 'va',
    double waitingTimeSec = 0.0,
    int bufferQuantity = 0,
    double laborCost = 300.0,
    double energyCost = 0.0,
    double materialCost = 0.0,
    double otherCost = 0.0,
    List<String> prevStationIds = const [],
    Offset position = Offset.zero,
  }) {
    final newId = DateTime.now().millisecondsSinceEpoch.toString();
    final newStation = WorkstationData(
      id: newId,
      name: name,
      cycleTime: cycleTime,
      machineId: machineId,
      machineName: machineName,
      workers: workers,
      eventType: eventType,
      valueType: valueType,
      waitingTimeSec: waitingTimeSec,
      bufferQuantity: bufferQuantity,
      laborCost: laborCost,
      energyCost: energyCost,
      materialCost: materialCost,
      otherCost: otherCost,
      prevStationIds: prevStationIds,
      position: position,
    );

    // Also update parent stations' nextStationIds
    final updatedStations = state.stations.map((s) {
      if (prevStationIds.contains(s.id)) {
        return s.copyWith(nextStationIds: [...s.nextStationIds, newId]);
      }
      return s;
    }).toList();

    state = state.copyWith(stations: [...updatedStations, newStation]);
    saveCurrentLine();
  }

  void updateStation(
    String id,
    String name,
    double cycleTime, {
    String? machineId,
    String? machineName,
    int? workers,
    String? eventType,
    String? valueType,
    double? waitingTimeSec,
    int? bufferQuantity,
    double? laborCost,
    double? energyCost,
    double? materialCost,
    double? otherCost,
  }) {
    final updated = state.stations.map((s) {
      if (s.id == id) {
        return s.copyWith(
          name: name,
          cycleTime: cycleTime,
          machineId: machineId,
          machineName: machineName,
          workers: workers,
          eventType: eventType,
          valueType: valueType,
          waitingTimeSec: waitingTimeSec,
          bufferQuantity: bufferQuantity,
          laborCost: laborCost,
          energyCost: energyCost,
          materialCost: materialCost,
          otherCost: otherCost,
        );
      }
      return s;
    }).toList();
    state = state.copyWith(stations: updated);
    saveCurrentLine();
  }

  void updateStationLeanType(
    String id, {
    String? eventType,
    String? valueType,
    double? waitingTimeSec,
  }) {
    final updated = state.stations.map((s) {
      if (s.id == id) {
        return s.copyWith(
          eventType: eventType,
          valueType: valueType,
          waitingTimeSec: waitingTimeSec,
        );
      }
      return s;
    }).toList();
    state = state.copyWith(stations: updated);
    saveCurrentLine();
  }

  void removeStation(String id) {
    final updated = state.stations.where((s) => s.id != id).map((s) {
      final newPrev = s.prevStationIds.where((p) => p != id).toList();
      final newNext = s.nextStationIds.where((n) => n != id).toList();
      return s.copyWith(prevStationIds: newPrev, nextStationIds: newNext);
    }).toList();
    state = state.copyWith(stations: updated);
    saveCurrentLine();
  }

  void linkStations(String fromId, String toId, {int? defaultColor}) {
    final connectionId = '$fromId->$toId';
    final existingConn = state.resolvedConnections.where((c) => c.id == connectionId).firstOrNull;

    final updatedStations = state.stations.map((s) {
      if (s.id == fromId) {
        if (s.nextStationIds.contains(toId)) {
          return s.copyWith(
            nextStationIds: s.nextStationIds.where((id) => id != toId).toList(),
          );
        } else {
          return s.copyWith(nextStationIds: [...s.nextStationIds, toId]);
        }
      }
      if (s.id == toId) {
        if (s.prevStationIds.contains(fromId)) {
          return s.copyWith(
            prevStationIds: s.prevStationIds.where((id) => id != fromId).toList(),
          );
        } else {
          return s.copyWith(prevStationIds: [...s.prevStationIds, fromId]);
        }
      }
      return s;
    }).toList();

    List<LineConnection> updatedConnections = List.from(state.resolvedConnections);
    if (existingConn != null) {
      updatedConnections.removeWhere((c) => c.id == connectionId);
    } else {
      updatedConnections.add(LineConnection(
        id: connectionId,
        fromStationId: fromId,
        toStationId: toId,
        colorValue: defaultColor ?? 0xFFFB8C00,
      ));
    }

    state = state.copyWith(
      stations: updatedStations,
      connections: updatedConnections,
    );
    saveCurrentLine();
  }

  void updateConnection(LineConnection connection) {
    final list = List<LineConnection>.from(state.resolvedConnections);
    final idx = list.indexWhere((c) => c.id == connection.id);
    if (idx >= 0) {
      list[idx] = connection;
    } else {
      list.add(connection);
    }
    state = state.copyWith(connections: list);
    saveCurrentLine();
  }

  void updateConnectionColor(String connectionId, int colorValue) {
    final list = state.resolvedConnections.map((c) {
      if (c.id == connectionId) {
        return c.copyWith(colorValue: colorValue);
      }
      return c;
    }).toList();
    state = state.copyWith(connections: list);
    saveCurrentLine();
  }

  void updateConnectionWaypoints(String connectionId, List<Offset> waypoints) {
    final list = state.resolvedConnections.map((c) {
      if (c.id == connectionId) {
        return c.copyWith(waypoints: waypoints);
      }
      return c;
    }).toList();
    state = state.copyWith(connections: list);
    saveCurrentLine();
  }

  void toggleConnectionCurved(String connectionId) {
    final list = state.resolvedConnections.map((c) {
      if (c.id == connectionId) {
        return c.copyWith(isCurved: !c.isCurved);
      }
      return c;
    }).toList();
    state = state.copyWith(connections: list);
    saveCurrentLine();
  }

  void removeConnection(String connectionId) {
    final parts = connectionId.split('->');
    if (parts.length == 2) {
      linkStations(parts[0], parts[1]);
    } else {
      final list = state.connections.where((c) => c.id != connectionId).toList();
      state = state.copyWith(connections: list);
      saveCurrentLine();
    }
  }

  void updateStationPosition(String id, Offset newPos) {
    state = state.copyWith(
      stations: state.stations.map((s) {
        if (s.id == id) return s.copyWith(position: newPos);
        return s;
      }).toList(),
    );
    saveCurrentLine();
  }

  Future<MachineBalancingData?> fetchMachineDataForBalancing(
      String machineId) async {
    try {
      double calculatedCycleTime = 20.0;
      double calculatedEnergyCost = 0.0;

      // Priority 1: Check work_processes / SOP steps duration
      final sopRes = await DbHelper.query('''
        SELECT SUM(s.duration_minutes) as total_min, COUNT(s.step_id) as step_cnt
        FROM work_processes wp
        JOIN work_process_steps s ON wp.process_id = s.process_id
        WHERE wp.machine_id = @id
      ''', params: {'id': machineId});

      bool capacityFound = false;
      if (sopRes.isNotEmpty) {
        final stepCnt = (sopRes.first['step_cnt'] as num?)?.toInt() ?? 0;
        final totalMin = (sopRes.first['total_min'] as num?)?.toDouble() ?? 0.0;
        if (stepCnt > 0 && totalMin > 0) {
          calculatedCycleTime = totalMin * 60.0;
          capacityFound = true;
        }
      }

      final specRes = await DbHelper.queryOne(
        'SELECT power_kw, capacity, capacity_unit, fuel_consumption_rate, fuel_type FROM machine_specs WHERE machine_id = @id',
        params: {'id': machineId},
      );

      if (specRes != null) {
        final powerKw = (specRes['power_kw'] as num?)?.toDouble() ?? 0.0;
        final elecCost = powerKw * state.electricityRate;

        final fuelRate =
            (specRes['fuel_consumption_rate'] as num?)?.toDouble() ?? 0.0;
        final fuelCost = fuelRate * state.fuelRate;

        calculatedEnergyCost = elecCost + fuelCost;

        final capacity = (specRes['capacity'] as num?)?.toDouble();
        final unit =
            specRes['capacity_unit']?.toString().toLowerCase() ?? '';

        if (capacity != null && capacity > 0) {
          capacityFound = true;
          if (unit.contains('hr') ||
              unit.contains('ชั่วโมง') ||
              unit.contains('ชม.')) {
            calculatedCycleTime = 3600.0 / capacity;
          } else if (unit.contains('min') || unit.contains('นาที')) {
            calculatedCycleTime = 60.0 / capacity;
          } else if (unit.contains('sec') || unit.contains('วินาที')) {
            calculatedCycleTime = 1.0 / capacity;
          } else if (unit.contains('day') || unit.contains('วัน')) {
            calculatedCycleTime = (8.0 * 3600.0) / capacity;
          } else {
            calculatedCycleTime = 3600.0 / capacity;
          }
        }
      }

      if (!capacityFound) {
        final runRes = await DbHelper.queryOne(
          '''SELECT 
              COALESCE(SUM(cumulative_hours), 0) as total_hrs,
              COALESCE(SUM(actual_production), 0) as total_actual
             FROM machine_running_hours
             WHERE machine_id = @id''',
          params: {'id': machineId},
        );
        if (runRes != null) {
          final totalHrs = (runRes['total_hrs'] as num?)?.toDouble() ?? 0.0;
          final totalActual =
              (runRes['total_actual'] as num?)?.toDouble() ?? 0.0;
          if (totalActual > 0) {
            calculatedCycleTime = (totalHrs * 3600) / totalActual;
          }
        }
      }

      return MachineBalancingData(
        cycleTime: calculatedCycleTime,
        energyCost: calculatedEnergyCost,
      );
    } catch (_) {}
    return null;
  }

  Future<String> createNewLine({
    required String lineName,
    String? department,
    double availableTimeMin = 480.0,
    double demandQuantity = 1000.0,
  }) async {
    final newLineId = const Uuid().v4();
    state = LineBalancingState(
      lineId: newLineId,
      lineName: lineName.trim().isNotEmpty ? lineName.trim() : 'สายการผลิตใหม่',
      department: department,
      availableTimeMin: availableTimeMin,
      demandQuantity: demandQuantity,
      electricityRate: state.electricityRate,
      fuelRate: state.fuelRate,
      stations: [],
    );
    await saveCurrentLine();
    return newLineId;
  }

  Future<void> deleteLine(String lineId) async {
    try {
      await ensureTables();
      await DbHelper.execute(
        'DELETE FROM production_line_stations WHERE line_id = @id',
        params: {'id': lineId},
      );
      await DbHelper.execute(
        'DELETE FROM production_lines WHERE line_id = @id',
        params: {'id': lineId},
      );

      if (state.lineId == lineId) {
        final remaining = await DbHelper.query(
          'SELECT line_id FROM production_lines ORDER BY created_at ASC LIMIT 1',
        );
        if (remaining.isNotEmpty) {
          await loadLine(remaining.first['line_id'].toString());
        } else {
          await createNewLine(lineName: 'สายการผลิตที่ 1 (Main Line)');
        }
      }
    } catch (_) {}
  }

  Future<void> renameLine(String lineId, String newName) async {
    try {
      await ensureTables();
      await DbHelper.execute(
        'UPDATE production_lines SET line_name = @name, updated_at = CURRENT_TIMESTAMP WHERE line_id = @id',
        params: {'id': lineId, 'name': newName.trim()},
      );
      if (state.lineId == lineId) {
        state = state.copyWith(lineName: newName.trim());
      }
    } catch (_) {}
  }

  Future<String> duplicateCurrentLine({String? newName}) async {
    final dupName = newName ?? '${state.lineName} (สำเนา)';
    final newLineId = const Uuid().v4();

    state = state.copyWith(
      lineId: newLineId,
      lineName: dupName,
    );
    await saveCurrentLine();
    return newLineId;
  }
}

final lineBalancingProvider =
    StateNotifierProvider<LineBalancingNotifier, LineBalancingState>((ref) {
  return LineBalancingNotifier();
});

final allProductionLinesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  await LineBalancingNotifier.ensureTables();
  final rows = await DbHelper.query('''
    SELECT pl.*, COUNT(pls.station_id) as station_count
    FROM production_lines pl
    LEFT JOIN production_line_stations pls ON pl.line_id = pls.line_id
    GROUP BY pl.line_id
    ORDER BY pl.created_at ASC
  ''');
  return rows;
});
