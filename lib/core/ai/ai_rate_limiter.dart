import 'dart:async';

/// Client-side rate limiter and flood protection for AI requests.
/// Protects external APIs (Gemini, OpenAI) from HTTP 429 quota exhaustion
/// and prevents local Ollama instances from crashing due to concurrent inference spikes.
class AiRateLimiter {
  static final AiRateLimiter instance = AiRateLimiter._();
  AiRateLimiter._();

  DateTime? _lastRequestTime;
  final List<DateTime> _requestTimestamps = [];
  bool _isLocked = false;

  /// Minimum interval between requests (e.g., 1 second cooldown)
  static const Duration defaultMinInterval = Duration(milliseconds: 800);

  /// Maximum requests allowed within a rolling 1-minute window (e.g. 15 RPM for free tiers)
  static const int maxRequestsPerMinute = 15;

  /// Check if a request is permitted right now
  bool canSend({Duration minInterval = defaultMinInterval}) {
    if (_isLocked) return false;

    final now = DateTime.now();
    if (_lastRequestTime != null && now.difference(_lastRequestTime!) < minInterval) {
      return false;
    }

    // Clean up timestamps older than 60 seconds
    _requestTimestamps.removeWhere((t) => now.difference(t).inSeconds >= 60);

    if (_requestTimestamps.length >= maxRequestsPerMinute) {
      return false;
    }

    return true;
  }

  /// Acquire lock for an in-flight request
  bool acquireLock({Duration minInterval = defaultMinInterval}) {
    if (!canSend(minInterval: minInterval)) return false;
    _isLocked = true;
    final now = DateTime.now();
    _lastRequestTime = now;
    _requestTimestamps.add(now);
    return true;
  }

  /// Release lock once the request completes (success or failure)
  void releaseLock() {
    _isLocked = false;
  }

  /// Get remaining cooldown seconds before next request is permitted
  int get remainingCooldownSeconds {
    final now = DateTime.now();
    if (_lastRequestTime != null) {
      final elapsed = now.difference(_lastRequestTime!);
      if (elapsed < defaultMinInterval) {
        return ((defaultMinInterval - elapsed).inMilliseconds / 1000).ceil();
      }
    }

    _requestTimestamps.removeWhere((t) => now.difference(t).inSeconds >= 60);
    if (_requestTimestamps.length >= maxRequestsPerMinute && _requestTimestamps.isNotEmpty) {
      final oldest = _requestTimestamps.first;
      final waitMs = 60000 - now.difference(oldest).inMilliseconds;
      return (waitMs / 1000).ceil().clamp(1, 60);
    }

    return 0;
  }

  /// Reset all limits (useful for test suites)
  void reset() {
    _lastRequestTime = null;
    _requestTimestamps.clear();
    _isLocked = false;
  }
}
