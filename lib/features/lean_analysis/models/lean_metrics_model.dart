import '../../work_processes/models/work_process_model.dart';
import '../../work_processes/models/work_process_step_model.dart';

class LeanProcessMetrics {
  final WorkProcess process;
  final WorkProcess? baselineProcess; // If comparing Improved vs Current

  const LeanProcessMetrics({
    required this.process,
    this.baselineProcess,
  });

  // Basic Metrics
  int get stepCount => process.steps.length;
  double get totalDurationMinutes => process.totalDurationMinutes;
  double get totalDistanceMeters => process.totalDistanceMeters;
  double get vaDurationMinutes => process.vaDurationMinutes;
  double get nvaDurationMinutes => process.nvaDurationMinutes;
  double get nnvaDurationMinutes => process.nnvaDurationMinutes;
  double get processCycleEfficiency => process.processCycleEfficiency;
  double get wasteRatio => process.wasteRatio;

  // ASME Breakdown
  Map<ProcessEventType, int> get eventCounts {
    final map = <ProcessEventType, int>{};
    for (final type in ProcessEventType.values) {
      map[type] = process.countByEvent(type);
    }
    return map;
  }

  Map<ProcessEventType, double> get eventDurations {
    final map = <ProcessEventType, double>{};
    for (final type in ProcessEventType.values) {
      map[type] = process.durationByEvent(type);
    }
    return map;
  }

  // Before vs After Comparisons (if baseline exists)
  bool get hasComparison => baselineProcess != null;

  double get timeSavedMinutes =>
      hasComparison ? baselineProcess!.totalDurationMinutes - totalDurationMinutes : 0.0;

  double get timeSavedPercent => hasComparison && baselineProcess!.totalDurationMinutes > 0
      ? (timeSavedMinutes / baselineProcess!.totalDurationMinutes) * 100.0
      : 0.0;

  double get distanceSavedMeters =>
      hasComparison ? baselineProcess!.totalDistanceMeters - totalDistanceMeters : 0.0;

  double get distanceSavedPercent => hasComparison && baselineProcess!.totalDistanceMeters > 0
      ? (distanceSavedMeters / baselineProcess!.totalDistanceMeters) * 100.0
      : 0.0;

  int get stepsEliminated =>
      hasComparison ? baselineProcess!.steps.length - process.steps.length : 0;

  double get nvaSavedMinutes =>
      hasComparison ? baselineProcess!.nvaDurationMinutes - nvaDurationMinutes : 0.0;

  double get pceImprovementPercent =>
      hasComparison ? processCycleEfficiency - baselineProcess!.processCycleEfficiency : 0.0;

  // Waste step items
  List<WorkProcessStep> get pureWasteSteps =>
      process.steps.where((s) => s.valueType == LeanValueType.nva).toList();

  List<WorkProcessStep> get necessaryWasteSteps =>
      process.steps.where((s) => s.valueType == LeanValueType.nnva).toList();
}
