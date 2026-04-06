import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';

class UserAccountState {
  final String status;
  final String message;

  const UserAccountState({
    required this.status,
    required this.message,
  });

  bool get isSuspended => status == 'suspended';
  bool get isDeleted => status == 'deleted';
  bool get isBlocked => isSuspended || isDeleted;
}

class UserAccountGuardService {
  const UserAccountGuardService._();

  static Future<UserAccountState> fetchCurrentUserState() async {
    final userId = await SessionService.getCurrentUserId();
    if (userId == null || userId <= 0) {
      throw Exception('No active user session.');
    }

    final headers = <String, String>{
      'Accept': 'application/json',
      'x-user-id': userId.toString(),
    };

    final base = ConfigService.getBaseUrl();
    http.Response res = await http
        .get(Uri.parse('$base/api/users/me'), headers: headers)
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      res = await http
          .get(Uri.parse('$base/api/users/$userId'), headers: headers)
          .timeout(const Duration(seconds: 20));
    }

    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }

    final decoded = jsonDecode(res.body);
    final data =
        decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    final userJson = data['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(data['user'] as Map<String, dynamic>)
        : data;

    final status = _normalizeStatus(_extractStatus(userJson));
    final message = _extractMessage(userJson);
    return UserAccountState(status: status, message: message);
  }

  static String extractStatusFromLoginPayload(Map<String, dynamic> data) {
    final userJson = data['user'] is Map<String, dynamic>
        ? Map<String, dynamic>.from(data['user'] as Map<String, dynamic>)
        : data;
    return _normalizeStatus(_extractStatus(userJson));
  }

  static String _extractStatus(Map<String, dynamic> data) {
    final candidates = <dynamic>[
      data['status'],
      data['account_status'],
      data['user_status'],
      data['state'],
      data['accountState'],
      data['accountStatus'],
      data['deleted_at'] != null ? 'deleted' : null,
      data['is_deleted'] == true ? 'deleted' : null,
      data['deleted'] == true ? 'deleted' : null,
      data['is_suspended'] == true ? 'suspended' : null,
      data['suspended'] == true ? 'suspended' : null,
      data['suspended_at'] != null ? 'suspended' : null,
    ];

    for (final candidate in candidates) {
      final value = candidate?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return 'active';
  }

  static String _normalizeStatus(String raw) {
    final value = raw.trim().toLowerCase();
    if (value == 'deleted' || value == 'remove' || value == 'removed') {
      return 'deleted';
    }
    if (value == 'suspended' ||
        value == 'suspension' ||
        value == 'blocked' ||
        value == 'banned') {
      return 'suspended';
    }
    return 'active';
  }

  static String _extractMessage(Map<String, dynamic> data) {
    final message = data['status_message'] ??
        data['message'] ??
        data['account_message'] ??
        data['reason'];
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
    return '';
  }
}
