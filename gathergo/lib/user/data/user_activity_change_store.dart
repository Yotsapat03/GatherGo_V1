import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class UserActivityChangeStore {
  static const String _kSnapshots = 'user_activity_change_snapshots_v1';
  static const String _kNotifications = 'user_activity_change_notifications_v1';

  static Future<List<Map<String, dynamic>>> sync({
    required List<Map<String, dynamic>> joinedSpots,
    required List<Map<String, dynamic>> joinedBigEvents,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final previousSnapshots = _decodeMap(
      prefs.getString(_kSnapshots),
    );
    final storedNotifications = _decodeList(
      prefs.getString(_kNotifications),
    );

    final nextSnapshots = <String, Map<String, dynamic>>{};
    final generatedNotifications = <Map<String, dynamic>>[];

    for (final spot in joinedSpots) {
      final snapshot = _buildSpotSnapshot(spot);
      final key = snapshot['snapshot_key'].toString();
      nextSnapshots[key] = snapshot;
      final previous = previousSnapshots[key];
      if (previous == null) continue;

      final changes = _diff(previous, snapshot);
      if (changes.isEmpty) continue;

      final changedAt =
          (snapshot['updated_at'] ?? DateTime.now().toIso8601String())
              .toString();
      final notificationKey = 'change|$key|$changedAt';
      if (storedNotifications.any(
        (item) => (item['notification_key'] ?? '').toString() == notificationKey,
      )) {
        continue;
      }

      generatedNotifications.add({
        'notification_key': notificationKey,
        'kind': 'change',
        'type': 'spot',
        'title': (snapshot['title'] ?? 'Spot').toString(),
        'entity_id': snapshot['entity_id'],
        'display_code': snapshot['display_code'],
        'changed_at': changedAt,
        'change_lines': changes,
        'payload': Map<String, dynamic>.from(spot),
      });
    }

    for (final event in joinedBigEvents) {
      final snapshot = _buildBigEventSnapshot(event);
      final key = snapshot['snapshot_key'].toString();
      nextSnapshots[key] = snapshot;
      final previous = previousSnapshots[key];
      if (previous == null) continue;

      final changes = _diff(previous, snapshot);
      if (changes.isEmpty) continue;

      final changedAt =
          (snapshot['updated_at'] ?? DateTime.now().toIso8601String())
              .toString();
      final notificationKey = 'change|$key|$changedAt';
      if (storedNotifications.any(
        (item) => (item['notification_key'] ?? '').toString() == notificationKey,
      )) {
        continue;
      }

      generatedNotifications.add({
        'notification_key': notificationKey,
        'kind': 'change',
        'type': 'big_event',
        'title': (snapshot['title'] ?? 'Big Event').toString(),
        'entity_id': snapshot['entity_id'],
        'display_code': snapshot['display_code'],
        'changed_at': changedAt,
        'change_lines': changes,
        'payload': Map<String, dynamic>.from(event),
      });
    }

    final mergedNotifications = <Map<String, dynamic>>[
      ...generatedNotifications,
      ...storedNotifications,
    ];

    await prefs.setString(_kSnapshots, jsonEncode(nextSnapshots));
    await prefs.setString(_kNotifications, jsonEncode(mergedNotifications));
    return mergedNotifications;
  }

  static Future<List<Map<String, dynamic>>> readNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    return _decodeList(prefs.getString(_kNotifications));
  }

  static Map<String, Map<String, dynamic>> _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(
            key.toString(),
            value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{},
          ),
        );
      }
    } catch (_) {}
    return {};
  }

  static List<Map<String, dynamic>> _decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static Map<String, dynamic> _buildSpotSnapshot(Map<String, dynamic> spot) {
    final id = (spot['id'] ?? spot['backendSpotId'] ?? '').toString();
    return {
      'snapshot_key': 'spot:$id',
      'entity_id': id,
      'display_code': (spot['display_code'] ?? 'SP$id').toString(),
      'title': (spot['title'] ?? '').toString(),
      'description': (spot['description'] ?? '').toString(),
      'location': (spot['location'] ?? '').toString(),
      'date': (spot['event_date'] ?? spot['date'] ?? '').toString(),
      'time': (spot['event_time'] ?? spot['time'] ?? '').toString(),
      'total_distance': (spot['total_distance'] ?? '').toString(),
      'status': (spot['status'] ?? '').toString(),
      'updated_at': (spot['updated_at'] ?? '').toString(),
    };
  }

  static Map<String, dynamic> _buildBigEventSnapshot(Map<String, dynamic> event) {
    final id = (event['id'] ?? event['event_id'] ?? '').toString();
    return {
      'snapshot_key': 'big_event:$id',
      'entity_id': id,
      'display_code': (event['display_code'] ?? 'EV$id').toString(),
      'title': (event['title'] ?? '').toString(),
      'description': (event['description'] ?? '').toString(),
      'location': (event['meeting_point'] ?? event['location'] ?? '').toString(),
      'date': (event['start_at'] ?? event['date'] ?? '').toString(),
      'end_at': (event['end_at'] ?? '').toString(),
      'total_distance': (event['total_distance'] ?? '').toString(),
      'status': (event['booking_status'] ?? event['status'] ?? '').toString(),
      'updated_at': (event['updated_at'] ?? event['event_updated_at'] ?? '').toString(),
    };
  }

  static List<String> _diff(
    Map<String, dynamic> previous,
    Map<String, dynamic> current,
  ) {
    const labels = <String, String>{
      'title': 'Title',
      'description': 'Description',
      'location': 'Location',
      'date': 'Date',
      'time': 'Time',
      'end_at': 'End time',
      'total_distance': 'Total distance',
      'status': 'Status',
    };

    final changes = <String>[];
    for (final entry in labels.entries) {
      final before = (previous[entry.key] ?? '').toString().trim();
      final after = (current[entry.key] ?? '').toString().trim();
      if (before == after) continue;
      changes.add('${entry.value}: ${before.isEmpty ? '-' : before} -> ${after.isEmpty ? '-' : after}');
    }
    return changes;
  }
}
