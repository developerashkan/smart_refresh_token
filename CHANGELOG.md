# Changelog

All notable changes to this package will be documented in this file.

## [0.1.0] - 2026-02-05
### Added
- Added `InMemoryTokenStorage` for quick onboarding, demos, and test usage.
- Added `Credentials.toJson()` and `Credentials.fromJson(...)` helpers.
- Added request opt-out support using `RefreshTokenInterceptor.skipAuthKey`.
- Added configurable proactive refresh behavior using `refreshBeforeExpiry`.

### Changed
- Refactored refresh logic to centralize and simplify credential refresh handling.
- Improved retry behavior and guardrails for unauthorized responses.
- Updated examples and docs to be easier to integrate in real projects.
- Expanded test coverage with interceptor and storage tests.

## [0.0.2] - 2025-10-08
### Added
- Initial release of `smart_refresh_token` package.
- Automatic Dio token refresh handling.
- Support for secure token storage using `flutter_secure_storage`.

## [0.0.1] - 2025-10-08
### Added
- Initial release of `smart_refresh_token` package.
