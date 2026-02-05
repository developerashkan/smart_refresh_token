import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_refresh_token/smart_refresh_token.dart';

void main() {
  group('Credentials', () {
    test('serializes and deserializes using toJson/fromJson', () {
      final creds = Credentials(
        accessToken: 'access123',
        refreshToken: 'refresh123',
        accessTokenExpireAt: DateTime.utc(2030, 1, 1),
        refreshTokenExpireAt: DateTime.utc(2030, 2, 1),
      );

      final encoded = json.encode(creds.toJson());
      final decoded = Credentials.fromJson(json.decode(encoded) as Map<String, dynamic>);

      expect(decoded.accessToken, creds.accessToken);
      expect(decoded.refreshToken, creds.refreshToken);
      expect(decoded.accessTokenExpireAt, creds.accessTokenExpireAt);
      expect(decoded.refreshTokenExpireAt, creds.refreshTokenExpireAt);
    });
  });

  group('InMemoryTokenStorage', () {
    test('write read delete lifecycle', () async {
      final storage = InMemoryTokenStorage();
      final creds = Credentials(
        accessToken: 'access123',
        refreshToken: 'refresh123',
        accessTokenExpireAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        refreshTokenExpireAt: DateTime.now().toUtc().add(const Duration(days: 1)),
      );

      await storage.write(creds);
      expect((await storage.read())?.accessToken, 'access123');

      await storage.delete();
      expect(await storage.read(), isNull);
    });
  });

  group('RefreshTokenInterceptor', () {
    test('refreshes expired access token before request', () async {
      final storage = InMemoryTokenStorage();
      await storage.write(
        Credentials(
          accessToken: 'expired',
          refreshToken: 'refresh-me',
          accessTokenExpireAt:
              DateTime.now().toUtc().subtract(const Duration(seconds: 5)),
          refreshTokenExpireAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        ),
      );

      final dio = Dio()
        ..httpClientAdapter = _MockAdapter((options) async {
          expect(options.headers['authorization'], 'Bearer fresh-access');
          return ResponseBody.fromString(
            '{"ok":true}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        })
        ..interceptors.add(
          RefreshTokenInterceptor(
            tokenStorage: storage,
            tokenRefresher: (_, __) async => Credentials(
              accessToken: 'fresh-access',
              refreshToken: 'fresh-refresh',
              accessTokenExpireAt:
                  DateTime.now().toUtc().add(const Duration(hours: 1)),
              refreshTokenExpireAt:
                  DateTime.now().toUtc().add(const Duration(days: 1)),
            ),
            onAuthFailure: () {},
          ),
        );

      final response = await dio.get('https://example.dev/private');
      expect(response.statusCode, 200);
      expect((await storage.read())?.accessToken, 'fresh-access');
    });

    test('supports skipping auth for public endpoints', () async {
      final storage = InMemoryTokenStorage();

      final dio = Dio()
        ..httpClientAdapter = _MockAdapter((options) async {
          expect(options.headers.containsKey('authorization'), isFalse);
          return ResponseBody.fromString('ok', 200);
        })
        ..interceptors.add(
          RefreshTokenInterceptor(
            tokenStorage: storage,
            tokenRefresher: (_, __) async => null,
            onAuthFailure: () {},
          ),
        );

      final response = await dio.get(
        'https://example.dev/public',
        options: Options(extra: {RefreshTokenInterceptor.skipAuthKey: true}),
      );

      expect(response.statusCode, 200);
    });
  });
}

typedef _AdapterHandler = Future<ResponseBody> Function(RequestOptions options);

class _MockAdapter implements HttpClientAdapter {
  _MockAdapter(this.handler);

  final _AdapterHandler handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return handler(options);
  }
}
