import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';

class UserAdminService {
  const UserAdminService._();

  static Future<void> suspendUser(String userId) {
    return _updateUserStatus(userId: userId, status: 'suspended');
  }

  static Future<void> unsuspendUser(String userId) {
    return _updateUserStatus(userId: userId, status: 'active');
  }

  static Future<void> deleteUser(String userId) async {
    final adminId = await _requireAdminId();
    final base = ConfigService.getBaseUrl();
    final id = userId.trim();
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'x-admin-id': adminId.toString(),
    };

    final attempts = <Future<http.Response> Function()>[
      () => http.delete(
            Uri.parse('$base/api/admin/users/$id').replace(
              queryParameters: {'admin_id': adminId.toString()},
            ),
            headers: headers,
          ),
      () => http.patch(
            Uri.parse('$base/api/admin/users/$id'),
            headers: headers,
            body: jsonEncode({'admin_id': adminId, 'status': 'deleted'}),
          ),
      () => http.patch(
            Uri.parse('$base/api/admin/users/$id/status'),
            headers: headers,
            body: jsonEncode({'admin_id': adminId, 'status': 'deleted'}),
          ),
    ];

    await _runAttempts(attempts);
  }

  static Future<void> _updateUserStatus({
    required String userId,
    required String status,
  }) async {
    final adminId = await _requireAdminId();
    final base = ConfigService.getBaseUrl();
    final id = userId.trim();
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'x-admin-id': adminId.toString(),
    };

    final attempts = <Future<http.Response> Function()>[
      () => http.patch(
            Uri.parse('$base/api/admin/users/$id'),
            headers: headers,
            body: jsonEncode({'admin_id': adminId, 'status': status}),
          ),
      () => http.patch(
            Uri.parse('$base/api/admin/users/$id/status'),
            headers: headers,
            body: jsonEncode({'admin_id': adminId, 'status': status}),
          ),
    ];

    await _runAttempts(attempts);
  }

  static Future<int> _requireAdminId() async {
    final adminId = await AdminSessionService.getCurrentAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }
    return adminId;
  }

  static Future<void> _runAttempts(
    List<Future<http.Response> Function()> attempts,
  ) async {
    String? lastError;
    for (final attempt in attempts) {
      try {
        final res = await attempt().timeout(const Duration(seconds: 20));
        if (res.statusCode >= 200 && res.statusCode < 300) {
          return;
        }
        lastError = _extractMessage(res);
        if (res.statusCode != 404 && res.statusCode != 405) {
          break;
        }
      } catch (e) {
        lastError = e.toString();
      }
    }

    throw Exception(lastError ?? 'Unable to update user status.');
  }

  static String _extractMessage(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        final message = decoded['message'] ?? decoded['error'];
        if (message is String && message.trim().isNotEmpty) {
          return message.trim();
        }
      }
    } catch (_) {}
    return 'HTTP ${res.statusCode}: ${res.body}';
  }
}
