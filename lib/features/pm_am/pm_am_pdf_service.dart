import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';
import '../../core/database/db_helper.dart';
import 'pm_am_screen.dart';
import '../settings/settings_provider.dart';

class PmAmPdfService {
  static Future<void> generateChecklistPdf({
    required PmSchedule schedule,
    required AppSettingsState settings,
    required String userName,
  }) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.sarabunRegular(),
        bold: await PdfGoogleFonts.sarabunBold(),
      ),
    );

    final logoBase64 = settings.get(AppSettingKeys.orgLogo);
    final docRef = settings.get(AppSettingKeys.docPmAmRef, defaultValue: 'F-MA-16 Rev1');
    final companyName = settings.get(AppSettingKeys.orgName, defaultValue: 'โรงงานของเรา');

    pw.MemoryImage? logoImage;
    if (logoBase64.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(base64Decode(logoBase64));
      } catch (e) {
        debugPrint('Logo decode error: $e');
      }
    }

    // Fetch tasks
    final tasks = await DbHelper.query(
      'SELECT * FROM pm_am_tasks WHERE plan_id = @pid ORDER BY task_order',
      params: {'pid': schedule.planId},
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        header: (context) => pw.Column(
          children: [
            pw.Row(
              children: [
                if (logoImage != null)
                  pw.Container(height: 40, child: pw.Image(logoImage)),
                pw.SizedBox(width: 15),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'CHECKLIST: ${schedule.planType}',
                      style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(companyName, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 20),
          child: pw.Text('$docRef | หน้า ${context.pageNumber} ของ ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (context) => [
          pw.Row(
            children: [
              pw.Expanded(
                child: _infoItem('ชื่อแผน', schedule.planName),
              ),
              pw.Expanded(
                child: _infoItem('เครื่องจักร', schedule.machineNo),
              ),
            ],
          ),
          pw.Row(
            children: [
              pw.Expanded(
                child: _infoItem('วันที่กำหนด', DateFormat('dd/MM/yyyy').format(schedule.scheduledDate)),
              ),
              pw.Expanded(
                child: _infoItem('ผู้รับผิดชอบ', schedule.assignedToName ?? '-'),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          _buildTaskTable(tasks),
          pw.SizedBox(height: 30),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureBox('ผู้ปฏิบัติงาน'),
              pw.Column(
                children: [
                  pw.Container(width: 150, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide()))),
                  pw.SizedBox(height: 5),
                  pw.Text(userName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.Text('ผู้ตรวจสอบ / หัวหน้างาน', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/Checklist_${schedule.planCode}_${DateFormat('yyyyMMdd').format(schedule.scheduledDate)}.pdf");
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(file.path);
  }

  static pw.Widget _infoItem(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(text: '$label: ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
      ),
    );
  }

  static pw.Widget _buildTaskTable(List<Map<String, dynamic>> tasks) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey),
      columnWidths: {
        0: const pw.FixedColumnWidth(30),
        1: const pw.FlexColumnWidth(),
        2: const pw.FixedColumnWidth(60),
        3: const pw.FixedColumnWidth(80),
        4: const pw.FixedColumnWidth(100),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('No.', bold: true),
            _cell('รายการตรวจสอบ / งาน', bold: true),
            _cell('ประเภท', bold: true),
            _cell('ผลการตรวจ', bold: true),
            _cell('หมายเหตุ / ค่าที่วัดได้', bold: true),
          ],
        ),
        ...tasks.asMap().entries.map((entry) {
          final i = entry.key;
          final t = entry.value;
          return pw.TableRow(
            children: [
              _cell('${i + 1}'),
              _cell(t['task_name'] as String? ?? '-'),
              _cell(t['task_type']?.toString().toUpperCase() ?? '-'),
              _cell(' [  ] P  [  ] F'),
              _cell(''),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _signatureBox(String label) {
    return pw.Column(
      children: [
        pw.Container(
          width: 150,
          height: 40,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey)),
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
      ],
    );
  }
}
