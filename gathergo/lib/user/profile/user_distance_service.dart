import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';

class DistanceUserSummary {
  final int userId;
  final String displayName;
  final String role;
  final double? totalKm;
  final int joinedCount;
  final int completedCount;
  final int unrecordedCount;
  final int postCount;
  final String profileImageUrl;
  final String district;
  final String province;
  final String status;

  const DistanceUserSummary({
    required this.userId,
    required this.displayName,
    required this.role,
    required this.totalKm,
    required this.joinedCount,
    required this.completedCount,
    required this.unrecordedCount,
    required this.postCount,
    required this.profileImageUrl,
    required this.district,
    required this.province,
    required this.status,
  });

  factory DistanceUserSummary.fromJson(Map<String, dynamic> json) {
    double? readDouble(List<String> keys) {
      for (final key in keys) {
        final raw = json[key];
        if (raw == null) continue;
        final parsed = double.tryParse(raw.toString().trim());
        if (parsed != null) return parsed;
      }
      return null;
    }

    int? readInt(List<String> keys) {
      for (final key in keys) {
        final raw = json[key];
        if (raw == null) continue;
        final parsed = int.tryParse(raw.toString().trim());
        if (parsed != null) return parsed;
      }
      return null;
    }

    final firstName =
        (json["first_name"] ?? json["firstName"] ?? "").toString();
    final lastName = (json["last_name"] ?? json["lastName"] ?? "").toString();
    final fullName = [firstName.trim(), lastName.trim()]
        .where((value) => value.isNotEmpty)
        .join(" ")
        .trim();
    final displayName = (json["display_name"] ?? "").toString().trim();
    final fallbackName = (json["name"] ?? "").toString().trim();
    final totalKm = readDouble(const <String>[
      "total_km",
      "totalKm",
      "completed_distance_km",
      "completedDistanceKm",
      "owner_completed_distance_km",
      "ownerCompletedDistanceKm",
      "distance_km",
      "distanceKm",
      "total_distance",
      "totalDistance",
    ]);
    final joinedCount = readInt(const <String>[
          "joined_count",
          "joinedCount",
        ]) ??
        0;
    final postCount = readInt(const <String>[
          "post_count",
          "postCount",
        ]) ??
        0;
    final completedCount = readInt(const <String>[
          "completed_count",
          "completedCount",
          "completed_events",
          "completedEvents",
          "completed_activities",
          "completedActivities",
          "activity_count",
          "activityCount",
          "total_completed",
          "totalCompleted",
        ]) ??
        (joinedCount + postCount);
    final unrecordedCount = readInt(const <String>[
          "unrecorded_count",
          "unrecordedCount",
        ]) ??
        0;

    return DistanceUserSummary(
      userId:
          int.tryParse((json["user_id"] ?? json["id"] ?? "").toString()) ?? 0,
      displayName: displayName.isNotEmpty
          ? displayName
          : (fullName.isNotEmpty
              ? fullName
              : (fallbackName.isNotEmpty ? fallbackName : "User")),
      role: (json["role"] ?? "").toString(),
      totalKm: totalKm,
      joinedCount: joinedCount,
      completedCount: completedCount,
      unrecordedCount: unrecordedCount,
      postCount: postCount,
      profileImageUrl:
          (json["profile_image_url"] ?? json["profileImageUrl"] ?? "")
              .toString(),
      district: (json["district"] ?? "").toString(),
      province: (json["province"] ?? "").toString(),
      status: (json["status"] ?? "").toString(),
    );
  }
}

class UserDistanceService {
  const UserDistanceService._();

