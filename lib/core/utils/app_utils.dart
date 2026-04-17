import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';

/// Security utilities
class SecurityUtils {
  SecurityUtils._();

  /// Hash a plain-text password with SHA-256
  static String hashPassword(String password) {
    final bytes = utf8.encode(password);
    return sha256.convert(bytes).toString();
  }

  /// Verify a plain-text password against a stored hash
  static bool verifyPassword(String plain, String hash) {
    return hashPassword(plain) == hash;
  }
}

/// Date/time formatters
class DateFormatters {
  DateFormatters._();

  static final _dateShort = DateFormat('dd/MM/yyyy');
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm');
  static final _timeOnly = DateFormat('HH:mm');
  static final _monthYear = DateFormat('MMM yyyy');

  static String formatDate(DateTime? dt) =>
      dt == null ? '-' : _dateShort.format(dt.toLocal());

  static String formatDateTime(DateTime? dt) =>
      dt == null ? '-' : _dateTime.format(dt.toLocal());

  static String formatTime(DateTime? dt) =>
      dt == null ? '-' : _timeOnly.format(dt.toLocal());

  static String formatMonthYear(DateTime? dt) =>
      dt == null ? '-' : _monthYear.format(dt.toLocal());

  static String timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'เมื่อกี้';
    if (diff.inMinutes < 60) return '${diff.inMinutes} นาทีที่แล้ว';
    if (diff.inHours < 24) return '${diff.inHours} ชั่วโมงที่แล้ว';
    if (diff.inDays < 7) return '${diff.inDays} วันที่แล้ว';
    return formatDate(dt);
  }
}

/// Number formatters
class NumberFormatters {
  NumberFormatters._();

  static final _decimal2 = NumberFormat('#,##0.00');
  static final _decimal0 = NumberFormat('#,##0');
  static final _currency = NumberFormat('#,##0.00');

  static String formatDecimal(num? v, {int decimals = 2}) {
    if (v == null) return '-';
    return decimals == 0 ? _decimal0.format(v) : _decimal2.format(v);
  }

  static String formatCurrency(num? v, {String symbol = '฿'}) =>
      v == null ? '-' : '$symbol ${_currency.format(v)}';

  static String formatHours(num? v) =>
      v == null ? '-' : '${_decimal2.format(v)} ชม.';
}

/// WO number generator (local — will be persisted to DB)
class WoNumberGenerator {
  static String generate(int sequence) {
    final year = DateTime.now().year;
    return 'WO-$year-${sequence.toString().padLeft(5, '0')}';
  }

  static String generatePermitNo(int sequence) {
    final year = DateTime.now().year;
    return 'WP-$year-${sequence.toString().padLeft(5, '0')}';
  }

  static String generatePrNo(int sequence) {
    final year = DateTime.now().year;
    return 'PR-$year-${sequence.toString().padLeft(5, '0')}';
  }
}
