import 'dart:ui';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/db_helper.dart';

class MachineBalancingData {
  final double cycleTime;
  final double energyCost;
  final int workers;

  MachineBalancingData({required this.cycleTime, required this.energyCost, this.workers = 1});
}

class WorkstationData {
  final String id;
  final String name;
  final double cycleTime; // in seconds
  final String? machineId;
  final String? machineName;
  final int workers; // number of workers

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
    this.laborCost = 300.0,
    this.energyCost = 0.0,
    this.materialCost = 0.0,
    this.otherCost = 0.0,
    this.prevStationIds = const [],
    this.nextStationIds = const [],
    this.position = Offset.zero,
  });

  double get totalHourlyCost => laborCost + energyCost + materialCost + otherCost;

  WorkstationData copyWith({
    String? name, 
    double? cycleTime, 
    String? machineId, 
    String? machineName, 
    int? workers,
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

class LineBalancingState {
  final double availableTimeMin;
  final double demandQuantity;
  final double electricityRate;
  final double fuelRate;
  final List<WorkstationData> stations;

  LineBalancingState({
    required this.availableTimeMin,
    required this.demandQuantity,
    this.electricityRate = 4.0, // Default 4 THB/kWh
    this.fuelRate = 30.0,       // Default 30 THB/L
    required this.stations,
  });

  double get taktTimeSec => demandQuantity > 0 ? (availableTimeMin * 60) / demandQuantity : 0;
  
  double get totalCycleTime => stations.fold(0.0, (sum, st) => sum + st.cycleTime);
  
  double get maxCycleTime {
    if (stations.isEmpty) return 0;
    return stations.map((e) => e.cycleTime).reduce((a, b) => a > b ? a : b);
  }

  double get lineEfficiency {
    if (stations.isEmpty || maxCycleTime == 0) return 0;
    return (totalCycleTime / (stations.length * maxCycleTime)) * 100;
  }

  double get balanceDelay => 100 - lineEfficiency;

  // New metrics
  double get leadTimeSec {
    if (stations.isEmpty) return 0.0;
    
    // Find root nodes (no prev)
    final Map<String, WorkstationData> nodeMap = { for (var s in stations) s.id: s };
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
      
      final result = node.cycleTime + maxChildPath;
      maxPath[nodeId] = result;
      return result;
    }
    
    final roots = stations.where((s) => s.prevStationIds.isEmpty).toList();
    if (roots.isEmpty) return totalCycleTime; // fallback if circular
    
    double maxLeadTime = 0.0;
    for (final root in roots) {
      final pathTime = findLongestPath(root.id);
      if (pathTime > maxLeadTime) maxLeadTime = pathTime;
    }
    
    return maxLeadTime;
  }
  
  double get totalLaborCost => stations.fold(0.0, (sum, st) => sum + st.laborCost) * (availableTimeMin / 60);
  double get totalEnergyCost => stations.fold(0.0, (sum, st) => sum + st.energyCost) * (availableTimeMin / 60);
  double get totalMaterialCost => stations.fold(0.0, (sum, st) => sum + st.materialCost) * (availableTimeMin / 60);
  double get totalOtherCost => stations.fold(0.0, (sum, st) => sum + st.otherCost) * (availableTimeMin / 60);

  double get totalOperationalCost => totalLaborCost + totalEnergyCost + totalMaterialCost + totalOtherCost;

  int get totalWorkers => stations.fold(0, (sum, st) => sum + st.workers);

  LineBalancingState copyWith({
    double? availableTimeMin,
    double? demandQuantity,
    double? electricityRate,
    double? fuelRate,
    List<WorkstationData>? stations,
  }) {
    return LineBalancingState(
      availableTimeMin: availableTimeMin ?? this.availableTimeMin,
      demandQuantity: demandQuantity ?? this.demandQuantity,
      electricityRate: electricityRate ?? this.electricityRate,
      fuelRate: fuelRate ?? this.fuelRate,
      stations: stations ?? this.stations,
    );
  }
}

class LineBalancingNotifier extends StateNotifier<LineBalancingState> {
  LineBalancingNotifier()
      : super(LineBalancingState(
          availableTimeMin: 480, // 8 hours
          demandQuantity: 1000,
          stations: [
            WorkstationData(id: '1', name: 'Station 1 (Assembly)', cycleTime: 20, workers: 1, laborCost: 300),
            WorkstationData(id: '2', name: 'Station 2 (Testing)', cycleTime: 25, workers: 1, laborCost: 300),
            WorkstationData(id: '3', name: 'Station 3 (Packaging)', cycleTime: 18, workers: 1, laborCost: 300),
          ],
        ));

  void updateDemand(double demand) {
    state = state.copyWith(demandQuantity: demand);
  }

  void updateAvailableTime(double minutes) {
    state = state.copyWith(availableTimeMin: minutes);
  }

  void updateRates(double elecRate, double fRate) {
    state = state.copyWith(electricityRate: elecRate, fuelRate: fRate);
    // Note: To be fully reactive, updating rates should recalculate existing stations' energy costs if linked. 
    // For simplicity, we just apply to new fetches.
  }

    void addStation(String name, double cycleTime, {
    String? machineId, 
    String? machineName, 
    int workers = 1,
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
  }

  void updateStation(String id, String name, double cycleTime, {
    String? machineId, 
    String? machineName, 
    int? workers,
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
          laborCost: laborCost,
          energyCost: energyCost,
          materialCost: materialCost,
          otherCost: otherCost,
        );
      }
      return s;
    }).toList();
    state = state.copyWith(stations: updated);
  }

    void removeStation(String id) {
    final updated = state.stations.where((s) => s.id != id).map((s) {
      // Remove references to this deleted station
      final newPrev = s.prevStationIds.where((p) => p != id).toList();
      final newNext = s.nextStationIds.where((n) => n != id).toList();
      return s.copyWith(prevStationIds: newPrev, nextStationIds: newNext);
    }).toList();
    state = state.copyWith(stations: updated);
  }

  
  void linkStations(String fromId, String toId) {
    state = state.copyWith(
      stations: state.stations.map((s) {
        if (s.id == fromId) {
          if (s.nextStationIds.contains(toId)) {
            // Unlink
            return s.copyWith(nextStationIds: s.nextStationIds.where((id) => id != toId).toList());
          } else {
            return s.copyWith(nextStationIds: [...s.nextStationIds, toId]);
          }
        }
        if (s.id == toId) {
          if (s.prevStationIds.contains(fromId)) {
            // Unlink
            return s.copyWith(prevStationIds: s.prevStationIds.where((id) => id != fromId).toList());
          } else {
            return s.copyWith(prevStationIds: [...s.prevStationIds, fromId]);
          }
        }
        return s;
      }).toList()
    );
  }

  void updateStationPosition(String id, Offset newPos) {
    state = state.copyWith(
      stations: state.stations.map((s) {
        if (s.id == id) return s.copyWith(position: newPos);
        return s;
      }).toList()
    );
  }

  Future<MachineBalancingData?> fetchMachineDataForBalancing(String machineId) async {
    try {
      double calculatedCycleTime = 20.0; // fallback
      double calculatedEnergyCost = 0.0;

      // Fetch specs for capacity and operational cost calculation
      final specRes = await DbHelper.queryOne(
        'SELECT power_kw, capacity, capacity_unit, fuel_consumption_rate, fuel_type FROM machine_specs WHERE machine_id = @id',
        params: {'id': machineId}
      );
      
      bool capacityFound = false;
      if (specRes != null) {
        // Energy cost calculation
        final powerKw = (specRes['power_kw'] as num?)?.toDouble() ?? 0.0;
        final elecCost = powerKw * state.electricityRate; 
        
        final fuelRate = (specRes['fuel_consumption_rate'] as num?)?.toDouble() ?? 0.0;
        final fuelCost = fuelRate * state.fuelRate;

        calculatedEnergyCost = elecCost + fuelCost;
        
        // Capacity for cycle time
        final capacity = (specRes['capacity'] as num?)?.toDouble();
        final unit = specRes['capacity_unit']?.toString().toLowerCase() ?? '';
        
        if (capacity != null && capacity > 0) {
          capacityFound = true;
          if (unit.contains('hr') || unit.contains('ชั่วโมง') || unit.contains('ชม.')) {
            calculatedCycleTime = 3600.0 / capacity;
          } else if (unit.contains('min') || unit.contains('นาที')) {
            calculatedCycleTime = 60.0 / capacity;
          } else if (unit.contains('sec') || unit.contains('วินาที')) {
            calculatedCycleTime = 1.0 / capacity;
          } else if (unit.contains('day') || unit.contains('วัน')) {
            calculatedCycleTime = (8.0 * 3600.0) / capacity; // assume 8 hr day
          } else {
            // Default assume per hour
            calculatedCycleTime = 3600.0 / capacity;
          }
        }
      }

      // If no capacity in specs, fallback to running hours history
      if (!capacityFound) {
        final runRes = await DbHelper.queryOne(
          '''SELECT 
              COALESCE(SUM(cumulative_hours), 0) as total_hrs,
              COALESCE(SUM(actual_production), 0) as total_actual
             FROM machine_running_hours
             WHERE machine_id = @id''',
          params: {'id': machineId}
        );
        if (runRes != null) {
          final totalHrs = (runRes['total_hrs'] as num?)?.toDouble() ?? 0.0;
          final totalActual = (runRes['total_actual'] as num?)?.toDouble() ?? 0.0;
          if (totalActual > 0) {
             calculatedCycleTime = (totalHrs * 3600) / totalActual; 
          }
        }
      }

      return MachineBalancingData(cycleTime: calculatedCycleTime, energyCost: calculatedEnergyCost);
    } catch (e) {
      print('Error calculating machine data: $e');
    }
    return null;
  }
}

final lineBalancingProvider = StateNotifierProvider<LineBalancingNotifier, LineBalancingState>((ref) {
  return LineBalancingNotifier();
});
