import 'dart:io';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../core/database/db_helper.dart';

class OutsourceVendorLogSheetPdfService {
  static Future<void> generateAndOpen({String keyword = ''}) async {
    final document = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.sarabunRegular(),
        bold: await PdfGoogleFonts.sarabunBold(),
      ),
    );

    final rows = await DbHelper.query(
      '''SELECT supplier_code, name, contact_name, phone, email, service_scope, vendor_type, is_approved 
         FROM suppliers 
         WHERE is_outsource_vendor = 1 
           AND (@keyword = '' OR name LIKE @like OR supplier_code LIKE @like OR service_scope LIKE @like)
         ORDER BY is_active DESC, name''',
      params: {'keyword': keyword, 'like': '%$keyword%'},
    );

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            pw.Text(
              'ทะเบียนผู้รับเหมาซ่อมภายนอก (Outsource Vendors)',
              style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF1E3A8A)),
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
              headers: [
                'รหัส',
                'ชื่อบริษัท / ร้าน',
                'ขอบเขตงาน',
                'ประเภท',
                'ผู้ติดต่อ',
                'เบอร์โทร',
                'สถานะ'
              ],
              data: rows.map((r) {
                final type = r['vendor_type'] == 'supply' ? 'จัดหา/อะไหล่' : r['vendor_type'] == 'other' ? 'บริการอื่น' : 'รับซ่อม';
                final approved = (r['is_approved'] as num? ?? 0) == 1 ? 'อนุมัติแล้ว' : 'รออนุมัติ';
                return [
                  r['supplier_code']?.toString() ?? '',
                  r['name']?.toString() ?? '',
                  r['service_scope']?.toString() ?? '',
                  type,
                  r['contact_name']?.toString() ?? '',
                  r['phone']?.toString() ?? '',
                  approved,
                ];
              }).toList(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF1E3A8A)),
              cellStyle: const pw.TextStyle(fontSize: 10),
              cellPadding: const pw.EdgeInsets.all(6),
              border: pw.TableBorder.all(color: PdfColors.grey300),
            ),
          ];
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/Outsource_Vendors_LogSheet.pdf');
    await file.writeAsBytes(await document.save());
    await OpenFilex.open(file.path);
  }
}
