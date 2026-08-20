import 'dart:convert';
import 'dart:math' as math;
import 'package:logger/logger.dart';
import 'package:uuid/uuid.dart';
import '../database/db_helper.dart';
import 'embedding_service.dart';

final _log = Logger();

class VectorSearchResult {
  final String vectorId;
  final String sourceType;
  final String? sourceId;
  final String title;
  final String? category;
  final String contentChunk;
  final Map<String, dynamic> metadata;
  final double score;

  const VectorSearchResult({
    required this.vectorId,
    required this.sourceType,
    this.sourceId,
    required this.title,
    this.category,
    required this.contentChunk,
    required this.metadata,
    required this.score,
  });

  Map<String, dynamic> toMap() {
    return {
      'vector_id': vectorId,
      'source_type': sourceType,
      'source_id': sourceId,
      'title': title,
      'category': category,
      'content': contentChunk,
      'similarity_score': '${(score * 100).toStringAsFixed(1)}%',
      'metadata': metadata,
    };
  }
}

class VectorDbService {
  static const _uuid = Uuid();

  /// Ensure knowledge_vectors table exists.
  static Future<void> ensureTable() async {
    try {
      await DbHelper.execute('''
        CREATE TABLE IF NOT EXISTS knowledge_vectors (
          vector_id      TEXT PRIMARY KEY,
          source_type    TEXT NOT NULL,
          source_id      TEXT,
          title          TEXT NOT NULL,
          category       TEXT,
          content_chunk  TEXT NOT NULL,
          embedding_json TEXT NOT NULL,
          metadata_json  TEXT,
          created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
          updated_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
      ''');

      await DbHelper.execute(
        'CREATE INDEX IF NOT EXISTS idx_kv_source ON knowledge_vectors(source_type, source_id)',
      );
      await DbHelper.execute(
        'CREATE INDEX IF NOT EXISTS idx_kv_category ON knowledge_vectors(category)',
      );
    } catch (e) {
      _log.w('Could not ensure knowledge_vectors table: $e');
    }
  }

  /// Upgrade an existing database to support Parallel Vector AI.
  /// 1. Creates knowledge_vectors table
  /// 2. Injects default embedding settings without touching existing data
  /// 3. Injects initial seed vectors if empty
  /// 4. Auto-indexes historical work orders, PM plans, and machine specs
  static Future<Map<String, dynamic>> upgradeExistingDatabase() async {
    await ensureTable();

    // 1. Add missing default settings
    final defaultSettings = {
      'embedding_provider': 'local',
      'embedding_model_mistral': 'mistral-embed',
      'embedding_base_url_mistral': 'https://api.mistral.ai/v1',
      'embedding_model_ollama': 'nomic-embed-text',
      'embedding_base_url_ollama': 'http://127.0.0.1:11434',
      'embedding_model_gemini': 'text-embedding-004',
      'embedding_model_openai': 'text-embedding-3-small',
      'embedding_base_url_openai': 'https://api.openai.com/v1',
    };

    for (final entry in defaultSettings.entries) {
      await DbHelper.execute('''
        INSERT OR IGNORE INTO app_settings (setting_key, setting_value, description, updated_at)
        VALUES (@key, @val, 'Default embedding setting', CURRENT_TIMESTAMP)
      ''', params: {'key': entry.key, 'val': entry.value});
    }

    // 2. Index existing historical data
    final count = await indexHistoricalKnowledge();

    return {
      'status': 'success',
      'table_created': true,
      'settings_updated': true,
      'vectors_indexed': count,
      'message': 'อัปเกรดฐานข้อมูลรองรับ Vector AI สำเร็จ (ประมวลผลข้อมูลเก่า $count รายการ)',
    };
  }

  /// Store or update vector record.
  static Future<void> upsertVector({
    String? vectorId,
    required String sourceType,
    String? sourceId,
    required String title,
    String? category,
    required String contentChunk,
    required List<double> embedding,
    Map<String, dynamic>? metadata,
  }) async {
    final id = vectorId ?? _uuid.v4();
    final embJson = jsonEncode(embedding);
    final metaJson = jsonEncode(metadata ?? {});

    await DbHelper.execute('''
      INSERT INTO knowledge_vectors (
        vector_id, source_type, source_id, title, category, content_chunk,
        embedding_json, metadata_json, updated_at
      )
      VALUES (@id, @source_type, @source_id, @title, @cat, @content, @emb, @meta, CURRENT_TIMESTAMP)
      ON CONFLICT(vector_id) DO UPDATE SET
        title = excluded.title,
        category = excluded.category,
        content_chunk = excluded.content_chunk,
        embedding_json = excluded.embedding_json,
        metadata_json = excluded.metadata_json,
        updated_at = CURRENT_TIMESTAMP
    ''', params: {
      'id': id,
      'source_type': sourceType,
      'source_id': sourceId,
      'title': title,
      'cat': category,
      'content': contentChunk,
      'emb': embJson,
      'meta': metaJson,
    });
  }

