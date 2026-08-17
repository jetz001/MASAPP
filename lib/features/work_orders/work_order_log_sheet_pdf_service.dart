import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/database/db_helper.dart';
import 'work_order_models.dart';

class WorkOrderLogSheetPdfService {
  static Future<void> generateAndOpen({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final document = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf')),
      ),
    );

    // Query data
    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(endDate);

    final rows = await DbHelper.query(
      '''
      SELECT 
        w.wo_id, w.wo_no, w.title, w.status, w.created_at, w.completed_at, w.priority,
        m.machine_name as machine_name, m.machine_no as machine_code,
        u.full_name as assigned_name
      FROM work_orders w
      LEFT JOIN machine_snapshots m ON m.snapshot_id = w.snapshot_id
      LEFT JOIN users u ON u.user_id = w.assigned_to
      WHERE date(w.created_at) >= date(@start) AND date(w.created_at) <= date(@end)
      ORDER BY w.created_at DESC
      ''',
      params: {
        'start': startStr,
        'end': endStr,
      },
    );

    final settingsRows = await DbHelper.query('SELECT setting_key, setting_value FROM app_settings');
    final settings = {
      for (final r in settingsRows)
        r['setting_key'].toString(): r['setting_value']?.toString() ?? ''
    };
    final orgLogoBase64 = settings['org_logo'] ?? '';
    final docRefStr = settings['doc_work_order_log_sheet_ref'] ?? 'F-MA-19 Rev1';
    
    String docCode = 'F-MA-19';
    String docRev = 'Rev.1';
    final parts = docRefStr.split(' ');
    if (parts.length >= 2) {
      docCode = parts[0];
      docRev = parts.sublist(1).join(' ');
      if (!docRev.toLowerCase().contains('.')) {
        docRev = docRev.replaceFirst(RegExp(r'rev', caseSensitive: false), 'Rev.');
      }
    } else if (parts.length == 1) {
      docCode = parts[0];
      docRev = '';
    }

    pw.MemoryImage? logoImage;
    if (orgLogoBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(orgLogoBase64);
        logoImage = pw.MemoryImage(bytes);
      } catch (_) {}
    }

    final df = DateFormat('dd/MM/yyyy', 'th');

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        header: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      flex: 1,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(4),
                        decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
                        child: pw.Center(
                          child: logoImage != null ? pw.Image(logoImage, height: 35, fit: pw.BoxFit.contain) : pw.SizedBox(height: 35),
                        ),
                      ),
                    ),
                    pw.Expanded(
                      flex: 4,
                      child: pw.Table(
                        border: const pw.TableBorder(
                          horizontalInside: pw.BorderSide(width: 0.5),
                          verticalInside: pw.BorderSide(width: 0.5),
                        ),
                        columnWidths: {
                          0: const pw.FlexColumnWidth(2),
                          1: const pw.FlexColumnWidth(4),
                          2: const pw.FlexColumnWidth(2),
                          3: const pw.FlexColumnWidth(2),
                        },
                        children: [
                          pw.TableRow(
                            children: [
                              pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('ระดับเอกสาร', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                              pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('ชื่อเอกสาร', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                              pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('สถานะเอกสาร', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                              pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('รหัสเอกสาร', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                            ],
                          ),
                          pw.TableRow(
                            children: [
                              pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('ฟอร์มเอกสาร', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                              pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('รายงานใบแจ้งซ่อม', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
                              pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(docRev, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                              pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(docCode, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                            ],
                          ),
                        ]
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('ตั้งแต่วันที่: ${df.format(startDate)} ถึงวันที่: ${df.format(endDate)}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('วันที่พิมพ์: ${df.format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
                ],
              ),
              pw.SizedBox(height: 8),
            ],
          );
        },
        build: (context) {
          if (rows.isEmpty) {
            return [
              pw.Center(
                child: pw.Text('ไม่มีข้อมูลใบแจ้งซ่อมในช่วงเวลาที่เลือก',
                    style: const pw.TextStyle(fontSize: 14)),
              )
            ];
          }

          final headers = [
            'ลำดับ',
            'เลขที่ใบงาน',
            'วันที่แจ้ง',
            'วันที่เสร็จ',
            'Days',
            'เครื่องจักร',
            'หัวข้อ/อาการ',
            'ความสำคัญ',
            'ช่างผู้รับผิดชอบ',
            'สถานะ'
          ];

          final tableData = <List<String>>[];
          for (var i = 0; i < rows.length; i++) {
            final row = rows[i];
            final statusEnum = WorkOrderStatusExt.fromDb(row['status'] as String?);
            final createdAtStr = row['created_at'] as String?;
            final dateStr = createdAtStr != null
                ? DateFormat('dd/MM/yyyy HH:mm', 'th').format(DateTime.parse(createdAtStr).toLocal())
                : '-';
            final completedAtStr = row['completed_at'] as String?;
            final compDateStr = completedAtStr != null
                ? DateFormat('dd/MM/yyyy HH:mm', 'th').format(DateTime.parse(completedAtStr).toLocal())
                : '-';
            final priorityStr = (row['priority'] as String?)?.toUpperCase() == 'HIGH' ? 'สูง' : 'ปกติ';

            String durationDays = '-';
            if (createdAtStr != null && completedAtStr != null) {
              final created = DateTime.parse(createdAtStr).toLocal();
              final completed = DateTime.parse(completedAtStr).toLocal();
              if (completed.isAfter(created)) {
                final diffDays = completed.difference(created).inMinutes / (60 * 24);
                durationDays = diffDays.toStringAsFixed(1);
              } else {
                durationDays = '0.0';
              }
            }

            tableData.add([
              (i + 1).toString(),
              row['wo_no']?.toString() ?? '-',
              dateStr,
              compDateStr,
              durationDays,
              '${row['machine_code'] ?? ''} - ${row['machine_name'] ?? ''}',
              row['title']?.toString() ?? '-',
              priorityStr,
              row['assigned_name']?.toString() ?? '-',
              statusEnum.label,
            ]);
          }

          return [
            pw.TableHelper.fromTextArray(
              headers: headers,
              data: tableData,
              border: pw.TableBorder.all(width: 0.5, color: PdfColors.grey400),
              headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 10),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey200),
              cellStyle: const pw.TextStyle(fontSize: 9),
              cellPadding: const pw.EdgeInsets.all(6),
              cellAlignments: {
                0: pw.Alignment.center,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
                5: pw.Alignment.centerLeft,
                6: pw.Alignment.centerLeft,
                7: pw.Alignment.center,
                8: pw.Alignment.centerLeft,
                9: pw.Alignment.center,
              },
              columnWidths: {
                0: const pw.FixedColumnWidth(25),
                1: const pw.FixedColumnWidth(80),
                2: const pw.FixedColumnWidth(65),
                3: const pw.FixedColumnWidth(65),
                4: const pw.FixedColumnWidth(40),
                5: const pw.FlexColumnWidth(2),
                6: const pw.FlexColumnWidth(2),
                7: const pw.FixedColumnWidth(40),
                8: const pw.FlexColumnWidth(1.5),
                9: const pw.FixedColumnWidth(45),
              },
            ),
          ];
        },
      ),
    );

    // Save and open
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/wo_log_sheet_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await file.writeAsBytes(await document.save());
    await OpenFilex.open(file.path);
  }
}
