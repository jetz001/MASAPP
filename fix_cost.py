# -*- coding: utf-8 -*-
import codecs

with codecs.open('lib/features/analytics/analytics_provider.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

start_idx = -1
end_idx = -1
for i, line in enumerate(lines):
    if 'Future<CostAnalysis> getCostAnalysis({' in line:
        start_idx = i
    if start_idx != -1 and i > start_idx + 10 and '/// Get failure predictions' in line:
        end_idx = i - 1
        break

if start_idx != -1 and end_idx != -1:
    new_method = """  Future<CostAnalysis> getCostAnalysis({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final start =
          startDate ?? DateTime.now().subtract(const Duration(days: 30));
      var end = endDate ?? DateTime.now();
      end = DateTime(end.year, end.month, end.day, 23, 59, 59);

      // Get PM cost (placeholder, could query work_orders with PM title)
      const pmCost = 0.0; 

      // Get CM cost (from work_order_labor)
      final cmResult = await DbHelper.queryOne(
        '''SELECT COALESCE(SUM(l.hours * 500), 0) as total 
           FROM work_order_labor l
           JOIN work_orders w ON l.wo_id = w.wo_id
           WHERE w.created_at BETWEEN @start AND @end''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );
      final cmCost = (cmResult?['total'] as num?)?.toDouble() ?? 0;

      // Get spare parts cost
      final partsResult = await DbHelper.queryOne(
        '''SELECT COALESCE(SUM(wp.quantity * sp.unit_cost), 0) as total 
           FROM work_order_parts wp
           JOIN spare_parts sp ON wp.part_id = sp.part_id
           JOIN work_orders w ON wp.wo_id = w.wo_id
           WHERE w.created_at BETWEEN @start AND @end''',
        params: {
          'start': start.toIso8601String(),
          'end': end.toIso8601String(),
        },
      );
      final sparePartsCost = (partsResult?['total'] as num?)?.toDouble() ?? 0;

      final totalCost = pmCost + cmCost + sparePartsCost;

      final breakdown = <CostBreakdown>[
        CostBreakdown(
          category: 'PM (Preventive)',
          amount: pmCost,
          percentage: totalCost > 0 ? (pmCost / totalCost) * 100 : 0,
        ),
        CostBreakdown(
          category: 'CM (Corrective)',
          amount: cmCost,
          percentage: totalCost > 0 ? (cmCost / totalCost) * 100 : 0,
        ),
        CostBreakdown(
          category: 'Spare Parts',
          amount: sparePartsCost,
          percentage: totalCost > 0 ? (sparePartsCost / totalCost) * 100 : 0,
        ),
      ];

      return CostAnalysis(
        breakdown: breakdown,
        totalCost: totalCost,
        pmCost: pmCost,
        cmCost: cmCost,
        sparePartsCost: sparePartsCost,
      );
    } catch (e) {
      return const CostAnalysis(
        breakdown: [],
        totalCost: 0,
        pmCost: 0,
        cmCost: 0,
        sparePartsCost: 0,
      );
    }
  }

"""
    new_lines = lines[:start_idx] + [new_method] + lines[end_idx:]
    with codecs.open('lib/features/analytics/analytics_provider.dart', 'w', encoding='utf-8') as f:
        f.writelines(new_lines)
    print("Replaced getCostAnalysis correctly!")
else:
    print("Could not find start/end")
