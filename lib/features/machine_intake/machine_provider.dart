import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/db_helper.dart';
import '../../core/utils/crypto_utils.dart';
import 'machine_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Repository
// ─────────────────────────────────────────────────────────────────────────────

class MachineRepository {
  /// Fetch all machines (list view)
  Future<List<MachineModel>> fetchAll({
    bool activeOnly = true,
    String? searchQuery,
    String? statusFilter,
    String? categoryId,
  }) async {
    final where = <String>['1=1'];
    final params = <String, dynamic>{};

    if (activeOnly) where.add('m.is_active = 1');
    if (statusFilter != null && statusFilter.isNotEmpty) {
      where.add("m.status = @status");
      params['status'] = statusFilter;
    }
    if (categoryId != null && categoryId.isNotEmpty) {
      where.add("m.category_id = @cat");
      params['cat'] = categoryId;
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      where.add("""(
        LOWER(m.machine_no) LIKE @q OR
        LOWER(m.machine_name) LIKE @q OR
        LOWER(m.brand) LIKE @q OR
        LOWER(m.model) LIKE @q OR
        LOWER(m.serial_no) LIKE @q OR
        LOWER(m.location) LIKE @q
      )""");
      params['q'] = '%${searchQuery.toLowerCase()}%';
    }

    final sql = '''
      SELECT
        m.machine_id, m.machine_no, m.machine_name, m.asset_no, m.brand, m.model, m.serial_no,
        m.status, m.location, m.installation_date, m.purchase_cost,
        m.handover_completed, m.is_active, m.notes, m.created_at,
        mc.name AS category_name,
        d.dept_name,
        COALESCE(rh.cumulative_hours, 0) AS total_running_hours,
        mh_s3.status AS stage3_status
      FROM machines m
      LEFT JOIN machine_categories mc ON mc.category_id = m.category_id
      LEFT JOIN departments d ON d.dept_id = m.dept_id
      LEFT JOIN (
        SELECT machine_id, cumulative_hours FROM machine_running_hours
        GROUP BY machine_id HAVING MAX(recorded_date)
      ) rh ON rh.machine_id = m.machine_id
      LEFT JOIN machine_handover mh_s3 ON mh_s3.machine_id = m.machine_id AND mh_s3.stage = 'stage3'
      WHERE ${where.join(' AND ')}
      ORDER BY m.created_at DESC
    ''';

    final rows = await DbHelper.query(sql, params: params);
    return rows.map(MachineModel.fromMap).toList();
  }

  /// Fetch single machine with specs and handover info
  Future<MachineModel?> fetchById(String machineId) async {
    final row = await DbHelper.queryOne(
      '''
      SELECT m.*, mc.name AS category_name, d.dept_name,
             s.name AS supplier_name
      FROM machines m
      LEFT JOIN machine_categories mc ON mc.category_id = m.category_id
      LEFT JOIN departments d ON d.dept_id = m.dept_id
      LEFT JOIN suppliers s ON s.supplier_id = m.supplier_id
      WHERE m.machine_id = @id
      ''',
      params: {'id': machineId},
    );
    if (row == null) return null;

    // Specs
    final specRow = await DbHelper.queryOne(
      'SELECT * FROM machine_specs WHERE machine_id = @id',
      params: {'id': machineId},
    );
    final specs = specRow != null ? MachineSpecs.fromMap(specRow) : null;

    // Handovers
    final handoverRows = await DbHelper.query(
      'SELECT * FROM machine_handover WHERE machine_id = @id ORDER BY stage',
      params: {'id': machineId},
    );
    HandoverInfo? s1, s2, s3;
    for (final h in handoverRows) {
      final info = HandoverInfo.fromMap(h);
      switch (info.stage) {
        case HandoverStage.stage1:
          s1 = info;
        case HandoverStage.stage2:
          s2 = info;
        case HandoverStage.stage3:
          s3 = info;
      }
    }

    return MachineModel.fromMap(row).copyWithDetails(
      specs: specs,
      stage1: s1,
      stage2: s2,
      stage3: s3,
    );
  }

