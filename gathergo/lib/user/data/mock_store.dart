import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockStore {
  static const String _kGlobalSpots = 'mockstore_global_spots_v1';
  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kGlobalSpots);
  }

  static Future<void> _saveGlobalSpots() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kGlobalSpots);
  }

  static Future<void> clearSessionState() async {
    joinedEvents.value = <Map<String, dynamic>>[];
    joinedSpots.value = <Map<String, dynamic>>[];
    mySpots.value = <Map<String, dynamic>>[];
    await _saveGlobalSpots();
  }

  // ===== Big Event (Browse) =====
  static final ValueNotifier<List<Map<String, dynamic>>> bigEvents =
      ValueNotifier<List<Map<String, dynamic>>>([
    {
      "image": "assets/images/user/events/event2.png",
      "distance": "5 km",
      "date": "5 December 2025",
      "location": "Mahidol campus",
      "organizer": "Young Sons",
      "description": "Big event sample description",
      "isPaid": true,
      "isJoined": false,
    },
    {
      "image": "assets/images/user/events/event1.png",
      "distance": "10 km",
      "date": "05/11/2025",
      "location": "Mahidol campus",
      "organizer": "JOG&JOY",
      "description": "Big event sample description",
      "isPaid": false,
      "isJoined": false,
    },
  ]);

  // ===== Joined Event =====
  static final ValueNotifier<List<Map<String, dynamic>>> joinedEvents =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  /// ✅ Join BigEvent (คงค่า isPaid เดิมจาก event)
  static void joinBigEvent(Map<String, dynamic> event) {
    final already = joinedEvents.value.any((e) => _sameBigEvent(e, event));
    if (already) return;

    final joined = Map<String, dynamic>.from(event);
    joined["isJoined"] = true;
    joined.putIfAbsent("isPaid", () => false); // กัน null

    final newEvents = List<Map<String, dynamic>>.from(bigEvents.value)
      ..removeWhere((e) => _sameBigEvent(e, event));

    final newJoined = List<Map<String, dynamic>>.from(joinedEvents.value)
      ..add(joined);

    bigEvents.value = newEvents;
    joinedEvents.value = newJoined;
  }

  /// ✅ Join BigEvent แบบ “จ่ายแล้ว”
  /// - เพิ่มเข้า joinedEvents พร้อม isPaid:true
  /// - ถ้าเคย join แล้ว (อยู่ใน joinedEvents) จะอัปเดตให้เป็น paid
  /// - ถ้าอยู่ใน bigEvents จะย้ายออกมา
  static void joinBigEventPaid(Map<String, dynamic> event) {
    // ถ้าเคย join แล้ว ให้ mark paid
    final alreadyJoined =
        joinedEvents.value.any((e) => _sameBigEvent(e, event));
    if (alreadyJoined) {
      markJoinedBigEventPaid(event);
      return;
    }

    final joined = Map<String, dynamic>.from(event);
    joined["isJoined"] = true;
    joined["isPaid"] = true;

    final newEvents = List<Map<String, dynamic>>.from(bigEvents.value)
      ..removeWhere((e) => _sameBigEvent(e, event));

    final newJoined = List<Map<String, dynamic>>.from(joinedEvents.value)
      ..add(joined);

    bigEvents.value = newEvents;
    joinedEvents.value = newJoined;
  }

  /// ✅ ถ้า event อยู่ใน joinedEvents แล้ว แต่อยากอัปเดตเป็น paid (เช่น หลังจ่ายเงิน)
  static void markJoinedBigEventPaid(Map<String, dynamic> event) {
    final list = List<Map<String, dynamic>>.from(joinedEvents.value);
    final index = list.indexWhere((e) => _sameBigEvent(e, event));
    if (index < 0) return;

    final updated = Map<String, dynamic>.from(list[index]);
    updated["isPaid"] = true;
    updated["isJoined"] = true;

    list[index] = updated;
    joinedEvents.value = list;
  }

  static void unjoinBigEvent(Map<String, dynamic> event) {
    final removed = List<Map<String, dynamic>>.from(joinedEvents.value)
      ..removeWhere((e) => _sameBigEvent(e, event));

    final back = Map<String, dynamic>.from(event);
    back["isJoined"] = false;
    back.putIfAbsent("isPaid", () => false);

    final newEvents = List<Map<String, dynamic>>.from(bigEvents.value);
    final alreadyInEvents = newEvents.any((e) => _sameBigEvent(e, back));
    if (!alreadyInEvents) newEvents.add(back);

    joinedEvents.value = removed;
    bigEvents.value = newEvents;
  }

  static bool _sameBigEvent(Map a, Map b) {
    return (a["date"] == b["date"]) &&
        (a["location"] == b["location"]) &&
        (a["organizer"] == b["organizer"]);
  }

  // =========================================
  // ✅ Compatibility methods (รองรับโค้ดที่เรียก joinEvent/unjoinEvent)
  // =========================================

  /// ให้โค้ดเก่าเรียก MockStore.joinEvent(event) ได้
  /// เดาว่าเป็น BigEvent หรือ Spot จาก key ที่มีใน Map
  static void joinEvent(Map<String, dynamic> event) {
    final bool isBigEvent =
        event.containsKey('organizer') || event.containsKey('isPaid');

    if (isBigEvent) {
      joinBigEvent(event);
    } else {
      joinSpot(event);
    }
  }

  /// ✅ เพิ่มใหม่: ให้ Payment เรียก MockStore.joinEventPaid(event)
  /// จะบังคับให้ BigEvent เป็น Paid (Spot ไม่รองรับ paid ใน flow นี้)
  static void joinEventPaid(Map<String, dynamic> event) {
    final bool isBigEvent =
        event.containsKey('organizer') || event.containsKey('isPaid');

    if (isBigEvent) {
      joinBigEventPaid(event);
    } else {
      // ถ้าเผลอส่ง spot มา ก็ join ปกติ
      joinSpot(event);
    }
  }

  /// ให้โค้ดเก่าเรียก MockStore.unjoinEvent(event) ได้
  static void unjoinEvent(Map<String, dynamic> event) {
    final bool isBigEvent =
        event.containsKey('organizer') || event.containsKey('isPaid');

    if (isBigEvent) {
      unjoinBigEvent(event);
    } else {
      unjoinSpot(event);
    }
  }

  // ===========================
  // ===== Spot (Browse) ========
  // ===========================
  static final ValueNotifier<List<Map<String, dynamic>>> spots =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  // ===== My Created Spots (Create Spot Flow) =====
  static final ValueNotifier<List<Map<String, dynamic>>> mySpots =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  /// สร้าง Spot ใหม่ (ของ User)
  /// - เพิ่มเข้า mySpots เพื่อให้หน้า Your Spot โผล่ทันที
  /// - (ทางเลือก) เพิ่มเข้า spots เพื่อให้ไปโผล่หน้า Browse Spot ด้วย
  static void createMySpot(
    Map<String, dynamic> spot, {
    bool alsoAddToBrowse = true,
  }) {
    final created = Map<String, dynamic>.from(spot);

    // default fields กัน null
    created.putIfAbsent("isJoined", () => false);
    created.putIfAbsent("host", () => "You");

    final newMy = List<Map<String, dynamic>>.from(mySpots.value)..add(created);
    mySpots.value = newMy;

    if (alsoAddToBrowse) {
      final browse = List<Map<String, dynamic>>.from(spots.value);

      final already = browse.any((s) => _sameSpot(s, created));
      if (!already) {
        browse.add(created);
        spots.value = browse;
        _saveGlobalSpots();
      }
    }
  }

  static void mergeSpotsFromBackend(List<Map<String, dynamic>> backendSpots) {
    spots.value = List<Map<String, dynamic>>.from(backendSpots);
    _saveGlobalSpots();
  }

  // ===== Joined Spot =====
  static final ValueNotifier<List<Map<String, dynamic>>> joinedSpots =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  static void joinSpot(Map<String, dynamic> spot) {
    final already = joinedSpots.value.any((s) => _sameSpot(s, spot));
    if (already) return;

    final joined = Map<String, dynamic>.from(spot);
    joined["isJoined"] = true;
    joined["joinedCount"] = "1";

    final newSpots = List<Map<String, dynamic>>.from(spots.value)
      ..removeWhere((s) => _sameSpot(s, spot));
    final newJoined = List<Map<String, dynamic>>.from(joinedSpots.value)
      ..add(joined);

    spots.value = newSpots;
    joinedSpots.value = newJoined;
    _saveGlobalSpots();
  }

  static void unjoinSpot(Map<String, dynamic> spot) {
    final removed = List<Map<String, dynamic>>.from(joinedSpots.value)
      ..removeWhere((s) => _sameSpot(s, spot));

    joinedSpots.value = removed;
  }

  static void removeSpot(Map<String, dynamic> spot) {
    final nextSpots = List<Map<String, dynamic>>.from(spots.value)
      ..removeWhere((s) => _sameSpot(s, spot));
    final nextJoined = List<Map<String, dynamic>>.from(joinedSpots.value)
      ..removeWhere((s) => _sameSpot(s, spot));
    final nextMy = List<Map<String, dynamic>>.from(mySpots.value)
      ..removeWhere((s) => _sameSpot(s, spot));

    spots.value = nextSpots;
    joinedSpots.value = nextJoined;
    mySpots.value = nextMy;
    _saveGlobalSpots();
  }

  static void updateSpot(Map<String, dynamic> spot) {
    final updated = Map<String, dynamic>.from(spot);

    List<Map<String, dynamic>> replaceIn(List<Map<String, dynamic>> source) {
      return source
          .map((item) => _sameSpot(item, updated) ||
                  ((item["backendSpotId"] ?? item["id"]).toString() ==
                      (updated["backendSpotId"] ?? updated["id"]).toString())
              ? Map<String, dynamic>.from(updated)
              : item)
          .toList(growable: false);
    }

    spots.value = replaceIn(List<Map<String, dynamic>>.from(spots.value));
    joinedSpots.value =
        replaceIn(List<Map<String, dynamic>>.from(joinedSpots.value));
    mySpots.value = replaceIn(List<Map<String, dynamic>>.from(mySpots.value));
    _saveGlobalSpots();
  }

  static bool _sameSpot(Map a, Map b) {
    return (a["title"] == b["title"]) &&
        (a["date"] == b["date"]) &&
        (a["time"] == b["time"]) &&
        (a["location"] == b["location"]);
  }
}
