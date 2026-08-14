import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/db_helper.dart';
import 'package:uuid/uuid.dart';

class SparePartsRepository {
  Future<void> addSparePart({
    required String partCode,
    required String partName,
    String? category,
    double? unitCost,
    int reorderLevel = 5,
    String? imagePath,
    String? supplierId,
  }) async {
    final partId = const Uuid().v4();
    await DbHelper.execute('''
      INSERT INTO spare_parts (part_id, part_code, part_name, category, unit_cost, reorder_level, image_path, supplier_id, is_active)
      VALUES (@partId, @partCode, @partName, @category, @unitCost, @reorderLevel, @imagePath, @supplierId, 1)
    ''', params: {
      'partId': partId,
      'partCode': partCode,
      'partName': partName,
      'category': category,
      'unitCost': unitCost,
      'reorderLevel': reorderLevel,
      'imagePath': imagePath,
      'supplierId': supplierId,
    });
    
    // Create inventory record
    await DbHelper.execute('''
      INSERT INTO spare_parts_inventory (part_id, quantity_on_hand, quantity_reserved)
      VALUES (@partId, 0, 0)
    ''', params: {
      'partId': partId,
    });
  }

  Future<void> updateSparePart({
    required String partId,
    required String partCode,
    required String partName,
    String? category,
    double? unitCost,
    int reorderLevel = 5,
    String? imagePath,
    String? supplierId,
  }) async {
    await DbHelper.execute('''
      UPDATE spare_parts
      SET part_code = @partCode,
          part_name = @partName,
          category = @category,
          unit_cost = @unitCost,
          reorder_level = @reorderLevel,
          image_path = @imagePath,
          supplier_id = @supplierId
      WHERE part_id = @partId
    ''', params: {
      'partId': partId,
      'partCode': partCode,
      'partName': partName,
      'category': category,
      'unitCost': unitCost,
      'reorderLevel': reorderLevel,
      'imagePath': imagePath,
      'supplierId': supplierId,
    });
  }

  Future<void> deleteSparePart(String partId) async {
    // Soft delete
    await DbHelper.execute('''
      UPDATE spare_parts
      SET is_active = 0
      WHERE part_id = @partId
    ''', params: {'partId': partId});
  }
}

final sparePartsRepoProvider = Provider((ref) => SparePartsRepository());
