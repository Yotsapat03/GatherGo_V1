import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserLocaleController {
  static const String _prefsKey = 'user_language_code';
  static const String fallbackLanguageCode = 'en';
  static const List<String> supportedLanguageCodes = <String>['th', 'en', 'zh'];

  static final ValueNotifier<String> languageCode =
      ValueNotifier<String>(fallbackLanguageCode);

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = (prefs.getString(_prefsKey) ?? fallbackLanguageCode).trim();
    languageCode.value =
        supportedLanguageCodes.contains(stored) ? stored : fallbackLanguageCode;
  }

  static Future<void> setLanguage(String code) async {
    final next =
        supportedLanguageCodes.contains(code) ? code : fallbackLanguageCode;
    if (languageCode.value == next) return;

    languageCode.value = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, next);
  }
}