  static DistanceUserSummary _mergeSummaries(
    DistanceUserSummary primary,
    DistanceUserSummary fallback,
  ) {
    // For Spot member comparisons, prefer progress carried by the member row.
    // Global user summary values can describe the person, but should not
    // overwrite room-specific distance/completion numbers.
    final fallbackShowsNoRoomProgress = fallback.totalKm == null &&
        fallback.completedCount <= 0 &&
        fallback.joinedCount <= 0 &&
        fallback.postCount <= 0;
    final double? mergedTotalKm = fallbackShowsNoRoomProgress
        ? 0.0
        : (fallback.totalKm ?? primary.totalKm);
    final mergedJoinedCount =
        fallback.joinedCount > 0 ? fallback.joinedCount : primary.joinedCount;
    final mergedCompletedCount = fallback.completedCount > 0
        ? fallback.completedCount
        : primary.completedCount;
    final mergedUnrecordedCount = fallback.unrecordedCount > 0
        ? fallback.unrecordedCount
        : primary.unrecordedCount;
    final mergedPostCount =
        fallback.postCount > 0 ? fallback.postCount : primary.postCount;

    return DistanceUserSummary(
      userId: primary.userId > 0 ? primary.userId : fallback.userId,
      displayName: primary.displayName.trim().isNotEmpty
          ? primary.displayName
          : fallback.displayName,
      role: primary.role.trim().isNotEmpty ? primary.role : fallback.role,
      totalKm: mergedTotalKm,
      joinedCount: mergedJoinedCount,
      completedCount: mergedCompletedCount,
      unrecordedCount: mergedUnrecordedCount,
      postCount: mergedPostCount,
      profileImageUrl: primary.profileImageUrl.trim().isNotEmpty
          ? primary.profileImageUrl
          : fallback.profileImageUrl,
      district: primary.district.trim().isNotEmpty
          ? primary.district
          : fallback.district,
      province: primary.province.trim().isNotEmpty
          ? primary.province
          : fallback.province,
      status:
          primary.status.trim().isNotEmpty ? primary.status : fallback.status,
    );
  }

  static Future<Map<String, String>> _headers() async {
    final userId = await SessionService.getCurrentUserId();
    return <String, String>{
      "Accept": "application/json",
      if (userId != null) "x-user-id": userId.toString(),
    };
  }

  static Map<String, dynamic> _readUserPayload(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw Exception("Invalid response format");
    }
    if (decoded["user"] is Map) {
      return Map<String, dynamic>.from(decoded["user"] as Map);
    }
    return decoded;
  }

  static Future<Map<String, dynamic>> _fetchUserPayloadByPath(
      String path) async {
    final uri = Uri.parse('${ConfigService.getBaseUrl()}$path');
    final res = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception("HTTP ${res.statusCode}: ${res.body}");
    }
    final decoded = jsonDecode(res.body);
    return _readUserPayload(decoded);
  }

  static Future<DistanceUserSummary?> fetchCurrentUserSummary() async {
    final userPayload = await _fetchUserPayloadByPath('/api/users/me');
    return DistanceUserSummary.fromJson(userPayload);
  }

  static Future<DistanceUserSummary?> fetchUserSummaryById(int userId) async {
    final userPayload = await _fetchUserPayloadByPath('/api/users/$userId');
    return DistanceUserSummary.fromJson(userPayload);
  }

  static Future<List<DistanceUserSummary>> fetchSpotMembers(int spotId) async {
    final uri =
        Uri.parse("${ConfigService.getBaseUrl()}/api/spots/$spotId/members");
    final res = await http
        .get(uri, headers: await _headers())
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      throw Exception("HTTP ${res.statusCode}: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return const <DistanceUserSummary>[];
    final rows = decoded["members"];
    if (rows is! List) return const <DistanceUserSummary>[];
    final currentUserId = await SessionService.getCurrentUserId();
    final rawMembers = rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    final hydratedMembers = await Future.wait(
      rawMembers.map((row) async {
        final fallback = DistanceUserSummary.fromJson(row);
        if (fallback.userId <= 0) {
          return fallback;
        }

        try {
          final fetched = fallback.userId == currentUserId
              ? await fetchCurrentUserSummary()
              : await fetchUserSummaryById(fallback.userId);
          if (fetched == null) return fallback;

          return _mergeSummaries(fetched, fallback);
        } catch (_) {
          return fallback;
        }
      }),
    );

    return hydratedMembers;
  }
}
