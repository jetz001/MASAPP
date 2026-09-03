import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:masapp/core/storage/attachment_storage_service.dart';

void main() {
  group('StoredAsset Model & Storage Conventions', () {
    test('StoredAsset instantiates correctly with all metadata fields', () {
      const asset = StoredAsset(
        assetId: 'asset-1234-uuid',
        moduleType: 'work_order',
        entityId: 'WO-2026-0001',
        category: 'attachment',
        displayName: 'broken_gear.jpg',
        sourcePath: 'C:\\Users\\User\\Downloads\\broken_gear.jpg',
        storagePath: 'storage/work_order/WO-2026-0001/original/wo_broken_gear.jpg',
        previewPath: 'storage/work_order/WO-2026-0001/preview/wo_broken_gear_preview.png',
        thumbnailPath: 'storage/work_order/WO-2026-0001/thumb/wo_broken_gear_thumb.png',
        mimeType: 'image/jpeg',
        fileSize: 204800,
        width: 1920,
        height: 1080,
        pageCount: null,
        isPrimary: true,
      );

      expect(asset.assetId, equals('asset-1234-uuid'));
      expect(asset.moduleType, equals('work_order'));
      expect(asset.entityId, equals('WO-2026-0001'));
      expect(asset.isPrimary, isTrue);
      expect(asset.mimeType, equals('image/jpeg'));
      expect(asset.fileSize, equals(204800));
      expect(asset.width, equals(1920));
      expect(asset.height, equals(1080));
      expect(asset.pageCount, isNull);
    });

    test('Managed storage path structure conforms to relative db layout', () {
      const moduleType = 'machine_handover';
      const entityId = 'MC-001';
      final relativeDir = p.join('storage', moduleType, entityId, 'original');

      expect(relativeDir.startsWith('storage'), isTrue);
      expect(relativeDir.contains(moduleType), isTrue);
      expect(relativeDir.contains(entityId), isTrue);
      expect(relativeDir.contains('original'), isTrue);
    });
  });
}
