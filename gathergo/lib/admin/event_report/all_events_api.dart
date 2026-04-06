import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import 'report_models.dart';

class AllEventsApi {
  static String get _baseUrl => ConfigService.getApiBaseUrl();

  static bool _isWrongTarget404(Uri primary, http.Response res, String path) {
    if (!kIsWeb || !kDebugMode) return false;
    if (res.statusCode != 404) return false;

    final body = res.body.toLowerCase();
    final cannotGetPath = body.contains('cannot get') && body.contains(path);
    if (!cannotGetPath) return false;

    final webOrigin = ConfigService.getWebOrigin();
    final isWebOrigin =
        webOrigin != null && ConfigService.isSameHostPort(primary, webOrigin);
    final isLikelyFlutterPort = ConfigService.isLikelyFlutterDevPort(primary);
    return isWebOrigin || isLikelyFlutterPort;
  }

  static Future<http.Response> _getWithAdmin(
    String path, {
    Map<String, String>? queryParameters,
  }) async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse('$_baseUrl$path').replace(
      queryParameters: {
        'admin_id': adminId.toString(),
        ...?queryParameters,
      },
    );

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-admin-id': adminId.toString(),
    };

    var response = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));

    if (_isWrongTarget404(uri, response, path)) {
      final fallback = ConfigService.getDevFallbackUri(path)?.replace(
        queryParameters: {
          'admin_id': adminId.toString(),
          ...?queryParameters,
        },
      );
      if (fallback != null && fallback != uri) {
        response = await http
            .get(fallback, headers: headers)
            .timeout(const Duration(seconds: 20));
      }
    }

    return response;
  }

  static Future<AvailablePeriodsResponse> fetchAvailablePeriods() async {
    final response =
        await _getWithAdmin('/api/admin/reports/all-events/available-periods');
    if (response.statusCode != 200) {
      throw Exception(
        'Fetch all-event periods failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid all-event periods response');
    }

    return AvailablePeriodsResponse.fromJson(
        Map<String, dynamic>.from(decoded));
  }

  static Future<AllEventsPieReport> fetchPieReport({
    required int year,
    required int month,
  }) async {
    final response = await _getWithAdmin(
      '/api/admin/reports/all-events/pie',
      queryParameters: {
        'year': year.toString(),
        'month': month.toString(),
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Fetch all-event pie report failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid all-event pie report response');
    }

    return AllEventsPieReport.fromJson(Map<String, dynamic>.from(decoded));
  }
}
