import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import 'activity_stats_refresh_service.dart';

class ActivityCompletionService {
  const ActivityCompletionService._();

  static double? _parseDistanceKm(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final direct = double.tryParse(raw);
    if (direct != null) return direct;

    final sanitized = raw
        .replaceAll(RegExp(r'(?i)\s*km\b'), '')
        .replaceAll(',', '')
        .trim();
    return double.tryParse(sanitized);
  }

  static Future<Map<String, String>> _headers(int userId) async {
    return <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'x-user-id': userId.toString(),
    };
  }

  static Future<bool> _send({
    required String method,
    required String path,
    required Map<String, dynamic> body,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('${ConfigService.getBaseUrl()}$path');
    late final http.Response response;
    switch (method) {
      case 'PATCH':
        response = await http
            .patch(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 20));
        break;
      case 'PUT':
        response = await http
            .put(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 20));
        break;
      default:
        response = await http
            .post(uri, headers: headers, body: jsonEncode(body))
            .timeout(const Duration(seconds: 20));
        break;
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return true;
    }
    if (response.statusCode == 404 || response.statusCode == 405) {
      return false;
    }
    throw Exception('HTTP ${response.statusCode}: ${response.body}');
  }

  static Future<bool> completeSpot(Map<String, dynamic> spot) async {
    final userId = await SessionService.getCurrentUserId();
    final spotId =
        int.tryParse((spot['backendSpotId'] ?? spot['id'] ?? '').toString());
    if (userId == null || userId <= 0 || spotId == null || spotId <= 0) {
      return false;
    }

    final headers = await _headers(userId);
    final taskType = (spot['taskType'] ?? 'spot_joined').toString();
    final requestedDistance = _parseDistanceKm(
      spot['completed_distance_km'] ?? spot['total_distance'] ?? spot['distance'],
    );
    if (requestedDistance != null && requestedDistance < 0) {
      throw Exception('distance_km must be non-negative');
    }
    final body = <String, dynamic>{
      'user_id': userId,
      'spot_id': spotId,
      'completed_at': DateTime.now().toIso8601String(),
      'task_type': taskType,
      'title': (spot['title'] ?? '').toString(),
      'distance_km': requestedDistance,
    };

    final attempts = <({String method, String path})>[
      (method: 'POST', path: '/api/spots/$spotId/complete'),
      (method: 'PATCH', path: '/api/spots/$spotId/complete'),
    ];

    for (final attempt in attempts) {
      final ok = await _send(
        method: attempt.method,
        path: attempt.path,
        body: body,
        headers: headers,
      );
      if (ok) {
        ActivityStatsRefreshService.notifyStatsChanged();
        return true;
      }
    }
    return false;
  }

  static Future<bool> completeBigEvent(Map<String, dynamic> event) async {
    final userId = await SessionService.getCurrentUserId();
    final eventId =
        int.tryParse((event['eventId'] ?? event['id'] ?? '').toString());
    final bookingId = int.tryParse(
      (event['bookingId'] ?? event['booking_id'] ?? '').toString(),
    );
    if (userId == null || userId <= 0 || eventId == null || eventId <= 0) {
      return false;
    }

    final headers = await _headers(userId);
    final requestedDistance = _parseDistanceKm(
      event['completed_distance_km'] ?? event['total_distance'] ?? event['distance'],
    );
    if (requestedDistance != null && requestedDistance < 0) {
      throw Exception('distance_km must be non-negative');
    }
    final body = <String, dynamic>{
      'user_id': userId,
      'event_id': eventId,
      if (bookingId != null && bookingId > 0) 'booking_id': bookingId,
      'completed_at': DateTime.now().toIso8601String(),
      'task_type': 'big_event_joined',
      'title': (event['title'] ?? '').toString(),
      'distance_km': requestedDistance,
    };

    final attempts = <({String method, String path})>[
      if (bookingId != null && bookingId > 0)
        (
          method: 'POST',
          path: '/api/user/joined-events/$bookingId/complete',
        ),
      if (bookingId != null && bookingId > 0)
        (
          method: 'PATCH',
          path: '/api/user/joined-events/$bookingId/complete',
        ),
    ];

    for (final attempt in attempts) {
      final ok = await _send(
        method: attempt.method,
        path: attempt.path,
        body: body,
        headers: headers,
      );
      if (ok) {
        ActivityStatsRefreshService.notifyStatsChanged();
        return true;
      }
    }
    return false;
  }
}
