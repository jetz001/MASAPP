import 'dart:convert';
import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../machine_models.dart';
import '../../../core/database/db_helper.dart';

class MachineFormUtils {
  /// Generate a manual checklist PDF for the machine
  static Future<void> generateManualChecklist(MachineModel machine) async {
    // Load Thai font (Sarabun) variants to resolve tofu and unicode issues
    final fontRegular = await PdfGoogleFonts.sarabunRegular();
    final fontBold = await PdfGoogleFonts.sarabunBold();
    final fontItalic = await PdfGoogleFonts.sarabunItalic();
    final fontBoldItalic = await PdfGoogleFonts.sarabunBoldItalic();

    // Fetch Settings
    final rows = await DbHelper.query('SELECT setting_key, setting_value FROM app_settings');
    final settings = {for (var r in rows) r['setting_key'].toString(): r['setting_value'].toString()};
    
    final orgName = settings['org_name'] ?? 'MASAPP Digital Handover';
    final docRef = settings['doc_intake_ref'] ?? 'FM-MA-001';
    final logoBase64 = settings['org_logo'];
    pw.MemoryImage? logoImage;
    if (logoBase64 != null && logoBase64.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(base64Decode(logoBase64));
      } catch (_) {}
    }

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        italic: fontItalic,
        boldItalic: fontBoldItalic,
      ),
    );

    final headerStyle = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
    final sectionStyle = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900);
    final labelStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    final valueStyle = pw.TextStyle(fontSize: 8);
    final tableHeaderStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10 * PdfPageFormat.mm, vertical: 10 * PdfPageFormat.mm),
        footer: (pw.Context context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.end,
          children: [
            pw.Text(docRef, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
          ],
        ),
        build: (pw.Context context) {
          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.start,
              children: [
                if (logoImage != null)
                  pw.Container(
                    width: 60, height: 60,
                    margin: const pw.EdgeInsets.only(right: 15),
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  )
                else
                  pw.Container(
                    width: 50, height: 50, color: PdfColors.blue900,
                    margin: const pw.EdgeInsets.only(right: 15),
                    child: pw.Center(child: pw.Text('MAS', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 14))),
                  ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('$orgName - MACHINE INTAKE FORM', style: pw.TextStyle(fontSize: 7, color: PdfColors.blue800, fontWeight: pw.FontWeight.bold)),
                    pw.Text('แบบฟอร์มตรวจรับเครื่องจักร', style: headerStyle),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 8),

            // Section: Machine Information
            pw.Text('1. ข้อมูลทั่วไป', style: sectionStyle),
            pw.SizedBox(height: 5),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _infoRow('หมายเลขเครื่อง:', machine.machineNo, labelStyle, valueStyle),
                      _infoRow('ชื่อเครื่องจักร:', machine.machineName ?? '', labelStyle, valueStyle),
                      _infoRow('รหัสทรัพย์สิน:', machine.assetNo ?? '', labelStyle, valueStyle),
                      _infoRow('ยี่ห้อ / รุ่น:', '${machine.brand ?? ""} / ${machine.model ?? ""}', labelStyle, valueStyle),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      _infoRow('สถานที่ติดตั้ง:', machine.location ?? '', labelStyle, valueStyle),
                      _infoRow('แผนก:', machine.deptId ?? '', labelStyle, valueStyle),
                      _infoRow('วันที่ติดตั้ง:', machine.installationDate?.toString().split(' ').first ?? '', labelStyle, valueStyle),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),

            // Section: Technical Specs
            pw.Text('2. ข้อมูลทางเทคนิค', style: sectionStyle),
            pw.SizedBox(height: 5),
            pw.Row(
              children: [
                pw.Expanded(child: _infoRow('กำลังไฟฟ้า:', '${machine.specs?.powerKw ?? ""} kW', labelStyle, valueStyle)),
                pw.Expanded(child: _infoRow('แรงดันไฟฟ้า:', '${machine.specs?.voltageV ?? ""} V', labelStyle, valueStyle)),
                pw.Expanded(child: _infoRow('ความสามารถ:', '${machine.specs?.capacity ?? ""} ${machine.specs?.capacityUnit ?? ""}', labelStyle, valueStyle)),
                pw.Expanded(child: _infoRow('ความเร็วรอบ:', '${machine.specs?.rpm ?? ""}', labelStyle, valueStyle)),
              ],
            ),
            pw.SizedBox(height: 10),

            // Section: Checklists
            pw.Text('3. รายการตรวจรับทางเทคนิค', style: sectionStyle),
            pw.SizedBox(height: 5),

            _buildChecklistTable('ระยะที่ 1: การติดตั้งและเตรียมเครื่อง', [
              ('การวางเครื่องจักร', 'ตรวจสอบตำแหน่งตามแผนผังโรงงาน'),
              ('การติดตั้งลม/ไฟฟ้า', 'ตรวจสอบความเรียบร้อยของสายและท่อ'),
              ('ความปลอดภัย', 'ตรวจสอบเซนเซอร์และฝาครอบป้องกัน'),
            ], tableHeaderStyle, valueStyle),

            pw.SizedBox(height: 10),

            _buildChecklistTable('ระยะที่ 2: การทดสอบเดินเครื่อง', [
              ('ระบบไฟฟ้า', 'ตรวจสอบแรงดันและกระแสไฟฟ้าขณะเดินเครื่อง'),
              ('ระบบลม', 'ตรวจสอบการรั่วซึมของลม'),
              ('ความเร็วในการทำงาน', 'ทดสอบการทำงานที่ความเร็วสูงสุด'),
            ], tableHeaderStyle, valueStyle),

            pw.SizedBox(height: 10),

            _buildChecklistTable('ระยะที่ 3: การตรวจรับขั้นตอนสุดท้าย', [
              ('คุณภาพชิ้นงาน', 'ตรวจสอบชิ้นงานที่ผลิตได้ตามตัวอย่าง'),
              ('ความสะอาดและความเรียบร้อย', 'ทำความสะอาดเครื่องจักรและบริเวณโดยรอบ'),
              ('การส่งมอบเอกสาร', 'ส่งมอบคู่มือและใบรับรองให้ฝ่ายผลิต'),
            ], tableHeaderStyle, valueStyle),

            pw.SizedBox(height: 10),

            // Section: Notes & Signatures
            pw.Text('4. หมายเหตุและการยอมรับ', style: sectionStyle),
            pw.SizedBox(height: 5),
            pw.Container(
              height: 35,
              width: double.infinity,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey),
              ),
              padding: const pw.EdgeInsets.all(3),
              child: pw.Text('บันทึกเพิ่มเติม:', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
            ),
            pw.SizedBox(height: 30),

            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _signatureBox('ผู้ตรวจรับ'),
                _signatureBox('ผู้อนุมัติ'),
              ],
            ),

            pw.SizedBox(height: 10),
          ];
        },
      ),
    );

    // Get temp directory and save file
    final tempDir = await getTemporaryDirectory();
    final fileName = 'ManualChecklist_${machine.machineNo.replaceAll("/", "_")}.pdf';
    final file = File('${tempDir.path}/$fileName');
    
    await file.writeAsBytes(await pdf.save());

    // Open file with system default viewer (browser or pdf app)
    await OpenFilex.open(file.path);
  }

  static Future<void> generateIntakeReport(MachineModel machine) async {
    // Load all Thai font (Sarabun) variants to fully support Unicode and styles
    final fontRegular = await PdfGoogleFonts.sarabunRegular();
    final fontBold = await PdfGoogleFonts.sarabunBold();
    final fontItalic = await PdfGoogleFonts.sarabunItalic();
    final fontBoldItalic = await PdfGoogleFonts.sarabunBoldItalic();
    final signatureFont = await PdfGoogleFonts.charmonmanBold();

    // Fetch Settings
    final rows = await DbHelper.query('SELECT setting_key, setting_value FROM app_settings');
    final settings = {for (var r in rows) r['setting_key'].toString(): r['setting_value'].toString()};
    
    final orgName = settings['org_name'] ?? 'MASAPP Digital Handover';
    final docRef = settings['doc_intake_ref'] ?? 'FM-MA-001';
    final logoBase64 = settings['org_logo'];
    pw.MemoryImage? logoImage;
    if (logoBase64 != null && logoBase64.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(base64Decode(logoBase64));
      } catch (_) {}
    }

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
        italic: fontItalic,
        boldItalic: fontBoldItalic,
      ),
    );

    final headerStyle = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
    final sectionStyle = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900);
    final labelStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
    final valueStyle = pw.TextStyle(fontSize: 8);
    final tableHeaderStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10 * PdfPageFormat.mm, vertical: 10 * PdfPageFormat.mm),
        footer: (pw.Context context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('หน้า ${context.pageNumber} / ${context.pagesCount}', style: pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
            pw.Text(docRef, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.grey800)),
          ],
        ),
        build: (pw.Context context) {
          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.start,
              children: [
                if (logoImage != null)
                  pw.Container(
                    width: 60, height: 60,
                    margin: const pw.EdgeInsets.only(right: 15),
                    child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                  )
                else
                  pw.Container(
                    width: 50, height: 50, color: PdfColors.blue900,
                    margin: const pw.EdgeInsets.only(right: 15),
                    child: pw.Center(child: pw.Text('MAS', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 14))),
                  ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('$orgName - MACHINE INTAKE REPORT', style: pw.TextStyle(fontSize: 7, color: PdfColors.blue800, fontWeight: pw.FontWeight.bold)),
                    pw.Text('รายงานการตรวจรับเครื่องจักรเสร็จสมบูรณ์', style: headerStyle),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 0.5),
            pw.SizedBox(height: 8),

            // Info Section
            pw.Text('1. ข้อมูลพื้นฐานและสเปกเครื่องจักร', style: sectionStyle),
            pw.SizedBox(height: 4),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      _infoRow('รหัสเครื่องจักร:', machine.machineNo, labelStyle, valueStyle),
                      _infoRow('ชื่อเครื่องจักร:', machine.machineName ?? '-', labelStyle, valueStyle),
                      _infoRow('ยี่ห้อ / รุ่น:', '${machine.brand ?? "-"} / ${machine.model ?? "-"}', labelStyle, valueStyle),
                      _infoRow('เลขซีเรียล:', machine.serialNo ?? '-', labelStyle, valueStyle),
                    ],
                  ),
                ),
                pw.Expanded(
                  child: pw.Column(
                    children: [
                      _infoRow('รหัสทรัพย์สิน:', machine.assetNo ?? '-', labelStyle, valueStyle),
                      _infoRow('สถานที่ติดตั้ง:', machine.location ?? '-', labelStyle, valueStyle),
                      _infoRow('วันที่ติดตั้ง:', machine.installationDate?.toString().split(' ').first ?? '-', labelStyle, valueStyle),
                      _infoRow('กำลังไฟฟ้า:', '${machine.specs?.powerKw ?? "-"} kW / ${machine.specs?.voltageV ?? "-"} V', labelStyle, valueStyle),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 12),

            // Checklists
            pw.Text('2. รายละเอียดการตรวจสอบ (Handover Checklists)', style: sectionStyle),
            pw.SizedBox(height: 6),

            if (machine.stage1 != null) ...[
              _buildResultTable('ระยะที่ 1: การติดตั้งและเตรียมเครื่อง (Preparation)', machine.stage1!, tableHeaderStyle, valueStyle),
              pw.SizedBox(height: 10),
            ],

            if (machine.stage2 != null) ...[
              _buildResultTable('ระยะที่ 2: การทดสอบเดินเครื่อง (Operation Test)', machine.stage2!, tableHeaderStyle, valueStyle),
              pw.SizedBox(height: 10),
            ],

            if (machine.stage3 != null) ...[
              _buildResultTable('ระยะที่ 3: ตรวจรับขั้นตอนสุดท้าย (Final Acceptance)', machine.stage3!, tableHeaderStyle, valueStyle),
              pw.SizedBox(height: 10),
            ],

            pw.SizedBox(height: 10),

            // Summary notes
            pw.Text('3. ข้อสรุปและหมายเหตุเพิ่มเติม', style: sectionStyle),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Text('ผลสรุปการตรวจรับ: ', style: labelStyle),
                if (machine.handoverConclusion == 'pass')
                  pw.Text('ผ่านรับเข้า (Accepted)', style: valueStyle.copyWith(color: PdfColors.green900, fontWeight: pw.FontWeight.bold))
                else if (machine.handoverConclusion == 'fail')
                  pw.Text('ไม่รับ (Rejected)', style: valueStyle.copyWith(color: PdfColors.red900, fontWeight: pw.FontWeight.bold))
                else
                  pw.Text('ยังไม่มีข้อสรุป', style: valueStyle.copyWith(color: PdfColors.grey600)),
              ],
            ),
            pw.SizedBox(height: 6),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('หมายเหตุ:', style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    (machine.stage3?.notes?.isNotEmpty == true) ? machine.stage3!.notes! : (machine.notes ?? 'ไม่มีบันทึกเพิ่มเติม'),
                    style: valueStyle,
                  ),
                ],
              ),
            ),

            pw.SizedBox(height: 12),

            // Attachments List
            if (machine.attachments.isNotEmpty) ...[
              pw.Text('4. รายการเอกสารแนบ (Attachments)', style: sectionStyle),
              pw.SizedBox(height: 4),
              ...machine.attachments.asMap().entries.map((entry) {
                final i = entry.key;
                final file = entry.value;
                final sizeMB = ((file['file_size'] as int? ?? 0) / 1024 / 1024).toStringAsFixed(2);
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 2, left: 10),
                  child: pw.Text('${i + 1}. ${file['file_name']} ($sizeMB MB)', style: valueStyle),
                );
              }),
              pw.SizedBox(height: 12),
            ],

            pw.SizedBox(height: 20),

            // Signatures
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _signatureBoxWithData(
                  'ผู้ตรวจรับ / Receiver', 
                  // prioritize stage 3 performer (Receiver), then stage 1
                  (machine.stage3?.performerName ?? machine.stage1?.performerName), 
                  (machine.stage3?.performedAt ?? machine.stage1?.performedAt),
                  signatureFont,
                ),
                _signatureBoxWithData(
                  'ผู้อนุมัติ / Approver', 
                  (machine.stage3?.status == HandoverStatus.approved) 
                      ? machine.stage3?.approverName : null, 
                  machine.stage3?.approvedAt,
                  signatureFont,
                ),
              ],
            ),

            pw.SizedBox(height: 20),
            pw.Center(
              child: pw.Text('เอกสารนี้จัดทำโดยระบบ MASAPP Digital Handover ณ วันที่ ${DateTime.now().toString().split('.')[0]}', 
                style: pw.TextStyle(fontSize: 6, color: PdfColors.grey600, fontStyle: pw.FontStyle.italic)),
            ),
          ];
        },
      ),
    );

    final tempDir = await getTemporaryDirectory();
    final fileName = 'IntakeReport_${machine.machineNo.replaceAll("/", "_")}.pdf';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(file.path);
  }

  static pw.Widget _infoRow(String label, String value, pw.TextStyle labelStyle, pw.TextStyle valueStyle) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.SizedBox(width: 80, child: pw.Text(label, style: labelStyle)),
          pw.Expanded(child: pw.Text(value, style: valueStyle)),
        ],
      ),
    );
  }

  static pw.Widget _buildChecklistTable(String title, List<(String, String)> items, pw.TextStyle headerStyle, pw.TextStyle cellStyle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(4),
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          width: double.infinity,
          child: pw.Text(title, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: {
            0: const pw.FixedColumnWidth(25), // No.
            1: const pw.FlexColumnWidth(3),   // Item
            2: const pw.FixedColumnWidth(40), // Pass
            3: const pw.FixedColumnWidth(40), // Fail
            4: const pw.FixedColumnWidth(40), // N/A
            5: const pw.FlexColumnWidth(2),   // Comments
          },
          children: [
            // Header Row
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              children: [
                _tableH('No.', headerStyle),
                _tableH('รายการตรวจสอบ', headerStyle),
                _tableH('ผ่าน', headerStyle),
                _tableH('ไม่ผ่าน', headerStyle),
                _tableH('N/A', headerStyle),
                _tableH('ความคิดเห็น', headerStyle),
              ],
            ),
            // Data Rows
            ...List.generate(items.length, (i) {
              return pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Center(child: pw.Text('${i + 1}', style: cellStyle))),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), 
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(items[i].$1, style: cellStyle.copyWith(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                        pw.Text(items[i].$2, style: cellStyle.copyWith(fontSize: 6, color: PdfColors.grey700)),
                      ],
                    )),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('')),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('')),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('')),
                  pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Text('')),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  static pw.Widget _tableH(String label, pw.TextStyle style) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Center(child: pw.Text(label, style: style)),
    );
  }

  static pw.Widget _signatureBox(String label) {
    return _signatureBoxWithData(label, null, null, null);
  }

  static pw.Widget _signatureBoxWithData(
    String label, 
    String? name, 
    DateTime? date,
    pw.Font? scriptFont,
  ) {
    return pw.Column(
      children: [
        if (name != null)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Text(
              name, 
              style: pw.TextStyle(
                fontSize: 18, 
                fontWeight: pw.FontWeight.normal, 
                font: scriptFont,
                color: PdfColors.blue900,
              ),
            ),
          ),
        pw.Container(
          width: 150,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5)),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text('( ${name ?? "________________________"} )', style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 2),
        pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('วันที่: ${date != null ? date.toString().split(' ')[0] : "________ / ________ / ________"}', style: const pw.TextStyle(fontSize: 7)),
      ],
    );
  }

  static List<(String, String)> _getDefaultItems(HandoverStage stage) {
    switch (stage) {
      case HandoverStage.stage1:
        return [
          ('การวางเครื่องจักร', 'ตรวจสอบตำแหน่งตามแผนผังโรงงาน'),
          ('การติดตั้งลม/ไฟฟ้า', 'ตรวจสอบความเรียบร้อยของสายและท่อ'),
          ('ความปลอดภัย', 'ตรวจสอบเซนเซอร์และฝาครอบป้องกัน'),
        ];
      case HandoverStage.stage2:
        return [
          ('ระบบไฟฟ้า', 'ตรวจสอบแรงดันและกระแสไฟฟ้าขณะเดินเครื่อง'),
          ('ระบบลม', 'ตรวจสอบการรั่วซึมของลม'),
          ('ความเร็วในการทำงาน', 'ทดสอบการทำงานที่ความเร็วสูงสุด'),
        ];
      case HandoverStage.stage3:
        return [
          ('คุณภาพชิ้นงาน', 'ตรวจสอบชิ้นงานที่ผลิตได้ตามตัวอย่าง'),
          ('ความสะอาดและความเรียบร้อย', 'ทำความสะอาดเครื่องจักรและบริเวณโดยรอบ'),
          ('การส่งมอบเอกสาร', 'ส่งมอบคู่มือและใบรับรองให้ฝ่ายผลิต'),
        ];
    }
  }

  static pw.Widget _buildResultTable(String title, HandoverInfo stage, pw.TextStyle headerStyle, pw.TextStyle cellStyle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(4),
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          width: double.infinity,
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(title, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('สถานะ: ${stage.statusLabel}', style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey800)),
            ],
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300),
          columnWidths: {
            0: const pw.FixedColumnWidth(20), // No.
            1: const pw.FlexColumnWidth(3),   // Item
            2: const pw.FixedColumnWidth(25), // P
            3: const pw.FixedColumnWidth(25), // F
            4: const pw.FixedColumnWidth(25), // N
            5: const pw.FlexColumnWidth(2),   // Remarks
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
              children: [
                _tableH('No.', headerStyle),
                _tableH('รายการตรวจสอบ', headerStyle),
                _tableH('P', headerStyle),
                _tableH('F', headerStyle),
                _tableH('N/A', headerStyle),
                _tableH('หมายเหตุ', headerStyle),
              ],
            ),
            ...List.generate(stage.results.isNotEmpty ? stage.results.length : _getDefaultItems(stage.stage).length, (i) {
              final itemName = stage.results.isNotEmpty ? stage.results[i].itemName : _getDefaultItems(stage.stage)[i].$1;
              final result = stage.results.isNotEmpty ? stage.results[i].result : 'none';
              final remarks = stage.results.isNotEmpty ? (stage.results[i].remarks ?? '') : '';
              
              return pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Center(child: pw.Text('${i + 1}', style: cellStyle))),
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(itemName, style: cellStyle)),
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Center(child: pw.Text(result == 'pass' ? '/' : '', style: cellStyle.copyWith(fontWeight: pw.FontWeight.bold, color: PdfColors.green700)))),
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Center(child: pw.Text(result == 'fail' ? 'X' : '', style: cellStyle.copyWith(fontWeight: pw.FontWeight.bold, color: PdfColors.red700)))),
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Center(child: pw.Text(result == 'na' ? '-' : '', style: cellStyle))),
                  pw.Padding(padding: const pw.EdgeInsets.all(3), child: pw.Text(remarks, style: cellStyle.copyWith(fontSize: 6))),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }
}
