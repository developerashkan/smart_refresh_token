import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_refresh_token/smart_refresh_token.dart';

class TestAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) onFetch;

  TestAdapter(this.onFetch);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return onFetch(options);
  }
}

void main() {
  group('InMemoryTokenStorage', () {
    test('write/read/delete lifecycle', () async {
      final storage = InMemoryTokenStorage();
      final creds = Credentials(
        accessToken: 'access123',
        refreshToken: 'refresh123',
        accessTokenExpireAt: DateTime.now().toUtc().add(
              const Duration(hours: 1),
            ),
        refreshTokenExpireAt: DateTime.now().toUtc().add(
              const Duration(days: 1),
            ),
      );

      await storage.write(creds);
      final readCreds = await storage.read();

      expect(readCreds, equals(creds));

      await storage.delete();
      expect(await storage.read(), isNull);
    });
  });

  group('RefreshTokenInterceptor', () {
    test('attaches Authorization header for valid token', () async {
      final storage = InMemoryTokenStorage(
        initialCredentials: Credentials(
          accessToken: 'valid-token',
          refreshToken: 'refresh-token',
          accessTokenExpireAt: DateTime.now().toUtc().add(
                const Duration(hours: 1),
              ),
        ),
      );

      late String? authorizationHeader;
      final dio = Dio()
        ..httpClientAdapter = TestAdapter((options) async {
          authorizationHeader = options.headers['authorization'] as String?;
          return ResponseBody.fromString(
            jsonEncode({'ok': true}),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        })
        ..interceptors.add(
          RefreshTokenInterceptor(
            tokenStorage: storage,
            tokenRefresher: (_, __) async => null,
            onAuthFailure: () async {},
          ),
        );

      await dio.get('https://example.com/me');

      expect(authorizationHeader, equals('Bearer valid-token'));
    });

    test('refreshes token when expired', () async {
      final storage = InMemoryTokenStorage(
        initialCredentials: Credentials(
          accessToken: 'expired-token',
          refreshToken: 'refresh-token',
          accessTokenExpireAt: DateTime.now().toUtc().subtract(
                const Duration(minutes: 1),
              ),
          refreshTokenExpireAt: DateTime.now().toUtc().add(
                const Duration(days: 1),
              ),
        ),
      );

      var refreshCallCount = 0;
      late String? authorizationHeader;

      final dio = Dio()
        ..httpClientAdapter = TestAdapter((options) async {
          authorizationHeader = options.headers['authorization'] as String?;
          return ResponseBody.fromString('', 200);
        })
        ..interceptors.add(
          RefreshTokenInterceptor(
            tokenStorage: storage,
            tokenRefresher: (_, __) async {
              refreshCallCount++;
              return Credentials(
                accessToken: 'new-token',
                refreshToken: 'new-refresh',
                accessTokenExpireAt: DateTime.now().toUtc().add(
                      const Duration(hours: 1),
                    ),
                refreshTokenExpireAt: DateTime.now().toUtc().add(
                      const Duration(days: 30),
                    ),
              );
            },
            onAuthFailure: () async {},
          ),
        );

      await dio.get('https://example.com/me');

      expect(refreshCallCount, 1);
      expect(authorizationHeader, 'Bearer new-token');
      expect((await storage.read())?.accessToken, 'new-token');
    });

    test('skipAuthKey bypasses authentication handling', () async {
      var authFailureCalls = 0;

      final dio = Dio()
        ..httpClientAdapter = TestAdapter(
          (_) async => ResponseBody.fromString('', 200),
        )
        ..interceptors.add(
          RefreshTokenInterceptor(
            tokenStorage: InMemoryTokenStorage(),
            tokenRefresher: (_, __) async => null,
            onAuthFailure: () async {
              authFailureCalls++;
            },
          ),
        );

      await dio.get(
        'https://example.com/public',
        options: Options(extra: {RefreshTokenInterceptor.skipAuthKey: true}),
      );

      expect(authFailureCalls, 0);
    });
  });

  group('RetryConfig', () {
    test('calculateDelay grows with attempts when jitter disabled', () {
      const config = RetryConfig(
        baseDelay: Duration(seconds: 1),
        backoffMultiplier: 2,
        jitter: 0,
      );

      expect(config.calculateDelay(1), const Duration(seconds: 1));
      expect(config.calculateDelay(2), const Duration(seconds: 2));
      expect(config.calculateDelay(3), const Duration(seconds: 4));
    });
  });
}
