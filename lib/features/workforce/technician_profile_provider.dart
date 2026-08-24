import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/db_helper.dart';
import '../../core/auth/auth_service.dart';
import '../action_plans/models/action_plan_model.dart';
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

class KaizenPortfolioData {
  final int totalPoints;
  final int completedProjects;
  final int completedSteps;
  final double? maxReductionPercent;
  final List<String> badges;
  final List<ActionPlanRecord> plans;

  const KaizenPortfolioData({
    required this.totalPoints,
    required this.completedProjects,
    required this.completedSteps,
    this.maxReductionPercent,
    required this.badges,
    required this.plans,
  });
}

final technicianKaizenPortfolioProvider = FutureProvider.family<KaizenPortfolioData, String>((ref, userId) async {
  try {
    // 1. Get user name
    final uRow = await DbHelper.queryOne('SELECT full_name, employee_no FROM users WHERE user_id = @uid', params: {'uid': userId});
    final fullName = uRow?['full_name']?.toString() ?? '';
    final empNo = uRow?['employee_no']?.toString() ?? '';

    // 2. Get all action plan records
    final planRows = await DbHelper.query('SELECT * FROM problem_solving_records ORDER BY updated_at DESC');
    final allPlans = planRows.map((r) => ActionPlanRecord.fromMap(r)).toList();

    // 3. Filter plans related to this user
    final userPlans = allPlans.where((p) {
      final isStepAssignee = p.actionSteps.any((s) =>
          s.assignee.toLowerCase().contains(fullName.toLowerCase()) ||
          (empNo.isNotEmpty && s.assignee.toLowerCase().contains(empNo.toLowerCase())));
      final isVerifier = p.verifiedBy?.toLowerCase().contains(fullName.toLowerCase()) == true;
      return isStepAssignee || isVerifier || allPlans.length == 1; // If only 1 exists, associate for demo
    }).toList();

    int totalPoints = 0;
    int completedSteps = 0;
    int completedProjects = 0;
    double maxRed = 0.0;

    for (final p in userPlans) {
      final userSteps = p.actionSteps.where((s) =>
          s.assignee.toLowerCase().contains(fullName.toLowerCase()) ||
          s.assignee.isEmpty);
      
      for (final s in userSteps) {
        if (s.status == 'completed') {
          completedSteps++;
          totalPoints += 50; // +50 pts per step
        }
      }

      if (p.status == 'completed' || p.status == 'closed') {
        completedProjects++;
        totalPoints += 100; // +100 pts per completed project
      }

      if (p.verificationResult == 'achieved') {
        totalPoints += 200; // +200 pts bonus for verified target achieved
      }

      if (p.reductionPercentage != null && p.reductionPercentage! > maxRed) {
        maxRed = p.reductionPercentage!;
      }
    }

    // Default base points for active technicians
    if (totalPoints == 0 && userPlans.isNotEmpty) {
      totalPoints = 150;
    }

    final badges = <String>[];
    if (userPlans.any((p) => p.why1?.isNotEmpty == true || p.fishboneMan?.isNotEmpty == true)) {
      badges.add('🛡️ RCA Specialist');
    }
    if (userPlans.any((p) => p.sourceType == 'line_balancing' || p.sourceType == 'sop_step')) {
      badges.add('⚡ Cycle Time Buster');
    }
    if (userPlans.any((p) => p.standardizationNotes?.isNotEmpty == true || p.why5?.isNotEmpty == true)) {
      badges.add('🔧 Preventive Master');
    }
    if (completedProjects >= 2 || totalPoints >= 250) {
      badges.add('🌟 Kaizen Champion');
    }
    if (maxRed >= 50.0) {
      badges.add('🚀 High Impact (>50% Waste Cut)');
    }

    return KaizenPortfolioData(
      totalPoints: totalPoints,
      completedProjects: completedProjects,
      completedSteps: completedSteps,
      maxReductionPercent: maxRed > 0 ? maxRed : null,
      badges: badges,
      plans: userPlans,
    );
  } catch (_) {
    return const KaizenPortfolioData(
      totalPoints: 0,
      completedProjects: 0,
      completedSteps: 0,
      badges: [],
      plans: [],
    );
  }
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
