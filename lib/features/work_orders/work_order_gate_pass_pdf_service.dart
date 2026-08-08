import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/database/db_helper.dart';

class WorkOrderGatePassPdfService {
  static Future<void> generateAndOpen({
    required String woId,
    required String vendorName,
    required String repairDetails,
    String? gatePassNo,
    DateTime? expectedReturnDate,
  }) async {
    final row = await DbHelper.queryOne(
      '''SELECT wo.wo_no, wo.title, wo.description,
        s.machine_no, s.machine_name FROM work_orders wo
        LEFT JOIN machine_snapshots s ON s.snapshot_id = wo.snapshot_id
        WHERE wo.wo_id = @id''',
      params: {'id': woId},
    );
    final document = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.sarabunRegular(),
        bold: await PdfGoogleFonts.sarabunBold(),
      ),
    );

    final settingsRows = await DbHelper.query('SELECT setting_key, setting_value FROM app_settings');
    final settings = {
      for (final r in settingsRows)
        r['setting_key'].toString(): r['setting_value']?.toString() ?? ''
    };
    final orgName = settings['org_name'] ?? '';
    final orgAddress = settings['org_address'] ?? '';
    final orgPhone = settings['org_phone'] ?? '';
    final orgLogoBase64 = settings['org_logo'] ?? '';

    pw.MemoryImage? logoImage;
    if (orgLogoBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(orgLogoBase64);
        logoImage = pw.MemoryImage(bytes);
      } catch (_) {}
    }
    final generatedNo = (gatePassNo != null && gatePassNo.trim().isNotEmpty)
        ? gatePassNo.trim()
        : 'GP-${row?['wo_no'] ?? woId.substring(0, 8)}';
    final fields = <(String, String)>[
      ('เลขที่ Gate Pass', generatedNo),
      ('อ้างอิงใบแจ้งซ่อม', row?['wo_no'] as String? ?? '-'),
      (
        'เครื่องจักร / ทรัพย์สิน',
        '${row?['machine_no'] ?? '-'} ${row?['machine_name'] ?? ''}',
      ),
      ('ผู้รับเหมาซ่อม', vendorName),
      ('รายการที่ส่งออกซ่อม', repairDetails),
      ('กำหนดรับคืน', expectedReturnDate != null ? DateFormat('dd/MM/yyyy').format(expectedReturnDate) : '-'),
      (
        'วันที่ออกเอกสาร',
        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
      ),
    ];
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (orgName.isNotEmpty || logoImage != null)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoImage != null) ...[
                    pw.Image(logoImage, width: 60, height: 60, fit: pw.BoxFit.contain),
                    pw.SizedBox(width: 16),
                  ],
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (orgName.isNotEmpty)
                          pw.Text(
                            orgName,
                            style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        if (orgAddress.isNotEmpty)
                          pw.Text(
                            orgAddress,
                            style: const pw.TextStyle(fontSize: 12),
                          ),
                        if (orgPhone.isNotEmpty)
                          pw.Text(
                            'โทร. $orgPhone',
                            style: const pw.TextStyle(fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            if (orgName.isNotEmpty || logoImage != null)
              pw.SizedBox(height: 24),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'ใบผ่านประตู - ส่งซ่อมภายนอก',
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text(
                  'GATE PASS',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue800,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 18),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey500),
              columnWidths: {0: const pw.FixedColumnWidth(150)},
              children: fields
                  .map(
                    (field) => pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(9),
                          child: pw.Text(
                            field.$1,
                            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(9),
                          child: pw.Text(field.$2),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
            pw.SizedBox(height: 42),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _signature('ผู้ส่งมอบ'),
                _signature('ผู้รับเหมาขนส่ง/รับของ'),
                _signature('รปภ. อนุญาตให้ออก'),
              ],
            ),
          ],
        ),
      ),
    );
    final dir = await getTemporaryDirectory();
    final safeNo = generatedNo;
    final file = File(
      '${dir.path}/GATE_PASS_${safeNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf',
    );
    await file.writeAsBytes(await document.save());
    await OpenFilex.open(file.path);
  }

  static pw.Widget _signature(String label) => pw.SizedBox(
    width: 150,
    child: pw.Column(
      children: [
        pw.SizedBox(height: 36),
        pw.Divider(),
        pw.Text(
          label,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    ),
  );
}

