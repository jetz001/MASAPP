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
import 'work_permit_screen.dart';
import '../settings/settings_provider.dart';

class WorkPermitPdfService {
  static Future<void> generateAndOpen({
    required WorkPermit permit,
    required AppSettingsState settings,
  }) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf')),
      ),
    );

    final logoBase64 = settings.get(AppSettingKeys.orgLogo);
    final companyName = settings.get(AppSettingKeys.orgName, defaultValue: 'โรงงานของเรา');
    final docRef = 'WP-FORM-001 Rev1';

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
                if (logoImage != null) pw.SizedBox(width: 15),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'ใบอนุญาตทำงาน (Work Permit)',
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(companyName, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                  ],
                ),
                pw.Spacer(),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('เลขที่: ${permit.permitNo}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    pw.Text('ประเภท: ${permit.permitType.label}', style: const pw.TextStyle(fontSize: 12)),
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
          pw.Text('รายละเอียดงาน', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _infoRow('เลขที่เครื่องจักร', permit.machineNo ?? '-'),
                _infoRow('รายละเอียด/ลักษณะงาน', permit.description),
                _infoRow('ผู้ขออนุญาต', permit.requestorName),
                _infoRow('อ้างอิงเอกสาร', permit.woNo != null ? 'ใบแจ้งซ่อม ${permit.woNo}' : (permit.pmAmCode != null ? 'แผน PM/AM ${permit.pmAmCode}' : '-')),
                _infoRow('วันที่สร้างใบอนุญาต', DateFormat('dd/MM/yyyy HH:mm').format(permit.createdAt)),
                _infoRow('ระยะเวลาทำงาน', permit.durationHours != null ? '${permit.durationHours} ชั่วโมง' : '-'),
              ],
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text('อุปกรณ์ความปลอดภัยที่กำหนด', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: permit.requiredEquipments.isEmpty
                  ? [pw.Text('ไม่มีการกำหนดอุปกรณ์พิเศษ', style: const pw.TextStyle(color: PdfColors.grey600))]
                  : permit.requiredEquipments.map((eq) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('• ', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                          pw.Expanded(child: pw.Text(eq)),
                        ],
                      ),
                    )).toList(),
            ),
          ),
          pw.SizedBox(height: 20),
          pw.Text('สถานะการอนุมัติ', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _infoRow('สถานะ', permit.status == 'approved' ? 'อนุมัติแล้ว' : permit.status == 'completed' ? 'เสร็จสิ้น' : 'รอการอนุมัติ / อื่นๆ'),
                _infoRow('ผู้อนุมัติ (จป./วิศวกร)', permit.authorizedBy ?? '-'),
                _infoRow('เวลาที่อนุมัติ', permit.authorizedAt != null ? DateFormat('dd/MM/yyyy HH:mm').format(permit.authorizedAt!) : '-'),
                _infoRow('วันเวลาหมดอายุ', (permit.authorizedAt != null && permit.durationHours != null) 
                    ? DateFormat('dd/MM/yyyy HH:mm').format(permit.authorizedAt!.add(Duration(hours: permit.durationHours!)))
                    : '-'),
              ],
            ),
          ),
          pw.SizedBox(height: 40),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _signatureBlock('ผู้ขออนุญาตทำงาน', permit.requestorName),
              _signatureBlock('ผู้อนุมัติ (จป./วิศวกร)', permit.authorizedBy ?? '....................................'),
            ],
          ),
        ],
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File('${output.path}/WP_${permit.permitNo}.pdf');
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(file.path);
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
          ),
          pw.Text(': '),
          pw.Expanded(
            child: pw.Text(value),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatureBlock(String title, String name) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text('ลงชื่อ.......................................................'),
        pw.SizedBox(height: 8),
        pw.Text('( $name )'),
        pw.SizedBox(height: 4),
        pw.Text(title, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text('วันที่......./......./.......', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600)),
      ],
    );
  }
}

