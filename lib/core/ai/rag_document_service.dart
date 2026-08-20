import 'dart:io';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:excel/excel.dart' as xls;
import '../database/db_helper.dart';
import '../storage/attachment_storage_service.dart';
import 'embedding_service.dart';
import 'vector_db_service.dart';

class RagDocumentItem {
  final String documentId;
  final String fileName;
  final String? machineId;
  final String category;
  final int chunkCount;
  final String? storagePath;
  final DateTime createdAt;

  const RagDocumentItem({
    required this.documentId,
    required this.fileName,
    this.machineId,
    required this.category,
    required this.chunkCount,
    this.storagePath,
    required this.createdAt,
  });
}

class RagDocumentService {
  static const _uuid = Uuid();

  /// Ingest an uploaded document (PDF, TXT, MD, etc.) into the Parallel Vector DB.
  static Future<Map<String, dynamic>> ingestDocument({
    required File file,
    String? machineId,
    String category = 'manual',
    String? customTitle,
  }) async {
    if (!await file.exists()) {
      throw Exception('ไม่พบไฟล์เอกสารที่ระบุ: ${file.path}');
    }

    final docId = _uuid.v4();
    final fileName = customTitle?.trim().isNotEmpty == true
        ? customTitle!.trim()
        : p.basename(file.path);
    final ext = p.extension(file.path).toLowerCase();

    // 1. Copy file to managed storage
    String? savedStoragePath;
    try {
      final asset = await AttachmentStorageService.instance.ingestFile(
        moduleType: 'rag_documents',
        entityId: docId,
        sourcePath: file.path,
        category: category,
      );
      savedStoragePath = asset.storagePath;
    } catch (_) {
      savedStoragePath = file.path;
    }

    // 2. Extract text chunks from file
    final extractedChunks = <Map<String, dynamic>>[];
    final fullTextBuffer = StringBuffer();

    if (ext == '.pdf') {
      final bytes = await file.readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);

      for (int i = 0; i < document.pages.count; i++) {
        final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i).trim();
        if (pageText.isEmpty) continue;

        fullTextBuffer.writeln('[หน้า ${i + 1}] $pageText\n');

        final pageChunks = _splitIntoChunks(pageText, maxChars: 800, overlap: 100);
        for (int c = 0; c < pageChunks.length; c++) {
          extractedChunks.add({
            'page': i + 1,
            'chunk_index': c,
            'text': pageChunks[c],
          });
        }
      }
      document.dispose();
    } else if (ext == '.xlsx' || ext == '.xls') {
      final bytes = await file.readAsBytes();
      final excel = xls.Excel.decodeBytes(bytes);
      for (final tableName in excel.tables.keys) {
        final sheet = excel.tables[tableName];
        if (sheet == null || sheet.maxRows == 0) continue;

        fullTextBuffer.writeln('=== แผ่นงาน (Sheet): $tableName ===');
        for (int r = 0; r < sheet.maxRows; r++) {
          final row = sheet.rows[r];
          if (row.isEmpty) continue;
          final rowValues = row
              .map((cell) => cell?.value?.toString().trim() ?? '')
              .where((v) => v.isNotEmpty)
              .toList();
          if (rowValues.isEmpty) continue;
          fullTextBuffer.writeln('แถวที่ ${r + 1}: ${rowValues.join(" | ")}');
        }
        fullTextBuffer.writeln('');
      }

      final rawExcelText = fullTextBuffer.toString().trim();
      final textChunks = _splitIntoChunks(rawExcelText, maxChars: 800, overlap: 100);
      for (int c = 0; c < textChunks.length; c++) {
        extractedChunks.add({
          'page': c + 1,
          'chunk_index': c,
          'text': textChunks[c],
        });
      }
    } else {
      // Plain text, markdown, CSV, JSON
      final rawText = await file.readAsString();
      fullTextBuffer.write(rawText);
      final textChunks = _splitIntoChunks(rawText, maxChars: 800, overlap: 100);
      for (int c = 0; c < textChunks.length; c++) {
        extractedChunks.add({
          'page': 1,
          'chunk_index': c,
          'text': textChunks[c],
        });
      }
    }

    if (extractedChunks.isEmpty) {
      throw Exception('ไม่สามารถสกัดข้อความจากเอกสารได้ หรือเอกสารเป็นหน้าว่าง');
    }

    // 3. Prepare formatted text for vectorization
    final textsToEmbed = <String>[];
    for (final item in extractedChunks) {
      final page = item['page'];
      final text = item['text'];
      final machineHeader = machineId != null && machineId.isNotEmpty ? ' | รหัสเครื่อง: $machineId' : '';
      final formattedChunk = 'เอกสารคู่มือ: $fileName (หน้า $page)$machineHeader\nหมวดหมู่: $category\nเนื้อหา:\n$text';
      textsToEmbed.add(formattedChunk);
    }

    // 4. Batch Embedding
    final embeddings = await EmbeddingService.getBatchEmbeddings(textsToEmbed);
    if (embeddings.length != extractedChunks.length) {
      throw Exception('เกิดข้อผิดพลาดในการคำนวณ Embedding เวกเตอร์');
    }

    // 5. Store vectors into knowledge_vectors
    await VectorDbService.ensureTable();
    for (int i = 0; i < extractedChunks.length; i++) {
      final item = extractedChunks[i];
      final chunkText = textsToEmbed[i];
      final emb = embeddings[i];
      final vectorId = 'vec_doc_${docId}_${i + 1}';

      await VectorDbService.upsertVector(
        vectorId: vectorId,
        sourceType: 'document',
        sourceId: docId,
        title: '$fileName (หน้า ${item['page']})',
        category: category,
        contentChunk: chunkText,
        embedding: emb,
        metadata: {
          'doc_id': docId,
          'file_name': fileName,
          'page': item['page'],
          'machine_id': machineId,
          'storage_path': savedStoragePath,
          'total_chunks': extractedChunks.length,
          'ingested_at': DateTime.now().toIso8601String(),
        },
      );
    }

    return {
      'status': 'success',
      'doc_id': docId,
      'file_name': fileName,
      'total_chunks': extractedChunks.length,
      'storage_path': savedStoragePath,
      'extracted_text': fullTextBuffer.toString().trim(),
      'message': 'นำเข้าเอกสาร $fileName เข้าสู่ระบบ RAG สำเร็จ ($extractedChunks.length เวกเตอร์)',
    };
  }

  /// List all documents ingested in the RAG Knowledge Store.
  static Future<List<RagDocumentItem>> listIngestedDocuments() async {
    await VectorDbService.ensureTable();

    final rows = await DbHelper.query('''
      SELECT source_id, title, category, metadata_json, created_at, COUNT(*) as chunk_count
      FROM knowledge_vectors
      WHERE source_type = 'document'
      GROUP BY source_id
      ORDER BY created_at DESC
    ''');

    final list = <RagDocumentItem>[];
    for (final r in rows) {
      final docId = r['source_id']?.toString() ?? '';
      Map<String, dynamic> meta = {};
      try {
        final metaStr = r['metadata_json']?.toString();
        if (metaStr != null && metaStr.isNotEmpty) {
          meta = jsonDecode(metaStr) as Map<String, dynamic>;
        }
      } catch (_) {}

      final fileName = meta['file_name']?.toString() ?? r['title']?.toString() ?? 'เอกสาร';
      final machineId = meta['machine_id']?.toString();
      final storagePath = meta['storage_path']?.toString();
      final count = (r['chunk_count'] as num?)?.toInt() ?? 0;
      final createdAt = r['created_at'] != null
          ? DateTime.tryParse(r['created_at'].toString()) ?? DateTime.now()
          : DateTime.now();

      list.add(RagDocumentItem(
        documentId: docId,
        fileName: fileName,
        machineId: machineId,
        category: r['category']?.toString() ?? 'manual',
        chunkCount: count,
        storagePath: storagePath,
        createdAt: createdAt,
      ));
    }
    return list;
  }

  /// Delete all vectors belonging to a specific document.
  static Future<void> deleteDocumentVectors(String documentId) async {
    await DbHelper.execute('''
      DELETE FROM knowledge_vectors
      WHERE source_type = 'document' AND source_id = @id
    ''', params: {'id': documentId});
  }

  /// Helper to split long text into overlapping chunks.
  static List<String> _splitIntoChunks(String text, {int maxChars = 800, int overlap = 100}) {
    final clean = text.replaceAll(RegExp(r'\r\n'), '\n').trim();
    if (clean.length <= maxChars) {
      return [clean];
    }

    final chunks = <String>[];
    int start = 0;
    while (start < clean.length) {
      int end = (start + maxChars).clamp(0, clean.length);

      // Try to break on newline or period near the end
      if (end < clean.length) {
        final lastNewline = clean.lastIndexOf('\n', end);
        if (lastNewline > start + 200) {
          end = lastNewline;
        } else {
          final lastSpace = clean.lastIndexOf(' ', end);
          if (lastSpace > start + 200) {
            end = lastSpace;
          }
        }
      }

      final chunk = clean.substring(start, end).trim();
      if (chunk.isNotEmpty) {
        chunks.add(chunk);
      }

      if (end >= clean.length) break;
      start = end - overlap;
      if (start < 0) start = 0;
    }
    return chunks;
  }
}
