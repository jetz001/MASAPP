import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'layout_models.dart';

class FactoryLayoutPainter extends CustomPainter {
  final FactoryLayout layout;
  final ui.Image? backgroundImage;
  final double zoomLevel;
  final Offset offset;
  final MachinePosition? selectedMachine;
    final bool isAligning;
    final bool showGrid; // Toggleable grid visibility
    final double tempBgScale;
    final Offset tempBgOffset;
    final Map<String, Color> themeColors;
  
    FactoryLayoutPainter({
      required this.layout,
      this.backgroundImage,
      required this.zoomLevel,
      required this.offset,
      this.selectedMachine,
      this.isAligning = false,
      this.showGrid = true,
      this.tempBgScale = 1.0,
      this.tempBgOffset = Offset.zero,
      required this.themeColors,
    });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(zoomLevel);

    // Fixed layout bounds (e.g. 32m x 110m in pixels)
    final fixedLayoutRect = Rect.fromLTWH(0, 0, layout.canvasSize.width, layout.canvasSize.height);

    // 1. Base Layer (Background canvas)
    _drawBaseBackground(canvas, canvasSize);

    // 2. Background Image Layer (Transformed)
    // In Align mode, we allow the image to bleed outside the fixed layout rect
    final double bgScale = isAligning ? tempBgScale : layout.backgroundScale;
    final Offset bgOffset = isAligning ? tempBgOffset : layout.backgroundOffset;

    if (backgroundImage != null) {
      final imageRect = Rect.fromLTWH(
        bgOffset.dx, 
        bgOffset.dy, 
        backgroundImage!.width * bgScale, 
        backgroundImage!.height * bgScale
      );
      
      // Draw white background and image for the floor plan
      _drawPlanBackground(canvas, imageRect);
      _drawFloorPlan(canvas, imageRect);
    }

    // Clip all relative layout items to the layout bounds if not aligning
    // If aligning, we show them all over the background
    if (!isAligning) {
      canvas.save();
      canvas.clipRect(fixedLayoutRect);
    }

    // 3. Activity Zones
    _drawZones(canvas);

    // 4. Grid Lines (Fixed to layout rect) - Now drawn AFTER zones for visibility
    if (showGrid || isAligning) {
       _drawGrid(canvas, fixedLayoutRect, isOverlay: isAligning);
    }

    // 5. Machines & Status Labels
    _drawMachines(canvas);

    if (!isAligning) {
      canvas.restore();
    }

    // 6. Alignment Overlays
    if (isAligning) {
      // Draw a boundary around the fixed layout area
      final borderPaint = Paint()
        ..color = Colors.blue.withAlpha(200)
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(fixedLayoutRect, borderPaint);
    }

