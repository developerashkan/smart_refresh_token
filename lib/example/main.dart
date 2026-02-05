import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:smart_refresh_token/smart_refresh_token.dart';

/// Production-ready storage backed by flutter_secure_storage.
class SecureTokenStorage implements TokenStorage {
  final FlutterSecureStorage secureStorage;

  SecureTokenStorage({required this.secureStorage});

  static const _kKey = 'app_credentials_v1';

  @override
  Future<void> delete() => secureStorage.delete(key: _kKey);

  @override
  Future<Credentials?> read() async {
    final value = await secureStorage.read(key: _kKey);
    if (value == null) return null;

    return Credentials.fromJson(json.decode(value) as Map<String, dynamic>);
  }

  @override
  Future<void> write(Credentials credentials) {
    return secureStorage.write(
      key: _kKey,
      value: json.encode(credentials.toJson()),
    );
  }
}

/// Example token refresher. Adapt to your API schema.
Future<Credentials?> myRefresher(String refreshToken, Dio client) async {
  try {
    final resp = await client.post(
      'https://api.yourdomain.com/v2/mobile/login/refresh/',
      data: {'refresh': refreshToken},
    );

    if (resp.statusCode != 200) return null;

    final data = resp.data as Map<String, dynamic>;
    final newAccess = data['access_token'] ?? data['token'] ?? data['access'];
    if (newAccess is! String) return null;

    final newRefresh = data['refresh'] as String? ?? refreshToken;
    final accessExpiresIn = data['access_expires_in'] as int? ?? 3600;
    final refreshExpiresIn = data['refresh_expires_in'] as int?;

    return Credentials(
      accessToken: newAccess,
      refreshToken: newRefresh,
      accessTokenExpireAt:
          DateTime.now().toUtc().add(Duration(seconds: accessExpiresIn)),
      refreshTokenExpireAt: refreshExpiresIn == null
          ? null
          : DateTime.now().toUtc().add(Duration(seconds: refreshExpiresIn)),
    );
  } catch (_) {
    return null;
  }
}

final tokenStorage = SecureTokenStorage(secureStorage: FlutterSecureStorage());

final interceptor = RefreshTokenInterceptor(
  tokenStorage: tokenStorage,
  tokenRefresher: myRefresher,
  onAuthFailure: () async {
    // app-specific: navigate to login, clear local state, etc.
  },
  // Refresh a little before expiry to avoid race conditions.
  refreshBeforeExpiry: const Duration(seconds: 45),
);

final dioAuth = Dio(BaseOptions(baseUrl: 'https://api.yourdomain.com'))
  ..interceptors.add(interceptor);

/// Example for unauthenticated requests:
Future<Response<dynamic>> fetchPublicFeed() {
  final options = Options(extra: {RefreshTokenInterceptor.skipAuthKey: true});
  return dioAuth.get('/public/feed', options: options);
}
