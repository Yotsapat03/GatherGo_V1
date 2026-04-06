import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';

class EngagementSlice {
  final String label;
  final int totalUsers;

  const EngagementSlice({
    required this.label,
    required this.totalUsers,
  });

  factory EngagementSlice.fromJson(Map<String, dynamic> json) {
    return EngagementSlice(
      label: (json['label'] ?? 'Unknown').toString(),
      totalUsers: _parseInt(json['total_users']),
    );
  }

  static int _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? 0}') ?? 0;
  }
}

class EngagementReportResponse {
  final String groupBy;
  final int month;
  final int year;
  final int totalUsers;
  final List<int> availableYears;
  final List<EngagementSlice> rows;

  const EngagementReportResponse({
    required this.groupBy,
    required this.month,
    required this.year,
    required this.totalUsers,
    required this.availableYears,
    required this.rows,
  });

  factory EngagementReportResponse.fromJson(Map<String, dynamic> json) {
    final rowsJson = (json['rows'] is List) ? json['rows'] as List : const [];
    final yearsJson =
        (json['available_years'] is List) ? json['available_years'] as List : const [];
    return EngagementReportResponse(
      groupBy: (json['group_by'] ?? 'gender').toString(),
      month: EngagementSlice._parseInt(json['month']),
      year: EngagementSlice._parseInt(json['year']),
      totalUsers: EngagementSlice._parseInt(json['total_users']),
      availableYears: yearsJson
          .map((value) => EngagementSlice._parseInt(value))
          .where((value) => value > 0)
          .toList(),
      rows: rowsJson
          .whereType<Map>()
          .map((row) => EngagementSlice.fromJson(Map<String, dynamic>.from(row)))
          .toList(),
    );
  }
}

class EngagementApi {
  static String get _baseUrl => ConfigService.getApiBaseUrl();

  static bool _isWrongTarget404(Uri primary, http.Response res) {
    if (!kIsWeb || !kDebugMode) return false;
    if (res.statusCode != 404) return false;

    final body = res.body.toLowerCase();
    const path = '/api/admin/event-report/engagement';
    final cannotGetPath = body.contains('cannot get') && body.contains(path);
    if (!cannotGetPath) return false;

    final webOrigin = ConfigService.getWebOrigin();
    final isWebOrigin =
        webOrigin != null && ConfigService.isSameHostPort(primary, webOrigin);
    final isLikelyFlutterPort = ConfigService.isLikelyFlutterDevPort(primary);
    return isWebOrigin || isLikelyFlutterPort;
  }

  static Future<EngagementReportResponse> fetchReport({
    required String groupBy,
    required int month,
    required int year,
  }) async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse('$_baseUrl/api/admin/event-report/engagement')
        .replace(queryParameters: {
      'admin_id': adminId.toString(),
      'group_by': groupBy,
      'month': month.toString(),
      'year': year.toString(),
    });

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-admin-id': adminId.toString(),
    };

    var response = await http.get(uri, headers: headers).timeout(
          const Duration(seconds: 20),
        );

    if (_isWrongTarget404(uri, response)) {
      final fallback = ConfigService.getDevFallbackUri(
        '/api/admin/event-report/engagement',
      )?.replace(queryParameters: {
        'admin_id': adminId.toString(),
        'group_by': groupBy,
        'month': month.toString(),
        'year': year.toString(),
      });
      if (fallback != null && fallback != uri) {
        response = await http.get(fallback, headers: headers).timeout(
              const Duration(seconds: 20),
            );
      }
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Fetch engagement report failed: ${response.statusCode} ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid engagement report response');
    }

    return EngagementReportResponse.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }
}
