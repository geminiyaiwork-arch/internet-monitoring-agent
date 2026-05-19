import 'dart:math';

/// Exponential backoff with jitter for offline heartbeat retries (TZ #13).
class ExponentialBackoff {
  ExponentialBackoff({
    this.initial = const Duration(seconds: 5),
    this.multiplier = 2,
    this.maxDelay = const Duration(minutes: 30),
    this.jitterFactor = 0.2,
  });

  final Duration initial;
  final double multiplier;
  final Duration maxDelay;
  final double jitterFactor;

  final Random _random = Random();

  Duration delayForAttempt(int attemptIndex) {
    if (attemptIndex < 0) return initial;
    final baseMs = initial.inMilliseconds * pow(multiplier, attemptIndex).toDouble();
    final capped = min(baseMs, maxDelay.inMilliseconds.toDouble());
    final jitter = capped * jitterFactor * (_random.nextDouble() * 2 - 1);
    final ms = max(initial.inMilliseconds, (capped + jitter).round());
    return Duration(milliseconds: ms);
  }
}
