import 'package:equatable/equatable.dart';

/// Represents authentication credentials with access and refresh tokens
class Credentials extends Equatable {
  /// The access token used for API requests
  final String accessToken;

  /// The refresh token used to obtain new access tokens
  final String refreshToken;

  /// When the access token expires
  final DateTime accessTokenExpireAt;

  /// Optional: When the refresh token expires
  final DateTime? refreshTokenExpireAt;

  /// Optional: Additional metadata
  final Map<String, dynamic>? metadata;

  const Credentials({
    required this.accessToken,
    required this.refreshToken,
    required this.accessTokenExpireAt,
    this.refreshTokenExpireAt,
    this.metadata,
  });

  /// Returns the authorization header value
  String get authorizationHeaderValue => 'Bearer $accessToken';

  /// Checks if the access token is expired
  bool get isAccessTokenExpired =>
      accessTokenExpireAt.isBefore(DateTime.now().toUtc());

  /// Checks if the refresh token is expired
  bool get isRefreshTokenExpired =>
      refreshTokenExpireAt != null &&
      refreshTokenExpireAt!.isBefore(DateTime.now().toUtc());

  /// Checks if access token is about to expire (within buffer time)
  bool isAccessTokenExpiringSoon([
    Duration buffer = const Duration(minutes: 5),
  ]) {
    return accessTokenExpireAt
        .subtract(buffer)
        .isBefore(DateTime.now().toUtc());
  }

  /// Creates a copy with updated fields
  Credentials copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? accessTokenExpireAt,
    DateTime? refreshTokenExpireAt,
    Map<String, dynamic>? metadata,
  }) {
    return Credentials(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      accessTokenExpireAt: accessTokenExpireAt ?? this.accessTokenExpireAt,
      refreshTokenExpireAt: refreshTokenExpireAt ?? this.refreshTokenExpireAt,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Converts to JSON
  Map<String, dynamic> toJson() {
    return {
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'accessTokenExpireAt': accessTokenExpireAt.toIso8601String(),
      'refreshTokenExpireAt': refreshTokenExpireAt?.toIso8601String(),
      'metadata': metadata,
    };
  }

  /// Creates from JSON
  factory Credentials.fromJson(Map<String, dynamic> json) {
    return Credentials(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      accessTokenExpireAt: DateTime.parse(
        json['accessTokenExpireAt'] as String,
      ).toUtc(),
      refreshTokenExpireAt: json['refreshTokenExpireAt'] != null
          ? DateTime.parse(json['refreshTokenExpireAt'] as String).toUtc()
          : null,
      metadata: (json['metadata'] as Map?)?.cast<String, dynamic>(),
    );
  }

  @override
  List<Object?> get props => [
    accessToken,
    refreshToken,
    accessTokenExpireAt,
    refreshTokenExpireAt,
    metadata,
  ];

  @override
  String toString() {
    String mask(String value) {
      if (value.length <= 10) return value;
      return '${value.substring(0, 10)}...';
    }

    return 'Credentials(accessToken: ${mask(accessToken)}, '
        'refreshToken: ${mask(refreshToken)}, '
        'accessTokenExpireAt: $accessTokenExpireAt, '
        'refreshTokenExpireAt: $refreshTokenExpireAt)';
  }
}
