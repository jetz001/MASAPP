import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'line_balancing_provider.dart';

const List<Color> kWokwiColors = [
  Color(0xFF212121), // 0: Black
  Color(0xFFE53935), // 1: Red
  Color(0xFFFB8C00), // 2: Orange
  Color(0xFFFDD835), // 3: Yellow
  Color(0xFF43A047), // 4: Green
  Color(0xFF1E88E5), // 5: Blue
  Color(0xFF8E24AA), // 6: Purple
  Color(0xFFD81B60), // 7: Magenta / Pink
  Color(0xFF00ACC1), // 8: Cyan
  Color(0xFFEEEEEE), // 9: White / Grey
];

const List<String> kWokwiColorNames = [
  'ดำ (Black)',
  'แดง (Red)',
  'ส้ม (Orange)',
  'เหลือง (Yellow)',
  'เขียว (Green)',
  'น้ำเงิน (Blue)',
  'ม่วง (Purple)',
  'ชมพู (Pink)',
  'ฟ้า (Cyan)',
  'ขาว (White)',
];

class LineGraphCanvas extends ConsumerStatefulWidget {
  const LineGraphCanvas({super.key});

  @override
  ConsumerState<LineGraphCanvas> createState() => _LineGraphCanvasState();
}

class _LineGraphCanvasState extends ConsumerState<LineGraphCanvas> {
  String? _linkingFromId;
  String? _selectedConnectionId;
  int _selectedColorIndex = 2; // Default Orange
  final TransformationController _transformController =
      TransformationController();

  static const double nodeWidth = 240;
  static const double nodeHeight = 130;
  static const double centerOffset = 2000.0;

  @override
  void initState() {
    super.initState();
    _transformController.value =
        Matrix4.translationValues(-1500.0, -1500.0, 0.0);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lineBalancingProvider);
    final notifier = ref.read(lineBalancingProvider.notifier);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final connections = state.resolvedConnections;
    final selectedConn = connections
        .where((c) => c.id == _selectedConnectionId)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Wokwi Top Color Palette & Controls Toolbar
        _buildWokwiToolbar(context, state, notifier, selectedConn, isDark),

