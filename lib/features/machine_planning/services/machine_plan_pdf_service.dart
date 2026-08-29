import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/machine_plan_models.dart';

class MachinePlanPdfService {
  static Future<File> generatePdfFile({
    required MachineWeeklyPlan plan,
    String? buildingFilter,
  }) async {
    // Load Thai fonts
    final regularFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf'),
    );

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
    );

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

    // Days list for Mon - Sun (7 days)
    final days = [
      DayOfWeek.mon,
      DayOfWeek.tue,
      DayOfWeek.wed,
      DayOfWeek.thu,
      DayOfWeek.fri,
      DayOfWeek.sat,
      DayOfWeek.sun,
    ];

    // Format dates for each day
    final Map<DayOfWeek, String> dayDateStrings = {};
    for (int i = 0; i < days.length; i++) {
      final date = plan.weekStartDate.add(Duration(days: i));
      // Convert to BE year (2 digits) e.g. 69
      final beYear = (date.year + 543) % 100;
      dayDateStrings[days[i]] =
          '${DateFormat('dd/MM').format(date)}/${beYear.toString().padLeft(2, '0')}';
    }

    final endBe = (plan.weekEndDate.year + 543) % 100;
    final headerRangeStr =
        '${DateFormat('dd').format(plan.weekStartDate)}-${DateFormat('dd/MM').format(plan.weekEndDate)}/${endBe.toString().padLeft(2, '0')}';

    // Day Header Colors
    final dayPdfColors = {
      DayOfWeek.mon: PdfColor.fromHex('FFF59D'), // Yellow
      DayOfWeek.tue: PdfColor.fromHex('F48FB1'), // Pink
      DayOfWeek.wed: PdfColor.fromHex('A5D6A7'), // Green
      DayOfWeek.thu: PdfColor.fromHex('FFCC80'), // Orange
      DayOfWeek.fri: PdfColor.fromHex('90CAF9'), // Blue
      DayOfWeek.sat: PdfColor.fromHex('CE93D8'), // Purple
      DayOfWeek.sun: PdfColor.fromHex('FFCDD2'), // Red
    };

    for (final entry in groupedByBuilding.entries) {
      final buildingName = entry.key;
      final items = entry.value;

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          header: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Text(
                  'รายการ การใช้งานเครื่องจักร ประจำสัปดาห์ $headerRangeStr',
                  style: pw.TextStyle(
                    font: boldFont,
                    fontSize: 16,
                    color: PdfColors.black,
                  ),
                ),
                pw.SizedBox(height: 8),
              ],
            );
          },
          build: (pw.Context context) {
            return [
              // Building Banner Table
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.8),
                columnWidths: {
                  0: const pw.FixedColumnWidth(24), // ลำดับ
                  1: const pw.FixedColumnWidth(105), // เครื่องจักร
                  2: const pw.FlexColumnWidth(1), // Mon
                  3: const pw.FlexColumnWidth(1), // Tue
                  4: const pw.FlexColumnWidth(1), // Wed
                  5: const pw.FlexColumnWidth(1), // Thu
                  6: const pw.FlexColumnWidth(1), // Fri
                  7: const pw.FlexColumnWidth(1), // Sat
                  8: const pw.FlexColumnWidth(1), // Sun
                  9: const pw.FixedColumnWidth(80), // ห้อง
                  10: const pw.FixedColumnWidth(110), // หมายเหตุ
                },
                children: [
                  // Row 1: Building Header row
                  pw.TableRow(
                    children: [
                      pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.symmetric(vertical: 4),
                        color: PdfColor.fromHex('E0E0E0'),
                        child: pw.Text('ลำดับ', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                      ),
                      pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.symmetric(vertical: 4),
                        color: PdfColor.fromHex('E0E0E0'),
                        child: pw.Text(
                          buildingName,
                          style: pw.TextStyle(font: boldFont, fontSize: 13, color: PdfColors.black),
                        ),
                      ),
                      ...days.map((d) {
                        return pw.Container(
                          color: dayPdfColors[d],
                          padding: const pw.EdgeInsets.symmetric(vertical: 2),
                          alignment: pw.Alignment.center,
                          child: pw.Column(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Text(
                                d.labelTh,
                                style: pw.TextStyle(font: boldFont, fontSize: 8),
                              ),
                              pw.Text(
                                dayDateStrings[d] ?? '',
                                style: pw.TextStyle(font: regularFont, fontSize: 7),
                              ),
                            ],
                          ),
                        );
                      }),
                      pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.symmetric(vertical: 4),
                        color: PdfColor.fromHex('E0E0E0'),
                        child: pw.Text('ห้อง', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                      ),
                      pw.Container(
                        alignment: pw.Alignment.center,
                        padding: const pw.EdgeInsets.symmetric(vertical: 4),
                        color: PdfColor.fromHex('E0E0E0'),
                        child: pw.Text('หมายเหตุ', style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.red800)),
                      ),
                    ],
                  ),

                  // Data Rows
                  ...items.asMap().entries.map((itemEntry) {
                    final index = itemEntry.key + 1;
                    final item = itemEntry.value;

                    return pw.TableRow(
                      children: [
                        // No
                        pw.Container(
                          alignment: pw.Alignment.center,
                          padding: const pw.EdgeInsets.all(3),
                          child: pw.Text('$index', style: pw.TextStyle(font: boldFont, fontSize: 8)),
                        ),
                        // Machine Code & Name
                        pw.Container(
                          padding: const pw.EdgeInsets.all(3),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                item.machineName,
                                style: pw.TextStyle(font: boldFont, fontSize: 7.5),
                                maxLines: 2,
                              ),
                              if (item.machineCode.isNotEmpty)
                                pw.Text(
                                  item.machineCode,
                                  style: pw.TextStyle(font: regularFont, fontSize: 6.5, color: PdfColors.blueGrey800),
                                ),
                            ],
                          ),
                        ),
                        // Mon - Sat cells
                        ...days.map((day) {
                          final slot = item.getSlot(day);
                          final isEmpty = slot.isEmpty;
                          final isOt = slot.isOt;

                          PdfColor? cellBg;
                          if (!isEmpty) {
                            if (isOt) {
                              cellBg = PdfColor.fromHex('FFAB91'); // Light red/orange for OT
                            } else {
                              cellBg = PdfColor.fromHex('FFFDE7'); // Light yellow
                            }
                          }

                          return pw.Container(
                            color: cellBg,
                            padding: const pw.EdgeInsets.symmetric(vertical: 3, horizontal: 2),
                            alignment: pw.Alignment.center,
                            child: isEmpty
                                ? pw.SizedBox.shrink()
                                : pw.Column(
                                    mainAxisSize: pw.MainAxisSize.min,
                                    children: [
                                      if (isOt)
                                        pw.Text(
                                          'OT',
                                          style: pw.TextStyle(
                                            font: boldFont,
                                            fontSize: 7.5,
                                            color: PdfColors.red900,
                                          ),
                                        ),
                                      pw.Text(
                                        slot.time,
                                        style: pw.TextStyle(
                                          font: isOt ? boldFont : regularFont,
                                          fontSize: 6.5,
                                          color: isOt ? PdfColors.red900 : PdfColors.black,
                                        ),
                                        textAlign: pw.TextAlign.center,
                                      ),
                                    ],
                                  ),
                          );
                        }),
                        // Room
                        pw.Container(
                          padding: const pw.EdgeInsets.all(3),
                          alignment: pw.Alignment.centerLeft,
                          child: pw.Text(
                            item.room ?? '',
                            style: pw.TextStyle(font: regularFont, fontSize: 7.5),
                          ),
                        ),
                        // Remarks
                        pw.Container(
                          padding: const pw.EdgeInsets.all(3),
                          alignment: pw.Alignment.centerLeft,
                          child: pw.Text(
                            item.remarks,
                            style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 7,
                              color: item.remarks.contains('**') ? PdfColors.red800 : PdfColors.black,
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ];
          },
        ),
      );
    }

    final outputDir = await getApplicationDocumentsDirectory();
    final fileName = 'Machine_Plan_${DateFormat('yyyyMMdd').format(plan.weekStartDate)}.pdf';
    final file = File('${outputDir.path}/$fileName');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  static Future<void> generateAndOpen({
    required MachineWeeklyPlan plan,
    String? buildingFilter,
  }) async {
    final file = await generatePdfFile(plan: plan, buildingFilter: buildingFilter);
    await OpenFilex.open(file.path);
  }
}
