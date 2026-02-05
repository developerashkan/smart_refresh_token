# smart_refresh_token

A simple, production-focused Flutter package for **automatic Dio access-token refresh**.

`smart_refresh_token` solves common auth pain points for mobile teams:
- stale/expired token race conditions,
- duplicated refresh calls from concurrent requests,
- retrying 401 requests after refresh,
- and clean opt-out for public endpoints.

## Highlights

- ✅ Automatic auth header injection.
- ✅ Automatic refresh when token is expired (or near expiry).
- ✅ Single-flight refresh lock to prevent multiple simultaneous refresh calls.
- ✅ Optional 401 retry flow.
- ✅ Easy skip-auth flag for public endpoints.
- ✅ Storage-agnostic design (`TokenStorage` abstraction).
- ✅ Built-in `InMemoryTokenStorage` for demos, tests, and quick starts.

---

## Install

```yaml
dependencies:
  smart_refresh_token: ^0.1.0
```

Then run:

```bash
flutter pub get
```

---

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
    refreshBeforeExpiry: const Duration(seconds: 45),
  ),
);
```

---

## Core API

### `Credentials`
- `toJson()` / `fromJson(...)` helpers.
- `authorizationHeaderValue` convenience getter.
- `isAccessTokenExpired(refreshBefore: ...)` for proactive refresh.

### `TokenStorage`
Implement these 3 methods:
- `read()`
- `write(credentials)`
- `delete()`

You can use:
- `InMemoryTokenStorage` (included), or
- your own secure storage implementation (see `lib/example/main.dart`).

### `RefreshTokenInterceptor`
Important options:
- `refreshBeforeExpiry` (default: 30s)
- `retryOnUnauthorized` (default: true)
- `refreshDio` and `retryDio` for advanced networking setups
- `authorizationHeaderKey` (default: `Authorization`)

---

## Public endpoints (skip auth)

For endpoints that must not include auth headers:

```dart
await dio.get(
  '/public/feed',
  options: Options(
    extra: {RefreshTokenInterceptor.skipAuthKey: true},
  ),
);
```

---

## Why this package is useful

It reduces boilerplate and prevents common real-world auth bugs:
- refresh storms from parallel requests,
- token expiry timing races,
- repetitive retry logic in each API method,
- and inconsistent auth failure handling across features.

---

## Example secure storage implementation

A complete `flutter_secure_storage` implementation is provided at:
- `lib/example/main.dart`

---

## License

MIT
