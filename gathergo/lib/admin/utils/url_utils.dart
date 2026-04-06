import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../../core/services/config_service.dart';

// Resolve relative URLs and only rewrite localhost when running on Android emulator.
String fixLocalhostForEmulator(String url) {
  final resolved = ConfigService.resolveUrl(url);

  // Web/desktop/iOS should keep localhost as-is.
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return resolved;
  }

  // Android emulator cannot access host localhost directly.
  return resolved
      .replaceFirst('http://127.0.0.1:3000', 'http://10.0.2.2:3000')
      .replaceFirst('http://localhost:3000', 'http://10.0.2.2:3000');
}
