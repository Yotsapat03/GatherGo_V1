import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdminSessionService {
  static const _keyAdminId = 'session_admin_id';
  static const _keyAdminEmail = 'session_admin_email';

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAdminId);
    await prefs.remove(_keyAdminEmail);
  }

  static Future<void> setSession({
    required int adminId,
    required String email,
  }) async {
    if (adminId <= 0) {
      throw ArgumentError('adminId must be > 0');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyAdminId, adminId);
    await prefs.setString(_keyAdminEmail, email.trim().toLowerCase());
    debugPrint('[GatherGo] AdminSessionService.setSession adminId=$adminId');
  }

  static Future<int?> getCurrentAdminId() async {
    final prefs = await SharedPreferences.getInstance();
    final adminId = prefs.getInt(_keyAdminId);
    debugPrint('[GatherGo] AdminSessionService.getCurrentAdminId adminId=$adminId');
    if (adminId == null || adminId <= 0) return null;
    return adminId;
  }

  static Future<String?> getCurrentAdminEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_keyAdminEmail)?.trim();
    debugPrint('[GatherGo] AdminSessionService.getCurrentAdminEmail email=$email');
    if (email == null || email.isEmpty) return null;
    return email;
  }

  static Future<int?> getAdminId() => getCurrentAdminId();
}
