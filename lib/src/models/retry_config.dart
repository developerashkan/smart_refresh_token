import 'package:dio/dio.dart';

/// Configuration for retry behavior
class RetryConfig {
  /// Maximum number of retry attempts
  final int maxRetries;

  /// Base delay between retries
  final Duration baseDelay;

  /// Maximum delay between retries
  final Duration maxDelay;

  /// Exponential backoff multiplier
  final double backoffMultiplier;

  /// Jitter factor (0.0 to 1.0) for randomizing delays
  final double jitter;

  /// HTTP status codes that should trigger a retry
  final Set<int> retryableStatusCodes;

  /// Dio exception types that should trigger a retry
  final Set<DioExceptionType> retryableExceptionTypes;

  /// Custom condition to determine if a request should be retried
  final bool Function(DioException error, int attemptCount)? retryCondition;

  /// Callback when a retry is about to happen
  final void Function(DioException error, int attemptCount, Duration delay)?
  onRetry;

  const RetryConfig({
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.jitter = 0.1,
    this.retryableStatusCodes = const {408, 429, 500, 502, 503, 504},
    this.retryableExceptionTypes = const {
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.connectionError,
    },
    this.retryCondition,
    this.onRetry,
  });

  /// Creates a conservative retry configuration
  factory RetryConfig.conservative() {
    return const RetryConfig(
      maxRetries: 2,
      baseDelay: Duration(seconds: 2),
      backoffMultiplier: 1.5,
    );
  }

  /// Creates an aggressive retry configuration
  factory RetryConfig.aggressive() {
    return const RetryConfig(
      maxRetries: 5,
      baseDelay: Duration(milliseconds: 500),
      backoffMultiplier: 2.5,
    );
  }

  /// Creates a configuration with no retries
  factory RetryConfig.noRetry() {
    return const RetryConfig(maxRetries: 0);
  }

  /// Calculates the delay for a specific retry attempt
  Duration calculateDelay(int attemptCount) {
    if (attemptCount <= 0) return Duration.zero;

    var delay =
        baseDelay.inMilliseconds * (backoffMultiplier * (attemptCount - 1));

    if (jitter > 0) {
      final jitterAmount = delay * jitter;
      final random = DateTime.now().millisecondsSinceEpoch % 1000 / 1000.0;
      delay += (random * 2 - 1) * jitterAmount;
    }

    delay = delay.clamp(0, maxDelay.inMilliseconds.toDouble());

    return Duration(milliseconds: delay.round());
  }

  /// Determines if an error should trigger a retry
  bool shouldRetry(DioException error, int attemptCount) {
    if (attemptCount >= maxRetries) return false;

    // Check custom condition first
    if (retryCondition != null) {
      return retryCondition!(error, attemptCount);
    }

    if (error.response?.statusCode != null &&
        retryableStatusCodes.contains(error.response!.statusCode)) {
      return true;
    }

    return retryableExceptionTypes.contains(error.type);
  }

  RetryConfig copyWith({
    int? maxRetries,
    Duration? baseDelay,
    Duration? maxDelay,
    double? backoffMultiplier,
    double? jitter,
    Set<int>? retryableStatusCodes,
    Set<DioExceptionType>? retryableExceptionTypes,
    bool Function(DioException error, int attemptCount)? retryCondition,
    void Function(DioException error, int attemptCount, Duration delay)?
    onRetry,
  }) {
    return RetryConfig(
      maxRetries: maxRetries ?? this.maxRetries,
      baseDelay: baseDelay ?? this.baseDelay,
      maxDelay: maxDelay ?? this.maxDelay,
      backoffMultiplier: backoffMultiplier ?? this.backoffMultiplier,
      jitter: jitter ?? this.jitter,
      retryableStatusCodes: retryableStatusCodes ?? this.retryableStatusCodes,
      retryableExceptionTypes:
          retryableExceptionTypes ?? this.retryableExceptionTypes,
      retryCondition: retryCondition ?? this.retryCondition,
      onRetry: onRetry ?? this.onRetry,
    );
  }
}
