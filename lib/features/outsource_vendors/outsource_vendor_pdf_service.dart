import 'package:flutter/services.dart';
import 'dart:io';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/database/db_helper.dart';

class OutsourceVendorPdfService {
  static Future<void> generateAndOpen({required String vendorId}) async {
    final rows = await DbHelper.query(
      'SELECT * FROM suppliers WHERE supplier_id = @id',
      params: {'id': vendorId},
    );
    if (rows.isEmpty) return;
    final vendor = rows.first;

    final document = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf')),
      ),
    );

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) {
          final type = vendor['vendor_type'] == 'supply' ? 'จัดหา/อะไหล่' : vendor['vendor_type'] == 'other' ? 'บริการอื่น' : 'รับซ่อม';
          final approved = (vendor['is_approved'] as num? ?? 0) == 1 ? 'อนุมัติแล้ว' : 'รออนุมัติ';
          final active = (vendor['is_active'] as num? ?? 0) == 1 ? 'เปิดใช้งาน' : 'พักใช้งาน';

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text('ข้อมูลผู้รับเหมาซ่อมภายนอก', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF1E3A8A))),
              ),
              pw.SizedBox(height: 24),
              pw.Table(
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(7),
                },
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  _buildRow('รหัสผู้รับเหมา', vendor['supplier_code']),
                  _buildRow('ชื่อบริษัท / ร้าน', vendor['name']),
                  _buildRow('ขอบเขตงาน', vendor['service_scope']),
                  _buildRow('ประเภท', type),
                  _buildRow('ผู้ติดต่อ', vendor['contact_name']),
                  _buildRow('เบอร์โทร', vendor['phone']),
                  _buildRow('อีเมล', vendor['email']),
                  _buildRow('ที่อยู่', vendor['address']),
                  _buildRow('สถานะการอนุมัติ', approved),
                  _buildRow('สถานะการใช้งาน', active),
                ],
              ),
            ],
          );
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Vendor_${vendor['supplier_code'] ?? 'Profile'}.pdf');
    await file.writeAsBytes(await document.save());
    await OpenFilex.open(file.path);
  }

  static pw.TableRow _buildRow(String label, dynamic value) {
    return pw.TableRow(
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          color: PdfColor.fromInt(0xFFF9FAFB),
          child: pw.Text(label, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
        ),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(value?.toString() ?? '-', style: const pw.TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