  /// Search top-K similar knowledge vectors for a given query text.
  static Future<List<VectorSearchResult>> searchSimilar(
    String query, {
    int topK = 5,
    double minScore = 0.20,
    String? category,
    String? sourceType,
  }) async {
    await ensureTable();

    final queryVector = await EmbeddingService.getEmbedding(query);
    if (queryVector.isEmpty) return [];

    String sql = 'SELECT * FROM knowledge_vectors WHERE 1=1';
    final params = <String, dynamic>{};

    if (category != null && category.trim().isNotEmpty) {
      sql += ' AND category = @cat';
      params['cat'] = category.trim();
    }
    if (sourceType != null && sourceType.trim().isNotEmpty) {
      sql += ' AND source_type = @stype';
      params['stype'] = sourceType.trim();
    }

    final rows = await DbHelper.query(sql, params: params);
    if (rows.isEmpty) return [];

    final scoredList = <VectorSearchResult>[];

    for (final row in rows) {
      try {
        final embRaw = row['embedding_json']?.toString();
        if (embRaw == null || embRaw.isEmpty) continue;

        final embList = (jsonDecode(embRaw) as List<dynamic>)
            .map((v) => (v as num).toDouble())
            .toList();

        final score = cosineSimilarity(queryVector, embList);
        if (score >= minScore) {
          Map<String, dynamic> metadata = {};
          final metaRaw = row['metadata_json']?.toString();
          if (metaRaw != null && metaRaw.isNotEmpty) {
            try {
              metadata = jsonDecode(metaRaw) as Map<String, dynamic>;
            } catch (_) {}
          }

          scoredList.add(
            VectorSearchResult(
              vectorId: row['vector_id'].toString(),
              sourceType: row['source_type'].toString(),
              sourceId: row['source_id']?.toString(),
              title: row['title']?.toString() ?? '',
              category: row['category']?.toString(),
              contentChunk: row['content_chunk']?.toString() ?? '',
              metadata: metadata,
              score: score,
            ),
          );
        }
      } catch (e) {
        _log.w('Failed to evaluate vector similarity for row ${row['vector_id']}: $e');
      }
    }

    scoredList.sort((a, b) => b.score.compareTo(a.score));
    return scoredList.take(topK).toList();
  }

