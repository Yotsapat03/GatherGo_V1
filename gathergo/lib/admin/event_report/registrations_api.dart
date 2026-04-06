import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import 'report_models.dart';

class RegistrationsApi {
  static String get _baseUrl => ConfigService.getApiBaseUrl();

  static bool _isWrongTarget404(Uri primary, http.Response res) {
    if (!kIsWeb || !kDebugMode) return false;
    if (res.statusCode != 404) return false;

    final body = res.body.toLowerCase();
    const path = '/api/admin/event-report/registrations';
    final cannotGetPath = body.contains('cannot get') && body.contains(path);
    if (!cannotGetPath) return false;

    final webOrigin = ConfigService.getWebOrigin();
    final isWebOrigin =
        webOrigin != null && ConfigService.isSameHostPort(primary, webOrigin);
    final isLikelyFlutterPort = ConfigService.isLikelyFlutterDevPort(primary);
    return isWebOrigin || isLikelyFlutterPort;
  }

  static Future<RegistrationReportResponse> fetchRegistrationsReport() async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse('$_baseUrl/api/admin/event-report/registrations')
        .replace(queryParameters: {
      'admin_id': adminId.toString(),
    });

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-admin-id': adminId.toString(),
    };

    ConfigService.log('Registrations report URL: $uri');
    var response = await http.get(
      uri,
      headers: headers,
    ).timeout(const Duration(seconds: 20));

    if (_isWrongTarget404(uri, response)) {
      final fallback = ConfigService.getDevFallbackUri(
        '/api/admin/event-report/registrations',
      )?.replace(queryParameters: {
        'admin_id': adminId.toString(),
      });
      if (fallback != null && fallback != uri) {
        ConfigService.log(
          'Registrations report wrong-target detected (HTTP ${response.statusCode}). Retrying URL: $fallback',
        );
        response = await http.get(
          fallback,
          headers: headers,
        ).timeout(const Duration(seconds: 20));
      }
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Fetch registrations report failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid registrations report response');
    }

    return RegistrationReportResponse.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }
}
