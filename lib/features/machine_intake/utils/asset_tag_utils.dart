import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;
import '../machine_models.dart';

class AssetTagUtils {
  /// Generate a PDF for the machine asset tag
  static Future<void> generateAndPrintTag(MachineModel machine) async {
    // Load Thai font
    final fontRegular = await PdfGoogleFonts.sarabunRegular();
    final fontBold = await PdfGoogleFonts.sarabunBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
      ),
    );

    // Generate QR code as an image
    final qrValidationResult = QrValidator.validate(
      data: 'MASAPP-MCH-${machine.machineId}',
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.L,
    );

    if (qrValidationResult.status != QrValidationStatus.valid) {
      throw Exception('Failed to generate QR code');
    }

    final qrCode = qrValidationResult.qrCode!;
    final painter = QrPainter.withQr(
      qr: qrCode,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: ui.Color(0xFF000000),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: ui.Color(0xFF000000),
      ),
      gapless: true,
    );

    // Convert painter to image bytes
    final picData = await painter.toImageData(200);
    final qrImage = pw.MemoryImage(picData!.buffer.asUint8List());

    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, 40 * PdfPageFormat.mm),
        margin: const pw.EdgeInsets.all(5 * PdfPageFormat.mm),
        build: (pw.Context context) {
          return pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              // QR Code
              pw.Container(
                width: 30 * PdfPageFormat.mm,
                height: 30 * PdfPageFormat.mm,
                child: pw.Image(qrImage),
              ),
              pw.SizedBox(width: 5 * PdfPageFormat.mm),
              // Machine Details
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text(
                      'MASAPP ป้ายรหัสเครื่องจักร',
                      style: pw.TextStyle(
                        fontSize: 8,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 1 * PdfPageFormat.mm),
                    pw.Text(
                      machine.machineNo,
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      machine.categoryName ?? 'ไม่ระบุประเภท',
                      style: const pw.TextStyle(fontSize: 8),
                    ),
                    pw.SizedBox(height: 2 * PdfPageFormat.mm),
                    pw.Text(
                      'ยี่ห้อ: ${machine.brand ?? "-"}',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                    pw.Text(
                      'รุ่น: ${machine.model ?? "-"}',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                    pw.SizedBox(height: 2 * PdfPageFormat.mm),
                    pw.Text(
                      'รหัส: ${machine.machineId?.substring(0, 13)}...',
                      style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    // Save as PDF and open
    final tempDir = await getTemporaryDirectory();
    final fileName = 'AssetTag_${machine.machineNo.replaceAll("/", "_")}.pdf';
    final file = File('${tempDir.path}/$fileName');
    
    await file.writeAsBytes(await pdf.save());
    await OpenFilex.open(file.path);
  }
}
