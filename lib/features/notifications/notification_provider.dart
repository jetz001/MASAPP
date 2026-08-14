import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/db_connection.dart';
import 'notification_models.dart';
import '../auth/auth_provider.dart';
import 'package:uuid/uuid.dart';

final notificationRepositoryProvider = Provider((ref) => NotificationRepository());

class NotificationRepository {
  Future<List<AppNotification>> fetchNotifications(String userId) async {
    final db = DbConnection.instance.db;
    final res = await db.query(
      'notifications',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'created_at DESC',
    );
    return res.map((m) => AppNotification.fromMap(m)).toList();
  }

  Future<int> getUnreadCount(String userId) async {
    final db = DbConnection.instance.db;
    final res = await db.rawQuery(
      'SELECT COUNT(*) as count FROM notifications WHERE user_id = ? AND is_read = 0',
      [userId],
    );
    return (res.first['count'] as int?) ?? 0;
  }

  Future<void> markAsRead(String id) async {
    final db = DbConnection.instance.db;
    await db.update(
      'notifications',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markAllAsRead(String userId) async {
    final db = DbConnection.instance.db;
    await db.update(
      'notifications',
      {'is_read': 1},
      where: 'user_id = ? AND is_read = 0',
      whereArgs: [userId],
    );
  }

  Future<void> addNotification({
    required String userId,
    required String title,
    String? message,
    String? type,
    String? relatedId,
  }) async {
    final db = DbConnection.instance.db;
    final id = const Uuid().v4();
    await db.insert('notifications', {
      'id': id,
      'user_id': userId,
      'title': title,
      'message': message,
      'type': type,
      'related_id': relatedId,
      'is_read': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}

// Provider for all notifications of current user
final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final user = ref.watch(authProvider);
  if (user == null) return [];
  
  final repo = ref.watch(notificationRepositoryProvider);
  return repo.fetchNotifications(user.userId);
});

// Provider for unread count of current user
final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final user = ref.watch(authProvider);
  if (user == null) return 0;
  
  final repo = ref.watch(notificationRepositoryProvider);
  return repo.getUnreadCount(user.userId);
});
