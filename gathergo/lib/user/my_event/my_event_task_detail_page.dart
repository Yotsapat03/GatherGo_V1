import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import '../../app_routes.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/spot_map_launcher.dart';
import '../data/mock_store.dart';
import '../services/activity_completion_service.dart';
import '../utils/activity_expiry.dart';

class MyEventTaskDetailPage extends StatefulWidget {
  const MyEventTaskDetailPage({super.key});

  @override
  State<MyEventTaskDetailPage> createState() => _MyEventTaskDetailPageState();
}

class _MyEventTaskDetailPageState extends State<MyEventTaskDetailPage> {
  bool _busy = false;

  static const List<Map<String, String>> _leaveReasons = [
    {
      "reason_code": "CHANGE_MIND_OTHER_ACTIVITY",
      "reason_text": "I changed my mind to join another activity",
    },
    {
      "reason_code": "NOT_AVAILABLE",
      "reason_text": "I am not available",
    },
    {
      "reason_code": "CREATOR_UNDESIRABLE_BEHAVIOR",
      "reason_text": "The spot creator has undesirable behavior",
    },
    {
      "reason_code": "PARTICIPANT_UNDESIRABLE_BEHAVIOR",
      "reason_text": "Other participants have undesirable behavior",
    },
    {
      "reason_code": "DONT_TRUST_ACTIVITY",
      "reason_text": "I do not trust this activity",
    },
    {
      "reason_code": "UNSAFE_LOCATION",
      "reason_text": "The location feels unsafe / secluded",
    },
  ];

  int? _spotId(Map<String, dynamic> item) {
    return int.tryParse(
      (item["backendSpotId"] ?? item["eventId"] ?? item["id"] ?? "").toString(),
    );
  }

  Future<void> _leaveSpot(Map<String, dynamic> item) async {
    final userId = await SessionService.getCurrentUserId();
    final spotId = _spotId(item);
    if (userId == null || userId <= 0 || spotId == null || spotId <= 0) {
      _showSnack("Cannot leave this spot.");
      return;
    }
    if (!mounted) return;

    final reason = await _showLeaveReasonDialog();
    if (reason == null) return;

    setState(() => _busy = true);
    try {
      final uri =
          Uri.parse("${ConfigService.getBaseUrl()}/api/spots/$spotId/leave");
      final res = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "x-user-id": userId.toString(),
        },
        body: jsonEncode({
          "user_id": userId,
          "reason_code": reason["reason_code"],
        }),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception("HTTP ${res.statusCode}: ${res.body}");
      }

