import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/db_helper.dart';
import '../../core/auth/auth_service.dart';
import '../work_orders/work_order_models.dart';
import 'workforce_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Models
// ─────────────────────────────────────────────────────────────────────────────

class TechnicianSkill {
  final String skillId;
  final String skillName;
  final String proficiencyLevel;
  final int? score;
  final String? ratedBy;
  final String? ratedAt;

  TechnicianSkill({
    required this.skillId,
    required this.skillName,
    required this.proficiencyLevel,
    this.score,
    this.ratedBy,
    this.ratedAt,
  });
}

class TechnicianAttachment {
  final String attachmentId;
  final String documentType; // 'certificate' or 'manual'
  final String fileName;
  final String filePath;
  final String uploadedAt;

  TechnicianAttachment({
    required this.attachmentId,
    required this.documentType,
    required this.fileName,
    required this.filePath,
    required this.uploadedAt,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final technicianDetailsProvider = FutureProvider.family<TechnicianProfile?, String>((ref, userId) async {
  final rows = await DbHelper.query(
    '''SELECT u.user_id, u.employee_no, u.full_name, u.role,
              u.email, u.phone, u.is_active,
              d.dept_name
       FROM users u
       LEFT JOIN departments d ON d.dept_id = u.dept_id
       WHERE u.user_id = @uid''',
    params: {'uid': userId},
  );

  if (rows.isEmpty) return null;

  final row = rows.first;
  final uid = row['user_id'] as String;

  final skillRows = await DbHelper.query(
    'SELECT skill_name FROM technician_skills WHERE technician_id = @uid',
    params: {'uid': uid},
  );
  final skills = skillRows.map((s) => s['skill_name'] as String).toList();

  final woResult = await DbHelper.queryOne(
    '''SELECT COUNT(*) as c FROM work_orders
       WHERE assigned_to = @uid AND status NOT IN ('completed','cancelled')''',
    params: {'uid': uid},
  );

  return TechnicianProfile(
    userId: uid,
    employeeNo: row['employee_no'] as String? ?? '-',
    fullName: row['full_name'] as String,
    role: row['role'] as String,
    deptName: row['dept_name'] as String?,
    email: row['email'] as String?,
    phone: row['phone'] as String?,
    isActive: row['is_active'] == 1,
    skills: skills,
    openWorkOrders: woResult?['c'] as int? ?? 0,
  );
});

final technicianTasksProvider = FutureProvider.family<List<WorkOrder>, String>((ref, userId) async {
  final rows = await DbHelper.query(
    '''SELECT * FROM work_orders
       WHERE assigned_to = @uid
       ORDER BY created_at DESC''',
    params: {'uid': userId},
  );

  return rows.map((row) => WorkOrder.fromMap(row)).toList();
});

final technicianAttachmentsProvider = FutureProvider.family<List<TechnicianAttachment>, String>((ref, userId) async {
  final rows = await DbHelper.query(
    '''SELECT * FROM technician_attachments
       WHERE technician_id = @uid
       ORDER BY uploaded_at DESC''',
    params: {'uid': userId},
  );

  return rows.map((row) => TechnicianAttachment(
    attachmentId: row['attachment_id'] as String,
    documentType: row['document_type'] as String,
    fileName: row['file_name'] as String,
    filePath: row['file_path'] as String,
    uploadedAt: row['uploaded_at'] as String,
  )).toList();
});

final technicianSkillsProvider = FutureProvider.family<List<TechnicianSkill>, String>((ref, userId) async {
  final rows = await DbHelper.query(
    '''SELECT * FROM technician_skills
       WHERE technician_id = @uid
       ORDER BY skill_name ASC''',
    params: {'uid': userId},
  );

  return rows.map((row) => TechnicianSkill(
    skillId: row['skill_id'] as String,
    skillName: row['skill_name'] as String,
    proficiencyLevel: row['proficiency_level'] as String? ?? 'intermediate',
    score: row['score'] as int?,
    ratedBy: row['rated_by'] as String?,
    ratedAt: row['rated_at'] as String?,
  )).toList();
});

// ─────────────────────────────────────────────────────────────────────────────
// Methods
// ─────────────────────────────────────────────────────────────────────────────

class TechnicianRepository {
  static const uuid = Uuid();

  static Future<void> uploadAttachment({
    required String technicianId,
    required String documentType,
    required String fileName,
    required String filePath,
  }) async {
    final uid = AuthService.currentUser?.userId ?? 'SYSTEM';
    await DbHelper.execute(
      '''INSERT INTO technician_attachments (
           attachment_id, technician_id, document_type, file_name, file_path, uploaded_by
         ) VALUES (@id, @tid, @type, @name, @path, @uid)''',
      params: {
        'id': uuid.v4(),
        'tid': technicianId,
        'type': documentType,
        'name': fileName,
        'path': filePath,
        'uid': uid,
      },
    );
  }

  static Future<void> deleteAttachment(String attachmentId) async {
    await DbHelper.execute(
      'DELETE FROM technician_attachments WHERE attachment_id = @id',
      params: {'id': attachmentId},
    );
  }

  static Future<void> updateSkillScore({
    required String skillId,
    required int score,
  }) async {
    final uid = AuthService.currentUser?.userId ?? 'SYSTEM';
    await DbHelper.execute(
      '''UPDATE technician_skills 
         SET score = @score, rated_by = @uid, rated_at = CURRENT_TIMESTAMP
         WHERE skill_id = @id''',
      params: {
        'score': score,
        'uid': uid,
        'id': skillId,
      },
    );
  }

  static Future<void> addSkill({
    required String technicianId,
    required String skillName,
  }) async {
    await DbHelper.execute(
      '''INSERT INTO technician_skills (
           skill_id, technician_id, skill_name, proficiency_level
         ) VALUES (@id, @tid, @name, 'intermediate')''',
      params: {
        'id': uuid.v4(),
        'tid': technicianId,
        'name': skillName,
      },
    );
  }
}
