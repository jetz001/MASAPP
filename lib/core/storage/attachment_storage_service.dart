import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:uuid/uuid.dart';

import '../database/db_helper.dart';

class StoredAsset {
  final String assetId;
  final String moduleType;
  final String entityId;
  final String category;
  final String displayName;
  final String sourcePath;
  final String storagePath;
  final String? previewPath;
  final String? thumbnailPath;
  final String mimeType;
  final int fileSize;
  final int? width;
  final int? height;
  final int? pageCount;
  final bool isPrimary;

  const StoredAsset({
    required this.assetId,
    required this.moduleType,
    required this.entityId,
    required this.category,
    required this.displayName,
    required this.sourcePath,
    required this.storagePath,
    required this.previewPath,
    required this.thumbnailPath,
    required this.mimeType,
    required this.fileSize,
    required this.width,
    required this.height,
    required this.pageCount,
    required this.isPrimary,
  });
}

class AttachmentStorageService {
  AttachmentStorageService._();

  static final AttachmentStorageService instance = AttachmentStorageService._();
  static const _previewMaxDimension = 1600;
  static const _thumbMaxDimension = 320;
  static const _requestTimeout = Duration(seconds: 20);

  Future<StoredAsset> ingestFile({
    required String moduleType,
    required String entityId,
    required String sourcePath,
    String? displayName,
    String category = 'attachment',
    bool isPrimary = false,
    String? storageRootPath,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('ไม่พบไฟล์ต้นทาง: $sourcePath');
    }

    final fileName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : p.basename(sourcePath);
    final bytes = await sourceFile.readAsBytes();
    final ext = _resolveExtension(fileName, sourcePath, null);
    final mimeType = _guessMimeType(ext);

    return _storeManagedAsset(
      moduleType: moduleType,
      entityId: entityId,
      sourcePath: sourcePath,
      displayName: fileName,
      category: category,
      isPrimary: isPrimary,
      bytes: bytes,
      fileExt: ext,
      mimeType: mimeType,
      persistMetadata: true,
      storageRootPath: storageRootPath,
    );
  }

  Future<StoredAsset> migrateLegacyFile({
    required String moduleType,
    required String entityId,
    required String sourcePath,
    String? displayName,
    String category = 'attachment',
    bool isPrimary = false,
    String? mimeType,
    String? storageRootPath,
  }) async {
    final trimmedSource = sourcePath.trim();
    if (trimmedSource.isEmpty) {
      throw Exception('ไม่พบ path ต้นทางสำหรับย้ายไฟล์');
    }

    final loaded = await _loadSource(trimmedSource);
    final fileName = displayName?.trim().isNotEmpty == true
        ? displayName!.trim()
        : _fileNameFromSource(trimmedSource);
    final ext = _resolveExtension(fileName, trimmedSource, loaded.contentType);
    final resolvedMimeType = mimeType?.trim().isNotEmpty == true
        ? mimeType!.trim()
        : (loaded.contentType?.trim().isNotEmpty == true
              ? loaded.contentType!.trim()
              : _guessMimeType(ext));

    return _storeManagedAsset(
      moduleType: moduleType,
      entityId: entityId,
      sourcePath: trimmedSource,
      displayName: fileName,
      category: category,
      isPrimary: isPrimary,
      bytes: loaded.bytes,
      fileExt: ext,
      mimeType: resolvedMimeType,
      persistMetadata: false,
      storageRootPath: storageRootPath,
    );
  }

  Future<Map<String, dynamic>?> findAssetByStoragePath(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;

    return DbHelper.queryOne(
      '''
      SELECT *
      FROM file_assets
      WHERE storage_path = @path OR source_path = @path
      ORDER BY updated_at DESC
      LIMIT 1
      ''',
      params: {'path': trimmed},
    );
  }

