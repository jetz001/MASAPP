import 'dart:convert';
import 'dart:math' as math;
import 'package:uuid/uuid.dart';

/// Result summary of a chunked batch execution.
class BatchProcessResult {
  final int totalItems;
  final int processedCount;
  final int insertedCount;
  final int updatedCount;
  final int failedCount;
  final List<String> details;
  final List<String> warnings;

  const BatchProcessResult({
    required this.totalItems,
    required this.processedCount,
    required this.insertedCount,
    required this.updatedCount,
    required this.failedCount,
    required this.details,
    required this.warnings,
  });

  bool get isSuccess => failedCount == 0;

  Map<String, dynamic> toMap() => {
    'total_items': totalItems,
    'processed_count': processedCount,
    'inserted_count': insertedCount,
    'updated_count': updatedCount,
    'failed_count': failedCount,
    'details': details,
    'warnings': warnings,
  };
}

/// Subagent Batch Worker for chunking, normalizing, and transactionally executing
/// high-volume bulk operations (80+ machines, PM plans, spare parts, layout positions).
class SubagentBatchWorker {
  static const int defaultChunkSize = 12;

  /// Process items in safe batches of [chunkSize] items.
  /// Reports real-time progress through [onProgress].
  static Future<BatchProcessResult> processInChunks<T>({
    required List<T> items,
    int chunkSize = defaultChunkSize,
    required String entityName,
    void Function(String stepMessage)? onProgress,
    required Future<void> Function(
      List<T> chunk,
      int chunkIndex,
      int totalChunks,
      List<String> detailsAccumulator,
      List<String> warningsAccumulator,
    ) processChunk,
  }) async {
    if (items.isEmpty) {
      return const BatchProcessResult(
        totalItems: 0,
        processedCount: 0,
        insertedCount: 0,
        updatedCount: 0,
        failedCount: 0,
        details: [],
        warnings: [],
      );
    }

    final effectiveChunkSize = math.max(1, chunkSize);
    final totalChunks = (items.length / effectiveChunkSize).ceil();
    final details = <String>[];
    final warnings = <String>[];
    int processedCount = 0;
    int failedCount = 0;

    for (var i = 0; i < totalChunks; i++) {
      final startIndex = i * effectiveChunkSize;
      final endIndex = math.min(startIndex + effectiveChunkSize, items.length);
      final currentChunk = items.sublist(startIndex, endIndex);
      final chunkNumber = i + 1;

      final progressMsg =
          'กำลังประมวลผล $entityName ชุดที่ $chunkNumber/$totalChunks ($endIndex/${items.length} รายการ)...';
      onProgress?.call(progressMsg);

      try {
        await processChunk(
          currentChunk,
          i,
          totalChunks,
          details,
          warnings,
        );
        processedCount += currentChunk.length;
      } catch (e) {
        failedCount += currentChunk.length;
        final errorMsg = 'เกิดข้อผิดพลาดในชุดที่  (-): ';
        warnings.add(errorMsg);
        onProgress?.call('⚠️ ');
      }

      // Small throttle delay between batches to allow SQLite WAL checkpoints and smooth UI updates
      if (i < totalChunks - 1) {
        await Future.delayed(const Duration(milliseconds: 60));
      }
    }

    onProgress?.call(
      '✅ ประมวลผล  เสร็จสิ้น (/ รายการ)',
    );

    return BatchProcessResult(
      totalItems: items.length,
      processedCount: processedCount,
      insertedCount: details.length,
      updatedCount: processedCount - details.length,
      failedCount: failedCount,
      details: details,
      warnings: warnings,
    );
  }

