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

    final has5Why = (plan.why1 != null && plan.why1!.isNotEmpty) ||
        (plan.why2 != null && plan.why2!.isNotEmpty) ||
        (plan.why3 != null && plan.why3!.isNotEmpty);

    final has4M1E = (plan.fishboneMan != null && plan.fishboneMan!.isNotEmpty) ||
        (plan.fishboneMachine != null && plan.fishboneMachine!.isNotEmpty) ||
        (plan.fishboneMaterial != null && plan.fishboneMaterial!.isNotEmpty) ||
        (plan.fishboneMethod != null && plan.fishboneMethod!.isNotEmpty) ||
        (plan.fishboneEnv != null && plan.fishboneEnv!.isNotEmpty);

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
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
                          width: 40,
                          height: 40,
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
                              fontSize: 12,
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
                        style: pw.TextStyle(font: regularFont, fontSize: 8.5, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'พิมพ์เมื่อ: $dateStr',
                        style: pw.TextStyle(font: regularFont, fontSize: 8.5, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        'หน้า ${context.pageNumber} / ${context.pagesCount}',
                        style: pw.TextStyle(font: regularFont, fontSize: 8, color: PdfColors.grey600),
                      ),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 5),
              pw.Divider(thickness: 1, color: PdfColors.blue800),
              pw.SizedBox(height: 6),
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
                                style: pw.TextStyle(font: boldFont, fontSize: 10.5, color: PdfColors.black),
                              ),
                              pw.TextSpan(
                                text: plan.problemTitle,
                                style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.blue900),
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
                            fontSize: 8.5,
                            color: plan.status == 'completed' || plan.status == 'closed'
                                ? PdfColors.green900
                                : PdfColors.orange900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Text(
                        'แหล่งที่มา: $sourceLabel',
                        style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey800),
                      ),
                      if (plan.createdAt != null) ...[
                        pw.SizedBox(width: 16),
                        pw.Text(
                          'วันที่บันทึก: ${plan.createdAt}',
                          style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey800),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            // 2. Root Cause Banner (Clean Highlight)
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.red50,
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                border: pw.Border.all(color: PdfColors.red300, width: 0.8),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.red700,
                          borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                        ),
                        child: pw.Text(
                          'สาเหตุรากเหง้า (Root Cause)',
                          style: pw.TextStyle(font: boldFont, fontSize: 8.5, color: PdfColors.white),
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    plan.rootCause?.isNotEmpty == true ? plan.rootCause! : 'ยังไม่ระบุสาเหตุรากเหง้า',
                    style: pw.TextStyle(font: boldFont, fontSize: 9.5, color: PdfColors.black),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            // 3. 5-Why Analysis Drill-down Table (Structured View)
            if (has5Why) ...[
              pw.Text(
                'การวิเคราะห์สาเหตุเชิงลึก (5-Why Analysis)',
                style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.blueGrey900),
              ),
              pw.SizedBox(height: 3),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: const {
                  0: pw.FixedColumnWidth(60),
                  1: pw.FlexColumnWidth(1),
                },
                children: [
                  if (plan.why1 != null && plan.why1!.isNotEmpty)
                    _buildWhyPdfRow('Why #1', plan.why1!, regularFont, boldFont, PdfColors.blue50),
                  if (plan.why2 != null && plan.why2!.isNotEmpty)
                    _buildWhyPdfRow('Why #2', plan.why2!, regularFont, boldFont, PdfColors.white),
                  if (plan.why3 != null && plan.why3!.isNotEmpty)
                    _buildWhyPdfRow('Why #3', plan.why3!, regularFont, boldFont, PdfColors.blue50),
                  if (plan.why4 != null && plan.why4!.isNotEmpty)
                    _buildWhyPdfRow('Why #4', plan.why4!, regularFont, boldFont, PdfColors.white),
                  if (plan.why5 != null && plan.why5!.isNotEmpty)
                    _buildWhyPdfRow('Why #5 (Root)', plan.why5!, regularFont, boldFont, PdfColors.red50),
                ],
              ),
              pw.SizedBox(height: 8),
            ],

            // 4. Ishikawa 4M1E Factors Table (If present)
            if (has4M1E) ...[
              pw.Text(
                'การวิเคราะห์ผังก้างปลา (Ishikawa Diagram - 4M1E)',
                style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.blueGrey900),
              ),
              pw.SizedBox(height: 3),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: const {
                  0: pw.FixedColumnWidth(90),
                  1: pw.FlexColumnWidth(1),
                },
                children: [
                  if (plan.fishboneMan != null && plan.fishboneMan!.isNotEmpty)
                    _build4mPdfRow('คน (Man)', plan.fishboneMan!, regularFont, boldFont),
                  if (plan.fishboneMachine != null && plan.fishboneMachine!.isNotEmpty)
                    _build4mPdfRow('เครื่องจักร (Machine)', plan.fishboneMachine!, regularFont, boldFont),
                  if (plan.fishboneMaterial != null && plan.fishboneMaterial!.isNotEmpty)
                    _build4mPdfRow('วัตถุดิบ/อะไหล่ (Material)', plan.fishboneMaterial!, regularFont, boldFont),
                  if (plan.fishboneMethod != null && plan.fishboneMethod!.isNotEmpty)
                    _build4mPdfRow('วิธีการ/คู่มือ (Method)', plan.fishboneMethod!, regularFont, boldFont),
                  if (plan.fishboneEnv != null && plan.fishboneEnv!.isNotEmpty)
                    _build4mPdfRow('สภาพแวดล้อม (Environment)', plan.fishboneEnv!, regularFont, boldFont),
                ],
              ),
              pw.SizedBox(height: 8),
            ],

            // 5. Action Plan Checklist Table
            pw.Text(
              'ตารางขั้นตอนแผนปฏิบัติการ (Action Plan Checklist)',
              style: pw.TextStyle(font: boldFont, fontSize: 10.5, color: PdfColors.blueGrey900),
            ),
            pw.SizedBox(height: 3),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
              columnWidths: const {
                0: pw.FixedColumnWidth(26),
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
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('ลำดับ', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('รายละเอียดขั้นตอนการทำงาน (Action Step)', style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('ผู้รับผิดชอบ', style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('กำหนดเสร็จ', style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(4),
                      child: pw.Text('สถานะ', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
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
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text('${idx + 1}', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(step.title, style: pw.TextStyle(font: regularFont, fontSize: 8.5)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(step.assignee.isNotEmpty ? step.assignee : '-', style: pw.TextStyle(font: regularFont, fontSize: 8.5)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(step.dueDate.isNotEmpty ? step.dueDate : '-', style: pw.TextStyle(font: regularFont, fontSize: 8.5)),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(4),
                        child: pw.Text(
                          isDone ? '✓ เสร็จแล้ว' : (step.status == 'in_progress' ? 'กำลังทำ' : 'รอดำเนินการ'),
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(
                            font: boldFont,
                            fontSize: 8,
                            color: isDone ? PdfColors.green800 : PdfColors.orange800,
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 10),

            // 6. Verification & Validation (V&V) Section
            pw.Container(
              padding: const pw.EdgeInsets.all(7),
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
                    style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.green900),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Row(
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                          'ตัวชี้วัด: ${plan.targetMetric?.isNotEmpty == true ? plan.targetMetric! : "-"}',
                          style: pw.TextStyle(font: regularFont, fontSize: 9),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          'ก่อนปรับปรุง: ${plan.beforeValue?.toStringAsFixed(1) ?? "-"} ${plan.metricUnit ?? ""}',
                          style: pw.TextStyle(font: regularFont, fontSize: 9),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          'เป้าหมาย: ${plan.targetValue?.toStringAsFixed(1) ?? "-"} ${plan.metricUnit ?? ""}',
                          style: pw.TextStyle(font: regularFont, fontSize: 9),
                        ),
                      ),
                      pw.Expanded(
                        child: pw.Text(
                          'ผลจริง: ${plan.actualValue?.toStringAsFixed(1) ?? "-"} ${plan.metricUnit ?? ""}',
                          style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.green900),
                        ),
                      ),
                    ],
                  ),
                  if (plan.reductionPercentage != null) ...[
                    pw.SizedBox(height: 3),
                    pw.Text(
                      plan.reductionPercentage! > 0
                          ? 'สรุปผลสำเร็จ: ตัวชี้วัดลดลงได้จริง ${plan.reductionPercentage!.toStringAsFixed(1)}% บรรลุตามเป้าหมาย'
                          : 'สรุปผลสำเร็จ: ตัวชี้วัดเปลี่ยนแปลง ${plan.reductionPercentage!.abs().toStringAsFixed(1)}%',
                      style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.green900),
                    ),
                  ],
                  if (plan.verifiedBy != null && plan.verifiedBy!.isNotEmpty) ...[
                    pw.SizedBox(height: 3),
                    pw.Text(
                      'ผู้ตรวจสอบ: ${plan.verifiedBy} (${plan.verificationDate ?? "-"}) | แผนคงสภาพ/มาตรฐานใหม่: ${plan.standardizationNotes ?? "-"}',
                      style: pw.TextStyle(font: regularFont, fontSize: 8.5, color: PdfColors.grey800),
                    ),
                  ],
                ],
              ),
            ),
            pw.SizedBox(height: 20),

            // 7. Signature Blocks
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('ผู้จัดทำแผนงาน (Prepared By)', style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
                    pw.SizedBox(height: 30),
                    pw.Text('(................................................)', style: pw.TextStyle(font: regularFont, fontSize: 8)),
                    pw.Text('วันที่: ....../....../......', style: pw.TextStyle(font: regularFont, fontSize: 8)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('ผู้ตรวจสอบผล (Verified By)', style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
                    pw.SizedBox(height: 30),
                    pw.Text(
                      plan.verifiedBy?.isNotEmpty == true
                          ? '(${plan.verifiedBy})'
                          : '(................................................)',
                      style: pw.TextStyle(font: regularFont, fontSize: 8),
                    ),
                    pw.Text(
                      plan.verificationDate?.isNotEmpty == true
                          ? 'วันที่: ${plan.verificationDate}'
                          : 'วันที่: ....../....../......',
                      style: pw.TextStyle(font: regularFont, fontSize: 8),
                    ),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('ผู้อนุมัติปิดแผนงาน (Approved By)', style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
                    pw.SizedBox(height: 30),
                    pw.Text('(................................................)', style: pw.TextStyle(font: regularFont, fontSize: 8)),
                    pw.Text('วันที่: ....../....../......', style: pw.TextStyle(font: regularFont, fontSize: 8)),
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

  static pw.TableRow _buildWhyPdfRow(
    String label,
    String content,
    pw.Font regularFont,
    pw.Font boldFont,
    PdfColor bg,
  ) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: bg),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
          child: pw.Text(label, style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
          child: pw.Text(content, style: pw.TextStyle(font: regularFont, fontSize: 8.5)),
        ),
      ],
    );
  }

  static pw.TableRow _build4mPdfRow(
    String label,
    String content,
    pw.Font regularFont,
    pw.Font boldFont,
  ) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
          child: pw.Text(label, style: pw.TextStyle(font: boldFont, fontSize: 8.5)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
          child: pw.Text(content, style: pw.TextStyle(font: regularFont, fontSize: 8.5)),
        ),
      ],
    );
  }
}
