import 'dart:io';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../action_plans/models/action_plan_model.dart';
import 'technician_profile_provider.dart';
import 'workforce_screen.dart';

class TechnicianPortfolioPdfService {
  /// Generates a Comprehensive Kaizen Portfolio PDF for a Technician
  static Future<void> generateAndOpen({
    required TechnicianProfile profile,
    required List<ActionPlanRecord> plans,
    required int kaizenPoints,
    required List<String> badges,
    List<TechnicianAttachment> certificates = const [],
  }) async {
    final pdf = pw.Document();

    // Load Thai Fonts
    final regularFontData = await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf');
    final boldFontData = await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf');
    final regularFont = pw.Font.ttf(regularFontData);
    final boldFont = pw.Font.ttf(boldFontData);

    // Pre-load certificate images if available
    final certImages = <String, pw.MemoryImage>{};
    for (final cert in certificates) {
      final ext = cert.filePath.toLowerCase();
      if (ext.endsWith('.png') || ext.endsWith('.jpg') || ext.endsWith('.jpeg') || ext.endsWith('.webp')) {
        final f = File(cert.filePath);
        if (await f.exists()) {
          try {
            final bytes = await f.readAsBytes();
            certImages[cert.attachmentId] = pw.MemoryImage(bytes);
          } catch (_) {}
        }
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // 1. Header Banner
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'MASAPP SMART WORKFORCE STUDIO',
                      style: pw.TextStyle(font: boldFont, fontSize: 9, color: PdfColors.blue900, letterSpacing: 1.5),
                    ),
                    pw.Text(
                      'แฟ้มสะสมผลงาน Kaizen & ทักษะบุคลากร',
                      style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.blueGrey900),
                    ),
                    pw.Text(
                      'Technician Kaizen Portfolio & Continuous Improvement Resume',
                      style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey600),
                    ),
                  ],
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#FEF3C7'),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: PdfColor.fromHex('#F59E0B')),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text('คะแนน Kaizen สะสม', style: pw.TextStyle(font: regularFont, fontSize: 8, color: PdfColor.fromHex('#92400E'))),
                      pw.Text('$kaizenPoints แต้ม', style: pw.TextStyle(font: boldFont, fontSize: 13, color: PdfColor.fromHex('#B45309'))),
                    ],
                  ),
                ),
              ],
            ),
            pw.Divider(thickness: 1, color: PdfColors.grey300),
            pw.SizedBox(height: 8),

            // 2. Personal Info & Badges Card
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                border: pw.Border.all(color: PdfColors.grey300),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    flex: 3,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          profile.fullName,
                          style: pw.TextStyle(font: boldFont, fontSize: 15, color: PdfColors.blueGrey900),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'ตำแหน่ง: ${profile.role} | แผนก: ${profile.deptName ?? "ฝ่ายซ่อมบำรุง"}',
                          style: pw.TextStyle(font: regularFont, fontSize: 9.5, color: PdfColors.grey700),
                        ),
                        pw.Text(
                          'รหัสพนักงาน: ${profile.employeeNo} | อีเมล: ${profile.email ?? "-"} | โทร: ${profile.phone ?? "-"}',
                          style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey600),
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 12),
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('เหรียญเกียรติยศ (Badges):', style: pw.TextStyle(font: boldFont, fontSize: 9.5, color: PdfColors.blueGrey800)),
                        pw.SizedBox(height: 4),
                        if (badges.isEmpty)
                          pw.Text('- กำลังสะสมผลงาน -', style: pw.TextStyle(font: regularFont, fontSize: 8.5, color: PdfColors.grey500))
                        else
                          pw.Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: badges.map((b) => pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: pw.BoxDecoration(
                                color: PdfColor.fromHex('#EFF6FF'),
                                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                                border: pw.Border.all(color: PdfColor.fromHex('#3B82F6'), width: 0.5),
                              ),
                              child: pw.Text(b, style: pw.TextStyle(font: regularFont, fontSize: 8, color: PdfColor.fromHex('#1E40AF'))),
                            )).toList(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 14),

            // 3. Skill Matrix & Competencies
            pw.Text(
              '1. ทักษะความชำนาญที่ได้รับการรับรอง (Skill Matrix)',
              style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.blueGrey900),
            ),
            pw.SizedBox(height: 4),
            if (profile.skills.isEmpty)
              pw.Text('ยังไม่มีการบันทึกทักษะในระบบ', style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey500))
            else
              pw.Wrap(
                spacing: 6,
                runSpacing: 6,
                children: profile.skills.map((s) => pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#ECFDF5'),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    border: pw.Border.all(color: PdfColor.fromHex('#10B981'), width: 0.8),
                  ),
                  child: pw.Text(s, style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColor.fromHex('#065F46'))),
                )).toList(),
              ),
            pw.SizedBox(height: 14),

            // 4. Action Plans & Kaizen Projects Done
            pw.Text(
              '2. ผลงานโครงการปรับปรุงและการแก้ปัญหา (Action Plans & Kaizen Record)',
              style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.blueGrey900),
            ),
            pw.SizedBox(height: 4),
            if (plans.isEmpty)
              pw.Text('ยังไม่มีประวัติการปิด Action Plan ในระบบ', style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey500))
            else
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: const {
                  0: pw.FixedColumnWidth(28),
                  1: pw.FlexColumnWidth(3),
                  2: pw.FlexColumnWidth(2),
                  3: pw.FixedColumnWidth(65),
                  4: pw.FixedColumnWidth(65),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _buildHeaderCell('#', boldFont),
                      _buildHeaderCell('หัวข้อปัญหา / โครงการ', boldFont),
                      _buildHeaderCell('สาเหตุรากเหง้า (RCA)', boldFont),
                      _buildHeaderCell('ผลลัพธ์ลดได้', boldFont),
                      _buildHeaderCell('สถานะ', boldFont),
                    ],
                  ),
                  ...plans.asMap().entries.map((entry) {
                    final idx = entry.key + 1;
                    final p = entry.value;
                    final red = p.reductionPercentage != null ? '${p.reductionPercentage!.toStringAsFixed(1)}%' : '-';
                    final isDone = p.status == 'completed' || p.status == 'closed';
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: idx % 2 == 0 ? PdfColor.fromHex('#F8FAFC') : PdfColors.white),
                      children: [
                        _buildDataCell('$idx', regularFont, align: pw.TextAlign.center),
                        _buildDataCell(p.problemTitle, regularFont),
                        _buildDataCell(p.rootCause ?? '-', regularFont),
                        _buildDataCell(red, boldFont, align: pw.TextAlign.center, color: PdfColor.fromHex('#047857')),
                        _buildDataCell(isDone ? 'สำเร็จ' : 'ดำเนินการ', regularFont, align: pw.TextAlign.center),
                      ],
                    );
                  }),
                ],
              ),
            pw.SizedBox(height: 14),

            // 5. Certificates & Training Credentials
            pw.Text(
              '3. ใบรับรองวิชาชีพและการฝึกอบรม (Certificates & Training Credentials)',
              style: pw.TextStyle(font: boldFont, fontSize: 11, color: PdfColors.blueGrey900),
            ),
            pw.SizedBox(height: 4),
            if (certificates.isEmpty)
              pw.Text('ยังไม่มีการแนบใบรับรองหรือประวัติการอบรมในระบบ', style: pw.TextStyle(font: regularFont, fontSize: 9, color: PdfColors.grey500))
            else ...[
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: const {
                  0: pw.FixedColumnWidth(28),
                  1: pw.FlexColumnWidth(4),
                  2: pw.FixedColumnWidth(90),
                  3: pw.FixedColumnWidth(80),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _buildHeaderCell('#', boldFont),
                      _buildHeaderCell('หลักสูตร / ชื่อเอกสารใบรับรอง', boldFont),
                      _buildHeaderCell('วันที่บันทึก', boldFont),
                      _buildHeaderCell('สถานะ', boldFont),
                    ],
                  ),
                  ...certificates.asMap().entries.map((entry) {
                    final idx = entry.key + 1;
                    final c = entry.value;
                    final uploadDate = c.uploadedAt.length >= 10 ? c.uploadedAt.substring(0, 10) : c.uploadedAt;
                    return pw.TableRow(
                      decoration: pw.BoxDecoration(color: idx % 2 == 0 ? PdfColor.fromHex('#F8FAFC') : PdfColors.white),
                      children: [
                        _buildDataCell('$idx', regularFont, align: pw.TextAlign.center),
                        _buildDataCell(c.fileName, regularFont),
                        _buildDataCell(uploadDate, regularFont, align: pw.TextAlign.center),
                        _buildDataCell('ผ่านการรับรอง', boldFont, align: pw.TextAlign.center, color: PdfColor.fromHex('#047857')),
                      ],
                    );
                  }),
                ],
              ),
              if (certImages.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                pw.Text('เอกสารแนบใบรับรอง (Certificate Previews):', style: pw.TextStyle(font: boldFont, fontSize: 9.5, color: PdfColors.blueGrey800)),
                pw.SizedBox(height: 6),
                pw.Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: certificates.where((c) => certImages.containsKey(c.attachmentId)).map((c) {
                    final img = certImages[c.attachmentId]!;
                    return pw.Container(
                      width: 150,
                      padding: const pw.EdgeInsets.all(4),
                      decoration: pw.BoxDecoration(
                        border: pw.Border.all(color: PdfColors.grey400, width: 0.8),
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                        color: PdfColors.white,
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.center,
                        children: [
                          pw.Container(
                            height: 95,
                            width: 142,
                            child: pw.Image(img, fit: pw.BoxFit.contain),
                          ),
                          pw.SizedBox(height: 4),
                          pw.Text(
                            c.fileName,
                            style: pw.TextStyle(font: regularFont, fontSize: 7.5, color: PdfColors.grey800),
                            maxLines: 1,
                            overflow: pw.TextOverflow.clip,
                            textAlign: pw.TextAlign.center,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
            pw.SizedBox(height: 20),

            // 6. Verification & Recommendation Signature Box
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('การรับรองแฟ้มสะสมผลงาน:', style: pw.TextStyle(font: boldFont, fontSize: 9.5, color: PdfColors.grey800)),
                      pw.SizedBox(height: 2),
                      pw.Text('เอกสารนี้ออกโดยระบบ MASAPP เพื่อใช้ประกอบการพิจารณาผลงานและเลื่อนตำแหน่ง', style: pw.TextStyle(font: regularFont, fontSize: 8, color: PdfColors.grey600)),
                      pw.Text('วันที่พิมพ์: ${DateTime.now().toString().substring(0, 16)}', style: pw.TextStyle(font: regularFont, fontSize: 8, color: PdfColors.grey500)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(
                        width: 130,
                        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey500))),
                        child: pw.SizedBox(height: 20),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text('ผู้จัดการฝ่าย / ผู้บังคับบัญชา', style: pw.TextStyle(font: regularFont, fontSize: 8.5, color: PdfColors.grey700)),
                    ],
                  ),
                ],
              ),
            ),
          ];
        },
      ),
    );

    // Save and open
    final outputDir = await getApplicationDocumentsDirectory();
    final file = File('${outputDir.path}/Technician_Kaizen_Portfolio_${profile.userId}.pdf');
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(file.path);
  }

  static pw.Widget _buildHeaderCell(String text, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 8.5, color: PdfColors.black), textAlign: pw.TextAlign.center),
    );
  }

  static pw.Widget _buildDataCell(String text, pw.Font font, {pw.TextAlign align = pw.TextAlign.left, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: pw.Text(text, style: pw.TextStyle(font: font, fontSize: 8.5, color: color ?? PdfColors.grey800), textAlign: align),
    );
  }
}