  Future<List<Map<String, dynamic>>> listAssets({
    required String moduleType,
    required String entityId,
    String? category,
  }) async {
    final where = <String>[
      'module_type = @moduleType',
      'entity_id = @entityId',
    ];
    final params = <String, dynamic>{
      'moduleType': moduleType,
      'entityId': entityId,
    };

    if (category != null && category.trim().isNotEmpty) {
      where.add('category = @category');
      params['category'] = category.trim();
    }

    return DbHelper.query('''
      SELECT *
      FROM file_assets
      WHERE ${where.join(' AND ')}
      ORDER BY is_primary DESC, created_at ASC
      ''', params: params);
  }

  bool looksManagedPath(String path) {
    final normalized = path.trim().replaceAll('/', '\\').toLowerCase();
    if (normalized.isEmpty) return false;
    return normalized.contains('\\storage\\');
  }

  Future<StoredAsset> _storeManagedAsset({
    required String moduleType,
    required String entityId,
    required String sourcePath,
    required String displayName,
    required String category,
    required bool isPrimary,
    required Uint8List bytes,
    required String fileExt,
    required String mimeType,
    required bool persistMetadata,
    required String? storageRootPath,
  }) async {
    final safeExt = fileExt.trim().isEmpty
        ? '.bin'
        : fileExt.trim().toLowerCase();
    final assetId = const Uuid().v4();
    final resolvedDbPath = storageRootPath?.trim().isNotEmpty == true
        ? storageRootPath!.trim()
        : DbHelper.dbPath;
    final baseName =
        '${moduleType}_${entityId}_${DateTime.now().millisecondsSinceEpoch}_${assetId.substring(0, 8)}';
    final rootDir = await _ensureDirectory(
      Directory(
        p.join(
          File(resolvedDbPath).parent.path,
          'storage',
          moduleType,
          entityId,
        ),
      ),
    );
    final originalDir = await _ensureDirectory(
      Directory(p.join(rootDir.path, 'original')),
    );
    final previewDir = await _ensureDirectory(
      Directory(p.join(rootDir.path, 'preview')),
    );
    final thumbDir = await _ensureDirectory(
      Directory(p.join(rootDir.path, 'thumb')),
    );

    final storagePath = p.join(originalDir.path, '$baseName$safeExt');
    final storedFile = File(storagePath);
    await storedFile.writeAsBytes(bytes, flush: true);

    String? previewPath;
    String? thumbnailPath;
    int? width;
    int? height;
    int? pageCount;

    if (_isImageExtension(safeExt)) {
      final derivatives = await _generateImageDerivatives(
        bytes: bytes,
        previewPath: p.join(previewDir.path, '${baseName}_preview.png'),
        thumbnailPath: p.join(thumbDir.path, '${baseName}_thumb.png'),
      );
      previewPath = derivatives.previewPath;
      thumbnailPath = derivatives.thumbnailPath;
      width = derivatives.width;
      height = derivatives.height;
    } else if (safeExt == '.pdf') {
      final derivatives = await _generatePdfDerivatives(
        bytes: bytes,
        thumbnailPath: p.join(thumbDir.path, '${baseName}_thumb.png'),
      );
      previewPath = derivatives.previewPath;
      thumbnailPath = derivatives.thumbnailPath;
      width = derivatives.width;
      height = derivatives.height;
      pageCount = derivatives.pageCount;
    }

    final fileSize = await storedFile.length();

    if (persistMetadata) {
      await _saveAssetMetadata(
        assetId: assetId,
        moduleType: moduleType,
        entityId: entityId,
        category: category,
        displayName: displayName,
        sourcePath: sourcePath,
        storagePath: storagePath,
        previewPath: previewPath,
        thumbnailPath: thumbnailPath,
        mimeType: mimeType,
        fileSize: fileSize,
        width: width,
        height: height,
        pageCount: pageCount,
        isPrimary: isPrimary,
      );
    }

    return StoredAsset(
      assetId: assetId,
      moduleType: moduleType,
      entityId: entityId,
      category: category,
      displayName: displayName,
      sourcePath: sourcePath,
      storagePath: storagePath,
      previewPath: previewPath,
      thumbnailPath: thumbnailPath,
      mimeType: mimeType,
      fileSize: fileSize,
      width: width,
      height: height,
      pageCount: pageCount,
      isPrimary: isPrimary,
    );
  }

