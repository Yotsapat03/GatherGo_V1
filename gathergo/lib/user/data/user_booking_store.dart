import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserBookingStore {
  static const String _kFavoriteBigEvents =
      'user_booking_store_favorite_big_events_v1';
  static bool _initialized = false;

  static final ValueNotifier<List<Map<String, dynamic>>> favoriteBigEvents =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFavoriteBigEvents);
    if (raw == null || raw.trim().isEmpty) return;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        favoriteBigEvents.value = decoded
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kFavoriteBigEvents,
      jsonEncode(favoriteBigEvents.value),
    );
  }

  static Future<void> clearAll() async {
    favoriteBigEvents.value = <Map<String, dynamic>>[];
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kFavoriteBigEvents);
  }

  static String favoriteKey(Map<String, dynamic> event) {
    final id = (event['id'] ?? event['event_id'] ?? event['eventId'] ?? '')
        .toString()
        .trim();
    if (id.isNotEmpty) return 'big-event:$id';

    final title = (event['title'] ?? '').toString().trim().toLowerCase();
    final date = (event['start_at'] ?? event['date'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final location = (event['location'] ??
            event['location_display'] ??
            event['meeting_point'] ??
            '')
        .toString()
        .trim()
        .toLowerCase();
    return 'big-event:$title|$date|$location';
  }

  static bool isFavorite(Map<String, dynamic> event) {
    final key = favoriteKey(event);
    return favoriteBigEvents.value.any(
      (item) => favoriteKey(item) == key,
    );
  }

  static Future<bool> toggleFavoriteBigEvent(Map<String, dynamic> event) async {
    if (isFavorite(event)) {
      await removeFavoriteBigEvent(event);
      return false;
    }
    await addFavoriteBigEvent(event);
    return true;
  }

  static Future<void> addFavoriteBigEvent(Map<String, dynamic> event) async {
    final item = Map<String, dynamic>.from(event)
      ..['favoriteKey'] = favoriteKey(event)
      ..['savedAt'] = DateTime.now().toIso8601String();

    final next = List<Map<String, dynamic>>.from(favoriteBigEvents.value)
      ..removeWhere((e) => favoriteKey(e) == favoriteKey(item))
      ..insert(0, item);
    favoriteBigEvents.value = next;
    await _save();
  }

  static Future<void> removeFavoriteBigEvent(Map<String, dynamic> event) async {
    final key = favoriteKey(event);
    favoriteBigEvents.value = List<Map<String, dynamic>>.from(
      favoriteBigEvents.value,
    )..removeWhere((item) => favoriteKey(item) == key);
    await _save();
  }
}
