import 'dart:io';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import '../models/machine_plan_models.dart';

class MachinePlanExcelService {
  static Future<File> generateExcelFile({
    required MachineWeeklyPlan plan,
    String? buildingFilter,
  }) async {
    final excel = Excel.createExcel();
    final defaultSheetName = excel.getDefaultSheet();
    if (defaultSheetName != null) {
      excel.delete(defaultSheetName);
    }

    final sheet = excel['Machine_Plan'];

    // Group items by building
    final Map<String, List<MachinePlanItem>> groupedByBuilding = {};
    for (final item in plan.items) {
      final bld = (item.building != null && item.building!.trim().isNotEmpty)
          ? item.building!.trim()
          : 'ส่วนกลาง / อื่นๆ';

      if (buildingFilter != null &&
          buildingFilter.isNotEmpty &&
          buildingFilter != 'ทั้งหมด' &&
          bld != buildingFilter) {
        continue;
      }

      groupedByBuilding.putIfAbsent(bld, () => []).add(item);
    }

    if (groupedByBuilding.isEmpty) {
      groupedByBuilding['ทั้งหมด'] = plan.items;
    }

    final days = [
      DayOfWeek.mon,
      DayOfWeek.tue,
      DayOfWeek.wed,
      DayOfWeek.thu,
      DayOfWeek.fri,
      DayOfWeek.sat,
      DayOfWeek.sun,
    ];

    int rowIndex = 0;

    // Header Title
    sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value =
        TextCellValue(plan.title);
    rowIndex += 2;

    for (final entry in groupedByBuilding.entries) {
      final buildingName = entry.key;
      final items = entry.value;

      // Building Header
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex)).value =
          TextCellValue('【 $buildingName 】');
      rowIndex++;

      // Columns Header
      final headers = [
        'ลำดับ',
        'รหัสเครื่องจักร',
        'ชื่อเครื่องจักร',
        ...days.map((d) {
          final date = plan.weekStartDate.add(Duration(days: days.indexOf(d)));
          return '${d.labelTh} (${DateFormat('dd/MM').format(date)})';
        }),
        'ห้อง',
        'หมายเหตุ',
      ];

      for (int c = 0; c < headers.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex)).value =
            TextCellValue(headers[c]);
      }
      rowIndex++;

      // Items Rows
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        final rowValues = <CellValue>[
          IntCellValue(i + 1),
          TextCellValue(item.machineCode),
          TextCellValue(item.machineName),
          ...days.map((d) {
            final slot = item.getSlot(d);
            if (slot.isEmpty) return TextCellValue('');
            return TextCellValue(slot.isOt ? 'OT ${slot.time}' : slot.time);
          }),
          TextCellValue(item.room ?? ''),
          TextCellValue(item.remarks),
        ];

        for (int c = 0; c < rowValues.length; c++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: rowIndex)).value =
              rowValues[c];
        }
        rowIndex++;
      }

      rowIndex += 2; // Gap between buildings
    }

    final outputDir = await getApplicationDocumentsDirectory();
    final fileName =
        'Machine_Plan_${DateFormat('yyyyMMdd').format(plan.weekStartDate)}.xlsx';
    final file = File('${outputDir.path}/$fileName');
    final bytes = excel.encode();
    if (bytes != null) {
      await file.writeAsBytes(bytes);
    }
    return file;
  }

  static Future<void> generateAndOpen({
    required MachineWeeklyPlan plan,
    String? buildingFilter,
  }) async {
    final file = await generateExcelFile(plan: plan, buildingFilter: buildingFilter);
    await OpenFilex.open(file.path);
  }
}