  Future<void> _saveAssetMetadata({
    required String assetId,
    required String moduleType,
    required String entityId,
    required String category,
    required String displayName,
    required String sourcePath,
    required String storagePath,
    required String? previewPath,
    required String? thumbnailPath,
    required String mimeType,
    required int fileSize,
    required int? width,
    required int? height,
    required int? pageCount,
    required bool isPrimary,
  }) async {
    if (isPrimary) {
      await DbHelper.execute(
        '''
        UPDATE file_assets
        SET is_primary = 0,
            updated_at = CURRENT_TIMESTAMP
        WHERE module_type = @moduleType
          AND entity_id = @entityId
          AND category = @category
        ''',
        params: {
          'moduleType': moduleType,
          'entityId': entityId,
          'category': category,
        },
      );
    }

    await DbHelper.execute(
      '''
      INSERT INTO file_assets (
        asset_id, module_type, entity_id, category, display_name, source_path,
        storage_path, preview_path, thumbnail_path, mime_type, file_ext,
        file_size, width, height, page_count, is_primary, created_at, updated_at
      ) VALUES (
        @assetId, @moduleType, @entityId, @category, @displayName, @sourcePath,
        @storagePath, @previewPath, @thumbnailPath, @mimeType, @fileExt,
        @fileSize, @width, @height, @pageCount, @isPrimary, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      )
      ''',
      params: {
        'assetId': assetId,
        'moduleType': moduleType,
        'entityId': entityId,
        'category': category,
        'displayName': displayName,
        'sourcePath': sourcePath,
        'storagePath': storagePath,
        'previewPath': previewPath,
        'thumbnailPath': thumbnailPath,
        'mimeType': mimeType,
        'fileExt': p.extension(storagePath).toLowerCase(),
        'fileSize': fileSize,
        'width': width,
        'height': height,
        'pageCount': pageCount,
        'isPrimary': isPrimary ? 1 : 0,
      },
    );
  }

  Future<_ImageDerivativeResult> _generateImageDerivatives({
    required Uint8List bytes,
    required String previewPath,
    required String thumbnailPath,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    final previewBytes = await _resizeImageToPng(
      image,
      maxDimension: _previewMaxDimension,
    );
    final thumbBytes = await _resizeImageToPng(
      image,
      maxDimension: _thumbMaxDimension,
    );

    await File(previewPath).writeAsBytes(previewBytes, flush: true);
    await File(thumbnailPath).writeAsBytes(thumbBytes, flush: true);

    return _ImageDerivativeResult(
      previewPath: previewPath,
      thumbnailPath: thumbnailPath,
      width: image.width,
      height: image.height,
    );
  }

  Future<_PdfDerivativeResult> _generatePdfDerivatives({
    required Uint8List bytes,
    required String thumbnailPath,
  }) async {
    Uint8List? rasterized;
    int? width;
    int? height;

    try {
      final images = Printing.raster(bytes, pages: const [0], dpi: 110);
      await for (final page in images) {
        rasterized = await page.toPng();
        width = page.width;
        height = page.height;
        break;
      }
    } catch (_) {}

    if (rasterized != null) {
      await File(thumbnailPath).writeAsBytes(rasterized, flush: true);
    }

    return _PdfDerivativeResult(
      previewPath: rasterized != null ? thumbnailPath : null,
      thumbnailPath: rasterized != null ? thumbnailPath : null,
      width: width,
      height: height,
      pageCount: _estimatePdfPageCount(bytes),
    );
  }

  Future<Uint8List> _resizeImageToPng(
    ui.Image image, {
    required int maxDimension,
  }) async {
    final longestSide = image.width > image.height ? image.width : image.height;
    final scale = longestSide <= maxDimension
        ? 1.0
        : maxDimension / longestSide;
    final targetWidth = (image.width * scale).round().clamp(1, image.width);
    final targetHeight = (image.height * scale).round().clamp(1, image.height);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final paint = ui.Paint();

    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, targetWidth.toDouble(), targetHeight.toDouble()),
      paint,
    );

