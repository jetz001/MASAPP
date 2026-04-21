import 'package:flutter/material.dart';

/// Models for factory layout visualization

/// Represents a zone (area) in the factory
class LayoutZone {
  final String zoneId;
  final String layoutId;
  final String name;
  final String type;
  final Rect bounds; // Position and size of the zone
  final Color color;

  const LayoutZone({
    required this.zoneId,
    required this.layoutId,
    required this.name,
    this.type = 'general',
    required this.bounds,
    this.color = Colors.green,
  });

  LayoutZone copyWith({
    String? zoneId,
    String? layoutId,
    String? name,
    String? type,
    Rect? bounds,
    Color? color,
  }) {
    return LayoutZone(
      zoneId: zoneId ?? this.zoneId,
      layoutId: layoutId ?? this.layoutId,
      name: name ?? this.name,
      type: type ?? this.type,
      bounds: bounds ?? this.bounds,
      color: color ?? this.color,
    );
  }
}

/// Represents a machine position on the factory layout
class MachinePosition {
  final String positionId;
  final String layoutId;
  final String machineId;
  final String machineNo;
  final String? brand;
  final String? model;
  final Offset position; // Center position in layout coordinates
  final Size size; // Width and height of machine representation
  final String zoneId; // Which zone it belongs to
  final MachineLayoutStatus status; // Visual status
  final DateTime? lastUpdated;

  const MachinePosition({
    required this.positionId,
    required this.layoutId,
    required this.machineId,
    required this.machineNo,
    this.brand,
    this.model,
    required this.position,
    this.size = const Size(60, 50),
    required this.zoneId,
    this.status = MachineLayoutStatus.normal,
    this.lastUpdated,
  });

  /// Get the bounding rectangle for this machine
  Rect get bounds => Rect.fromLTWH(
    position.dx - size.width / 2,
    position.dy - size.height / 2,
    size.width,
    size.height,
  );

  /// Check if point is within machine bounds
  bool contains(Offset point) {
    return bounds.contains(point);
  }

  MachinePosition copyWith({
    String? positionId,
    String? layoutId,
    String? machineId,
    String? machineNo,
    String? brand,
    String? model,
    Offset? position,
    Size? size,
    String? zoneId,
    MachineLayoutStatus? status,
    DateTime? lastUpdated,
  }) {
    return MachinePosition(
      positionId: positionId ?? this.positionId,
      layoutId: layoutId ?? this.layoutId,
      machineId: machineId ?? this.machineId,
      machineNo: machineNo ?? this.machineNo,
      brand: brand ?? this.brand,
      model: model ?? this.model,
      position: position ?? this.position,
      size: size ?? this.size,
      zoneId: zoneId ?? this.zoneId,
      status: status ?? this.status,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}

/// Status of machine on the layout (for visual representation)
enum MachineLayoutStatus {
  normal, // Green - operating normally
  maintenance, // Yellow - PM/AM in progress
  breakdown, // Red - breakdown
  offline, // Gray - offline/not running
  alert, // Orange - warning/alert
}

extension MachineLayoutStatusExt on MachineLayoutStatus {
  Color get color {
    switch (this) {
      case MachineLayoutStatus.normal:
        return const Color(0xFF10B981); // Green
      case MachineLayoutStatus.maintenance:
        return const Color(0xFFFBBF24); // Yellow
      case MachineLayoutStatus.breakdown:
        return const Color(0xFFEF4444); // Red
      case MachineLayoutStatus.offline:
        return const Color(0xFF9CA3AF); // Gray
      case MachineLayoutStatus.alert:
        return const Color(0xFFF97316); // Orange
    }
  }

  String get label {
    switch (this) {
      case MachineLayoutStatus.normal:
        return 'ปกติ';
      case MachineLayoutStatus.maintenance:
        return 'บำรุงรักษา';
      case MachineLayoutStatus.breakdown:
        return 'เสีย';
      case MachineLayoutStatus.offline:
        return 'หยุดเดิน';
      case MachineLayoutStatus.alert:
        return 'แจ้งเตือน';
    }
  }
}

/// Factory layout configuration
class FactoryLayout {
  final String layoutId;
  final String name;
  final Size canvasSize; // Width and height of the layout canvas
  final List<LayoutZone> zones;
  final List<MachinePosition> machines;
  final String? backgroundPath; // Path to PDF or Image file
  final double backgroundOpacity; // 0.0 to 1.0
  final DateTime? lastUpdated;

  const FactoryLayout({
    required this.layoutId,
    required this.name,
    this.canvasSize = const Size(1600, 1000),
    this.zones = const [],
    this.machines = const [],
    this.backgroundPath,
    this.backgroundOpacity = 1.0,
    this.lastUpdated,
  });

  FactoryLayout copyWith({
    String? layoutId,
    String? name,
    Size? canvasSize,
    List<LayoutZone>? zones,
    List<MachinePosition>? machines,
    String? backgroundPath,
    double? backgroundOpacity,
    DateTime? lastUpdated,
  }) {
    return FactoryLayout(
      layoutId: layoutId ?? this.layoutId,
      name: name ?? this.name,
      canvasSize: canvasSize ?? this.canvasSize,
      zones: zones ?? this.zones,
      machines: machines ?? this.machines,
      backgroundPath: backgroundPath ?? this.backgroundPath,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }

  /// Find machine at position (with zoom/pan offset)
  MachinePosition? getMachineAt(Offset point) {
    // Search in reverse order (top-most first)
    for (int i = machines.length - 1; i >= 0; i--) {
      if (machines[i].contains(point)) {
        return machines[i];
      }
    }
    return null;
  }

  /// Get zone containing point
  LayoutZone? getZoneAt(Offset point) {
    for (final zone in zones) {
      if (zone.bounds.contains(point)) {
        return zone;
      }
    }
    return null;
  }
}
