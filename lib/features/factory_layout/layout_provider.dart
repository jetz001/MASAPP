import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/db_helper.dart';
import 'layout_models.dart';

/// Repository for factory layout data
class LayoutRepository {
  /// Load layout configuration from database
  Future<FactoryLayout?> loadLayout(String layoutId) async {
    try {
      final row = await DbHelper.queryOne(
        'SELECT * FROM factory_layouts WHERE layout_id = @id',
        params: {'id': layoutId},
      );

      if (row == null) return null;

      // Load zones
      final zoneRows = await DbHelper.query(
        'SELECT * FROM layout_zones WHERE layout_id = @id ORDER BY zone_id',
        params: {'id': layoutId},
      );

      final zones = <LayoutZone>[];
      for (final zoneRow in zoneRows) {
        zones.add(
          LayoutZone(
            zoneId: zoneRow['zone_id'] as String,
            name: zoneRow['zone_name'] as String,
            bounds: Rect.fromLTWH(
              (zoneRow['x_start'] as num).toDouble(),
              (zoneRow['y_start'] as num).toDouble(),
              ((zoneRow['x_end'] as num) - (zoneRow['x_start'] as num)).toDouble(),
              ((zoneRow['y_end'] as num) - (zoneRow['y_start'] as num)).toDouble(),
            ),
            description: zoneRow['description'] as String?,
          ),
        );
      }

      // Load machines
      final machineRows = await DbHelper.query(
        '''SELECT mp.*, m.machine_no, m.brand, m.model, m.status
           FROM machine_positions mp
           JOIN machines m ON m.machine_id = mp.machine_id
           WHERE mp.layout_id = @id
           ORDER BY mp.created_at''',
        params: {'id': layoutId},
      );

      final machines = <MachinePosition>[];
      for (final machineRow in machineRows) {
        machines.add(
          MachinePosition(
            machineId: machineRow['machine_id'] as String,
            machineNo: machineRow['machine_no'] as String,
            brand: machineRow['brand'] as String?,
            model: machineRow['model'] as String?,
            position: Offset(
              (machineRow['x_position'] as num).toDouble(),
              (machineRow['y_position'] as num).toDouble(),
            ),
            size: Size(
              (machineRow['width'] as num?)?.toDouble() ?? 60,
              (machineRow['height'] as num?)?.toDouble() ?? 50,
            ),
            zoneId: machineRow['zone_id'] as String,
            status: _parseStatus(machineRow['status'] as String?),
            lastUpdated: machineRow['updated_at'] != null
                ? DateTime.tryParse(machineRow['updated_at'] as String)
                : null,
          ),
        );
      }

      return FactoryLayout(
        layoutId: layoutId,
        name: row['layout_name'] as String,
        canvasSize: Size(
          (row['canvas_width'] as num?)?.toDouble() ?? 1600,
          (row['canvas_height'] as num?)?.toDouble() ?? 1000,
        ),
        zones: zones,
        machines: machines,
        lastUpdated: row['updated_at'] != null
            ? DateTime.tryParse(row['updated_at'] as String)
            : null,
      );
    } catch (e) {
      return null;
    }
  }

  /// Save machine position
  Future<void> updateMachinePosition(
    String layoutId,
    String machineId,
    Offset position,
  ) async {
    await DbHelper.execute(
      '''UPDATE machine_positions
         SET x_position = @x, y_position = @y, updated_at = CURRENT_TIMESTAMP
         WHERE layout_id = @layout_id AND machine_id = @machine_id''',
      params: {
        'layout_id': layoutId,
        'machine_id': machineId,
        'x': position.dx,
        'y': position.dy,
      },
    );
  }

  /// Get all layouts
  Future<List<FactoryLayout>> getAllLayouts() async {
    try {
      final rows = await DbHelper.query(
        'SELECT layout_id, layout_name FROM factory_layouts ORDER BY layout_name',
      );
      return rows
          .map(
            (row) => FactoryLayout(
              layoutId: row['layout_id'] as String,
              name: row['layout_name'] as String,
            ),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  static MachineLayoutStatus _parseStatus(String? status) {
    switch (status) {
      case 'breakdown':
        return MachineLayoutStatus.breakdown;
      case 'pm':
      case 'am':
        return MachineLayoutStatus.maintenance;
      case 'offline':
        return MachineLayoutStatus.offline;
      default:
        return MachineLayoutStatus.normal;
    }
  }
}

/// Riverpod providers for factory layout

final layoutRepositoryProvider = Provider((ref) => LayoutRepository());

/// Get list of available layouts
final layoutListProvider = FutureProvider((ref) async {
  final repo = ref.watch(layoutRepositoryProvider);
  return await repo.getAllLayouts();
});

/// Selected layout ID
final selectedLayoutIdProvider = StateProvider<String>(
  (ref) => 'default_layout',
);

/// Current layout with machines and zones
final currentLayoutProvider = FutureProvider((ref) async {
  final repo = ref.watch(layoutRepositoryProvider);
  final layoutId = ref.watch(selectedLayoutIdProvider);
  return await repo.loadLayout(layoutId);
});

/// Selected machine on the layout
final selectedMachineProvider = StateProvider<MachinePosition?>((ref) => null);

/// Zoom level (1.0 = 100%)
final zoomLevelProvider = StateProvider<double>((ref) => 1.0);

/// Pan offset (translation)
final panOffsetProvider = StateProvider<Offset>((ref) => Offset.zero);

/// Update machine position
final updateMachinePositionProvider =
    FutureProvider.family<
      void,
      ({String layoutId, String machineId, Offset position})
    >((ref, params) async {
      final repo = ref.watch(layoutRepositoryProvider);
      await repo.updateMachinePosition(
        params.layoutId,
        params.machineId,
        params.position,
      );
      // Invalidate layout to refresh
      ref.invalidate(currentLayoutProvider);
    });
