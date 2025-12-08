import 'dart:math' as math;
import 'package:dio/dio.dart';
import '../models/retry_config.dart';

/// Utility class for implementing retry policies
class RetryPolicy {
  final RetryConfig config;

  const RetryPolicy(this.config);

  /// Executes a function with retry logic
  Future<T> execute<T>(
    Future<T> Function() operation, {
    bool Function(dynamic error)? shouldRetry,
  }) async {
    int attemptCount = 0;
    dynamic lastError;

    while (attemptCount <= config.maxRetries) {
      try {
        return await operation();
      } catch (error) {
        lastError = error;
        attemptCount++;

        if (attemptCount > config.maxRetries) {
          rethrow;
        }

        bool retry = false;
        if (error is DioException) {
          retry = config.shouldRetry(error, attemptCount);
        } else if (shouldRetry != null) {
          retry = shouldRetry(error);
        }

        if (!retry) {
          rethrow;
        }

        final delay = config.calculateDelay(attemptCount);

        if (config.onRetry != null && error is DioException) {
          config.onRetry!(error, attemptCount, delay);
        }

        await Future.delayed(delay);
      }
    }

    throw lastError;
  }

  /// Calculates exponential backoff with jitter
  static Duration calculateExponentialBackoff({
    required Duration baseDelay,
    required int attemptCount,
    double multiplier = 2.0,
    Duration? maxDelay,
    double jitter = 0.1,
  }) {
    var delay =
        baseDelay.inMilliseconds * math.pow(multiplier, attemptCount - 1);

    if (jitter > 0) {
      final random = math.Random();
      final jitterAmount = delay * jitter;
      delay += (random.nextDouble() * 2 - 1) * jitterAmount;
    }

    if (maxDelay != null) {
      delay = math.min(delay, maxDelay.inMilliseconds.toDouble());
    }

    return Duration(milliseconds: delay.round());
  }
}
