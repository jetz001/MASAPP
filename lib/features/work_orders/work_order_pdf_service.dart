import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/database/db_helper.dart';
import 'work_order_models.dart';
import 'work_order_provider.dart';

class WorkOrderPdfService {
  static Future<void> generateAndOpen({required String woId}) async {
    final repo = WorkOrderRepository();
    final wo = await repo.getWorkOrder(woId);
    if (wo == null) return;

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
    final orgLogoBase64 = settings['org_logo'] ?? '';
    final docRefStr = settings['doc_work_order_ref'] ?? 'F-MA-06 Rev2';
    
    String docCode = 'F-MA-06';
    String docRev = 'Rev.2';
    final parts = docRefStr.split(' ');
    if (parts.length >= 2) {
      docCode = parts[0];
      docRev = parts.sublist(1).join(' ');
      if (!docRev.toLowerCase().contains('.')) {
        docRev = docRev.replaceFirst(RegExp(r'rev', caseSensitive: false), 'Rev.');
      }
    } else if (parts.length == 1) {
      docCode = parts[0];
      docRev = '';
    }

    pw.MemoryImage? logoImage;
    if (orgLogoBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(orgLogoBase64);
        logoImage = pw.MemoryImage(bytes);
      } catch (_) {}
    }

    final outsourceRow = await DbHelper.queryOne(
        'SELECT * FROM work_order_outsource WHERE wo_id = @id ORDER BY created_at DESC LIMIT 1',
        params: {'id': woId});
    final vendorName = outsourceRow?['vendor_name'] as String? ?? '';
    final repairDetails = outsourceRow?['repair_details'] as String? ?? '';

    // Load attachments
    final attachmentImages = <pw.MemoryImage>[];
    if (wo.attachments != null) {
      for (final path in wo.attachments!) {
        final file = File(path);
        if (await file.exists()) {
          try {
            final bytes = await file.readAsBytes();
            attachmentImages.add(pw.MemoryImage(bytes));
          } catch (_) {}
        }
      }
    }

    pw.Widget _checkbox(bool checked) {
      return pw.Container(
        width: 10,
        height: 10,
        decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
        child: checked ? pw.Center(child: pw.Text('/', style: const pw.TextStyle(fontSize: 8))) : null,
      );
    }

    pw.Widget _sectionHeader(String title, {bool isSubHeader = false}) {
      return pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(
          color: isSubHeader ? PdfColors.grey200 : PdfColors.grey300,
          border: const pw.Border(bottom: pw.BorderSide(width: 0.5)),
        ),
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Text(title, textAlign: pw.TextAlign.center, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
      );
    }

