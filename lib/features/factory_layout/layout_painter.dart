import 'package:flutter/material.dart';
import 'layout_models.dart';

/// CustomPaint widget for rendering factory layout
class FactoryLayoutPainter extends CustomPainter {
  final FactoryLayout layout;
  final MachinePosition? selectedMachine;
  final double zoomLevel;
  final Offset panOffset;

  FactoryLayoutPainter({
    required this.layout,
    this.selectedMachine,
    this.zoomLevel = 1.0,
    this.panOffset = Offset.zero,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    // Save canvas state
    canvas.save();

    // Apply pan offset and zoom
    canvas.translate(panOffset.dx, panOffset.dy);
    canvas.scale(zoomLevel);

    // Draw background
    _drawBackground(canvas, canvasSize);

    // Draw zones
    _drawZones(canvas);

    // Draw machines
    _drawMachines(canvas);

    // Restore canvas state
    canvas.restore();
  }

  void _drawBackground(Canvas canvas, Size canvasSize) {
    final paint = Paint()
      ..color = const Color(0xFF1F2937)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, layout.canvasSize.width, layout.canvasSize.height),
      paint,
    );

    // Grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF374151)
      ..strokeWidth = 0.5;

    const gridSize = 50.0;
    for (double x = 0; x < layout.canvasSize.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, layout.canvasSize.height),
        gridPaint,
      );
    }
    for (double y = 0; y < layout.canvasSize.height; y += gridSize) {
      canvas.drawLine(
        Offset(0, y),
        Offset(layout.canvasSize.width, y),
        gridPaint,
      );
    }
  }

  void _drawZones(Canvas canvas) {
    for (final zone in layout.zones) {
      // Zone background
      final zonePaint = Paint()
        ..color = zone.color.withAlpha(60)
        ..style = PaintingStyle.fill;
      canvas.drawRect(zone.bounds, zonePaint);

      // Zone border
      final borderPaint = Paint()
        ..color = zone.color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      canvas.drawRect(zone.bounds, borderPaint);

      // Zone label
      final textPainter = TextPainter(
        text: TextSpan(
          text: zone.name,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
            fontWeight: FontWeight.w600,
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

  void _drawMachines(Canvas canvas) {
    for (final machine in layout.machines) {
      final isSelected = selectedMachine?.machineId == machine.machineId;

      // Machine shape (rounded rectangle)
      final machinePaint = Paint()
        ..color = machine.status.color
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = isSelected ? Colors.white : machine.status.color
        ..strokeWidth = isSelected ? 3 : 1.5
        ..style = PaintingStyle.stroke;

      final machineRect = machine.bounds;
      const radius = Radius.circular(4);

      canvas.drawRRect(
        RRect.fromRectAndRadius(machineRect, radius),
        machinePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(machineRect, radius),
        borderPaint,
      );

      // Machine label
      final label = machine.machineNo;
      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(
                blurRadius: 2,
                color: Colors.black.withAlpha(200),
                offset: const Offset(0.5, 0.5),
              ),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
      );
      textPainter.layout(maxWidth: machine.size.width - 4);

      final textOffset = Offset(
        machineRect.center.dx - textPainter.width / 2,
        machineRect.center.dy - textPainter.height / 2,
      );
      textPainter.paint(canvas, textOffset);

      // Status indicator (small dot)
      if (isSelected) {
        final indicatorPaint = Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill;
        canvas.drawCircle(
          Offset(machineRect.right - 4, machineRect.top - 4),
          3,
          indicatorPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(FactoryLayoutPainter oldDelegate) {
    return layout != oldDelegate.layout ||
        selectedMachine != oldDelegate.selectedMachine ||
        zoomLevel != oldDelegate.zoomLevel ||
        panOffset != oldDelegate.panOffset;
  }
}

/// Interactive layout canvas with zoom and pan
class FactoryLayoutCanvas extends StatefulWidget {
  final FactoryLayout? layout;
  final MachinePosition? selectedMachine;
  final ValueChanged<MachinePosition?>? onMachineSelected;
  final VoidCallback? onLayoutTapped;

  const FactoryLayoutCanvas({
    super.key,
    this.layout,
    this.selectedMachine,
    this.onMachineSelected,
    this.onLayoutTapped,
  });

  @override
  State<FactoryLayoutCanvas> createState() => _FactoryLayoutCanvasState();
}

class _FactoryLayoutCanvasState extends State<FactoryLayoutCanvas> {
  late double _zoomLevel;
  late Offset _panOffset;

  @override
  void initState() {
    super.initState();
    _zoomLevel = 1.0;
    _panOffset = Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.layout == null) {
      return const Center(child: Text('Layout not available'));
    }

    return GestureDetector(
      onScaleUpdate: (details) {
        setState(() {
          // Zoom with pinch
          _zoomLevel = (_zoomLevel * details.scale).clamp(0.5, 3.0);
          // Pan with drag
          _panOffset += details.focalPointDelta;
        });
      },
      onTapUp: (details) {
        // Convert screen coordinates to layout coordinates
        final localPosition = details.localPosition;
        final layoutPosition = (localPosition - _panOffset) / _zoomLevel;

        final machine = widget.layout!.getMachineAt(layoutPosition);
        widget.onMachineSelected?.call(machine);
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.move,
        child: CustomPaint(
          painter: FactoryLayoutPainter(
            layout: widget.layout!,
            selectedMachine: widget.selectedMachine,
            zoomLevel: _zoomLevel,
            panOffset: _panOffset,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}
