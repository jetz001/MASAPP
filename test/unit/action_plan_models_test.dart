import 'package:flutter_test/flutter_test.dart';
import 'package:masapp/features/action_plans/models/action_plan_model.dart';

void main() {
  group('ActionPlanRecord & ActionStepItem Model Tests', () {
    test('ActionStepItem JSON round-trip', () {
      final step = ActionStepItem(
        id: 'step-1',
        title: 'Check hydraulic oil pressure',
        assignee: 'Technician Somchai',
        dueDate: '2026-09-10',
        status: 'in_progress',
        note: 'Inspect relief valve setting',
      );

      final json = step.toJson();
      expect(json['id'], equals('step-1'));
      expect(json['status'], equals('in_progress'));

      final restored = ActionStepItem.fromJson(json);
      expect(restored.id, equals('step-1'));
      expect(restored.title, equals('Check hydraulic oil pressure'));
      expect(restored.assignee, equals('Technician Somchai'));
      expect(restored.note, equals('Inspect relief valve setting'));
    });

    test('ActionPlanRecord calculates progress and reduction percentage correctly', () {
      final plan = ActionPlanRecord(
        rcaId: 'RCA-2026-001',
        sourceType: 'work_order',
        problemTitle: 'Hydraulic overheat',
        rcaMethod: '5why',
        beforeValue: 120.0,
        targetValue: 80.0,
        actualValue: 75.0,
        metricUnit: '°C',
        actionSteps: [
          ActionStepItem(id: '1', title: 'Clean heat exchanger', status: 'completed'),
          ActionStepItem(id: '2', title: 'Replace coolant filter', status: 'completed'),
          ActionStepItem(id: '3', title: 'Install temp sensor', status: 'pending'),
          ActionStepItem(id: '4', title: 'Operator training', status: 'pending'),
        ],
      );

      expect(plan.totalStepsCount, equals(4));
      expect(plan.completedStepsCount, equals(2));
      expect(plan.progress, equals(0.5)); // 50%

      // Reduction: ((120 - 75) / 120) * 100 = 45 / 120 * 100 = 37.5%
      expect(plan.reductionPercentage, closeTo(37.5, 0.01));
    });

    test('ActionPlanRecord handles empty steps safely', () {
      final emptyPlan = ActionPlanRecord(
        rcaId: 'RCA-002',
        sourceType: 'custom',
        problemTitle: 'Test problem',
        actionSteps: [],
      );

      expect(emptyPlan.totalStepsCount, equals(0));
      expect(emptyPlan.completedStepsCount, equals(0));
      expect(emptyPlan.progress, equals(0.0));
      expect(emptyPlan.reductionPercentage, isNull);
    });
  });
}
