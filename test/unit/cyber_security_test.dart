import 'package:flutter_test/flutter_test.dart';
import 'package:masapp/core/ai/ai_rate_limiter.dart';
import 'package:masapp/core/ai/ai_tool_handler.dart';
import 'package:masapp/core/auth/rbac_models.dart';
import 'package:masapp/core/utils/crypto_utils.dart';

void main() {
  group('Cybersecurity: API Flooding & Rapid Request Protection', () {
    setUp(() {
      AiRateLimiter.instance.reset();
    });

    test('RateLimiter permits initial request and locks during execution', () {
      final limiter = AiRateLimiter.instance;
      expect(limiter.canSend(), isTrue);

      // Acquire lock
      final acquired = limiter.acquireLock();
      expect(acquired, isTrue);

      // While locked, concurrent requests are blocked
      expect(limiter.canSend(), isFalse);
      expect(limiter.acquireLock(), isFalse);

      // Once released, cooldown applies
      limiter.releaseLock();
      // Back-to-back within default 800ms cooldown is still blocked
      expect(limiter.canSend(), isFalse);
      expect(limiter.remainingCooldownSeconds, greaterThanOrEqualTo(0));
    });

    test('RateLimiter enforces rolling 1-minute window limit (max 15 RPM)', () {
      final limiter = AiRateLimiter.instance;

      // Simulate 15 requests with zero minInterval
      for (int i = 0; i < AiRateLimiter.maxRequestsPerMinute; i++) {
        expect(limiter.canSend(minInterval: Duration.zero), isTrue);
        limiter.acquireLock(minInterval: Duration.zero);
        limiter.releaseLock();
      }

      // 16th request within the minute must be blocked
      expect(limiter.canSend(minInterval: Duration.zero), isFalse);
      expect(limiter.remainingCooldownSeconds, greaterThan(0));
    });
  });

  group('Cybersecurity: Path Traversal & Injection Defense', () {
    test('Directory traversal characters in module/entity paths are sanitized', () {
      const dirtyModule = '../../system32/cmd';
      const dirtyEntity = '..\\..\\hack.exe';

      final safeModule = dirtyModule.replaceAll(RegExp(r'[\\/:*?"<>|.]'), '_').trim();
      final safeEntity = dirtyEntity.replaceAll(RegExp(r'[\\/:*?"<>|.]'), '_').trim();

      expect(safeModule.contains('..'), isFalse);
      expect(safeModule.contains('/'), isFalse);
      expect(safeModule.contains('\\'), isFalse);
      expect(safeModule, equals('______system32_cmd'));

      expect(safeEntity.contains('..'), isFalse);
      expect(safeEntity.contains('/'), isFalse);
      expect(safeEntity.contains('\\'), isFalse);
      expect(safeEntity, equals('______hack_exe'));
    });
  });

  group('Cybersecurity: Password Hashing & Salt Verification', () {
    test('CryptoUtils generates salted bcrypt hashes and prevents plain-text exposure', () {
      const password = 'FactoryAdmin@2026';

      final hash1 = CryptoUtils.hashPassword(password);
      final hash2 = CryptoUtils.hashPassword(password);

      // Bcrypt hash verification
      expect(hash1.startsWith(r'$2'), isTrue);
      expect(hash2.startsWith(r'$2'), isTrue);

      // Salt verification: Two hashes of the same password MUST NOT be identical
      expect(hash1, isNot(equals(hash2)));

      // Verification correctness
      expect(CryptoUtils.verifyPassword(password, hash1), isTrue);
      expect(CryptoUtils.verifyPassword(password, hash2), isTrue);
      expect(CryptoUtils.verifyPassword('WrongPassword123', hash1), isFalse);
    });
  });

  group('Cybersecurity: RBAC & Privilege Escalation Defense', () {
    test('Viewer role has strictly read-only permissions and cannot mutate system', () {
      final viewerPerms = rolePermissions[UserRole.viewer] ?? {};

      expect(viewerPerms.contains(PermissionCategory.machineCreate), isFalse);
      expect(viewerPerms.contains(PermissionCategory.machineDelete), isFalse);
      expect(viewerPerms.contains(PermissionCategory.woCreate), isFalse);
      expect(viewerPerms.contains(PermissionCategory.woApprove), isFalse);
      expect(viewerPerms.contains(PermissionCategory.woClose), isFalse);
      expect(viewerPerms.contains(PermissionCategory.userManage), isFalse);
      expect(viewerPerms.contains(PermissionCategory.settingsManage), isFalse);
    });

    test('Only Administrator role can manage users and system settings', () {
      for (final role in UserRole.values) {
        final perms = rolePermissions[role] ?? {};
        if (role == UserRole.admin) {
          expect(perms.contains(PermissionCategory.userManage), isTrue);
          expect(perms.contains(PermissionCategory.settingsManage), isTrue);
        } else {
          expect(
            perms.contains(PermissionCategory.userManage),
            isFalse,
            reason: '${role.name} should not be able to manage users',
          );
          expect(
            perms.contains(PermissionCategory.settingsManage),
            isFalse,
            reason: '${role.name} should not be able to manage settings',
          );
        }
      }
    });
  });

  group('Cybersecurity: AI Tool Sandbox & Database Exfiltration Defense', () {
    test('AI cannot dump password hashes or API keys from sensitive tables', () async {
      final targets = ['users', 'user_sessions', 'app_settings', 'audit_log'];

      for (final target in targets) {
        final res = await AiToolHandler.handleToolCall(
          'query_database',
          {'sql': 'SELECT * FROM $target;'},
        );
        expect(res.contains('error'), isTrue);
        expect(res.contains('restricted'), isTrue);
      }
    });

    test('AI rejects malicious SQL injection payloads and mutating statements', () async {
      final payloads = [
        'DELETE FROM machines;',
        'DROP TABLE work_orders;',
        'UPDATE users SET role = "admin";',
        'INSERT INTO users (username) VALUES ("hacker");',
        'SELECT * FROM machines; DROP TABLE machines;',
        'ALTER TABLE users ADD COLUMN is_pwned TEXT;',
      ];

      for (final payload in payloads) {
        final res = await AiToolHandler.handleToolCall(
          'query_database',
          {'sql': payload},
        );
        expect(
          res.contains('error'),
          isTrue,
          reason: 'Payload should have been rejected: $payload',
        );
      }
    });
  });
}
