import 'package:flutter/services.dart';
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
  static Future<void> generateMasterPlanPdf({
    required String machineNo,
    required String? machineBrand,
    required String planType,
    required List<Map<String, dynamic>> tasks,
    required AppSettingsState settings,
    required String userName,
    String? createdByName,
    String? approvedByName,
  }) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf')),
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
                      'แผนแม่บทบำรุงรักษา (Master Plan) - $planType',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
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
                child: _infoItem('เครื่องจักร', '$machineNo ${machineBrand ?? ''}'.trim()),
              ),
              pw.Expanded(
                child: _infoItem('วันที่พิมพ์', DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())),
              ),
            ],
          ),
          pw.Row(
            children: [
              pw.Expanded(
                child: _infoItem('ประเภทแผน', planType),
              ),
              pw.Expanded(
                child: _infoItem('ผู้พิมพ์', userName),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          _buildMasterPlanTaskTable(tasks),
          pw.SizedBox(height: 30),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureBox(
                'ผู้ออกแผน', 
                name: createdByName,
              ),
              _signatureBox(
                'ผู้อนุมัติ',
                name: approvedByName,
              ),
            ],
          ),
        ],
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/MasterPlan_${machineNo.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${planType}.pdf");
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(file.path);
  }

  /// Generate a single combined logsheet PDF for ALL machines with plans.
  /// [rows] is the flat JOIN result: one row per task, grouped by machine.
  static Future<void> generateAllMachinesLogsheetPdf({
    required String planType,
    required List<Map<String, dynamic>> rows,
    required AppSettingsState settings,
    required String userName,
  }) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf')),
      ),
    );

    final logoBase64 = settings.get(AppSettingKeys.orgLogo);
    final docRef = settings.get(AppSettingKeys.docPmAmRef, defaultValue: 'F-MA-16 Rev1');
    final companyName = settings.get(AppSettingKeys.orgName, defaultValue: 'โรงงานของเรา');
    final now = DateTime.now();

    pw.MemoryImage? logoImage;
    if (logoBase64.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(base64Decode(logoBase64));
      } catch (e) {
        debugPrint('Logo decode error: $e');
      }
    }

    // Group rows by machine_no
    final Map<String, List<Map<String, dynamic>>> byMachine = {};
    for (final row in rows) {
      final key = '${row['machine_no']} ${row['brand'] ?? ''}'.trim();
      byMachine.putIfAbsent(key, () => []).add(row);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logoImage != null)
                  pw.Container(height: 50, child: pw.Image(logoImage)),
                pw.SizedBox(width: 15),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'บันทึกการบำรุงรักษา (Logsheet) - $planType : ทุกเครื่องจักร',
                      style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(companyName, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 6),
          ],
        ),
        footer: (context) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('หน้า ${context.pageNumber} ของ ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('เอกสารอ้างอิง: $docRef', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  pw.Text('วันที่พิมพ์: ${DateFormat('dd/MM/yyyy HH:mm').format(now)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  pw.Text('ผู้พิมพ์: $userName', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
        ),
        build: (context) {
          final widgets = <pw.Widget>[];

          // One section per machine
          for (final entry in byMachine.entries) {
            final machineName = entry.key;
            final machineTasks = entry.value;

            // Machine header row
            widgets.add(
              pw.Container(
                color: PdfColors.blueGrey700,
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                child: pw.Text(
                  'เครื่องจักร: $machineName',
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                ),
              ),
            );

            // Tasks table
            widgets.add(_buildAllMachinesLogsheetTable(machineTasks));
            widgets.add(pw.SizedBox(height: 12));
          }


          return widgets;
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/Logsheet_All_${planType}_${DateFormat('yyyyMMdd').format(now)}.pdf");
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(file.path);
  }


  static Future<void> generateLogsheetPdf({
    required String machineNo,
    required String? machineBrand,
    required String planType,
    required List<Map<String, dynamic>> tasks,
    required AppSettingsState settings,
    required String userName,
    String? createdByName,
    String? approvedByName,
  }) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf')),
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

    final machineName = '$machineNo ${machineBrand ?? ''}'.trim();
    final now = DateTime.now();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(30),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logoImage != null)
                  pw.Container(height: 50, child: pw.Image(logoImage)),
                pw.SizedBox(width: 15),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'บันทึกการบำรุงรักษา (Logsheet) - $planType',
                        style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.Text(companyName, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('เอกสารอ้างอิง: $docRef', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    pw.Text('วันที่พิมพ์: ${DateFormat('dd/MM/yyyy HH:mm').format(now)}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 5),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 20),
          child: pw.Text('$docRef | หน้า ${context.pageNumber} ของ ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (context) => [
          // Info block
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              children: [
                pw.Row(
                  children: [
                    pw.Expanded(child: _infoItem('เครื่องจักร', machineName)),
                    pw.Expanded(child: _infoItem('ประเภทแผน', planType)),
                  ],
                ),
                pw.Row(
                  children: [
                    pw.Expanded(child: _infoItem('วันที่ดำเนินการ', '...................................')),
                    pw.Expanded(child: _infoItem('รอบที่ดำเนินการ', '...................................')),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          _buildLogsheetTable(tasks),
          pw.SizedBox(height: 30),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureBox('ผู้ปฏิบัติงาน'),
              _signatureBox('หัวหน้างาน / ผู้ตรวจสอบ'),
              _signatureBox('ผู้อนุมัติ', name: approvedByName),
            ],
          ),
        ],
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/Logsheet_${machineName.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}_${planType}_${DateFormat('yyyyMMdd').format(now)}.pdf");
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(file.path);
  }


  static Future<void> generateChecklistPdf({
    required PmSchedule schedule,
    required AppSettingsState settings,
    required String userName,
  }) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf')),
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
              _signatureBox('ผู้ปฏิบัติงาน', name: schedule.assignedToName),
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

  static Future<void> generateMultipleChecklistsPdf({
    required List<PmSchedule> schedules,
    required AppSettingsState settings,
    required String userName,
  }) async {
    if (schedules.isEmpty) return;

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf')),
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

    // Combine headers
    final types = schedules.map((e) => e.planType).toSet().join('/');
    final machines = schedules.map((e) => e.machineNo).toSet().join(', ');
    final planNames = schedules.map((e) => e.planName).toSet().join(', ');
    final assignees = schedules.map((e) => e.assignedToName ?? '-').where((e) => e != '-').toSet().join(', ');
    final assigneeText = assignees.isEmpty ? '-' : assignees;
    final dates = schedules.map((e) => DateFormat('dd/MM/yyyy').format(e.scheduledDate)).toSet().join(', ');

    // Combine tasks
    final List<Map<String, dynamic>> allTasks = [];
    for (var schedule in schedules) {
      final tasks = await DbHelper.query(
        'SELECT * FROM pm_am_tasks WHERE plan_id = @pid ORDER BY task_order',
        params: {'pid': schedule.planId},
      );
      // Optional: if plan names are different, we can prepend it, but user just wants them merged.
      allTasks.addAll(tasks);
    }

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
                      'CHECKLIST: $types',
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
                child: _infoItem('ชื่อแผน', planNames),
              ),
              pw.Expanded(
                child: _infoItem('เครื่องจักร', machines),
              ),
            ],
          ),
          pw.Row(
            children: [
              pw.Expanded(
                child: _infoItem('วันที่กำหนด', dates),
              ),
              pw.Expanded(
                child: _infoItem('ผู้รับผิดชอบ', assigneeText),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          _buildTaskTable(allTasks),
          pw.SizedBox(height: 30),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureBox('ผู้ปฏิบัติงาน', name: assignees.isEmpty ? null : assignees),
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
    final file = File("${output.path}/Bulk_Checklists_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf");
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
        2: const pw.FixedColumnWidth(100),
        3: const pw.FixedColumnWidth(80),
        4: const pw.FixedColumnWidth(100),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('No.', bold: true),
            _cell('รายการตรวจสอบ / งาน', bold: true),
            _cell('มาตรฐานการตรวจ', bold: true),
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
              _cell(t['expected_result']?.toString() ?? '-'),
              _cell(' [  ] P  [  ] F'),
              _cell(''),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildMasterPlanTaskTable(List<Map<String, dynamic>> tasks) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey),
      columnWidths: {
        0: const pw.FixedColumnWidth(30),
        1: const pw.FlexColumnWidth(),
        2: const pw.FixedColumnWidth(100),
        3: const pw.FixedColumnWidth(100),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('No.', bold: true),
            _cell('รายการตรวจสอบ / งาน', bold: true),
            _cell('มาตรฐาน', bold: true),
            _cell('ความถี่', bold: true),
          ],
        ),
        ...tasks.asMap().entries.map((entry) {
          final i = entry.key;
          final t = entry.value;
          
          final String days = t['frequency_days']?.toString() ?? '';
          final String months = t['frequency_months']?.toString() ?? '';
          String freqStr = '';
          if (days.isNotEmpty && months.isNotEmpty) {
            freqStr = 'ทุก $days วัน และ $months เดือน';
          } else if (days.isNotEmpty) {
            freqStr = 'ทุก $days วัน';
          } else if (months.isNotEmpty) {
            freqStr = 'ทุก $months เดือน';
          } else {
            freqStr = '-';
          }
          
          return pw.TableRow(
            children: [
              _cell('${i + 1}'),
              _cell(t['task_name'] as String? ?? '-'),
              _cell(t['expected_result'] as String? ?? '-'),
              _cell(freqStr),
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

  static pw.Widget _signatureBox(String role, {String? name}) {
    return pw.Column(
      children: [
        pw.Container(
          width: 150,
          alignment: pw.Alignment.bottomCenter,
          height: 30,
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide())),
          child: name != null && name.isNotEmpty 
              ? pw.Text(name, style: const pw.TextStyle(fontSize: 10))
              : pw.SizedBox(),
        ),
        pw.SizedBox(height: 5),
        pw.Text(role, style: const pw.TextStyle(fontSize: 8)),
      ],
    );
  }

  static pw.Widget _buildLogsheetTable(List<Map<String, dynamic>> tasks) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FixedColumnWidth(30),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FixedColumnWidth(60),
        4: const pw.FixedColumnWidth(50),
        5: const pw.FixedColumnWidth(80),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
          children: [
            _cell('No.', bold: true),
            _cell('รายการตรวจสอบ', bold: true),
            _cell('มาตรฐาน / ค่าที่ยอมรับ', bold: true),
            _cell('ความถี่', bold: true),
            _cell('ผล', bold: true),
            _cell('หมายเหตุ', bold: true),
          ],
        ),
        ...tasks.asMap().entries.map((entry) {
          final i = entry.key;
          final t = entry.value;

          final String days = t['frequency_days']?.toString() ?? '';
          final String months = t['frequency_months']?.toString() ?? '';
          String freqStr = '';
          if (days.isNotEmpty && months.isNotEmpty) {
            freqStr = '${days}วัน/${months}เดือน';
          } else if (days.isNotEmpty) {
            freqStr = 'ทุก $days วัน';
          } else if (months.isNotEmpty) {
            freqStr = 'ทุก $months เดือน';
          } else {
            freqStr = '-';
          }

          final isEven = i % 2 == 0;
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.white : PdfColors.grey50,
            ),
            children: [
              _cell('${i + 1}'),
              _cell(t['task_name'] as String? ?? '-'),
              _cell(t['expected_result'] as String? ?? '-'),
              _cell(freqStr),
              // Result checkbox column
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('□ ผ่าน', style: const pw.TextStyle(fontSize: 8)),
                    pw.SizedBox(height: 3),
                    pw.Text('□ ไม่ผ่าน', style: const pw.TextStyle(fontSize: 8)),
                  ],
                ),
              ),
              _cell(''),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _buildAllMachinesLogsheetTable(List<Map<String, dynamic>> tasks) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400),
      columnWidths: {
        0: const pw.FixedColumnWidth(25),
        1: const pw.FlexColumnWidth(3),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FixedColumnWidth(70),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
          children: [
            _cell('No.', bold: true),
            _cell('รายการตรวจสอบ', bold: true),
            _cell('มาตรฐาน', bold: true),
            _cell('ความถี่', bold: true),
          ],
        ),
        ...tasks.asMap().entries.map((entry) {
          final i = entry.key;
          final t = entry.value;
          final String days = t['frequency_days']?.toString() ?? '';
          final String months = t['frequency_months']?.toString() ?? '';
          String freqStr = '-';
          if (days.isNotEmpty && months.isNotEmpty) {
            freqStr = '${days}วัน/${months}เดือน';
          } else if (days.isNotEmpty) {
            freqStr = 'ทุก $days วัน';
          } else if (months.isNotEmpty) {
            freqStr = 'ทุก $months เดือน';
          }
          final isEven = i % 2 == 0;
          return pw.TableRow(
            decoration: pw.BoxDecoration(color: isEven ? PdfColors.white : PdfColors.grey50),
            children: [
              _cell('${i + 1}'),
              _cell(t['task_name'] as String? ?? '-'),
              _cell(t['expected_result'] as String? ?? '-'),
              _cell(freqStr),
            ],
          );
        }),
      ],
    );
  }
}
