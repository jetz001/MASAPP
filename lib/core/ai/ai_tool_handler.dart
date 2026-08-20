import 'package:uuid/uuid.dart';
// lib/core/ai/ai_tool_handler.dart
// Executes SQL queries on behalf of the AI — database-first with optional external search.

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../database/db_helper.dart';
import 'vector_db_service.dart';

class AiToolHandler {
  // Tables the AI cannot query (sensitive)
  static const _blockedTables = {
    'users',
    'user_sessions',
    'audit_log',
    'app_settings',
    'ai_chat_history',
  };

  static const _dangerousKeywords = [
    'DROP',
    'DELETE',
    'UPDATE',
    'INSERT',
    'CREATE',
    'ALTER',
    'TRUNCATE',
    'REPLACE',
    'ATTACH',
    'DETACH',
    'PRAGMA',
  ];
  static const _requestTimeout = Duration(seconds: 12);
  static const _braveSearchApiKeySetting = 'brave_search_api_key';

  /// Handle a tool call from AI
  static Future<String> handleToolCall(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (toolName) {
        case 'query_database':
          return await _queryDatabase(args);
        case 'get_available_tables':
          return await _getAvailableTables();
        case 'get_table_schema':
          return await _getTableSchema(args);
        case 'search_vector_knowledge':
          return await _searchVectorKnowledge(args);
        case 'find_machine_assets':
          return await _findMachineAssets(args);
        case 'search_external_web':
          return await _searchExternalWeb(args);
        case 'search_external_images':
          return await _searchExternalImages(args);
                case 'register_machines':
          return await _registerMachines(args);
        case 'create_pm_plans':
          return await _createPmPlans(args);
        case 'register_spare_parts':
          return await _registerSpareParts(args);
        case 'create_work_order':
          return await _createWorkOrder(args);
        default:
          return '{"error": "Unknown tool: $toolName"}';
      }
    } catch (e) {
      return '{"error": "${_esc(e.toString())}"}';
    }
  }


  static Future<String> _registerMachines(Map<String, dynamic> args) async {
    final rawList = args['machines'];
    if (rawList is! List || rawList.isEmpty) {
      return jsonEncode({'error': 'Parameter "machines" must be a non-empty array.'});
    }

    int inserted = 0;
    int updated = 0;
    final details = <String>[];

    for (final item in rawList) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();

      final machineNo = map['machine_no']?.toString().trim() ?? '';
      if (machineNo.isEmpty) continue;

      final machineName = map['machine_name']?.toString().trim();
      final assetNo = map['asset_no']?.toString().trim();
      final brand = map['brand']?.toString().trim();
      final model = map['model']?.toString().trim();
      final serialNo = map['serial_no']?.toString().trim();
      final location = map['location']?.toString().trim();
      final status = map['status']?.toString().trim().toLowerCase() ?? 'normal';
      final notes = map['notes']?.toString().trim();

      // Check if machine already exists
      final existing = await DbHelper.queryOne(
        'SELECT machine_id FROM machines WHERE machine_no = @no OR (asset_no IS NOT NULL AND asset_no = @no)',
        params: {'no': machineNo},
      );

      String machineId;
      if (existing != null) {
        machineId = existing['machine_id'].toString();
        await DbHelper.execute('''
          UPDATE machines
          SET machine_name = COALESCE(@name, machine_name),
              asset_no = COALESCE(@asset, asset_no),
              brand = COALESCE(@brand, brand),
              model = COALESCE(@model, model),
              serial_no = COALESCE(@serial, serial_no),
              location = COALESCE(@loc, location),
              status = COALESCE(@status, status),
              notes = COALESCE(@notes, notes),
              updated_at = CURRENT_TIMESTAMP
          WHERE machine_id = @id
        ''', params: {
          'id': machineId,
          'name': machineName,
          'asset': assetNo,
          'brand': brand,
          'model': model,
          'serial': serialNo,
          'loc': location,
          'status': status,
          'notes': notes,
        });
        updated++;
      } else {
        machineId = const Uuid().v4();
        await DbHelper.execute('''
          INSERT INTO machines (
            machine_id, machine_no, machine_name, asset_no, brand, model,
            serial_no, location, status, is_active, notes, created_at, updated_at
          ) VALUES (
            @id, @no, @name, @asset, @brand, @model,
            @serial, @loc, @status, 1, @notes, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          )
        ''', params: {
          'id': machineId,
          'no': machineNo,
          'name': machineName,
          'asset': assetNo,
          'brand': brand,
          'model': model,
          'serial': serialNo,
          'loc': location,
          'status': status,
          'notes': notes,
        });
        inserted++;
      }

      // Specs
      if (map['specs'] is Map) {
        final specs = (map['specs'] as Map).cast<String, dynamic>();
        final specId = const Uuid().v4();
        await DbHelper.execute('''
          INSERT OR REPLACE INTO machine_specs (
            spec_id, machine_id, power_kw, voltage_v, current_a, capacity, updated_at
          ) VALUES (
            @sid, @mid, @power, @volt, @curr, @cap, CURRENT_TIMESTAMP
          )
        ''', params: {
          'sid': specId,
          'mid': machineId,
          'power': (specs['power_kw'] as num?)?.toDouble(),
          'volt': (specs['voltage_v'] as num?)?.toDouble(),
          'curr': (specs['current_a'] as num?)?.toDouble(),
          'cap': (specs['capacity'] as num?)?.toDouble(),
        });
      }

      details.add('$machineNo: ${machineName ?? brand ?? "เครื่องจักร"}');
    }

    return jsonEncode({
      'status': 'success',
      'inserted_count': inserted,
      'updated_count': updated,
      'total_processed': inserted + updated,
      'machines': details,
      'message': 'บันทึกข้อมูลเครื่องจักรลงฐานข้อมูลสำเร็จ (เพิ่มใหม่ $inserted, อัปเดต $updated เครื่อง)',
    });
  }


  static Future<String> _createPmPlans(Map<String, dynamic> args) async {
    final machineIdentifier = args['machine_identifier']?.toString().trim() ?? '';
    final planType = (args['plan_type']?.toString().trim().toUpperCase() == 'AM') ? 'AM' : 'PM';
    final planName = args['plan_name']?.toString().trim() ?? 'แผนบำรุงรักษาประจำเครื่อง';
    final frequencyDays = (args['frequency_days'] as num?)?.toInt() ?? 30;
    final tasks = args['tasks'];

    // Find machine
    final machine = await DbHelper.queryOne(
      'SELECT machine_id, machine_no, machine_name FROM machines WHERE machine_no = @id OR machine_id = @id LIMIT 1',
      params: {'id': machineIdentifier},
    );

    if (machine == null) {
      return jsonEncode({'error': 'ไม่พบเครื่องจักรที่มีรหัส/ชื่อ "$machineIdentifier"'});
    }

    final machineId = machine['machine_id'].toString();
    final machineNo = machine['machine_no'].toString();
    final planId = const Uuid().v4();
    final planCode = '$planType-$machineNo-${DateTime.now().millisecondsSinceEpoch % 10000}';

    await DbHelper.execute('''
      INSERT INTO pm_am_plans (
        plan_id, machine_id, plan_type, plan_code, plan_name,
        frequency_days, status, created_at, updated_at
      ) VALUES (
        @id, @mid, @type, @code, @name,
        @freq, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      )
    ''', params: {
      'id': planId,
      'mid': machineId,
      'type': planType,
      'code': planCode,
      'name': planName,
      'freq': frequencyDays,
    });

    int taskCount = 0;
    if (tasks is List && tasks.isNotEmpty) {
      for (int i = 0; i < tasks.length; i++) {
        final t = tasks[i];
        final taskName = (t is Map ? t['task_name'] : t)?.toString().trim() ?? '';
        if (taskName.isEmpty) continue;
        final taskType = (t is Map ? t['task_type']?.toString() : null) ?? 'inspect';
        final isCritical = (t is Map && t['is_critical'] == true) ? 1 : 0;

        await DbHelper.execute('''
          INSERT INTO pm_am_tasks (
            task_id, plan_id, task_order, task_name, task_type, is_critical, created_at
          ) VALUES (
            @tid, @pid, @order, @name, @type, @crit, CURRENT_TIMESTAMP
          )
        ''', params: {
          'tid': const Uuid().v4(),
          'pid': planId,
          'order': i + 1,
          'name': taskName,
          'type': taskType,
          'crit': isCritical,
        });
        taskCount++;
      }
    }

    return jsonEncode({
      'status': 'success',
      'plan_id': planId,
      'plan_code': planCode,
      'plan_name': planName,
      'machine_no': machineNo,
      'tasks_created': taskCount,
      'message': 'สร้างแผนแม่บท $planType ($planCode) สำหรับเครื่อง $machineNo สำเร็จ พร้อมรายการตรวจเช็ค $taskCount รายการ',
    });
  }

  static Future<String> _registerSpareParts(Map<String, dynamic> args) async {
    final rawParts = args['parts'];
    if (rawParts is! List || rawParts.isEmpty) {
      return jsonEncode({'error': 'Parameter "parts" must be a non-empty array.'});
    }

    final machineIdentifier = args['machine_identifier']?.toString().trim();
    String? linkedMachineId;
    if (machineIdentifier != null && machineIdentifier.isNotEmpty) {
      final machine = await DbHelper.queryOne(
        'SELECT machine_id FROM machines WHERE machine_no = @id OR machine_id = @id LIMIT 1',
        params: {'id': machineIdentifier},
      );
      linkedMachineId = machine?['machine_id']?.toString();
    }

    int inserted = 0;
    final partNames = <String>[];

    for (final item in rawParts) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();

      final partCode = map['part_code']?.toString().trim() ?? 'PART-${DateTime.now().millisecondsSinceEpoch % 100000}';
      final partName = map['part_name']?.toString().trim() ?? '';
      if (partName.isEmpty) continue;

      final category = map['category']?.toString().trim();
      final unitCost = (map['unit_cost'] as num?)?.toDouble() ?? 0.0;
      final reorderLevel = (map['reorder_level'] as num?)?.toInt() ?? 5;
      final initialQty = (map['initial_quantity'] as num?)?.toInt() ?? 0;

      final existing = await DbHelper.queryOne(
        'SELECT part_id FROM spare_parts WHERE part_code = @code LIMIT 1',
        params: {'code': partCode},
      );

      String partId;
      if (existing != null) {
        partId = existing['part_id'].toString();
      } else {
        partId = const Uuid().v4();
        await DbHelper.execute('''
          INSERT INTO spare_parts (
            part_id, part_code, part_name, category, unit_cost, reorder_level, is_active, created_at
          ) VALUES (
            @id, @code, @name, @cat, @cost, @reorder, 1, CURRENT_TIMESTAMP
          )
        ''', params: {
          'id': partId,
          'code': partCode,
          'name': partName,
          'cat': category,
          'cost': unitCost,
          'reorder': reorderLevel,
        });

        // Create inventory record
        await DbHelper.execute('''
          INSERT OR IGNORE INTO spare_parts_inventory (
            inventory_id, part_id, quantity_on_hand, quantity_reserved, updated_at
          ) VALUES (
            @invid, @pid, @qty, 0, CURRENT_TIMESTAMP
          )
        ''', params: {
          'invid': const Uuid().v4(),
          'pid': partId,
          'qty': initialQty,
        });
        inserted++;
      }

      // Link to machine if requested
      if (linkedMachineId != null) {
        await DbHelper.execute('''
          INSERT OR IGNORE INTO part_machine_map (map_id, part_id, machine_id, quantity)
          VALUES (@mid, @pid, @machid, 1)
        ''', params: {
          'mid': const Uuid().v4(),
          'pid': partId,
          'machid': linkedMachineId,
        });
      }

      partNames.add('$partCode: $partName');
    }

    return jsonEncode({
      'status': 'success',
      'inserted_count': inserted,
      'parts': partNames,
      'message': 'บันทึกรายการอะไหล่สำเร็จ $inserted รายการ',
    });
  }

  static Future<String> _createWorkOrder(Map<String, dynamic> args) async {
    final title = args['title']?.toString().trim() ?? 'แจ้งซ่อมเครื่องจักร';
    final machineIdentifier = args['machine_identifier']?.toString().trim() ?? '';
    final symptom = args['symptom']?.toString().trim() ?? '';
    final priority = args['priority']?.toString().trim().toLowerCase() ?? 'normal';
    final description = args['description']?.toString().trim() ?? symptom;

    // Find machine
    final machine = await DbHelper.queryOne(
      'SELECT machine_id, machine_no, machine_name FROM machines WHERE machine_no = @id OR machine_id = @id LIMIT 1',
      params: {'id': machineIdentifier},
    );

    final machineId = machine?['machine_id']?.toString() ?? 'GENERAL';
    final machineNo = machine?['machine_no']?.toString() ?? 'ทั่วไป';

    // Auto-generate WO No
    final year = DateTime.now().year;
    final countRow = await DbHelper.queryOne(
      "SELECT COUNT(*) as c FROM work_orders WHERE wo_no LIKE 'WO-$year-%'",
    );
    final nextNum = ((countRow?['c'] as num?)?.toInt() ?? 0) + 1;
    final woNo = 'WO-$year-${nextNum.toString().padLeft(5, '0')}';
    final woId = const Uuid().v4();

    // Default admin user id for system creation
    final adminUser = await DbHelper.queryOne("SELECT user_id FROM users LIMIT 1");
    final createdBy = adminUser?['user_id']?.toString() ?? 'U-ADMIN';

    await DbHelper.execute('''
      INSERT INTO work_orders (
        wo_id, wo_no, machine_id, status, priority, title,
        description, failure_symptom, created_by, created_at, updated_at
      ) VALUES (
        @id, @no, @mid, 'pending', @pri, @title,
        @desc, @sym, @by, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      )
    ''', params: {
      'id': woId,
      'no': woNo,
      'mid': machineId,
      'pri': priority,
      'title': title,
      'desc': description,
      'sym': symptom,
      'by': createdBy,
    });

    // Auto-sync to Vector DB
    VectorDbService.syncWorkOrder(woId);

    return jsonEncode({
      'status': 'success',
      'wo_id': woId,
      'wo_no': woNo,
      'title': title,
      'machine_no': machineNo,
      'priority': priority,
      'message': 'เปิดใบแจ้งซ่อมเลขที่ $woNo ($title) สำหรับเครื่อง $machineNo เรียบร้อยแล้ว',
    });
  }

  static Future<String> _searchVectorKnowledge(Map<String, dynamic> args) async {
    final query = (args['query'] as String? ?? '').trim();
    final category = args['category'] as String?;
    final topK = (args['top_k'] as num?)?.toInt() ?? 5;
    if (query.isEmpty) return '{"error": "Query cannot be empty"}';

    final results = await VectorDbService.searchSimilar(
      query,
      topK: topK,
      category: category,
    );

    if (results.isEmpty) {
      return '{"results": [], "count": 0, "message": "No matching knowledge vectors found"}';
    }

    return jsonEncode({
      'results': results.map((r) => r.toMap()).toList(),
      'count': results.length,
    });
  }

  static Future<String> _queryDatabase(Map<String, dynamic> args) async {
    final sql = (args['sql'] as String? ?? '').trim();
    final upper = sql.toUpperCase();

    if (!(upper.startsWith('SELECT') || upper.startsWith('WITH'))) {
      return '{"error": "Only SELECT or WITH ... SELECT statements are allowed."}';
    }

    for (final kw in _dangerousKeywords) {
      if (RegExp(
        r'(^|\s)' + kw + r'(\s|$)',
        caseSensitive: false,
      ).hasMatch(sql)) {
        return '{"error": "Forbidden keyword: $kw"}';
      }
    }

    final tables = _extractTables(sql);
    final readableTables = await _getReadableTables();
    for (final t in tables) {
      if (_blockedTables.contains(t)) {
        return '{"error": "Access to table \'$t\' is restricted."}';
      }
      if (!readableTables.contains(t)) {
        return '{"error": "Table \'$t\' is not available in this database."}';
      }
    }

    final limited = upper.contains('LIMIT') ? sql : '$sql LIMIT 200';
    final rows = await DbHelper.query(limited);
    if (rows.isEmpty) return '{"result":[],"count":0,"note":"No data found"}';
    return '{"result":${_rowsToJson(rows)},"count":${rows.length}}';
  }

  static Future<String> _getAvailableTables() async {
    final buf = StringBuffer('{"tables":{');
    var first = true;
    for (final t in await _getReadableTables()) {
      final cols = await DbHelper.query(
        "SELECT name FROM pragma_table_info('$t') LIMIT 30",
      );
      if (cols.isEmpty) continue;
      if (!first) buf.write(',');
      final names = cols.map((c) => '"${c['name']}"').join(',');
      buf.write('"$t":[$names]');
      first = false;
    }
    buf.write('}}');
    return buf.toString();
  }

  static Future<String> _getTableSchema(Map<String, dynamic> args) async {
    final t = (args['table_name'] as String? ?? '').toLowerCase().trim();
    if (_blockedTables.contains(t)) return '{"error":"Table $t is restricted"}';
    final readableTables = await _getReadableTables();
    if (!readableTables.contains(t)) return '{"error":"Table $t not found"}';
    final cols = await DbHelper.query(
      "SELECT name, type, pk FROM pragma_table_info('$t')",
    );
    if (cols.isEmpty) return '{"error":"Table $t not found"}';
    final j = cols
        .map(
          (c) =>
              '{"name":"${c['name']}","type":"${c['type']}","pk":${c['pk']}}',
        )
        .join(',');
    return '{"table":"$t","columns":[$j]}';
  }

  static Future<String> _findMachineAssets(Map<String, dynamic> args) async {
    final query = (args['query'] as String? ?? '').trim();
    final assetType = (args['asset_type'] as String? ?? 'all').trim();

    if (query.isEmpty) {
      return _json({'error': 'Query is required for machine asset lookup.'});
    }

    final like = '%${query.toLowerCase()}%';
    final machines = await DbHelper.query(
      '''
      SELECT machine_id, machine_no, machine_name, asset_no, brand, model, serial_no, location, status
      FROM machines
      WHERE LOWER(machine_no) = LOWER(@query)
         OR LOWER(COALESCE(asset_no, '')) = LOWER(@query)
         OR LOWER(COALESCE(serial_no, '')) = LOWER(@query)
         OR LOWER(machine_no) LIKE @like
         OR LOWER(COALESCE(machine_name, '')) LIKE @like
         OR LOWER(COALESCE(asset_no, '')) LIKE @like
         OR LOWER(COALESCE(brand, '')) LIKE @like
         OR LOWER(COALESCE(model, '')) LIKE @like
         OR LOWER(COALESCE(serial_no, '')) LIKE @like
      ORDER BY
        CASE
          WHEN LOWER(machine_no) = LOWER(@query) THEN 0
          WHEN LOWER(COALESCE(asset_no, '')) = LOWER(@query) THEN 1
          WHEN LOWER(COALESCE(serial_no, '')) = LOWER(@query) THEN 2
          WHEN LOWER(COALESCE(machine_name, '')) LIKE @like THEN 3
          ELSE 4
        END,
        updated_at DESC,
        created_at DESC
      LIMIT 5
      ''',
      params: {'query': query, 'like': like},
    );

    if (machines.isEmpty) {
      return _json({
        'query': query,
        'count': 0,
        'note': 'No machine matched this query.',
        'machines': const [],
      });
    }

    final results = <Map<String, dynamic>>[];
    for (final machine in machines) {
      final machineId = machine['machine_id']?.toString() ?? '';
      if (machineId.isEmpty) continue;

      final fileAssetRows = await DbHelper.query(
        '''
        SELECT
          fa.asset_id,
          fa.display_name,
          fa.storage_path,
          fa.source_path,
          fa.preview_path,
          fa.thumbnail_path,
          fa.mime_type,
          fa.file_ext,
          fa.file_size,
          fa.page_count,
          fa.category,
          fa.is_primary,
          fa.created_at,
          fa.updated_at,
          h.stage
        FROM machine_handover h
        JOIN file_assets fa
          ON fa.module_type = 'machine_handover'
         AND fa.entity_id = h.handover_id
        WHERE h.machine_id = @machineId
          ${_machineAssetFilterClause(assetType)}
        ORDER BY
          CASE WHEN fa.is_primary = 1 THEN 0 ELSE 1 END,
          COALESCE(fa.updated_at, fa.created_at) DESC
        LIMIT 100
        ''',
        params: {'machineId': machineId},
      );

      final legacyRows = fileAssetRows.isEmpty
          ? await DbHelper.query(
              '''
              SELECT
                a.attachment_id AS asset_id,
                a.file_name AS display_name,
                a.file_path AS storage_path,
                a.file_path AS source_path,
                '' AS preview_path,
                '' AS thumbnail_path,
                a.mime_type,
                '' AS file_ext,
                a.file_size,
                NULL AS page_count,
                'attachment' AS category,
                0 AS is_primary,
                a.uploaded_at AS created_at,
                a.uploaded_at AS updated_at,
                h.stage
              FROM handover_attachments a
              JOIN machine_handover h ON h.handover_id = a.handover_id
              WHERE h.machine_id = @machineId
              ORDER BY a.uploaded_at DESC
              LIMIT 100
              ''',
              params: {'machineId': machineId},
            )
          : const <Map<String, dynamic>>[];

      final assets = (fileAssetRows.isNotEmpty ? fileAssetRows : legacyRows)
          .map(
            (row) => {
              'asset_id': row['asset_id']?.toString() ?? '',
              'title': row['display_name']?.toString() ?? '',
              'path': row['storage_path']?.toString() ?? '',
              'source_path': row['source_path']?.toString() ?? '',
              'preview_path': row['preview_path']?.toString() ?? '',
              'thumbnail_path': row['thumbnail_path']?.toString() ?? '',
              'mime_type': row['mime_type']?.toString() ?? '',
              'file_ext': row['file_ext']?.toString() ?? '',
              'file_size': row['file_size'],
              'page_count': row['page_count'],
              'category': row['category']?.toString() ?? '',
              'stage': row['stage']?.toString() ?? '',
              'is_primary': row['is_primary'],
              'created_at': row['created_at']?.toString() ?? '',
              'updated_at': row['updated_at']?.toString() ?? '',
            },
          )
          .where((row) => (row['path'] as String).trim().isNotEmpty)
          .toList();

      results.add({
        'machine_id': machineId,
        'machine_no': machine['machine_no']?.toString() ?? '',
        'machine_name': machine['machine_name']?.toString() ?? '',
        'asset_no': machine['asset_no']?.toString() ?? '',
        'brand': machine['brand']?.toString() ?? '',
        'model': machine['model']?.toString() ?? '',
        'serial_no': machine['serial_no']?.toString() ?? '',
        'location': machine['location']?.toString() ?? '',
        'status': machine['status']?.toString() ?? '',
        'asset_count': assets.length,
        'assets': assets,
      });
    }

    return _json({
      'query': query,
      'asset_type': assetType,
      'count': results.length,
      'machines': results,
    });
  }

  static Future<String> _searchExternalWeb(Map<String, dynamic> args) async {
    final query = (args['query'] as String? ?? '').trim();
    final dbContext = (args['db_context'] as String? ?? '').trim();
    final whyExternal = (args['why_external_needed'] as String? ?? '').trim();
    final maxResults = _intArg(
      args['max_results'],
      fallback: 5,
      min: 1,
      max: 8,
    );

    if (query.isEmpty) {
      return _json({'error': 'Query is required for external web search.'});
    }
    if (dbContext.isEmpty || whyExternal.isEmpty) {
      return _json({
        'error':
            'DB-first policy: provide db_context and why_external_needed before using external search.',
      });
    }

    final braveApiKey = await _getSetting(_braveSearchApiKeySetting);
    if (braveApiKey != null && braveApiKey.trim().isNotEmpty) {
      final braveResults = await _searchBraveWeb(
        query: query,
        maxResults: maxResults,
        apiKey: braveApiKey.trim(),
      );
      if (braveResults.isNotEmpty) {
        return _externalResponse(
          provider: 'brave_search',
          query: query,
          dbContext: dbContext,
          whyExternalNeeded: whyExternal,
          results: braveResults,
        );
      }
    }

    final wikipediaResults = await _searchWikipediaThaiFirst(query, maxResults);
    if (wikipediaResults.isNotEmpty) {
      return _externalResponse(
        provider: 'wikipedia',
        query: query,
        dbContext: dbContext,
        whyExternalNeeded: whyExternal,
        results: wikipediaResults,
      );
    }

    final duckDuckGoResults = await _searchDuckDuckGoInstant(query, maxResults);
    return _externalResponse(
      provider: 'duckduckgo_instant_answer',
      query: query,
      dbContext: dbContext,
      whyExternalNeeded: whyExternal,
      results: duckDuckGoResults,
    );
  }

  static Future<String> _searchExternalImages(Map<String, dynamic> args) async {
    final query = (args['query'] as String? ?? '').trim();
    final dbContext = (args['db_context'] as String? ?? '').trim();
    final whyExternal = (args['why_external_needed'] as String? ?? '').trim();
    final maxResults = _intArg(
      args['max_results'],
      fallback: 4,
      min: 1,
      max: 6,
    );

    if (query.isEmpty) {
      return _json({'error': 'Query is required for external image search.'});
    }
    if (dbContext.isEmpty || whyExternal.isEmpty) {
      return _json({
        'error':
            'DB-first policy: provide db_context and why_external_needed before using external image search.',
      });
    }

    final results = await _searchWikimediaCommonsImages(query, maxResults);
    return _externalResponse(
      provider: 'wikimedia_commons',
      query: query,
      dbContext: dbContext,
      whyExternalNeeded: whyExternal,
      results: results,
    );
  }

  static Future<List<String>> _getReadableTables() async {
    final rows = await DbHelper.query('''
      SELECT name
      FROM sqlite_master
      WHERE type = 'table'
        AND name NOT LIKE 'sqlite_%'
      ORDER BY name
      ''');

    return rows
        .map((row) => row['name']?.toString().toLowerCase() ?? '')
        .where((name) => name.isNotEmpty && !_blockedTables.contains(name))
        .toList();
  }

  static Set<String> _extractTables(String sql) {
    final tables = <String>{};
    final pat = RegExp(r'(?:FROM|JOIN)\s+([a-zA-Z_]\w*)', caseSensitive: false);
    for (final m in pat.allMatches(sql)) {
      if (m.groupCount >= 1) tables.add(m.group(1)!.toLowerCase());
    }
    return tables;
  }

  static String _machineAssetFilterClause(String assetType) {
    switch (assetType.trim().toLowerCase()) {
      case 'image':
      case 'images':
      case 'photo':
      case 'photos':
        return '''
          AND (
            fa.category = 'image'
            OR LOWER(COALESCE(fa.mime_type, '')) LIKE 'image/%'
            OR LOWER(COALESCE(fa.file_ext, '')) IN ('.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp')
          )
        ''';
      case 'pdf':
        return '''
          AND (
            LOWER(COALESCE(fa.mime_type, '')) = 'application/pdf'
            OR LOWER(COALESCE(fa.file_ext, '')) = '.pdf'
          )
        ''';
      case 'document':
      case 'documents':
      case 'manual':
      case 'manuals':
        return '''
          AND (
            fa.category = 'attachment'
            OR LOWER(COALESCE(fa.mime_type, '')) IN (
              'application/pdf',
              'application/msword',
              'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
            )
            OR LOWER(COALESCE(fa.file_ext, '')) IN ('.pdf', '.doc', '.docx')
          )
        ''';
      default:
        return '';
    }
  }

  static Future<List<Map<String, dynamic>>> _searchBraveWeb({
    required String query,
    required int maxResults,
    required String apiKey,
  }) async {
    try {
      final uri = Uri.parse('https://api.search.brave.com/res/v1/web/search')
          .replace(
            queryParameters: {
              'q': query,
              'count': '$maxResults',
              'search_lang': 'th',
            },
          );
      final response = await http
          .get(
            uri,
            headers: {
              'Accept': 'application/json',
              'X-Subscription-Token': apiKey,
            },
          )
          .timeout(_requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final web = (json['web'] as Map?)?.cast<String, dynamic>() ?? {};
      final rawResults = (web['results'] as List?) ?? const [];

      return rawResults
          .cast<Map>()
          .map((raw) => raw.cast<String, dynamic>())
          .map(
            (item) => {
              'title': item['title']?.toString() ?? '',
              'url': item['url']?.toString() ?? '',
              'snippet': item['description']?.toString() ?? '',
              'source': 'Brave Search',
            },
          )
          .where((item) => (item['url'] as String).isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _searchWikipediaThaiFirst(
    String query,
    int maxResults,
  ) async {
    final thaiResults = await _searchWikipedia(
      'th.wikipedia.org',
      query,
      maxResults,
      'Wikipedia (TH)',
    );
    if (thaiResults.isNotEmpty) {
      return thaiResults;
    }

    return _searchWikipedia(
      'en.wikipedia.org',
      query,
      maxResults,
      'Wikipedia (EN)',
    );
  }

  static Future<List<Map<String, dynamic>>> _searchWikipedia(
    String host,
    String query,
    int maxResults,
    String sourceLabel,
  ) async {
    try {
      final uri = Uri.parse('https://$host/w/api.php').replace(
        queryParameters: {
          'action': 'query',
          'format': 'json',
          'list': 'search',
          'srsearch': query,
          'srlimit': '$maxResults',
          'utf8': '1',
          'origin': '*',
        },
      );

      final response = await http.get(uri).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final queryJson = (json['query'] as Map?)?.cast<String, dynamic>() ?? {};
      final results = (queryJson['search'] as List?) ?? const [];

      return results
          .cast<Map>()
          .map((raw) => raw.cast<String, dynamic>())
          .map((item) {
            final title = item['title']?.toString() ?? '';
            return {
              'title': title,
              'url':
                  "https://$host/wiki/${Uri.encodeComponent(title.replaceAll(' ', '_'))}",
              'snippet': _stripHtml(item['snippet']?.toString() ?? ''),
              'source': sourceLabel,
            };
          })
          .where((item) => (item['title'] as String).isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> _searchDuckDuckGoInstant(
    String query,
    int maxResults,
  ) async {
    try {
      final uri = Uri.parse('https://api.duckduckgo.com/').replace(
        queryParameters: {
          'q': query,
          'format': 'json',
          'no_html': '1',
          'skip_disambig': '0',
        },
      );
      final response = await http.get(uri).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final items = <Map<String, dynamic>>[];

      final abstractText = json['AbstractText']?.toString() ?? '';
      final abstractUrl = json['AbstractURL']?.toString() ?? '';
      final heading = json['Heading']?.toString() ?? query;
      if (abstractText.isNotEmpty && abstractUrl.isNotEmpty) {
        items.add({
          'title': heading,
          'url': abstractUrl,
          'snippet': abstractText,
          'source': 'DuckDuckGo Instant Answer',
        });
      }

      _appendDuckDuckGoTopics(
        topics: (json['RelatedTopics'] as List?) ?? const [],
        into: items,
        remaining: maxResults - items.length,
      );
      return items.take(maxResults).toList();
    } catch (_) {
      return [];
    }
  }

  static void _appendDuckDuckGoTopics({
    required List topics,
    required List<Map<String, dynamic>> into,
    required int remaining,
  }) {
    if (remaining <= 0) return;

    for (final topic in topics) {
      if (into.length >= remaining) break;
      if (topic is! Map) continue;
      final item = topic.cast<String, dynamic>();
      if (item.containsKey('Topics')) {
        _appendDuckDuckGoTopics(
          topics: (item['Topics'] as List?) ?? const [],
          into: into,
          remaining: remaining,
        );
        continue;
      }

      final url = item['FirstURL']?.toString() ?? '';
      final text = item['Text']?.toString() ?? '';
      if (url.isEmpty || text.isEmpty) continue;

      into.add({
        'title': text.split(' - ').first.split('  ').first.trim(),
        'url': url,
        'snippet': text,
        'source': 'DuckDuckGo Instant Answer',
      });
    }
  }

  static Future<List<Map<String, dynamic>>> _searchWikimediaCommonsImages(
    String query,
    int maxResults,
  ) async {
    try {
      final uri = Uri.parse('https://commons.wikimedia.org/w/api.php').replace(
        queryParameters: {
          'action': 'query',
          'format': 'json',
          'generator': 'search',
          'gsrsearch': query,
          'gsrnamespace': '6',
          'gsrlimit': '$maxResults',
          'prop': 'imageinfo',
          'iiprop': 'url|extmetadata',
          'iiurlwidth': '800',
          'origin': '*',
        },
      );

      final response = await http.get(uri).timeout(_requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final queryJson = (json['query'] as Map?)?.cast<String, dynamic>() ?? {};
      final pages = (queryJson['pages'] as Map?)?.cast<String, dynamic>() ?? {};

      final items = pages.values
          .whereType<Map>()
          .map((raw) => raw.cast<String, dynamic>())
          .map((page) {
            final imageInfoList = (page['imageinfo'] as List?) ?? const [];
            final imageInfo =
                imageInfoList.isNotEmpty && imageInfoList.first is Map
                ? (imageInfoList.first as Map).cast<String, dynamic>()
                : <String, dynamic>{};
            final metadata =
                (imageInfo['extmetadata'] as Map?)?.cast<String, dynamic>() ??
                {};
            return {
              'title': (page['title']?.toString() ?? '').replaceFirst(
                'File:',
                '',
              ),
              'url':
                  imageInfo['descriptionurl']?.toString() ??
                  imageInfo['url']?.toString() ??
                  '',
              'image_url':
                  imageInfo['thumburl']?.toString() ??
                  imageInfo['url']?.toString() ??
                  '',
              'thumbnail':
                  imageInfo['thumburl']?.toString() ??
                  imageInfo['url']?.toString() ??
                  '',
              'snippet': _extractMetadataValue(metadata['ImageDescription']),
              'license':
                  _extractMetadataValue(metadata['LicenseShortName']) ??
                  _extractMetadataValue(metadata['UsageTerms']),
              'source': 'Wikimedia Commons',
            };
          })
          .where((item) => (item['image_url'] as String).isNotEmpty)
          .toList();

      return items;
    } catch (_) {
      return [];
    }
  }

  static String _externalResponse({
    required String provider,
    required String query,
    required String dbContext,
    required String whyExternalNeeded,
    required List<Map<String, dynamic>> results,
  }) {
    return _json({
      'source_scope': 'external',
      'external_notice':
          'ข้อมูลภายนอก: ผลลัพธ์ชุดนี้มาจากแหล่งภายนอก ไม่ใช่ข้อมูลในฐาน MASAPP',
      'provider': provider,
      'query': query,
      'db_first_context': dbContext,
      'why_external_needed': whyExternalNeeded,
      'count': results.length,
      'results': results,
    });
  }

  static int _intArg(
    Object? raw, {
    required int fallback,
    required int min,
    required int max,
  }) {
    final parsed = raw is num
        ? raw.toInt()
        : int.tryParse(raw?.toString() ?? '');
    if (parsed == null) return fallback;
    if (parsed < min) return min;
    if (parsed > max) return max;
    return parsed;
  }

  static Future<String?> _getSetting(String key) async {
    final row = await DbHelper.queryOne(
      'SELECT setting_value FROM app_settings WHERE setting_key = @key',
      params: {'key': key},
    );
    final value = row?['setting_value']?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  static String _stripHtml(String input) {
    return input
        .replaceAll(RegExp(r'<[^>]+>'), ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _extractMetadataValue(Object? raw) {
    if (raw is Map) {
      final value = raw['value']?.toString() ?? '';
      final cleaned = _stripHtml(value);
      return cleaned.isEmpty ? null : cleaned;
    }
    final text = raw?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static String _json(Map<String, dynamic> value) => jsonEncode(value);

  static String _rowsToJson(List<Map<String, dynamic>> rows) {
    final items = rows
        .map((row) {
          final pairs = row.entries
              .map((e) {
                final v = e.value;
                if (v == null) return '"${e.key}":null';
                if (v is num || v is bool) return '"${e.key}":$v';
                return '"${e.key}":"${_esc(v.toString())}"';
              })
              .join(',');
          return '{$pairs}';
        })
        .join(',');
    return '[$items]';
  }

  static String _esc(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('"', '\\"')
      .replaceAll('\n', '\\n')
      .replaceAll('\r', '\\r');
}
