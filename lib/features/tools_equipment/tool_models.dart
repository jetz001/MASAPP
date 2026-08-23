

class ToolItem {
  final String toolId;
  final String toolCode;
  final String toolName;
  final String? category;
  final String? imagePath;
  final String status; // available, in_use, repair, lost
  final DateTime? purchaseDate;
  final double? price;
  final String? notes;
  final DateTime createdAt;
  final bool isActive;

  ToolItem({
    required this.toolId,
    required this.toolCode,
    required this.toolName,
    this.category,
    this.imagePath,
    this.status = 'available',
    this.purchaseDate,
    this.price,
    this.notes,
    required this.createdAt,
    this.isActive = true,
  });

  factory ToolItem.fromMap(Map<String, dynamic> map) {
    DateTime parseDate(dynamic val) {
      if (val == null) return DateTime.now();
      if (val is DateTime) return val;
      return DateTime.tryParse(val.toString()) ?? DateTime.now();
    }

    DateTime? parseNullableDate(dynamic val) {
      if (val == null) return null;
      if (val is DateTime) return val;
      return DateTime.tryParse(val.toString());
    }

    return ToolItem(
      toolId: map['tool_id']?.toString() ?? '',
      toolCode: map['tool_code']?.toString() ?? '',
      toolName: map['tool_name']?.toString() ?? '',
      category: map['category']?.toString(),
      imagePath: map['image_path']?.toString(),
      status: map['status']?.toString() ?? 'available',
      purchaseDate: parseNullableDate(map['purchase_date']),
      price: (map['price'] as num?)?.toDouble(),
      notes: map['notes']?.toString(),
      createdAt: parseDate(map['created_at']),
      isActive: (map['is_active'] == 1 || map['is_active'] == true || map['is_active'] == null),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'tool_id': toolId,
      'tool_code': toolCode,
      'tool_name': toolName,
      'category': category,
      'image_path': imagePath,
      'status': status,
      'purchase_date': purchaseDate?.toIso8601String(),
      'price': price,
      'notes': notes,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive ? 1 : 0,
    };
  }

  ToolItem copyWith({
    String? toolId,
    String? toolCode,
    String? toolName,
    String? category,
    String? imagePath,
    String? status,
    DateTime? purchaseDate,
    double? price,
    String? notes,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return ToolItem(
      toolId: toolId ?? this.toolId,
      toolCode: toolCode ?? this.toolCode,
      toolName: toolName ?? this.toolName,
      category: category ?? this.category,
      imagePath: imagePath ?? this.imagePath,
      status: status ?? this.status,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      price: price ?? this.price,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }
}

class ToolTransaction {
  final String transactionId;
  final String toolId;
  final String actionType; // check_out, check_in, send_repair, receive_repair
  final String? userId;
  final String? referenceNo; // e.g. WO-2026-001
  final String? notes;
  final DateTime actionDate;

  ToolTransaction({
    required this.transactionId,
    required this.toolId,
    required this.actionType,
    this.userId,
    this.referenceNo,
    this.notes,
    required this.actionDate,
  });

  factory ToolTransaction.fromMap(Map<String, dynamic> map) {
    return ToolTransaction(
      transactionId: map['transaction_id'] as String,
      toolId: map['tool_id'] as String,
      actionType: map['action_type'] as String,
      userId: map['user_id'] as String?,
      referenceNo: map['reference_no'] as String?,
      notes: map['notes'] as String?,
      actionDate: DateTime.parse(map['action_date'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'transaction_id': transactionId,
      'tool_id': toolId,
      'action_type': actionType,
      'user_id': userId,
      'reference_no': referenceNo,
      'notes': notes,
      'action_date': actionDate.toIso8601String(),
    };
  }
}
