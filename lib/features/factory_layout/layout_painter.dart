import 'package:flutter/material.dart';
import 'layout_models.dart';

/// CustomPaint widget for rendering factory layout
class FactoryLayoutPainter extends CustomPainter {
  final FactoryLayout layout;
  final MachinePosition? selectedMachine;

  FactoryLayoutPainter({
    required this.layout,
    this.selectedMachine,
  });

  @override
  void paint(Canvas canvas, Size canvasSize) {
    // Draw background
    _drawBackground(canvas);

    // Draw zones
    _drawZones(canvas);

    // Draw machines
    _drawMachines(canvas);
  }

  void _drawBackground(Canvas canvas) {
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
    for (double x = 0; x <= layout.canvasSize.width; x += gridSize) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, layout.canvasSize.height),
        gridPaint,
      );
    }
    for (double y = 0; y <= layout.canvasSize.height; y += gridSize) {
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
            color: Colors.white.withAlpha(120),
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
        ..color = isSelected ? Colors.white : machine.status.color.withAlpha(180)
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
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                blurRadius: 3,
                color: Colors.black.withAlpha(200),
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
          ..color = Colors.white.withAlpha(100)
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
        selectedMachine != oldDelegate.selectedMachine;
  }
}

/// Interactive layout canvas with zoom and pan via InteractiveViewer
class FactoryLayoutCanvas extends StatefulWidget {
  final FactoryLayout? layout;
  final MachinePosition? selectedMachine;
  final ValueChanged<MachinePosition?>? onMachineSelected;

  const FactoryLayoutCanvas({
    super.key,
    this.layout,
    this.selectedMachine,
    this.onMachineSelected,
  });

  @override
  State<FactoryLayoutCanvas> createState() => _FactoryLayoutCanvasState();
}

class _FactoryLayoutCanvasState extends State<FactoryLayoutCanvas> {
  final TransformationController _transformationController =
      TransformationController();

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.layout == null) {
      return const Center(child: Text('Layout not available'));
    }

    final canvasSize = widget.layout!.canvasSize;

    return LayoutBuilder(builder: (context, constraints) {
      return InteractiveViewer(
        transformationController: _transformationController,
        boundaryMargin: const EdgeInsets.all(500),
        minScale: 0.1,
        maxScale: 5.0,
        child: GestureDetector(
          onTapUp: (details) {
            // Important: details.localPosition in GestureDetector child of InteractiveViewer
            // ALREADY accounts for the current transform.
            final tapPosition = details.localPosition;

            final machine = widget.layout!.getMachineAt(tapPosition);
            widget.onMachineSelected?.call(machine);
          },
          child: CustomPaint(
            size: canvasSize,
            painter: FactoryLayoutPainter(
              layout: widget.layout!,
              selectedMachine: widget.selectedMachine,
            ),
          ),
        ),
      );
    });
  }
}
