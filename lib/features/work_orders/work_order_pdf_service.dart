import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

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
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf')),
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

    final outsourceRows = await DbHelper.query(
        '''SELECT o.*, u.full_name, i.full_name as inspector_name 
           FROM work_order_outsource o
           LEFT JOIN users u ON u.user_id = o.created_by
           LEFT JOIN users i ON i.user_id = o.inspector_id
           WHERE o.wo_id = @id ORDER BY o.created_at ASC''',
        params: {'id': woId});
        
    final outsource1 = outsourceRows.isNotEmpty ? outsourceRows[0] : null;
    final outsource2 = outsourceRows.length > 1 ? outsourceRows[1] : null;
    
    // Use the latest one for general info (Section 2 & 3)
    final outsourceRow = outsourceRows.isNotEmpty ? outsourceRows.last : null;

    final vendorName = outsourceRow?['vendor_name'] as String? ?? '';
    final repairDetails = outsourceRow?['repair_details'] as String? ?? '';
    
    final outsourcerName = outsourceRow != null && outsourceRow['full_name'] != null 
        ? outsourceRow['full_name'] as String
        : null;
    final outsourceDate = outsourceRow?['created_at'] != null 
        ? DateTime.tryParse(outsourceRow!['created_at'].toString()) 
        : null;

    // Use latest return for the signature block
    final actualReturnDate = outsourceRow?['actual_return_date'] != null
        ? DateTime.tryParse(outsourceRow!['actual_return_date'].toString())
        : null;
        
    // Keep inspector for Section 4 signature from the latest return
    final inspectorName = outsourceRow?['inspector_name'] as String?;

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
        width: 12,
        height: 12,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 1, color: checked ? PdfColor.fromHex('#1E3A8A') : PdfColors.grey600),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
          color: checked ? PdfColor.fromHex('#EFF6FF') : null,
        ),
        child: checked ? pw.Center(child: pw.Text('/', style: pw.TextStyle(fontSize: 9, color: PdfColor.fromHex('#1E3A8A'), fontWeight: pw.FontWeight.bold))) : null,
      );
    }

    pw.Widget _sectionHeader(String title, {bool isSubHeader = false}) {
      return pw.Container(
        width: double.infinity,
        decoration: pw.BoxDecoration(
          color: isSubHeader ? PdfColor.fromHex('#E5E7EB') : PdfColor.fromHex('#1E3A8A'),
          border: pw.Border(
            bottom: pw.BorderSide(width: 0.5, color: isSubHeader ? PdfColors.grey400 : PdfColor.fromHex('#1E3A8A')),
          ),
        ),
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: pw.Text(
          title, 
          textAlign: isSubHeader ? pw.TextAlign.left : pw.TextAlign.center, 
          style: pw.TextStyle(
            fontWeight: pw.FontWeight.bold, 
            fontSize: isSubHeader ? 10 : 12,
            color: isSubHeader ? PdfColors.black : PdfColors.white,
          )
        ),
      );
    }

    pw.Widget _buildBorderedRow(List<pw.Widget> children, {List<int>? flex}) {
      return pw.Table(
        border: pw.TableBorder(
          bottom: const pw.BorderSide(width: 0.5, color: PdfColors.grey400),
          verticalInside: const pw.BorderSide(width: 0.5, color: PdfColors.grey300),
        ),
        columnWidths: flex != null 
          ? { for (int i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i].toDouble()) }
          : null,
        children: [
          pw.TableRow(
            children: children.map((child) {
              return pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                child: child,
              );
            }).toList(),
          ),
        ]
      );
    }

    pw.Widget _buildDottedRow(String label, String text, {int lines = 3}) {
      return pw.Container(
        width: double.infinity,
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(width: 0.5, color: PdfColors.grey400)),
        ),
        padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(label, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
            pw.SizedBox(height: 4),
            pw.Text(text.isEmpty ? '-' : text, style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 4),
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
                    border: const pw.TableBorder(bottom: pw.BorderSide(width: 1, color: PdfColors.black)),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(3),
                      1: const pw.FlexColumnWidth(7),
                    },
                    children: [
                      pw.TableRow(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.all(8),
                            decoration: const pw.BoxDecoration(border: pw.Border(right: pw.BorderSide(width: 0.5, color: PdfColors.grey400))),
                            child: pw.Center(
                              child: logoImage != null ? pw.Image(logoImage, height: 40, fit: pw.BoxFit.contain) : pw.SizedBox(height: 40),
                            )
                          ),
                          pw.Table(
                            border: const pw.TableBorder(
                              horizontalInside: pw.BorderSide(width: 0.5, color: PdfColors.grey400),
                              verticalInside: pw.BorderSide(width: 0.5, color: PdfColors.grey400),
                            ),
                            columnWidths: {
                              0: const pw.FlexColumnWidth(2),
                              1: const pw.FlexColumnWidth(4),
                              2: const pw.FlexColumnWidth(2),
                              3: const pw.FlexColumnWidth(2),
                            },
                            children: [
                              pw.TableRow(
                                decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F9FAFB')), // Light gray bg for header
                                children: [
                                  pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text('ระดับเอกสาร', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey800))),
                                  pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text('ชื่อเอกสาร', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey800))),
                                  pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text('สถานะเอกสาร', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey800))),
                                  pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 6), child: pw.Text('รหัสเอกสาร', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, color: PdfColors.grey800))),
                                ],
                              ),
                              pw.TableRow(
                                children: [
                                  pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 8), child: pw.Text('ฟอร์มเอกสาร', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                                  pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 8), child: pw.Text('ใบแจ้งซ่อม', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E3A8A')))), // Accent color for title
                                  pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 8), child: pw.Text(docRev, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
                                  pw.Container(padding: const pw.EdgeInsets.symmetric(vertical: 8), child: pw.Text(docCode, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10))),
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
                    pw.Text('ชื่อเครื่อง: ${wo.machineBrand ?? ''}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text('รหัสเครื่อง M/C NO.: ${wo.machineNo ?? ''}', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
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
                    pw.Text('ลงชื่อ ช่างซ่อมบำรุง: ${wo.assignedToName ?? outsourcerName ?? ''}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('วันที่: ${wo.completedAt != null ? DateFormat('dd/MM/yyyy').format(wo.completedAt!) : outsourceDate != null ? DateFormat('dd/MM/yyyy').format(outsourceDate) : ''}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('เวลา: ${wo.completedAt != null ? DateFormat('HH:mm').format(wo.completedAt!) : outsourceDate != null ? DateFormat('HH:mm').format(outsourceDate) : ''}', style: const pw.TextStyle(fontSize: 10)),
                  ], flex: [4, 2, 2]),
                  _buildBorderedRow([
                    pw.Text('ลงชื่อ ผู้อนุมัติซ่อม: ${wo.approvedByName ?? outsourcerName ?? ''}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('วันที่: ${wo.approvedAt != null ? DateFormat('dd/MM/yyyy').format(wo.approvedAt!) : outsourceDate != null ? DateFormat('dd/MM/yyyy').format(outsourceDate) : ''}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('', style: const pw.TextStyle(fontSize: 10)),
                  ], flex: [4, 2, 2]),

                  // Section 3
                  _sectionHeader('3. ส่งซ่อมภายนอก'),
                  _sectionHeader('รายการนำออกเพื่อส่งซ่อม', isSubHeader: true),
                  _buildBorderedRow([
                    pw.Text('No', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E3A8A'))),
                    pw.Text('รายการ', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E3A8A'))),
                    pw.Text('จำนวน', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E3A8A'))),
                    pw.Text('หมายเหตุ', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColor.fromHex('#1E3A8A'))),
                  ], flex: [1, 5, 2, 3]),
                  ...() {
                    List<Map<String, String>> parsedItems = [];
                    try {
                      final decoded = jsonDecode(repairDetails);
                      if (decoded is List) {
                        parsedItems = decoded.map((e) => {
                          'item': e['item']?.toString() ?? '',
                          'qty': e['qty']?.toString() ?? '',
                          'note': e['note']?.toString() ?? '',
                        }).toList();
                      }
                    } catch (_) {
                      final lines = repairDetails.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                      parsedItems = lines.map((e) => {'item': e, 'qty': '', 'note': ''}).toList();
                    }

                    if (parsedItems.isEmpty) {
                      return [
                        _buildBorderedRow([
                          pw.Text('1', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                          pw.Text('', style: const pw.TextStyle(fontSize: 10)),
                          pw.Text('', style: const pw.TextStyle(fontSize: 10)),
                          pw.Text('', style: const pw.TextStyle(fontSize: 10)),
                        ], flex: [1, 5, 2, 3])
                      ];
                    }
                    return List.generate(parsedItems.length, (index) {
                      final item = parsedItems[index];
                      return _buildBorderedRow([
                        pw.Text('${index + 1}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(item['item'] ?? '', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(item['qty'] ?? '', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(item['note'] ?? '', style: const pw.TextStyle(fontSize: 10)),
                      ], flex: [1, 5, 2, 3]);
                    });
                  }(),
                  _buildBorderedRow([
                    pw.Text('ช่างซ่อมบำรุง: ${wo.assignedToName ?? outsourcerName ?? ''}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('วันที่ส่งซ่อม: ${outsourceDate != null ? DateFormat('dd/MM/yyyy').format(outsourceDate) : '____________'}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('เวลา: ${outsourceDate != null ? DateFormat('HH:mm').format(outsourceDate) : '____________'}', style: const pw.TextStyle(fontSize: 10)),
                  ], flex: [4, 2, 2]),

                  // Section 4
                  _sectionHeader('4. รับคืนจากซ่อมภายนอก'),
                  ...() {
                    final List<pw.Widget> resultRows = [];
                    int globalAttempt = 1;
                    
                    for (final row in outsourceRows) {
                      final actualReturn = row['actual_return_date'] != null ? DateTime.tryParse(row['actual_return_date'].toString()) : null;
                      final notesStr = (row['notes'] ?? '').toString();
                      final noteLines = notesStr.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                      
                      if (noteLines.isEmpty) {
                        if (actualReturn != null) {
                          final passed = row['is_passed_inspection'] == 1;
                          resultRows.add(_buildBorderedRow([
                            pw.Text('ผลการซ่อมครั้งที่ $globalAttempt', style: const pw.TextStyle(fontSize: 10)),
                            pw.Row(children: [
                              _checkbox(passed), pw.SizedBox(width: 8), pw.Text('ใช้งานได้ปกติ', style: const pw.TextStyle(fontSize: 10)),
                              pw.SizedBox(width: 24),
                              _checkbox(!passed), pw.SizedBox(width: 8), pw.Text('ใช้งานไม่ได้(ส่งคืนซ่อมใหม่)', style: const pw.TextStyle(fontSize: 10)),
                            ]),
                            pw.Text('วันที่: ${DateFormat('dd/MM/yyyy').format(actualReturn)}', style: const pw.TextStyle(fontSize: 10)),
                          ], flex: [2, 5, 2]));
                          globalAttempt++;
                        }
                      } else {
                        for (int i = 0; i < noteLines.length; i++) {
                          final line = noteLines[i];
                          bool isPass = line.startsWith('[ผ่าน]');
                          bool isReject = line.startsWith('[ตีกลับ]');
                          
                          String dateStr = '____________';
                          final dateMatch = RegExp(r'\[(\d{2}/\d{2}/\d{4})\]').firstMatch(line);
                          if (dateMatch != null) {
                            dateStr = dateMatch.group(1)!;
                          } else if (i == noteLines.length - 1 && actualReturn != null) {
                             dateStr = DateFormat('dd/MM/yyyy').format(actualReturn);
                          }
                          
                          bool thisPass = false;
                          bool thisReject = false;
                          if (isPass) thisPass = true;
                          else if (isReject) thisReject = true;
                          else if (i == noteLines.length - 1 && actualReturn != null) {
                             thisPass = row['is_passed_inspection'] == 1;
                             thisReject = !thisPass;
                          }

                          String cleanNote = line.replaceFirst('[ผ่าน]', '').replaceFirst('[ตีกลับ]', '').replaceAll(RegExp(r'\[\d{2}/\d{2}/\d{4}\]'), '').trim();
                          
                          resultRows.add(_buildBorderedRow([
                            pw.Text('ผลการซ่อมครั้งที่ $globalAttempt', style: const pw.TextStyle(fontSize: 10)),
                            pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Row(children: [
                                  _checkbox(thisPass), pw.SizedBox(width: 8), pw.Text('ใช้งานได้ปกติ', style: const pw.TextStyle(fontSize: 10)),
                                  pw.SizedBox(width: 24),
                                  _checkbox(thisReject), pw.SizedBox(width: 8), pw.Text('ใช้งานไม่ได้(ส่งคืนซ่อมใหม่)', style: const pw.TextStyle(fontSize: 10)),
                                ]),
                                if (cleanNote.isNotEmpty)
                                  pw.Padding(padding: const pw.EdgeInsets.only(top: 4), child: pw.Text('หมายเหตุ: $cleanNote', style: const pw.TextStyle(fontSize: 10))),
                              ]
                            ),
                            pw.Text('วันที่: $dateStr', style: const pw.TextStyle(fontSize: 10)),
                          ], flex: [2, 5, 2]));
                          
                          globalAttempt++;
                        }
                      }
                    }
                    
                    if (resultRows.isEmpty) {
                       resultRows.add(_buildBorderedRow([
                         pw.Text('ผลการซ่อมครั้งที่ 1', style: const pw.TextStyle(fontSize: 10)),
                         pw.Row(children: [
                           _checkbox(false), pw.SizedBox(width: 8), pw.Text('ใช้งานได้ปกติ', style: const pw.TextStyle(fontSize: 10)),
                           pw.SizedBox(width: 24),
                           _checkbox(false), pw.SizedBox(width: 8), pw.Text('ใช้งานไม่ได้(ส่งคืนซ่อมใหม่)', style: const pw.TextStyle(fontSize: 10)),
                         ]),
                         pw.Text('วันที่: ____________', style: const pw.TextStyle(fontSize: 10)),
                       ], flex: [2, 5, 2]));
                    }
                    
                    return resultRows;
                  }(),
                  _buildBorderedRow([
                    pw.Text('ลงชื่อ ช่างซ่อมบำรุง: ${inspectorName ?? '____________'}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('วันที่รับคืน: ${actualReturnDate != null ? DateFormat('dd/MM/yyyy').format(actualReturnDate) : '____________'}', style: const pw.TextStyle(fontSize: 10)),
                    pw.Text('เวลา: ${actualReturnDate != null ? DateFormat('HH:mm').format(actualReturnDate) : '____________'}', style: const pw.TextStyle(fontSize: 10)),
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

  static Future<void> generateSparePartRequisition({required String woId}) async {
    final repo = WorkOrderRepository();
    final wo = await repo.getWorkOrder(woId);
    if (wo == null) return;

    final rows = await DbHelper.query(
      '''SELECT wp.*, sp.part_name, sp.part_code
         FROM work_order_parts wp
         JOIN spare_parts sp ON sp.part_id = wp.part_id
         WHERE wp.wo_id = @woId
         ORDER BY wp.created_at ASC''',
      params: {'woId': woId},
    );
    final parts = rows.map((r) => WorkOrderPart.fromMap(r)).toList();

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
    final orgLogoBase64 = settings['org_logo'] ?? '';

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                if (orgLogoBase64.isNotEmpty)
                  pw.Container(
                    width: 60,
                    height: 60,
                    child: pw.Image(pw.MemoryImage(base64Decode(orgLogoBase64))),
                  )
                else
                  pw.SizedBox(width: 60),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text('ใบเบิกวัสดุ / อะไหล่ (Material Requisition Form)', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
                    pw.Text('อ้างอิงใบแจ้งซ่อม: ${wo.woNo}', style: const pw.TextStyle(fontSize: 14)),
                  ],
                ),
                pw.SizedBox(width: 60),
              ],
            ),
            pw.SizedBox(height: 20),

            // Info
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('ชื่อเครื่องจักร: ${wo.machineNo ?? "-"}', style: const pw.TextStyle(fontSize: 12)),
                pw.Text('วันที่ขอเบิก: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 12)),
              ],
            ),
            pw.SizedBox(height: 10),

            // Table
            pw.TableHelper.fromTextArray(
              headers: ['ลำดับ', 'รหัสอะไหล่', 'รายการ', 'จำนวน', 'หน่วย'],
              data: List.generate(parts.length, (index) {
                final p = parts[index];
                return [
                  (index + 1).toString(),
                  p.partCode ?? '-',
                  p.partName ?? '-',
                  p.quantity.toString(),
                  'ชิ้น', // Assuming pieces
                ];
              }),
              border: pw.TableBorder.all(),
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
              cellStyle: const pw.TextStyle(fontSize: 12),
              cellAlignment: pw.Alignment.centerLeft,
            ),
            pw.SizedBox(height: 40),

            // Signatures
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                pw.Column(
                  children: [
                    pw.Text('ผู้ขอเบิก (ผู้รับของ)'),
                    pw.SizedBox(height: 40),
                    pw.Text('(................................................)'),
                    pw.Text('วันที่: ....../....../......'),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('ผู้อนุมัติจ่ายของ'),
                    pw.SizedBox(height: 40),
                    pw.Text('(................................................)'),
                    pw.Text('วันที่: ....../....../......'),
                  ],
                ),
                pw.Column(
                  children: [
                    pw.Text('ผู้จ่ายของ'),
                    pw.SizedBox(height: 40),
                    pw.Text('(................................................)'),
                    pw.Text('วันที่: ....../....../......'),
                  ],
                ),
              ],
            ),
          ];
        },
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/Requisition_${wo.woNo.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_')}.pdf',
    );
    await file.writeAsBytes(await document.save());
    await OpenFilex.open(file.path);
  }
}
