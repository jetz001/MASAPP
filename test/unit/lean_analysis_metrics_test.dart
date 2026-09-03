import 'package:flutter_test/flutter_test.dart';
import 'package:masapp/features/lean_analysis/models/lean_metrics_model.dart';
import 'package:masapp/features/work_processes/models/work_process_model.dart';
import 'package:masapp/features/work_processes/models/work_process_step_model.dart';

void main() {
  group('LeanProcessMetrics & Production Engineering Calculations', () {
    final now = DateTime.now();

    final baselineSteps = [
      WorkProcessStep(
        stepId: 's1',
        processId: 'p1',
        stepNo: 1,
        description: 'Machine Setup',
        eventType: ProcessEventType.operation,
        distanceMeters: 0.0,
        durationMinutes: 10.0,
        valueType: LeanValueType.va,
        createdAt: now,
      ),
      WorkProcessStep(
        stepId: 's2',
        processId: 'p1',
        stepNo: 2,
        description: 'Transport Parts',
        eventType: ProcessEventType.transportation,
        distanceMeters: 50.0,
        durationMinutes: 15.0,
        valueType: LeanValueType.nva, // Waste
        createdAt: now,
      ),
      WorkProcessStep(
        stepId: 's3',
        processId: 'p1',
        stepNo: 3,
        description: 'Wait for Supervisor Approval',
        eventType: ProcessEventType.delay,
        distanceMeters: 0.0,
        durationMinutes: 25.0,
        valueType: LeanValueType.nva, // Waste
        createdAt: now,
      ),
    ];

    final improvedSteps = [
      WorkProcessStep(
        stepId: 's1_new',
        processId: 'p2',
        stepNo: 1,
        description: 'Optimized Machine Setup',
        eventType: ProcessEventType.operation,
        distanceMeters: 0.0,
        durationMinutes: 10.0,
        valueType: LeanValueType.va,
        createdAt: now,
      ),
      WorkProcessStep(
        stepId: 's2_new',
        processId: 'p2',
        stepNo: 2,
        description: 'Conveyor Transport',
        eventType: ProcessEventType.transportation,
        distanceMeters: 10.0,
        durationMinutes: 5.0,
        valueType: LeanValueType.nnva,
        createdAt: now,
      ),
    ];

    final baselineProcess = WorkProcess(
      processId: 'p1',
      processNo: 'PRC-001',
      title: 'Current Assembly Line',
      methodType: WorkProcessMethodType.current,
      workType: WorkTypeCategory.product,
      status: 'active',
      createdAt: now,
      updatedAt: now,
      steps: baselineSteps,
    );

    final improvedProcess = WorkProcess(
      processId: 'p2',
      processNo: 'PRC-002',
      title: 'Improved Assembly Line',
      methodType: WorkProcessMethodType.improved,
      workType: WorkTypeCategory.product,
      status: 'active',
      createdAt: now,
      updatedAt: now,
      steps: improvedSteps,
    );

    test('Baseline metrics calculate total duration, distance and waste correctly', () {
      final metrics = LeanProcessMetrics(process: baselineProcess);

      expect(metrics.stepCount, equals(3));
      expect(metrics.totalDurationMinutes, equals(50.0)); // 10 + 15 + 25
      expect(metrics.totalDistanceMeters, equals(50.0));
      expect(metrics.vaDurationMinutes, equals(10.0));
      expect(metrics.nvaDurationMinutes, equals(40.0)); // 15 + 25

      // Cycle Efficiency: 10 / 50 * 100 = 20%
      expect(metrics.processCycleEfficiency, closeTo(20.0, 0.01));
      // Waste ratio: 40 / 50 * 100 = 80%
      expect(metrics.wasteRatio, closeTo(80.0, 0.01));
    });

    test('Before vs After comparisons reflect actual savings', () {
      final comparisonMetrics = LeanProcessMetrics(
        process: improvedProcess,
        baselineProcess: baselineProcess,
      );

      expect(comparisonMetrics.hasComparison, isTrue);
      // Time saved: 50 - 15 = 35 minutes
      expect(comparisonMetrics.timeSavedMinutes, equals(35.0));
      // Time saved percent: 35 / 50 * 100 = 70%
      expect(comparisonMetrics.timeSavedPercent, closeTo(70.0, 0.01));

      // Distance saved: 50 - 10 = 40 meters
      expect(comparisonMetrics.distanceSavedMeters, equals(40.0));
      expect(comparisonMetrics.distanceSavedPercent, closeTo(80.0, 0.01));

      // Steps eliminated: 3 - 2 = 1 step
      expect(comparisonMetrics.stepsEliminated, equals(1));
    });
  });
}