    pw.Widget _buildBorderedRow(List<pw.Widget> children, {List<int>? flex}) {
      return pw.Table(
        border: const pw.TableBorder(
          bottom: pw.BorderSide(width: 0.5),
          verticalInside: pw.BorderSide(width: 0.5),
        ),
        columnWidths: flex != null 
          ? { for (int i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i].toDouble()) }
          : null,
        children: [
          pw.TableRow(
            children: children.map((child) {
              return pw.Container(
                padding: const pw.EdgeInsets.all(4),
                child: child,
              );
            }).toList(),
          ),
        ]
      );
    }

    pw.Widget _buildDottedRow(String label, String text, {int lines = 3}) {
      return pw.Container(
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
        padding: const pw.EdgeInsets.all(4),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('$label $text', style: const pw.TextStyle(fontSize: 10)),
            for (int i = 1; i < lines; i++) ...[
              pw.SizedBox(height: 14),
              pw.Divider(borderStyle: pw.BorderStyle.dashed, thickness: 0.5, color: PdfColors.grey500),
            ]
          ],
        ),
      );
    }

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            // Outer Border
            pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
              child: pw.Column(
                children: [
                  // Header
                  pw.Table(
                    border: const pw.TableBorder(bottom: pw.BorderSide(width: 0.5)),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2),
                      1: const pw.FlexColumnWidth(8),
                    },
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.all(4),
                            decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5))),
                            child: pw.Center(
                              child: logoImage != null ? pw.Image(logoImage, height: 35, fit: pw.BoxFit.contain) : pw.SizedBox(height: 35),
                            )
                          ),
                          pw.Table(
                            border: const pw.TableBorder(
                              horizontalInside: pw.BorderSide(width: 0.5),
                              verticalInside: pw.BorderSide(width: 0.5),
                            ),
                            columnWidths: {
                              0: const pw.FlexColumnWidth(2),
                              1: const pw.FlexColumnWidth(4),
                              2: const pw.FlexColumnWidth(2),
                              3: const pw.FlexColumnWidth(2),
                            },
                            children: [
                              pw.TableRow(
                                children: [
                                  pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('ระดับเอกสาร', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                                  pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('ชื่อเอกสาร', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                                  pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('สถานะเอกสาร', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                                  pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('รหัสเอกสาร', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                                ],
                              ),
                              pw.TableRow(
                                children: [
                                  pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('ฟอร์มเอกสาร', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                                  pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text('ใบแจ้งซ่อม', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold))),
                                  pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(docRev, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                                  pw.Container(padding: const pw.EdgeInsets.all(4), child: pw.Text(docCode, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                                ],
                              ),
                            ]
                          )
                        ]
                      )
                    ]
                  ),

                  // Section 1
                  _sectionHeader('1. ส่วนผู้แจ้งซ่อม'),
                  _buildBorderedRow([
                    pw.Text('ชื่อเครื่อง: ${wo.machineBrand ?? ''}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('รหัสเครื่อง M/C NO.: ${wo.machineNo ?? ''}', style: const pw.TextStyle(fontSize: 10)),
                  ], flex: [1, 1]),
                  _buildDottedRow('อาการเสียที่พบ/สิ่งที่ต้องการให้ดำเนินการ:', wo.failureSymptom ?? wo.description ?? '', lines: 3),
                  _buildBorderedRow([
                    pw.Text('ลงชื่อ ผู้แจ้งซ่อม: ${wo.reportedByName ?? 'SYSTEM'}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('วันที่: ${DateFormat('dd/MM/yyyy').format(wo.reportedAt)}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('เวลา: ${DateFormat('HH:mm').format(wo.reportedAt)}', style: const pw.TextStyle(fontSize: 10)),
                  ], flex: [4, 2, 2]),

                  // Section 2
                  _sectionHeader('2. ส่วนช่างซ่อมบำรุง'),
                  _buildDottedRow('สาเหตุของอาการที่เสีย:', wo.rca?.rootCause ?? '', lines: 3),
                  _buildDottedRow('รายละเอียดการซ่อม:', wo.closureNotes ?? '', lines: 3),
                  _buildBorderedRow([
                    pw.Row(children: [
                      pw.Text('สรุปผลการซ่อม', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(width: 24),
                      _checkbox(wo.status == WorkOrderStatus.completed && outsourceRow == null),
                      pw.SizedBox(width: 8),
                      pw.Text('ซ่อมเสร็จสิ้น', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(width: 24),
                      _checkbox(outsourceRow != null || wo.status == WorkOrderStatus.outsourced),
                      pw.SizedBox(width: 8),
                      pw.Text('ส่งซ่อมภายนอก', style: const pw.TextStyle(fontSize: 10)),
                    ])
                  ]),
                  _buildBorderedRow([
                    pw.Text('ชื่อ/บริษัท ที่ส่งซ่อม: $vendorName', style: const pw.TextStyle(fontSize: 10)),
                  ]),
                  _buildBorderedRow([
                    pw.Text('ลงชื่อ ช่างซ่อมบำรุง: ${wo.assignedToName ?? ''}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('วันที่: ${wo.completedAt != null ? DateFormat('dd/MM/yyyy').format(wo.completedAt!) : ''}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('เวลา: ${wo.completedAt != null ? DateFormat('HH:mm').format(wo.completedAt!) : ''}', style: const pw.TextStyle(fontSize: 10)),
                  ], flex: [4, 2, 2]),
                  _buildBorderedRow([
                    pw.Text('ลงชื่อ ผู้อนุมัติซ่อม: ${wo.approvedByName ?? ''}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('วันที่: ${wo.approvedAt != null ? DateFormat('dd/MM/yyyy').format(wo.approvedAt!) : ''}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('', style: const pw.TextStyle(fontSize: 10)),
                  ], flex: [4, 2, 2]),

                  // Section 3
                  _sectionHeader('3. ส่งซ่อมภายนอก'),
                  _sectionHeader('รายการนำออกเพื่อส่งซ่อม', isSubHeader: true),
                  _buildBorderedRow([
                    pw.Text('No', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text('รายการ', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text('จำนวน', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text('หมายเหตุ', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  ], flex: [1, 5, 2, 3]),
                  for (int i = 1; i <= 4; i++)
                    _buildBorderedRow([
                      pw.Text('$i', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                      pw.Text(i == 1 ? repairDetails : '', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('', style: const pw.TextStyle(fontSize: 10)),
                      pw.Text('', style: const pw.TextStyle(fontSize: 10)),
                    ], flex: [1, 5, 2, 3]),
                  _buildBorderedRow([
                    pw.Text('ช่างซ่อมบำรุง: ${wo.assignedToName ?? ''}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('วันที่ส่งซ่อม: ____________', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('เวลา: ____________', style: const pw.TextStyle(fontSize: 10)),
                  ], flex: [4, 2, 2]),

                  // Section 4
                  _sectionHeader('4. รับคืนจากซ่อมภายนอก'),
                  _buildBorderedRow([
                    pw.Text('ผลการซ่อมครั้งที่ 1', style: const pw.TextStyle(fontSize: 10)),
                    pw.Row(children: [
                      _checkbox(false), pw.SizedBox(width: 8), pw.Text('ใช้งานได้ปกติ', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(width: 24),
                      _checkbox(false), pw.SizedBox(width: 8), pw.Text('ใช้งานไม่ได้(ส่งคืนซ่อมใหม่)', style: const pw.TextStyle(fontSize: 10)),
                    ]),
                    pw.Text('วันที่: ____________', style: const pw.TextStyle(fontSize: 10)),
                  ], flex: [2, 5, 2]),
                  _buildBorderedRow([
                    pw.Text('ผลการซ่อมครั้งที่ 2', style: const pw.TextStyle(fontSize: 10)),
                    pw.Row(children: [
                      _checkbox(false), pw.SizedBox(width: 8), pw.Text('ใช้งานได้ปกติ', style: const pw.TextStyle(fontSize: 10)),
                      pw.SizedBox(width: 24),
                      _checkbox(false), pw.SizedBox(width: 8), pw.Text('ใช้งานไม่ได้(ส่งคืนซ่อมใหม่)', style: const pw.TextStyle(fontSize: 10)),
                    ]),
                    pw.Text('วันที่: ____________', style: const pw.TextStyle(fontSize: 10)),
                  ], flex: [2, 5, 2]),
                  _buildBorderedRow([
                    pw.Text('ลงชื่อ ช่างซ่อมบำรุง: ____________', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('วันที่รับคืน: ____________', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('เวลา: ____________', style: const pw.TextStyle(fontSize: 10)),
                  ], flex: [4, 2, 2]),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    // Add attachments pages
    for (final img in attachmentImages) {
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (_) => pw.Center(
            child: pw.Image(img, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/WO_${wo.woNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf',
    );
    await file.writeAsBytes(await document.save());
    await OpenFilex.open(file.path);
  }
}
