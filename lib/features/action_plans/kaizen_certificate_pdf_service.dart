import 'dart:io';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'models/action_plan_model.dart';

class KaizenCertificatePdfService {
  /// Generates an Executive Landscape Certificate PDF and opens it
  static Future<void> generateAndOpen({
    required ActionPlanRecord plan,
    String? recipientName,
    String? recipientRole,
    String? recipientEmpNo,
  }) async {
    final pdf = pw.Document();

    // 1. Load Thai Fonts (Prompt)
    final regularFontData = await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf');
    final boldFontData = await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf');
    final regularFont = pw.Font.ttf(regularFontData);
    final boldFont = pw.Font.ttf(boldFontData);

    // Resolve Recipient Info
    final name = recipientName?.isNotEmpty == true
        ? recipientName!
        : (plan.actionSteps.isNotEmpty && plan.actionSteps.first.assignee.isNotEmpty
            ? plan.actionSteps.first.assignee
            : (plan.verifiedBy?.isNotEmpty == true ? plan.verifiedBy! : 'ทีมงานปรับปรุง Kaizen'));

    final reductionText = plan.reductionPercentage != null
        ? '${plan.reductionPercentage!.toStringAsFixed(1)}%'
        : null;

    final beforeValStr = plan.beforeValue != null
        ? '${plan.beforeValue!.toStringAsFixed(1)} ${plan.metricUnit ?? ""}'
        : null;
    final actualValStr = plan.actualValue != null
        ? '${plan.actualValue!.toStringAsFixed(1)} ${plan.metricUnit ?? ""}'
        : null;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) {
          return pw.Container(
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColor.fromHex('#1E3A8A'), width: 4), // Navy
            ),
            padding: const pw.EdgeInsets.all(12),
            child: pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromHex('#D97706'), width: 1.5), // Gold inner border
              ),
              padding: const pw.EdgeInsets.symmetric(horizontal: 40, vertical: 24),
              child: pw.Column(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // 1. Top Header Banner
                  pw.Column(
                    children: [
                      pw.Text(
                        'MASAPP SMART FACTORY & MAINTENANCE MANAGEMENT',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 10,
                          color: PdfColor.fromHex('#64748B'),
                          letterSpacing: 2,
                        ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'CERTIFICATE OF ACHIEVEMENT',
                        style: pw.TextStyle(
                          font: boldFont,
                          fontSize: 22,
                          color: PdfColor.fromHex('#1E3A8A'),
                          letterSpacing: 3,
                        ),
                      ),
                      pw.Text(
                        'ใบประกาศนียบัตรเชิดชูเกียรติผลงานนวัตกรรมและการแก้ปัญหา (Kaizen Award)',
                        style: pw.TextStyle(
                          font: regularFont,
                          fontSize: 11,
                          color: PdfColor.fromHex('#D97706'),
                        ),
                      ),
                    ],
                  ),

                  // 2. Recipient Section
                  pw.Column(
                    children: [
                      pw.Text(
                        'ขอมอบใบประกาศเกียรติคุณฉบับนี้ให้ไว้เพื่อแสดงว่า',
                        style: pw.TextStyle(font: regularFont, fontSize: 11, color: PdfColors.grey700),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                        decoration: const pw.BoxDecoration(
                          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.blueGrey800, width: 1.5)),
                        ),
                        child: pw.Text(
                          name,
                          style: pw.TextStyle(font: boldFont, fontSize: 20, color: PdfColor.fromHex('#0F172A')),
                        ),
                      ),
                      if (recipientRole != null || recipientEmpNo != null) ...[
                        pw.SizedBox(height: 4),
                        pw.Text(
                          '${recipientRole ?? ""} ${recipientEmpNo != null ? "รหัส: $recipientEmpNo" : ""}'.trim(),
                          style: pw.TextStyle(font: regularFont, fontSize: 10, color: PdfColors.grey600),
                        ),
                      ],
                    ],
                  ),

                  // 3. Project & Achievement Statement
                  pw.Column(
                    children: [
                      pw.Text(
                        'ได้ปฏิบัติงานและดำเนินโครงการปรับปรุงอย่างยอดเยี่ยม จนบรรลุผลสำเร็จตามเป้าหมาย ในหัวข้อ:',
                        style: pw.TextStyle(font: regularFont, fontSize: 10.5, color: PdfColors.grey800),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: pw.BoxDecoration(
                          color: PdfColor.fromHex('#F8FAFC'),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                          border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                        ),
                        child: pw.Column(
                          children: [
                            pw.Text(
                              plan.problemTitle,
                              style: pw.TextStyle(font: boldFont, fontSize: 13, color: PdfColor.fromHex('#1E293B')),
                              textAlign: pw.TextAlign.center,
                            ),
                            if (plan.rootCause != null && plan.rootCause!.isNotEmpty) ...[
                              pw.SizedBox(height: 4),
                              pw.Text(
                                'สาเหตุรากเหง้าที่แก้ไขได้: ${plan.rootCause}',
                                style: pw.TextStyle(font: regularFont, fontSize: 9.5, color: PdfColors.grey700),
                                textAlign: pw.TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),

                  // 4. Quantified Results Box
                  if (reductionText != null || beforeValStr != null) ...[
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#ECFDF5'),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                        border: pw.Border.all(color: PdfColor.fromHex('#10B981'), width: 1),
                      ),
                      child: pw.Row(
                        mainAxisSize: pw.MainAxisSize.min,
                        children: [
                          pw.Text(
                            'ผลลัพธ์ที่ทำได้จริง: ',
                            style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColor.fromHex('#065F46')),
                          ),
                          if (beforeValStr != null && actualValStr != null) ...[
                            pw.Text(
                              'ก่อนปรับปรุง $beforeValStr -> หลังปรับปรุง $actualValStr ',
                              style: pw.TextStyle(font: regularFont, fontSize: 10.5, color: PdfColor.fromHex('#047857')),
                            ),
                          ],
                          if (reductionText != null) ...[
                            pw.Text(
                              '(ลดความสูญเปล่าได้ $reductionText)',
                              style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColor.fromHex('#047857')),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

                  // 5. Footer Signatures & Date
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      // Left: Date & Doc ID
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text(
                            'วันที่รับรองผล: ${plan.verificationDate ?? DateTime.now().toString().substring(0, 10)}',
                            style: pw.TextStyle(font: regularFont, fontSize: 9.5, color: PdfColors.grey700),
                          ),
                          pw.Text(
                            'รหัสเอกสารอ้างอิง: ${plan.rcaId}',
                            style: pw.TextStyle(font: regularFont, fontSize: 8.5, color: PdfColors.grey500),
                          ),
                        ],
                      ),

                      // Center: Gold Seal Emblem
                      pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(
                          shape: pw.BoxShape.circle,
                          border: pw.Border.all(color: PdfColor.fromHex('#D97706'), width: 2),
                        ),
                        child: pw.Text(
                          'KAIZEN\nVERIFIED',
                          textAlign: pw.TextAlign.center,
                          style: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColor.fromHex('#D97706')),
                        ),
                      ),

                      // Right: Signature line
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Container(
                            width: 140,
                            decoration: const pw.BoxDecoration(
                              border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey500, width: 1)),
                            ),
                            child: pw.Padding(
                              padding: const pw.EdgeInsets.only(bottom: 2),
                              child: pw.Text(
                                plan.verifiedBy?.isNotEmpty == true ? plan.verifiedBy! : 'ผู้จัดการโรงงาน / หัวหน้าฝ่าย',
                                textAlign: pw.TextAlign.center,
                                style: pw.TextStyle(font: boldFont, fontSize: 10, color: PdfColors.grey900),
                              ),
                            ),
                          ),
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'ผู้รับรองและอนุมัติปิดแผนงาน',
                            style: pw.TextStyle(font: regularFont, fontSize: 8.5, color: PdfColors.grey600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    // Save and open
    final outputDir = await getApplicationDocumentsDirectory();
    final file = File('${outputDir.path}/Kaizen_Certificate_${plan.rcaId}.pdf');
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(file.path);
  }
}