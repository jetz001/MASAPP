import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'line_balancing_provider.dart';

class LineGraphCanvas extends ConsumerStatefulWidget {
  const LineGraphCanvas({super.key});

  @override
  ConsumerState<LineGraphCanvas> createState() => _LineGraphCanvasState();
}

class _LineGraphCanvasState extends ConsumerState<LineGraphCanvas> {
  String? _linkingFromId;
  final TransformationController _transformController = TransformationController();

  @override
  void initState() {
    super.initState();
    // Center roughly
    _transformController.value = Matrix4.identity()..translate(-1500.0, -1500.0);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lineBalancingProvider);
    final notifier = ref.read(lineBalancingProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Toolbar
        Container(
          padding: const EdgeInsets.all(8.0),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _linkingFromId == null
                      ? 'ลากกล่องจัดเรียง | โยงเส้น: กด "โยงเส้น" แล้วคลิกกล่องปลายทาง (หากเคยโยงแล้วจะเป็นการลบเส้น)'
                      : 'กำลังโยงเส้น... คลิกกล่องปลายทาง (หรือคลิกกล่องที่เคยโยงแล้วเพื่อลบเส้น)',
                  style: TextStyle(
                    fontWeight: _linkingFromId != null ? FontWeight.bold : FontWeight.normal,
                    color: _linkingFromId != null ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              ),
              if (_linkingFromId != null)
                TextButton.icon(
                  icon: const Icon(Icons.cancel),
                  label: const Text('ยกเลิกโยงเส้น'),
                  onPressed: () {
                    setState(() {
                      _linkingFromId = null;
                    });
                  },
                ),
            ],
          ),
        ),
        
        // Canvas area
        Expanded(
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Stack(
              children: [
                InteractiveViewer(
                  transformationController: _transformController,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(4000),
              minScale: 0.1,
              maxScale: 2.0,
              child: SizedBox(
                width: 4000,
                height: 4000,
                child: Stack(
                  children: [
                    // Draw lines
                    CustomPaint(
                      size: const Size(4000, 4000),
                      painter: _GraphPainter(
                        stations: state.stations,
                        linkingFromId: _linkingFromId,
                        theme: Theme.of(context),
                      ),
                    ),
                    
                    // Draw Nodes
                    ...state.stations.map((station) {
                      final isLinking = _linkingFromId == station.id;
                      final isLinkTarget = _linkingFromId != null && _linkingFromId != station.id;
                      
                      // Node size
                      const double nodeWidth = 240;
                      const double nodeHeight = 130;

                      return Positioned(
                        left: station.position.dx + 2000, // Offset to center canvas
                        top: station.position.dy + 2000,
                        child: GestureDetector(
                          onPanUpdate: _linkingFromId == null ? (details) {
                            final newPos = station.position + details.delta;
                            notifier.updateStationPosition(station.id, newPos);
                          } : null,
                          onTap: () {
                            if (_linkingFromId != null && _linkingFromId != station.id) {
                              notifier.linkStations(_linkingFromId!, station.id);
                              setState(() {
                                _linkingFromId = null;
                              });
                            }
                          },
                          child: Material(
                            elevation: isLinking ? 8 : 4,
                            borderRadius: BorderRadius.circular(12),
                            color: isLinkTarget 
                                ? Theme.of(context).colorScheme.primaryContainer 
                                : Theme.of(context).cardColor,
                            child: Container(
                              width: nodeWidth,
                              constraints: BoxConstraints(minHeight: nodeHeight),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isLinking 
                                      ? Theme.of(context).colorScheme.primary 
                                      : Theme.of(context).dividerColor,
                                  width: isLinking ? 3 : 1,
                                ),
                              ),
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          station.name,
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () {
                                          notifier.removeStation(station.id);
                                        },
                                        child: const Icon(Icons.close, size: 16, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text('Cycle Time: ${station.cycleTime.toStringAsFixed(1)} s', style: const TextStyle(fontSize: 12)),
                                  Text('พนักงาน: ${station.workers} คน', style: const TextStyle(fontSize: 12)),
                                  if (station.nextStationIds.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: station.nextStationIds.map((nextId) {
                                        final nextSt = state.stations.where((s) => s.id == nextId).firstOrNull;
                                        if (nextSt == null) return const SizedBox.shrink();
                                        return InputChip(
                                          label: Text(nextSt.name, style: const TextStyle(fontSize: 10)),
                                          padding: EdgeInsets.zero,
                                          visualDensity: VisualDensity.compact,
                                          deleteIcon: const Icon(Icons.close, size: 12),
                                          onDeleted: () {
                                            notifier.linkStations(station.id, nextId);
                                          },
                                        );
                                      }).toList(),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          backgroundColor: isLinking ? Theme.of(context).colorScheme.primaryContainer : null,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _linkingFromId = isLinking ? null : station.id;
                                          });
                                        },
                                        icon: Icon(isLinking ? Icons.close : Icons.link, size: 14),
                                        label: Text(isLinking ? 'ยกเลิก' : 'โยงเส้น', style: const TextStyle(fontSize: 12)),
                                      ),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            // Zoom controls
            Positioned(
              bottom: 16,
              right: 16,
              child: Column(
                children: [
                  FloatingActionButton.small(
                    heroTag: 'zoomIn',
                    child: const Icon(Icons.zoom_in),
                    onPressed: () {
                      final matrix = _transformController.value;
                      matrix.scale(1.2);
                      _transformController.value = matrix;
                    },
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'zoomOut',
                    child: const Icon(Icons.zoom_out),
                    onPressed: () {
                      final matrix = _transformController.value;
                      matrix.scale(1 / 1.2);
                      _transformController.value = matrix;
                    },
                  ),
                  const SizedBox(height: 8),
                  FloatingActionButton.small(
                    heroTag: 'reset',
                    child: const Icon(Icons.home),
                    onPressed: () {
                      _transformController.value = Matrix4.identity()..translate(-1500.0, -1500.0);
                    },
                  ),
                ],
              ),
            ),
          ], // Close Stack
        ),
      ),
    ),
      ],
    );
  }
}

class _GraphPainter extends CustomPainter {
  final List<WorkstationData> stations;
  final String? linkingFromId;
  final ThemeData theme;

  _GraphPainter({
    required this.stations,
    this.linkingFromId,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = theme.colorScheme.primary.withOpacity(0.6)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final arrowPaint = Paint()
      ..color = theme.colorScheme.primary.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    const double nodeWidth = 240;
    const double nodeHeight = 130;
    const double centerOffset = 2000.0;

    // Calculate connections per node to fan them out
    final Map<String, int> outCount = {};
    final Map<String, int> inCount = {};
    
    // First pass: count connections
    for (final s in stations) {
      outCount[s.id] = 0;
      for (final nextId in s.nextStationIds) {
        inCount[nextId] = (inCount[nextId] ?? 0) + 1;
      }
    }

    final Map<String, int> currentOut = {};
    final Map<String, int> currentIn = {};

    for (final station in stations) {
      for (final nextId in station.nextStationIds) {
        final nextStation = stations.where((s) => s.id == nextId).firstOrNull;
        if (nextStation != null) {
          // Spread connection points vertically
          final oIdx = currentOut[station.id] ?? 0;
          final totalOut = station.nextStationIds.length;
          final oSpread = totalOut > 1 ? (oIdx - (totalOut - 1) / 2.0) * 20 : 0.0;
          currentOut[station.id] = oIdx + 1;

          final iIdx = currentIn[nextId] ?? 0;
          final totalIn = inCount[nextId] ?? 1;
          final iSpread = totalIn > 1 ? (iIdx - (totalIn - 1) / 2.0) * 20 : 0.0;
          currentIn[nextId] = iIdx + 1;

          final startPos = Offset(
            station.position.dx + centerOffset + nodeWidth, 
            station.position.dy + centerOffset + (nodeHeight / 2) + oSpread
          );
          final endPos = Offset(
            nextStation.position.dx + centerOffset, 
            nextStation.position.dy + centerOffset + (nodeHeight / 2) + iSpread
          );

          final path = Path();
          path.moveTo(startPos.dx, startPos.dy);
          
          // Dynamic control points based on distance (makes curves sweep wider)
          final double distanceX = (endPos.dx - startPos.dx).abs();
          final double distanceY = (endPos.dy - startPos.dy).abs();
          
          // Base horizontal sweep on X distance, but if it's placed backwards, loop it
          double cpOffset = distanceX * 0.5;
          if (cpOffset < 60.0) cpOffset = 60.0; // Minimum sweep
          
          // If destination is behind source, we need to loop around
          final bool isBackwards = endPos.dx < startPos.dx + 50;
          
          Offset controlPoint1;
          Offset controlPoint2;
          
          if (isBackwards) {
            // Loop over or under based on Y relative position
            final loopHeight = distanceY > 100 ? distanceY * 0.5 : 150.0;
            final sign = endPos.dy > startPos.dy ? 1 : -1;
            controlPoint1 = Offset(startPos.dx + cpOffset, startPos.dy + (loopHeight * sign));
            controlPoint2 = Offset(endPos.dx - cpOffset, endPos.dy + (loopHeight * sign));
          } else {
            controlPoint1 = Offset(startPos.dx + cpOffset, startPos.dy);
            controlPoint2 = Offset(endPos.dx - cpOffset, endPos.dy);
          }
          
          path.cubicTo(
            controlPoint1.dx, controlPoint1.dy, 
            controlPoint2.dx, controlPoint2.dy, 
            endPos.dx, endPos.dy
          );
          
          canvas.drawPath(path, paint);

          // Draw arrow head aligned with angle of entry
          const arrowSize = 12.0;
          final arrowPath = Path();
          arrowPath.moveTo(endPos.dx, endPos.dy);
          
          // For normal curve, entry is roughly horizontal. If looping, it might come from above/below.
          // Simple horizontal arrow for now, adjusted slightly for spread
          arrowPath.lineTo(endPos.dx - arrowSize, endPos.dy - arrowSize / 1.5);
          arrowPath.lineTo(endPos.dx - arrowSize, endPos.dy + arrowSize / 1.5);
          arrowPath.close();
          canvas.drawPath(arrowPath, arrowPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GraphPainter oldDelegate) => true;
}