    canvas.restore();
  }

  void _drawBaseBackground(Canvas canvas, Size size) {
    // Fill the visible area with a neutral grey, but the actual canvas is already translated.
    // We just fill a large enough area around the layout.
    final paint = Paint()..color = themeColors['backgroundColor']?.withAlpha(100) ?? Colors.grey.withAlpha(50);
    canvas.drawRect(
      Rect.fromLTWH(-5000, -5000, 10000, 10000), 
      paint,
    );
  }

  void _drawPlanBackground(Canvas canvas, Rect rect) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, paint);
  }

  void _drawFloorPlan(Canvas canvas, Rect dst) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: layout.backgroundOpacity)
      ..filterQuality = FilterQuality.medium;

    final src = Rect.fromLTWH(
        0, 0, backgroundImage!.width.toDouble(), backgroundImage!.height.toDouble());

    canvas.drawImageRect(backgroundImage!, src, dst, paint);
  }

  void _drawGrid(Canvas canvas, Rect rect, {bool isOverlay = false}) {
    // 100% Blue as requested, with much thicker strokes
    final gridPaint = Paint()
      ..color = const Color(0xFF2196F3) // Colors.blue
      ..strokeWidth = 4.0 // Extra thick for major grid
      ..style = PaintingStyle.stroke;

    const gridSize = 250.0; // 5 meters = 250 pixels (1m = 50px)
    
    // Draw minor grid (1m)
    final minorPaint = Paint()
      ..color = const Color(0xFF2196F3).withValues(alpha: 0.5) // Slightly lighter but still very visible
      ..strokeWidth = 2.0; // Thick for minor grid
    
    const minorSize = 50.0; // 1 meter = 50 pixels
    for (double x = rect.left; x <= rect.right; x += minorSize) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), minorPaint);
    }
    for (double y = rect.top; y <= rect.bottom; y += minorSize) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), minorPaint);
    }

    // Draw major grid (5m)
    for (double x = rect.left; x <= rect.right; x += gridSize) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
    }
    for (double y = rect.top; y <= rect.bottom; y += gridSize) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }
  }

  void _drawZones(Canvas canvas) {
    for (final zone in layout.zones) {
      // Zone background
      final zonePaint = Paint()
        ..color = zone.color.withAlpha(40)
        ..style = PaintingStyle.fill;
      canvas.drawRect(zone.bounds, zonePaint);

      // Zone border
      final borderPaint = Paint()
        ..color = zone.color.withAlpha(150)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawRect(zone.bounds, borderPaint);

      // Zone label
      final textPainter = TextPainter(
        text: TextSpan(
          text: zone.name,
          style: TextStyle(
            color: (themeColors['labelColor'] ?? Colors.black).withValues(alpha: 0.5),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(zone.bounds.left + 12, zone.bounds.top + 12),
      );
    }
  }

  void _drawMachines(Canvas canvas) {
    for (final machine in layout.machines) {
      final isSelected = selectedMachine?.machineId == machine.machineId;
      final statusColor = machine.status.color;
      final rect = machine.bounds;
      final center = machine.position;

      // 1. Deep Drop Shadow (Makes it pop off any CAD/Blueprint drawing)
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.shift(const Offset(0, 4)), const Radius.circular(8)),
        shadowPaint,
      );

      // 2. Selection Glow
      if (isSelected) {
        final glowPaint = Paint()
          ..color = statusColor.withValues(alpha: 0.6)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(6), const Radius.circular(12)),
          glowPaint,
        );
      }

      // 3. Card Base Body
      final bodyPaint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        bodyPaint,
      );

      // 4. Header Bar (Vibrant Status Color - Solid & Highly Visible)
      final double headerHeight = (rect.height * 0.42).clamp(24.0, 36.0);
      final headerRect = Rect.fromLTWH(rect.left, rect.top, rect.width, headerHeight);
      final headerPaint = Paint()
        ..color = statusColor
        ..style = PaintingStyle.fill;
      
      // Top rounded corners for header
      final headerRRect = RRect.fromRectAndCorners(
        headerRect,
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
      );
      canvas.drawRRect(headerRRect, headerPaint);

      // 5. Header Content: Icon & Machine No (Bold White Text)
      final machineNoSpan = TextSpan(
        text: '⚙️ ${machine.machineNo}',
        style: TextStyle(
          color: Colors.white,
          fontSize: (headerHeight * 0.52).clamp(11.0, 15.0),
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          shadows: const [
            Shadow(color: Colors.black45, blurRadius: 2, offset: Offset(0, 1)),
          ],
        ),
      );
      final headerPainter = TextPainter(
        text: machineNoSpan,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '...',
      );
      headerPainter.layout(maxWidth: rect.width - 12);
      headerPainter.paint(
        canvas,
        Offset(rect.left + (rect.width - headerPainter.width) / 2, headerRect.top + (headerHeight - headerPainter.height) / 2),
      );

      // 6. Body Content: Dimensions & Status Label (High Contrast Dark Text)
      final double widthM = machine.size.width / 50.0;
      final double heightM = machine.size.height / 50.0;
      final dimText = '${widthM.toStringAsFixed(1)}m × ${heightM.toStringAsFixed(1)}m';

      final bodyTextSpan = TextSpan(
        children: [
          TextSpan(
            text: '$dimText\n',
            style: TextStyle(
              color: const Color(0xFF1E293B),
              fontSize: ((rect.height - headerHeight) * 0.35).clamp(9.0, 12.0),
              fontWeight: FontWeight.bold,
            ),
          ),
          TextSpan(
            text: machine.status.label,
            style: TextStyle(
              color: statusColor,
              fontSize: ((rect.height - headerHeight) * 0.32).clamp(8.5, 11.0),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
      final bodyPainter = TextPainter(
        text: bodyTextSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
      );
      bodyPainter.layout(maxWidth: rect.width - 8);

      final bodyAreaHeight = rect.height - headerHeight;
      bodyPainter.paint(
        canvas,
        Offset(
          rect.left + (rect.width - bodyPainter.width) / 2,
          rect.top + headerHeight + (bodyAreaHeight - bodyPainter.height) / 2,
        ),
      );

      // 7. High-Contrast Border
      final borderPaint = Paint()
        ..color = isSelected ? const Color(0xFF2563EB) : statusColor
        ..strokeWidth = isSelected ? 3.5 : 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(8)),
        borderPaint,
      );

      // 8. Top Pin Landmark Flag (For fast identification from afar)
      final pinCenter = Offset(rect.left + 12, rect.top - 8);
      final pinBgPaint = Paint()
        ..color = statusColor
        ..style = PaintingStyle.fill;
      final pinBorderPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      // Small Landmark Badge
      canvas.drawCircle(pinCenter, 6.0, pinBgPaint);
      canvas.drawCircle(pinCenter, 6.0, pinBorderPaint);

      // 9. Resize Corner Handles (When Selected)
      if (isSelected) {
        final handlePaint = Paint()
          ..color = const Color(0xFF2563EB)
          ..style = PaintingStyle.fill;
        final handleBorder = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;

        for (final corner in [
          rect.topLeft,
          rect.topRight,
          rect.bottomLeft,
          rect.bottomRight,
        ]) {
          canvas.drawCircle(corner, 4.5, handlePaint);
          canvas.drawCircle(corner, 4.5, handleBorder);
        }
      }
    }
  }

  @override
  bool shouldRepaint(FactoryLayoutPainter oldDelegate) {
    return layout != oldDelegate.layout ||
        backgroundImage != oldDelegate.backgroundImage ||
        selectedMachine != oldDelegate.selectedMachine ||
        zoomLevel != oldDelegate.zoomLevel ||
        showGrid != oldDelegate.showGrid ||
        isAligning != oldDelegate.isAligning ||
        offset != oldDelegate.offset ||
        themeColors != oldDelegate.themeColors;
  }
}