      MockStore.unjoinSpot(item);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.userMyEvent,
        (route) => false,
      );
    } catch (e) {
      _showSnack("Leave failed: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, String>?> _showLeaveReasonDialog() {
    String? selectedReasonCode;

    return showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Why do you want to leave this Spot?"),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _leaveReasons.map((reason) {
                  final code = reason["reason_code"]!;
                  final text = reason["reason_text"]!;
                  return RadioListTile<String>(
                    value: code,
                    groupValue: selectedReasonCode,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(text),
                    onChanged: (value) {
                      setDialogState(() => selectedReasonCode = value);
                    },
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: selectedReasonCode == null
                  ? null
                  : () {
                      final selected = _leaveReasons.firstWhere(
                        (reason) => reason["reason_code"] == selectedReasonCode,
                      );
                      Navigator.pop(dialogContext, selected);
                    },
              child: const Text("Confirm Leave"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSpot(Map<String, dynamic> item) async {
    final userId = await SessionService.getCurrentUserId();
    final spotId = _spotId(item);
    if (userId == null || userId <= 0 || spotId == null || spotId <= 0) {
      _showSnack("Cannot delete this spot.");
      return;
    }
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text("Delete Spot?"),
        content: const Text("This will delete the spot for everyone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final uri = Uri.parse(
          "${ConfigService.getBaseUrl()}/api/spots/$spotId?user_id=$userId");
      final res = await http.delete(
        uri,
        headers: {
          "Accept": "application/json",
          "x-user-id": userId.toString(),
        },
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception("HTTP ${res.statusCode}: ${res.body}");
      }

      MockStore.removeSpot(item);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.userMyEvent,
        (route) => false,
      );
    } catch (e) {
      _showSnack("Delete failed: $e");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openSpotMap(Map<String, dynamic> item) async {
    final ok = await SpotMapLauncher.open(
      latitude: item["locationLat"] ?? item["location_lat"],
      longitude: item["locationLng"] ?? item["location_lng"],
      locationText: item["meeting_point"] ?? item["location"],
    );
    if (!ok) {
      _showSnack("Location is not available.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = (ModalRoute.of(context)?.settings.arguments is Map)
        ? Map<String, dynamic>.from(
            ModalRoute.of(context)!.settings.arguments as Map)
        : <String, dynamic>{};
    final item = (args["item"] is Map)
        ? Map<String, dynamic>.from(args["item"] as Map)
        : <String, dynamic>{};

    if (item.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Task Detail")),
        body: const Center(child: Text("No task data")),
      );
    }

    final taskType = (item["taskType"] ?? "").toString();
    final isSpotCreated = taskType == "spot_created";
    final isSpotJoined = taskType == "spot_joined";
    final isSpotTask = isSpotCreated || isSpotJoined;
    final creatorUserId = int.tryParse(
        (item["creatorUserId"] ?? item["created_by_user_id"] ?? "").toString());
    final title = (item["title"] ?? "-").toString();
    final location =
        (item["meeting_point"] ?? item["location"] ?? "-").toString();
    final date = (item["date"] ?? item["start_at"] ?? "-").toString();
    final distance =
        (item["total_distance"] ?? item["distance"] ?? "-").toString();
    final description = (item["description"] ?? "-").toString();
    final isExpired = ActivityExpiry.isExpiredAfterGrace(item);

    String typeLabel(String t) {
      switch (t) {
        case "spot_created":
          return "SPOT CREATED";
        case "spot_joined":
          return "SPOT JOINED";
        default:
          return "BIG EVENT JOINED";
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text("Task Detail"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                typeLabel(taskType),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 12),
            _line("Title", title),
            _line("Location", location),
            _line("Date", date),
            _line("Distance", distance),
            _line("Description", description),
            const Spacer(),
            if (isSpotTask)
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: isExpired
                      ? null
                      : () => Navigator.pushNamed(
                            context,
                            AppRoutes.userSpotChatGroup,
                            arguments: {"spot": item},
                          ),
                  child: const Text("Chat Group"),
                ),
              ),
            if (isSpotTask) const SizedBox(height: 10),
            if (isSpotTask)
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _openSpotMap(item),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text("Open in Google Maps"),
                ),
              ),
            if (isSpotTask) const SizedBox(height: 10),
            if (isSpotTask)
              FutureBuilder<int?>(
                future: SessionService.getCurrentUserId(),
                builder: (context, snapshot) {
                  final currentUserId = snapshot.data;
                  final canDelete = isSpotCreated &&
                      currentUserId != null &&
                      currentUserId > 0 &&
                      creatorUserId != null &&
                      creatorUserId == currentUserId;
                  final canLeave = isSpotJoined;
                  if (!canDelete && !canLeave) {
                    return const SizedBox.shrink();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                if (canDelete) {
                                  await _deleteSpot(item);
                                } else if (canLeave) {
                                  await _leaveSpot(item);
                                }
                              },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: canDelete
                              ? const Color(0xFFD92D20)
                              : Colors.black,
                          side: BorderSide(
                            color: canDelete
                                ? const Color(0xFFD92D20)
                                : const Color(0xFFDD6B20),
                          ),
                        ),
                        child: Text(
                          canDelete ? "Delete Spot" : "Leave Spot",
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  );
                },
              ),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C9A7),
                ),
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          bool savedToDb = true;
                          if (taskType == "big_event_joined") {
                            savedToDb = await ActivityCompletionService
                                .completeBigEvent(
                              item,
                            );
                          } else if (taskType == "spot_joined" ||
                              taskType == "spot_created") {
                            savedToDb =
                                await ActivityCompletionService.completeSpot(
                                    item);
                          }
                          if (!savedToDb) {
                            _showSnack("Completion was not saved.");
                            if (mounted) setState(() => _busy = false);
                            return;
                          }
                        } catch (e) {
                          _showSnack("Completion save failed: $e");
                          if (mounted) setState(() => _busy = false);
                          return;
                        }
                        if (!mounted) return;
                        setState(() => _busy = false);
                        if (taskType == "big_event_joined") {
                          Navigator.pushNamedAndRemoveUntil(
                            context,
                            AppRoutes.userJoinedEvent,
                            (route) => false,
                          );
                          return;
                        }
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          AppRoutes.userMyEvent,
                          (route) => false,
                        );
                      },
                child: const Text(
                  "Complete",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE6EAF2)),
            ),
            child: Text(value),
          ),
        ],
      ),
    );
  }
}
