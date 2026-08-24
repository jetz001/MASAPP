import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/database/db_helper.dart';
import 'models/action_plan_model.dart';

class ActionPlanPdfService {
  static Future<void> generateAndOpen({required ActionPlanRecord plan}) async {
    // Load Thai fonts
    final regularFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf'),
    );
    final boldFont = pw.Font.ttf(
      await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf'),
    );

    final document = pw.Document(
      theme: pw.ThemeData.withFont(
        base: regularFont,
        bold: boldFont,
      ),
    );

    // Fetch Organization Settings
    final settingsRows = await DbHelper.query(
      'SELECT setting_key, setting_value FROM app_settings',
    );
    final settings = {
      for (final r in settingsRows)
        r['setting_key'].toString(): r['setting_value']?.toString() ?? ''
    };
    final orgName = settings['org_name']?.isNotEmpty == true
        ? settings['org_name']!
        : 'ระบบบริหารจัดการคุณภาพและซ่อมบำรุงโรงงาน';
    final orgLogoBase64 = settings['org_logo'] ?? '';

    pw.MemoryImage? logoImage;
    if (orgLogoBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(orgLogoBase64);
        logoImage = pw.MemoryImage(bytes);
      } catch (_) {}
    }

    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    String sourceLabel = 'ปัญหากำหนดเอง';
    if (plan.sourceType == 'work_order') {
      sourceLabel = 'งานซ่อมบำรุง (Work Order)';
    } else if (plan.sourceType == 'line_balancing') {
      sourceLabel = 'สายการผลิต (Line Balancing)';
    } else if (plan.sourceType == 'sop_step') {
      sourceLabel = 'ขั้นตอนการทำงาน (SOP)';
    }

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        header: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      if (logoImage != null)
                        pw.Container(
                          width: 44,
                          height: 44,
                          margin: const pw.EdgeInsets.only(right: 10),
                          child: pw.Image(logoImage),
                        ),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            orgName,
                            style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 13,
                              color: PdfColors.blueGrey800,
                            ),
                          ),
                          pw.Text(
                            'รายงานแผนปฏิบัติการ & การแก้ปัญหา (Action Plan & RCA Report)',
                            style: pw.TextStyle(
                              font: boldFont,
                              fontSize: 11,
                              color: PdfColors.blue900,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'รหัสเอกสาร: F-IE-01 (Rev.1)',
                        style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'พิมพ์เมื่อ: $dateStr',
                        style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'หน้า ${context.pageNumber} / ${context.pagesCount}',
                        style: pw.TextStyle(font: regularFont, fontSize: 8.5, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 6),
              pw.Divider(thickness: 1.2, color: PdfColors.blue800),
              pw.SizedBox(height: 8),
            ],
          );
        },
        build: (pw.Context context) {
          return [
            // 1. Problem Information Header Box
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.RichText(
                          text: pw.TextSpan(
                            children: [
                              pw.TextSpan(
                                text: 'หัวข้อปัญหา / แผนงาน: ',
                                style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.black),
                              ),
                              pw.TextSpan(
                                text: plan.problemTitle,
                                style: pw.TextStyle(font: boldFont, fontSize: 11.5, color: PdfColors.blue900),
                              ),
                            ],
                          ),
                        ),
                      ),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: pw.BoxDecoration(
                          color: plan.status == 'completed' || plan.status == 'closed'
                              ? PdfColors.green100
                              : PdfColors.orange100,
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                          border: pw.Border.all(
                            color: plan.status == 'completed' || plan.status == 'closed'
                                ? PdfColors.green800
                                : PdfColors.orange800,
                            width: 0.6,
                          ),
                        ),
                        child: pw.Text(
                          plan.status == 'completed' || plan.status == 'closed'
                              ? 'เสร็จสมบูรณ์ (Completed)'
                              : 'กำลังดำเนินการ (In-Progress)',
                          style: pw.TextStyle(
                            font: boldFont,
                            fontSize: 9,
                            color: plan.status == 'completed' || plan.status == 'closed'
                                ? PdfColors.green900
                                : PdfColors.orange900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Text(
                        'แหล่งที่มา: $sourceLabel',
                        style: pw.TextStyle(font: regularFont, fontSize: 9.5, color: PdfColors.grey800),
                      ),
                      if (plan.createdAt != null) ...[
                        pw.SizedBox(width: 16),
                        pw.Text(
                          'วันที่บันทึก: ${plan.createdAt}',
                          style: pw.TextStyle(font: regularFont, fontSize: 9.5, color: PdfColors.grey800),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 10),

            // 2. Root Cause & 5-Why Analysis Box
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.red50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.red200, width: 0.8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'สาเหตุรากเหง้าที่แท้จริง (Root Cause):',
                    style: pw.TextStyle(font: boldFont, fontSize: 10.5, color: PdfColors.red900),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    plan.rootCause?.isNotEmpty == true ? plan.rootCause! : 'ยังไม่ระบุสาเหตุรากเหง้า',
                    style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.black),
                  ),
                  if (plan.why1 != null && plan.why1!.isNotEmpty) ...[
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'การวิเคราะห์ 5-Why: 1. ${plan.why1 ?? "-"}  ➔  2. ${plan.why2 ?? "-"}  ➔  3. ${plan.why3 ?? "-"}  ➔  4. ${plan.why4 ?? "-"}  ➔  5. ${plan.why5 ?? "-"}',
                      style: pw.TextStyle(font: regularFont, fontSize: 8.5, color: PdfColors.grey800),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // 3. Action Plan Checklist Table
            pw.Text(
              'ตารางขั้นตอนแผนปฏิบัติการ (Action Plan Checklist)',
              style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.blueGrey900),
            ),
            pw.SizedBox(height: 4),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
              columnWidths: const {
                0: pw.FixedColumnWidth(28),
                1: pw.FlexColumnWidth(5),
                2: pw.FlexColumnWidth(2.5),
                3: pw.FlexColumnWidth(2),
                4: pw.FlexColumnWidth(1.8),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.blue100),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('ลำดับ', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('รายละเอียดขั้นตอนการทำงาน (Action Step)', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('ผู้รับผิดชอบ', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('กำหนดเสร็จ', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(5),
                      child: pw.Text('สถานะ', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 9)),
                    ),
                  ],
                ),
                ...plan.actionSteps.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final step = entry.value;
                  final isDone = step.status == 'completed';

                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: idx % 2 == 0 ? PdfColors.white : PdfColors.grey50),
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text('${idx + 1}', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(step.title, style: pw.TextStyle(font: regularFont, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(step.assignee.isNotEmpty ? step.assignee : '-', style: pw.TextStyle(font: regularFont, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(step.dueDate.isNotEmpty ? step.dueDate : '-', style: pw.TextStyle(font: regularFont, fontSize: 9)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(5),
                        child: pw.Text(
                          isDone ? '✓ เสร็จแล้ว' : (step.status == 'in_progress' ? 'กำลังทำ' : 'รอดำเนินการ'),
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            font: boldFont,
                            fontSize: 8.5,
                            color: isDone ? PdfColors.green800 : PdfColors.orange800,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 12),

            // 4. Verification & Validation (V&V) Section
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.green50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.green300, width: 0.8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'การสอบทานผลสำเร็จหลังการปรับปรุง (Verification & Validation):',
                    style: pw.TextStyle(font: boldFont, fontSize: 10.5, color: PdfColors.green900),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          'ตัวชี้วัด: ${plan.targetMetric?.isNotEmpty == true ? plan.targetMetric! : "-"}',
                          style: pw.TextStyle(font: regularFont, fontSize: 9.5),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          'ก่อนปรับปรุง: ${plan.beforeValue?.toStringAsFixed(1) ?? "-"} ${plan.metricUnit ?? ""}',
                          style: pw.TextStyle(font: regularFont, fontSize: 9.5),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          'เป้าหมาย: ${plan.targetValue?.toStringAsFixed(1) ?? "-"} ${plan.metricUnit ?? ""}',
                          style: pw.TextStyle(font: regularFont, fontSize: 9.5),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          'ผลจริง: ${plan.actualValue?.toStringAsFixed(1) ?? "-"} ${plan.metricUnit ?? ""}',
                          style: pw.TextStyle(font: boldFont, fontSize: 9.5, color: PdfColors.green900),
                        ),
                      ),
                    ],
                  ),
                  if (plan.reductionPercentage != null) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      plan.reductionPercentage! > 0
                          ? 'สรุปผลสำเร็จ: ตัวชี้วัดลดลงได้จริง ${plan.reductionPercentage!.toStringAsFixed(1)}% บรรลุตามเป้าหมาย'
                          : 'สรุปผลสำเร็จ: ตัวชี้วัดเปลี่ยนแปลง ${plan.reductionPercentage!.abs().toStringAsFixed(1)}%',
                      style: pw.TextStyle(font: boldFont, fontSize: 9.5, color: PdfColors.green900),
                    ),
                  ],
                  if (plan.verifiedBy != null && plan.verifiedBy!.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'ผู้ตรวจสอบ: ${plan.verifiedBy} (${plan.verificationDate ?? "-"}) | แผนคงสภาพ/มาตรฐานใหม่: ${plan.standardizationNotes ?? "-"}',
                      style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey800),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // 5. Signature Blocks
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('ผู้จัดทำแผนงาน (Prepared By)', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                    pw.SizedBox(height: 36),
                    pw.Text('(................................................)', style: pw.TextStyle(font: regularFont, fontSize: 8.5)),
                    pw.Text('วันที่: ....../....../......', style: pw.TextStyle(font: regularFont, fontSize: 8.5)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('ผู้ตรวจสอบผล (Verified By)', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                    pw.SizedBox(height: 36),
                    pw.Text(
                      plan.verifiedBy?.isNotEmpty == true
                          ? '(${plan.verifiedBy})'
                          : '(................................................)',
                      style: pw.TextStyle(font: regularFont, fontSize: 8.5),
                    ),
                    pw.Text(
                      plan.verificationDate?.isNotEmpty == true
                          ? 'วันที่: ${plan.verificationDate}'
                          : 'วันที่: ....../....../......',
                      style: pw.TextStyle(font: regularFont, fontSize: 8.5),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('ผู้อนุมัติปิดแผนงาน (Approved By)', style: pw.TextStyle(font: boldFont, fontSize: 9)),
                    pw.SizedBox(height: 36),
                    pw.Text('(................................................)', style: pw.TextStyle(font: regularFont, fontSize: 8.5)),
                    pw.Text('วันที่: ....../....../......', style: pw.TextStyle(font: regularFont, fontSize: 8.5)),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    // Save and open PDF
    final dir = await getTemporaryDirectory();
    final fileName = 'Action_Plan_${plan.rcaId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(await document.save());
    await OpenFilex.open(file.path);
  }
}
