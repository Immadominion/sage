/// User model — maps to backend `users` table + auth response.
class User {
  final int id;
  final String walletAddress;
  final String? displayName;
  final bool setupCompleted;
  final String? execMode;
  final DateTime createdAt;

  const User({
    required this.id,
    required this.walletAddress,
    this.displayName,
    this.setupCompleted = false,
    this.execMode,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => User(
    id: json['id'] as int,
    walletAddress: json['walletAddress'] as String,
    displayName: json['displayName'] as String?,
    setupCompleted: json['setupCompleted'] as bool? ?? false,
    execMode: json['execMode'] as String?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'walletAddress': walletAddress,
    'displayName': displayName,
    'setupCompleted': setupCompleted,
    'execMode': execMode,
    'createdAt': createdAt.toIso8601String(),
  };
}

/// Auth tokens returned by /auth/verify and /auth/refresh.
class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final String expiresIn;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> json) => AuthTokens(
    accessToken: json['accessToken'] as String,
    refreshToken: json['refreshToken'] as String,
    expiresIn: json['expiresIn'] as String,
  );
}
