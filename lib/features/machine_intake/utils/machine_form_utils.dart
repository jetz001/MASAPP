import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../machine_models.dart';

class MachineFormUtils {
  /// Generate a manual checklist PDF for the machine
  static Future<void> generateManualChecklist(MachineModel machine) async {
    // Load Thai font (Sarabun) to resolve tofu issues
    final fontRegular = await PdfGoogleFonts.sarabunRegular();
    final fontBold = await PdfGoogleFonts.sarabunBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
      ),
    );

    final headerStyle = pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold);
    final sectionStyle = pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue900);
    final labelStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final valueStyle = pw.TextStyle(fontSize: 9);
    final tableHeaderStyle = pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white);

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(
          horizontal: 12 * PdfPageFormat.mm,
          vertical: 10 * PdfPageFormat.mm,
        ),
        build: (pw.Context context) {
          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('MASAPP - ระบบบริหารจัดการงานซ่อมบำรุง', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.Text('แบบฟอร์มตรวจรับเครื่องจักร', style: headerStyle),
                    pw.Text('ชื่อเครื่อง: ${machine.machineName ?? ""}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                    pw.Text('(บันทึกการตรวจเช็คหน้างาน)', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
                  ],
                ),
                pw.Container(
                  width: 40,
                  height: 40,
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.blue900,
                  ),
                  child: pw.Center(
                    child: pw.Text('MAS', style: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(),
            pw.SizedBox(height: 10),

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
            pw.Center(
              child: pw.Text('วันที่ออกรายงาน: ${DateTime.now().toString().split('.')[0]}', 
                style: pw.TextStyle(fontSize: 7, color: PdfColors.grey)),
            ),
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
    return pw.Column(
      children: [
        pw.Container(
          width: 150,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: PdfColors.black, width: 0.5)),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Text('( ________________________ )', style: const pw.TextStyle(fontSize: 8)),
        pw.SizedBox(height: 2),
        pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Text('วันที่เซ็น: ________ / ________ / ________', style: const pw.TextStyle(fontSize: 7)),
      ],
    );
  }
}
