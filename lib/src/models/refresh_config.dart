/// Configuration for token refresh behavior
class RefreshConfig {
  /// Buffer time before token expiration to trigger proactive refresh
  final Duration expirationBuffer;

  /// Whether to refresh tokens proactively before they expire
  final bool proactiveRefresh;

  /// Whether to refresh tokens in parallel for multiple requests
  final bool parallelRefresh;

  /// Maximum time to wait for a token refresh
  final Duration refreshTimeout;

  /// Authorization header key
  final String authorizationHeaderKey;

  /// Custom headers to include in refresh requests
  final Map<String, dynamic>? refreshHeaders;

  /// Callback when token refresh starts
  final void Function()? onRefreshStart;

  /// Callback when token refresh succeeds
  final void Function(dynamic newCredentials)? onRefreshSuccess;

  /// Callback when token refresh fails
  final void Function(dynamic error)? onRefreshFailure;

  /// Whether to log refresh operations
  final bool enableLogging;

  const RefreshConfig({
    this.expirationBuffer = const Duration(minutes: 5),
    this.proactiveRefresh = true,
    this.parallelRefresh = false,
    this.refreshTimeout = const Duration(seconds: 30),
    this.authorizationHeaderKey = 'authorization',
    this.refreshHeaders,
    this.onRefreshStart,
    this.onRefreshSuccess,
    this.onRefreshFailure,
    this.enableLogging = false,
  });

  RefreshConfig copyWith({
    Duration? expirationBuffer,
    bool? proactiveRefresh,
    bool? parallelRefresh,
    Duration? refreshTimeout,
    String? authorizationHeaderKey,
    Map<String, dynamic>? refreshHeaders,
    void Function()? onRefreshStart,
    void Function(dynamic newCredentials)? onRefreshSuccess,
    void Function(dynamic error)? onRefreshFailure,
    bool? enableLogging,
  }) {
    return RefreshConfig(
      expirationBuffer: expirationBuffer ?? this.expirationBuffer,
      proactiveRefresh: proactiveRefresh ?? this.proactiveRefresh,
      parallelRefresh: parallelRefresh ?? this.parallelRefresh,
      refreshTimeout: refreshTimeout ?? this.refreshTimeout,
      authorizationHeaderKey:
          authorizationHeaderKey ?? this.authorizationHeaderKey,
      refreshHeaders: refreshHeaders ?? this.refreshHeaders,
      onRefreshStart: onRefreshStart ?? this.onRefreshStart,
      onRefreshSuccess: onRefreshSuccess ?? this.onRefreshSuccess,
      onRefreshFailure: onRefreshFailure ?? this.onRefreshFailure,
      enableLogging: enableLogging ?? this.enableLogging,
    );
  }
}