        // 2. Interactive Canvas
        Expanded(
          child: Container(
            color: isDark ? const Color(0xFF18181B) : const Color(0xFF242426),
            child: Stack(
              children: [
                InteractiveViewer(
                  transformationController: _transformController,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(4000),
                  minScale: 0.1,
                  maxScale: 2.5,
                  child: SizedBox(
                    width: 4000,
                    height: 4000,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTapUp: (details) {
                        final localPos = details.localPosition;
                        _handleCanvasTap(localPos, connections, state.stations);
                      },
                      onDoubleTapDown: (details) {
                        final localPos = details.localPosition;
                        _handleCanvasDoubleTap(
                            localPos, connections, state.stations, notifier);
                      },
                      child: Stack(
                        children: [
                          // Background Grid
                          CustomPaint(
                            size: const Size(4000, 4000),
                            painter: _GridBackgroundPainter(isDark: isDark),
                          ),

                          // Draw Wires / Lines
                          CustomPaint(
                            size: const Size(4000, 4000),
                            painter: _WokwiWirePainter(
                              stations: state.stations,
                              connections: connections,
                              selectedConnectionId: _selectedConnectionId,
                              linkingFromId: _linkingFromId,
                              theme: theme,
                            ),
                          ),

                          // Draggable Waypoint Handles for Selected Connection (ดึงหลบสิ่งกีดขวาง)
                          if (selectedConn != null) ...[
                            ..._buildWaypointHandles(
                                selectedConn, state.stations, notifier),
                          ],

                          // Draw Workstation Nodes
                          ...state.stations.map((station) {
                            final isLinking = _linkingFromId == station.id;
                            final isLinkTarget = _linkingFromId != null &&
                                _linkingFromId != station.id;

                            return Positioned(
                              left: station.position.dx + centerOffset,
                              top: station.position.dy + centerOffset,
                              child: GestureDetector(
                                onPanUpdate: _linkingFromId == null
                                    ? (details) {
                                        // Compensate for current zoom/scale so box tracks mouse 1:1
                                        final scale = _transformController.value
                                            .getMaxScaleOnAxis();
                                        final canvasDelta = scale > 0
                                            ? (details.delta / scale)
                                            : details.delta;
                                        final newPos =
                                            station.position + canvasDelta;
                                        notifier.updateStationPosition(
                                            station.id, newPos);
                                      }
                                    : null,
                                onPanEnd: _linkingFromId == null
                                    ? (_) {
                                        notifier.saveCurrentLine();
                                      }
                                    : null,
                                onTap: () {
                                  if (_linkingFromId != null &&
                                      _linkingFromId != station.id) {
                                    notifier.linkStations(
                                      _linkingFromId!,
                                      station.id,
                                      defaultColor: kWokwiColors[
                                              _selectedColorIndex]
                                          .toARGB32(),
                                    );
                                    setState(() {
                                      _linkingFromId = null;
                                    });
                                  }
                                },
                                child: _buildStationCard(
                                  station,
                                  isLinking,
                                  isLinkTarget,
                                  state,
                                  notifier,
                                  theme,
                                ),
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),

                // Zoom & Reset controls
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'zoomIn',
                        child: const Icon(Icons.zoom_in),
                        onPressed: () {
                          final matrix = _transformController.value.clone();
                          matrix.scaleByDouble(1.2, 1.2, 1.0, 1.0);
                          _transformController.value = matrix;
                        },
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'zoomOut',
                        child: const Icon(Icons.zoom_out),
                        onPressed: () {
                          final matrix = _transformController.value.clone();
                          matrix.scaleByDouble(1 / 1.2, 1 / 1.2, 1.0, 1.0);
                          _transformController.value = matrix;
                        },
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'reset',
                        child: const Icon(Icons.home),
                        onPressed: () {
                          _transformController.value =
                              Matrix4.translationValues(-1500.0, -1500.0, 0.0);
                        },
                      ),
                    ],
                  ),
                ),

                // 4. Empty State Banner
                if (state.stations.isEmpty)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF1E1E24) : Colors.white).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_tree_outlined, size: 48, color: Colors.orange.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'ยังไม่มีสถานีงานในสายการผลิตนี้',
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'กดปุ่ม "+ เพิ่มสถานี" ด้านบน หรือให้ AI Assistant ช่วยจัดผังสายการผลิต',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
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

  // Wokwi Toolbar at Top
  Widget _buildWokwiToolbar(
    BuildContext context,
    LineBalancingState state,
    LineBalancingNotifier notifier,
    LineConnection? selectedConn,
    bool isDark,
  ) {
    String? fromName;
    String? toName;
    if (selectedConn != null) {
      fromName = state.stations
          .where((s) => s.id == selectedConn.fromStationId)
          .firstOrNull
          ?.name;
      toName = state.stations
          .where((s) => s.id == selectedConn.toStationId)
          .firstOrNull
          ?.name;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1F1F23) : const Color(0xFF2D2D30),
        border: const Border(bottom: BorderSide(color: Color(0xFF3F3F46))),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          // 0-9 Wokwi Color Swatches Palette
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < kWokwiColors.length; i++) ...[
                _buildColorSwatchButton(
                  index: i,
                  color: kWokwiColors[i],
                  selectedConn: selectedConn,
                  notifier: notifier,
                ),
                if (i < kWokwiColors.length - 1) const SizedBox(width: 4),
              ],
            ],
          ),

          // Delete wire button (Trash icon)
          if (selectedConn != null) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Colors.redAccent, size: 20),
              tooltip: 'ลบเส้นที่เลือก (Delete Wire)',
              style: IconButton.styleFrom(
                backgroundColor: Colors.red.withValues(alpha: 0.15),
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
              ),
              onPressed: () {
                notifier.removeConnection(selectedConn.id);
                setState(() => _selectedConnectionId = null);
              },
            ),

            // Toggle 90-degree Orthogonal / Bezier Curve
            IconButton(
              icon: Icon(
                selectedConn.isCurved
                    ? Icons.rounded_corner_rounded
                    : Icons.polyline_rounded,
                color: Colors.amberAccent,
                size: 20,
              ),
              tooltip: selectedConn.isCurved
                  ? 'เปลี่ยนเป็นเส้นมุมฉาก 90° (Wokwi Orthogonal)'
                  : 'เปลี่ยนเป็นเส้นโค้งมน (Smooth Curve)',
              style: IconButton.styleFrom(
                backgroundColor: Colors.amber.withValues(alpha: 0.15),
                padding: const EdgeInsets.all(6),
                minimumSize: Size.zero,
              ),
              onPressed: () {
                notifier.toggleConnectionCurved(selectedConn.id);
              },
            ),

            // Add Waypoint Button
            TextButton.icon(
              icon: const Icon(Icons.add_location_alt_rounded,
                  size: 16, color: Colors.tealAccent),
              label: const Text('เพิ่มจุดดึงหลบ',
                  style: TextStyle(fontSize: 12, color: Colors.tealAccent)),
              style: TextButton.styleFrom(
                backgroundColor: Colors.teal.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
              ),
              onPressed: () {
                _addDefaultWaypointToConnection(
                    selectedConn, state.stations, notifier);
              },
            ),

            // Reset Waypoints Button
            if (selectedConn.waypoints.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.refresh_rounded,
                    size: 14, color: Colors.grey),
                label: const Text('ล้างจุดดัด',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  minimumSize: Size.zero,
                ),
                onPressed: () {
                  notifier.updateConnectionWaypoints(selectedConn.id, []);
                },
              ),
          ],

          // Selected Info & Hint
          if (selectedConn != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Color(selectedConn.colorValue).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: Color(selectedConn.colorValue)
                        .withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Color(selectedConn.colorValue),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${fromName ?? "ต้นทาง"} ➔ ${toName ?? "ปลายทาง"} (${selectedConn.isCurved ? "เส้นโค้ง" : "มุมฉาก 90°"})',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: () => setState(() => _selectedConnectionId = null),
                    child: const Icon(Icons.close, size: 14, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ] else ...[
            Text(
              _linkingFromId != null
                  ? '⚡ กำลังโยงเส้น... คลิกกล่องปลายทาง (หรือคลิกกล่องเดิมเพื่อยกเลิก)'
                  : '💡 คลิกที่เส้นเพื่อเลือก/เปลี่ยนสี/ดึงหลบ | ดับเบิ้ลคลิกบนเส้นเพื่อเพิ่มจุดดัด',
              style: TextStyle(
                fontSize: 11.5,
                color: _linkingFromId != null
                    ? Colors.amberAccent
                    : Colors.grey.shade400,
                fontWeight: _linkingFromId != null
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
            if (_linkingFromId != null)
              TextButton(
                onPressed: () => setState(() => _linkingFromId = null),
                child: const Text('ยกเลิก',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildColorSwatchButton({
    required int index,
    required Color color,
    required LineConnection? selectedConn,
    required LineBalancingNotifier notifier,
  }) {
    final bool isSelected = selectedConn != null
        ? selectedConn.colorValue == color.toARGB32()
        : _selectedColorIndex == index;

    return InkWell(
      onTap: () {
        if (selectedConn != null) {
          notifier.updateConnectionColor(selectedConn.id, color.toARGB32());
        } else {
          setState(() => _selectedColorIndex = index);
        }
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.black54,
            width: isSelected ? 2.5 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.8),
                    blurRadius: 6,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Center(
          child: Text(
            '$index',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color.computeLuminance() > 0.5
                  ? Colors.black87
                  : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  // Draggable Waypoint Handles (จุดดึงหลบสิ่งกีดขวาง)
  List<Widget> _buildWaypointHandles(
    LineConnection conn,
    List<WorkstationData> stations,
    LineBalancingNotifier notifier,
  ) {
    final widgets = <Widget>[];

    for (int i = 0; i < conn.waypoints.length; i++) {
      final wp = conn.waypoints[i];
      final wpIndex = i;

      widgets.add(
        Positioned(
          left: wp.dx - 14,
          top: wp.dy - 14,
          child: GestureDetector(
            onPanUpdate: (details) {
              // Zoom scale compensation for smooth 1:1 mouse tracking
              final scale = _transformController.value.getMaxScaleOnAxis();
              final canvasDelta =
                  scale > 0 ? (details.delta / scale) : details.delta;
              final newPos = wp + canvasDelta;
              final updated = List<Offset>.from(conn.waypoints);
              updated[wpIndex] = newPos;
              notifier.updateConnectionWaypoints(conn.id, updated);
            },
            onDoubleTap: () {
              // Remove this waypoint on double tap
              final updated = List<Offset>.from(conn.waypoints)
                ..removeAt(wpIndex);
              notifier.updateConnectionWaypoints(conn.id, updated);
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.move,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Color(conn.colorValue),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.drag_indicator_rounded,
                      size: 14, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return widgets;
  }

  void _addDefaultWaypointToConnection(
    LineConnection conn,
    List<WorkstationData> stations,
    LineBalancingNotifier notifier,
  ) {
    final fromSt =
        stations.where((s) => s.id == conn.fromStationId).firstOrNull;
    final toSt = stations.where((s) => s.id == conn.toStationId).firstOrNull;
    if (fromSt == null || toSt == null) return;

    final start = Offset(
      fromSt.position.dx + centerOffset + nodeWidth,
      fromSt.position.dy + centerOffset + (nodeHeight / 2),
    );
    final end = Offset(
      toSt.position.dx + centerOffset,
      toSt.position.dy + centerOffset + (nodeHeight / 2),
    );

    Offset newWp;
    if (conn.waypoints.isEmpty) {
      newWp = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2 + 50);
    } else {
      final lastWp = conn.waypoints.last;
      newWp = Offset((lastWp.dx + end.dx) / 2, (lastWp.dy + end.dy) / 2 + 40);
    }

    final updated = [...conn.waypoints, newWp];
    notifier.updateConnectionWaypoints(conn.id, updated);
  }

  void _handleCanvasTap(
    Offset tapPos,
    List<LineConnection> connections,
    List<WorkstationData> stations,
  ) {
    String? hitConnId;
    double minDistance = 25.0; // Hit test threshold in pixels

    for (final conn in connections) {
      final fromSt =
          stations.where((s) => s.id == conn.fromStationId).firstOrNull;
      final toSt = stations.where((s) => s.id == conn.toStationId).firstOrNull;
      if (fromSt == null || toSt == null) continue;

      final start = Offset(
        fromSt.position.dx + centerOffset + nodeWidth,
        fromSt.position.dy + centerOffset + (nodeHeight / 2),
      );
      final end = Offset(
        toSt.position.dx + centerOffset,
        toSt.position.dy + centerOffset + (nodeHeight / 2),
      );

      final pts = [start, ...conn.waypoints, end];
      for (int i = 0; i < pts.length - 1; i++) {
        final dist = _distanceToSegment(tapPos, pts[i], pts[i + 1]);
        if (dist < minDistance) {
          minDistance = dist;
          hitConnId = conn.id;
        }
      }
    }

    setState(() {
      _selectedConnectionId = hitConnId;
    });
  }

  void _handleCanvasDoubleTap(
    Offset tapPos,
    List<LineConnection> connections,
    List<WorkstationData> stations,
    LineBalancingNotifier notifier,
  ) {
    for (final conn in connections) {
      final fromSt =
          stations.where((s) => s.id == conn.fromStationId).firstOrNull;
      final toSt = stations.where((s) => s.id == conn.toStationId).firstOrNull;
      if (fromSt == null || toSt == null) continue;

      final start = Offset(
        fromSt.position.dx + centerOffset + nodeWidth,
        fromSt.position.dy + centerOffset + (nodeHeight / 2),
      );
      final end = Offset(
        toSt.position.dx + centerOffset,
        toSt.position.dy + centerOffset + (nodeHeight / 2),
      );

      final pts = [start, ...conn.waypoints, end];
      for (int i = 0; i < pts.length - 1; i++) {
        final dist = _distanceToSegment(tapPos, pts[i], pts[i + 1]);
        if (dist < 25.0) {
          // Insert waypoint between pts[i] and pts[i+1]
          final updated = List<Offset>.from(conn.waypoints);
          updated.insert(i, tapPos);
          notifier.updateConnectionWaypoints(conn.id, updated);
          setState(() => _selectedConnectionId = conn.id);
          return;
        }
      }
    }
  }

  double _distanceToSegment(Offset p, Offset v, Offset w) {
    final l2 = (v.dx - w.dx) * (v.dx - w.dx) + (v.dy - w.dy) * (v.dy - w.dy);
    if (l2 == 0) return (p - v).distance;
    final t =
        ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2;
    final clampedT = t.clamp(0.0, 1.0);
    final projection = Offset(
        v.dx + clampedT * (w.dx - v.dx), v.dy + clampedT * (w.dy - v.dy));
    return (p - projection).distance;
  }

  Widget _buildStationCard(
    WorkstationData station,
    bool isLinking,
    bool isLinkTarget,
    LineBalancingState state,
    LineBalancingNotifier notifier,
    ThemeData theme,
  ) {
    return Material(
      elevation: isLinking ? 10 : 4,
      borderRadius: BorderRadius.circular(12),
      color: isLinkTarget
          ? theme.colorScheme.primaryContainer
          : theme.cardColor,
      child: Container(
        width: nodeWidth,
        constraints: const BoxConstraints(minHeight: nodeHeight),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isLinking
                ? theme.colorScheme.primary
                : theme.dividerColor,
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
                  onTap: () => notifier.removeStation(station.id),
                  child: const Icon(Icons.close, size: 16, color: Colors.grey),
                ),
              ],
            ),
            if (station.machineName != null &&
                station.machineName!.isNotEmpty) ...[
              Text(
                'เครื่อง: ${station.machineName}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 4),
            Text(
              'Cycle Time: ${station.cycleTime.toStringAsFixed(1)} s (${(station.cycleTime / 60).toStringAsFixed(1)} m)',
              style: const TextStyle(fontSize: 11.5),
            ),
            Text(
              'พนักงาน: ${station.workers} คน',
              style: const TextStyle(fontSize: 11.5),
            ),
            if (station.nextStationIds.isNotEmpty) ...[
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: station.nextStationIds.map((nextId) {
                  final nextSt =
                      state.stations.where((s) => s.id == nextId).firstOrNull;
                  if (nextSt == null) return const SizedBox.shrink();
                  final connId = '${station.id}->$nextId';
                  final conn = state.resolvedConnections
                      .where((c) => c.id == connId)
                      .firstOrNull;
                  final connColor =
                      conn != null ? Color(conn.colorValue) : Colors.orange;

                  return InputChip(
                    avatar: CircleAvatar(
                      backgroundColor: connColor,
                      radius: 5,
                    ),
                    label: Text(nextSt.name,
                        style: const TextStyle(fontSize: 10)),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    backgroundColor: isLinking
                        ? theme.colorScheme.primaryContainer
                        : null,
                  ),
                  onPressed: () {
                    setState(() {
                      _linkingFromId = isLinking ? null : station.id;
                    });
                  },
                  icon: Icon(isLinking ? Icons.close : Icons.link, size: 14),
                  label: Text(
                    isLinking ? 'ยกเลิก' : 'โยงเส้น',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Background Circuit Grid Painter
class _GridBackgroundPainter extends CustomPainter {
  final bool isDark;
  _GridBackgroundPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final dotPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.white.withValues(alpha: 0.15)
      ..style = PaintingStyle.fill;

    const double step = 30.0;
    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GridBackgroundPainter oldDelegate) => false;
}

// Wokwi Wire / Line Painter
class _WokwiWirePainter extends CustomPainter {
  final List<WorkstationData> stations;
  final List<LineConnection> connections;
  final String? selectedConnectionId;
  final String? linkingFromId;
  final ThemeData theme;

  _WokwiWirePainter({
    required this.stations,
    required this.connections,
    this.selectedConnectionId,
    this.linkingFromId,
    required this.theme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double nodeWidth = 240;
    const double nodeHeight = 130;
    const double centerOffset = 2000.0;

    for (final conn in connections) {
      final fromSt =
          stations.where((s) => s.id == conn.fromStationId).firstOrNull;
      final toSt = stations.where((s) => s.id == conn.toStationId).firstOrNull;
      if (fromSt == null || toSt == null) continue;

      final isSelected = conn.id == selectedConnectionId;
      final wireColor = Color(conn.colorValue);

      final startPos = Offset(
        fromSt.position.dx + centerOffset + nodeWidth,
        fromSt.position.dy + centerOffset + (nodeHeight / 2),
      );
      final endPos = Offset(
        toSt.position.dx + centerOffset,
        toSt.position.dy + centerOffset + (nodeHeight / 2),
      );

      final path =
          _buildWirePath(startPos, endPos, conn.waypoints, conn.isCurved);

      // Selected Glow Outline
      if (isSelected) {
        final glowPaint = Paint()
          ..color = Colors.white.withValues(alpha: 0.8)
          ..strokeWidth = 9
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(path, glowPaint);
      }

      // Wire Shadow/Border
      final borderPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.6)
        ..strokeWidth = 5.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, borderPaint);

      // Main Wire Core
      final wirePaint = Paint()
        ..color = wireColor
        ..strokeWidth = 3.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      canvas.drawPath(path, wirePaint);

      // Arrow Head pointing at destination
      final incomingPoint = _getIncomingPoint(startPos, endPos, conn.waypoints, conn.isCurved);
      _drawArrowHead(canvas, endPos, incomingPoint, wireColor);
    }
  }

  Offset _getIncomingPoint(
    Offset start,
    Offset end,
    List<Offset> waypoints,
    bool isCurved,
  ) {
    if (waypoints.isNotEmpty) {
      return waypoints.last;
    }
    if (isCurved) {
      final double distanceX = (end.dx - start.dx).abs();
      double cpOffset = distanceX * 0.5;
      if (cpOffset < 60.0) cpOffset = 60.0;
      final bool isBackwards = end.dx < start.dx + 50;
      final double distanceY = (end.dy - start.dy).abs();
      if (isBackwards) {
        final loopHeight = distanceY > 100 ? distanceY * 0.5 : 150.0;
        final sign = end.dy > start.dy ? 1 : -1;
        return Offset(end.dx - cpOffset, end.dy + (loopHeight * sign));
      }
      return Offset(end.dx - cpOffset, end.dy);
    } else {
      // Orthogonal Manhattan step - the last segment is purely horizontal into the node's left edge
      if (end.dx >= start.dx + 40) {
        final midX = (start.dx + end.dx) / 2;
        return Offset(midX, end.dy);
      } else {
        final backX = end.dx - 40;
        return Offset(backX, end.dy);
      }
    }
  }

  Path _buildWirePath(
    Offset start,
    Offset end,
    List<Offset> waypoints,
    bool isCurved,
  ) {
    final path = Path();
    final allPoints = [start, ...waypoints, end];

    if (allPoints.length == 2 && waypoints.isEmpty) {
      if (isCurved) {
        final double distanceX = (end.dx - start.dx).abs();
        final double distanceY = (end.dy - start.dy).abs();
        double cpOffset = distanceX * 0.5;
        if (cpOffset < 60.0) cpOffset = 60.0;
        final bool isBackwards = end.dx < start.dx + 50;

        Offset cp1, cp2;
        if (isBackwards) {
          final loopHeight = distanceY > 100 ? distanceY * 0.5 : 150.0;
          final sign = end.dy > start.dy ? 1 : -1;
          cp1 = Offset(start.dx + cpOffset, start.dy + (loopHeight * sign));
          cp2 = Offset(end.dx - cpOffset, end.dy + (loopHeight * sign));
        } else {
          cp1 = Offset(start.dx + cpOffset, start.dy);
          cp2 = Offset(end.dx - cpOffset, end.dy);
        }
        path.moveTo(start.dx, start.dy);
        path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
      } else {
        // Wokwi 90-degree Orthogonal Step Routing
        path.moveTo(start.dx, start.dy);
        if (end.dx >= start.dx + 40) {
          final midX = (start.dx + end.dx) / 2;
          path.lineTo(midX, start.dy);
          path.lineTo(midX, end.dy);
          path.lineTo(end.dx, end.dy);
        } else {
          // Loop backwards orthogonally
          final midY = (start.dy + end.dy) / 2;
          final stepX = start.dx + 40;
          final backX = end.dx - 40;
          path.lineTo(stepX, start.dy);
          path.lineTo(stepX, midY);
          path.lineTo(backX, midY);
          path.lineTo(backX, end.dy);
          path.lineTo(end.dx, end.dy);
        }
      }
    } else {
      // User has custom waypoints (ดึงหลบสิ่งกีดขวาง)
      path.moveTo(allPoints.first.dx, allPoints.first.dy);
      if (isCurved) {
        for (int i = 0; i < allPoints.length - 1; i++) {
          final p0 = allPoints[i];
          final p1 = allPoints[i + 1];
          final midX = (p0.dx + p1.dx) / 2;
          path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
        }
      } else {
        // Stepped point-to-point / orthogonal
        for (int i = 1; i < allPoints.length; i++) {
          path.lineTo(allPoints[i].dx, allPoints[i].dy);
        }
      }
    }

    return path;
  }

  void _drawArrowHead(
    Canvas canvas,
    Offset endPos,
    Offset prevPos,
    Color color,
  ) {
    const arrowLength = 14.0;
    const arrowWidth = 7.0;
    final angle = math.atan2(endPos.dy - prevPos.dy, endPos.dx - prevPos.dx);

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final arrowPath = Path();
    arrowPath.moveTo(endPos.dx, endPos.dy);
    arrowPath.lineTo(
      endPos.dx - arrowLength * math.cos(angle) + arrowWidth * math.sin(angle),
      endPos.dy - arrowLength * math.sin(angle) - arrowWidth * math.cos(angle),
    );
    arrowPath.lineTo(
      endPos.dx - (arrowLength * 0.75) * math.cos(angle),
      endPos.dy - (arrowLength * 0.75) * math.sin(angle),
    );
    arrowPath.lineTo(
      endPos.dx - arrowLength * math.cos(angle) - arrowWidth * math.sin(angle),
      endPos.dy - arrowLength * math.sin(angle) + arrowWidth * math.cos(angle),
    );
    arrowPath.close();

    canvas.drawPath(arrowPath, arrowPaint);
    canvas.drawPath(arrowPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _WokwiWirePainter oldDelegate) => true;
}