    final picture = recorder.endRecording();
    final resized = await picture.toImage(targetWidth, targetHeight);
    final byteData = await resized.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  int? _estimatePdfPageCount(Uint8List bytes) {
    try {
      final content = latin1.decode(bytes, allowInvalid: true);
      final pageMatches = RegExp(r'/Type\s*/Page\b').allMatches(content).length;
      return pageMatches > 0 ? pageMatches : null;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _ensureDirectory(Directory dir) async {
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  bool _isImageExtension(String ext) {
    return const [
      '.jpg',
      '.jpeg',
      '.png',
      '.gif',
      '.webp',
      '.bmp',
    ].contains(ext.toLowerCase());
  }

  String _guessMimeType(String ext) {
    switch (ext.toLowerCase()) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.bmp':
        return 'image/bmp';
      case '.pdf':
        return 'application/pdf';
      case '.doc':
        return 'application/msword';
      case '.docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  String _resolveExtension(
    String displayName,
    String sourcePath,
    String? contentType,
  ) {
    final fromDisplay = p.extension(displayName).toLowerCase();
    if (fromDisplay.isNotEmpty) return fromDisplay;

    final fromSource = p
        .extension(_fileNameFromSource(sourcePath))
        .toLowerCase();
    if (fromSource.isNotEmpty) return fromSource;

    switch ((contentType ?? '').toLowerCase()) {
      case 'image/jpeg':
        return '.jpg';
      case 'image/png':
        return '.png';
      case 'image/gif':
        return '.gif';
      case 'image/webp':
        return '.webp';
      case 'image/bmp':
        return '.bmp';
      case 'application/pdf':
        return '.pdf';
      case 'application/msword':
        return '.doc';
      case 'application/vnd.openxmlformats-officedocument.wordprocessingml.document':
        return '.docx';
      default:
        return '.bin';
    }
  }

  String _fileNameFromSource(String sourcePath) {
    final trimmed = sourcePath.trim();
    if (trimmed.isEmpty) return 'asset.bin';

    if (trimmed.toLowerCase().startsWith('http://') ||
        trimmed.toLowerCase().startsWith('https://')) {
      final uri = Uri.tryParse(trimmed);
      final last = uri?.pathSegments.isNotEmpty == true
          ? uri!.pathSegments.last
          : '';
      return Uri.decodeComponent(last.isEmpty ? 'asset.bin' : last);
    }

    if (trimmed.toLowerCase().startsWith('file:///')) {
      return p.basename(Uri.parse(trimmed).toFilePath());
    }

    return p.basename(trimmed);
  }

  Future<_LoadedSource> _loadSource(String sourcePath) async {
    final trimmed = sourcePath.trim();
    if (trimmed.toLowerCase().startsWith('http://') ||
        trimmed.toLowerCase().startsWith('https://')) {
      final response = await http
          .get(Uri.parse(trimmed))
          .timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('ดาวน์โหลดไฟล์ไม่สำเร็จ: HTTP ${response.statusCode}');
      }
      return _LoadedSource(
        bytes: response.bodyBytes,
        contentType: response.headers['content-type']?.split(';').first.trim(),
      );
    }

    final filePath = trimmed.toLowerCase().startsWith('file:///')
        ? Uri.parse(trimmed).toFilePath()
        : trimmed;
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('ไม่พบไฟล์ต้นทาง: $sourcePath');
    }

    return _LoadedSource(bytes: await file.readAsBytes(), contentType: null);
  }
}

class _ImageDerivativeResult {
  final String previewPath;
  final String thumbnailPath;
  final int width;
  final int height;

  const _ImageDerivativeResult({
    required this.previewPath,
    required this.thumbnailPath,
    required this.width,
    required this.height,
  });
}

class _PdfDerivativeResult {
  final String? previewPath;
  final String? thumbnailPath;
  final int? width;
  final int? height;
  final int? pageCount;

  const _PdfDerivativeResult({
    required this.previewPath,
    required this.thumbnailPath,
    required this.width,
    required this.height,
    required this.pageCount,
  });
}

class _LoadedSource {
  final Uint8List bytes;
  final String? contentType;

  const _LoadedSource({required this.bytes, required this.contentType});
}
