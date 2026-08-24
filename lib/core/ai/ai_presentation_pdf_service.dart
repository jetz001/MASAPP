import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class AiPresentationPdfService {
  /// Generate and export a complete Slide Presentation Deck in A4 Landscape (16:9) PDF format.
  static Future<String> generatePresentationPdf({
    required String title,
    String? subtitle,
    String? author,
    String themeName = 'blue',
    required List<Map<String, dynamic>> slides,
    List<String>? sourceReferences,
  }) async {
    // 1. Load Thai Fonts
    pw.Font fontRegular;
    pw.Font fontBold;
    try {
      fontRegular = pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Regular.ttf'));
      fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/Prompt/Prompt-Bold.ttf'));
    } catch (_) {
      fontRegular = pw.Font.helvetica();
      fontBold = pw.Font.helveticaBold();
    }

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
      ),
    );

    // 2. Resolve Palette
    final colors = _resolveThemeColors(themeName);
    final formattedDate = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

    // 3. Render Each Slide as an A4 Landscape Page
    for (int slideIdx = 0; slideIdx < slides.length; slideIdx++) {
      final slide = slides[slideIdx];
      final slideType = (slide['slide_type'] ?? slide['type'])?.toString().toLowerCase().trim() ?? 'content';
      final slideTitle = slide['title']?.toString().trim() ?? 'สไลด์ที่ ${slideIdx + 1}';
      final slideSubtitle = slide['subtitle']?.toString().trim();
      final pageNum = slideIdx + 1;
      final totalPages = slides.length;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: pw.EdgeInsets.zero,
          build: (context) {
            if (slideType == 'title' || slideType == 'cover' || slideIdx == 0) {
              return _buildCoverSlide(
                title: slideTitle.isNotEmpty ? slideTitle : title,
                subtitle: slideSubtitle ?? subtitle ?? 'รายงานผลการดำเนินงานและวิเคราะห์ทางวิศวกรรม',
                author: author ?? 'ฝ่ายซ่อมบำรุงและวิศวกรรม (AI Synthesis)',
                date: formattedDate,
                colors: colors,
                sources: sourceReferences,
              );
            }

            return _buildStandardSlide(
              slideType: slideType,
              title: slideTitle,
              subtitle: slideSubtitle,
              slideData: slide,
              pageNum: pageNum,
              totalPages: totalPages,
              deckTitle: title,
              colors: colors,
            );
          },
        ),
      );
    }

    // 4. Save PDF to Output / Documents Directory
    final outputDir = await _getExportDirectory();
    final sanitizedTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_').trim();
    final fileName = 'Slide_${sanitizedTitle}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';
    final targetFile = File(p.join(outputDir.path, fileName));
    final pdfBytes = await pdf.save();
    await targetFile.writeAsBytes(pdfBytes);

    return targetFile.path;
  }

  /// Resolve color scheme palette based on theme name
  static _PresentationColors _resolveThemeColors(String themeName) {
    switch (themeName.toLowerCase().trim()) {
      case 'teal':
      case 'green':
      case 'lean':
        return _PresentationColors(
          primary: PdfColor.fromHex('#00796B'),
          primaryLight: PdfColor.fromHex('#E0F2F1'),
          accent: PdfColor.fromHex('#4CAF50'),
          darkBg: PdfColor.fromHex('#004D40'),
          surface: PdfColor.fromHex('#F5FBFA'),
          border: PdfColor.fromHex('#B2DFDB'),
        );
      case 'purple':
      case 'enterprise':
        return _PresentationColors(
          primary: PdfColor.fromHex('#5E35B1'),
          primaryLight: PdfColor.fromHex('#EDE7F6'),
          accent: PdfColor.fromHex('#9C27B0'),
          darkBg: PdfColor.fromHex('#311B92'),
          surface: PdfColor.fromHex('#F9F8FD'),
          border: PdfColor.fromHex('#D1C4E9'),
        );
      case 'orange':
      case 'urgent':
      case 'rca':
        return _PresentationColors(
          primary: PdfColor.fromHex('#D84315'),
          primaryLight: PdfColor.fromHex('#FBE9E7'),
          accent: PdfColor.fromHex('#FF8F00'),
          darkBg: PdfColor.fromHex('#BF360C'),
          surface: PdfColor.fromHex('#FFF8F6'),
          border: PdfColor.fromHex('#FFCCBC'),
        );
      case 'blue':
      default:
        return _PresentationColors(
          primary: PdfColor.fromHex('#1565C0'),
          primaryLight: PdfColor.fromHex('#E3F2FD'),
          accent: PdfColor.fromHex('#0288D1'),
          darkBg: PdfColor.fromHex('#0D47A1'),
          surface: PdfColor.fromHex('#F8FBFF'),
          border: PdfColor.fromHex('#BBDEFB'),
        );
    }
  }

  /// Cover / Title Slide
  static pw.Widget _buildCoverSlide({
    required String title,
    required String subtitle,
    required String author,
    required String date,
    required _PresentationColors colors,
    List<String>? sources,
  }) {
    return pw.Container(
      width: double.infinity,
      height: double.infinity,
      color: colors.darkBg,
      child: pw.Stack(
        children: [
          // Background Accent Shape
          pw.Positioned(
            right: -60,
            bottom: -60,
            child: pw.Container(
              width: 320,
              height: 320,
              decoration: pw.BoxDecoration(
                shape: pw.BoxShape.circle,
                color: colors.primary.flatten(background: colors.darkBg),
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(48),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                // Header Tag
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: const pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
                      ),
                      child: pw.Text(
                        'MASAPP · EXECUTIVE PRESENTATION STUDIO',
                        style: pw.TextStyle(
                          color: colors.primary,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Text(
                      date,
                      style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
                    ),
                  ],
                ),

                // Main Title Box
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      title,
                      style: pw.TextStyle(
                        color: PdfColors.white,
                        fontSize: 26,
                        fontWeight: pw.FontWeight.bold,
                        lineSpacing: 1.3,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Text(
                      subtitle,
                      style: const pw.TextStyle(
                        color: PdfColors.blueGrey100,
                        fontSize: 14,
                      ),
                    ),
                    pw.SizedBox(height: 20),
                    pw.Container(
                      width: 80,
                      height: 4,
                      decoration: pw.BoxDecoration(
                        color: colors.accent,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                      ),
                    ),
                  ],
                ),

                // Footer Metadata & Grounded Sources
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'ผู้จัดทำ / จัดเตรียม:',
                          style: const pw.TextStyle(color: PdfColors.blueGrey200, fontSize: 9),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          author,
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (sources != null && sources.isNotEmpty)
                      pw.Container(
                        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: pw.BoxDecoration(
                          color: const PdfColor(1, 1, 1, 0.15),
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                        ),
                        child: pw.Text(
                          '📚 สังเคราะห์จากข้อมูล ${sources.length} แหล่ง (Work Orders, OEE, RCA, PM)',
                          style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Standard Slide Layout
  static pw.Widget _buildStandardSlide({
    required String slideType,
    required String title,
    String? subtitle,
    required Map<String, dynamic> slideData,
    required int pageNum,
    required int totalPages,
    required String deckTitle,
    required _PresentationColors colors,
  }) {
    return pw.Container(
      width: double.infinity,
      height: double.infinity,
      color: colors.surface,
      child: pw.Column(
        children: [
          // 1. Slide Header Banner
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 14),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border(bottom: pw.BorderSide(color: colors.border, width: 1)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          pw.Container(
                            width: 6,
                            height: 16,
                            decoration: pw.BoxDecoration(
                              color: colors.primary,
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Text(
                            title,
                            style: pw.TextStyle(
                              fontSize: 16,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blueGrey900,
                            ),
                          ),
                        ],
                      ),
                      if (subtitle != null && subtitle.isNotEmpty) ...[
                        pw.SizedBox(height: 2),
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(left: 14),
                          child: pw.Text(
                            subtitle,
                            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: pw.BoxDecoration(
                    color: colors.primaryLight,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    _formatTypeBadge(slideType),
                    style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: colors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. Slide Content Body
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(32, 16, 32, 12),
              child: _buildSlideContentByType(slideType, slideData, colors),
            ),
          ),

          // 3. Slide Footer
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 32, vertical: 8),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              border: pw.Border(top: pw.BorderSide(color: colors.border, width: 0.8)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'MASAPP Factory Maintenance Studio · $deckTitle',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                ),
                pw.Text(
                  'หน้า $pageNum / $totalPages',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: colors.primary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTypeBadge(String type) {
    switch (type) {
      case 'kpi':
        return '📊 KPI & METRICS';
      case 'fishbone':
        return '🐟 FISHBONE 4M1E';
      case 'rca_5why':
      case '5why':
        return '🔍 5-WHY ROOT CAUSE';
      case 'eight_d':
      case '8d':
        return '📋 8D PROBLEM SOLVING';
      case 'chart':
        return '📈 STATISTICAL CHART';
      case 'table':
        return '📑 DATA TABLE';
      case 'summary':
        return '🎯 SUMMARY & ACTIONS';
      default:
        return '📝 BRIEFING';
    }
  }

  /// Dispatch content rendering based on slide type
  static pw.Widget _buildSlideContentByType(
    String type,
    Map<String, dynamic> data,
    _PresentationColors colors,
  ) {
    switch (type) {
      case 'kpi':
        return _buildKpiSlideContent(data, colors);
      case 'fishbone':
        return _buildFishboneSlideContent(data, colors);
      case 'rca_5why':
      case '5why':
        return _build5WhySlideContent(data, colors);
      case 'eight_d':
      case '8d':
        return _build8DSlideContent(data, colors);
      case 'table':
        return _buildTableSlideContent(data, colors);
      case 'chart':
        return _buildChartSummarySlideContent(data, colors);
      case 'summary':
        return _buildSummarySlideContent(data, colors);
      default:
        return _buildGeneralContentSlide(data, colors);
    }
  }

  /// 1. KPI Metric Grid Slide
  static pw.Widget _buildKpiSlideContent(Map<String, dynamic> data, _PresentationColors colors) {
    final rawMetrics = data['metrics'] ?? data['kpis'] ?? [];
    final description = data['content']?.toString().trim();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (description != null && description.isNotEmpty) ...[
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              border: pw.Border.all(color: colors.border),
            ),
            child: pw.Text(
              description,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey800),
            ),
          ),
          pw.SizedBox(height: 12),
        ],
        pw.Expanded(
          child: pw.GridView(
            crossAxisCount: 3,
            childAspectRatio: 1.7,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            children: (rawMetrics is List ? rawMetrics : []).map<pw.Widget>((m) {
              if (m is! Map) return pw.SizedBox.shrink();
              final label = m['label']?.toString() ?? 'ตัวชี้วัด';
              final val = m['value']?.toString() ?? '-';
              final target = m['target']?.toString();
              final status = (m['status']?.toString() ?? 'good').toLowerCase();
              final change = m['change']?.toString();

              PdfColor cardAccent = colors.primary;
              if (status == 'good' || status == 'pass') cardAccent = PdfColors.green700;
              if (status == 'warning') cardAccent = PdfColors.orange700;
              if (status == 'critical' || status == 'fail') cardAccent = PdfColors.red700;

              return pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                  border: pw.Border.all(color: colors.border),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      label,
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                      maxLines: 1,
                    ),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          val,
                          style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: cardAccent,
                          ),
                        ),
                        if (change != null)
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: cardAccent.flatten(background: PdfColors.white),
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                            ),
                            child: pw.Text(
                              change,
                              style: pw.TextStyle(fontSize: 8, color: cardAccent, fontWeight: pw.FontWeight.bold),
                            ),
                          ),
                      ],
                    ),
                    if (target != null)
                      pw.Text(
                        'เป้าหมาย: $target',
                        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// 2. Fishbone 4M1E Diagram Slide
  static pw.Widget _buildFishboneSlideContent(Map<String, dynamic> data, _PresentationColors colors) {
    final rawFb = data['fishbone_data'] ?? data;
    final problem = (rawFb['problem'] ?? data['problem'] ?? 'ปัญหาหลักที่เกิดขึ้น')?.toString() ?? '';
    final man = _parseStringList(rawFb['man']);
    final machine = _parseStringList(rawFb['machine']);
    final method = _parseStringList(rawFb['method']);
    final material = _parseStringList(rawFb['material']);
    final environment = _parseStringList(rawFb['environment'] ?? rawFb['env']);

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Left: 4M1E 2-Row Category Cards
        pw.Expanded(
          flex: 7,
          child: pw.Column(
            children: [
              // Top Row: Man, Machine, Method
              pw.Expanded(
                child: pw.Row(
                  children: [
                    pw.Expanded(child: _buildFishboneBranch('👨 Man (คน/ทักษะ)', man, colors)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: _buildFishboneBranch('⚙️ Machine (เครื่องจักร)', machine, colors)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: _buildFishboneBranch('📋 Method (ขั้นตอน/วิธี)', method, colors)),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              // Bottom Row: Material, Environment
              pw.Expanded(
                child: pw.Row(
                  children: [
                    pw.Expanded(child: _buildFishboneBranch('📦 Material (วัตถุดิบ/อะไหล่)', material, colors)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(child: _buildFishboneBranch('🌡️ Environment (สิ่งแวดล้อม)', environment, colors)),
                    pw.SizedBox(width: 8),
                    pw.Expanded(
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(10),
                        decoration: pw.BoxDecoration(
                          color: colors.primaryLight,
                          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                          border: pw.Border.all(color: colors.border),
                        ),
                        child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          mainAxisAlignment: pw.MainAxisAlignment.center,
                          children: [
                            pw.Text(
                              '💡 มาตรการสกัดกั้น:',
                              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: colors.primary),
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              'วิเคราะห์ปัจจัยรอบด้านเพื่อระบุ Root Cause และป้องกันการเกิดซ้ำ (ECRS)',
                              style: const pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey800),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        // Right: Problem Arrow Box
        pw.Expanded(
          flex: 3,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: colors.primary,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: const pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(
                    '⚠️ หัวข้อปัญหา (PROBLEM EFFECT)',
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: colors.primary),
                  ),
                ),
                pw.SizedBox(height: 10),
                pw.Text(
                  problem,
                  style: pw.TextStyle(
                    color: PdfColors.white,
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    lineSpacing: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildFishboneBranch(String title, List<String> items, _PresentationColors colors) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: colors.border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: colors.primary),
          ),
          pw.SizedBox(height: 4),
          pw.Expanded(
            child: items.isEmpty
                ? pw.Text('- ไม่มีประเด็นตรวจพบ', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500))
                : pw.ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (ctx, idx) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('• ', style: pw.TextStyle(fontSize: 8, color: colors.accent)),
                          pw.Expanded(
                            child: pw.Text(
                              items[idx],
                              style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.blueGrey900),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 3. 5-Why Root Cause Drill-down Slide
  static pw.Widget _build5WhySlideContent(Map<String, dynamic> data, _PresentationColors colors) {
    final raw5W = data['five_why_data'] ?? data;
    final problem = raw5W['problem']?.toString() ?? 'ปัญหาที่ระบุ';
    final whys = _parseStringList(raw5W['whys'] ?? [
      raw5W['why_1'],
      raw5W['why_2'],
      raw5W['why_3'],
      raw5W['why_4'],
      raw5W['why_5'],
    ]);
    final rootCause = raw5W['root_cause']?.toString() ?? (whys.isNotEmpty ? whys.last : 'ยังไม่ระบุสาเหตุที่แท้จริง');
    final action = raw5W['countermeasure'] ?? raw5W['preventive_action']?.toString();

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Left 5-Why Flow Steps
        pw.Expanded(
          flex: 6,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              // Problem bar
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.grey200,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Text(
                  '🚨 ปัญหาเริ่มต้น: $problem',
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Expanded(
                child: pw.ListView.builder(
                  itemCount: whys.length,
                  itemBuilder: (ctx, idx) {
                    final isLast = idx == whys.length - 1;
                    return pw.Container(
                      margin: const pw.EdgeInsets.only(bottom: 5),
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: isLast ? colors.primaryLight : PdfColors.white,
                        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                        border: pw.Border.all(color: isLast ? colors.primary : colors.border),
                      ),
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: isLast ? colors.primary : colors.accent,
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                            ),
                            child: pw.Text(
                              'Why #${idx + 1}',
                              style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                            ),
                          ),
                          pw.SizedBox(width: 8),
                          pw.Expanded(
                            child: pw.Text(
                              whys[idx],
                              style: pw.TextStyle(
                                fontSize: 8.5,
                                fontWeight: isLast ? pw.FontWeight.bold : pw.FontWeight.normal,
                                color: isLast ? colors.primary : PdfColors.blueGrey900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 12),
        // Right: Root Cause & Countermeasure box
        pw.Expanded(
          flex: 4,
          child: pw.Column(
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                    border: pw.Border.all(color: colors.primary, width: 1.5),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: pw.BoxDecoration(
                              color: colors.primary,
                              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                            ),
                            child: pw.Text('🎯 ROOT CAUSE', style: pw.TextStyle(fontSize: 8, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        rootCause,
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
                      ),
                      if (action != null && action.toString().isNotEmpty) ...[
                        pw.Divider(color: colors.border, thickness: 0.8),
                        pw.Text('🛡️ มาตรการป้องกันถาวร (Action Plan):', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: colors.primary)),
                        pw.SizedBox(height: 4),
                        pw.Text(action.toString(), style: const pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey800)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 4. 8D Problem Solving Methodology Slide
  static pw.Widget _build8DSlideContent(Map<String, dynamic> data, _PresentationColors colors) {
    final raw8D = data['eight_d_data'] ?? data['steps'] ?? [];
    final List<Map<String, dynamic>> steps = [];
    if (raw8D is List) {
      for (final item in raw8D) {
        if (item is Map) steps.add(item.cast<String, dynamic>());
      }
    }

    if (steps.isEmpty) {
      return pw.Center(child: pw.Text('ไม่มีข้อมูล 8D Report สำหรับสไลด์นี้'));
    }

    return pw.Table(
      border: pw.TableBorder.all(color: colors.border, width: 0.8),
      columnWidths: const {
        0: pw.FixedColumnWidth(45),
        1: pw.FixedColumnWidth(110),
        2: pw.FlexColumnWidth(3),
        3: pw.FixedColumnWidth(80),
        4: pw.FixedColumnWidth(60),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: pw.BoxDecoration(color: colors.primaryLight),
          children: [
            _tableHeader('ขั้นตอน'),
            _tableHeader('หัวข้อ'),
            _tableHeader('การดำเนินการ / รายละเอียด'),
            _tableHeader('ผู้รับผิดชอบ'),
            _tableHeader('สถานะ'),
          ],
        ),
        // Rows
        ...steps.map((st) {
          final code = st['step']?.toString() ?? 'D';
          final title = st['title']?.toString() ?? '';
          final desc = st['description']?.toString() ?? st['detail']?.toString() ?? '-';
          final owner = st['owner']?.toString() ?? st['responsible']?.toString() ?? '-';
          final status = st['status']?.toString() ?? 'Completed';

          return pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.white),
            children: [
              _tableCell(code, isBold: true, align: pw.TextAlign.center),
              _tableCell(title, isBold: true),
              _tableCell(desc),
              _tableCell(owner, align: pw.TextAlign.center),
              _tableCell(status, align: pw.TextAlign.center),
            ],
          );
        }),
      ],
    );
  }

  static pw.Widget _tableHeader(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  static pw.Widget _tableCell(String text, {bool isBold = false, pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 7.5, fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal),
        textAlign: align,
      ),
    );
  }

  /// 5. Table Slide Content
  static pw.Widget _buildTableSlideContent(Map<String, dynamic> data, _PresentationColors colors) {
    final rawTable = data['table_data'] ?? data;
    final headers = _parseStringList(rawTable['headers'] ?? ['ลำดับ', 'รายการ', 'ค่า', 'หน่วย']);
    final rawRows = rawTable['rows'] ?? [];

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border.all(color: colors.border),
      ),
      child: pw.Table(
        border: pw.TableBorder.all(color: colors.border, width: 0.5),
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: colors.primaryLight),
            children: headers.map((h) => _tableHeader(h)).toList(),
          ),
          if (rawRows is List)
            ...rawRows.map((row) {
              final List<String> cells = row is List ? row.map((e) => e.toString()).toList() : [];
              return pw.TableRow(
                children: cells.map((c) => _tableCell(c)).toList(),
              );
            }),
        ],
      ),
    );
  }

  /// 6. Chart Summary Slide
  static pw.Widget _buildChartSummarySlideContent(Map<String, dynamic> data, _PresentationColors colors) {
    final chart = data['chart_data'] ?? data;
    final items = chart['data'] ?? [];
    final unit = chart['unit']?.toString() ?? '';
    final notes = data['content']?.toString() ?? '';

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Left: Data Bars
        pw.Expanded(
          flex: 6,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              border: pw.Border.all(color: colors.border),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('📊 สรุปข้อมูลเชิงปริมาณ:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colors.primary)),
                pw.SizedBox(height: 8),
                pw.Expanded(
                  child: items is List
                      ? pw.ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (ctx, idx) {
                            final it = items[idx];
                            if (it is! Map) return pw.SizedBox.shrink();
                            final lbl = it['label']?.toString() ?? '';
                            final val = (it['value'] as num?)?.toDouble() ?? 0.0;
                            return pw.Padding(
                              padding: const pw.EdgeInsets.only(bottom: 6),
                              child: pw.Column(
                                crossAxisAlignment: pw.CrossAxisAlignment.start,
                                children: [
                                  pw.Row(
                                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                    children: [
                                      pw.Text(lbl, style: const pw.TextStyle(fontSize: 8.5)),
                                      pw.Text('$val $unit', style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
                                    ],
                                  ),
                                  pw.SizedBox(height: 2),
                                  pw.Container(
                                    height: 5,
                                    decoration: pw.BoxDecoration(
                                      color: colors.primaryLight,
                                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                                    ),
                                    child: pw.Row(
                                      children: [
                                        pw.Container(
                                          width: (val * 4).clamp(10.0, 200.0),
                                          decoration: pw.BoxDecoration(
                                            color: colors.primary,
                                            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        )
                      : pw.SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 12),
        // Right: Takeaway Notes
        pw.Expanded(
          flex: 4,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              border: pw.Border.all(color: colors.border),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('💡 ข้อสังเกตและข้อเสนอแนะ:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: colors.accent)),
                pw.SizedBox(height: 8),
                pw.Text(
                  notes.isNotEmpty ? notes : 'วิเคราะห์ข้อมูลพบว่าอัตราการทำงานอยู่ในเกณฑ์มาตรฐาน ควรติดตามการบำรุงรักษาเชิงป้องกันอย่างต่อเนื่อง',
                  style: const pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey800, lineSpacing: 1.4),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 7. Summary & Action Items Slide
  static pw.Widget _buildSummarySlideContent(Map<String, dynamic> data, _PresentationColors colors) {
    final actions = _parseStringList(data['action_items'] ?? data['actions'] ?? data['items'] ?? []);
    final conclusion = data['content']?.toString() ?? 'สรุปภาพรวมผลการดำเนินงาน';

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Expanded(
          flex: 5,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              border: pw.Border.all(color: colors.border),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('📌 สรุปภาพรวม (Executive Summary):', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: colors.primary)),
                pw.SizedBox(height: 8),
                pw.Text(conclusion, style: const pw.TextStyle(fontSize: 9.5, color: PdfColors.blueGrey900, lineSpacing: 1.4)),
              ],
            ),
          ),
        ),
        pw.SizedBox(width: 12),
        pw.Expanded(
          flex: 5,
          child: pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: colors.primaryLight,
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
              border: pw.Border.all(color: colors.border),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('🎯 แผนงานขั้นตอนถัดไป (Next Actions):', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: colors.primary)),
                pw.SizedBox(height: 8),
                pw.Expanded(
                  child: actions.isEmpty
                      ? pw.Text('- กำกับดูแลงานซ่อมและติดตามผลการดำเนินงานตามแผนแม่บท PM/AM ประจำเดือน', style: const pw.TextStyle(fontSize: 9))
                      : pw.ListView.builder(
                          itemCount: actions.length,
                          itemBuilder: (ctx, idx) => pw.Padding(
                            padding: const pw.EdgeInsets.only(bottom: 6),
                            child: pw.Row(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: [
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: pw.BoxDecoration(
                                    color: colors.primary,
                                    shape: pw.BoxShape.circle,
                                  ),
                                  child: pw.Text('${idx + 1}', style: pw.TextStyle(fontSize: 7, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
                                ),
                                pw.SizedBox(width: 8),
                                pw.Expanded(child: pw.Text(actions[idx], style: const pw.TextStyle(fontSize: 8.5, color: PdfColors.blueGrey900))),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 8. General Content Slide
  static pw.Widget _buildGeneralContentSlide(Map<String, dynamic> data, _PresentationColors colors) {
    final text = data['content']?.toString() ?? '';
    final bullets = _parseStringList(data['bullets'] ?? data['points']);

    return pw.Container(
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: colors.border),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          if (text.isNotEmpty) ...[
            pw.Text(text, style: const pw.TextStyle(fontSize: 10, color: PdfColors.blueGrey900, lineSpacing: 1.4)),
            pw.SizedBox(height: 10),
          ],
          if (bullets.isNotEmpty)
            pw.Expanded(
              child: pw.ListView.builder(
                itemCount: bullets.length,
                itemBuilder: (ctx, idx) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('✔ ', style: pw.TextStyle(fontSize: 9, color: colors.accent, fontWeight: pw.FontWeight.bold)),
                      pw.Expanded(
                        child: pw.Text(bullets[idx], style: const pw.TextStyle(fontSize: 9, color: PdfColors.blueGrey900)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw == null) return [];
    if (raw is List) {
      return raw.map((e) => e?.toString().trim() ?? '').where((e) => e.isNotEmpty).toList();
    }
    return [raw.toString().trim()];
  }

  static Future<Directory> _getExportDirectory() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final masappDir = Directory(p.join(appDocDir.path, 'MASAPP_Presentations'));
      if (!await masappDir.exists()) {
        await masappDir.create(recursive: true);
      }
      return masappDir;
    } catch (_) {
      return Directory.current;
    }
  }

  /// Open PDF using system viewer
  static Future<void> openPdf(String filePath) async {
    try {
      await OpenFilex.open(filePath);
    } catch (e) {
      debugPrint('Open PDF error: $e');
    }
  }

  /// Print PDF
  static Future<void> printPdf(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        await Printing.layoutPdf(onLayout: (_) => bytes);
      }
    } catch (e) {
      debugPrint('Print PDF error: $e');
    }
  }
}

class _PresentationColors {
  final PdfColor primary;
  final PdfColor primaryLight;
  final PdfColor accent;
  final PdfColor darkBg;
  final PdfColor surface;
  final PdfColor border;

  const _PresentationColors({
    required this.primary,
    required this.primaryLight,
    required this.accent,
    required this.darkBg,
    required this.surface,
    required this.border,
  });
}
