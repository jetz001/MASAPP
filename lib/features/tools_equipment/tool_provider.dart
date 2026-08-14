import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/database/db_helper.dart';
import 'tool_models.dart';

final toolsProvider = FutureProvider<List<ToolItem>>((ref) async {
  final repo = ref.watch(toolsRepoProvider);
  return repo.getTools();
});

final toolsRepoProvider = Provider<ToolsRepository>((ref) {
  return ToolsRepository();
});

class ToolsRepository {
  Future<List<ToolItem>> getTools() async {
    final rows = await DbHelper.query(
      'SELECT * FROM tools WHERE is_active = 1 ORDER BY tool_code ASC',
    );
    return rows.map((row) => ToolItem.fromMap(row)).toList();
  }

  Future<void> addTool({
    required String toolCode,
    required String toolName,
    String? category,
    String? imagePath,
    DateTime? purchaseDate,
    double? price,
    String? notes,
  }) async {
    final toolId = const Uuid().v4();
    final tool = ToolItem(
      toolId: toolId,
      toolCode: toolCode,
      toolName: toolName,
      category: category,
      imagePath: imagePath,
      status: 'available',
      purchaseDate: purchaseDate,
      price: price,
      notes: notes,
      createdAt: DateTime.now(),
      isActive: true,
    );
    await DbHelper.execute(
      '''
      INSERT INTO tools (
        tool_id, tool_code, tool_name, category, image_path, status, purchase_date, price, notes, created_at, is_active
      ) VALUES (
        @tool_id, @tool_code, @tool_name, @category, @image_path, @status, @purchase_date, @price, @notes, @created_at, @is_active
      )
      ''',
      params: tool.toMap(),
    );
  }

  Future<void> updateTool({
    required String toolId,
    required String toolCode,
    required String toolName,
    String? category,
    String? imagePath,
    DateTime? purchaseDate,
    double? price,
    String? notes,
  }) async {
    await DbHelper.execute(
      '''
      UPDATE tools SET 
        tool_code = @tool_code, 
        tool_name = @tool_name, 
        category = @category, 
        image_path = @image_path, 
        purchase_date = @purchase_date, 
        price = @price, 
        notes = @notes
      WHERE tool_id = @tool_id
      ''',
      params: {
        'tool_id': toolId,
        'tool_code': toolCode,
        'tool_name': toolName,
        'category': category,
        'image_path': imagePath,
        'purchase_date': purchaseDate?.toIso8601String(),
        'price': price,
        'notes': notes,
      },
    );
  }

  Future<void> deleteTool(String toolId) async {
    await DbHelper.execute(
      'UPDATE tools SET is_active = 0 WHERE tool_id = @tool_id',
      params: {'tool_id': toolId},
    );
  }

  Future<void> recordTransaction({
    required String toolId,
    required String actionType,
    String? userId,
    String? referenceNo,
    String? notes,
  }) async {
    await DbHelper.transaction((txn) async {
      final transactionId = const Uuid().v4();
      final actionDate = DateTime.now();

      await DbHelper.txExecute(
        txn,
        '''
        INSERT INTO tool_transactions (
          transaction_id, tool_id, action_type, user_id, reference_no, notes, action_date
        ) VALUES (
          @transaction_id, @tool_id, @action_type, @user_id, @reference_no, @notes, @action_date
        )
        ''',
        params: {
          'transaction_id': transactionId,
          'tool_id': toolId,
          'action_type': actionType,
          'user_id': userId,
          'reference_no': referenceNo,
          'notes': notes,
          'action_date': actionDate.toIso8601String(),
        },
      );

      // Update tool status
      String newStatus;
      switch (actionType) {
        case 'check_out':
          newStatus = 'in_use';
          break;
        case 'check_in':
          newStatus = 'available';
          break;
        case 'send_repair':
          newStatus = 'repair';
          break;
        case 'receive_repair':
          newStatus = 'available';
          break;
        case 'lost':
          newStatus = 'lost';
          break;
        default:
          newStatus = 'available';
      }

      await DbHelper.txExecute(
        txn,
        'UPDATE tools SET status = @status WHERE tool_id = @tool_id',
        params: {
          'status': newStatus,
          'tool_id': toolId,
        },
      );
    });
  }
}
