import '../../work_processes/models/work_process_model.dart';
import '../../work_processes/models/work_process_step_model.dart';

/// Represents a single process node in the Value Stream Mapping (VSM)
class VsmStepNode {
  final WorkProcessStep step;
  final int index;
  final bool isBottleneck;
  final double cycleTimeMinutes; // VA processing time
  final double delayTimeMinutes; // NVA / waiting / transport time
  final double distanceMeters;

  const VsmStepNode({
    required this.step,
    required this.index,
    required this.isBottleneck,
    required this.cycleTimeMinutes,
    required this.delayTimeMinutes,
    required this.distanceMeters,
  });

  bool get isPureWaste => step.valueType == LeanValueType.nva;
  bool get isNecessaryWaste => step.valueType == LeanValueType.nnva;
  bool get isValueAdd => step.valueType == LeanValueType.va;
  bool get hasKaizenOpportunity =>
      isBottleneck || isPureWaste || (step.problemCause?.isNotEmpty ?? false);
}

/// Aggregated metrics for Value Stream Mapping
class VsmSummary {
  final double totalLeadTimeMinutes;
  final double totalProcessingTimeMinutes;
  final double totalDelayTimeMinutes;
  final double processCycleEfficiency;
  final double totalDistanceMeters;
  final int totalSteps;
  final int kaizenCount;
  final List<VsmStepNode> nodes;

  const VsmSummary({
    required this.totalLeadTimeMinutes,
    required this.totalProcessingTimeMinutes,
    required this.totalDelayTimeMinutes,
    required this.processCycleEfficiency,
    required this.totalDistanceMeters,
    required this.totalSteps,
    required this.kaizenCount,
    required this.nodes,
  });

  factory VsmSummary.fromProcess(WorkProcess process) {
    final steps = process.steps;
    if (steps.isEmpty) {
      return const VsmSummary(
        totalLeadTimeMinutes: 0,
        totalProcessingTimeMinutes: 0,
        totalDelayTimeMinutes: 0,
        processCycleEfficiency: 0,
        totalDistanceMeters: 0,
        totalSteps: 0,
        kaizenCount: 0,
        nodes: [],
      );
    }

    final avgDuration = process.totalDurationMinutes / steps.length;
    final nodes = <VsmStepNode>[];
    int kaizens = 0;

    for (var i = 0; i < steps.length; i++) {
      final s = steps[i];
      final isVa = s.valueType == LeanValueType.va;
      final isBottleneck =
          s.durationMinutes >= (avgDuration * 1.4) && s.durationMinutes > 5;
      final cycleTime = isVa ? s.durationMinutes : 0.0;
      final delayTime = !isVa ? s.durationMinutes : 0.0;

      final node = VsmStepNode(
        step: s,
        index: i + 1,
        isBottleneck: isBottleneck,
        cycleTimeMinutes: cycleTime,
        delayTimeMinutes: delayTime,
        distanceMeters: s.distanceMeters,
      );

      if (node.hasKaizenOpportunity) {
        kaizens++;
      }
      nodes.add(node);
    }

    final totalLead = process.totalDurationMinutes;
    final totalVa = process.vaDurationMinutes;
    final totalNva = process.nvaDurationMinutes + process.nnvaDurationMinutes;
    final pce = totalLead > 0 ? (totalVa / totalLead) * 100.0 : 0.0;

    return VsmSummary(
      totalLeadTimeMinutes: totalLead,
      totalProcessingTimeMinutes: totalVa,
      totalDelayTimeMinutes: totalNva,
      processCycleEfficiency: pce,
      totalDistanceMeters: process.totalDistanceMeters,
      totalSteps: steps.length,
      kaizenCount: kaizens,
      nodes: nodes,
    );
  }
}

/// RCA 5-Why & Fishbone (Ishikawa 4M1E) analysis model for VSM Bottlenecks
class VsmRcaAnalysis {
  final String processId;
  final String? stepId;
  final String stepDescription;
  final String failureOrWasteType; // 'bottleneck', 'waste_nva', 'delay', 'defect', 'breakdown'
  final String why1;
  final String why2;
  final String why3;
  final String why4;
  final String why5;
  final String rootCause;
  final String correctiveAction;
  final String preventiveAction; // ECRS countermeasure
  final Map<String, List<String>> fishboneCauses; // 'man', 'machine', 'material', 'method', 'environment'

  const VsmRcaAnalysis({
    required this.processId,
    this.stepId,
    required this.stepDescription,
    this.failureOrWasteType = 'bottleneck',
    this.why1 = '',
    this.why2 = '',
    this.why3 = '',
    this.why4 = '',
    this.why5 = '',
    required this.rootCause,
    this.correctiveAction = '',
    this.preventiveAction = '',
    this.fishboneCauses = const {},
  });

  Map<String, dynamic> toMap() {
    return {
      'process_id': processId,
      'step_id': stepId,
      'step_description': stepDescription,
      'failure_or_waste_type': failureOrWasteType,
      'why_1': why1,
      'why_2': why2,
      'why_3': why3,
      'why_4': why4,
      'why_5': why5,
      'root_cause': rootCause,
      'corrective_action': correctiveAction,
      'preventive_action': preventiveAction,
      'fishbone_causes': fishboneCauses,
    };
  }
}
