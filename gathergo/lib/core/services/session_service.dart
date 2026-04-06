import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const _keyUserId = 'session_user_id';
  static const _keyEmail = 'session_user_email';
  static int? _cachedUserId;
  static String? _cachedEmail;

  static int? get currentUserIdSync => _cachedUserId;
  static String? get currentUserEmailSync => _cachedEmail;

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyUserId);
    await prefs.remove(_keyEmail);
    _cachedUserId = null;
    _cachedEmail = null;
  }

  static Future<void> setSession({
    required int userId,
    required String email,
  }) async {
    if (userId <= 0) {
      throw ArgumentError('userId must be > 0');
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyUserId, userId);
    await prefs.setString(_keyEmail, email.trim().toLowerCase());
    _cachedUserId = userId;
    _cachedEmail = email.trim().toLowerCase();
  }

  static Future<int?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt(_keyUserId);
    if (userId == null || userId <= 0) {
      _cachedUserId = null;
      return null;
    }
    _cachedUserId = userId;
    return userId;
  }

  static Future<String?> getCurrentUserEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_keyEmail)?.trim();
    if (email == null || email.isEmpty) {
      _cachedEmail = null;
      return null;
    }
    _cachedEmail = email;
    return email;
  }
}