  /// Check if a specific field (machine_no, asset_no) already exists
  Future<bool> isDuplicate(String field, String value, {String? excludeId}) async {
    final sql = excludeId != null
        ? 'SELECT COUNT(*) as cnt FROM machines WHERE $field = @val AND machine_id != @ex'
        : 'SELECT COUNT(*) as cnt FROM machines WHERE $field = @val';
    
    final params = {'val': value};
    if (excludeId != null) params['ex'] = excludeId;

    final row = await DbHelper.queryOne(sql, params: params);
    return (row?['cnt'] as int? ?? 0) > 0;
  }

  /// Insert a new machine and specs, return the new machine_id
  Future<String> createMachine({
    required Map<String, dynamic> machineData,
    Map<String, dynamic>? specsData,
    required String createdBy,
  }) async {
    return await DbHelper.transaction((tx) async {
      final machineId = const Uuid().v4();
      await DbHelper.txExecute(
        tx,
        '''
          INSERT INTO machines (
            machine_id, machine_no, machine_name, asset_no, brand, model, serial_no,
            category_id, dept_id, location, installation_date,
            warranty_expiry, purchase_cost, supplier_id, notes, created_by
          ) VALUES (
            @id, @machine_no, @machine_name, @asset_no, @brand, @model, @serial_no,
            @category_id, @dept_id, @location, @installation_date,
            @warranty_expiry, @purchase_cost, @supplier_id, @notes, @created_by
          )
        ''',
        params: machineData..addAll({'created_by': createdBy, 'id': machineId}),
      );

      if (specsData != null && specsData.isNotEmpty) {
        await DbHelper.txExecute(
          tx,
          '''
            INSERT INTO machine_specs (
              spec_id, machine_id, power_kw, voltage_v, current_a, frequency_hz,
              capacity, capacity_unit, weight_kg, dim_length_mm,
              dim_width_mm, dim_height_mm, rpm
            ) VALUES (
              @sid, @machine_id, @power_kw, @voltage_v, @current_a, @frequency_hz,
              @capacity, @capacity_unit, @weight_kg, @dim_length_mm,
              @dim_width_mm, @dim_height_mm, @rpm
            )
          ''',
          params: specsData..addAll({'machine_id': machineId, 'sid': const Uuid().v4()}),
        );
      }

      // Create 3 handover stage records
      for (final stage in ['stage1', 'stage2', 'stage3']) {
        await DbHelper.txExecute(
          tx,
          '''
            INSERT INTO machine_handover (handover_id, machine_id, stage, status)
            VALUES (@hid, @mid, @stage, 'pending')
          ''',
          params: {'mid': machineId, 'stage': stage, 'hid': const Uuid().v4()},
        );
      }

      return machineId;
    });
  }

