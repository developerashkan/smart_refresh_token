import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:synchronized/synchronized.dart';

class Credentials {
  final String accessToken;
  final String refreshToken;
  final DateTime accessTokenExpireAt;
  final DateTime? refreshTokenExpireAt;

  Credentials({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpireAt,
    this.refreshTokenExpireAt,
  });

  factory Credentials.fromJson(Map<String, dynamic> json) {
    return Credentials(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      accessTokenExpireAt:
          DateTime.parse(json['accessTokenExpireAt'] as String).toUtc(),
      refreshTokenExpireAt: json['refreshTokenExpireAt'] == null
          ? null
          : DateTime.parse(json['refreshTokenExpireAt'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'accessTokenExpireAt': accessTokenExpireAt.toUtc().toIso8601String(),
      'refreshTokenExpireAt': refreshTokenExpireAt?.toUtc().toIso8601String(),
    };
  }

  String get authorizationHeaderValue => 'Bearer $accessToken';

  bool isAccessTokenExpired({
    Duration refreshBefore = Duration.zero,
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    return accessTokenExpireAt.toUtc().isBefore(current.add(refreshBefore));
  }

  bool isRefreshTokenExpired({DateTime? now}) {
    if (refreshTokenExpireAt == null) return false;
    final current = (now ?? DateTime.now()).toUtc();
    return refreshTokenExpireAt!.toUtc().isBefore(current);
  }

  Credentials copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? accessTokenExpireAt,
    DateTime? refreshTokenExpireAt,
  }) {
    return Credentials(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accessTokenExpireAt: accessTokenExpireAt ?? this.accessTokenExpireAt,
      refreshTokenExpireAt: refreshTokenExpireAt ?? this.refreshTokenExpireAt,
    );
  }
}

abstract class TokenStorage {
  Future<Credentials?> read();
  Future<void> write(Credentials credentials);
  Future<void> delete();
}

class InMemoryTokenStorage implements TokenStorage {
  Credentials? _credentials;

  @override
  Future<void> delete() async {
    _credentials = null;
  }

  @override
  Future<Credentials?> read() async => _credentials;

  @override
  Future<void> write(Credentials credentials) async {
    _credentials = credentials;
  }
}

typedef TokenRefresher = Future<Credentials?> Function(
  String refreshToken,
  Dio client,
);

typedef OnAuthFailure = FutureOr<void> Function();

class RefreshTokenInterceptor extends Interceptor {
  static const String skipAuthKey = 'smart_refresh_token.skip_auth';
  static const String refreshedRetryKey = 'smart_refresh_token.retried_after_refresh';

  final TokenStorage tokenStorage;
  final TokenRefresher tokenRefresher;
  final OnAuthFailure onAuthFailure;
  final Dio? refreshDio;
  final Dio? retryDio;
  final String authorizationHeaderKey;
  final Duration refreshBeforeExpiry;
  final bool retryOnUnauthorized;

  final Lock _lock = Lock();

  RefreshTokenInterceptor({
    required this.tokenStorage,
    required this.tokenRefresher,
    required this.onAuthFailure,
    this.refreshDio,
    this.retryDio,
    this.authorizationHeaderKey = HttpHeaders.authorizationHeader,
    this.refreshBeforeExpiry = const Duration(seconds: 30),
    this.retryOnUnauthorized = true,
  });

  static void markAsUnauthenticated(RequestOptions options) {
    options.extra[skipAuthKey] = true;
  }

  Future<Dio> _getRefreshDio() async {
    return refreshDio ?? Dio();
  }

  Future<Dio> _getRetryDio() async {
    return retryDio ?? refreshDio ?? Dio();
  }

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.extra[skipAuthKey] == true) {
      handler.next(options);
      return;
    }

    _attachAuthorizationAndMaybeRefresh(options).then((shouldProceed) {
      if (shouldProceed) {
        handler.next(options);
      } else {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            error: 'Authentication failed - unable to refresh token',
          ),
        );
      }
    }).catchError((e, st) {
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          error: 'Unexpected error in refresh interceptor: $e\n$st',
        ),
      );
    });
  }

  Future<bool> _attachAuthorizationAndMaybeRefresh(RequestOptions options) async {
    return _lock.synchronized(() async {
      final credentials = await tokenStorage.read();

      if (credentials == null) {
        await onAuthFailure();
        return false;
      }

      if (!credentials.isAccessTokenExpired(refreshBefore: refreshBeforeExpiry)) {
        options.headers[authorizationHeaderKey] = credentials.authorizationHeaderValue;
        return true;
      }

      final refreshed = await _refreshCredentials(credentials);
      if (refreshed == null) {
        return false;
      }

      options.headers[authorizationHeaderKey] = refreshed.authorizationHeaderValue;
      return true;
    });
  }

  Future<Credentials?> _refreshCredentials(Credentials credentials) async {
    if (credentials.isRefreshTokenExpired()) {
      await tokenStorage.delete();
      await onAuthFailure();
      return null;
    }

    final dioClient = await _getRefreshDio();
    final newCreds = await tokenRefresher(credentials.refreshToken, dioClient);

    if (newCreds != null) {
      await tokenStorage.write(newCreds);
      return newCreds;
    }

    await tokenStorage.delete();
    await onAuthFailure();
    return null;
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final status = err.response?.statusCode;
    final options = err.requestOptions;

    if (!retryOnUnauthorized || status != HttpStatus.unauthorized) {
      handler.next(err);
      return;
    }

    if (options.extra[skipAuthKey] == true || options.extra[refreshedRetryKey] == true) {
      handler.next(err);
      return;
    }

    try {
      final success = await _lock.synchronized(() async {
        final credentials = await tokenStorage.read();
        if (credentials == null) return false;

        if (!credentials.isAccessTokenExpired(refreshBefore: refreshBeforeExpiry)) {
          return true;
        }

        return (await _refreshCredentials(credentials)) != null;
      });

      if (!success) {
        handler.next(err);
        return;
      }

      final latest = await tokenStorage.read();
      if (latest == null) {
        handler.next(err);
        return;
      }

      options.headers[authorizationHeaderKey] = latest.authorizationHeaderValue;
      options.extra[refreshedRetryKey] = true;

      final retryClient = await _getRetryDio();
      final retryResponse = await retryClient.fetch(options);
      handler.resolve(retryResponse);
    } catch (_) {
      handler.next(err);
    }
  }
}
