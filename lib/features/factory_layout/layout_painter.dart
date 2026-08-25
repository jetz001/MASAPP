import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'layout_models.dart';

class FactoryLayoutPainter extends CustomPainter {
  final FactoryLayout layout;
  final ui.Image? backgroundImage;
  final double zoomLevel;
  final Offset offset;
  final MachinePosition? selectedMachine;
  final bool showGrid;
  final Map<String, Color> themeColors;

  FactoryLayoutPainter({
    required this.layout,
    this.backgroundImage,
    required this.zoomLevel,
    required this.offset,
    this.selectedMachine,
    this.showGrid = true,
    required this.themeColors,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(zoomLevel);

    // 1. Base infinite canvas background
    _drawBaseBackground(canvas, canvasSize);

    // 2. Compute Auto-fit Layout Rect for Floor Plan
    final layoutRect = _computeLayoutRect();

    // 3. Draw Floor Plan Background & Document Base
    _drawPlanBackground(canvas, layoutRect);
    if (backgroundImage != null) {
      _drawFloorPlan(canvas, layoutRect);
    }

    // 4. Activity Zones (if any)
    _drawZones(canvas);

    // 5. Grid Lines (Fixed to layout bounds)
    if (showGrid) {
      _drawGrid(canvas, layoutRect);
    }

    // 6. Machine Pin Dots
    _drawMachines(canvas);

    // 7. Outer Plan Boundary Border
    final borderPaint = Paint()
      ..color = const Color(0xFF64748B).withValues(alpha: 0.5)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(layoutRect, const Radius.circular(8)),
      borderPaint,
    );

    canvas.restore();
  }

  Rect _computeLayoutRect() {
    final double canvasW = layout.canvasSize.width;
    final double canvasH = layout.canvasSize.height;

    if (backgroundImage != null) {
      final double imgW = backgroundImage!.width.toDouble();
      final double imgH = backgroundImage!.height.toDouble();
      final double imgAspect = imgW / imgH;
      final double canvasAspect = canvasW / canvasH;

      double drawW, drawH;
      double offsetX = 0, offsetY = 0;

      if (imgAspect > canvasAspect) {
        drawW = canvasW;
        drawH = canvasW / imgAspect;
        offsetY = (canvasH - drawH) / 2;
      } else {
        drawH = canvasH;
        drawW = canvasH * imgAspect;
        offsetX = (canvasW - drawW) / 2;
      }
      return Rect.fromLTWH(offsetX, offsetY, drawW, drawH);
    }

    return Rect.fromLTWH(0, 0, canvasW, canvasH);
  }

  void _drawBaseBackground(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = themeColors['backgroundColor'] ?? const Color(0xFF0F172A);
    canvas.drawRect(
      const Rect.fromLTWH(-10000, -10000, 20000, 20000),
      paint,
    );
  }

