import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import 'user_profile_model.dart';

class UserProfileService {
  const UserProfileService._();

  static Future<UserProfile> fetchCurrentUserProfile() async {
    final userId = await SessionService.getCurrentUserId();
    if (userId == null || userId <= 0) {
      throw Exception("No active user session.");
    }

    final headers = <String, String>{
      "Accept": "application/json",
      "x-user-id": userId.toString(),
    };

    final meUri = Uri.parse("${ConfigService.getBaseUrl()}/api/users/me");
    var res = await http
        .get(meUri, headers: headers)
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      final byIdUri =
          Uri.parse("${ConfigService.getBaseUrl()}/api/users/$userId");
      res = await http
          .get(byIdUri, headers: headers)
          .timeout(const Duration(seconds: 20));
    }

    if (res.statusCode != 200) {
      throw Exception("HTTP ${res.statusCode}: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception("Invalid response format");
    }

    final userJson = decoded["user"] is Map
        ? Map<String, dynamic>.from(decoded["user"] as Map)
        : decoded;

    return UserProfile.fromJson(userJson);
  }

  static Future<UserProfile> fetchUserProfileById(
    int targetUserId, {
    Map<String, dynamic>? fallbackUserJson,
  }) async {
    if (targetUserId <= 0) {
      throw Exception("Invalid user id.");
    }

    final currentUserId = await SessionService.getCurrentUserId();
    final headers = <String, String>{
      "Accept": "application/json",
      if (currentUserId != null) "x-user-id": currentUserId.toString(),
    };

    final uri =
        Uri.parse("${ConfigService.getBaseUrl()}/api/users/$targetUserId");

    try {
      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        throw Exception("HTTP ${res.statusCode}: ${res.body}");
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception("Invalid response format");
      }

      final userJson = decoded["user"] is Map
          ? Map<String, dynamic>.from(decoded["user"] as Map)
          : Map<String, dynamic>.from(decoded);

      final mergedJson = <String, dynamic>{
        if (fallbackUserJson != null) ...fallbackUserJson,
        ...userJson,
      };

      return UserProfile.fromJson(mergedJson);
    } catch (_) {
      if (fallbackUserJson != null) {
        return UserProfile.fromJson(fallbackUserJson);
      }
      rethrow;
    }
  }
}
