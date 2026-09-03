import 'package:flutter_test/flutter_test.dart';
import 'package:masapp/features/work_orders/work_order_models.dart';

void main() {
  group('WorkOrder Model & Enums', () {
    test('WorkOrderStatus fromDb and dbValue round-trip', () {
      expect(WorkOrderStatusExt.fromDb('pending'), equals(WorkOrderStatus.pending));
      expect(WorkOrderStatusExt.fromDb('approved'), equals(WorkOrderStatus.approved));
      expect(WorkOrderStatusExt.fromDb('in_progress'), equals(WorkOrderStatus.inProgress));
      expect(WorkOrderStatusExt.fromDb('completed'), equals(WorkOrderStatus.completed));
      expect(WorkOrderStatusExt.fromDb('cancelled'), equals(WorkOrderStatus.cancelled));
      expect(WorkOrderStatusExt.fromDb('rejected'), equals(WorkOrderStatus.rejected));
      expect(WorkOrderStatusExt.fromDb('outsourced'), equals(WorkOrderStatus.outsourced));
      expect(WorkOrderStatusExt.fromDb('unknown_status'), equals(WorkOrderStatus.pending));

      // dbValue matching
      expect(WorkOrderStatus.inProgress.dbValue, equals('in_progress'));
      expect(WorkOrderStatus.approved.dbValue, equals('approved'));
      expect(WorkOrderStatus.completed.dbValue, equals('completed'));
    });

    test('WorkOrderPriority fromDb and dbValue round-trip', () {
      expect(WorkOrderPriorityExt.fromDb('low'), equals(WorkOrderPriority.low));
      expect(WorkOrderPriorityExt.fromDb('normal'), equals(WorkOrderPriority.normal));
      expect(WorkOrderPriorityExt.fromDb('high'), equals(WorkOrderPriority.high));
      expect(WorkOrderPriorityExt.fromDb('urgent'), equals(WorkOrderPriority.urgent));
      expect(WorkOrderPriorityExt.fromDb('unknown'), equals(WorkOrderPriority.normal));

      expect(WorkOrderPriority.urgent.dbValue, equals('urgent'));
      expect(WorkOrderPriority.urgent.label, equals('ด่วน'));
    });
  });
}
