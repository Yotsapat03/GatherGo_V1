/// Configuration Service
/// Centralized platform detection and configuration management
/// Supports: Android, iOS, Web, Windows, macOS, Linux
library;

import 'package:flutter/foundation.dart';

class ConfigService {
  ConfigService._();

  static String _platformDefaultBaseUrl() {
    if (kIsWeb) return 'http://localhost:3000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  static bool _isValidAbsoluteHttpUrl(Uri? uri) {
    if (uri == null) return false;
    final okScheme = uri.scheme == 'http' || uri.scheme == 'https';
    return okScheme && uri.hasAuthority && uri.host.isNotEmpty;
  }

  static int _effectivePort(Uri uri) {
    if (uri.hasPort) return uri.port;
    if (uri.scheme == 'https') return 443;
    return 80;
  }

  static bool isSameHostPort(Uri a, Uri b) {
    return a.host.toLowerCase() == b.host.toLowerCase() &&
        _effectivePort(a) == _effectivePort(b);
  }

  static bool isLikelyFlutterDevPort(Uri uri) {
    if (!kIsWeb) return false;
    final p = _effectivePort(uri);
    final localHost = uri.host.toLowerCase() == 'localhost' || uri.host == '127.0.0.1';
    // Flutter web dev ports can vary (including low ports like :1482).
    // Treat any local non-standard port as a potential web dev host.
    if (!localHost) return false;
    return p != 80 && p != 443 && p != 3000;
  }

  static Uri? getWebOrigin() {
    if (!kIsWeb) return null;
    return Uri.base;
  }

  static Uri? _parseAbsoluteBase(String raw) {
    final parsed = Uri.tryParse(raw.trim());
    if (!_isValidAbsoluteHttpUrl(parsed)) return null;
    return parsed!;
  }

  static String? _devFallbackBaseUrl() {
    const raw = String.fromEnvironment('BACKEND_FALLBACK_URL', defaultValue: '');
    final parsed = _parseAbsoluteBase(raw);
    if (parsed != null) return parsed.toString();

    if (kIsWeb && kDebugMode) {
      return 'http://localhost:3000';
    }
    return null;
  }

  static Uri? getDevFallbackUri(String path) {
    final base = _devFallbackBaseUrl();
    if (base == null) return null;
    final b = Uri.parse(base);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return b.resolve(normalizedPath);
  }

  /// Get API base URL.
  /// Priority:
  /// 1) --dart-define API_URL=...
  /// 2) Platform default
  /// - Android emulator: http://10.0.2.2:3000
  /// - Web/iOS/macOS/Windows/Linux: http://localhost:3000
  static String getApiBaseUrl() {
    const apiUrlFromEnvRaw = String.fromEnvironment('API_URL', defaultValue: '');
    final apiUrlFromEnv = apiUrlFromEnvRaw.trim();
    final fallback = _platformDefaultBaseUrl();

    final parsedApi = _parseAbsoluteBase(apiUrlFromEnv);
    if (parsedApi != null) {
      // Never override a valid absolute API_URL.
      return parsedApi.toString();
    }

    if (apiUrlFromEnv.isNotEmpty) {
      // For web debug, invalid/relative API_URL can still use dev fallback.
      if (kIsWeb && kDebugMode) {
        final devFallback = _devFallbackBaseUrl();
        if (devFallback != null) {
          debugPrint('[GatherGo] Invalid/relative API_URL. Using dev fallback: $devFallback');
          return devFallback;
        }
      }
      debugPrint('[GatherGo] Ignoring invalid API_URL, fallback to $fallback: $apiUrlFromEnv');
    }

    return fallback;
  }

  static String getBaseUrl() => getApiBaseUrl();

  /// Resolve a URL that might come from backend
  /// Handles different formats:
  /// - '/uploads/qr/xxx.png' -> combine with baseUrl
  /// - 'http://...' -> use as-is
  /// - 'uploads/qr/xxx.png' -> add leading slash and combine
  static String resolveUrl(String? input) {
    final raw = (input ?? '').trim();
    if (raw.isEmpty) return '';

    if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return raw;
    }

    if (raw.startsWith('/')) {
      return '${getBaseUrl()}$raw';
    }

    if (raw.startsWith('uploads/') || raw.startsWith('qr/')) {
      return '${getBaseUrl()}/$raw';
    }

    return '${getBaseUrl()}/$raw';
  }

  /// Check if running on web
  static bool get isWeb => kIsWeb;

  /// Check if running on Android
  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// Check if running on iOS
  static bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  /// Check if running on native platform (not web)
  static bool get isNative => !kIsWeb;

  /// API version (use for backward compatibility)
  static const String apiVersion = 'v1';

  /// Default request timeout
  static const Duration requestTimeout = Duration(seconds: 30);

  /// Image upload constants
  static const int maxImageSizeBytes = 5 * 1024 * 1024; // 5MB
  static const int maxImagesPerEvent = 10;
  static const int imageQuality = 85; // JPEG quality (0-100)

  /// Payment Constants
  static const String defaultCurrency = 'THB';
  static const List<String> supportedCurrencies = ['THB'];

  /// Logging
  static const bool enableDebugLogging = kDebugMode;

  static void log(String message) {
    if (enableDebugLogging) {
      debugPrint('[GatherGo] $message');
    }
  }
}
