import '../../user/localization/user_locale_controller.dart';

class AdminLocaleController {
  static const fallbackLanguageCode = UserLocaleController.fallbackLanguageCode;
  static const supportedLanguageCodes =
      UserLocaleController.supportedLanguageCodes;
  static final languageCode = UserLocaleController.languageCode;

  static Future<void> init() => UserLocaleController.init();

  static Future<void> setLanguage(String code) =>
      UserLocaleController.setLanguage(code);
}
