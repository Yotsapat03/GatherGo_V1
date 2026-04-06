import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import 'report_models.dart';

class SpotReportsApi {
  static String get _baseUrl => ConfigService.getApiBaseUrl();

  static Future<List<SpotLeaveFeedbackRow>> fetchBehaviorSafetyLeaveFeedback() async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    debugPrint('[GatherGo] SpotReportsApi.fetchBehaviorSafetyLeaveFeedback adminId=$adminId');
    final uri = Uri.parse('$_baseUrl/api/admin/spot-leave-feedback')
        .replace(queryParameters: {
      'admin_id': adminId.toString(),
    });
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'x-admin-id': adminId.toString(),
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception('Fetch spot leave feedback failed: ${response.statusCode} ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid spot leave feedback response');
    }

    return decoded
        .map<SpotLeaveFeedbackRow>(
          (item) => SpotLeaveFeedbackRow.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }
}
