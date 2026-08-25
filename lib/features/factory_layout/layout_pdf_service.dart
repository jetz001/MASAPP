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
import 'layout_models.dart';
import '../../core/database/db_helper.dart';
import '../settings/settings_provider.dart';

class LayoutPdfService {
  static Future<void> generateMachineTag({
    required FactoryLayout layout,
    required MachinePosition machine,
    required AppSettingsState settings,
    required String userName,
    String? imagePath,
  }) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf')),
      ),
    );

    final logoBase64 = settings.get(AppSettingKeys.orgLogo);
    final docRef = settings.get(AppSettingKeys.docMachineTagRef, defaultValue: 'F-MA-18 Rev1');
    final companyName = settings.get(AppSettingKeys.orgName, defaultValue: 'BOSSCARTON');

    // Query Full Machine Data & Specifications from DB
    Map<String, dynamic>? machineRow;
    Map<String, dynamic>? specRow;
    List<Map<String, dynamic>> attachmentsList = [];
    try {
      final rows = await DbHelper.query(
        '''
        SELECT m.*, 
               c.name AS category_name, 
               d.dept_name,
               s.name AS supplier_name
        FROM machines m
        LEFT JOIN machine_categories c ON c.category_id = m.category_id
        LEFT JOIN departments d ON d.dept_id = m.dept_id
        LEFT JOIN suppliers s ON s.supplier_id = m.supplier_id
        WHERE m.machine_id = @id
        ''',
        params: {'id': machine.machineId},
      );
      if (rows.isNotEmpty) {
        machineRow = rows.first;
      }
      final sRows = await DbHelper.query(
        'SELECT * FROM machine_specs WHERE machine_id = @id',
        params: {'id': machine.machineId},
      );
      if (sRows.isNotEmpty) {
        specRow = sRows.first;
      }
      attachmentsList = await DbHelper.query(
        '''
        SELECT a.* FROM handover_attachments a
        JOIN machine_handover h ON h.handover_id = a.handover_id
        WHERE h.machine_id = @id
        ORDER BY a.uploaded_at DESC
        ''',
        params: {'id': machine.machineId},
      );
    } catch (e) {
      debugPrint('Error querying machine profile for PDF: $e');
    }

    // 1. Prepare Background Image
    pw.ImageProvider? bgImage;
    try {
      if (layout.backgroundPath != null) {
        final file = File(layout.backgroundPath!);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          if (layout.backgroundPath!.toLowerCase().endsWith('.pdf')) {
            await for (final page in Printing.raster(bytes, pages: [0], dpi: 150)) {
              final pngBytes = await page.toPng();
              bgImage = pw.MemoryImage(pngBytes);
              break;
            }
          } else {
            bgImage = pw.MemoryImage(bytes);
          }
        }
      }
    } catch (e) {
      debugPrint('PDF Export Error (Background Image): $e');
    }

    pw.MemoryImage? logoImage;
    if (logoBase64.isNotEmpty) {
      try {
        logoImage = pw.MemoryImage(base64Decode(logoBase64));
      } catch (e) {
        debugPrint('Logo decode error: $e');
      }
    }
    
    // Resolve Machine Photo from parameter or Machine Registry attachments
    pw.MemoryImage? machinePhoto;
    String? resolvedImagePath = imagePath;
    if (resolvedImagePath == null || !File(resolvedImagePath).existsSync()) {
      for (final att in attachmentsList) {
        final p = att['file_path'] as String?;
        if (p != null) {
          final lower = p.toLowerCase();
          if (lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.png') ||
              lower.endsWith('.webp')) {
            if (File(p).existsSync()) {
              resolvedImagePath = p;
              break;
            }
          }
        }
      }
    }
    if (resolvedImagePath != null) {
      try {
        final file = File(resolvedImagePath);
        if (await file.exists()) {
          machinePhoto = pw.MemoryImage(await file.readAsBytes());
        }
      } catch (e) {
        debugPrint('Machine photo decode error: $e');
      }
    }

    PdfColor statusColor;
    PdfColor statusBgColor;
    switch (machine.status) {
      case MachineLayoutStatus.normal:
        statusColor = PdfColors.green700;
        statusBgColor = PdfColors.green50;
        break;
      case MachineLayoutStatus.maintenance:
        statusColor = PdfColors.amber700;
        statusBgColor = PdfColors.amber50;
        break;
      case MachineLayoutStatus.breakdown:
        statusColor = PdfColors.red700;
        statusBgColor = PdfColors.red50;
        break;
      case MachineLayoutStatus.offline:
        statusColor = PdfColors.grey700;
        statusBgColor = PdfColors.grey100;
        break;
      case MachineLayoutStatus.alert:
        statusColor = PdfColors.orange700;
        statusBgColor = PdfColors.orange50;
        break;
    }

    final bool isPortraitLayout = layout.canvasSize.height > layout.canvasSize.width;

    pdf.addPage(
      pw.Page(
        pageFormat: isPortraitLayout ? PdfPageFormat.a4 : PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(14),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // --- 1. MODERN HEADER BAR ---
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    // Left: Logo & Company
                    pw.Row(
                      children: [
                        if (logoImage != null)
                          pw.Container(
                            height: 36,
                            width: 36,
                            margin: const pw.EdgeInsets.only(right: 10),
                            child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                          ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                              companyName,
                              style: pw.TextStyle(fontSize: 12.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800),
                            ),
                            pw.Text(
                              'MASAPP - Maintenance Asset & Space System',
                              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Center: Document Title & Area
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          'แผนผังระบุตำแหน่งเครื่องจักร',
                          style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.indigo50,
                            borderRadius: pw.BorderRadius.circular(4),
                            border: pw.Border.all(color: PdfColors.indigo200, width: 0.8),
                          ),
                          child: pw.Text(
                            'พื้นที่ (Area): ${layout.name}',
                            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.indigo800),
                          ),
                        ),
                      ],
                    ),

                    // Right: Doc Ref & Date
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: pw.BoxDecoration(
                            color: PdfColors.blueGrey50,
                            borderRadius: pw.BorderRadius.circular(4),
                            border: pw.Border.all(color: PdfColors.blueGrey200, width: 0.8),
                          ),
                          child: pw.Text(
                            docRef,
                            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey700),
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()),
                          style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 8),

              // --- 2. MAIN BODY (PLAN + MACHINE DETAILS) ---
              pw.Expanded(
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                  children: [
                    // --- LEFT: FLOOR PLAN AREA ---
                    pw.Expanded(
                      flex: 7,
                      child: pw.Container(
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey100,
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(color: PdfColors.grey300),
                        ),
                        child: pw.Stack(
                          children: [
                            pw.LayoutBuilder(builder: (context, constraints) {
                              double canvasW = layout.canvasSize.width;
                              double canvasH = layout.canvasSize.height;
                              double containerW = constraints!.maxWidth;
                              double containerH = constraints.maxHeight;

                              double scale = (containerW / canvasW).clamp(0.0, containerH / canvasH);
                              double drawW = canvasW * scale;
                              double drawH = canvasH * scale;
                              double offsetX = (containerW - drawW) / 2;
                              double offsetY = (containerH - drawH) / 2;

                              pw.Widget? alignedImage;
                              if (bgImage is pw.MemoryImage) {
                                double imgW = bgImage.width!.toDouble();
                                double imgH = bgImage.height!.toDouble();
                                double imgAspect = imgW / imgH;
                                double canvasAspect = canvasW / canvasH;

                                double bgDrawW, bgDrawH, bgOffsetX = 0, bgOffsetY = 0;
                                if (imgAspect > canvasAspect) {
                                  bgDrawW = drawW;
                                  bgDrawH = drawW / imgAspect;
                                  bgOffsetY = (drawH - bgDrawH) / 2;
                                } else {
                                  bgDrawH = drawH;
                                  bgDrawW = drawH * imgAspect;
                                  bgOffsetX = (drawW - bgDrawW) / 2;
                                }

                                alignedImage = pw.Positioned(
                                  left: offsetX + bgOffsetX,
                                  top: offsetY + bgOffsetY,
                                  child: pw.SizedBox(
                                    width: bgDrawW,
                                    height: bgDrawH,
                                    child: pw.Image(bgImage, fit: pw.BoxFit.fill),
                                  ),
                                );
                              }

                              final px = offsetX + (machine.position.dx * scale);
                              final py = offsetY + (machine.position.dy * scale);

                              return pw.Stack(
                                children: [
                                  alignedImage ?? pw.SizedBox(),

                                  // Glowing Halo Ring around the machine dot
                                  pw.Positioned(
                                    left: px - 11,
                                    top: py - 11,
                                    child: pw.Container(
                                      width: 22,
                                      height: 22,
                                      decoration: pw.BoxDecoration(
                                        shape: pw.BoxShape.circle,
                                        border: pw.Border.all(color: statusColor, width: 1.5),
                                      ),
                                    ),
                                  ),

                                  // Pin Point Dot on the exact coordinate
                                  pw.Positioned(
                                    left: px - 5,
                                    top: py - 5,
                                    child: pw.Container(
                                      width: 10,
                                      height: 10,
                                      decoration: pw.BoxDecoration(
                                        color: statusColor,
                                        shape: pw.BoxShape.circle,
                                        border: pw.Border.all(color: PdfColors.white, width: 1.8),
                                      ),
                                    ),
                                  ),

                                  // Modern Machine Tag Badge
                                  pw.Positioned(
                                    left: px - 22,
                                    top: py - 26,
                                    child: pw.Container(
                                      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                      decoration: pw.BoxDecoration(
                                        color: PdfColors.white,
                                        borderRadius: pw.BorderRadius.circular(4),
                                        border: pw.Border.all(color: statusColor, width: 1.2),
                                      ),
                                      child: pw.Row(
                                        mainAxisSize: pw.MainAxisSize.min,
                                        children: [
                                          pw.Container(
                                            width: 4,
                                            height: 4,
                                            decoration: pw.BoxDecoration(
                                              color: statusColor,
                                              shape: pw.BoxShape.circle,
                                            ),
                                          ),
                                          pw.SizedBox(width: 3),
                                          pw.Text(
                                            machine.machineNo,
                                            style: pw.TextStyle(
                                              fontSize: 8.5,
                                              fontWeight: pw.FontWeight.bold,
                                              color: PdfColors.blueGrey900,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    ),

                    pw.SizedBox(width: 8),

                    // --- RIGHT: COMPREHENSIVE MACHINE DETAIL CARD ---
                    pw.Expanded(
                      flex: 3,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(8),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.white,
                          borderRadius: pw.BorderRadius.circular(8),
                          border: pw.Border.all(color: PdfColors.grey300),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            // 1. Machine Code, Name & Status Pill
                            pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Expanded(
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                    children: [
                                      pw.Text(
                                        machine.machineNo,
                                        style: pw.TextStyle(
                                          fontSize: 16,
                                          fontWeight: pw.FontWeight.bold,
                                          color: PdfColors.blueGrey900,
                                        ),
                                      ),
                                      if (machineRow?['machine_name'] != null &&
                                          (machineRow!['machine_name'] as String).trim().isNotEmpty)
                                        pw.Text(
                                          machineRow['machine_name'] as String,
                                          style: pw.TextStyle(
                                            fontSize: 10,
                                            fontWeight: pw.FontWeight.bold,
                                            color: PdfColors.indigo800,
                                          ),
                                          maxLines: 1,
                                        ),
                                    ],
                                  ),
                                ),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                  decoration: pw.BoxDecoration(
                                    color: statusBgColor,
                                    borderRadius: pw.BorderRadius.circular(12),
                                    border: pw.Border.all(color: statusColor, width: 0.8),
                                  ),
                                  child: pw.Text(
                                    machine.status.label,
                                    style: pw.TextStyle(
                                      fontSize: 8.5,
                                      fontWeight: pw.FontWeight.bold,
                                      color: statusColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            pw.SizedBox(height: 5),

                            // 2. Machine Photo from Machine Registry (if available)
                            if (machinePhoto != null) ...[
                              pw.Container(
                                height: 88,
                                width: double.infinity,
                                decoration: pw.BoxDecoration(
                                  borderRadius: pw.BorderRadius.circular(6),
                                  border: pw.Border.all(color: PdfColors.grey300),
                                  color: PdfColors.grey50,
                                ),
                                child: pw.Image(machinePhoto, fit: pw.BoxFit.contain),
                              ),
                              pw.SizedBox(height: 4),
                            ],

                            // 3. Section: ข้อมูลทั่วไป (General Profile)
                            _buildSectionHeader('ข้อมูลทั่วไป (General Profile)'),
                            if (machineRow?['asset_no'] != null &&
                                (machineRow!['asset_no'] as String).trim().isNotEmpty)
                              _buildCleanRow('รหัสสินทรัพย์:', machineRow['asset_no'] as String),
                            _buildCleanRow(
                              'ยี่ห้อ / รุ่น:',
                              [
                                machineRow?['brand'] ?? machine.brand,
                                machineRow?['model'] ?? machine.model,
                              ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' / ').isNotEmpty
                                  ? [
                                      machineRow?['brand'] ?? machine.brand,
                                      machineRow?['model'] ?? machine.model,
                                    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' / ')
                                  : '-',
                            ),
                            if (machineRow?['serial_no'] != null &&
                                (machineRow!['serial_no'] as String).trim().isNotEmpty)
                              _buildCleanRow('Serial No:', machineRow['serial_no'] as String),
                            _buildCleanRow(
                              'หมวดหมู่ / แผนก:',
                              [
                                machineRow?['category_name'],
                                machineRow?['dept_name'],
                              ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' / ').isNotEmpty
                                  ? [
                                      machineRow?['category_name'],
                                      machineRow?['dept_name'],
                                    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' / ')
                                  : '-',
                            ),
                            _buildCleanRow(
                              'สถานที่ / ไลน์:',
                              (machineRow?['location'] as String?)?.trim().isNotEmpty == true
                                  ? machineRow!['location'] as String
                                  : (machine.zoneId.trim().isNotEmpty ? machine.zoneId : '-'),
                            ),

                            // 4. Section: สเปกทางเทคนิค & ผัง (Specs & Layout)
                            _buildSectionHeader('สเปก & ผังโรงงาน (Specs & Layout)'),
                            if (specRow != null &&
                                (specRow['power_kw'] != null || specRow['voltage_v'] != null))
                              _buildCleanRow(
                                'กำลังไฟฟ้า (Power):',
                                '${specRow['power_kw'] ?? '-'} kW (${specRow['voltage_v'] ?? '-'} V / ${specRow['current_a'] ?? '-'} A)',
                              ),
                            if (specRow != null &&
                                (specRow['dim_length_mm'] != null ||
                                    specRow['dim_width_mm'] != null ||
                                    specRow['dim_height_mm'] != null))
                              _buildCleanRow(
                                'ขนาดจริง (L×W×H):',
                                '${specRow['dim_length_mm'] ?? '-'} × ${specRow['dim_width_mm'] ?? '-'} × ${specRow['dim_height_mm'] ?? '-'} มม.',
                              ),
                            if (specRow != null && specRow['weight_kg'] != null)
                              _buildCleanRow('น้ำหนักเครื่อง:', '${specRow['weight_kg']} กก.'),
                            if (specRow != null && specRow['capacity'] != null)
                              _buildCleanRow('กำลังการผลิต:', '${specRow['capacity']} ${specRow['capacity_unit'] ?? ''}'),
                            _buildCleanRow(
                              'พิกัดบนผัง (X, Y):',
                              '(${machine.position.dx.toInt()}, ${machine.position.dy.toInt()})',
                            ),
                            _buildCleanRow(
                              'ขนาดบนผัง (Size):',
                              '${(machine.size.width / 50.0).toStringAsFixed(1)} ม. × ${(machine.size.height / 50.0).toStringAsFixed(1)} ม.',
                            ),
                            if (machineRow?['installation_date'] != null &&
                                (machineRow!['installation_date'] as String).trim().isNotEmpty)
                              _buildCleanRow('วันที่ติดตั้ง:', machineRow['installation_date'] as String),

                            pw.Spacer(),

                            // 5. Footer Card: QR Code + Approver
                            pw.Container(
                              padding: const pw.EdgeInsets.all(5),
                              decoration: pw.BoxDecoration(
                                color: PdfColors.blueGrey50,
                                borderRadius: pw.BorderRadius.circular(6),
                                border: pw.Border.all(color: PdfColors.blueGrey100),
                              ),
                              child: pw.Row(
                                children: [
                                  pw.BarcodeWidget(
                                    barcode: pw.Barcode.qrCode(),
                                    data: 'MASAPP://machine/${machine.machineId}',
                                    drawText: false,
                                    width: 32,
                                    height: 32,
                                    color: PdfColors.blueGrey900,
                                  ),
                                  pw.SizedBox(width: 7),
                                  pw.Expanded(
                                    child: pw.Column(
                                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                                      mainAxisAlignment: pw.MainAxisAlignment.center,
                                      children: [
                                        pw.Text(
                                          'ผู้ออกรายงาน: $userName',
                                          style: pw.TextStyle(
                                            fontSize: 7.5,
                                            fontWeight: pw.FontWeight.bold,
                                            color: PdfColors.blueGrey800,
                                          ),
                                          maxLines: 1,
                                        ),
                                        pw.Text(
                                          'สแกน QR เพื่อดูข้อมูลเครื่องจักรสดในระบบ',
                                          style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/MachineTag_${machine.machineNo}.pdf");
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(file.path);
  }

  static Future<void> generateAreaRegistryPdf({
    required List<FactoryLayout> layouts,
    required AppSettingsState settings,
    required String userName,
  }) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf')),
        bold: pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf')),
      ),
    );

    final logoBase64 = settings.get(AppSettingKeys.orgLogo);
    final companyName = settings.get(AppSettingKeys.orgName, defaultValue: 'โรงงานของเรา');
    final docRef = settings.get(AppSettingKeys.docAreaRegistryRef, defaultValue: 'F-MA-17 Rev1');

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
        margin: const pw.EdgeInsets.all(40),
        header: (context) => pw.Column(
          children: [
            pw.Row(
              children: [
                if (logoImage != null)
                  pw.Container(height: 50, child: pw.Image(logoImage)),
                pw.SizedBox(width: 15),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('ทะเบียนพื้นที่โรงงาน (Areas Registry)', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                    pw.Text(companyName, style: const pw.TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(thickness: 2),
            pw.SizedBox(height: 20),
          ],
        ),
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 20),
          child: pw.Text('$docRef | หน้า ${context.pageNumber} ของ ${context.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ),
        build: (context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FixedColumnWidth(80),
              2: const pw.FixedColumnWidth(80),
              3: const pw.FixedColumnWidth(100),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blueGrey100),
                children: [
                  _cell('ชื่อพื้นที่ (Area Name)', bold: true),
                  _cell('กว้าง (m)', bold: true),
                  _cell('ยาว (m)', bold: true),
                  _cell('สถานะ', bold: true),
                ],
              ),
              ...layouts.map((l) => pw.TableRow(
                children: [
                  _cell(l.name),
                  _cell(l.widthM.toStringAsFixed(1)),
                  _cell(l.heightM.toStringAsFixed(1)),
                  _cell(l.isApproved ? 'อนุมัติแล้ว' : 'รอการจัดผัง'),
                ],
              )),
            ],
          ),
          pw.SizedBox(height: 40),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Column(
                children: [
                  pw.Container(width: 150, decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide()))),
                  pw.SizedBox(height: 5),
                  pw.Text(userName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                  pw.Text('ผู้ออกรายงาน', style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File("${output.path}/AreasRegistry_${DateTime.now().millisecondsSinceEpoch}.pdf");
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(file.path);
  }

  static pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }

  static pw.Widget _buildSectionHeader(String title) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 4, bottom: 2.5),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
      decoration: pw.BoxDecoration(
        color: PdfColors.indigo50,
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 7.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.indigo900,
        ),
      ),
    );
  }

  static pw.Widget _buildCleanRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2.5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 65,
            child: pw.Text(
              label,
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 7.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blueGrey900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
