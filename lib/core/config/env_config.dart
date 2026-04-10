/// Environment configuration for the Sage app.
///
/// Manages base URLs, feature flags, and environment-specific settings.
/// Configured via `--dart-define` at build time:
///
/// ```bash
/// # Development — uses localhost (requires ADB reverse or emulator)
/// flutter run
///
/// # Production APK build
/// flutter build apk --release \
///   --dart-define=ENV=production \
///   --dart-define=API_BASE_URL=https://<your-railway-url> \
///   --dart-define=SOLANA_RPC_URL=https://<your-helius-rpc>
///
/// # Custom backend URL (e.g., local dev on LAN)
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.100:3001
/// ```
///
/// **IMPORTANT**: Before building a release APK, update [_kProductionApiUrl]
/// with your deployed Railway backend URL.
library;

import 'package:flutter/foundation.dart';

enum Environment { development, staging, production }

/// Default production backend URL. Update this when Railway deployment is live.
/// Override per-build via `--dart-define=API_BASE_URL=<url>`.
const String _kProductionApiUrl = 'http://192.168.1.113:3001';

/// Default production Solana RPC. Override via `--dart-define=SOLANA_RPC_URL=<url>`.
const String _kProductionRpcUrl = '';

class EnvConfig {
  /// Current environment, set via `--dart-define=ENV=<value>`
  static const String _envName = String.fromEnvironment(
    'ENV',
    defaultValue: 'development',
  );

  /// Override API base URL via `--dart-define=API_BASE_URL=<url>`
  static const String _apiBaseUrlOverride = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// Override ML service URL via `--dart-define=ML_BASE_URL=<url>`
  static const String _mlBaseUrlOverride = String.fromEnvironment(
    'ML_BASE_URL',
  );

  static Environment get environment {
    switch (_envName) {
      case 'production':
        return Environment.production;
      case 'staging':
        return Environment.staging;
      default:
        return Environment.development;
    }
  }

  static bool get isProduction => environment == Environment.production;
  static bool get isDevelopment => environment == Environment.development;
  static bool get isStaging => environment == Environment.staging;

  /// Backend API base URL.
  ///
  /// Priority: `--dart-define=API_BASE_URL` > [_kProductionApiUrl] > localhost.
  static String get apiBaseUrl {
    if (_apiBaseUrlOverride.isNotEmpty) return _apiBaseUrlOverride;

    // Always use the production URL if it's configured, regardless of environment.
    // This ensures release APKs never fall back to localhost.
    if (_kProductionApiUrl.isNotEmpty) return _kProductionApiUrl;

    switch (environment) {
      case Environment.production:
      case Environment.staging:
        debugPrint(
          '⚠️ API_BASE_URL not configured for ${environment.name}. '
          'Set _kProductionApiUrl in env_config.dart or pass '
          '--dart-define=API_BASE_URL=<url>',
        );
        return 'http://192.168.1.113:3001';
      case Environment.development:
        debugPrint(
          '⚠️ Dev mode: using http://localhost:3001. '
          'For physical device testing, pass '
          '--dart-define=API_BASE_URL=http://<your-lan-ip>:3001',
        );
        return 'http://192.168.1.113:3001';
    }
  }

  /// ML prediction service base URL.
  ///
  /// In all hosted environments ML is proxied through the backend's /ml route.
  static String get mlBaseUrl {
    if (_mlBaseUrlOverride.isNotEmpty) return _mlBaseUrlOverride;
    return '$apiBaseUrl/ml';
  }

  /// Solana network name.
  static String get solanaNetwork {
    switch (environment) {
      case Environment.production:
        return 'mainnet-beta';
      case Environment.staging:
      case Environment.development:
        return 'devnet';
    }
  }

  /// Solana RPC endpoint override via `--dart-define=SOLANA_RPC_URL=<url>`.
  static const String _solanaRpcUrlOverride = String.fromEnvironment(
    'SOLANA_RPC_URL',
  );

  /// Solana RPC endpoint.
  ///
  /// Priority: `--dart-define=SOLANA_RPC_URL` > [_kProductionRpcUrl] > public devnet.
  static String get solanaRpcUrl {
    if (_solanaRpcUrlOverride.isNotEmpty) return _solanaRpcUrlOverride;

    switch (environment) {
      case Environment.production:
        if (_kProductionRpcUrl.isNotEmpty) return _kProductionRpcUrl;
        debugPrint(
          '⚠️ SOLANA_RPC_URL not configured for production. '
          'Using public mainnet RPC — expect rate limits.',
        );
        return 'https://api.mainnet-beta.solana.com';
      case Environment.staging:
      case Environment.development:
        return 'https://api.devnet.solana.com';
    }
  }

  /// Whether to enable debug logging.
  static bool get enableDebugLogging => !isProduction || kDebugMode;

  /// Whether to show the debug banner on home screen.
  static bool get showDebugBanner => isDevelopment;

  /// Connection timeout for API calls.
  static Duration get apiConnectTimeout =>
      isProduction ? const Duration(seconds: 15) : const Duration(seconds: 10);

  /// Receive timeout for API calls.
  static Duration get apiReceiveTimeout =>
      isProduction ? const Duration(seconds: 30) : const Duration(seconds: 60);

  /// Label for UI display (settings screen).
  static String get environmentLabel {
    switch (environment) {
      case Environment.production:
        return 'Production';
      case Environment.staging:
        return 'Staging';
      case Environment.development:
        return 'Development';
    }
  }

  /// Whether the backend API URL is configured.
  ///
  /// Returns `false` in production/staging when neither `--dart-define` nor
  /// [_kProductionApiUrl] is set. The app should show a config error screen.
  static bool get isApiConfigured => apiBaseUrl.isNotEmpty;
}
