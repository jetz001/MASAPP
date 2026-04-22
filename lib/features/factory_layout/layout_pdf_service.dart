import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'layout_models.dart';

class LayoutPdfService {
  static Future<void> generateMachineTag({
    required FactoryLayout layout,
    required MachinePosition machine,
  }) async {
    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: await PdfGoogleFonts.sarabunRegular(),
        bold: await PdfGoogleFonts.sarabunBold(),
      ),
    );

    // 1. Prepare Background Image (Handle both Image and PDF)
    pw.ImageProvider? bgImage;
    try {
      if (layout.backgroundPath != null) {
        final file = File(layout.backgroundPath!);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          
          if (layout.backgroundPath!.toLowerCase().endsWith('.pdf')) {
            // Convert PDF page to Image for embedding
            await for (final page in Printing.raster(bytes, pages: [0], dpi: 200)) {
              final pngBytes = await page.toPng();
              bgImage = pw.MemoryImage(pngBytes);
              break; // Use the first page
            }
          } else {
            // Standard Image (PNG/JPG)
            bgImage = pw.MemoryImage(bytes);
          }
        }
      }
    } catch (e) {
      // Log error and proceed without background if failed
      debugPrint('PDF Export Error (Background Image): $e');
    }

    // 2. Load Logo or Assets (optional, using default text for now)
    // final logo = await imageFromAssetBundle('assets/images/logo.png');

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (pw.Context context) {
          return pw.Row(
            children: [
              // --- LEFT: PLAN AREA (75%) ---
              pw.Expanded(
                flex: 3,
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey300),
                  ),
                  child: pw.Stack(
                    children: [
                      // Floor Plan Image
                      if (bgImage != null)
                        pw.Center(child: pw.Image(bgImage, fit: pw.BoxFit.contain)),
                      
                      // Overlay Arrow pointing to machine
                      pw.LayoutBuilder(builder: (context, constraints) {
                        // Calculate drawing Rect for the floor plan inside the container
                        // (Mimic the aspect ratio logic from the painter)
                        double canvasW = layout.canvasSize.width;
                        double canvasH = layout.canvasSize.height;
                        
                        double containerW = constraints!.maxWidth;
                        double containerH = constraints.maxHeight;
                        
                        double imgAspect = canvasW / canvasH;
                        double containerAspect = containerW / containerH;
                        
                        double drawW, drawH;
                        double offsetX = 0, offsetY = 0;
                        
                        if (imgAspect > containerAspect) {
                          drawW = containerW;
                          drawH = containerW / imgAspect;
                          offsetY = (containerH - drawH) / 2;
                        } else {
                          drawH = containerH;
                          drawW = containerH * imgAspect;
                          offsetX = (containerW - drawW) / 2;
                        }

                        // Map machine position (1600x1000) to PDF points
                        final px = offsetX + (machine.position.dx / canvasW) * drawW;
                        final py = offsetY + (machine.position.dy / canvasH) * drawH;

                        return pw.Stack(
                          children: [
                            // Arrow
                            pw.Positioned(
                              left: px - 20,
                              top: py - 60,
                              child: pw.Transform.rotate(
                                angle: 0,
                                child: pw.Column(
                                  children: [
                                    pw.Container(
                                      width: 40,
                                      height: 60,
                                      child: pw.CustomPaint(
                                        painter: (canvas, size) {
                                          canvas.setFillColor(PdfColors.red);
                                          
                                          // Draw Arrow Body
                                          canvas.drawRect(size.x / 2 - 4, 15, 8, size.y - 15);
                                          canvas.fillPath();
                                          
                                          // Draw Arrow Head
                                          canvas.moveTo(0, 15);
                                          canvas.lineTo(size.x, 15);
                                          canvas.lineTo(size.x / 2, 0);
                                          canvas.closePath();
                                          canvas.fillPath();
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            
                            // Pulse dot at target
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

              // --- RIGHT: DETAILS AREA (25%) ---
              pw.Container(
                width: 200,
                padding: const pw.EdgeInsets.all(20),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.blueGrey50,
                  border: pw.Border(left: pw.BorderSide(color: PdfColors.blueGrey100, width: 2)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('ป้ายกำกับเครื่องจักร', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
                    pw.Text(layout.name, style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey500)),
                    pw.Divider(color: PdfColors.blueGrey200),
                    pw.SizedBox(height: 20),
                    
                    _buildDetail('รหัสเครื่องจักร', machine.machineNo),
                    _buildDetail('ยี่ห้อ', machine.brand ?? '-'),
                    _buildDetail('รุ่น', machine.model ?? '-'),
                    _buildDetail('โซน', machine.zoneId.isEmpty ? '-' : machine.zoneId),
                    _buildDetail('ตำแหน่ง', '(${machine.position.dx.toInt()}, ${machine.position.dy.toInt()})'),
                    _buildDetail('สถานะ', machine.status.label),
                    
                    pw.Spacer(),
                    
                    // QR Code placeholder logic (could use qr_flutter to image if needed)
                    pw.Container(
                      height: 100,
                      width: 100,
                      decoration: const pw.BoxDecoration(color: PdfColors.white),
                      child: pw.Center(child: pw.Text('QR CODE', style: const pw.TextStyle(color: PdfColors.grey500, fontSize: 10))),
                    ),
                    pw.SizedBox(height: 10),
                    pw.Text('วันที่ออกรายงาน:', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                    pw.Text(DateTime.now().toString().substring(0, 16), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    // 3. Save and Open in browser/default viewer
    final output = await getTemporaryDirectory();
    final file = File("${output.path}/MachineTag_${machine.machineNo}.pdf");
    await file.writeAsBytes(await pdf.save());
    
    await OpenFilex.open(file.path);
  }

  static pw.Widget _buildDetail(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey400, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(value, style: pw.TextStyle(fontSize: 14, color: PdfColors.black, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }
}
