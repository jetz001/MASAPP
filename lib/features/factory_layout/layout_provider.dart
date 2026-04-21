import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:logger/logger.dart';
import '../../core/database/db_helper.dart';
import 'layout_models.dart';

final _log = Logger();

final isScanningProvider = StateProvider<bool>((ref) => false);
final isEditModeProvider = StateProvider<bool>((ref) => false);

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
            layoutId: layoutId,
            name: zoneRow['zone_name'] as String,
            type: zoneRow['zone_type'] as String? ?? 'production',
            bounds: Rect.fromLTWH(
              (zoneRow['x_start'] as num).toDouble(),
              (zoneRow['y_start'] as num).toDouble(),
              ((zoneRow['x_end'] as num) - (zoneRow['x_start'] as num)).toDouble(),
              ((zoneRow['y_end'] as num) - (zoneRow['y_start'] as num)).toDouble(),
            ),
            color: zoneRow['background_color'] != null
                ? Color(int.parse(zoneRow['background_color'].toString().replaceAll('#', ''), radix: 16) | 0xFF000000)
                : Colors.green,
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
            positionId: machineRow['position_id'] as String,
            layoutId: layoutId,
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
            zoneId: machineRow['zone_id'] as String? ?? '',
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
        backgroundPath: row['background_path'] as String?,
        backgroundOpacity: (row['background_opacity'] as num?)?.toDouble() ?? 1.0,
        lastUpdated: row['updated_at'] != null
            ? DateTime.tryParse(row['updated_at'] as String)
            : null,
      );
    } catch (e, stack) {
      _log.e('Error loading layout $layoutId: $e', stackTrace: stack);
      rethrow;
    }
  }

  /// Ensure all required columns exist in the layout tables
  static Future<void> ensureSchema() async {
    try {
      await DbHelper.execute('ALTER TABLE factory_layouts ADD COLUMN background_path TEXT');
    } catch (_) {}
    try {
      await DbHelper.execute('ALTER TABLE factory_layouts ADD COLUMN background_opacity REAL DEFAULT 1.0');
    } catch (_) {}
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

  /// Delete a machine position
  Future<void> deleteMachinePosition(String layoutId, String positionId) async {
    await DbHelper.execute(
      'DELETE FROM machine_positions WHERE layout_id = @lid AND position_id = @pid',
      params: {'lid': layoutId, 'pid': positionId},
    );
  }

  /// Delete a layout zone
  Future<void> deleteLayoutZone(String layoutId, String zoneId) async {
    await DbHelper.execute(
      'DELETE FROM layout_zones WHERE layout_id = @lid AND zone_id = @zid',
      params: {'lid': layoutId, 'zid': zoneId},
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

  /// Create a new factory layout
  Future<String> createLayout({
    required String name,
    String? description,
    double widthM = 32.0,
    double heightM = 20.0,
    double scale = 50.0,
    String? backgroundPath,
    double backgroundOpacity = 1.0,
    String? createdBy,
  }) async {
    final layoutId = 'layout_${DateTime.now().millisecondsSinceEpoch}';
    await DbHelper.execute(
      '''INSERT INTO factory_layouts (
           layout_id, layout_name, description, width_m, height_m, 
           scale_pixel_per_m, background_path, background_opacity,
           created_by, created_at, updated_at
         ) VALUES (
           @id, @name, @desc, @width, @height, @scale, @bg, @opacity, @user, 
           CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
         )''',
      params: {
        'id': layoutId,
        'name': name,
        'desc': description,
        'width': widthM,
        'height': heightM,
        'scale': scale,
        'bg': backgroundPath,
        'opacity': backgroundOpacity,
        'user': createdBy,
      },
    );
    return layoutId;
  }

  /// Delete a layout
  Future<void> deleteLayout(String layoutId) async {
    await DbHelper.execute(
      'DELETE FROM factory_layouts WHERE layout_id = @id',
      params: {'id': layoutId},
    );
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

/// Provider for loading layout background image/pdf
final layoutBackgroundImageProvider =
    FutureProvider.family<ui.Image?, String?>((ref, path) async {
  if (path == null || path.isEmpty) return null;

  try {
    final file = File(path);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();

    // Check if it's a PDF
    if (path.toLowerCase().endsWith('.pdf')) {
      // Rasterize the first page of the PDF
      final images = Printing.raster(bytes, pages: [0], dpi: 150);
      await for (final image in images) {
        final uiImage = await decodeImageFromList(await image.toPng());
        return uiImage;
      }
    } else {
      // Direct image file
      final uiImage = await decodeImageFromList(bytes);
      return uiImage;
    }
  } catch (e) {
    debugPrint('Error loading background image: $e');
  }
  return null;
});

/// Riverpod providers for factory layout

final layoutRepositoryProvider = Provider((ref) => LayoutRepository());

/// Get list of available layouts
final layoutListProvider = FutureProvider((ref) async {
  final repo = ref.watch(layoutRepositoryProvider);
  return await repo.getAllLayouts();
});

/// Selected layout ID
final selectedLayoutIdProvider = StateProvider<String?>((ref) => null);

/// Current layout with machines and zones
final currentLayoutProvider = FutureProvider<FactoryLayout?>((ref) async {
  final layouts = await ref.watch(layoutListProvider.future);
  if (layouts.isEmpty) return null;

  String? selectedId = ref.watch(selectedLayoutIdProvider);
  
  if (selectedId == null || !layouts.any((l) => l.layoutId == selectedId)) {
    // Default to first layout if none selected or selection invalid
    selectedId = layouts.first.layoutId;
    // Update provider in microtask to avoid side-effects during build
    Future.microtask(() {
      ref.read(selectedLayoutIdProvider.notifier).state = selectedId;
    });
  }

  final repo = ref.watch(layoutRepositoryProvider);
  return await repo.loadLayout(selectedId);
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
