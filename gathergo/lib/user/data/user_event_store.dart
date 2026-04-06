import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../core/services/session_service.dart';

class UserEventStore {
  static const String _kPendingEvents = 'user_event_store_pending_v1';
  static const String _kCompletedEvents = 'user_event_store_completed_v1';
  static bool _initialized = false;
  static int? _activeOwnerUserId;
  static List<Map<String, dynamic>> _allPendingEvents =
      <Map<String, dynamic>>[];
  static List<Map<String, dynamic>> _allCompletedEvents =
      <Map<String, dynamic>>[];

  static final ValueNotifier<List<Map<String, dynamic>>> pendingEvents =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  static final ValueNotifier<List<Map<String, dynamic>>> completedEvents =
      ValueNotifier<List<Map<String, dynamic>>>([]);
  static final ValueNotifier<Map<String, dynamic>> scoreBoard =
      ValueNotifier<Map<String, dynamic>>({
    "totalKm": 0.0,
    "completedCount": 0,
    "unrecorded": 0,
  });

  static Future<void> init() async {
    if (!_initialized) {
      _initialized = true;

      final prefs = await SharedPreferences.getInstance();
      final pendingRaw = prefs.getString(_kPendingEvents);
      final completedRaw = prefs.getString(_kCompletedEvents);

      if (pendingRaw != null && pendingRaw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(pendingRaw);
          if (decoded is List) {
            _allPendingEvents = decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } catch (_) {}
      }

      if (completedRaw != null && completedRaw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(completedRaw);
          if (decoded is List) {
            _allCompletedEvents = decoded
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
          }
        } catch (_) {}
      }
    }
    _activeOwnerUserId = await SessionService.getCurrentUserId();
    _refreshVisibleState();
  }

  static Future<void> refreshForCurrentUser() async {
    if (!_initialized) {
      await init();
      return;
    }
    _activeOwnerUserId = await SessionService.getCurrentUserId();
    _refreshVisibleState();
  }

  static Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPendingEvents);
    await prefs.remove(_kCompletedEvents);
    _allPendingEvents = <Map<String, dynamic>>[];
    _allCompletedEvents = <Map<String, dynamic>>[];
    _refreshVisibleState();
  }

  static int? _currentOwnerUserId() {
    return SessionService.currentUserIdSync ?? _activeOwnerUserId;
  }

  static int _normalizedOwnerUserId(Map<String, dynamic> item) {
    return int.tryParse(
            (item["ownerUserId"] ?? item["owner_user_id"] ?? "0").toString()) ??
        0;
  }

  static List<Map<String, dynamic>> _itemsForOwner(
    List<Map<String, dynamic>> items,
    int? ownerUserId,
  ) {
    final ownerId = ownerUserId ?? _currentOwnerUserId() ?? 0;
    if (ownerId <= 0) return <Map<String, dynamic>>[];
    return items
        .where((item) => _normalizedOwnerUserId(item) == ownerId)
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  static void _refreshVisibleState() {
    pendingEvents.value = _itemsForOwner(_allPendingEvents, _activeOwnerUserId);
    completedEvents.value =
        _itemsForOwner(_allCompletedEvents, _activeOwnerUserId);
    _recomputeScoreBoard();
  }

  static Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPendingEvents, jsonEncode(_allPendingEvents));
    await prefs.setString(_kCompletedEvents, jsonEncode(_allCompletedEvents));
  }

  static List<Map<String, dynamic>> completedEventsForUser(int? userId) {
    return _itemsForOwner(_allCompletedEvents, userId);
  }

  static List<Map<String, dynamic>> pendingEventsForUser(int? userId) {
    return _itemsForOwner(_allPendingEvents, userId);
  }

  static Map<String, dynamic> _withOwner(Map<String, dynamic> item) {
    final ownerUserId = _currentOwnerUserId() ?? 0;
    return <String, dynamic>{
      ...item,
      "ownerUserId": ownerUserId,
    };
  }

  static String bigEventPendingKey({
    required dynamic eventId,
    required dynamic bookingId,
    required String title,
    required String startAt,
    required String location,
  }) {
    final normalizedBookingId = int.tryParse("$bookingId") ?? 0;
    final normalizedEventId = int.tryParse("$eventId") ?? 0;
    if (normalizedBookingId > 0 && normalizedEventId > 0) {
      return "${normalizedEventId}_$normalizedBookingId";
    }
    return "big_event_joined|$normalizedEventId|$title|$startAt|$location";
  }

  static String spotPendingKey({
    required String taskType,
    required String title,
    required String date,
    required String time,
    required String location,
  }) {
    return "$taskType|$title|$date|$time|$location";
  }

  static bool isCompletedKey(String key) {
    if (key.isEmpty) return false;
    return _itemsForOwner(_allCompletedEvents, null)
        .any((e) => (e["pendingKey"] ?? "").toString() == key);
  }

  static bool isPendingKey(String key) {
    if (key.isEmpty) return false;
    return _itemsForOwner(_allPendingEvents, null)
        .any((e) => (e["pendingKey"] ?? "").toString() == key);
  }

  static void addPendingEvent(Map<String, dynamic> payload) {
    final eventMap = (payload["event"] is Map)
        ? Map<String, dynamic>.from(payload["event"] as Map)
        : <String, dynamic>{};
    if (eventMap.isEmpty) return;

    final eventId = int.tryParse((eventMap["id"] ?? "").toString()) ?? 0;
    final bookingId =
        int.tryParse((payload["bookingId"] ?? "").toString()) ?? 0;
    final title = (eventMap["title"] ?? "-").toString();
    final startAt =
        (eventMap["start_at"] ?? eventMap["date"] ?? "-").toString();
    final location =
        (eventMap["meeting_point"] ?? eventMap["location"] ?? "-").toString();
    final key = bigEventPendingKey(
      eventId: eventId,
      bookingId: bookingId,
      title: title,
      startAt: startAt,
      location: location,
    );

    final item = _withOwner(<String, dynamic>{
      ...eventMap,
      "event": eventMap,
      "eventId": eventId,
      "bookingId": bookingId,
      "pendingKey": key,
      "taskType": "big_event_joined",
      "status": "IN PROGRESS",
    });

    final next = List<Map<String, dynamic>>.from(_allPendingEvents)
      ..removeWhere((e) =>
          _normalizedOwnerUserId(e) == _normalizedOwnerUserId(item) &&
          (e["pendingKey"] ?? "").toString() == key)
      ..insert(0, item);
    _allPendingEvents = next;
    _refreshVisibleState();
    _save();
  }

  static void addCreatedSpot(Map<String, dynamic> spot) {
    _addSpotTask(spot, taskType: "spot_created");
  }

  static void addJoinedSpot(Map<String, dynamic> spot) {
    _addSpotTask(spot, taskType: "spot_joined");
  }

  static void _addSpotTask(
    Map<String, dynamic> spot, {
    required String taskType,
  }) {
    final source = Map<String, dynamic>.from(spot);
    final title = (source["title"] ?? "Spot").toString();
    final date = (source["date"] ?? "").toString();
    final time = (source["time"] ?? "").toString();
    final location = (source["location"] ?? "").toString();
    final key = spotPendingKey(
      taskType: taskType,
      title: title,
      date: date,
      time: time,
      location: location,
    );

    final item = _withOwner(<String, dynamic>{
      ...source,
      "event": source,
      "pendingKey": key,
      "taskType": taskType,
      "status": "IN PROGRESS",
    });

    final next = List<Map<String, dynamic>>.from(_allPendingEvents)
      ..removeWhere((e) =>
          _normalizedOwnerUserId(e) == _normalizedOwnerUserId(item) &&
          (e["pendingKey"] ?? "").toString() == key)
      ..insert(0, item);
    _allPendingEvents = next;
    _refreshVisibleState();
    _save();
  }

  static void completeTask(Map<String, dynamic> item) {
    final ownedItem = _withOwner(Map<String, dynamic>.from(item));
    final key = (ownedItem["pendingKey"] ?? "").toString();
    if (key.isEmpty) return;
    final ownerUserId = _normalizedOwnerUserId(ownedItem);
    final nextPending = List<Map<String, dynamic>>.from(_allPendingEvents)
      ..removeWhere((e) =>
          _normalizedOwnerUserId(e) == ownerUserId &&
          (e["pendingKey"] ?? "").toString() == key);
    _allPendingEvents = nextPending;

    final done = Map<String, dynamic>.from(ownedItem)
      ..["status"] = "COMPLETED"
      ..["completedAt"] = DateTime.now().toIso8601String();
    final nextDone = List<Map<String, dynamic>>.from(_allCompletedEvents)
      ..removeWhere((e) =>
          _normalizedOwnerUserId(e) == ownerUserId &&
          (e["pendingKey"] ?? "").toString() == key)
      ..insert(0, done);
    _allCompletedEvents = nextDone;
    _refreshVisibleState();
    _save();
  }

  static void markCompleted(Map<String, dynamic> item) {
    completeTask(item);
  }

  static void _recomputeScoreBoard() {
    final done = completedEvents.value;
    double totalKm = 0;
    for (final item in done) {
      totalKm += _distanceKm(item);
    }
    scoreBoard.value = {
      "totalKm": totalKm,
      "completedCount": done.length,
      "unrecorded": pendingEvents.value.length,
    };
  }

  static double _distanceKm(Map<String, dynamic> item) {
    double? asDouble(dynamic v) => v == null ? null : double.tryParse("$v");

    final direct = asDouble(item["total_distance"]);
    if (direct != null) return direct;

    final kmPerRound = asDouble(item["kmPerRound"] ?? item["distance_per_lap"]);
    final round = asDouble(item["round"] ?? item["number_of_laps"]);
    if (kmPerRound != null && round != null) return kmPerRound * round;

    final distanceText = (item["distance"] ?? "").toString();
    final m = RegExp(r"(\d+(\.\d+)?)").firstMatch(distanceText);
    if (m != null) return double.tryParse(m.group(1) ?? "") ?? 0;
    return 0;
  }
}
