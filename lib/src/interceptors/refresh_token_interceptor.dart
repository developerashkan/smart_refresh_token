import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:synchronized/synchronized.dart';
import '../models/credentials.dart';
import '../models/retry_config.dart';
import '../models/refresh_config.dart';
import '../storage/token_storage.dart';
import '../utils/retry_policy.dart';
import '../utils/logger.dart';

/// Callback type for token refresh
typedef TokenRefresher =
    Future<Credentials?> Function(String refreshToken, Dio client);

/// Callback type for authentication failure
typedef OnAuthFailure = FutureOr<void> Function();

/// Advanced Dio interceptor for automatic token refresh with retry logic
class RefreshTokenInterceptor extends Interceptor {
  final TokenStorage tokenStorage;
  final TokenRefresher tokenRefresher;
  final OnAuthFailure onAuthFailure;
  final Dio? refreshDio;
  final RefreshConfig refreshConfig;
  final RetryConfig retryConfig;
  final RefreshTokenLogger logger;

  final Lock _refreshLock = Lock();

  RefreshTokenInterceptor({
    required this.tokenStorage,
    required this.tokenRefresher,
    required this.onAuthFailure,
    this.refreshDio,
    RefreshConfig? refreshConfig,
    RetryConfig? retryConfig,
    RefreshTokenLogger? logger,
  }) : refreshConfig = refreshConfig ?? const RefreshConfig(),
       retryConfig = retryConfig ?? const RetryConfig(),
       logger = logger ?? const RefreshTokenLogger();

  Future<Dio> _getRefreshDio() async {
    return refreshDio ?? Dio();
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      logger.debug('Processing request: ${options.uri}');

      final shouldProceed = await _attachAuthorizationAndMaybeRefresh(options);

      if (shouldProceed) {
        handler.next(options);
      } else {
        logger.error('Authentication failed - unable to refresh token');
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            error: 'Authentication failed - unable to refresh token',
          ),
        );
      }
    } catch (e, st) {
      logger.error('Unexpected error in onRequest', e, st);
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: 'Unexpected error in refresh interceptor: $e',
          stackTrace: st,
        ),
      );
    }
  }

  Future<bool> _attachAuthorizationAndMaybeRefresh(
    RequestOptions options,
  ) async {
    return await _refreshLock.synchronized(() async {
      final credentials = await tokenStorage.read();

      if (credentials == null) {
        logger.info('No credentials found');
        await onAuthFailure();
        return false;
      }

      final needsRefresh = refreshConfig.proactiveRefresh
          ? credentials.isAccessTokenExpiringSoon(
              refreshConfig.expirationBuffer,
            )
          : credentials.isAccessTokenExpired;

      if (!needsRefresh) {
        logger.debug('Token is valid, attaching to request');
        options.headers[refreshConfig.authorizationHeaderKey] =
            credentials.authorizationHeaderValue;
        return true;
      }

      logger.info('Token expired or expiring soon, refreshing...');

      if (credentials.isRefreshTokenExpired) {
        logger.error('Refresh token is expired');
        await tokenStorage.delete();
        await onAuthFailure();
        return false;
      }

      return await _performTokenRefresh(credentials, options);
    });
  }

  Future<bool> _performTokenRefresh(
    Credentials credentials,
    RequestOptions options,
  ) async {
    try {
      refreshConfig.onRefreshStart?.call();
      logger.info('Starting token refresh');

      final dioClient = await _getRefreshDio();

      if (refreshConfig.refreshHeaders != null) {
        dioClient.options.headers.addAll(refreshConfig.refreshHeaders!);
      }

      final newCreds = await Future.any([
        tokenRefresher(credentials.refreshToken, dioClient),
        Future.delayed(
          refreshConfig.refreshTimeout,
          () => throw TimeoutException('Token refresh timeout'),
        ),
      ]);

      if (newCreds != null) {
        logger.info('Token refresh successful');
        await tokenStorage.write(newCreds);
        options.headers[refreshConfig.authorizationHeaderKey] =
            newCreds.authorizationHeaderValue;
        refreshConfig.onRefreshSuccess?.call(newCreds);
        return true;
      } else {
        logger.error('Token refresh returned null');
        await tokenStorage.delete();
        refreshConfig.onRefreshFailure?.call('Refresh returned null');
        await onAuthFailure();
        return false;
      }
    } catch (e, st) {
      logger.error('Token refresh failed', e, st);
      await tokenStorage.delete();
      refreshConfig.onRefreshFailure?.call(e);
      await onAuthFailure();
      return false;
    }
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final options = err.requestOptions;

    logger.debug('Error intercepted: ${err.type}, status: $status');

    if (status == HttpStatus.unauthorized) {
      logger.info('Unauthorized error, attempting token refresh');

      try {
        final success = await _handleUnauthorizedError(options);

        if (success) {
          logger.info('Token refreshed, retrying request');
          await _retryRequestWithPolicy(options, handler, err);
          return;
        }
      } catch (e, st) {
        logger.error('Failed to handle unauthorized error', e, st);
      }
    }

    if (retryConfig.shouldRetry(err, 0)) {
      logger.info('Error is retryable, attempting retry');
      await _retryRequestWithPolicy(options, handler, err);
      return;
    }

    logger.debug('Passing error to handler');
    handler.next(err);
  }

  Future<bool> _handleUnauthorizedError(RequestOptions options) async {
    return await _refreshLock.synchronized(() async {
      final credentials = await tokenStorage.read();
      if (credentials == null) {
        logger.info('No credentials found during error handling');
        return false;
      }

      if (credentials.isRefreshTokenExpired) {
        logger.error('Refresh token expired during error handling');
        await tokenStorage.delete();
        await onAuthFailure();
        return false;
      }

      return await _performTokenRefresh(credentials, options);
    });
  }

  Future<void> _retryRequestWithPolicy(
    RequestOptions options,
    ErrorInterceptorHandler handler,
    DioException originalError,
  ) async {
    final retryPolicy = RetryPolicy(retryConfig);
    int attemptCount = 0;

    try {
      final response = await retryPolicy.execute<Response>(
        () async {
          attemptCount++;
          logger.debug('Retry attempt $attemptCount for ${options.uri}');

          final credentials = await tokenStorage.read();
          if (credentials != null) {
            options.headers[refreshConfig.authorizationHeaderKey] =
                credentials.authorizationHeaderValue;
          }

          final dio = Dio();
          return await dio.fetch(options);
        },
        shouldRetry: (error) {
          if (error is DioException) {
            return retryConfig.shouldRetry(error, attemptCount);
          }
          return false;
        },
      );

      logger.info('Request retry successful');
      handler.resolve(response);
    } catch (e) {
      logger.error('All retry attempts failed', e);
      handler.next(originalError);
    }
  }

  /// Manually trigger a token refresh
  Future<bool> refreshToken() async {
    logger.info('Manual token refresh triggered');

    return await _refreshLock.synchronized(() async {
      final credentials = await tokenStorage.read();
      if (credentials == null) {
        logger.error('No credentials found for manual refresh');
        return false;
      }

      if (credentials.isRefreshTokenExpired) {
        logger.error('Refresh token expired');
        await tokenStorage.delete();
        await onAuthFailure();
        return false;
      }

      final options = RequestOptions(path: '');
      return await _performTokenRefresh(credentials, options);
    });
  }

  /// Clear all stored tokens
  Future<void> clearTokens() async {
    logger.info('Clearing all tokens');
    await tokenStorage.delete();
  }
}