  /// Calculate Cosine Similarity between two vectors.
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) return 0.0;

    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (var i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    if (normA <= 0.0 || normB <= 0.0) return 0.0;
    return dotProduct / (math.sqrt(normA) * math.sqrt(normB));
  }

  /// Automatically sync a single work order to Vector DB in background
  static Future<void> syncWorkOrder(String woId) async {
    try {
      final rows = await DbHelper.query(
        'SELECT wo_id, wo_no, title, description, failure_symptom, failure_cause, '
        'action_taken, status, priority, machine_id '
        'FROM work_orders WHERE wo_id = @id LIMIT 1',
        params: {'id': woId},
      );
      if (rows.isEmpty) return;

      final wo = rows.first;
      final woNo = wo['wo_no'] ?? '';
      final title = wo['title'] ?? 'ใบแจ้งซ่อม $woNo';
      final symptom = wo['failure_symptom'] ?? '';
      final cause = wo['failure_cause'] ?? '';
      final action = wo['action_taken'] ?? '';
      final desc = wo['description'] ?? '';

      final chunk = 'ใบแจ้งซ่อม: $woNo | หัวข้อ: $title\n'
          'อาการเสีย (Symptom): $symptom\n'
          'สาเหตุที่พบ (Cause/RCA): $cause\n'
          'วิธีแก้ไขและการซ่อม (Action Taken): $action\n'
          'รายละเอียดเพิ่มเติม: $desc';

      final emb = await EmbeddingService.getEmbedding(chunk);
      if (emb.isNotEmpty) {
        await upsertVector(
          vectorId: 'vec_wo_$woId',
          sourceType: 'work_order',
          sourceId: woId,
          title: title.toString(),
          category: 'repair_history',
          contentChunk: chunk,
          embedding: emb,
          metadata: {
            'wo_no': woNo,
            'machine_id': wo['machine_id'],
            'status': wo['status'],
            'priority': wo['priority'],
          },
        );
        _log.i('[VectorDB] Auto-synced work order $woNo to Vector DB');
      }
    } catch (e) {
      _log.w('[VectorDB] Failed to auto-sync work order: $e');
    }
  }

  /// Index/Re-index historical Work Orders (RCA, Symptoms, Solutions) and Machine Documents into Vector DB.
  static Future<int> indexHistoricalKnowledge() async {
    await ensureTable();
    int count = 0;

    try {
      // 1. Index Work Orders with solutions / symptoms / causes
      final woRows = await DbHelper.query('''
        SELECT wo_id, wo_no, title, description, failure_symptom, failure_cause,
               action_taken, status, priority, machine_id
        FROM work_orders
        WHERE (failure_symptom IS NOT NULL AND failure_symptom != '')
           OR (action_taken IS NOT NULL AND action_taken != '')
           OR (failure_cause IS NOT NULL AND failure_cause != '')
      ''');

      for (final wo in woRows) {
        final woNo = wo['wo_no'] ?? '';
        final title = wo['title'] ?? 'ใบแจ้งซ่อม $woNo';
        final symptom = wo['failure_symptom'] ?? '';
        final cause = wo['failure_cause'] ?? '';
        final action = wo['action_taken'] ?? '';
        final desc = wo['description'] ?? '';

        final chunk = 'ใบแจ้งซ่อม: $woNo | หัวข้อ: $title\n'
            'อาการเสีย (Symptom): $symptom\n'
            'สาเหตุที่พบ (Cause/RCA): $cause\n'
            'วิธีแก้ไขและการซ่อม (Action Taken): $action\n'
            'รายละเอียดเพิ่มเติม: $desc';

        final emb = await EmbeddingService.getEmbedding(chunk);
        if (emb.isNotEmpty) {
          await upsertVector(
            vectorId: 'vec_wo_${wo['wo_id']}',
            sourceType: 'work_order',
            sourceId: wo['wo_id']?.toString(),
            title: title.toString(),
            category: 'repair_history',
            contentChunk: chunk,
            embedding: emb,
            metadata: {
              'wo_no': woNo,
              'machine_id': wo['machine_id'],
              'status': wo['status'],
              'priority': wo['priority'],
            },
          );
          count++;
        }
      }

      // 2. Index PM/AM Plans
      final pmRows = await DbHelper.query('''
        SELECT plan_id, plan_code, plan_name, description, machine_id, frequency_type
        FROM pm_am_plans
      ''');

      for (final pm in pmRows) {
        final code = pm['plan_code'] ?? '';
        final name = pm['plan_name'] ?? '';
        final desc = pm['description'] ?? '';
        final freq = pm['frequency_type'] ?? '';

        final chunk = 'แผนการบำรุงรักษา (PM/AM Plan): $code - $name\n'
            'ความถี่: $freq\n'
            'รายละเอียดข้อกำหนดการตรวจเช็ค: $desc';

        final emb = await EmbeddingService.getEmbedding(chunk);
        if (emb.isNotEmpty) {
          await upsertVector(
            vectorId: 'vec_pm_${pm['plan_id']}',
            sourceType: 'pm_plan',
            sourceId: pm['plan_id']?.toString(),
            title: name.toString(),
            category: 'pm_standard',
            contentChunk: chunk,
            embedding: emb,
            metadata: {
              'plan_code': code,
              'machine_id': pm['machine_id'],
              'frequency_type': freq,
            },
          );
          count++;
        }
      }

      // 3. Index Machine Specs
      final mcRows = await DbHelper.query('''
        SELECT m.machine_id, m.machine_no, m.machine_name, m.brand, m.model,
               s.motor_power_kw, s.voltage_v, s.air_pressure_bar, s.hydraulic_pressure_bar
        FROM machines m
        LEFT JOIN machine_specs s ON m.machine_id = s.machine_id
      ''');

      for (final mc in mcRows) {
        final no = mc['machine_no'] ?? '';
        final name = mc['machine_name'] ?? '';
        final brand = mc['brand'] ?? '';
        final model = mc['model'] ?? '';
        final kw = mc['motor_power_kw'] ?? '-';
        final v = mc['voltage_v'] ?? '-';
        final air = mc['air_pressure_bar'] ?? '-';
        final hyd = mc['hydraulic_pressure_bar'] ?? '-';

        final chunk = 'ข้อมูลเครื่องจักรและสเปก: $no ($name)\n'
            'ยี่ห้อ: $brand | รุ่น: $model\n'
            'กำลังมอเตอร์: $kw kW | แรงดันไฟฟ้า: $v V\n'
            'แรงดันลมมาตรฐาน: $air bar | แรงดันไฮดรอลิกมาตรฐาน: $hyd bar';

        final emb = await EmbeddingService.getEmbedding(chunk);
        if (emb.isNotEmpty) {
          await upsertVector(
            vectorId: 'vec_mc_${mc['machine_id']}',
            sourceType: 'machine_spec',
            sourceId: mc['machine_id']?.toString(),
            title: '$no - $name',
            category: 'machine_specs',
            contentChunk: chunk,
            embedding: emb,
            metadata: {
              'machine_no': no,
              'brand': brand,
              'model': model,
            },
          );
          count++;
        }
      }
    } catch (e) {
      _log.e('Error during knowledge indexing: $e');
    }

    return count;
  }
}
