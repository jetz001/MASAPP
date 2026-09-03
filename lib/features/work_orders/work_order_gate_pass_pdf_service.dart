import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf')),
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
      ('รายการที่ส่งออกซ่อม', _formatRepairDetails(repairDetails)),
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
            pw.Container(height: 8, color: PdfColor.fromHex('#1E3A8A')),
            pw.SizedBox(height: 24),
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
                              color: PdfColor.fromHex('#1E293B'),
                            ),
                          ),
                        if (orgAddress.isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          pw.Text(
                            orgAddress,
                            style: pw.TextStyle(fontSize: 11, color: PdfColor.fromHex('#475569')),
                          ),
                        ],
                        if (orgPhone.isNotEmpty) ...[
                          pw.SizedBox(height: 2),
                          pw.Text(
                            'โทร. $orgPhone',
                            style: pw.TextStyle(fontSize: 11, color: PdfColor.fromHex('#475569')),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            pw.SizedBox(height: 32),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(width: 4, height: 28, color: PdfColor.fromHex('#1D4ED8')),
                pw.SizedBox(width: 12),
                pw.Text(
                  'ใบผ่านประตู - ส่งซ่อมภายนอก',
                  style: pw.TextStyle(
                    fontSize: 20,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0F172A'),
                  ),
                ),
                pw.Spacer(),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#1E3A8A'),
                    borderRadius: pw.BorderRadius.circular(4),
                  ),
                  child: pw.Text(
                    'GATE PASS',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 32),
            pw.Container(
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 1),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Column(
                children: List.generate(fields.length, (index) {
                  final field = fields[index];
                  final isEven = index % 2 == 0;
                  return pw.Container(
                    decoration: pw.BoxDecoration(
                      color: isEven ? PdfColors.white : PdfColor.fromHex('#F8FAFC'),
                      borderRadius: index == 0
                          ? const pw.BorderRadius.vertical(top: pw.Radius.circular(7))
                          : index == fields.length - 1
                              ? const pw.BorderRadius.vertical(bottom: pw.Radius.circular(7))
                              : pw.BorderRadius.zero,
                    ),
                    padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                    child: pw.Row(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.SizedBox(
                          width: 140,
                          child: pw.Text(
                            field.$1,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#475569'),
                              fontSize: 12,
                            ),
                          ),
                        ),
                        pw.Expanded(
                          child: pw.Text(
                            field.$2,
                            style: pw.TextStyle(
                              color: PdfColor.fromHex('#0F172A'),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ),
            pw.SizedBox(height: 48),
            pw.Container(
              padding: const pw.EdgeInsets.all(24),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F1F5F9'),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _signature('ผู้ส่งมอบ'),
                  _signature('ผู้รับเหมาขนส่ง/รับของ'),
                  _signature('รปภ. อนุญาตให้ออก'),
                ],
              ),
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
        pw.SizedBox(height: 50),
        pw.Container(height: 1, color: PdfColor.fromHex('#94A3B8')),
        pw.SizedBox(height: 8),
        pw.Text(
          label,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 11, color: PdfColor.fromHex('#475569')),
        ),
      ],
    ),
  );

  static String _formatRepairDetails(String details) {
    try {
      final decoded = jsonDecode(details);
      if (decoded is List) {
        return decoded.map((e) {
          final item = e['item'] ?? '';
          final qty = e['qty']?.toString().trim() ?? '';
          final note = e['note']?.toString().trim() ?? '';
          final parts = <String>[item];
          if (qty.isNotEmpty) parts.add('($qty)');
          if (note.isNotEmpty) parts.add('- $note');
          return parts.join(' ');
        }).join('\n');
      }
    } catch (_) {}
    return details;
  }
}

