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

    // 3. Grid Lines (Fixed to layout rect)
    // Draw if exploring is set to visible, or if explicitly aligning
    if (showGrid || isAligning) {
       _drawGrid(canvas, fixedLayoutRect, isOverlay: isAligning);
    }

    // 4. Activity Zones
    _drawZones(canvas);

    // 5. Machines & Status Labels
    _drawMachines(canvas);

    if (!isAligning) {
      canvas.restore();
    }

    // 6. Alignment Overlays
    if (isAligning) {
      // Draw grid ON TOP of everything during alignment for maximum visibility
      _drawGrid(canvas, fixedLayoutRect, isOverlay: true);
      
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
    final gridPaint = Paint()
      ..color = isOverlay 
          ? Colors.blue.withAlpha(100) 
          : (themeColors['gridColor'] ?? Colors.grey).withAlpha(60)
      ..strokeWidth = isOverlay ? 1.5 : 0.5;

    const gridSize = 250.0; // 5 meters = 250 pixels (1m = 50px)
    
    // Draw minor grid (1m) if in overlay mode for better precision
    if (isOverlay) {
      final minorPaint = Paint()
        ..color = Colors.blue.withAlpha(30)
        ..strokeWidth = 0.5;
      
      const minorSize = 10.0; // 1 meter = 10 pixels
      for (double x = rect.left; x <= rect.right; x += minorSize) {
        canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), minorPaint);
      }
      for (double y = rect.top; y <= rect.bottom; y += minorSize) {
        canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), minorPaint);
      }
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
      final center = machine.position;

      // 1. Draw Dot Marker
      final dotRadius = isSelected ? 10.0 : 7.0;
      
      // Shadow/Glow for the dot
      if (isSelected) {
        final glowPaint = Paint()
          ..color = statusColor.withValues(alpha: 0.5)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        canvas.drawCircle(center, dotRadius + 4, glowPaint);
      }

      // Outer Ring
      final ringPaint = Paint()
        ..color = isSelected ? Colors.white : Colors.white.withAlpha(180)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isSelected ? 3 : 2;
      canvas.drawCircle(center, dotRadius, ringPaint);

      // Core Dot
      final dotPaint = Paint()
        ..color = statusColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, dotRadius, dotPaint);

      // 2. Draw Floating Label (Tooltip) - Only if selected
      if (isSelected) {
        final labelText = machine.machineNo;
        final textPainter = TextPainter(
          text: TextSpan(
            text: labelText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();

        final labelPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
        final labelWidth = textPainter.width + labelPadding.horizontal;
        final labelHeight = textPainter.height + labelPadding.vertical;
        
        // Position label above the dot
        final labelRect = Rect.fromCenter(
          center: center - Offset(0, dotRadius + labelHeight / 2 + 12),
          width: labelWidth,
          height: labelHeight,
        );

        // Draw bubble background
        final bubblePaint = Paint()
          ..color = Colors.black.withValues(alpha: 0.8)
          ..style = PaintingStyle.fill;
        canvas.drawRRect(
          RRect.fromRectAndRadius(labelRect, const Radius.circular(6)),
          bubblePaint,
        );

        // Draw small arrow pointing to the dot
        final path = Path();
        path.moveTo(center.dx - 6, labelRect.bottom);
        path.lineTo(center.dx + 6, labelRect.bottom);
        path.lineTo(center.dx, labelRect.bottom + 6);
        path.close();
        canvas.drawPath(path, bubblePaint);

        // Draw text
        textPainter.paint(
          canvas,
          Offset(labelRect.left + labelPadding.left, labelRect.top + labelPadding.top),
        );
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