  /// Update machine info and specs in a transaction
  Future<void> updateMachine({
    required String machineId,
    required Map<String, dynamic> machineData,
    Map<String, dynamic>? specsData,
  }) async {
    await DbHelper.transaction((tx) async {
      // Update basic info
      await DbHelper.txExecute(
        tx,
        '''
        UPDATE machines SET
          machine_no = @machine_no, machine_name = @machine_name, asset_no = @asset_no,
          brand = @brand, model = @model, serial_no = @serial_no,
          category_id = @category_id, dept_id = @dept_id,
          location = @location, installation_date = @installation_date,
          warranty_expiry = @warranty_expiry, purchase_cost = @purchase_cost,
          supplier_id = @supplier_id, notes = @notes,
          updated_at = CURRENT_TIMESTAMP
        WHERE machine_id = @id
        ''',
        params: machineData..['id'] = machineId,
      );

      // Update or Insert specs
      if (specsData != null && specsData.isNotEmpty) {
        final existing = await DbHelper.txQuery(
          tx, 'SELECT spec_id FROM machine_specs WHERE machine_id = @id',
          params: {'id': machineId},
        );

        if (existing.isNotEmpty) {
          await DbHelper.txExecute(
            tx,
            '''
            UPDATE machine_specs SET
              power_kw = @power_kw, voltage_v = @voltage_v, current_a = @current_a,
              frequency_hz = @frequency_hz, capacity = @capacity,
              capacity_unit = @capacity_unit, weight_kg = @weight_kg,
              dim_length_mm = @dim_length_mm, dim_width_mm = @dim_width_mm,
              dim_height_mm = @dim_height_mm, rpm = @rpm
            WHERE machine_id = @machine_id
            ''',
            params: specsData..['machine_id'] = machineId,
          );
        } else {
          await DbHelper.txExecute(
            tx,
            '''
            INSERT INTO machine_specs (
              spec_id, machine_id, power_kw, voltage_v, current_a, frequency_hz,
              capacity, capacity_unit, weight_kg, dim_length_mm,
              dim_width_mm, dim_height_mm, rpm
            ) VALUES (
              @sid, @machine_id, @power_kw, @voltage_v, @current_a, @frequency_hz,
              @capacity, @capacity_unit, @weight_kg, @dim_length_mm,
              @dim_width_mm, @dim_height_mm, @rpm
            )
            ''',
            params: specsData..addAll({'machine_id': machineId, 'sid': const Uuid().v4()}),
          );
        }
      }
      return null;
    });
  }

  /// Soft-delete a machine (admin only)
  Future<void> deleteMachine(String machineId) async {
    await DbHelper.execute(
      'UPDATE machines SET is_active = 0, updated_at = CURRENT_TIMESTAMP WHERE machine_id = @id',
      params: {'id': machineId},
    );
  }

  /// Verify user PIN for approval, or set it if null
  Future<bool> verifyApprovalPin(String userId, String pin) async {
    final row = await DbHelper.queryOne(
      'SELECT approval_pin_hash FROM users WHERE user_id = @uid',
      params: {'uid': userId},
    );
    if (row == null) return false;

    final hash = row['approval_pin_hash']?.toString();
    if (hash == null || hash.isEmpty) {
      // First time setting PIN
      final newHash = CryptoUtils.hashPassword(pin);
      await DbHelper.execute(
        'UPDATE users SET approval_pin_hash = @hash WHERE user_id = @uid',
        params: {'uid': userId, 'hash': newHash},
      );
      return true;
    }

    return CryptoUtils.verifyPassword(pin, hash);
  }

  /// Change current user PIN
  Future<String?> changeUserPin(String userId, String oldPin, String newPin) async {
    final row = await DbHelper.queryOne(
      'SELECT approval_pin_hash FROM users WHERE user_id = @uid',
      params: {'uid': userId},
    );
    if (row == null) return 'ไม่พบข้อมูลผู้ใช้';

    final hash = row['approval_pin_hash']?.toString();
    if (hash != null && hash.isNotEmpty) {
      if (!CryptoUtils.verifyPassword(oldPin, hash)) {
        return 'รหัส PIN เดิมไม่ถูกต้อง';
      }
    }

    final newHash = CryptoUtils.hashPassword(newPin);
    await DbHelper.execute(
      'UPDATE users SET approval_pin_hash = @hash WHERE user_id = @uid',
      params: {'uid': userId, 'hash': newHash},
    );
    return null;
  }

  /// Reset a user's PIN (Admin only)
  Future<void> resetUserPin(String targetUserId) async {
    await DbHelper.execute(
      'UPDATE users SET approval_pin_hash = NULL WHERE user_id = @uid',
      params: {'uid': targetUserId},
    );
  }

