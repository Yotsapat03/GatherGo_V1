import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/services/admin_session_service.dart';
import '../../../core/services/config_service.dart';

class AuditLogEntry {
  final int id;
  final int? actorId;
  final String actorName;
  final String actorEmail;
  final String actorCode;
  final String action;
  final DateTime createdAt;
  final String? entityType;
  final int? entityId;
  final String? entityName;
  final String? ipAddress;
  final Map<String, dynamic> metadata;

  AuditLogEntry({
    required this.id,
    this.actorId,
    required this.actorName,
    required this.actorEmail,
    required this.actorCode,
    required this.action,
    required this.createdAt,
    this.entityType,
    this.entityId,
    this.entityName,
    this.ipAddress,
    this.metadata = const {},
  });

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  static int? _parseActorId(Map<String, dynamic> json) {
    final explicit =
        _parseInt(json['actor_id'] ?? json['admin_user_id'] ?? json['user_id']);
    if (explicit != null) return explicit;

    final code =
        (json['actor_code'] ?? json['user_code'] ?? json['display_code'] ?? '')
            .toString()
            .trim();
    final match = RegExp(r'(\d+)$').firstMatch(code);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static Map<String, dynamic> _parseMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return const {};
  }

  factory AuditLogEntry.fromJson(Map<String, dynamic> json) {
    return AuditLogEntry(
      id: _parseInt(json['id']) ?? 0,
      actorId: _parseActorId(json),
      actorName: (json['actor_name'] ?? json['user_name'] ?? '-').toString(),
      actorEmail: (json['actor_email'] ?? json['email'] ?? '-').toString(),
      actorCode: (json['actor_code'] ??
              json['user_code'] ??
              json['display_code'] ??
              '-')
          .toString(),
      action: (json['action'] ?? '-').toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      entityType: json['entity_type']?.toString(),
      entityId: _parseInt(json['entity_id']),
      entityName: json['entity_name']?.toString(),
      ipAddress: json['ip_address']?.toString(),
      metadata: _parseMap(json['metadata_json']),
    );
  }
}

class AuditLogApi {
  static String get _baseUrl => ConfigService.getBaseUrl();

  static Future<List<AuditLogEntry>> fetchAdminLogs({String q = ''}) async {
    final adminId = await AdminSessionService.getCurrentAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse('$_baseUrl/api/admin/audit-logs/admin').replace(
      queryParameters: {
        'q': q,
        'admin_id': adminId.toString(),
      },
    );

    try {
      final resp = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'x-admin-id': adminId.toString(),
        },
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        throw Exception('Fetch admin logs failed: ${resp.statusCode}');
      }

      final data = jsonDecode(resp.body);
      final list = (data is List) ? data : (data['items'] as List? ?? []);
      return list
          .map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Exception catch (e) {
      throw Exception('Network/Format error: $e');
    }
  }

  static Future<List<AuditLogEntry>> fetchUserLogs({String q = ''}) async {
    final adminId = await AdminSessionService.getCurrentAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse('$_baseUrl/api/admin/audit-logs/users').replace(
      queryParameters: {
        'q': q,
        'admin_id': adminId.toString(),
      },
    );

    try {
      final resp = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'x-admin-id': adminId.toString(),
        },
      ).timeout(const Duration(seconds: 20));

      if (resp.statusCode != 200) {
        throw Exception('Fetch user logs failed: ${resp.statusCode}');
      }

      final data = jsonDecode(resp.body);
      final list = (data is List) ? data : (data['items'] as List? ?? []);
      return list
          .map((e) => AuditLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Exception catch (e) {
      throw Exception('Network/Format error: $e');
    }
  }
}
