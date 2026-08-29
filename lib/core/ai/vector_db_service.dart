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

    // Hybrid Fallback: If no vector matches (due to dimension change or remote fallback), match keywords
    if (scoredList.isEmpty && query.trim().isNotEmpty) {
      final terms = query.toLowerCase().split(RegExp(r'\s+')).where((t) => t.length >= 2).toList();
      for (final row in rows) {
        final content = (row['content_chunk']?.toString() ?? '').toLowerCase();
        final title = (row['title']?.toString() ?? '').toLowerCase();
        int matchCount = 0;
        for (final t in terms) {
          if (content.contains(t) || title.contains(t)) {
            matchCount++;
          }
        }
        if (matchCount > 0) {
          final keywordScore = (matchCount / (terms.isEmpty ? 1 : terms.length)).clamp(0.2, 0.95);
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
              score: keywordScore,
            ),
          );
        }
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
        'SELECT wo.wo_id, wo.wo_no, wo.title, wo.description, wo.failure_symptom, wo.failure_cause, wo.closure_notes, '
        'wo.status, wo.priority, wo.machine_id, '
        'rca.root_cause, rca.correction_action AS action_taken, rca.preventive_action '
        'FROM work_orders wo '
        'LEFT JOIN work_order_rca rca ON wo.wo_id = rca.wo_id '
        'WHERE wo.wo_id = @id LIMIT 1',
        params: {'id': woId},
      );
      if (rows.isEmpty) return;

      final wo = rows.first;
      final woNo = wo['wo_no'] ?? '';
      final title = wo['title'] ?? 'ใบแจ้งซ่อม $woNo';
      final symptom = wo['failure_symptom'] ?? '';
      final cause = wo['failure_cause'] ?? wo['root_cause'] ?? '';
      final action = (wo['action_taken'] != null && wo['action_taken'].toString().isNotEmpty)
          ? wo['action_taken']
          : (wo['closure_notes'] ?? '');
      final preventive = wo['preventive_action'] ?? '';
      final desc = wo['description'] ?? '';

      final chunk = 'ใบแจ้งซ่อม: $woNo | หัวข้อ: $title\n'
          'อาการเสีย (Symptom): $symptom\n'
          'สาเหตุที่พบ (Cause/RCA): $cause\n'
          'วิธีแก้ไขและการซ่อม (Action Taken): $action\n'
          '${preventive.toString().isNotEmpty ? 'แนวทางป้องกัน (Preventive Action): $preventive\n' : ''}'
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

  /// Automatically sync a single Work Process and its steps/Lean analysis to Vector DB
  static Future<void> syncWorkProcess(String processId) async {
    try {
      final rows = await DbHelper.query(
        'SELECT wp.*, m.machine_no, m.machine_name FROM work_processes wp '
        'LEFT JOIN machines m ON wp.machine_id = m.machine_id '
        'WHERE wp.process_id = @id LIMIT 1',
        params: {'id': processId},
      );
      if (rows.isEmpty) return;

      final p = rows.first;
      final processNo = p['process_no'] ?? '';
      final title = p['title'] ?? '';
      final method = p['method_type'] == 'improved'
          ? 'ฉบับปรับปรุง (Improved)'
          : 'ฉบับปัจจุบัน (Current)';
      final workType = p['work_type'] == 'product'
          ? 'ผลิตภัณฑ์ (Product)'
          : 'คน (Man)';
      final dept = p['department'] ?? '-';
      final machineNo = p['machine_no'] ?? '-';

      final stepRows = await DbHelper.query(
        'SELECT * FROM work_process_steps WHERE process_id = @id ORDER BY step_no ASC',
        params: {'id': processId},
      );

      final stepsText = stepRows.map((s) {
        final no = s['step_no'];
        final desc = s['description'];
        final event = s['event_type'];
        final val = s['value_type'];
        final dur = s['duration_minutes'];
        final dist = s['distance_meters'];
        final prob = s['problem_cause']?.toString() ?? '';
        final idea = s['improvement_idea']?.toString() ?? '';
        final probStr = prob.isNotEmpty ? ' | ปัญหา: $prob' : '';
        final ideaStr = idea.isNotEmpty ? ' | แนวทาง ECRS: $idea' : '';
        return '$no. [$event | $val] $desc (เวลา: $dur นาที, ระยะ: $dist ม.)$probStr$ideaStr';
      }).join('\n');

      final chunk =
          'การวิเคราะห์ขั้นตอนการทำงานและ Lean Analysis: $processNo - $title\n'
          'วิธีการ: $method | ประเภท: $workType | แผนก: $dept | เครื่องจักร: $machineNo\n'
          'ขั้นตอนการทำงานทั้งหมด (${stepRows.length} ขั้นตอน):\n$stepsText';

      final emb = await EmbeddingService.getEmbedding(chunk);
      if (emb.isNotEmpty) {
        await upsertVector(
          vectorId: 'vec_wp_$processId',
          sourceType: 'work_process',
          sourceId: processId,
          title: '$processNo - $title',
          category: 'lean_analysis',
          contentChunk: chunk,
          embedding: emb,
          metadata: {
            'process_no': processNo,
            'method_type': p['method_type'],
            'work_type': p['work_type'],
            'machine_id': p['machine_id'],
          },
        );
        _log.i('[VectorDB] Auto-synced work process $processNo to Vector DB');
      }
    } catch (e) {
      _log.w('[VectorDB] Failed to auto-sync work process: $e');
    }
  }

  /// Automatically sync a Production Line & Line Balancing & VSM to Vector DB
  static Future<void> syncLineBalancing(String lineId) async {
    try {
      final lineRows = await DbHelper.query(
        'SELECT * FROM production_lines WHERE line_id = @id LIMIT 1',
        params: {'id': lineId},
      );
      if (lineRows.isEmpty) return;

      final l = lineRows.first;
      final lineName = l['line_name'] ?? '';
      final dept = l['department'] ?? '-';
      final availMin = (l['available_time_min'] as num?)?.toDouble() ?? 480.0;
      final demand = (l['demand_quantity'] as num?)?.toDouble() ?? 1000.0;
      final taktSec = demand > 0 ? (availMin * 60) / demand : 0.0;

      final stationRows = await DbHelper.query(
        'SELECT * FROM production_line_stations WHERE line_id = @id ORDER BY station_no ASC',
        params: {'id': lineId},
      );

      double totalCycleSec = 0.0;
      double maxCycleSec = 0.0;
      String bottleneckStation = '-';
      int totalWorkers = 0;
      double totalVaSec = 0.0;
      double totalNvaSec = 0.0;

      final stationsText = stationRows.map((s) {
        final no = s['station_no'];
        final name = s['station_name'];
        final mcName = s['machine_name'] ?? '-';
        final ct = (s['cycle_time_sec'] as num?)?.toDouble() ?? 0.0;
        final wk = (s['workers'] as num?)?.toInt() ?? 1;
        final evt = s['event_type'] ?? 'operation';
        final val = s['value_type'] ?? 'va';
        final wait = (s['waiting_time_sec'] as num?)?.toDouble() ?? 0.0;

        totalCycleSec += ct;
        totalWorkers += wk;
        if (val == 'va') {
          totalVaSec += ct;
        } else {
          totalNvaSec += ct;
        }
        totalNvaSec += wait;

        if (ct > maxCycleSec) {
          maxCycleSec = ct;
          bottleneckStation = '$name ($ct วินาที)';
        }

        return '$no. สถานี: $name | เครื่องจักร: $mcName | Cycle Time: $ct วิ. (พนักงาน: $wk คน) | ประเภท Lean: [$evt / $val] | เวลารอคอย: $wait วิ.';
      }).join('\n');

      final lineEfficiency = (stationRows.isNotEmpty && maxCycleSec > 0)
          ? (totalCycleSec / (stationRows.length * maxCycleSec)) * 100
          : 0.0;
      final balanceDelay = 100 - lineEfficiency;
      final totalLeadSec = totalVaSec + totalNvaSec;
      final pce = totalLeadSec > 0 ? (totalVaSec / totalLeadSec) * 100 : 0.0;

      final chunk =
          'สายการผลิตและการวิเคราะห์ Line Balancing & Value Stream Mapping (VSM):\n'
          'ชื่อสายการผลิต: $lineName | แผนก: $dept\n'
          'Takt Time: ${taktSec.toStringAsFixed(1)} วินาที/ชิ้น | Demand: ${demand.toStringAsFixed(0)} ชิ้น | เวลาทำงาน: ${availMin.toStringAsFixed(0)} นาที\n'
          'ประสิทธิภาพสายการผลิต (Line Efficiency): ${lineEfficiency.toStringAsFixed(1)}% | Balance Delay (ความสูญเปล่า): ${balanceDelay.toStringAsFixed(1)}%\n'
          'สถานีคอขวด (Bottleneck): $bottleneckStation\n'
          'จำนวนสถานี: ${stationRows.length} สถานี | พนักงานรวม: $totalWorkers คน\n'
          'VSM Process Cycle Efficiency (PCE): ${pce.toStringAsFixed(1)}% | เวลารวมสร้างมูลค่า (VA): ${totalVaSec.toStringAsFixed(1)} วินาที | เวลารวมสูญเปล่า/รอคอย (NVA/Delay): ${totalNvaSec.toStringAsFixed(1)} วินาที\n'
          'รายละเอียดสถานีงานในไลน์:\n$stationsText';

      final emb = await EmbeddingService.getEmbedding(chunk);
      if (emb.isNotEmpty) {
        await upsertVector(
          vectorId: 'vec_line_$lineId',
          sourceType: 'line_balancing',
          sourceId: lineId,
          title: 'สายการผลิต: $lineName (Line Balancing & VSM)',
          category: 'line_balancing_vsm',
          contentChunk: chunk,
          embedding: emb,
          metadata: {
            'line_id': lineId,
            'line_name': lineName,
            'line_efficiency': lineEfficiency,
            'takt_time_sec': taktSec,
            'bottleneck': bottleneckStation,
            'pce': pce,
          },
        );
        _log.i('[VectorDB] Auto-synced production line $lineName to Vector DB');
      }
    } catch (e) {
      _log.w('[VectorDB] Failed to auto-sync line balancing: $e');
    }
  }

  /// Automatically sync a single Machine and its specs to Vector DB
  static Future<void> syncMachine(String machineId) async {
    try {
      final rows = await DbHelper.query('''
        SELECT m.machine_id, m.machine_no, m.machine_name, m.brand, m.model, m.serial_no, m.location, m.status,
               s.power_kw, s.voltage_v, s.current_a, s.capacity, s.weight_kg, s.extra_specs
        FROM machines m
        LEFT JOIN machine_specs s ON m.machine_id = s.machine_id
        WHERE m.machine_id = @id OR m.machine_no = @id
        LIMIT 1
      ''', params: {'id': machineId});
      if (rows.isEmpty) return;

      final mc = rows.first;
      final mId = mc['machine_id']?.toString() ?? machineId;
      final no = mc['machine_no'] ?? '';
      final name = mc['machine_name'] ?? '';
      final brand = mc['brand'] ?? '';
      final model = mc['model'] ?? '';
      final loc = mc['location'] ?? '';
      final status = mc['status'] ?? '';
      final kw = mc['power_kw'] ?? '-';
      final v = mc['voltage_v'] ?? '-';
      final a = mc['current_a'] ?? '-';
      final cap = mc['capacity'] ?? '-';
      final w = mc['weight_kg'] ?? '-';

      // Find linked work process steps / SOP
      final wpRows = await DbHelper.query('''
        SELECT wp.process_no, wp.title, wp.process_id
        FROM work_processes wp
        WHERE wp.machine_id = @id
        ORDER BY wp.created_at DESC LIMIT 1
      ''', params: {'id': mId});

      String sopText = '';
      if (wpRows.isNotEmpty) {
        final wpId = wpRows.first['process_id'].toString();
        final wpTitle = wpRows.first['title'] ?? '';
        final stepRows = await DbHelper.query(
          'SELECT step_no, description, duration_minutes FROM work_process_steps WHERE process_id = @id ORDER BY step_no ASC',
          params: {'id': wpId},
        );
        if (stepRows.isNotEmpty) {
          final stepsStr = stepRows.map((s) => '${s['step_no']}. ${s['description']} (${s['duration_minutes']} นาที)').join(' -> ');
          sopText = '\nขั้นตอนการทำงานมาตรฐาน (SOP: $wpTitle): $stepsStr';
        }
      }

      final chunk = 'ข้อมูลเครื่องจักรและสเปก: $no ($name)\n'
          'ยี่ห้อ: $brand | รุ่น: $model | ตำแหน่ง: $loc | สถานะ: $status\n'
          'กำลังไฟฟ้า: $kw kW | แรงดันไฟฟ้า: $v V | กระแสไฟฟ้า: $a A\n'
          'ความสามารถในการผลิต/ความจุ: $cap | น้ำหนักเครื่อง: $w kg$sopText';

      final emb = await EmbeddingService.getEmbedding(chunk);
      if (emb.isNotEmpty) {
        await upsertVector(
          vectorId: 'vec_mc_$mId',
          sourceType: 'machine_spec',
          sourceId: mId,
          title: '$no - $name',
          category: 'machine_specs',
          contentChunk: chunk,
          embedding: emb,
          metadata: {
            'machine_no': no,
            'machine_name': name,
            'brand': brand,
            'model': model,
            'location': loc,
          },
        );
        _log.i('[VectorDB] Auto-synced machine $no ($name) to Vector DB');
      }
    } catch (e) {
      _log.w('[VectorDB] Failed to auto-sync machine: $e');
    }
  }

  /// Automatically sync a single Spare Part to Vector DB
  static Future<void> syncSparePart(String partId) async {
    try {
      final rows = await DbHelper.query('''
        SELECT sp.part_id, sp.part_code, sp.part_name, sp.category, sp.unit_cost, sp.reorder_level,
               inv.quantity_on_hand, inv.location
        FROM spare_parts sp
        LEFT JOIN spare_parts_inventory inv ON sp.part_id = inv.part_id
        WHERE sp.part_id = @id OR sp.part_code = @id
        LIMIT 1
      ''', params: {'id': partId});
      if (rows.isEmpty) return;

      final sp = rows.first;
      final pId = sp['part_id']?.toString() ?? partId;
      final code = sp['part_code'] ?? '';
      final name = sp['part_name'] ?? '';
      final cat = sp['category'] ?? '-';
      final cost = sp['unit_cost'] ?? 0;
      final reorder = sp['reorder_level'] ?? 0;
      final qty = sp['quantity_on_hand'] ?? 0;
      final loc = sp['location'] ?? '-';

      // Find linked machines
      final mapRows = await DbHelper.query('''
        SELECT m.machine_no, m.machine_name
        FROM part_machine_map pmm
        JOIN machines m ON pmm.machine_id = m.machine_id
        WHERE pmm.part_id = @id
      ''', params: {'id': pId});
      final linkedMc = mapRows.map((m) => '${m['machine_no']} (${m['machine_name']})').join(', ');

      final chunk = 'ข้อมูลอะไหล่และการใช้งาน: $code - $name\n'
          'หมวดหมู่: $cat | คงเหลือในคลัง: $qty หน่วย (จุดสั่งซื้อ: $reorder) | ตำแหน่งเก็บ: $loc | ราคาต่อหน่วย: ฿$cost\n'
          'ใช้กับเครื่องจักร: ${linkedMc.isEmpty ? 'ทั่วไป' : linkedMc}';

      final emb = await EmbeddingService.getEmbedding(chunk);
      if (emb.isNotEmpty) {
        await upsertVector(
          vectorId: 'vec_part_$pId',
          sourceType: 'spare_part',
          sourceId: pId,
          title: '$code - $name',
          category: 'spare_parts',
          contentChunk: chunk,
          embedding: emb,
          metadata: {
            'part_code': code,
            'part_name': name,
            'category': cat,
            'location': loc,
            'quantity_on_hand': qty,
          },
        );
        _log.i('[VectorDB] Auto-synced spare part $code ($name) to Vector DB');
      }
    } catch (e) {
      _log.w('[VectorDB] Failed to auto-sync spare part: $e');
    }
  }

  /// Automatically sync a single Tool to Vector DB
  static Future<void> syncTool(String toolId) async {
    try {
      final rows = await DbHelper.query('''
        SELECT tool_id, tool_code, tool_name, category, status, notes
        FROM tools
        WHERE tool_id = @id OR tool_code = @id
        LIMIT 1
      ''', params: {'id': toolId});
      if (rows.isEmpty) return;

      final t = rows.first;
      final tId = t['tool_id']?.toString() ?? toolId;
      final code = t['tool_code'] ?? '';
      final name = t['tool_name'] ?? '';
      final cat = t['category'] ?? '-';
      final status = t['status'] ?? 'available';
      final notes = t['notes'] ?? '';

      final chunk = 'ข้อมูลเครื่องมือช่างและอุปกรณ์: $code - $name\n'
          'หมวดหมู่: $cat | สถานะปัจจุบัน: $status\n'
          'หมายเหตุ/สถานที่จัดเก็บ: $notes';

      final emb = await EmbeddingService.getEmbedding(chunk);
      if (emb.isNotEmpty) {
        await upsertVector(
          vectorId: 'vec_tool_$tId',
          sourceType: 'tool_equipment',
          sourceId: tId,
          title: '$code - $name',
          category: 'tools_equipment',
          contentChunk: chunk,
          embedding: emb,
          metadata: {
            'tool_code': code,
            'tool_name': name,
            'category': cat,
            'status': status,
          },
        );
        _log.i('[VectorDB] Auto-synced tool $code ($name) to Vector DB');
      }
    } catch (e) {
      _log.w('[VectorDB] Failed to auto-sync tool: $e');
    }
  }

  /// Automatically sync a Problem Solving / RCA / Action Plan to Vector DB
  static Future<void> syncProblemSolvingAndActionPlan(String rcaId) async {
    await ensureTable();
    try {
      final rows = await DbHelper.query(
        'SELECT * FROM problem_solving_records WHERE rca_id = @id',
        params: {'id': rcaId},
      );
      if (rows.isEmpty) return;

      final r = rows.first;
      final title = r['problem_title']?.toString() ?? 'Action Plan';
      final rootCause = r['root_cause']?.toString() ?? '';
      final w1 = r['why_1']?.toString() ?? '';
      final w2 = r['why_2']?.toString() ?? '';
      final w3 = r['why_3']?.toString() ?? '';
      final w4 = r['why_4']?.toString() ?? '';
      final w5 = r['why_5']?.toString() ?? '';
      final fMan = r['fishbone_man']?.toString() ?? '';
      final fMach = r['fishbone_machine']?.toString() ?? '';
      final fMat = r['fishbone_material']?.toString() ?? '';
      final fMet = r['fishbone_method']?.toString() ?? '';
      final fEnv = r['fishbone_env']?.toString() ?? '';
      final tMetric = r['target_metric']?.toString() ?? '';
      final bVal = r['before_value']?.toString() ?? '';
      final tVal = r['target_value']?.toString() ?? '';
      final aVal = r['actual_value']?.toString() ?? '';
      final unit = r['metric_unit']?.toString() ?? '';
      final vBy = r['verified_by']?.toString() ?? '';
      final vDate = r['verification_date']?.toString() ?? '';
      final vRes = r['verification_result']?.toString() ?? '';
      final sNotes = r['standardization_notes']?.toString() ?? '';
      final status = r['status']?.toString() ?? 'in_progress';

      String stepsText = '';
      if (r['action_steps_json'] != null && r['action_steps_json'].toString().isNotEmpty) {
        try {
          final decoded = jsonDecode(r['action_steps_json'].toString());
          if (decoded is List) {
            stepsText = decoded.map((s) {
              final st = s as Map<String, dynamic>;
              final sTitle = st['title'] ?? '';
              final sAssignee = st['assignee'] ?? '';
              final sDue = st['due_date'] ?? '';
              final sStatus = st['status'] ?? 'pending';
              return '- $sTitle (ผู้รับผิดชอบ: $sAssignee, กำหนดเสร็จ: $sDue, สถานะ: $sStatus)';
            }).join('\n');
          }
        } catch (_) {}
      }

      final chunk = 'แผนปฏิบัติการ & การแก้ปัญหา (Action Plan & RCA): $title\n'
          'สถานะแผนงาน: $status\n'
          'สาเหตุรากเหง้า (Root Cause): $rootCause\n'
          'การวิเคราะห์ 5-Why: [W1: $w1 -> W2: $w2 -> W3: $w3 -> W4: $w4 -> W5: $w5]\n'
          'ผังก้างปลา 4M1E: [คน: $fMan | เครื่องจักร: $fMach | วัตถุดิบ: $fMat | วิธีการ: $fMet | สิ่งแวดล้อม: $fEnv]\n'
          'ขั้นตอนแผนปฏิบัติการ (Action Steps):\n$stepsText\n'
          'การสอบทานผลสำเร็จ (Verification & Validation):\n'
          'ตัวชี้วัด: $tMetric | ก่อน: $bVal $unit | เป้าหมาย: $tVal $unit | ผลจริง: $aVal $unit\n'
          'ผลการประเมิน: $vRes โดย $vBy ($vDate)\n'
          'แผนคงสภาพ/มาตรฐานใหม่ (Standardization): $sNotes';

      final emb = await EmbeddingService.getEmbedding(chunk);
      if (emb.isNotEmpty) {
        await upsertVector(
          vectorId: 'vec_rca_$rcaId',
          sourceType: 'action_plan',
          sourceId: rcaId,
          title: title,
          category: 'action_plan',
          contentChunk: chunk,
          embedding: emb,
          metadata: {
            'rca_id': rcaId,
            'source_type': r['source_type'],
            'source_id': r['source_id'],
            'status': status,
            'target_metric': tMetric,
            'verification_result': vRes,
          },
        );
        _log.i('[VectorDB] Auto-synced Action Plan & RCA $title to Vector DB');
      }
    } catch (e) {
      _log.w('[VectorDB] Failed to auto-sync Action Plan: $e');
    }
  }

  /// Automatically sync a Technician's Skills, Certificates & Kaizen Portfolio to Vector DB
  static Future<void> syncTechnicianSkillAndPortfolio(String userId) async {
    await ensureTable();
    try {
      final uRows = await DbHelper.query('''
        SELECT u.user_id, u.employee_no, u.full_name, u.role, u.phone, u.email, u.is_active, d.dept_name
        FROM users u
        LEFT JOIN departments d ON d.dept_id = u.dept_id
        WHERE u.user_id = @id
        LIMIT 1
      ''', params: {'id': userId});
      if (uRows.isEmpty) return;

      final u = uRows.first;
      final empNo = u['employee_no']?.toString() ?? '-';
      final name = u['full_name']?.toString() ?? 'ช่างเทคนิค';
      final role = u['role']?.toString() ?? 'technician';
      final dept = u['dept_name']?.toString() ?? 'ฝ่ายซ่อมบำรุง';
      final phone = u['phone']?.toString() ?? '-';
      final email = u['email']?.toString() ?? '-';
      final isActive = u['is_active'] == 1 ? 'พร้อมปฏิบัติงาน (Active)' : 'หยุด/ลา (Inactive)';

      // 1. Fetch skills with proficiency and score
      final sRows = await DbHelper.query(
        'SELECT skill_name, proficiency_level, score FROM technician_skills WHERE technician_id = @id',
        params: {'id': userId},
      );
      final skillText = sRows.map((s) {
        final sName = s['skill_name'];
        final sProf = s['proficiency_level'] ?? 'intermediate';
        final sScore = s['score'] != null ? ' (คะแนน: ${s['score']}/100)' : '';
        return '$sName [ระดับ: $sProf$sScore]';
      }).join(', ');

      // 2. Fetch certificates
      final certRows = await DbHelper.query(
        "SELECT file_name, document_type FROM technician_attachments WHERE technician_id = @id AND document_type = 'certificate'",
        params: {'id': userId},
      );
      final certText = certRows.map((c) => c['file_name']?.toString()).whereType<String>().join(', ');

      // 3. Fetch completed Kaizen Action Plans & Work Orders
      final woDoneCount = await DbHelper.queryOne(
        "SELECT COUNT(*) as c FROM work_orders WHERE assigned_to = @id AND status = 'completed'",
        params: {'id': userId},
      );
      final completedWo = (woDoneCount?['c'] as int?) ?? 0;

      // 3.1 Fetch machines worked on
      final mcRows = await DbHelper.query('''
        SELECT DISTINCT m.machine_no, m.machine_name
        FROM work_orders wo
        JOIN machines m ON wo.machine_id = m.machine_id
        WHERE wo.assigned_to = @id
        LIMIT 10
      ''', params: {'id': userId});
      final machinesWorked = mcRows.map((m) => '${m['machine_no']} (${m['machine_name']})').join(', ');

      // 4. Calculate real Kaizen points, projects & badges from DB
      final planRows = await DbHelper.query('SELECT * FROM problem_solving_records');
      int kPoints = (completedWo * 20) + (sRows.length * 15);
      int completedProjects = 0;
      final badges = <String>[];
      bool hasRca = false;
      bool hasCycleTime = false;
      bool hasPreventive = false;
      double maxRed = 0.0;

      for (final pRow in planRows) {
        final stepsJson = pRow['action_steps_json']?.toString() ?? '';
        final verifiedBy = pRow['verified_by']?.toString() ?? '';
        final status = pRow['status']?.toString() ?? '';
        final vRes = pRow['verification_result']?.toString() ?? '';
        final srcType = pRow['source_type']?.toString() ?? '';
        final why1 = pRow['why_1']?.toString() ?? '';
        final fMan = pRow['fishbone_man']?.toString() ?? '';
        final stdNotes = pRow['standardization_notes']?.toString() ?? '';
        final red = (pRow['reduction_percentage'] as num?)?.toDouble() ?? 0.0;

        final isAssignee = stepsJson.contains(name) || (empNo.isNotEmpty && stepsJson.contains(empNo));
        final isVerifier = verifiedBy.contains(name);

        if (isAssignee || isVerifier) {
          if (why1.isNotEmpty || fMan.isNotEmpty) hasRca = true;
          if (srcType == 'line_balancing' || srcType == 'sop_step') hasCycleTime = true;
          if (stdNotes.isNotEmpty) hasPreventive = true;
          if (red > maxRed) maxRed = red;

          if (status == 'completed' || status == 'closed') {
            completedProjects++;
            kPoints += 100;
          }
          if (vRes == 'achieved') {
            kPoints += 200;
          }
        }
      }

      if (hasRca) badges.add('🛡️ RCA Specialist');
      if (hasCycleTime) badges.add('⚡ Cycle Time Buster');
      if (hasPreventive) badges.add('🔧 Preventive Master');
      if (completedProjects >= 2 || kPoints >= 250) badges.add('🌟 Kaizen Champion');
      if (maxRed >= 50.0) badges.add('🚀 High Impact (>50% Waste Cut)');

      final chunk = 'ข้อมูลบุคลากร, ช่างซ่อมบำรุง & ทักษะความเชี่ยวชาญ (Workforce & Technician Profile):\n'
          'ชื่อ-นามสกุล: $name | รหัสพนักงาน: $empNo | ตำแหน่ง/บทบาท: $role | สถานะ: $isActive\n'
          'แผนก: $dept | เบอร์โทรศัพท์: $phone | อีเมล: $email\n'
          'ทักษะความชำนาญและความสามารถ (Skill Matrix): ${skillText.isEmpty ? 'ยังไม่ระบุ' : skillText}\n'
          'เครื่องจักรที่เชี่ยวชาญ/เคยซ่อม: ${machinesWorked.isEmpty ? 'ทั่วไป' : machinesWorked}\n'
          'คะแนน Kaizen สะสม: $kPoints แต้ม | โครงการ Action Plan / RCA ที่ปิดสำเร็จ: $completedProjects โครงการ\n'
          'เหรียญเกียรติยศที่ได้รับ: ${badges.isEmpty ? 'กำลังสะสมผลงาน' : badges.join(', ')}\n'
          'ใบประกาศนียบัตร/ใบเซอร์: ${certText.isEmpty ? 'ไม่มีเอกสารแนบ' : certText}\n'
          'สถิติงานซ่อมบำรุงที่ปิดสำเร็จ: $completedWo งาน';

      final emb = await EmbeddingService.getEmbedding(chunk);
      if (emb.isNotEmpty) {
        await upsertVector(
          vectorId: 'vec_tech_$userId',
          sourceType: 'technician_profile',
          sourceId: userId,
          title: '$empNo - $name ($role)',
          category: 'workforce_skills',
          contentChunk: chunk,
          embedding: emb,
          metadata: {
            'user_id': userId,
            'employee_no': empNo,
            'full_name': name,
            'role': role,
            'phone': phone,
            'email': email,
            'department': dept,
            'kaizen_points': kPoints,
            'completed_projects': completedProjects,
            'badges': badges,
            'skills': sRows.map((s) => s['skill_name']).toList(),
          },
        );
        _log.i('[VectorDB] Auto-synced Technician Profile & Skill Matrix for $name to Vector DB');
      }
    } catch (e) {
      _log.w('[VectorDB] Failed to auto-sync technician profile: $e');
    }
  }

  /// Sync all technicians into Vector DB
  static Future<int> syncAllTechnicians() async {
    await ensureTable();
    int count = 0;
    try {
      final userRows = await DbHelper.query(
        "SELECT user_id FROM users WHERE is_active = 1 OR role IN ('technician', 'engineer', 'safety', 'operator')",
      );
      for (final u in userRows) {
        final uId = u['user_id']?.toString();
        if (uId != null && uId.isNotEmpty) {
          await syncTechnicianSkillAndPortfolio(uId);
          count++;
        }
      }
    } catch (e) {
      _log.e('Failed to sync all technicians: $e');
    }
    return count;
  }

  /// Automatically sync a Machine Weekly Plan / Allocation Schedule to Vector DB
  static Future<void> syncMachinePlan(String planId) async {
    await ensureTable();
    try {
      final pRows = await DbHelper.query(
        'SELECT * FROM machine_plans WHERE plan_id = @id LIMIT 1',
        params: {'id': planId},
      );
      if (pRows.isEmpty) return;

      final p = pRows.first;
      final weekStart = p['week_start_date']?.toString() ?? '';
      final weekEnd = p['week_end_date']?.toString() ?? '';
      final weekNo = p['week_number']?.toString() ?? '';
      final year = p['year']?.toString() ?? '';
      final status = p['status']?.toString() ?? 'draft';
      final notes = p['notes']?.toString() ?? '';

      // Fetch items in this plan
      final itemRows = await DbHelper.query(
        'SELECT * FROM machine_plan_items WHERE plan_id = @id ORDER BY building, order_index',
        params: {'id': planId},
      );

      final buffer = StringBuffer();
      buffer.writeln('แผนการใช้เครื่องจักรและจัดสรรการผลิตรายสัปดาห์ (Weekly Machine Allocation Plan):');
      buffer.writeln('สัปดาห์ที่: $weekNo/$year | ช่วงวันที่: $weekStart ถึง $weekEnd | สถานะ: $status');
      if (notes.isNotEmpty) buffer.writeln('หมายเหตุแผนงาน: $notes');
      buffer.writeln('รายการเครื่องจักรที่จัดสรรการผลิต (${itemRows.length} รายการ):');

      for (final item in itemRows) {
        final bld = item['building'] ?? 'ส่วนกลาง';
        final room = item['room'] ?? '-';
        final mCode = item['machine_code'] ?? '';
        final mName = item['machine_name'] ?? '';
        final line = item['line_name'] ?? '-';
        final st = item['station_name'] ?? '-';
        final remarks = item['remarks'] ?? '';

        String getDayStr(dynamic rawJson) {
          if (rawJson == null || rawJson.toString().isEmpty) return '-';
          try {
            final map = jsonDecode(rawJson.toString());
            final time = map['time']?.toString();
            final isOt = map['is_ot'] == true;
            if (time == null || time.isEmpty) return '-';
            return isOt ? '$time (OT)' : time;
          } catch (_) {
            return '-';
          }
        }

        final mon = getDayStr(item['day_mon_json']);
        final tue = getDayStr(item['day_tue_json']);
        final wed = getDayStr(item['day_wed_json']);
        final thu = getDayStr(item['day_thu_json']);
        final fri = getDayStr(item['day_fri_json']);
        final sat = getDayStr(item['day_sat_json']);
        final sun = getDayStr(item['day_sun_json']);

        buffer.writeln(
          '- [$bld] $mName ($mCode) | ห้อง: $room | สายการผลิต: $line (สถานี: $st)\n'
          '  ตารางเดินเครื่อง: จ: $mon | อ: $tue | พ: $wed | พฤ: $thu | ศ: $fri | ส: $sat | อา: $sun'
          '${remarks.toString().isNotEmpty ? ' | หมายเหตุ: $remarks' : ''}',
        );
      }

      final chunk = buffer.toString();
      final title = 'แผนการใช้เครื่องจักร สัปดาห์ W$weekNo ($weekStart - $weekEnd)';

      final emb = await EmbeddingService.getEmbedding(chunk);
      if (emb.isNotEmpty) {
        await upsertVector(
          vectorId: 'vec_mplan_$planId',
          sourceType: 'machine_plan',
          sourceId: planId,
          title: title,
          category: 'machine_planning',
          contentChunk: chunk,
          embedding: emb,
          metadata: {
            'plan_id': planId,
            'week_number': weekNo,
            'year': year,
            'week_start_date': weekStart,
            'week_end_date': weekEnd,
            'status': status,
            'total_machines': itemRows.length,
          },
        );
        _log.i('[VectorDB] Auto-synced Machine Weekly Plan $title to Vector DB');
      }
    } catch (e) {
      _log.w('[VectorDB] Failed to auto-sync machine plan: $e');
    }
  }

  /// Delete vector for a Machine Plan
  static Future<void> deleteMachinePlanVector(String planId) async {
    try {
      await DbHelper.execute(
        "DELETE FROM knowledge_vectors WHERE source_type = 'machine_plan' AND source_id = @id",
        params: {'id': planId},
      );
    } catch (_) {}
  }

  /// Sync all machine plans to Vector DB
  static Future<int> syncAllMachinePlans() async {
    await ensureTable();
    int count = 0;
    try {
      final rows = await DbHelper.query('SELECT plan_id FROM machine_plans');
      for (final r in rows) {
        final pId = r['plan_id']?.toString();
        if (pId != null && pId.isNotEmpty) {
          await syncMachinePlan(pId);
          count++;
        }
      }
    } catch (e) {
      _log.e('Failed to sync all machine plans: $e');
    }
    return count;
  }

  /// Index/Re-index historical Work Orders (RCA, Symptoms, Solutions), Machines, Spare Parts, Tools, and Lean Processes into Vector DB.
  static Future<int> indexHistoricalKnowledge() async {
    await ensureTable();
    int count = 0;

    try {
      // 1. Index Work Orders with solutions / symptoms / causes
      final woRows = await DbHelper.query('''
        SELECT wo.wo_id, wo.wo_no, wo.title, wo.description, wo.failure_symptom, wo.failure_cause, wo.closure_notes,
               wo.status, wo.priority, wo.machine_id,
               rca.root_cause, rca.correction_action AS action_taken, rca.preventive_action
        FROM work_orders wo
        LEFT JOIN work_order_rca rca ON wo.wo_id = rca.wo_id
        WHERE (wo.failure_symptom IS NOT NULL AND wo.failure_symptom != '')
           OR (wo.failure_cause IS NOT NULL AND wo.failure_cause != '')
           OR (rca.root_cause IS NOT NULL AND rca.root_cause != '')
           OR (rca.correction_action IS NOT NULL AND rca.correction_action != '')
           OR (wo.closure_notes IS NOT NULL AND wo.closure_notes != '')
           OR (wo.description IS NOT NULL AND wo.description != '')
      ''');

      for (final wo in woRows) {
        final woNo = wo['wo_no'] ?? '';
        final title = wo['title'] ?? 'ใบแจ้งซ่อม $woNo';
        final symptom = wo['failure_symptom'] ?? '';
        final cause = wo['failure_cause'] ?? wo['root_cause'] ?? '';
        final action = (wo['action_taken'] != null && wo['action_taken'].toString().isNotEmpty)
            ? wo['action_taken']
            : (wo['closure_notes'] ?? '');
        final preventive = wo['preventive_action'] ?? '';
        final desc = wo['description'] ?? '';

        final chunk = 'ใบแจ้งซ่อม: $woNo | หัวข้อ: $title\n'
            'อาการเสีย (Symptom): $symptom\n'
            'สาเหตุที่พบ (Cause/RCA): $cause\n'
            'วิธีแก้ไขและการซ่อม (Action Taken): $action\n'
            '${preventive.toString().isNotEmpty ? 'แนวทางป้องกัน (Preventive Action): $preventive\n' : ''}'
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
               s.power_kw, s.voltage_v, s.current_a, s.capacity, s.weight_kg, s.extra_specs
        FROM machines m
        LEFT JOIN machine_specs s ON m.machine_id = s.machine_id
      ''');

      for (final mc in mcRows) {
        final no = mc['machine_no'] ?? '';
        final name = mc['machine_name'] ?? '';
        final brand = mc['brand'] ?? '';
        final model = mc['model'] ?? '';
        final kw = mc['power_kw'] ?? '-';
        final v = mc['voltage_v'] ?? '-';
        final a = mc['current_a'] ?? '-';
        final cap = mc['capacity'] ?? '-';
        final w = mc['weight_kg'] ?? '-';

        final chunk = 'ข้อมูลเครื่องจักรและสเปก: $no ($name)\n'
            'ยี่ห้อ: $brand | รุ่น: $model\n'
            'กำลังไฟฟ้า: $kw kW | แรงดันไฟฟ้า: $v V | กระแสไฟฟ้า: $a A\n'
            'ความสามารถในการผลิต/ความจุ: $cap | น้ำหนักเครื่อง: $w kg';

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

      // 4. Index Spare Parts
      final partRows = await DbHelper.query('SELECT part_id FROM spare_parts WHERE is_active = 1');
      for (final part in partRows) {
        final pId = part['part_id']?.toString();
        if (pId != null && pId.isNotEmpty) {
          await syncSparePart(pId);
          count++;
        }
      }

      // 5. Index Tools & Equipment
      final toolRows = await DbHelper.query('SELECT tool_id FROM tools WHERE is_active = 1');
      for (final tool in toolRows) {
        final tId = tool['tool_id']?.toString();
        if (tId != null && tId.isNotEmpty) {
          await syncTool(tId);
          count++;
        }
      }

      // 6. Index Work Processes & Lean Analysis
      final wpRows = await DbHelper.query('SELECT process_id FROM work_processes');
      for (final wp in wpRows) {
        final pId = wp['process_id']?.toString();
        if (pId != null && pId.isNotEmpty) {
          await syncWorkProcess(pId);
          count++;
        }
      }

      // 7. Index Production Lines & Line Balancing
      final lineRows = await DbHelper.query('SELECT line_id FROM production_lines');
      for (final l in lineRows) {
        final lId = l['line_id']?.toString();
        if (lId != null && lId.isNotEmpty) {
          await syncLineBalancing(lId);
          count++;
        }
      }

      // 8. Index Problem Solving Records & Action Plans
      final rcaRows = await DbHelper.query('SELECT rca_id FROM problem_solving_records');
      for (final rca in rcaRows) {
        final rId = rca['rca_id']?.toString();
        if (rId != null && rId.isNotEmpty) {
          await syncProblemSolvingAndActionPlan(rId);
          count++;
        }
      }

      // 9. Index Technician Profiles, Skill Matrix & Achievements
      final userRows = await DbHelper.query('SELECT user_id FROM users WHERE is_active = 1');
      for (final u in userRows) {
        final uId = u['user_id']?.toString();
        if (uId != null && uId.isNotEmpty) {
          await syncTechnicianSkillAndPortfolio(uId);
          count++;
        }
      }

      // 10. Index Machine Weekly Allocation Plans
      final planRows = await DbHelper.query('SELECT plan_id FROM machine_plans');
      for (final p in planRows) {
        final pId = p['plan_id']?.toString();
        if (pId != null && pId.isNotEmpty) {
          await syncMachinePlan(pId);
          count++;
        }
      }
    } catch (e) {
      _log.e('Error during knowledge indexing: $e');
    }

    return count;
  }
}