  void _drawPlanBackground(Canvas canvas, Rect rect) {
    // Document drop shadow
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.shift(const Offset(0, 8)), const Radius.circular(8)),
      shadowPaint,
    );

    // Plan base paper fill
    final basePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      basePaint,
    );
  }

  void _drawFloorPlan(Canvas canvas, Rect dst) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: layout.backgroundOpacity.clamp(0.1, 1.0))
      ..filterQuality = FilterQuality.high;

    final src = Rect.fromLTWH(
      0,
      0,
      backgroundImage!.width.toDouble(),
      backgroundImage!.height.toDouble(),
    );

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(dst, const Radius.circular(8)));
    canvas.drawImageRect(backgroundImage!, src, dst, paint);
    canvas.restore();
  }

  void _drawGrid(Canvas canvas, Rect rect) {
    const minorSize = 50.0; // 1 meter = 50px
    const gridSize = 250.0; // 5 meters = 250px

    final minorPaint = Paint()
      ..color = const Color(0xFF3B82F6).withValues(alpha: 0.15)
      ..strokeWidth = 1.0;

    final majorPaint = Paint()
      ..color = const Color(0xFF2563EB).withValues(alpha: 0.35)
      ..strokeWidth = 2.0;

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, const Radius.circular(8)));

    for (double x = rect.left; x <= rect.right; x += minorSize) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), minorPaint);
    }
    for (double y = rect.top; y <= rect.bottom; y += minorSize) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), minorPaint);
    }

    for (double x = rect.left; x <= rect.right; x += gridSize) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), majorPaint);
    }
    for (double y = rect.top; y <= rect.bottom; y += gridSize) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), majorPaint);
    }

    canvas.restore();
  }

  void _drawZones(Canvas canvas) {
    for (final zone in layout.zones) {
      final zonePaint = Paint()
        ..color = zone.color.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(zone.bounds, const Radius.circular(6)),
        zonePaint,
      );

      final borderPaint = Paint()
        ..color = zone.color.withValues(alpha: 0.6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(zone.bounds, const Radius.circular(6)),
        borderPaint,
      );

      final textPainter = TextPainter(
        text: TextSpan(
          text: zone.name,
          style: TextStyle(
            color: zone.color,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(zone.bounds.left + 8, zone.bounds.top + 8),
      );
    }
  }

  /// Draw sleek Pin Dot Markers with mini code labels
  void _drawMachines(Canvas canvas) {
    for (final machine in layout.machines) {
      final isSelected = selectedMachine?.machineId == machine.machineId;
      final statusColor = machine.status.color;
      final center = machine.position;

      // 1. Drop Shadow for Dot
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: isSelected ? 0.45 : 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, isSelected ? 8 : 4);
      canvas.drawCircle(center.translate(0, 2), isSelected ? 13 : 10, shadowPaint);

      // 2. Selection Glow Ring
      if (isSelected) {
        final ringPaint = Paint()
          ..color = const Color(0xFF2563EB).withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0;
        canvas.drawCircle(center, 16, ringPaint);
      }

      // 3. Pin Outer Border (Thick White border for maximum contrast against any drawing)
      final outerBorder = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, isSelected ? 12 : 9.5, outerBorder);

      // 4. Pin Inner Status Color Dot
      final dotPaint = Paint()
        ..color = statusColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, isSelected ? 9 : 7.5, dotPaint);

      // 5. Mini Label Tag above dot (e.g. ST-05)
      final textSpan = TextSpan(
        text: machine.machineNo,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      );
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final double tagW = textPainter.width + 10;
      const double tagH = 16.0;
      final tagRect = Rect.fromCenter(
        center: Offset(center.dx, center.dy - 14),
        width: tagW,
        height: tagH,
      );

      // Tag drop shadow
      final tagShadow = Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawRRect(
        RRect.fromRectAndRadius(tagRect.shift(const Offset(0, 1.5)), const Radius.circular(4)),
        tagShadow,
      );

      // Tag background
      final tagBgPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(tagRect, const Radius.circular(4)),
        tagBgPaint,
      );

      // Tag border
      final tagBorderPaint = Paint()
        ..color = isSelected ? const Color(0xFF2563EB) : statusColor.withValues(alpha: 0.85)
        ..strokeWidth = isSelected ? 1.8 : 1.0
        ..style = PaintingStyle.stroke;
      canvas.drawRRect(
        RRect.fromRectAndRadius(tagRect, const Radius.circular(4)),
        tagBorderPaint,
      );

      // Render Text
      textPainter.paint(
        canvas,
        Offset(tagRect.left + (tagW - textPainter.width) / 2, tagRect.top + (tagH - textPainter.height) / 2),
      );
    }
  }

  @override
  bool shouldRepaint(FactoryLayoutPainter oldDelegate) {
    return layout != oldDelegate.layout ||
        backgroundImage != oldDelegate.backgroundImage ||
        selectedMachine != oldDelegate.selectedMachine ||
        zoomLevel != oldDelegate.zoomLevel ||
        showGrid != oldDelegate.showGrid ||
        offset != oldDelegate.offset ||
        themeColors != oldDelegate.themeColors;
  }
}
