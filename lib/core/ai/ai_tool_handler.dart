import 'dart:io';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

import '../database/db_helper.dart';
import '../storage/attachment_storage_service.dart';
import 'rag_document_service.dart';
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
  static const _requestTimeout = Duration(seconds: 60);
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
        case 'extract_document_text':
        case 'read_document_text':
          return await _extractDocumentText(args);
        case 'find_machine_assets':
          return await _findMachineAssets(args);
        case 'manage_machine_assets':
        case 'attach_machine_document':
          return await _manageMachineAssets(args);
        case 'search_external_web':
          return await _searchExternalWeb(args);
        case 'search_external_images':
          return await _searchExternalImages(args);
        case 'manage_machines':
        case 'register_machines':
          return await _manageMachines(args);
        case 'manage_locations':
          return await _manageLocations(args);
        case 'manage_pm_plans':
        case 'create_pm_plans':
          return await _managePmPlans(args);
        case 'manage_pm_schedules':
          return await _managePmSchedules(args);
        case 'manage_work_orders':
        case 'create_work_order':
          return await _manageWorkOrders(args);
        case 'manage_contractors':
          return await _manageContractors(args);
        case 'manage_work_permits':
          return await _manageWorkPermits(args);
        case 'manage_spare_parts':
        case 'register_spare_parts':
          return await _manageSpareParts(args);
        case 'manage_tools':
          return await _manageTools(args);
        case 'manage_oee_logs':
          return await _manageOeeLogs(args);
        case 'manage_technicians':
          return await _manageTechnicians(args);
        case 'manage_work_processes':
        case 'import_work_processes':
        case 'manage_sop_steps':
          return await _manageWorkProcesses(args);
        default:
          return '{"error": "Unknown tool: $toolName"}';
      }
    } catch (e) {
      return '{"error": "${_esc(e.toString())}"}';
    }
  }


  // ── Helper Entity Finders ──────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> _findMachine(String identifier) async {
    if (identifier.trim().isEmpty) return null;
    final id = identifier.trim();

    // 1. Direct match
    final exact = await DbHelper.queryOne(
      'SELECT * FROM machines WHERE machine_no = @id OR machine_id = @id OR asset_no = @id LIMIT 1',
      params: {'id': id},
    );
    if (exact != null) return exact;

    // 2. Normalized alphanumeric match (e.g. "DP 01" matches "DP-01" or "DP01")
    final normInput = id.toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');
    final allMachines = await DbHelper.query('SELECT * FROM machines WHERE is_active = 1 OR is_active IS NULL');
    for (final m in allMachines) {
      final mNo = (m['machine_no'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');
      final aNo = (m['asset_no'] ?? '').toString().toLowerCase().replaceAll(RegExp(r'[\s\-_]+'), '');
      if (mNo == normInput || aNo == normInput) {
        return m;
      }
    }

    // 3. Fallback LIKE match
    return await DbHelper.queryOne(
      'SELECT * FROM machines WHERE machine_name LIKE @like OR machine_no LIKE @like LIMIT 1',
      params: {'like': '%$id%'},
    );
  }

  static Future<Map<String, dynamic>?> _findUser(String identifier) async {
    if (identifier.trim().isEmpty) return null;
    final id = identifier.trim();
    return await DbHelper.queryOne(
      'SELECT * FROM users WHERE user_id = @id OR username = @id OR employee_no = @id OR full_name LIKE @like LIMIT 1',
      params: {'id': id, 'like': '%$id%'},
    );
  }

  static Future<Map<String, dynamic>?> _findPart(String identifier) async {
    if (identifier.trim().isEmpty) return null;
    final id = identifier.trim();
    return await DbHelper.queryOne(
      'SELECT * FROM spare_parts WHERE part_code = @id OR part_id = @id OR part_name LIKE @like LIMIT 1',
      params: {'id': id, 'like': '%$id%'},
    );
  }

  static Future<Map<String, dynamic>?> _findTool(String identifier) async {
    if (identifier.trim().isEmpty) return null;
    final id = identifier.trim();
    return await DbHelper.queryOne(
      'SELECT * FROM tools WHERE tool_code = @id OR tool_id = @id OR tool_name LIKE @like LIMIT 1',
      params: {'id': id, 'like': '%$id%'},
    );
  }

  static Future<Map<String, dynamic>?> _findWorkOrder(String identifier) async {
    if (identifier.trim().isEmpty) return null;
    final id = identifier.trim();
    return await DbHelper.queryOne(
      'SELECT * FROM work_orders WHERE wo_no = @id OR wo_id = @id LIMIT 1',
      params: {'id': id},
    );
  }

  static Future<Map<String, dynamic>?> _findPmPlan(String identifier) async {
    if (identifier.trim().isEmpty) return null;
    final id = identifier.trim();
    return await DbHelper.queryOne(
      'SELECT * FROM pm_am_plans WHERE plan_code = @id OR plan_id = @id OR plan_name LIKE @like LIMIT 1',
      params: {'id': id, 'like': '%$id%'},
    );
  }

  // ── 0. MACHINE ASSETS / DOCUMENTS (manage_machine_assets) ───────────────────

  static Future<String> _manageMachineAssets(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'attach_document';
    final rawIdentifiers = (args['machine_identifier'] ?? args['machine_no'] ?? args['machines'])?.toString().trim() ?? '';
    if (rawIdentifiers.isEmpty) {
      return jsonEncode({'error': 'กรุณาระบุรหัสเครื่องจักร (machine_identifier)'});
    }

    // Split or expand multiple machine identifiers (e.g. "BM-01 ถึง BM-09", "BM-01, BM-02", JSON array)
    final machineList = <String>[];
    final rangeMatch = RegExp(
      r'([A-Za-z]+[-_]?\s*)(\d+)\s*(?:ถึง|to|-|\.\.)\s*(?:[A-Za-z]+[-_]?\s*)?(\d+)',
      caseSensitive: false,
    ).firstMatch(rawIdentifiers);

    if (rangeMatch != null) {
      final prefix = rangeMatch.group(1)?.trim() ?? '';
      final startNum = int.tryParse(rangeMatch.group(2)!) ?? 1;
      final endNum = int.tryParse(rangeMatch.group(3)!) ?? 1;
      final padLen = rangeMatch.group(2)!.length;
      if (startNum <= endNum && endNum - startNum <= 100) {
        for (int n = startNum; n <= endNum; n++) {
          final numStr = n.toString().padLeft(padLen, '0');
          machineList.add('$prefix$numStr');
        }
      }
    } else if (args['machines'] is List) {
      for (final m in args['machines'] as List) {
        if (m is Map && m['machine_no'] != null) {
          machineList.add(m['machine_no'].toString().trim());
        } else if (m is String) {
          machineList.add(m.trim());
        }
      }
    } else {
      final parts = rawIdentifiers.split(RegExp(r'[,;\n\s]+'));
      for (final p in parts) {
        final clean = p
            .replaceAll(RegExp(r'^(ถึง|และ|to|and)$', caseSensitive: false), '')
            .trim();
        if (clean.isNotEmpty && clean.length >= 2) {
          machineList.add(clean);
        }
      }
    }

    if (machineList.isEmpty) {
      machineList.add(rawIdentifiers);
    }

    // Resolve valid user_id to avoid FOREIGN KEY constraint error
    String? validUserId;
    if (args['user_id'] != null && args['user_id'].toString().isNotEmpty) {
      final u = await _findUser(args['user_id'].toString());
      validUserId = u?['user_id']?.toString();
    }
    validUserId ??= (await DbHelper.queryOne('SELECT user_id FROM users LIMIT 1'))?['user_id']?.toString();

    final results = <String>[];
    int successCount = 0;

    for (final identifier in machineList) {
      var machine = await _findMachine(identifier);
      String machineId;
      String machineNo;

      if (machine == null) {
        machineId = const Uuid().v4();
        machineNo = identifier;
        await DbHelper.execute('''
          INSERT INTO machines (
            machine_id, machine_no, machine_name, status, is_active, created_at, updated_at
          ) VALUES (
            @id, @no, @name, 'normal', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          )
        ''', params: {
          'id': machineId,
          'no': machineNo,
          'name': 'เครื่องจักร $machineNo',
        });
        for (final st in ['stage1', 'stage2', 'stage3']) {
          await DbHelper.execute('''
            INSERT INTO machine_handover (handover_id, machine_id, stage, status, created_at, updated_at)
            VALUES (@hid, @mid, @st, 'pending', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
          ''', params: {'hid': const Uuid().v4(), 'mid': machineId, 'st': st});
        }
      } else {
        machineId = machine['machine_id'].toString();
        machineNo = machine['machine_no'].toString();
      }

      if (action == 'attach_document' || action == 'attach' || action == 'upload' || action == 'attach_file') {
        final fileName = args['file_name']?.toString().trim() ?? 'เอกสารแนบ';
        var filePath = (args['file_path'] ?? args['path'])?.toString().trim() ?? '';
        final category = args['category']?.toString().trim() ?? 'manual';

        var handover = await DbHelper.queryOne(
          'SELECT handover_id FROM machine_handover WHERE machine_id = @mid ORDER BY created_at DESC LIMIT 1',
          params: {'mid': machineId},
        );

        String handoverId;
        if (handover != null) {
          handoverId = handover['handover_id'].toString();
        } else {
          handoverId = const Uuid().v4();
          await DbHelper.execute('''
            INSERT INTO machine_handover (
              handover_id, machine_id, stage, status, created_at, updated_at
            ) VALUES (
              @hid, @mid, 'stage2', 'completed', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
            )
          ''', params: {'hid': handoverId, 'mid': machineId});
        }

        String savedPath = filePath;
        int fileSize = 0;
        String mimeType = 'application/pdf';

        if (filePath.isNotEmpty) {
          final sourceFile = File(filePath);
          if (await sourceFile.exists()) {
            fileSize = await sourceFile.length();
            final ext = p.extension(filePath).toLowerCase();
            if (ext == '.pdf') {
              mimeType = 'application/pdf';
            } else if (ext == '.png') {
              mimeType = 'image/png';
            } else if (ext == '.jpg' || ext == '.jpeg') {
              mimeType = 'image/jpeg';
            } else if (ext == '.xlsx' || ext == '.xls') {
              mimeType = 'application/vnd.ms-excel';
            } else if (ext == '.doc' || ext == '.docx') {
              mimeType = 'application/msword';
            }

            try {
              final asset = await AttachmentStorageService.instance.ingestFile(
                moduleType: 'machine_handover',
                entityId: handoverId,
                sourcePath: filePath,
                displayName: fileName,
                category: category,
              );
              savedPath = asset.storagePath;
              fileSize = asset.fileSize;
              mimeType = asset.mimeType;
            } catch (_) {
              savedPath = filePath;
            }
          }
        }

        final attachmentId = const Uuid().v4();
        await DbHelper.execute('''
          INSERT INTO handover_attachments (
            attachment_id, handover_id, file_name, file_path, file_size, mime_type, uploaded_by, uploaded_at
          ) VALUES (
            @id, @hid, @name, @path, @size, @mime, @uid, CURRENT_TIMESTAMP
          )
        ''', params: {
          'id': attachmentId,
          'hid': handoverId,
          'name': fileName,
          'path': savedPath,
          'size': fileSize,
          'mime': mimeType,
          'uid': validUserId,
        });

        if (category == 'cover' || mimeType.startsWith('image/')) {
          await DbHelper.execute('''
            UPDATE machines
            SET cover_image = @img, updated_at = CURRENT_TIMESTAMP
            WHERE machine_id = @mid
          ''', params: {
            'img': savedPath,
            'mid': machineId,
          });
        }

        results.add('$machineNo: แนบเอกสาร "$fileName" สำเร็จ');
        successCount++;
      } else if (action == 'remove_document' || action == 'delete_document') {
        final attachmentId = args['attachment_id']?.toString().trim();
        final fileName = args['file_name']?.toString().trim();

        if (attachmentId != null && attachmentId.isNotEmpty) {
          await DbHelper.execute(
            'DELETE FROM handover_attachments WHERE attachment_id = @id',
            params: {'id': attachmentId},
          );
        } else if (fileName != null && fileName.isNotEmpty) {
          await DbHelper.execute('''
            DELETE FROM handover_attachments
            WHERE file_name LIKE @name
              AND handover_id IN (SELECT handover_id FROM machine_handover WHERE machine_id = @mid)
          ''', params: {'name': '%$fileName%', 'mid': machineId});
        }

        results.add('$machineNo: ลบเอกสารเรียบร้อย');
        successCount++;
      }
    }

    return jsonEncode({
      'status': 'success',
      'action': action,
      'processed_count': successCount,
      'details': results,
      'message': 'ดำเนินการจัดการเอกสารเครื่องจักรสำเร็จ $successCount เครื่อง (${machineList.join(', ')}) เรียบร้อยแล้ว สามารถตรวจสอบได้ที่หน้า ทะเบียนเครื่องจักร -> เอกสาร',
    });
  }

  // ── 1. MACHINES CRUD (manage_machines) ─────────────────────────────────────

  static Future<String> _manageMachines(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'insert';
    if (action == 'attach_document' || action == 'attach_file' || action == 'attach' || action == 'upload_doc') {
      return await _manageMachineAssets(args);
    }

    // Bulk registration support
    if (args['machines'] is List && (args['machines'] as List).isNotEmpty) {
      final rawList = args['machines'] as List;
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

        if (map['specs'] is Map) {
          final specs = (map['specs'] as Map).cast<String, dynamic>();
          await DbHelper.execute('''
            INSERT OR REPLACE INTO machine_specs (
              spec_id, machine_id, power_kw, voltage_v, current_a, capacity, updated_at
            ) VALUES (
              @sid, @mid, @power, @volt, @curr, @cap, CURRENT_TIMESTAMP
            )
          ''', params: {
            'sid': const Uuid().v4(),
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
        'action': 'bulk_register',
        'inserted_count': inserted,
        'updated_count': updated,
        'total_processed': inserted + updated,
        'machines': details,
        'message': 'บันทึกข้อมูลเครื่องจักรลงฐานข้อมูลสำเร็จ (เพิ่มใหม่ $inserted, อัปเดต $updated เครื่อง)',
      });
    }

    final identifier = (args['machine_identifier'] ?? args['machine_no'])?.toString().trim() ?? '';

    if (action == 'delete') {
      final machine = await _findMachine(identifier);
      if (machine == null) {
        return jsonEncode({'error': 'ไม่พบเครื่องจักร "$identifier" ในระบบ'});
      }
      final machineId = machine['machine_id'].toString();
      final machineNo = machine['machine_no'].toString();
      await DbHelper.execute(
        'UPDATE machines SET is_active = 0, status = "offline", updated_at = CURRENT_TIMESTAMP WHERE machine_id = @id',
        params: {'id': machineId},
      );
      return jsonEncode({
        'status': 'success',
        'action': 'delete',
        'machine_id': machineId,
        'machine_no': machineNo,
        'message': 'ปิดการใช้งาน/ลบเครื่องจักร $machineNo เรียบร้อยแล้ว',
      });
    }

    if (action == 'update' || action == 'update_specs' || action == 'update_spec') {
      final machine = await _findMachine(identifier);
      if (machine == null) {
        return jsonEncode({'error': 'ไม่พบเครื่องจักร "$identifier" ที่ต้องการอัปเดต'});
      }
      final machineId = machine['machine_id'].toString();
      final machineNo = machine['machine_no'].toString();

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
        'name': args['machine_name'],
        'asset': args['asset_no'],
        'brand': args['brand'],
        'model': args['model'],
        'serial': args['serial_no'],
        'loc': args['location'],
        'status': args['status']?.toString().toLowerCase(),
        'notes': args['notes'],
      });

      final rawSpecs = (args['specs'] is Map)
          ? (args['specs'] as Map).cast<String, dynamic>()
          : args;

      final powerKw = (rawSpecs['power_kw'] as num?)?.toDouble();
      final voltV = (rawSpecs['voltage_v'] as num?)?.toDouble();
      final currA = (rawSpecs['current_a'] as num?)?.toDouble();
      final freqHz = (rawSpecs['frequency_hz'] as num?)?.toDouble();
      final cap = (rawSpecs['capacity'] as num?)?.toDouble();
      final capUnit = rawSpecs['capacity_unit']?.toString();
      final weightKg = (rawSpecs['weight_kg'] as num?)?.toDouble();
      final dimL = (rawSpecs['dim_length_mm'] as num?)?.toDouble();
      final dimW = (rawSpecs['dim_width_mm'] as num?)?.toDouble();
      final dimH = (rawSpecs['dim_height_mm'] as num?)?.toDouble();
      final rpm = (rawSpecs['rpm'] as num?)?.toDouble();
      final extraSpecs = rawSpecs['extra_specs'] != null
          ? (rawSpecs['extra_specs'] is String
              ? rawSpecs['extra_specs']
              : jsonEncode(rawSpecs['extra_specs']))
          : null;

      final hasSpecs = powerKw != null ||
          voltV != null ||
          currA != null ||
          freqHz != null ||
          cap != null ||
          capUnit != null ||
          weightKg != null ||
          dimL != null ||
          dimW != null ||
          dimH != null ||
          rpm != null ||
          extraSpecs != null;

      if (hasSpecs) {
        final existingSpec = await DbHelper.query(
          'SELECT spec_id FROM machine_specs WHERE machine_id = @mid LIMIT 1',
          params: {'mid': machineId},
        );

        if (existingSpec.isNotEmpty) {
          await DbHelper.execute('''
            UPDATE machine_specs
            SET power_kw = COALESCE(@power, power_kw),
                voltage_v = COALESCE(@volt, voltage_v),
                current_a = COALESCE(@curr, current_a),
                frequency_hz = COALESCE(@freq, frequency_hz),
                capacity = COALESCE(@cap, capacity),
                capacity_unit = COALESCE(@cap_unit, capacity_unit),
                weight_kg = COALESCE(@weight, weight_kg),
                dim_length_mm = COALESCE(@dim_l, dim_length_mm),
                dim_width_mm = COALESCE(@dim_w, dim_width_mm),
                dim_height_mm = COALESCE(@dim_h, dim_height_mm),
                rpm = COALESCE(@rpm, rpm),
                extra_specs = COALESCE(@extra, extra_specs),
                updated_at = CURRENT_TIMESTAMP
            WHERE machine_id = @mid
          ''', params: {
            'mid': machineId,
            'power': powerKw,
            'volt': voltV,
            'curr': currA,
            'freq': freqHz,
            'cap': cap,
            'cap_unit': capUnit,
            'weight': weightKg,
            'dim_l': dimL,
            'dim_w': dimW,
            'dim_h': dimH,
            'rpm': rpm,
            'extra': extraSpecs,
          });
        } else {
          await DbHelper.execute('''
            INSERT INTO machine_specs (
              spec_id, machine_id, power_kw, voltage_v, current_a, frequency_hz,
              capacity, capacity_unit, weight_kg, dim_length_mm, dim_width_mm, dim_height_mm,
              rpm, extra_specs, updated_at
            ) VALUES (
              @sid, @mid, @power, @volt, @curr, @freq,
              @cap, @cap_unit, @weight, @dim_l, @dim_w, @dim_h,
              @rpm, @extra, CURRENT_TIMESTAMP
            )
          ''', params: {
            'sid': const Uuid().v4(),
            'mid': machineId,
            'power': powerKw,
            'volt': voltV,
            'curr': currA,
            'freq': freqHz,
            'cap': cap,
            'cap_unit': capUnit,
            'weight': weightKg,
            'dim_l': dimL,
            'dim_w': dimW,
            'dim_h': dimH,
            'rpm': rpm,
            'extra': extraSpecs,
          });
        }
      }

      VectorDbService.syncMachine(machineId);

      final updatedSpecsMap = <String, dynamic>{};
      if (powerKw != null) updatedSpecsMap['power_kw'] = '$powerKw kW';
      if (voltV != null) updatedSpecsMap['voltage_v'] = '$voltV V';
      if (currA != null) updatedSpecsMap['current_a'] = '$currA A';
      if (freqHz != null) updatedSpecsMap['frequency_hz'] = '$freqHz Hz';
      if (cap != null) updatedSpecsMap['capacity'] = '$cap ${capUnit ?? ""}'.trim();
      if (weightKg != null) updatedSpecsMap['weight_kg'] = '$weightKg kg';
      if (dimL != null && dimW != null && dimH != null) {
        updatedSpecsMap['dimensions_mm'] = '$dimL x $dimW x $dimH mm';
      }
      if (rpm != null) updatedSpecsMap['rpm'] = '$rpm RPM';
      if (extraSpecs != null) updatedSpecsMap['extra_specs'] = extraSpecs;

      return jsonEncode({
        'status': 'success',
        'action': 'update',
        'machine_id': machineId,
        'machine_no': machineNo,
        'updated_specs': updatedSpecsMap,
        'message': 'อัปเดตสเปกและข้อมูลเครื่องจักร $machineNo สำเร็จ',
      });
    }

    // Default / Insert: Check if machine already exists first
    final machineNo = (args['machine_no'] ?? identifier).trim();
    if (machineNo.isEmpty) {
      return jsonEncode({'error': 'กรุณาระบุรหัสเครื่องจักร (machine_no)'});
    }

    final existingMachine = await _findMachine(machineNo);
    if (existingMachine != null) {
      // Machine already exists! Smartly update machine & specs
      final machineId = existingMachine['machine_id'].toString();
      final existingNo = existingMachine['machine_no'].toString();

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
        'name': args['machine_name'],
        'asset': args['asset_no'],
        'brand': args['brand'],
        'model': args['model'],
        'serial': args['serial_no'],
        'loc': args['location'],
        'status': args['status']?.toString().toLowerCase(),
        'notes': args['notes'],
      });

      final rawSpecs = (args['specs'] is Map)
          ? (args['specs'] as Map).cast<String, dynamic>()
          : args;

      final powerKw = (rawSpecs['power_kw'] as num?)?.toDouble();
      final voltV = (rawSpecs['voltage_v'] as num?)?.toDouble();
      final currA = (rawSpecs['current_a'] as num?)?.toDouble();
      final freqHz = (rawSpecs['frequency_hz'] as num?)?.toDouble();
      final cap = (rawSpecs['capacity'] as num?)?.toDouble();
      final capUnit = rawSpecs['capacity_unit']?.toString();
      final weightKg = (rawSpecs['weight_kg'] as num?)?.toDouble();
      final dimL = (rawSpecs['dim_length_mm'] as num?)?.toDouble();
      final dimW = (rawSpecs['dim_width_mm'] as num?)?.toDouble();
      final dimH = (rawSpecs['dim_height_mm'] as num?)?.toDouble();
      final rpm = (rawSpecs['rpm'] as num?)?.toDouble();
      final extraSpecs = rawSpecs['extra_specs'] != null
          ? (rawSpecs['extra_specs'] is String
              ? rawSpecs['extra_specs']
              : jsonEncode(rawSpecs['extra_specs']))
          : null;

      final hasSpecs = powerKw != null ||
          voltV != null ||
          currA != null ||
          freqHz != null ||
          cap != null ||
          capUnit != null ||
          weightKg != null ||
          dimL != null ||
          dimW != null ||
          dimH != null ||
          rpm != null ||
          extraSpecs != null;

      if (hasSpecs) {
        final existingSpec = await DbHelper.query(
          'SELECT spec_id FROM machine_specs WHERE machine_id = @mid LIMIT 1',
          params: {'mid': machineId},
        );

        if (existingSpec.isNotEmpty) {
          await DbHelper.execute('''
            UPDATE machine_specs
            SET power_kw = COALESCE(@power, power_kw),
                voltage_v = COALESCE(@volt, voltage_v),
                current_a = COALESCE(@curr, current_a),
                frequency_hz = COALESCE(@freq, frequency_hz),
                capacity = COALESCE(@cap, capacity),
                capacity_unit = COALESCE(@cap_unit, capacity_unit),
                weight_kg = COALESCE(@weight, weight_kg),
                dim_length_mm = COALESCE(@dim_l, dim_length_mm),
                dim_width_mm = COALESCE(@dim_w, dim_width_mm),
                dim_height_mm = COALESCE(@dim_h, dim_height_mm),
                rpm = COALESCE(@rpm, rpm),
                extra_specs = COALESCE(@extra, extra_specs),
                updated_at = CURRENT_TIMESTAMP
            WHERE machine_id = @mid
          ''', params: {
            'mid': machineId,
            'power': powerKw,
            'volt': voltV,
            'curr': currA,
            'freq': freqHz,
            'cap': cap,
            'cap_unit': capUnit,
            'weight': weightKg,
            'dim_l': dimL,
            'dim_w': dimW,
            'dim_h': dimH,
            'rpm': rpm,
            'extra': extraSpecs,
          });
        } else {
          await DbHelper.execute('''
            INSERT INTO machine_specs (
              spec_id, machine_id, power_kw, voltage_v, current_a, frequency_hz,
              capacity, capacity_unit, weight_kg, dim_length_mm, dim_width_mm, dim_height_mm,
              rpm, extra_specs, updated_at
            ) VALUES (
              @sid, @mid, @power, @volt, @curr, @freq,
              @cap, @cap_unit, @weight, @dim_l, @dim_w, @dim_h,
              @rpm, @extra, CURRENT_TIMESTAMP
            )
          ''', params: {
            'sid': const Uuid().v4(),
            'mid': machineId,
            'power': powerKw,
            'volt': voltV,
            'curr': currA,
            'freq': freqHz,
            'cap': cap,
            'cap_unit': capUnit,
            'weight': weightKg,
            'dim_l': dimL,
            'dim_w': dimW,
            'dim_h': dimH,
            'rpm': rpm,
            'extra': extraSpecs,
          });
        }
      }

      VectorDbService.syncMachine(machineId);

      final updatedSpecsMap = <String, dynamic>{};
      if (powerKw != null) updatedSpecsMap['power_kw'] = '$powerKw kW';
      if (voltV != null) updatedSpecsMap['voltage_v'] = '$voltV V';
      if (currA != null) updatedSpecsMap['current_a'] = '$currA A';
      if (freqHz != null) updatedSpecsMap['frequency_hz'] = '$freqHz Hz';
      if (cap != null) updatedSpecsMap['capacity'] = '$cap ${capUnit ?? ""}'.trim();
      if (weightKg != null) updatedSpecsMap['weight_kg'] = '$weightKg kg';
      if (dimL != null && dimW != null && dimH != null) {
        updatedSpecsMap['dimensions_mm'] = '$dimL x $dimW x $dimH mm';
      }
      if (rpm != null) updatedSpecsMap['rpm'] = '$rpm RPM';
      if (extraSpecs != null) updatedSpecsMap['extra_specs'] = extraSpecs;

      return jsonEncode({
        'status': 'success',
        'action': 'update',
        'machine_id': machineId,
        'machine_no': existingNo,
        'updated_specs': updatedSpecsMap,
        'message': 'อัปเดตสเปกและข้อมูลเครื่องจักร $existingNo สำเร็จ',
      });
    }

    // New machine insert
    final machineId = const Uuid().v4();
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
      'name': args['machine_name'],
      'asset': args['asset_no'],
      'brand': args['brand'],
      'model': args['model'],
      'serial': args['serial_no'],
      'loc': args['location'],
      'status': args['status']?.toString().toLowerCase() ?? 'normal',
      'notes': args['notes'],
    });

    final rawSpecs = (args['specs'] is Map)
        ? (args['specs'] as Map).cast<String, dynamic>()
        : args;

    final powerKw = (rawSpecs['power_kw'] as num?)?.toDouble();
    final voltV = (rawSpecs['voltage_v'] as num?)?.toDouble();
    final currA = (rawSpecs['current_a'] as num?)?.toDouble();
    final freqHz = (rawSpecs['frequency_hz'] as num?)?.toDouble();
    final cap = (rawSpecs['capacity'] as num?)?.toDouble();
    final capUnit = rawSpecs['capacity_unit']?.toString();
    final weightKg = (rawSpecs['weight_kg'] as num?)?.toDouble();
    final dimL = (rawSpecs['dim_length_mm'] as num?)?.toDouble();
    final dimW = (rawSpecs['dim_width_mm'] as num?)?.toDouble();
    final dimH = (rawSpecs['dim_height_mm'] as num?)?.toDouble();
    final rpm = (rawSpecs['rpm'] as num?)?.toDouble();
    final extraSpecs = rawSpecs['extra_specs'] != null
        ? (rawSpecs['extra_specs'] is String
            ? rawSpecs['extra_specs']
            : jsonEncode(rawSpecs['extra_specs']))
        : null;

    final hasSpecs = powerKw != null ||
        voltV != null ||
        currA != null ||
        freqHz != null ||
        cap != null ||
        capUnit != null ||
        weightKg != null ||
        dimL != null ||
        dimW != null ||
        dimH != null ||
        rpm != null ||
        extraSpecs != null;

    if (hasSpecs) {
      await DbHelper.execute('''
        INSERT INTO machine_specs (
          spec_id, machine_id, power_kw, voltage_v, current_a, frequency_hz,
          capacity, capacity_unit, weight_kg, dim_length_mm, dim_width_mm, dim_height_mm,
          rpm, extra_specs, updated_at
        ) VALUES (
          @sid, @mid, @power, @volt, @curr, @freq,
          @cap, @cap_unit, @weight, @dim_l, @dim_w, @dim_h,
          @rpm, @extra, CURRENT_TIMESTAMP
        )
      ''', params: {
        'sid': const Uuid().v4(),
        'mid': machineId,
        'power': powerKw,
        'volt': voltV,
        'curr': currA,
        'freq': freqHz,
        'cap': cap,
        'cap_unit': capUnit,
        'weight': weightKg,
        'dim_l': dimL,
        'dim_w': dimW,
        'dim_h': dimH,
        'rpm': rpm,
        'extra': extraSpecs,
      });
    }

    VectorDbService.syncMachine(machineId);

    return jsonEncode({
      'status': 'success',
      'action': 'insert',
      'machine_id': machineId,
      'machine_no': machineNo,
      'message': 'ขึ้นทะเบียนเครื่องจักรใหม่ $machineNo สำเร็จ',
    });
  }

  // ── 2. LOCATIONS & FACTORY LAYOUT CRUD (manage_locations) ──────────────────

  static Future<String> _manageLocations(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'create_zone';

    if (action == 'create_layout') {
      final layoutName = args['layout_name']?.toString().trim() ?? 'Main Factory Layout';
      final layoutId = const Uuid().v4();
      await DbHelper.execute('''
        INSERT INTO factory_layouts (
          layout_id, layout_name, description, floor_no, width_m, height_m, is_active, created_at, updated_at
        ) VALUES (
          @id, @name, @desc, @floor, @w, @h, 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
      ''', params: {
        'id': layoutId,
        'name': layoutName,
        'desc': args['description'],
        'floor': (args['floor_no'] as num?)?.toInt() ?? 1,
        'w': (args['width_m'] as num?)?.toDouble() ?? 50.0,
        'h': (args['height_m'] as num?)?.toDouble() ?? 30.0,
      });
      return jsonEncode({
        'status': 'success',
        'layout_id': layoutId,
        'layout_name': layoutName,
        'message': 'สร้างผังโรงงาน "$layoutName" สำเร็จ',
      });
    }

    if (action == 'create_zone') {
      final layout = await DbHelper.queryOne('SELECT layout_id FROM factory_layouts WHERE is_active = 1 LIMIT 1');
      final layoutId = args['layout_id']?.toString() ?? layout?['layout_id']?.toString() ?? 'DEFAULT_LAYOUT';
      final zoneName = args['zone_name']?.toString().trim() ?? 'Zone Area';
      final zoneId = const Uuid().v4();

      await DbHelper.execute('''
        INSERT INTO layout_zones (
          zone_id, layout_id, zone_name, zone_type, x_start, y_start, x_end, y_end,
          background_color, border_color, created_at
        ) VALUES (
          @id, @lid, @name, @type, @xs, @ys, @xe, @ye, @bg, @border, CURRENT_TIMESTAMP
        )
      ''', params: {
        'id': zoneId,
        'lid': layoutId,
        'name': zoneName,
        'type': args['zone_type'] ?? 'production',
        'xs': (args['x_start'] as num?)?.toDouble() ?? 0.0,
        'ys': (args['y_start'] as num?)?.toDouble() ?? 0.0,
        'xe': (args['x_end'] as num?)?.toDouble() ?? 10.0,
        'ye': (args['y_end'] as num?)?.toDouble() ?? 10.0,
        'bg': args['background_color'] ?? '#E8F5E9',
        'border': args['border_color'] ?? '#4CAF50',
      });
      return jsonEncode({
        'status': 'success',
        'zone_id': zoneId,
        'zone_name': zoneName,
        'message': 'เพิ่มโซนพื้นที่ "$zoneName" ในผังโรงงานสำเร็จ',
      });
    }

    if (action == 'update_zone') {
      final zoneId = args['zone_id']?.toString().trim();
      final zoneName = args['zone_name']?.toString().trim();
      if (zoneId == null && zoneName == null) {
        return jsonEncode({'error': 'กรุณาระบุ zone_id หรือ zone_name ที่ต้องการแก้ไข'});
      }
      await DbHelper.execute('''
        UPDATE layout_zones
        SET zone_name = COALESCE(@name, zone_name),
            zone_type = COALESCE(@type, zone_type),
            background_color = COALESCE(@bg, background_color),
            border_color = COALESCE(@border, border_color)
        WHERE zone_id = @id OR zone_name = @targetName
      ''', params: {
        'id': zoneId,
        'targetName': zoneName,
        'name': args['new_zone_name'] ?? zoneName,
        'type': args['zone_type'],
        'bg': args['background_color'],
        'border': args['border_color'],
      });
      return jsonEncode({'status': 'success', 'message': 'อัปเดตข้อมูลโซนพื้นที่สำเร็จ'});
    }

    if (action == 'delete_zone') {
      final zoneId = args['zone_id']?.toString().trim();
      final zoneName = args['zone_name']?.toString().trim();
      await DbHelper.execute(
        'DELETE FROM layout_zones WHERE zone_id = @id OR zone_name = @name',
        params: {'id': zoneId, 'name': zoneName},
      );
      return jsonEncode({'status': 'success', 'message': 'ลบโซนพื้นที่เรียบร้อยแล้ว'});
    }

    if (action == 'set_machine_position') {
      final machineIdentifier = args['machine_identifier']?.toString().trim() ?? '';
      final machine = await _findMachine(machineIdentifier);
      if (machine == null) {
        return jsonEncode({'error': 'ไม่พบเครื่องจักร "$machineIdentifier"'});
      }
      final machineId = machine['machine_id'].toString();
      final layout = await DbHelper.queryOne('SELECT layout_id FROM factory_layouts WHERE is_active = 1 LIMIT 1');
      final layoutId = args['layout_id']?.toString() ?? layout?['layout_id']?.toString() ?? 'DEFAULT_LAYOUT';

      await DbHelper.execute('''
        INSERT OR REPLACE INTO machine_positions (
          position_id, layout_id, machine_id, zone_id, x_position, y_position, width, height, status_color, updated_at
        ) VALUES (
          @id, @lid, @mid, @zid, @x, @y, @w, @h, @color, CURRENT_TIMESTAMP
        )
      ''', params: {
        'id': const Uuid().v4(),
        'lid': layoutId,
        'mid': machineId,
        'zid': args['zone_id'],
        'x': (args['x_position'] as num?)?.toDouble() ?? 0.0,
        'y': (args['y_position'] as num?)?.toDouble() ?? 0.0,
        'w': (args['width'] as num?)?.toDouble() ?? 40.0,
        'h': (args['height'] as num?)?.toDouble() ?? 40.0,
        'color': args['status_color'] ?? '#4CAF50',
      });
      return jsonEncode({
        'status': 'success',
        'machine_no': machine['machine_no'],
        'message': 'กำหนดตำแหน่งพิกัดเครื่องจักร ${machine["machine_no"]} บนผังสำเร็จ',
      });
    }

    if (action == 'delete_machine_position') {
      final machineIdentifier = args['machine_identifier']?.toString().trim() ?? '';
      final machine = await _findMachine(machineIdentifier);
      if (machine != null) {
        await DbHelper.execute(
          'DELETE FROM machine_positions WHERE machine_id = @mid',
          params: {'mid': machine['machine_id']},
        );
      }
      return jsonEncode({'status': 'success', 'message': 'ลบพิกัดเครื่องจักรออกจากผังเรียบร้อยแล้ว'});
    }

    return jsonEncode({'error': 'ไม่รู้จัก action "$action"'});
  }

  // ── 3. PM/AM MASTER PLANS CRUD (manage_pm_plans) ───────────────────────────

  static Future<String> _managePmPlans(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'create_plan';

    if (action == 'delete_plan' || action == 'delete') {
      final identifier = (args['plan_identifier'] ?? args['plan_code'])?.toString().trim() ?? '';
      final plan = await _findPmPlan(identifier);
      if (plan == null) {
        return jsonEncode({'error': 'ไม่พบแผนแม่บท PM/AM "$identifier"'});
      }
      final planId = plan['plan_id'].toString();
      await DbHelper.execute('DELETE FROM pm_am_tasks WHERE plan_id = @id', params: {'id': planId});
      await DbHelper.execute('DELETE FROM pm_am_plans WHERE plan_id = @id', params: {'id': planId});
      return jsonEncode({
        'status': 'success',
        'plan_code': plan['plan_code'],
        'message': 'ลบแผนแม่บท PM/AM (${plan["plan_code"]}) และรายการตรวจเช็คทั้งหมดเรียบร้อยแล้ว',
      });
    }

    if (action == 'update_plan' || action == 'update') {
      final identifier = (args['plan_identifier'] ?? args['plan_code'])?.toString().trim() ?? '';
      final plan = await _findPmPlan(identifier);
      if (plan == null) {
        return jsonEncode({'error': 'ไม่พบแผนแม่บท PM/AM "$identifier" ที่ต้องการแก้ไข'});
      }
      final planId = plan['plan_id'].toString();
      await DbHelper.execute('''
        UPDATE pm_am_plans
        SET plan_name = COALESCE(@name, plan_name),
            frequency_days = COALESCE(@freq, frequency_days),
            status = COALESCE(@status, status),
            description = COALESCE(@desc, description),
            updated_at = CURRENT_TIMESTAMP
        WHERE plan_id = @id
      ''', params: {
        'id': planId,
        'name': args['plan_name'],
        'freq': (args['frequency_days'] as num?)?.toInt(),
        'status': args['status'],
        'desc': args['description'],
      });
      return jsonEncode({
        'status': 'success',
        'plan_code': plan['plan_code'],
        'message': 'อัปเดตข้อมูลแผนแม่บท PM/AM (${plan["plan_code"]}) สำเร็จ',
      });
    }

    if (action == 'add_task') {
      final identifier = (args['plan_identifier'] ?? args['plan_code'])?.toString().trim() ?? '';
      final plan = await _findPmPlan(identifier);
      if (plan == null) {
        return jsonEncode({'error': 'ไม่พบแผนแม่บท PM/AM "$identifier"'});
      }
      final taskName = args['task_name']?.toString().trim() ?? '';
      if (taskName.isEmpty) {
        return jsonEncode({'error': 'กรุณาระบุชื่องานตรวจเช็ค (task_name)'});
      }
      final countRow = await DbHelper.queryOne(
        'SELECT COUNT(*) as c FROM pm_am_tasks WHERE plan_id = @id',
        params: {'id': plan['plan_id']},
      );
      final nextOrder = ((countRow?['c'] as num?)?.toInt() ?? 0) + 1;
      final taskId = const Uuid().v4();

      await DbHelper.execute('''
        INSERT INTO pm_am_tasks (
          task_id, plan_id, task_order, task_name, task_type, is_critical, created_at
        ) VALUES (
          @tid, @pid, @order, @name, @type, @crit, CURRENT_TIMESTAMP
        )
      ''', params: {
        'tid': taskId,
        'pid': plan['plan_id'],
        'order': nextOrder,
        'name': taskName,
        'type': args['task_type'] ?? 'inspect',
        'crit': args['is_critical'] == true ? 1 : 0,
      });
      return jsonEncode({
        'status': 'success',
        'task_id': taskId,
        'task_name': taskName,
        'message': 'เพิ่มรายการตรวจเช็ค "$taskName" ในแผน ${plan["plan_code"]} สำเร็จ',
      });
    }

    if (action == 'delete_task') {
      final taskId = args['task_id']?.toString().trim();
      final taskName = args['task_name']?.toString().trim();
      await DbHelper.execute(
        'DELETE FROM pm_am_tasks WHERE task_id = @id OR task_name = @name',
        params: {'id': taskId, 'name': taskName},
      );
      return jsonEncode({'status': 'success', 'message': 'ลบรายการตรวจเช็คเรียบร้อยแล้ว'});
    }

    // Check if bulk plans list is provided
    final rawPlans = args['plans'] ?? args['items'] ?? args['list'];
    if (rawPlans is List && rawPlans.isNotEmpty) {
      int createdPlans = 0;
      int totalTasks = 0;
      final createdCodes = <String>[];

      for (final p in rawPlans) {
        if (p is! Map) continue;
        final pMap = Map<String, dynamic>.from(p);
        final mcIdentifier = (pMap['machine_identifier'] ?? pMap['machine_no'] ?? pMap['machine_id'])?.toString().trim() ?? '';
        if (mcIdentifier.isEmpty) continue;

        final machine = await _findMachine(mcIdentifier);
        if (machine == null) continue;

        final machineId = machine['machine_id'].toString();
        final machineNo = machine['machine_no'].toString();
        final pType = (pMap['plan_type']?.toString().trim().toUpperCase() == 'AM') ? 'AM' : 'PM';
        final pName = pMap['plan_name']?.toString().trim() ?? 'แผนบำรุงรักษา $pType $machineNo';
        final freqDays = (pMap['frequency_days'] as num?)?.toInt() ?? (pType == 'AM' ? 1 : 30);
        final pTasks = pMap['tasks'];

        final planId = const Uuid().v4();
        final planCode = '$pType-$machineNo-${DateTime.now().millisecondsSinceEpoch % 10000}';

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
          'type': pType,
          'code': planCode,
          'name': pName,
          'freq': freqDays,
        });
        createdPlans++;
        createdCodes.add(planCode);

        if (pTasks is List && pTasks.isNotEmpty) {
          for (int i = 0; i < pTasks.length; i++) {
            final t = pTasks[i];
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
            totalTasks++;
          }
        }
      }

      return jsonEncode({
        'status': 'success',
        'plans_created': createdPlans,
        'tasks_created': totalTasks,
        'plan_codes': createdCodes,
        'message': 'สร้างแผนแม่บท PM/AM สำเร็จ $createdPlans แผน (รวมรายการตรวจเช็ค $totalTasks รายการ)',
      });
    }

    // Default: create single plan / insert
    final machineIdentifier = args['machine_identifier']?.toString().trim() ?? '';
    final planType = (args['plan_type']?.toString().trim().toUpperCase() == 'AM') ? 'AM' : 'PM';
    final planName = args['plan_name']?.toString().trim() ?? 'แผนบำรุงรักษาประจำเครื่อง';
    final frequencyDays = (args['frequency_days'] as num?)?.toInt() ?? 30;
    final tasks = args['tasks'];

    final machine = await _findMachine(machineIdentifier);
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

  // ── 4. PM/AM SCHEDULES & EXECUTIONS CRUD (manage_pm_schedules) ─────────────

  static Future<String> _managePmSchedules(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'create_schedule';

    if (action == 'delete_schedule' || action == 'delete') {
      final scheduleId = args['schedule_id']?.toString().trim() ?? '';
      await DbHelper.execute('DELETE FROM pm_am_executions WHERE schedule_id = @id', params: {'id': scheduleId});
      await DbHelper.execute('DELETE FROM pm_am_schedules WHERE schedule_id = @id', params: {'id': scheduleId});
      return jsonEncode({'status': 'success', 'message': 'ยกเลิก/ลบกำหนดการ PM/AM เรียบร้อยแล้ว'});
    }

    if (action == 'update_status' || action == 'update') {
      final scheduleId = args['schedule_id']?.toString().trim() ?? '';
      final status = args['status']?.toString().trim() ?? 'completed';
      final assignedToName = args['assigned_to']?.toString().trim();
      String? assignedToId;
      if (assignedToName != null && assignedToName.isNotEmpty) {
        final u = await _findUser(assignedToName);
        assignedToId = u?['user_id']?.toString();
      }

      await DbHelper.execute('''
        UPDATE pm_am_schedules
        SET status = @status,
            assigned_to = COALESCE(@assigned, assigned_to),
            updated_at = CURRENT_TIMESTAMP
        WHERE schedule_id = @id
      ''', params: {
        'id': scheduleId,
        'status': status,
        'assigned': assignedToId,
      });
      return jsonEncode({'status': 'success', 'message': 'อัปเดตสถานะกำหนดการ PM เป็น "$status" สำเร็จ'});
    }

    if (action == 'record_execution') {
      final scheduleId = args['schedule_id']?.toString().trim() ?? '';
      final taskIdentifier = (args['task_id'] ?? args['task_name'])?.toString().trim() ?? '';
      final result = args['result']?.toString().toLowerCase() ?? 'pass';
      final remarks = args['remarks']?.toString().trim();
      final partsUsed = args['parts_used'] != null ? jsonEncode(args['parts_used']) : null;

      final task = await DbHelper.queryOne(
        'SELECT task_id FROM pm_am_tasks WHERE task_id = @id OR task_name = @id LIMIT 1',
        params: {'id': taskIdentifier},
      );
      final taskId = task?['task_id']?.toString() ?? taskIdentifier;

      final executionId = const Uuid().v4();
      await DbHelper.execute('''
        INSERT INTO pm_am_executions (
          execution_id, schedule_id, task_id, result, remarks, parts_used, completed_at, created_at
        ) VALUES (
          @eid, @sid, @tid, @res, @rem, @parts, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
      ''', params: {
        'eid': executionId,
        'sid': scheduleId,
        'tid': taskId,
        'res': result,
        'rem': remarks,
        'parts': partsUsed,
      });
      return jsonEncode({
        'status': 'success',
        'execution_id': executionId,
        'result': result,
        'message': 'บันทึกผลการตรวจเช็คงาน PM ($result) เรียบร้อยแล้ว',
      });
    }

    // Default: create_schedule
    final planIdentifier = args['plan_identifier']?.toString().trim() ?? '';
    final plan = await _findPmPlan(planIdentifier);
    if (plan == null) {
      return jsonEncode({'error': 'ไม่พบแผนแม่บท PM/AM "$planIdentifier"'});
    }

    final scheduledDate = args['scheduled_date']?.toString().trim() ?? DateTime.now().toIso8601String().substring(0, 10);
    final assignedToName = args['assigned_to']?.toString().trim();
    String? assignedToId;
    if (assignedToName != null && assignedToName.isNotEmpty) {
      final u = await _findUser(assignedToName);
      assignedToId = u?['user_id']?.toString();
    }

    final scheduleId = const Uuid().v4();
    await DbHelper.execute('''
      INSERT INTO pm_am_schedules (
        schedule_id, plan_id, scheduled_date, assigned_to, status, created_at, updated_at
      ) VALUES (
        @id, @pid, @date, @assigned, 'pending', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      )
    ''', params: {
      'id': scheduleId,
      'pid': plan['plan_id'],
      'date': scheduledDate,
      'assigned': assignedToId,
    });

    return jsonEncode({
      'status': 'success',
      'schedule_id': scheduleId,
      'scheduled_date': scheduledDate,
      'plan_code': plan['plan_code'],
      'message': 'สร้างกำหนดการ PM สำหรับแผน ${plan["plan_code"]} วันที่ $scheduledDate สำเร็จ',
    });
  }

  // ── 5. WORK ORDERS & RCA CRUD (manage_work_orders) ─────────────────────────

  static Future<String> _manageWorkOrders(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'create_order';

    if (action == 'delete_order' || action == 'delete') {
      final woIdentifier = (args['wo_identifier'] ?? args['wo_no'])?.toString().trim() ?? '';
      final wo = await _findWorkOrder(woIdentifier);
      if (wo == null) {
        return jsonEncode({'error': 'ไม่พบใบแจ้งซ่อม "$woIdentifier"'});
      }
      final woId = wo['wo_id'].toString();
      await DbHelper.execute(
        'UPDATE work_orders SET status = "cancelled", updated_at = CURRENT_TIMESTAMP WHERE wo_id = @id',
        params: {'id': woId},
      );
      return jsonEncode({
        'status': 'success',
        'wo_no': wo['wo_no'],
        'message': 'ยกเลิกใบแจ้งซ่อมเลขที่ ${wo["wo_no"]} เรียบร้อยแล้ว',
      });
    }

    if (action == 'update_order' || action == 'update') {
      final woIdentifier = (args['wo_identifier'] ?? args['wo_no'])?.toString().trim() ?? '';
      final wo = await _findWorkOrder(woIdentifier);
      if (wo == null) {
        return jsonEncode({'error': 'ไม่พบใบแจ้งซ่อม "$woIdentifier" ที่ต้องการอัปเดต'});
      }
      final woId = wo['wo_id'].toString();
      final status = args['status']?.toString();
      final assignedToName = args['assigned_to']?.toString().trim();
      String? assignedToId;
      if (assignedToName != null && assignedToName.isNotEmpty) {
        final u = await _findUser(assignedToName);
        assignedToId = u?['user_id']?.toString();
      }

      await DbHelper.execute('''
        UPDATE work_orders
        SET status = COALESCE(@status, status),
            priority = COALESCE(@pri, priority),
            assigned_to = COALESCE(@assigned, assigned_to),
            failure_cause = COALESCE(@cause, failure_cause),
            actual_hours = COALESCE(@hours, actual_hours),
            completed_at = CASE WHEN @status = 'completed' THEN CURRENT_TIMESTAMP ELSE completed_at END,
            updated_at = CURRENT_TIMESTAMP
        WHERE wo_id = @id
      ''', params: {
        'id': woId,
        'status': status,
        'pri': args['priority'],
        'assigned': assignedToId,
        'cause': args['failure_cause'],
        'hours': (args['actual_hours'] as num?)?.toDouble(),
      });

      VectorDbService.syncWorkOrder(woId);

      return jsonEncode({
        'status': 'success',
        'wo_no': wo['wo_no'],
        'message': 'อัปเดตสถานะและข้อมูลใบแจ้งซ่อม ${wo["wo_no"]} เรียบร้อยแล้ว',
      });
    }

    if (action == 'record_labor') {
      final woIdentifier = (args['wo_identifier'] ?? args['wo_no'])?.toString().trim() ?? '';
      final wo = await _findWorkOrder(woIdentifier);
      if (wo == null) {
        return jsonEncode({'error': 'ไม่พบใบแจ้งซ่อม "$woIdentifier"'});
      }
      final techIdentifier = args['technician_identifier']?.toString().trim() ?? '';
      final tech = await _findUser(techIdentifier);
      final techId = tech?['user_id']?.toString() ?? 'U-TECH';
      final hours = (args['labor_hours'] as num?)?.toDouble() ?? 1.0;

      final laborId = const Uuid().v4();
      await DbHelper.execute('''
        INSERT INTO work_order_labor (
          labor_id, wo_id, technician_id, start_time, end_time, hours, task_description, created_at
        ) VALUES (
          @lid, @woid, @tid, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, @hours, @desc, CURRENT_TIMESTAMP
        )
      ''', params: {
        'lid': laborId,
        'woid': wo['wo_id'],
        'tid': techId,
        'hours': hours,
        'desc': args['task_description'] ?? 'ดำเนินการตรวจซ่อมตามอาการ',
      });
      return jsonEncode({
        'status': 'success',
        'labor_id': laborId,
        'wo_no': wo['wo_no'],
        'hours': hours,
        'message': 'บันทึกชั่วโมงแรงงานการซ่อม $hours ชม. ลงในใบแจ้งซ่อม ${wo["wo_no"]} สำเร็จ',
      });
    }

    if (action == 'record_rca') {
      final woIdentifier = (args['wo_identifier'] ?? args['wo_no'])?.toString().trim() ?? '';
      final wo = await _findWorkOrder(woIdentifier);
      if (wo == null) {
        return jsonEncode({'error': 'ไม่พบใบแจ้งซ่อม "$woIdentifier"'});
      }
      final rootCause = args['root_cause']?.toString().trim() ?? 'สาเหตุการชำรุดเสียหาย';
      final rcaId = const Uuid().v4();

      await DbHelper.execute('''
        INSERT OR REPLACE INTO work_order_rca (
          rca_id, wo_id, failure_type, why_1, why_2, why_3, why_4, why_5,
          root_cause, correction_action, preventive_action, analyzed_at, created_at, updated_at
        ) VALUES (
          @rid, @woid, @type, @w1, @w2, @w3, @w4, @w5,
          @rc, @correct, @prev, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
      ''', params: {
        'rid': rcaId,
        'woid': wo['wo_id'],
        'type': args['failure_type'] ?? 'breakdown',
        'w1': args['why_1'],
        'w2': args['why_2'],
        'w3': args['why_3'],
        'w4': args['why_4'],
        'w5': args['why_5'],
        'rc': rootCause,
        'correct': args['correction_action'],
        'prev': args['preventive_action'],
      });

      VectorDbService.syncWorkOrder(wo['wo_id'].toString());

      return jsonEncode({
        'status': 'success',
        'rca_id': rcaId,
        'wo_no': wo['wo_no'],
        'root_cause': rootCause,
        'message': 'บันทึกผลการวิเคราะห์สาเหตุ RCA 5-Why สำหรับใบแจ้งซ่อม ${wo["wo_no"]} เรียบร้อยแล้ว',
      });
    }

    // Default: create_order / insert
    final title = args['title']?.toString().trim() ?? 'แจ้งซ่อมเครื่องจักร';
    final machineIdentifier = args['machine_identifier']?.toString().trim() ?? '';
    final symptom = args['symptom']?.toString().trim() ?? '';
    final priority = args['priority']?.toString().trim().toLowerCase() ?? 'normal';
    final description = args['description']?.toString().trim() ?? symptom;

    final machine = await _findMachine(machineIdentifier);
    final machineId = machine?['machine_id']?.toString() ?? 'GENERAL';
    final machineNo = machine?['machine_no']?.toString() ?? 'ทั่วไป';

    final year = DateTime.now().year;
    final countRow = await DbHelper.queryOne(
      "SELECT COUNT(*) as c FROM work_orders WHERE wo_no LIKE 'WO-$year-%'",
    );
    final nextNum = ((countRow?['c'] as num?)?.toInt() ?? 0) + 1;
    final woNo = 'WO-$year-${nextNum.toString().padLeft(5, '0')}';
    final woId = const Uuid().v4();

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

    VectorDbService.syncWorkOrder(woId);

    return jsonEncode({
      'status': 'success',
      'action': 'create_order',
      'wo_id': woId,
      'wo_no': woNo,
      'title': title,
      'machine_no': machineNo,
      'priority': priority,
      'message': 'เปิดใบแจ้งซ่อมเลขที่ $woNo ($title) สำหรับเครื่อง $machineNo เรียบร้อยแล้ว',
    });
  }

  // ── 6. OUTSOURCE VENDORS & CONTRACTORS CRUD (manage_contractors) ───────────

  static Future<String> _manageContractors(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'create_contractor';

    // Bulk registration / Bulk update
    final rawList = args['contractors'] ?? args['suppliers'] ?? args['items'];
    if (rawList is List && rawList.isNotEmpty) {
      int inserted = 0;
      int updated = 0;
      final processedNames = <String>[];

      for (final item in rawList) {
        if (item is! Map) continue;
        final map = item.cast<String, dynamic>();
        final name = (map['name'] ?? map['supplier_name'] ?? map['part_name'])?.toString().trim() ?? '';
        final code = (map['supplier_code'] ?? map['contractor_identifier'] ?? map['code'] ?? map['part_identifier'])?.toString().trim() ?? '';
        if (name.isEmpty && code.isEmpty) continue;

        final contactName = (map['contact_name'] ?? map['contact'])?.toString().trim();
        final phone = map['phone']?.toString().trim();
        final email = map['email']?.toString().trim();
        final address = map['address']?.toString().trim();
        final scope = (map['service_scope'] ?? map['remarks'])?.toString().trim();
        final vendorType = (map['vendor_type'] ?? map['category'] ?? 'supplier')?.toString().trim();
        final isApproved = map['is_approved'] == true ? 1 : 0;

        // Check if exists
        final existing = await DbHelper.queryOne('''
          SELECT supplier_id, supplier_code, name FROM suppliers
          WHERE (supplier_code = @code AND @code != '')
             OR (supplier_id = @code AND @code != '')
             OR (name = @name AND @name != '')
             OR (name LIKE @likeName AND @likeName != '')
          LIMIT 1
        ''', params: {
          'code': code,
          'name': name,
          'likeName': name.isNotEmpty ? '%$name%' : '',
        });

        if (existing != null) {
          final sId = existing['supplier_id'].toString();
          await DbHelper.execute('''
            UPDATE suppliers
            SET name = CASE WHEN @name != '' THEN @name ELSE name END,
                contact_name = COALESCE(@contact, contact_name),
                phone = COALESCE(@phone, phone),
                email = COALESCE(@email, email),
                address = COALESCE(@addr, address),
                service_scope = COALESCE(@scope, service_scope),
                vendor_type = COALESCE(@type, vendor_type),
                is_active = 1
            WHERE supplier_id = @id
          ''', params: {
            'id': sId,
            'name': name,
            'contact': contactName,
            'phone': phone,
            'email': email,
            'addr': address,
            'scope': scope,
            'type': vendorType,
          });
          updated++;
          processedNames.add(name.isNotEmpty ? name : code);
        } else {
          final sId = const Uuid().v4();
          final finalCode = code.isNotEmpty ? code : 'VEN-${DateTime.now().millisecondsSinceEpoch % 100000}';
          await DbHelper.execute('''
            INSERT INTO suppliers (
              supplier_id, supplier_code, name, contact_name, phone, email,
              address, is_outsource_vendor, service_scope, vendor_type, is_approved, is_active, created_at
            ) VALUES (
              @id, @code, @name, @contact, @phone, @email,
              @addr, 1, @scope, @type, @approved, 1, CURRENT_TIMESTAMP
            )
          ''', params: {
            'id': sId,
            'code': finalCode,
            'name': name.isNotEmpty ? name : finalCode,
            'contact': contactName,
            'phone': phone,
            'email': email,
            'addr': address,
            'scope': scope,
            'type': vendorType,
            'approved': isApproved,
          });
          inserted++;
          processedNames.add(name.isNotEmpty ? name : finalCode);
        }
      }

      return jsonEncode({
        'status': 'success',
        'action': 'bulk_contractors',
        'inserted_count': inserted,
        'updated_count': updated,
        'total_processed': inserted + updated,
        'contractors': processedNames,
        'message': 'บันทึก/อัปเดตข้อมูลผู้รับเหมาและซัพพลายเออร์สำเร็จ (เพิ่มใหม่ $inserted, อัปเดต $updated รายการ)',
      });
    }

    final identifier = (args['contractor_identifier'] ??
            args['supplier_code'] ??
            args['part_identifier'] ??
            args['part_code'] ??
            args['name'])
        ?.toString()
        .trim() ??
        '';

    if (action == 'delete_contractor' || action == 'delete') {
      await DbHelper.execute(
        'UPDATE suppliers SET is_active = 0 WHERE supplier_code = @id OR supplier_id = @id OR name = @id OR name LIKE @likeId',
        params: {'id': identifier, 'likeId': '%$identifier%'},
      );
      return jsonEncode({'status': 'success', 'message': 'ปิดการใช้งาน/ลบผู้รับเหมา "$identifier" เรียบร้อยแล้ว'});
    }

    if (action == 'update_contractor' || action == 'update') {
      final existing = await DbHelper.queryOne('''
        SELECT supplier_id, supplier_code, name FROM suppliers
        WHERE supplier_code = @id OR supplier_id = @id OR name = @id OR name LIKE @likeId
        LIMIT 1
      ''', params: {'id': identifier, 'likeId': '%$identifier%'});

      if (existing != null) {
        final supplierId = existing['supplier_id'].toString();
        await DbHelper.execute('''
          UPDATE suppliers
          SET name = COALESCE(@name, name),
              contact_name = COALESCE(@contact, contact_name),
              phone = COALESCE(@phone, phone),
              email = COALESCE(@email, email),
              address = COALESCE(@addr, address),
              service_scope = COALESCE(@scope, service_scope),
              vendor_type = COALESCE(@type, vendor_type),
              is_approved = COALESCE(@approved, is_approved),
              is_active = COALESCE(@active, is_active)
          WHERE supplier_id = @id
        ''', params: {
          'id': supplierId,
          'name': args['name'] ?? args['part_name'],
          'contact': args['contact_name'],
          'phone': args['phone'],
          'email': args['email'],
          'addr': args['address'],
          'scope': args['service_scope'] ?? args['remarks'],
          'type': args['vendor_type'] ?? args['category'],
          'approved': args['is_approved'] == true ? 1 : (args['is_approved'] == false ? 0 : null),
          'active': args['is_active'] == false ? 0 : (args['is_active'] == true ? 1 : null),
        });
        return jsonEncode({'status': 'success', 'message': 'อัปเดตข้อมูลผู้รับเหมา/ซัพพลายเออร์ "$identifier" สำเร็จ'});
      }
    }

    // Default: create_contractor / insert
    final name = (args['name'] ?? args['part_name'])?.toString().trim() ?? 'ผู้รับเหมาบริการ';
    final supplierCode = (args['supplier_code'] ?? args['contractor_identifier'] ?? args['part_identifier'])?.toString().trim() ?? 'VEN-${DateTime.now().millisecondsSinceEpoch % 10000}';
    final supplierId = const Uuid().v4();

    await DbHelper.execute('''
      INSERT INTO suppliers (
        supplier_id, supplier_code, name, contact_name, phone, email,
        address, is_outsource_vendor, service_scope, vendor_type, is_approved, is_active, created_at
      ) VALUES (
        @id, @code, @name, @contact, @phone, @email,
        @addr, 1, @scope, @type, @approved, 1, CURRENT_TIMESTAMP
      )
    ''', params: {
      'id': supplierId,
      'code': supplierCode,
      'name': name,
      'contact': args['contact_name'],
      'phone': args['phone'],
      'email': args['email'],
      'addr': args['address'],
      'scope': args['service_scope'] ?? args['remarks'],
      'type': args['vendor_type'] ?? args['category'] ?? 'maintenance',
      'approved': args['is_approved'] == true ? 1 : 0,
    });

    return jsonEncode({
      'status': 'success',
      'supplier_id': supplierId,
      'supplier_code': supplierCode,
      'name': name,
      'message': 'เพิ่มทะเบียนผู้รับเหมา/ซัพพลายเออร์ "$name" ($supplierCode) สำเร็จ',
    });
  }

  // ── 7. WORK PERMITS & SAFETY CHECKS CRUD (manage_work_permits) ─────────────

  static Future<String> _manageWorkPermits(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'create_permit';

    if (action == 'delete_permit' || action == 'delete') {
      final identifier = (args['permit_identifier'] ?? args['permit_no'])?.toString().trim() ?? '';
      await DbHelper.execute('''
        UPDATE work_permits SET status = 'cancelled', updated_at = CURRENT_TIMESTAMP
        WHERE permit_no = @id OR permit_id = @id
      ''', params: {'id': identifier});
      return jsonEncode({'status': 'success', 'message': 'ยกเลิกใบอนุญาตทำงาน "$identifier" เรียบร้อยแล้ว'});
    }

    if (action == 'update_status' || action == 'update') {
      final identifier = (args['permit_identifier'] ?? args['permit_no'])?.toString().trim() ?? '';
      final status = args['status']?.toString().trim() ?? 'approved';
      final authorizedByName = args['authorized_by']?.toString().trim();
      String? authorizedById;
      if (authorizedByName != null && authorizedByName.isNotEmpty) {
        final u = await _findUser(authorizedByName);
        authorizedById = u?['user_id']?.toString();
      }

      await DbHelper.execute('''
        UPDATE work_permits
        SET status = @status,
            authorized_by = COALESCE(@auth, authorized_by),
            authorized_at = CASE WHEN @status = 'approved' THEN CURRENT_TIMESTAMP ELSE authorized_at END,
            completed_at = CASE WHEN @status = 'completed' THEN CURRENT_TIMESTAMP ELSE completed_at END,
            updated_at = CURRENT_TIMESTAMP
        WHERE permit_no = @id OR permit_id = @id
      ''', params: {
        'id': identifier,
        'status': status,
        'auth': authorizedById,
      });
      return jsonEncode({'status': 'success', 'message': 'อัปเดตสถานะ Work Permit "$identifier" เป็น "$status" สำเร็จ'});
    }

    if (action == 'update_safety_check') {
      final checkId = args['check_id']?.toString().trim();
      final checkItem = args['check_item']?.toString().trim();
      final isPassed = args['is_passed'] == true ? 1 : 0;
      final remarks = args['remarks']?.toString().trim();

      await DbHelper.execute('''
        UPDATE permit_safety_checks
        SET is_passed = @pass,
            remarks = COALESCE(@rem, remarks),
            checked_at = CURRENT_TIMESTAMP
        WHERE check_id = @id OR check_item = @item
      ''', params: {
        'id': checkId,
        'item': checkItem,
        'pass': isPassed,
        'rem': remarks,
      });
      return jsonEncode({'status': 'success', 'message': 'บันทึกผลการตรวจสอบความปลอดภัยเรียบร้อยแล้ว'});
    }

    // Default: create_permit / insert
    final permitType = args['permit_type']?.toString().trim() ?? 'hot_work';
    final description = args['description']?.toString().trim() ?? 'ขออนุญาตเข้าปฏิบัติงาน';
    final machineIdentifier = args['machine_identifier']?.toString().trim() ?? '';
    final machine = await _findMachine(machineIdentifier);
    final machineId = machine?['machine_id']?.toString();

    final adminUser = await DbHelper.queryOne("SELECT user_id, full_name FROM users LIMIT 1");
    final requestorId = adminUser?['user_id']?.toString() ?? 'U-ADMIN';
    final requestorName = args['requester_name']?.toString().trim() ?? adminUser?['full_name']?.toString() ?? 'Admin';

    final year = DateTime.now().year;
    final countRow = await DbHelper.queryOne("SELECT COUNT(*) as c FROM work_permits WHERE permit_no LIKE 'WP-$year-%'");
    final nextNum = ((countRow?['c'] as num?)?.toInt() ?? 0) + 1;
    final permitNo = 'WP-$year-${nextNum.toString().padLeft(5, '0')}';
    final permitId = const Uuid().v4();

    await DbHelper.execute('''
      INSERT INTO work_permits (
        permit_id, permit_no, permit_type, machine_id, department, description,
        duration_hours, requestor, requester_name, status, created_at, updated_at
      ) VALUES (
        @id, @no, @type, @mid, @dept, @desc,
        @dur, @req, @rname, 'pending', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      )
    ''', params: {
      'id': permitId,
      'no': permitNo,
      'type': permitType,
      'mid': machineId,
      'dept': args['department'] ?? 'Maintenance',
      'desc': description,
      'dur': (args['duration_hours'] as num?)?.toInt() ?? 8,
      'req': requestorId,
      'rname': requestorName,
    });

    if (args['safety_checks'] is List && (args['safety_checks'] as List).isNotEmpty) {
      for (final check in args['safety_checks'] as List) {
        final itemText = (check is Map ? check['check_item'] : check)?.toString().trim() ?? '';
        if (itemText.isEmpty) continue;
        await DbHelper.execute('''
          INSERT INTO permit_safety_checks (
            check_id, permit_id, check_item, check_type, is_passed, remarks
          ) VALUES (
            @cid, @pid, @item, @type, 0, NULL
          )
        ''', params: {
          'cid': const Uuid().v4(),
          'pid': permitId,
          'item': itemText,
          'type': check is Map ? check['check_type'] : 'safety',
        });
      }
    }

    return jsonEncode({
      'status': 'success',
      'permit_id': permitId,
      'permit_no': permitNo,
      'permit_type': permitType,
      'message': 'สร้างใบอนุญาตทำงาน $permitNo ($permitType) สำเร็จ',
    });
  }

  // ── 8. SPARE PARTS & STOCK MOVEMENTS CRUD (manage_spare_parts) ────────────

  static Future<String> _manageSpareParts(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'create_part';

    // Bulk registration
    if (args['parts'] is List && (args['parts'] as List).isNotEmpty) {
      final rawParts = args['parts'] as List;
      final machineIdentifier = args['machine_identifier']?.toString().trim();
      String? linkedMachineId;
      if (machineIdentifier != null && machineIdentifier.isNotEmpty) {
        final machine = await _findMachine(machineIdentifier);
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

        final existing = await DbHelper.queryOne('SELECT part_id FROM spare_parts WHERE part_code = @code LIMIT 1', params: {'code': partCode});
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
        VectorDbService.syncSparePart(partId);
        partNames.add('$partCode: $partName');
      }

      return jsonEncode({
        'status': 'success',
        'inserted_count': inserted,
        'parts': partNames,
        'message': 'บันทึกรายการอะไหล่สำเร็จ $inserted รายการ',
      });
    }

    if (action == 'delete_part' || action == 'delete') {
      final identifier = (args['part_identifier'] ?? args['part_code'])?.toString().trim() ?? '';
      await DbHelper.execute(
        'UPDATE spare_parts SET is_active = 0 WHERE part_code = @id OR part_id = @id',
        params: {'id': identifier},
      );
      return jsonEncode({'status': 'success', 'message': 'ปิดการใช้งานอะไหล่ "$identifier" เรียบร้อยแล้ว'});
    }

    if (action == 'update_part' || action == 'update') {
      final identifier = (args['part_identifier'] ?? args['part_code'])?.toString().trim() ?? '';
      final part = await _findPart(identifier);
      if (part == null) {
        // Smart fallback: If this is actually a supplier/contractor record
        final isSupplierHint = args.containsKey('contact_name') ||
            args.containsKey('email') ||
            args.containsKey('phone') ||
            args.containsKey('address') ||
            args.containsKey('remarks') ||
            (args['category']?.toString().toLowerCase().contains('supplier') ?? false);
        final sup = await DbHelper.queryOne(
          'SELECT supplier_id FROM suppliers WHERE supplier_code = @id OR name = @id OR name LIKE @likeId LIMIT 1',
          params: {'id': identifier, 'likeId': '%$identifier%'},
        );
        if (isSupplierHint || sup != null) {
          return _manageContractors(args);
        }
        return jsonEncode({'error': 'ไม่พบอะไหล่ "$identifier" ที่ต้องการแก้ไข'});
      }
      final partId = part['part_id'].toString();

      await DbHelper.execute('''
        UPDATE spare_parts
        SET part_name = COALESCE(@name, part_name),
            category = COALESCE(@cat, category),
            unit_cost = COALESCE(@cost, unit_cost),
            reorder_level = COALESCE(@reorder, reorder_level),
            is_active = COALESCE(@active, is_active)
        WHERE part_id = @id
      ''', params: {
        'id': partId,
        'name': args['part_name'],
        'cat': args['category'],
        'cost': (args['unit_cost'] as num?)?.toDouble(),
        'reorder': (args['reorder_level'] as num?)?.toInt(),
        'active': args['is_active'] == false ? 0 : (args['is_active'] == true ? 1 : null),
      });

      if (args['location'] != null) {
        await DbHelper.execute(
          'UPDATE spare_parts_inventory SET location = @loc, updated_at = CURRENT_TIMESTAMP WHERE part_id = @id',
          params: {'id': partId, 'loc': args['location']},
        );
      }

      VectorDbService.syncSparePart(partId);

      return jsonEncode({'status': 'success', 'message': 'อัปเดตข้อมูลอะไหล่ ${part["part_code"]} สำเร็จ'});
    }

    if (action == 'record_transaction') {
      final identifier = (args['part_identifier'] ?? args['part_code'])?.toString().trim() ?? '';
      final part = await _findPart(identifier);
      if (part == null) {
        return jsonEncode({'error': 'ไม่พบอะไหล่ "$identifier"'});
      }
      final partId = part['part_id'].toString();
      final transType = args['trans_type']?.toString().toLowerCase().trim() ?? 'out'; // in, out, adjustment, return
      final qty = (args['quantity'] as num?)?.toInt() ?? 1;

      final transId = const Uuid().v4();
      await DbHelper.execute('''
        INSERT INTO spare_parts_transactions (
          trans_id, part_id, trans_type, quantity, reference_id, remarks, trans_date
        ) VALUES (
          @tid, @pid, @type, @qty, @ref, @rem, CURRENT_TIMESTAMP
        )
      ''', params: {
        'tid': transId,
        'pid': partId,
        'type': transType,
        'qty': qty,
        'ref': args['reference_id'],
        'rem': args['remarks'],
      });

      // Update Inventory on hand
      if (transType == 'in' || transType == 'return') {
        await DbHelper.execute(
          'UPDATE spare_parts_inventory SET quantity_on_hand = quantity_on_hand + @qty, updated_at = CURRENT_TIMESTAMP WHERE part_id = @id',
          params: {'id': partId, 'qty': qty},
        );
      } else if (transType == 'out') {
        await DbHelper.execute(
          'UPDATE spare_parts_inventory SET quantity_on_hand = MAX(0, quantity_on_hand - @qty), updated_at = CURRENT_TIMESTAMP WHERE part_id = @id',
          params: {'id': partId, 'qty': qty},
        );
      } else if (transType == 'adjustment') {
        await DbHelper.execute(
          'UPDATE spare_parts_inventory SET quantity_on_hand = @qty, last_counted_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE part_id = @id',
          params: {'id': partId, 'qty': qty},
        );
      }

      final inv = await DbHelper.queryOne('SELECT quantity_on_hand FROM spare_parts_inventory WHERE part_id = @id', params: {'id': partId});
      final currentQty = inv?['quantity_on_hand'] ?? 0;
      
      VectorDbService.syncSparePart(partId);

      return jsonEncode({
        'status': 'success',
        'trans_type': transType,
        'quantity': qty,
        'current_stock': currentQty,
        'message': 'บันทึกการตัดจ่าย/รับเข้าอะไหล่ ${part["part_name"]} จำนวน $qty เรียบร้อยแล้ว (ยอดคงเหลือปัจจุบัน: $currentQty)',
      });
    }

    if (action == 'link_machine') {
      final partIdentifier = (args['part_identifier'] ?? args['part_code'])?.toString().trim() ?? '';
      final machineIdentifier = args['machine_identifier']?.toString().trim() ?? '';
      final part = await _findPart(partIdentifier);
      final machine = await _findMachine(machineIdentifier);

      if (part == null || machine == null) {
        return jsonEncode({'error': 'ไม่พบอะไหล่หรือเครื่องจักรที่ระบุ'});
      }

      await DbHelper.execute('''
        INSERT OR REPLACE INTO part_machine_map (map_id, part_id, machine_id, quantity)
        VALUES (@mid, @pid, @machid, @qty)
      ''', params: {
        'mid': const Uuid().v4(),
        'pid': part['part_id'],
        'machid': machine['machine_id'],
        'qty': (args['quantity'] as num?)?.toInt() ?? 1,
      });

      return jsonEncode({
        'status': 'success',
        'message': 'ผูกอะไหล่ ${part["part_name"]} เข้ากับเครื่อง ${machine["machine_no"]} เรียบร้อยแล้ว',
      });
    }

    // Default: create_part / insert
    final partCode = args['part_code']?.toString().trim() ?? 'PART-${DateTime.now().millisecondsSinceEpoch % 100000}';
    final partName = args['part_name']?.toString().trim() ?? 'อะไหล่ใหม่';
    final partId = const Uuid().v4();
    final unitCost = (args['unit_cost'] as num?)?.toDouble() ?? 0.0;
    final reorderLevel = (args['reorder_level'] as num?)?.toInt() ?? 5;
    final initialQty = (args['initial_quantity'] as num?)?.toInt() ?? 0;

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
      'cat': args['category'] ?? 'mechanical',
      'cost': unitCost,
      'reorder': reorderLevel,
    });

    await DbHelper.execute('''
      INSERT OR REPLACE INTO spare_parts_inventory (
        inventory_id, part_id, quantity_on_hand, quantity_reserved, location, updated_at
      ) VALUES (
        @invid, @pid, @qty, 0, @loc, CURRENT_TIMESTAMP
      )
    ''', params: {
      'invid': const Uuid().v4(),
      'pid': partId,
      'qty': initialQty,
      'loc': args['location'] ?? 'A-01',
    });

    VectorDbService.syncSparePart(partId);

    return jsonEncode({
      'status': 'success',
      'part_id': partId,
      'part_code': partCode,
      'part_name': partName,
      'initial_stock': initialQty,
      'message': 'เพิ่มรายการอะไหล่ $partName ($partCode) สำเร็จ (สต็อกเริ่มต้น $initialQty)',
    });
  }

  // ── 9. TOOLS & EQUIPMENT CRUD (manage_tools) ──────────────────────────────

  static Future<String> _manageTools(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'create_tool';

    if (action == 'delete_tool' || action == 'delete') {
      final identifier = (args['tool_identifier'] ?? args['tool_code'])?.toString().trim() ?? '';
      await DbHelper.execute(
        'UPDATE tools SET is_active = 0, status = "lost" WHERE tool_code = @id OR tool_id = @id',
        params: {'id': identifier},
      );
      return jsonEncode({'status': 'success', 'message': 'ปิดการใช้งาน/ลบเครื่องมือช่าง "$identifier" เรียบร้อยแล้ว'});
    }

    if (action == 'update_tool' || action == 'update') {
      final identifier = (args['tool_identifier'] ?? args['tool_code'])?.toString().trim() ?? '';
      final tool = await _findTool(identifier);
      if (tool == null) {
        return jsonEncode({'error': 'ไม่พบเครื่องมือช่าง "$identifier" ที่ต้องการแก้ไข'});
      }
      final toolId = tool['tool_id'].toString();

      await DbHelper.execute('''
        UPDATE tools
        SET tool_name = COALESCE(@name, tool_name),
            category = COALESCE(@cat, category),
            price = COALESCE(@price, price),
            status = COALESCE(@status, status),
            notes = COALESCE(@notes, notes),
            is_active = COALESCE(@active, is_active)
        WHERE tool_id = @id
      ''', params: {
        'id': toolId,
        'name': args['tool_name'],
        'cat': args['category'],
        'price': (args['price'] as num?)?.toDouble(),
        'status': args['status']?.toString().toLowerCase(),
        'notes': args['notes'],
        'active': args['is_active'] == false ? 0 : (args['is_active'] == true ? 1 : null),
      });

      VectorDbService.syncTool(toolId);

      return jsonEncode({'status': 'success', 'message': 'อัปเดตข้อมูลเครื่องมือ ${tool["tool_code"]} สำเร็จ'});
    }

    if (action == 'record_transaction') {
      final identifier = (args['tool_identifier'] ?? args['tool_code'])?.toString().trim() ?? '';
      final tool = await _findTool(identifier);
      if (tool == null) {
        return jsonEncode({'error': 'ไม่พบเครื่องมือช่าง "$identifier"'});
      }
      final toolId = tool['tool_id'].toString();
      final actionType = args['action_type']?.toString().trim() ?? 'check_out'; // check_out, check_in, send_repair, receive_repair

      final adminUser = await DbHelper.queryOne("SELECT user_id FROM users LIMIT 1");
      final userId = adminUser?['user_id']?.toString() ?? 'U-ADMIN';

      final transId = const Uuid().v4();
      await DbHelper.execute('''
        INSERT INTO tool_transactions (
          transaction_id, tool_id, action_type, user_id, reference_no, notes, action_date
        ) VALUES (
          @tid, @toolId, @type, @uid, @ref, @notes, CURRENT_TIMESTAMP
        )
      ''', params: {
        'tid': transId,
        'toolId': toolId,
        'type': actionType,
        'uid': userId,
        'ref': args['reference_no'],
        'notes': args['notes'],
      });

      String newStatus = 'available';
      if (actionType == 'check_out') newStatus = 'in_use';
      if (actionType == 'send_repair') newStatus = 'repair';
      if (actionType == 'check_in' || actionType == 'receive_repair') newStatus = 'available';

      await DbHelper.execute(
        'UPDATE tools SET status = @status WHERE tool_id = @id',
        params: {'id': toolId, 'status': newStatus},
      );

      return jsonEncode({
        'status': 'success',
        'action_type': actionType,
        'tool_status': newStatus,
        'message': 'บันทึกการเบิก-คืนเครื่องมือ ${tool["tool_name"]} ($actionType) สำเร็จ (สถานะปัจจุบัน: $newStatus)',
      });
    }

    // Default: create_tool / insert
    final toolCode = args['tool_code']?.toString().trim() ?? 'TOOL-${DateTime.now().millisecondsSinceEpoch % 10000}';
    final toolName = args['tool_name']?.toString().trim() ?? 'เครื่องมือช่าง';
    final toolId = const Uuid().v4();

    await DbHelper.execute('''
      INSERT INTO tools (
        tool_id, tool_code, tool_name, category, status, price, notes, is_active, created_at
      ) VALUES (
        @id, @code, @name, @cat, @status, @price, @notes, 1, CURRENT_TIMESTAMP
      )
    ''', params: {
      'id': toolId,
      'code': toolCode,
      'name': toolName,
      'cat': args['category'] ?? 'hand_tools',
      'status': args['status'] ?? 'available',
      'price': (args['price'] as num?)?.toDouble() ?? 0.0,
      'notes': args['notes'],
    });

    VectorDbService.syncTool(toolId);

    return jsonEncode({
      'status': 'success',
      'tool_id': toolId,
      'tool_code': toolCode,
      'tool_name': toolName,
      'message': 'ลงทะเบียนเครื่องมือช่าง $toolName ($toolCode) สำเร็จ',
    });
  }

  // ── 10. OEE & RUNNING HOURS CRUD (manage_oee_logs) ─────────────────────────

  static Future<String> _manageOeeLogs(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'record_log';

    if (action == 'delete_log' || action == 'delete') {
      final hoursId = args['hours_id']?.toString().trim();
      final machineIdentifier = args['machine_identifier']?.toString().trim();
      final recordedDate = args['recorded_date']?.toString().trim();

      if (hoursId != null) {
        await DbHelper.execute('DELETE FROM machine_running_hours WHERE hours_id = @id', params: {'id': hoursId});
      } else if (machineIdentifier != null && recordedDate != null) {
        final machine = await _findMachine(machineIdentifier);
        if (machine != null) {
          await DbHelper.execute(
            'DELETE FROM machine_running_hours WHERE machine_id = @mid AND recorded_date = @date',
            params: {'mid': machine['machine_id'], 'date': recordedDate},
          );
        }
      }
      return jsonEncode({'status': 'success', 'message': 'ลบรายการบันทึก OEE เรียบร้อยแล้ว'});
    }

    if (action == 'update_log' || action == 'update') {
      final hoursId = args['hours_id']?.toString().trim();
      if (hoursId == null) {
        return jsonEncode({'error': 'กรุณาระบุ hours_id ที่ต้องการอัปเดต'});
      }
      await DbHelper.execute('''
        UPDATE machine_running_hours
        SET cumulative_hours = COALESCE(@cum, cumulative_hours),
            daily_hours = COALESCE(@daily, daily_hours),
            target_production = COALESCE(@target, target_production),
            actual_production = COALESCE(@actual, actual_production),
            good_production = COALESCE(@good, good_production)
        WHERE hours_id = @id
      ''', params: {
        'id': hoursId,
        'cum': (args['cumulative_hours'] as num?)?.toDouble(),
        'daily': (args['daily_hours'] as num?)?.toDouble(),
        'target': (args['target_production'] as num?)?.toDouble(),
        'actual': (args['actual_production'] as num?)?.toDouble(),
        'good': (args['good_production'] as num?)?.toDouble(),
      });
      return jsonEncode({'status': 'success', 'message': 'อัปเดตข้อมูลบันทึก OEE สำเร็จ'});
    }

    // Default: record_log / insert
    final machineIdentifier = args['machine_identifier']?.toString().trim() ?? '';
    final machine = await _findMachine(machineIdentifier);
    if (machine == null) {
      return jsonEncode({'error': 'ไม่พบเครื่องจักร "$machineIdentifier"'});
    }

    final recordedDate = args['recorded_date']?.toString().trim() ?? DateTime.now().toIso8601String().substring(0, 10);
    final hoursId = const Uuid().v4();

    await DbHelper.execute('''
      INSERT INTO machine_running_hours (
        hours_id, machine_id, cumulative_hours, daily_hours, recorded_date,
        target_production, actual_production, good_production, data_source, created_at
      ) VALUES (
        @id, @mid, @cum, @daily, @date,
        @target, @actual, @good, @source, CURRENT_TIMESTAMP
      )
    ''', params: {
      'id': hoursId,
      'mid': machine['machine_id'],
      'cum': (args['cumulative_hours'] as num?)?.toDouble() ?? 8.0,
      'daily': (args['daily_hours'] as num?)?.toDouble() ?? 8.0,
      'date': recordedDate,
      'target': (args['target_production'] as num?)?.toDouble() ?? 1000.0,
      'actual': (args['actual_production'] as num?)?.toDouble() ?? 950.0,
      'good': (args['good_production'] as num?)?.toDouble() ?? 920.0,
      'source': args['data_source'] ?? 'manual',
    });

    return jsonEncode({
      'status': 'success',
      'hours_id': hoursId,
      'machine_no': machine['machine_no'],
      'recorded_date': recordedDate,
      'message': 'บันทึกข้อมูล OEE และชั่วโมงการทำงานสำหรับเครื่อง ${machine["machine_no"]} ประจำวันที่ $recordedDate สำเร็จ',
    });
  }

  // ── 11. TECHNICIANS & SKILLS CRUD (manage_technicians) ─────────────────────

  static Future<String> _manageTechnicians(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'add_skill';

    final techIdentifier = args['technician_identifier']?.toString().trim() ?? '';
    final tech = await _findUser(techIdentifier);
    if (tech == null) {
      return jsonEncode({'error': 'ไม่พบข้อมูลช่าง/ผู้ใช้ "$techIdentifier" ในระบบ'});
    }
    final techId = tech['user_id'].toString();

    if (action == 'delete_skill' || action == 'delete') {
      final skillId = args['skill_id']?.toString().trim();
      final skillName = args['skill_name']?.toString().trim();
      await DbHelper.execute(
        'DELETE FROM technician_skills WHERE technician_id = @tid AND (skill_id = @id OR skill_name = @name)',
        params: {'tid': techId, 'id': skillId, 'name': skillName},
      );
      return jsonEncode({'status': 'success', 'message': 'ลบทักษะของช่าง ${tech["full_name"]} เรียบร้อยแล้ว'});
    }

    if (action == 'update_skill') {
      final skillName = args['skill_name']?.toString().trim() ?? '';
      await DbHelper.execute('''
        UPDATE technician_skills
        SET proficiency_level = COALESCE(@prof, proficiency_level),
            certified = COALESCE(@cert, certified)
        WHERE technician_id = @tid AND (skill_name = @name OR skill_id = @id)
      ''', params: {
        'tid': techId,
        'id': args['skill_id'],
        'name': skillName,
        'prof': args['proficiency_level'],
        'cert': args['certified'] == true ? 1 : (args['certified'] == false ? 0 : null),
      });
      return jsonEncode({'status': 'success', 'message': 'อัปเดตระดับทักษะของช่าง ${tech["full_name"]} สำเร็จ'});
    }

    if (action == 'set_availability') {
      final date = args['available_date']?.toString().trim() ?? DateTime.now().toIso8601String().substring(0, 10);
      final availId = const Uuid().v4();
      await DbHelper.execute('''
        INSERT OR REPLACE INTO technician_availability (
          avail_id, technician_id, available_date, available_hours, reserved_hours, created_at
        ) VALUES (
          @id, @tid, @date, @avail, @res, CURRENT_TIMESTAMP
        )
      ''', params: {
        'id': availId,
        'tid': techId,
        'date': date,
        'avail': (args['available_hours'] as num?)?.toDouble() ?? 8.0,
        'res': (args['reserved_hours'] as num?)?.toDouble() ?? 0.0,
      });
      return jsonEncode({
        'status': 'success',
        'technician': tech['full_name'],
        'date': date,
        'message': 'บันทึกเวลาพร้อมทำงานของช่าง ${tech["full_name"]} วันที่ $date สำเร็จ',
      });
    }

    // Default: add_skill
    final skillName = args['skill_name']?.toString().trim() ?? 'General Maintenance';
    final skillId = const Uuid().v4();

    await DbHelper.execute('''
      INSERT INTO technician_skills (
        skill_id, technician_id, skill_name, proficiency_level, certified, created_at
      ) VALUES (
        @id, @tid, @name, @prof, @cert, CURRENT_TIMESTAMP
      )
    ''', params: {
      'id': skillId,
      'tid': techId,
      'name': skillName,
      'prof': args['proficiency_level'] ?? 'intermediate',
      'cert': args['certified'] == true ? 1 : 0,
    });

    return jsonEncode({
      'status': 'success',
      'skill_id': skillId,
      'technician': tech['full_name'],
      'skill_name': skillName,
      'message': 'เพิ่มทักษะความชำนาญ "$skillName" ให้กับช่าง ${tech["full_name"]} สำเร็จ',
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

  static Future<String> _extractDocumentText(Map<String, dynamic> args) async {
    final filePath = (args['file_path'] ?? args['path'] ?? '')?.toString().trim() ?? '';
    if (filePath.isEmpty) {
      return jsonEncode({'error': 'กรุณาระบุที่อยู่ไฟล์ (file_path)'});
    }
    final maxPages = (args['max_pages'] as num?)?.toInt() ?? 50;
    final file = File(filePath);
    final text = await RagDocumentService.extractText(file: file, maxPages: maxPages);
    return jsonEncode({
      'status': 'success',
      'file_path': filePath,
      'file_name': p.basename(filePath),
      'extracted_text': text,
    });
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

  // ── WORK PROCESSES & SOP / JSA CRUD (manage_work_processes) ────────────────
  static Future<String> _manageWorkProcesses(Map<String, dynamic> args) async {
    final action = args['action']?.toString().toLowerCase().trim() ?? 'create_process';

    // 1. Bulk import SOP / JSA for multiple machines
    if (action == 'import_sop_bulk' || (args['processes'] is List && (args['processes'] as List).isNotEmpty)) {
      final list = args['processes'] as List;
      int imported = 0;
      final results = <Map<String, dynamic>>[];

      for (final raw in list) {
        if (raw is! Map) continue;
        final p = Map<String, dynamic>.from(raw);
        final mcId = p['machine_identifier']?.toString() ?? '';
        final mc = await _findMachine(mcId);
        final machineId = mc?['machine_id']?.toString();
        final machineNo = mc?['machine_no']?.toString() ?? mcId;

        final processId = const Uuid().v4();
        final now = DateTime.now();
        final processNo = p['process_no']?.toString().trim().isNotEmpty == true
            ? p['process_no']!.toString().trim()
            : (machineNo.isNotEmpty ? 'SOP-${machineNo.replaceAll(RegExp(r'[\s\-_]+'), '')}' : 'SOP-${DateFormat('yyMMdd-HHmm').format(now)}');
        final title = p['title']?.toString().trim().isNotEmpty == true
            ? p['title']!.toString().trim()
            : 'ขั้นตอนการปฏิบัติงานและความปลอดภัย (SOP/JSA) $machineNo';

        await DbHelper.execute('''
          INSERT OR REPLACE INTO work_processes (
            process_id, process_no, title, company, factory, department,
            method_type, work_type, machine_id, prepared_by, prepared_date,
            approved_by, approved_date, notes, status, created_at, updated_at
          ) VALUES (
            @id, @no, @title, @co, @fac, @dept,
            @method, @work_type, @mid, @prep_by, @prep_date,
            @appr_by, @appr_date, @notes, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
          )
        ''', params: {
          'id': processId,
          'no': processNo,
          'title': title,
          'co': p['company']?.toString() ?? '',
          'fac': p['factory']?.toString() ?? '',
          'dept': p['department']?.toString() ?? '',
          'method': p['method_type']?.toString() ?? 'current',
          'work_type': p['work_type']?.toString() ?? 'standard',
          'mid': machineId,
          'prep_by': p['prepared_by']?.toString() ?? 'AI Assistant',
          'prep_date': DateFormat('yyyy-MM-dd').format(now),
          'appr_by': p['approved_by']?.toString(),
          'appr_date': p['approved_date']?.toString(),
          'notes': p['notes']?.toString(),
        });

        // Insert steps
        final rawSteps = p['steps'];
        int stepCount = 0;
        if (rawSteps is List) {
          for (int sIdx = 0; sIdx < rawSteps.length; sIdx++) {
            final st = rawSteps[sIdx];
            if (st is! Map) continue;
            final stMap = Map<String, dynamic>.from(st);
            final stepId = const Uuid().v4();
            final stepNo = (stMap['step_no'] as num?)?.toInt() ?? (sIdx + 1);
            final desc = stMap['description']?.toString().trim() ?? '';
            if (desc.isEmpty) continue;

            final duration = (stMap['duration_minutes'] as num?)?.toDouble() ?? 5.0;
            final valType = stMap['value_type']?.toString() ?? 'va';
            final problemCause = stMap['problem_cause']?.toString() ?? stMap['hazard_risk']?.toString();
            final improvementIdea = stMap['improvement_idea']?.toString() ?? stMap['safety_control']?.toString();

            await DbHelper.execute('''
              INSERT INTO work_process_steps (
                step_id, process_id, step_no, description, event_type,
                duration_minutes, distance_meters, tools_used,
                value_type, problem_cause, improvement_idea, created_at
              ) VALUES (
                @sid, @pid, @sno, @desc, 'operation',
                @dur, 0.0, @tools,
                @val_type, @prob, @imp, CURRENT_TIMESTAMP
              )
            ''', params: {
              'sid': stepId,
              'pid': processId,
              'sno': stepNo,
              'desc': desc,
              'dur': duration,
              'tools': stMap['tools_used']?.toString(),
              'val_type': valType,
              'prob': problemCause,
              'imp': improvementIdea,
            });
            stepCount++;
          }
        }

        VectorDbService.syncWorkProcess(processId);
        imported++;
        results.add({
          'machine_no': machineNo,
          'process_no': processNo,
          'title': title,
          'steps_count': stepCount,
        });
      }

      return jsonEncode({
        'status': 'success',
        'imported_count': imported,
        'processes': results,
        'message': 'บันทึกขั้นตอนการทำงาน SOP/JSA สำเร็จทั้งหมด $imported เครื่อง',
      });
    }

    // 2. Single Process create or update
    final mcId = args['machine_identifier']?.toString() ?? '';
    final mc = await _findMachine(mcId);
    final machineId = mc?['machine_id']?.toString();
    final machineNo = mc?['machine_no']?.toString() ?? mcId;

    if (action == 'create_process' || action == 'import_sop') {
      final processId = const Uuid().v4();
      final now = DateTime.now();
      final processNo = args['process_no']?.toString().trim().isNotEmpty == true
          ? args['process_no']!.toString().trim()
          : (machineNo.isNotEmpty ? 'SOP-${machineNo.replaceAll(RegExp(r'[\s\-_]+'), '')}' : 'SOP-${DateFormat('yyMMdd-HHmm').format(now)}');
      final title = args['title']?.toString().trim().isNotEmpty == true
          ? args['title']!.toString().trim()
          : 'ขั้นตอนการปฏิบัติงานและความปลอดภัย (SOP/JSA) $machineNo';

      await DbHelper.execute('''
        INSERT OR REPLACE INTO work_processes (
          process_id, process_no, title, company, factory, department,
          method_type, work_type, machine_id, prepared_by, prepared_date,
          approved_by, approved_date, notes, status, created_at, updated_at
        ) VALUES (
          @id, @no, @title, @co, @fac, @dept,
          @method, @work_type, @mid, @prep_by, @prep_date,
          @appr_by, @appr_date, @notes, 'active', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        )
      ''', params: {
        'id': processId,
        'no': processNo,
        'title': title,
        'co': args['company']?.toString() ?? '',
        'fac': args['factory']?.toString() ?? '',
        'dept': args['department']?.toString() ?? '',
        'method': args['method_type']?.toString() ?? 'current',
        'work_type': args['work_type']?.toString() ?? 'standard',
        'mid': machineId,
        'prep_by': args['prepared_by']?.toString() ?? 'AI Assistant',
        'prep_date': DateFormat('yyyy-MM-dd').format(now),
        'appr_by': args['approved_by']?.toString(),
        'appr_date': args['approved_date']?.toString(),
        'notes': args['notes']?.toString(),
      });

      // Insert steps
      final rawSteps = args['steps'];
      int stepCount = 0;
      if (rawSteps is List) {
        for (int sIdx = 0; sIdx < rawSteps.length; sIdx++) {
          final st = rawSteps[sIdx];
          if (st is! Map) continue;
          final stMap = Map<String, dynamic>.from(st);
          final stepId = const Uuid().v4();
          final stepNo = (stMap['step_no'] as num?)?.toInt() ?? (sIdx + 1);
          final desc = stMap['description']?.toString().trim() ?? '';
          if (desc.isEmpty) continue;

          final duration = (stMap['duration_minutes'] as num?)?.toDouble() ?? 5.0;
          final valType = stMap['value_type']?.toString() ?? 'va';
          final problemCause = stMap['problem_cause']?.toString() ?? stMap['hazard_risk']?.toString();
          final improvementIdea = stMap['improvement_idea']?.toString() ?? stMap['safety_control']?.toString();

          await DbHelper.execute('''
            INSERT INTO work_process_steps (
              step_id, process_id, step_no, description, event_type,
              duration_minutes, distance_meters, tools_used,
              value_type, problem_cause, improvement_idea, created_at
            ) VALUES (
              @sid, @pid, @sno, @desc, 'operation',
              @dur, 0.0, @tools,
              @val_type, @prob, @imp, CURRENT_TIMESTAMP
            )
          ''', params: {
            'sid': stepId,
            'pid': processId,
            'sno': stepNo,
            'desc': desc,
            'dur': duration,
            'tools': stMap['tools_used']?.toString(),
            'val_type': valType,
            'prob': problemCause,
            'imp': improvementIdea,
          });
          stepCount++;
        }
      }

      VectorDbService.syncWorkProcess(processId);

      return jsonEncode({
        'status': 'success',
        'process_id': processId,
        'process_no': processNo,
        'title': title,
        'machine_no': machineNo,
        'steps_count': stepCount,
        'message': 'บันทึกขั้นตอนการปฏิบัติงาน $processNo สำหรับเครื่อง $machineNo สำเร็จ (รวม $stepCount ขั้นตอน)',
      });
    }

    if (action == 'add_steps') {
      final pIdentifier = args['process_identifier']?.toString() ?? '';
      final pRow = await DbHelper.queryOne(
        'SELECT process_id, process_no, title FROM work_processes WHERE process_id = @id OR process_no = @id OR machine_id = @mid LIMIT 1',
        params: {'id': pIdentifier, 'mid': machineId ?? ''},
      );
      if (pRow == null) {
        return jsonEncode({'status': 'error', 'message': 'ไม่พบกระบวนการขั้นตอนการทำงานที่ระบุ: $pIdentifier'});
      }
      final pid = pRow['process_id'] as String;

      final countRow = await DbHelper.queryOne('SELECT COUNT(*) as cnt FROM work_process_steps WHERE process_id = @pid', params: {'pid': pid});
      int currentCount = (countRow?['cnt'] as num?)?.toInt() ?? 0;

      final rawSteps = args['steps'];
      int added = 0;
      if (rawSteps is List) {
        for (final st in rawSteps) {
          if (st is! Map) continue;
          final stMap = Map<String, dynamic>.from(st);
          final stepId = const Uuid().v4();
          currentCount++;
          final desc = stMap['description']?.toString().trim() ?? '';
          if (desc.isEmpty) continue;

          await DbHelper.execute('''
            INSERT INTO work_process_steps (
              step_id, process_id, step_no, description, event_type,
              duration_minutes, distance_meters, tools_used,
              value_type, problem_cause, improvement_idea, created_at
            ) VALUES (
              @sid, @pid, @sno, @desc, 'operation',
              @dur, 0.0, @tools,
              @val_type, @prob, @imp, CURRENT_TIMESTAMP
            )
          ''', params: {
            'sid': stepId,
            'pid': pid,
            'sno': currentCount,
            'desc': desc,
            'dur': (stMap['duration_minutes'] as num?)?.toDouble() ?? 5.0,
            'tools': stMap['tools_used']?.toString(),
            'val_type': stMap['value_type']?.toString() ?? 'va',
            'prob': stMap['problem_cause']?.toString(),
            'imp': stMap['improvement_idea']?.toString(),
          });
          added++;
        }
      }

      VectorDbService.syncWorkProcess(pid);
      return jsonEncode({
        'status': 'success',
        'process_id': pid,
        'added_steps': added,
        'message': 'เพิ่มขั้นตอนใหม่ $added ขั้นตอนลงใน ${pRow['process_no']} สำเร็จ',
      });
    }

    if (action == 'delete_process') {
      final pIdentifier = args['process_identifier']?.toString() ?? '';
      await DbHelper.execute(
        'DELETE FROM work_processes WHERE process_id = @id OR process_no = @id',
        params: {'id': pIdentifier},
      );
      return jsonEncode({'status': 'success', 'message': 'ลบกระบวนการทำงาน $pIdentifier สำเร็จ'});
    }

    return jsonEncode({'status': 'error', 'message': 'ไม่รู้จักคำสั่ง action: $action'});
  }
}
