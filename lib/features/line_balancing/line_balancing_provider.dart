import 'package:flutter_riverpod/flutter_riverpod.dart';

class WorkstationData {
  final String id;
  final String name;
  final double cycleTime; // in seconds

  WorkstationData({
    required this.id,
    required this.name,
    required this.cycleTime,
  });

  WorkstationData copyWith({String? name, double? cycleTime}) {
    return WorkstationData(
      id: id,
      name: name ?? this.name,
      cycleTime: cycleTime ?? this.cycleTime,
    );
  }
}

class LineBalancingState {
  final double availableTimeMin;
  final double demandQuantity;
  final List<WorkstationData> stations;

  LineBalancingState({
    required this.availableTimeMin,
    required this.demandQuantity,
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

  LineBalancingState copyWith({
    double? availableTimeMin,
    double? demandQuantity,
    List<WorkstationData>? stations,
  }) {
    return LineBalancingState(
      availableTimeMin: availableTimeMin ?? this.availableTimeMin,
      demandQuantity: demandQuantity ?? this.demandQuantity,
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
            WorkstationData(id: '1', name: 'Station 1 (Assembly)', cycleTime: 20),
            WorkstationData(id: '2', name: 'Station 2 (Testing)', cycleTime: 25),
            WorkstationData(id: '3', name: 'Station 3 (Packaging)', cycleTime: 18),
          ],
        ));

  void updateDemand(double demand) {
    state = state.copyWith(demandQuantity: demand);
  }

  void updateAvailableTime(double minutes) {
    state = state.copyWith(availableTimeMin: minutes);
  }

  void addStation(String name, double cycleTime) {
    final newStation = WorkstationData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      cycleTime: cycleTime,
    );
    state = state.copyWith(stations: [...state.stations, newStation]);
  }

  void updateStation(String id, String name, double cycleTime) {
    final updated = state.stations.map((s) {
      if (s.id == id) {
        return s.copyWith(name: name, cycleTime: cycleTime);
      }
      return s;
    }).toList();
    state = state.copyWith(stations: updated);
  }

  void removeStation(String id) {
    final updated = state.stations.where((s) => s.id != id).toList();
    state = state.copyWith(stations: updated);
  }
}

final lineBalancingProvider = StateNotifierProvider<LineBalancingNotifier, LineBalancingState>((ref) {
  return LineBalancingNotifier();
});
