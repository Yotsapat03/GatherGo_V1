import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app_routes.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/payment_booking_status.dart';
import '../../widgets/common/app_nav_bar.dart';

class MyEventPage extends StatefulWidget {
  const MyEventPage({super.key});

  @override
  State<MyEventPage> createState() => _MyEventPageState();
}

class _MyEventPageState extends State<MyEventPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bigEvents = [];
  List<Map<String, dynamic>> _joinedSpots = [];
  List<Map<String, dynamic>> _createdSpots = [];

  String get _baseUrl => ConfigService.getBaseUrl();

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userId = await SessionService.getCurrentUserId();
      if (userId == null || userId <= 0) {
        throw Exception("No active user session");
      }

      final joinedEventsUri =
          Uri.parse("$_baseUrl/api/user/joined-events?user_id=$userId");
      final joinedSpotsUri =
          Uri.parse("$_baseUrl/api/spots/joined?user_id=$userId");
      final createdSpotsUri =
          Uri.parse("$_baseUrl/api/spots/mine?user_id=$userId");

      final responses = await Future.wait([
        http.get(joinedEventsUri,
            headers: {"Accept": "application/json", "x-user-id": "$userId"}),
        http.get(joinedSpotsUri,
            headers: {"Accept": "application/json", "x-user-id": "$userId"}),
        http.get(createdSpotsUri,
            headers: {"Accept": "application/json", "x-user-id": "$userId"}),
      ]);

      if (responses[0].statusCode != 200) {
        throw Exception(
            "Joined events HTTP ${responses[0].statusCode}: ${responses[0].body}");
      }
      if (responses[1].statusCode != 200) {
        throw Exception(
            "Joined spots HTTP ${responses[1].statusCode}: ${responses[1].body}");
      }
      if (responses[2].statusCode != 200) {
        throw Exception(
            "Created spots HTTP ${responses[2].statusCode}: ${responses[2].body}");
      }

      final joinedEvents = jsonDecode(responses[0].body);
      final joinedSpots = jsonDecode(responses[1].body);
      final createdSpots = jsonDecode(responses[2].body);

      if (joinedEvents is! List ||
          joinedSpots is! List ||
          createdSpots is! List) {
        throw Exception("Invalid response format");
      }

      final bigEvents = joinedEvents
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) =>
              (e["source_type"] ?? "BIG_EVENT").toString().toUpperCase() ==
              "BIG_EVENT")
          .map((e) => _mapBigEventTask(e))
          .toList();

      final joinedSpotTasks = joinedSpots
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map((e) => _mapSpotTask(e, taskType: "spot_joined"))
          .toList();

      final createdSpotTasks = createdSpots
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map((e) => _mapSpotTask(e, taskType: "spot_created"))
          .toList();

      if (!mounted) return;
      setState(() {
        _bigEvents = bigEvents;
        _joinedSpots = joinedSpotTasks;
        _createdSpots = createdSpotTasks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Map<String, dynamic> _mapBigEventTask(Map<String, dynamic> e) {
    final eventId = int.tryParse((e["id"] ?? "").toString()) ?? 0;
    final bookingId =
        int.tryParse((e["booking_id"] ?? e["bookingId"] ?? "").toString()) ?? 0;
    final title = (e["title"] ?? "-").toString();
    final startAt = (e["start_at"] ?? e["date"] ?? "-").toString();
    final location =
        (e["meeting_point"] ?? e["location"] ?? e["city"] ?? "-").toString();
    final pendingKey = bookingId > 0
        ? "${eventId}_$bookingId"
        : "big_event_joined|$eventId|$title|$startAt|$location";
    return {
      ...e,
      "eventId": eventId,
      "bookingId": bookingId,
      "pendingKey": pendingKey,
      "taskType": "big_event_joined",
      "title": title,
      "meeting_point": (e["meeting_point"] ?? "-").toString(),
      "location": (e["meeting_point"] ?? e["city"] ?? "-").toString(),
      "date": startAt,
      "distance": (e["total_distance"] ?? "0").toString(),
      "total_distance": (e["total_distance"] ?? "0").toString(),
      "completed_at": (e["completed_at"] ?? "").toString(),
      "status": ((e["completed_at"] ?? "").toString().trim().isNotEmpty)
          ? "COMPLETED"
          : PaymentBookingStatus.isPaymentSuccessful(e["payment_status"])
              ? "PAID"
              : PaymentBookingStatus.isBookingConfirmed(e["booking_status"])
                  ? "JOINED"
                  : "IN PROGRESS",
    };
  }

  Map<String, dynamic> _mapSpotTask(Map<String, dynamic> s,
      {required String taskType}) {
    final kmPerRound = (s["km_per_round"] ?? "").toString();
    final round = (s["round_count"] ?? "").toString();
    final directTotal =
        double.tryParse((s["total_distance"] ?? "").toString().trim());
    final totalDistance = directTotal != null
        ? (directTotal == directTotal.roundToDouble()
            ? directTotal.toStringAsFixed(0)
            : directTotal.toStringAsFixed(2))
        : (double.tryParse(kmPerRound) != null &&
                double.tryParse(round) != null)
            ? (double.parse(kmPerRound) * double.parse(round)).toString()
            : "0";
    final title = (s["title"] ?? "-").toString();
    final date = (s["event_date"] ?? "-").toString();
    final time = (s["event_time"] ?? "").toString();
    final location = (s["location"] ?? "-").toString();
    final pendingKey = "$taskType|$title|$date|$time|$location";
    return {
      ...s,
      "pendingKey": pendingKey,
      "taskType": taskType,
      "title": title,
      "location": location,
      "locationLink": (s["location_link"] ?? "").toString(),
      "location_lat": s["location_lat"],
      "location_lng": s["location_lng"],
      "locationLat": s["location_lat"],
      "locationLng": s["location_lng"],
      "date": "$date $time".trim(),
      "distance": "$totalDistance KM",
      "kmPerRound": kmPerRound,
      "round": round,
      "total_distance": totalDistance,
      "description": (s["description"] ?? "-").toString(),
      "completed_at": taskType == "spot_created"
          ? (s["owner_completed_at"] ?? "").toString()
          : (s["completed_at"] ?? "").toString(),
      "owner_completed_at": (s["owner_completed_at"] ?? "").toString(),
      "status": ((taskType == "spot_created"
                      ? s["owner_completed_at"]
                      : s["completed_at"]) ??
                  "")
              .toString()
              .trim()
              .isNotEmpty
          ? "COMPLETED"
          : "IN PROGRESS",
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: SafeArea(
        child: Column(
          children: [
            AppNavBar(
              title: "My Event",
              showBack: true,
              onBack: () => Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.userHome,
                (route) => false,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text("Load failed\n$_error",
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: _loadAll,
                                  child: const Text("Retry"),
                                ),
                              ],
                            ),
                          ),
                        )
                      : (_bigEvents.isEmpty &&
                              _joinedSpots.isEmpty &&
                              _createdSpots.isEmpty)
                          ? const Center(child: Text("No events in progress"))
                          : RefreshIndicator(
                              onRefresh: _loadAll,
                              child: ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                children: [
                                  _Section(
                                    title: "Big Event Joined",
                                    items: _bigEvents
                                        .where((e) =>
                                            (e["status"] ?? "")
                                                .toString()
                                                .toUpperCase() !=
                                            "COMPLETED")
                                        .toList(),
                                    color: const Color(0xFFE8F7F4),
                                  ),
                                  const SizedBox(height: 12),
                                  _Section(
                                    title: "Spot Joined",
                                    items: _joinedSpots
                                        .where((e) =>
                                            (e["status"] ?? "")
                                                .toString()
                                                .toUpperCase() !=
                                            "COMPLETED")
                                        .toList(),
                                    color: const Color(0xFFEAF2FF),
                                  ),
                                  const SizedBox(height: 12),
                                  _Section(
                                    title: "Spot Created",
                                    items: _createdSpots
                                        .where((e) =>
                                            (e["status"] ?? "")
                                                .toString()
                                                .toUpperCase() !=
                                            "COMPLETED")
                                        .toList(),
                                    color: const Color(0xFFFFF4E8),
                                  ),
                                ],
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyEventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final Color color;

  const _MyEventCard({required this.event, required this.color});

  String _distanceWithKm(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '-') return '-';
    return value.toUpperCase().contains('KM') ? value : '$value KM';
  }

  @override
  Widget build(BuildContext context) {
    final title = (event["title"] ?? "-").toString();
    final location =
        (event["meeting_point"] ?? event["location"] ?? "-").toString();
    final distance = _distanceWithKm(
      (event["total_distance"] ?? event["distance"] ?? "-").toString(),
    );
    final status = (event["status"] ?? "IN PROGRESS").toString().toUpperCase();
    final isPaid = status == "PAID";

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => Navigator.pushNamed(
        context,
        AppRoutes.userMyEventDetail,
        arguments: {"item": event},
      ),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE6EAF2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isPaid
                        ? const Color(0xFFE9FFF8)
                        : const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: isPaid
                          ? const Color(0xFF00C9A7)
                          : const Color(0xFF2E6BE6),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text("Location: $location",
                maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text("Distance: $distance"),
            const SizedBox(height: 8),
            const Text(
              "Tap to view details",
              style:
                  TextStyle(fontWeight: FontWeight.w600, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final Color color;

  const _Section({
    required this.title,
    required this.items,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Text("No tasks", style: TextStyle(color: Colors.black54)),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MyEventCard(event: item, color: color),
              )),
        ],
      ),
    );
  }
}
