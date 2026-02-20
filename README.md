# smart_refresh_token

A production-focused Flutter/Dart package for **automatic Dio access-token refresh**.

`smart_refresh_token` handles real auth edge-cases out of the box:
- concurrent request refresh storms,
- proactive token refresh before expiry,
- automatic retry with exponential backoff,
- simple opt-out for public endpoints,
- and pluggable token storage.

## Install

```yaml
dependencies:
  smart_refresh_token: ^0.1.1
```

```bash
flutter pub get
```

## Quick start

```dart
import 'package:dio/dio.dart';
import 'package:smart_refresh_token/smart_refresh_token.dart';

final storage = InMemoryTokenStorage();

Future<Credentials?> refreshToken(String refreshToken, Dio client) async {
  final resp = await client.post(
    'https://api.example.com/auth/refresh',
    data: {'refresh': refreshToken},
  );

  if (resp.statusCode != 200) return null;

  final data = resp.data as Map<String, dynamic>;
  return Credentials(
    accessToken: data['access_token'] as String,
    refreshToken: (data['refresh_token'] as String?) ?? refreshToken,
    accessTokenExpireAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    refreshTokenExpireAt: DateTime.now().toUtc().add(const Duration(days: 30)),
  );
}

final dio = Dio();
dio.interceptors.add(
  RefreshTokenInterceptor(
    tokenStorage: storage,
    tokenRefresher: refreshToken,
    onAuthFailure: () async {
      // e.g. navigate to login, clear app state
    },
    refreshConfig: const RefreshConfig(
      expirationBuffer: Duration(seconds: 45),
    ),
    retryConfig: RetryConfig.conservative(),
  ),
);
```

## Public endpoints (skip auth)

```dart
await dio.get(
  '/public/feed',
  options: Options(
    extra: {RefreshTokenInterceptor.skipAuthKey: true},
  ),
);
```

## Main APIs

### `Credentials`
- `toJson()` / `fromJson(...)`
- `authorizationHeaderValue`
- `isAccessTokenExpired`
- `isAccessTokenExpiringSoon(buffer)`

### `TokenStorage`
Implement:
- `read()`
- `write(credentials)`
- `delete()`

Built-in:
- `InMemoryTokenStorage` (great for tests and simple apps)

### `RefreshTokenInterceptor`
Constructor options:
- `tokenStorage`, `tokenRefresher`, `onAuthFailure` (required)
- `refreshConfig` for refresh behavior
- `retryConfig` for retry strategy
- `refreshDio` for dedicated refresh transport
- `retryDio` for dedicated retry transport
- `logger` for package logging

### `RefreshConfig`
- `expirationBuffer`
- `proactiveRefresh`
- `parallelRefresh`
- `refreshTimeout`
- `authorizationHeaderKey`
- refresh callbacks: `onRefreshStart`, `onRefreshSuccess`, `onRefreshFailure`

### `RetryConfig`
- `maxRetries`
- `baseDelay`, `maxDelay`
- `backoffMultiplier`, `jitter`
- `retryableStatusCodes`
- `retryableExceptionTypes`

## Why teams use it

- Prevents duplicate refresh calls during traffic spikes.
- Centralizes auth failure behavior.
- Reduces repetitive endpoint-level retry and auth code.
- Works with any storage backend through `TokenStorage`.

## Example app

See `example/lib/main.dart` for a complete Flutter demo.

## License

MIT
