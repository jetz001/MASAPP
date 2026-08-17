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
    
    pw.MemoryImage? machinePhoto;
    if (imagePath != null) {
      try {
        final file = File(imagePath);
        if (await file.exists()) {
          machinePhoto = pw.MemoryImage(await file.readAsBytes());
        }
      } catch (e) {
        debugPrint('Machine photo decode error: $e');
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        build: (pw.Context context) {
          return pw.Column(
            children: [
              pw.Expanded(
                child: pw.Row(
                  children: [
                    // --- LEFT: PLAN AREA ---
                    pw.Expanded(
                      flex: 3,
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          border: pw.Border.all(color: PdfColors.grey300),
                        ),
                        child: pw.ClipRect(
                          child: pw.Stack(
                            children: [
                              pw.LayoutBuilder(builder: (context, constraints) {
                                double canvasW = layout.canvasSize.width;
                                double canvasH = layout.canvasSize.height;
                                double containerW = constraints!.maxWidth;
                                double containerH = constraints.maxHeight;
                                double gridAspect = canvasW / canvasH;
                                double containerAspect = containerW / containerH;
                                double drawW, drawH;
                                double offsetX = 0, offsetY = 0;
                                
                                if (gridAspect > containerAspect) {
                                  drawW = containerW;
                                  drawH = containerW / gridAspect;
                                  offsetY = (containerH - drawH) / 2;
                                } else {
                                  drawH = containerH;
                                  drawW = containerH * gridAspect;
                                  offsetX = (containerW - drawW) / 2;
                                }

                                final double scaleFactor = drawW / canvasW;

                                pw.Widget? alignedImage;
                                if (bgImage is pw.MemoryImage) {
                                  final double imgW = bgImage.width!.toDouble();
                                  final double imgH = bgImage.height!.toDouble();
                                  final double pdfImgX = offsetX + (layout.backgroundOffset.dx * scaleFactor);
                                  final double pdfImgY = offsetY + (layout.backgroundOffset.dy * scaleFactor);
                                  final double pdfImgW = imgW * layout.backgroundScale * scaleFactor;
                                  final double pdfImgH = imgH * layout.backgroundScale * scaleFactor;

                                  alignedImage = pw.Positioned(
                                    left: pdfImgX,
                                    top: pdfImgY,
                                    child: pw.SizedBox(
                                      width: pdfImgW,
                                      height: pdfImgH,
                                      child: pw.Image(bgImage),
                                    ),
                                  );
                                }

                                final px = offsetX + (machine.position.dx * scaleFactor);
                                final py = offsetY + (machine.position.dy * scaleFactor);

                                return pw.Stack(
                                  children: [
                                    alignedImage ?? pw.SizedBox(),
                                    pw.Positioned(
                                      left: px - 20,
                                      top: py - 60,
                                      child: pw.Container(
                                        width: 40,
                                        height: 60,
                                        child: pw.CustomPaint(
                                          painter: (canvas, size) {
                                            canvas.setFillColor(PdfColors.red);
                                            canvas.drawRect(size.x / 2 - 4, 15, 8, size.y - 15);
                                            canvas.fillPath();
                                            canvas.moveTo(0, 15);
                                            canvas.lineTo(size.x, 15);
                                            canvas.lineTo(size.x / 2, 0);
                                            canvas.closePath();
                                            canvas.fillPath();
                                          },
                                        ),
                                      ),
                                    ),
                                    pw.Positioned(
                                      left: px - 5,
                                      top: py - 5,
                                      child: pw.Container(
                                        width: 10,
                                        height: 10,
                                        decoration: const pw.BoxDecoration(
                                          color: PdfColors.red,
                                          shape: pw.BoxShape.circle,
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
                    ),

                    // --- RIGHT: DETAILS AREA ---
                    pw.Container(
                      width: 200,
                      padding: const pw.EdgeInsets.all(15),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.blueGrey50,
                        border: pw.Border(left: pw.BorderSide(color: PdfColors.blueGrey100, width: 2)),
                      ),
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          if (logoImage != null)
                            pw.Container(
                              height: 40,
                              alignment: pw.Alignment.centerLeft,
                              child: pw.Image(logoImage, fit: pw.BoxFit.contain),
                            ),
                          pw.SizedBox(height: 10),
                          pw.Text('ป้ายกำกับเครื่องจักร', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                          pw.Text(layout.name, style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey500)),
                          pw.Divider(color: PdfColors.blueGrey200),
                          pw.SizedBox(height: 15),
                          
                          if (machinePhoto != null) ...[
                            pw.Center(
                              child: pw.Container(
                                height: 90,
                                decoration: pw.BoxDecoration(
                                  border: pw.Border.all(color: PdfColors.grey300),
                                  color: PdfColors.white,
                                ),
                                child: pw.Image(machinePhoto, fit: pw.BoxFit.contain),
                              ),
                            ),
                            pw.SizedBox(height: 15),
                          ],
                          
                          _buildDetail('รหัสเครื่องจักร', machine.machineNo),
                          _buildDetail('ยี่ห้อ', machine.brand ?? '-'),
                          _buildDetail('รุ่น', machine.model ?? '-'),
                          _buildDetail('โซน', machine.zoneId.isEmpty ? '-' : machine.zoneId),
                          _buildDetail('ตำแหน่ง', '(${machine.position.dx.toInt()}, ${machine.position.dy.toInt()})'),
                          _buildDetail('สถานะ', machine.status.label),
                          
                          pw.Spacer(),
                          pw.Text(userName, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                          pw.Text('ผู้ออกรายงาน:', style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                          pw.Text(DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()), style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Container(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(docRef, style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
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

  static pw.Widget _buildDetail(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey400, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 1),
          pw.Text(value, style: pw.TextStyle(fontSize: 12, color: PdfColors.black, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}
