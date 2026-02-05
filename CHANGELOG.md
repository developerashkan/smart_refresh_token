## [0.1.0] - 2026-02-05
### Added
- Added `InMemoryTokenStorage` for quick starts and tests.
- Added `RefreshTokenInterceptor.skipAuthKey` support to bypass auth injection/refresh for public endpoints.
- Added `retryDio` option so retries can use a dedicated Dio instance.

### Improved
- Improved refresh lock behavior: `parallelRefresh` now controls whether requests share the refresh lock.
- Improved retry delay calculation to true exponential backoff with optional jitter.
- Safer `Credentials.toString()` for short token strings.

### Fixed
- Fixed README/API mismatch for refresh configuration and skip-auth usage.
- Fixed metadata parsing in `Credentials.fromJson` for loosely typed maps.

## [0.0.3] - 2025-11-27
### Added
- Dynamic retry logic (configurable backoff, max attempts).
- Comprehensive examples demonstrating refresh + retry flows.
- New `RetryConfig` for runtime retry customization.

### Improved
- More stable token refresh interceptor.
- Clearer documentation and example structure.

### Fixed
- Missing platform folders in example project.

## [0.0.2] - 2025-10-08
### Added
- Initial release of `smart_refresh_token` package.
- Automatic Dio token refresh handling.
- Support for secure token storage using `flutter_secure_storage`.

## [0.0.1] - 2025-10-08
### Added
- Initial release of `smart_refresh_token` package.