  /// Update handover stage status
  Future<void> updateHandoverStage({
    required String machineId,
    required HandoverStage stage,
    required HandoverStatus status,
    required String performedBy,
    String? notes,
  }) async {
    final isApproval = status == HandoverStatus.approved;
    final sql = isApproval 
      ? '''
        UPDATE machine_handover SET
          status = @status,
          approved_by = @user,
          approved_at = CURRENT_TIMESTAMP,
          notes = @notes,
          updated_at = CURRENT_TIMESTAMP
        WHERE machine_id = @mid AND stage = @stage
        '''
      : '''
        UPDATE machine_handover SET
          status = @status,
          performed_by = @user,
          performed_at = CURRENT_TIMESTAMP,
          notes = @notes,
          updated_at = CURRENT_TIMESTAMP
        WHERE machine_id = @mid AND stage = @stage
        ''';

    await DbHelper.execute(
      sql,
      params: {
        'mid': machineId,
        'stage': stage.dbValue,
        'status': status.name.replaceAll('InProgress', '_in_progress').toLowerCase().replaceAll('inprogress', 'in_progress'),
        'user': performedBy,
        'notes': notes,
      },
    );

    // Check if all 3 stages are done → mark machine handover_completed
    final stages = await DbHelper.query(
      "SELECT status FROM machine_handover WHERE machine_id = @mid",
      params: {'mid': machineId},
    );
    final allApproved = stages.every((s) => s['status'] == 'approved');
    if (allApproved) {
      await DbHelper.execute(
        'UPDATE machines SET handover_completed = 1, updated_at = CURRENT_TIMESTAMP WHERE machine_id = @mid',
        params: {'mid': machineId},
      );
    }
  }

  /// Fetch checklist results for a specific handover stage
  Future<List<ChecklistResult>> fetchHandoverResults(String handoverId) async {
    final rows = await DbHelper.query(
      'SELECT * FROM handover_checklist_results WHERE handover_id = @hid',
      params: {'hid': handoverId},
    );
    return rows.map((r) => ChecklistResult(
      resultId: r['result_id'].toString(),
      itemName: r['item_name'].toString(),
      result: r['result']?.toString(),
      actualValue: r['actual_value']?.toString(),
      remarks: r['remarks']?.toString(),
    )).toList();
  }

  /// Save checklist results for a handover stage
  Future<void> saveChecklistResults({
    required String handoverId,
    required List<Map<String, dynamic>> results,
  }) async {
    await DbHelper.transaction((tx) async {
      // Clear existing results for this handover
      await DbHelper.txExecute(
        tx,
        'DELETE FROM handover_checklist_results WHERE handover_id = @hid',
        params: {'hid': handoverId},
      );

      for (final r in results) {
        await DbHelper.txExecute(
          tx,
          '''
            INSERT INTO handover_checklist_results (result_id, handover_id, item_name, result, actual_value, remarks)
            VALUES (@rid, @hid, @item, @result, @value, @remarks)
          ''',
          params: {
            'rid': const Uuid().v4(),
            'hid': handoverId,
            'item': r['item_name'],
            'result': r['result'],
            'value': r['actual_value'],
            'remarks': r['remarks'],
          },
        );
      }
      return null;
    });
  }

  /// Fetch categories for dropdown
  Future<List<Map<String, dynamic>>> fetchCategories() async {
    return DbHelper.query('SELECT category_id, code, name FROM machine_categories ORDER BY name');
  }

  /// Fetch departments for dropdown
  Future<List<Map<String, dynamic>>> fetchDepartments() async {
    return DbHelper.query('SELECT dept_id, dept_code, dept_name FROM departments ORDER BY dept_name');
  }

  /// Fetch suppliers for dropdown
  Future<List<Map<String, dynamic>>> fetchSuppliers() async {
    return DbHelper.query("SELECT supplier_id, supplier_code, name FROM suppliers WHERE is_active = 1 ORDER BY name");
  }

