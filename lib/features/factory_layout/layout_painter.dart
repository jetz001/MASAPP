import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'layout_models.dart';

class FactoryLayoutPainter extends CustomPainter {
  final FactoryLayout layout;
  final ui.Image? backgroundImage;
  final double zoomLevel;
  final Offset offset;
  final MachinePosition? selectedMachine;
  final Map<String, Color> themeColors;

  FactoryLayoutPainter({
    required this.layout,
    this.backgroundImage,
    required this.zoomLevel,
    required this.offset,
    this.selectedMachine,
    required this.themeColors,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(zoomLevel);

    // Calculate image destination rect (preserving aspect ratio)
    Rect imageRect = Rect.fromLTWH(0, 0, layout.canvasSize.width, layout.canvasSize.height);
    
    if (backgroundImage != null) {
      final double imgWidth = backgroundImage!.width.toDouble();
      final double imgHeight = backgroundImage!.height.toDouble();
      final double canvasWidth = layout.canvasSize.width;
      final double canvasHeight = layout.canvasSize.height;

      final double imgAspect = imgWidth / imgHeight;
      final double canvasAspect = canvasWidth / canvasHeight;

      double drawWidth, drawHeight;
      double offsetX = 0, offsetY = 0;

      if (imgAspect > canvasAspect) {
        drawWidth = canvasWidth;
        drawHeight = canvasWidth / imgAspect;
        offsetY = (canvasHeight - drawHeight) / 2;
      } else {
        drawHeight = canvasHeight;
        drawWidth = canvasHeight * imgAspect;
        offsetX = (canvasWidth - drawWidth) / 2;
      }
      imageRect = Rect.fromLTWH(offsetX, offsetY, drawWidth, drawHeight);
    }

    // 1. Base Layer (Grey background outside image)
    _drawBaseBackground(canvas, canvasSize);

    // Clip all subsequent drawing to the image area
    canvas.clipRect(imageRect);

    // 2. White background for the floor plan area
    _drawPlanBackground(canvas, imageRect);

    // 3. Floor Plan Image
    if (backgroundImage != null) {
      _drawFloorPlan(canvas, imageRect);
    }

    // 4. Grid Lines (Constrained to imageRect)
    _drawGrid(canvas, imageRect);

    // 5. Activity Zones
    _drawZones(canvas);

    // 6. Machines & Status Labels
    _drawMachines(canvas);

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

  void _drawGrid(Canvas canvas, Rect rect) {
    final gridPaint = Paint()
      ..color = themeColors['gridColor'] ?? Colors.grey.withAlpha(50)
      ..strokeWidth = 0.5;

    const gridSize = 50.0;
    for (double x = rect.left; x <= rect.right; x += gridSize) {
      canvas.drawLine(
        Offset(x, rect.top),
        Offset(x, rect.bottom),
        gridPaint,
      );
    }
    for (double y = rect.top; y <= rect.bottom; y += gridSize) {
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(rect.right, y),
        gridPaint,
      );
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

      // Machine shape (rounded rectangle)
      final machinePaint = Paint()
        ..color = machine.status.color
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = isSelected 
            ? (themeColors['selectedBorderColor'] ?? Colors.blue) 
            : machine.status.color.withAlpha(180)
        ..strokeWidth = isSelected ? 3 : 1.5
        ..style = PaintingStyle.stroke;

      final machineRect = machine.bounds;
      const radius = Radius.circular(6);

      // Drop shadow for machines
      if (!isSelected) {
        final shadowPaint = Paint()
          ..color = Colors.black.withAlpha(80)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawRRect(
          RRect.fromRectAndRadius(machineRect.shift(const Offset(2, 2)), radius),
          shadowPaint,
        );
      }

      canvas.drawRRect(
        RRect.fromRectAndRadius(machineRect, radius),
        machinePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(machineRect, radius),
        borderPaint,
      );

      // Machine label
      final textPainter = TextPainter(
        text: TextSpan(
          text: machine.machineNo,
          style: TextStyle(
            color: machine.status.color.computeLuminance() > 0.5
                ? Colors.black
                : Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                blurRadius: 3,
                color: Colors.black.withValues(alpha: 0.5),
                offset: const Offset(1, 1),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );
      textPainter.layout(maxWidth: machine.size.width - 4);

      final textOffset = Offset(
        machineRect.center.dx - textPainter.width / 2,
        machineRect.center.dy - textPainter.height / 2,
      );
      textPainter.paint(canvas, textOffset);

      // Status indicator (shine effect for selected)
      if (isSelected) {
        final glowPaint = Paint()
          ..color = (themeColors['selectedBorderColor'] ?? Colors.blue).withValues(alpha: 0.4)
          ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 8);
        canvas.drawRRect(
          RRect.fromRectAndRadius(machineRect, radius),
          glowPaint,
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
        offset != oldDelegate.offset ||
        themeColors != oldDelegate.themeColors;
  }
}