  /// Data Quality Guardrail: Clean and normalize machine technical specs.
  static Map<String, dynamic> normalizeMachineSpecs(Map<String, dynamic> raw) {
    final specs = (raw['specs'] is Map)
        ? (raw['specs'] as Map).cast<String, dynamic>()
        : raw;

    double? parseNum(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      final str = val.toString().replaceAll(RegExp(r'[^0-9.-]'), '').trim();
      return double.tryParse(str);
    }

    int? parseInt(dynamic val) {
      if (val == null) return null;
      if (val is int) return val;
      if (val is num) return val.toInt();
      final str = val.toString().replaceAll(RegExp(r'[^0-9-]'), '').trim();
      return int.tryParse(str);
    }

    final powerKw = parseNum(specs['power_kw'] ?? specs['power'] ?? specs['kw']);
    final voltV = parseNum(specs['voltage_v'] ?? specs['voltage'] ?? specs['volt']);
    final currA = parseNum(specs['current_a'] ?? specs['current'] ?? specs['amp']);
    final freqHz = parseNum(specs['frequency_hz'] ?? specs['frequency'] ?? specs['hz']);
    final capacity = parseNum(specs['capacity'] ?? specs['speed']);
    final capacityUnit = specs['capacity_unit']?.toString().trim();
    final weightKg = parseNum(specs['weight_kg'] ?? specs['weight']);
    final dimL = parseNum(specs['dim_length_mm'] ?? specs['length_mm'] ?? specs['length']);
    final dimW = parseNum(specs['dim_width_mm'] ?? specs['width_mm'] ?? specs['width']);
    final dimH = parseNum(specs['dim_height_mm'] ?? specs['height_mm'] ?? specs['height']);
    final rpm = parseNum(specs['rpm'] ?? specs['speed_rpm']);
    final fuelRate = parseNum(specs['fuel_consumption_rate'] ?? specs['fuel_rate']);
    final fuelType = specs['fuel_type']?.toString().trim();
    final workers = parseInt(specs['default_workers'] ?? specs['workers']);

    dynamic extraSpecs = specs['extra_specs'];
    if (extraSpecs != null && extraSpecs is! String) {
      try {
        extraSpecs = jsonEncode(extraSpecs);
      } catch (_) {
        extraSpecs = extraSpecs.toString();
      }
    }

    return {
      'power_kw': powerKw,
      'voltage_v': voltV,
      'current_a': currA,
      'frequency_hz': freqHz,
      'capacity': capacity,
      'capacity_unit': capacityUnit,
      'weight_kg': weightKg,
      'dim_length_mm': dimL,
      'dim_width_mm': dimW,
      'dim_height_mm': dimH,
      'rpm': rpm,
      'fuel_consumption_rate': fuelRate,
      'fuel_type': fuelType,
      'default_workers': workers,
      'extra_specs': extraSpecs,
      'has_specs': powerKw != null ||
          voltV != null ||
          currA != null ||
          freqHz != null ||
          capacity != null ||
          capacityUnit != null ||
          weightKg != null ||
          dimL != null ||
          dimW != null ||
          dimH != null ||
          rpm != null ||
          fuelRate != null ||
          fuelType != null ||
          workers != null ||
          extraSpecs != null,
    };
  }

  /// Data Quality Guardrail: Clean and normalize PM tasks.
  static Map<String, dynamic> normalizePmTask(Map<String, dynamic> raw) {
    final name = raw['task_name']?.toString().trim() ?? 'Inspection Task';
    var type = raw['task_type']?.toString().toLowerCase().trim() ?? 'inspect';
    final validTypes = {'clean', 'lubricate', 'tighten', 'inspect', 'replace', 'calibrate'};
    if (!validTypes.contains(type)) {
      type = 'inspect';
    }

    return {
      'task_id': raw['task_id']?.toString() ?? const Uuid().v4(),
      'task_name': name,
      'task_type': type,
      'is_critical': raw['is_critical'] == true || raw['is_critical'] == 1,
      'std_duration_min': (raw['std_duration_min'] as num?)?.toInt() ?? 15,
      'sop_instruction': raw['sop_instruction']?.toString(),
    };
  }

  /// Data Quality Guardrail: Clean and normalize spare parts data.
  static Map<String, dynamic> normalizeSparePart(Map<String, dynamic> raw) {
    double? parseNum(dynamic val) {
      if (val == null) return null;
      if (val is num) return val.toDouble();
      final str = val.toString().replaceAll(RegExp(r'[^0-9.-]'), '').trim();
      return double.tryParse(str);
    }

    return {
      'part_id': raw['part_id']?.toString() ?? const Uuid().v4(),
      'part_no': raw['part_no']?.toString().trim() ?? 'PART-',
      'part_name': raw['part_name']?.toString().trim() ?? 'Spare Part',
      'category': raw['category']?.toString().trim() ?? 'General',
      'unit': raw['unit']?.toString().trim() ?? 'ชิ้น',
      'current_stock': parseNum(raw['current_stock'] ?? raw['stock'] ?? raw['qty']) ?? 0.0,
      'min_stock': parseNum(raw['min_stock'] ?? raw['min_level']) ?? 1.0,
      'max_stock': parseNum(raw['max_stock'] ?? raw['max_level']) ?? 100.0,
      'unit_cost': parseNum(raw['unit_cost'] ?? raw['cost'] ?? raw['price']) ?? 0.0,
      'location': raw['location']?.toString().trim() ?? 'Store A',
    };
  }
}