  /// Save an attachment record to the database
  Future<void> saveAttachment({
    required String handoverId,
    required String fileName,
    required String filePath,
    required int fileSize,
    required String mimeType,
    required String userId,
  }) async {
    await DbHelper.execute(
      '''
      INSERT INTO handover_attachments (
        attachment_id, handover_id, file_name, file_path, file_size, mime_type, uploaded_by
      ) VALUES (@id, @hid, @name, @path, @size, @mime, @uid)
      ''',
      params: {
        'id': const Uuid().v4(),
        'hid': handoverId,
        'name': fileName,
        'path': filePath,
        'size': fileSize,
        'mime': mimeType,
        'uid': userId,
      },
    );
  }

  /// Fetch all attachments for a specific machine's handover stages
  Future<List<Map<String, dynamic>>> fetchAttachments(String machineId) async {
    return DbHelper.query(
      '''
      SELECT a.*, h.stage
      FROM handover_attachments a
      JOIN machine_handover h ON h.handover_id = a.handover_id
      WHERE h.machine_id = @mid
      ORDER BY a.uploaded_at DESC
      ''',
      params: {'mid': machineId},
    );
  }

  /// Delete an attachment record
  Future<void> deleteAttachment(String attachmentId) async {
    await DbHelper.execute(
      'DELETE FROM handover_attachments WHERE attachment_id = @id',
      params: {'id': attachmentId},
    );
  }
}

// Extension to allow copying a MachineModel with extra details
extension MachineModelCopy on MachineModel {
  MachineModel copyWithDetails({
    MachineSpecs? specs,
    HandoverInfo? stage1,
    HandoverInfo? stage2,
    HandoverInfo? stage3,
  }) {
    return MachineModel(
      machineId: machineId,
      machineNo: machineNo,
      machineName: machineName,
      assetNo: assetNo,
      brand: brand,
      model: model,
      serialNo: serialNo,
      categoryId: categoryId,
      categoryName: categoryName,
      deptId: deptId,
      deptName: deptName,
      location: location,
      status: status,
      installationDate: installationDate,
      warrantyExpiry: warrantyExpiry,
      purchaseCost: purchaseCost,
      supplierId: supplierId,
      supplierName: supplierName,
      handoverCompleted: handoverCompleted,
      isActive: isActive,
      notes: notes,
      createdAt: createdAt,
      specs: specs ?? this.specs,
      stage1: stage1 ?? this.stage1,
      stage2: stage2 ?? this.stage2,
      stage3: stage3 ?? this.stage3,
      totalRunningHours: totalRunningHours,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final machineRepositoryProvider = Provider<MachineRepository>(
  (_) => MachineRepository(),
);

final machineListProvider =
    FutureProvider.family<List<MachineModel>, MachineListFilter>(
  (ref, filter) async {
    final repo = ref.watch(machineRepositoryProvider);
    return repo.fetchAll(
      searchQuery: filter.searchQuery,
      statusFilter: filter.status,
      categoryId: filter.categoryId,
    );
  },
);

class MachineListFilter {
  final String? searchQuery;
  final String? status;
  final String? categoryId;

  const MachineListFilter({this.searchQuery, this.status, this.categoryId});

  @override
  bool operator ==(Object other) =>
      other is MachineListFilter &&
      other.searchQuery == searchQuery &&
      other.status == status &&
      other.categoryId == categoryId;

  @override
  int get hashCode => Object.hash(searchQuery, status, categoryId);
}

final singleMachineProvider =
    FutureProvider.family<MachineModel?, String>((ref, id) async {
  final repo = ref.watch(machineRepositoryProvider);
  return repo.fetchById(id);
});

final categoriesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(machineRepositoryProvider).fetchCategories();
});

final departmentsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(machineRepositoryProvider).fetchDepartments();
});

final suppliersProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.watch(machineRepositoryProvider).fetchSuppliers();
});
