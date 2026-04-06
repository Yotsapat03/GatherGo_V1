import 'package:flutter/material.dart';

import '../../user/localization/user_locale_controller.dart';

class WelcomeI18n {
  static const Map<String, Map<String, String>> _values =
      <String, Map<String, String>>{
    'th': <String, String>{
      'find_your_pace': 'ค้นหาจังหวะของคุณ รวมทีมของคุณ',
      'sign_up': 'สมัครสมาชิก',
      'log_in': 'เข้าสู่ระบบ',
      'select_role': 'เลือกบทบาท',
      'choose_where_to_enter': 'เลือกว่า จะเข้าส่วนไหน',
      'who_are_you': 'คุณคือใคร?',
      'user': 'ผู้ใช้',
      'admin': 'แอดมิน',
      'back': 'ย้อนกลับ',
      'email': 'อีเมล:',
      'password': 'รหัสผ่าน:',
      'confirm': 'ยืนยัน',
      'create_new_account': 'สร้างบัญชีใหม่',
      'enter_email': 'อีเมล',
      'enter_password': 'รหัสผ่าน',
      'please_enter_both': 'กรุณากรอกอีเมลและรหัสผ่าน',
      'incorrect_email_password': 'อีเมลหรือรหัสผ่านไม่ถูกต้อง กรุณาลองใหม่',
      'inactive_account': 'บัญชีนี้ยังไม่เปิดใช้งาน',
      'suspended_account': 'บัญชีนี้ถูกระงับชั่วคราว โปรดติดต่อแอดมิน',
      'deleted_account':
          'บัญชีนี้ถูกลบโดยแอดมินแล้วเนื่องจากทำผิดกฎ โปรดสมัครใหม่',
      'login_response_missing_user_id': 'ไม่พบ User ID ในผลลัพธ์การเข้าสู่ระบบ',
      'login_response_missing_admin_id':
          'ไม่พบ Admin ID ในผลลัพธ์การเข้าสู่ระบบ',
      'user_login_api_not_found': 'ไม่พบ API เข้าสู่ระบบของผู้ใช้บนเซิร์ฟเวอร์',
      'unable_connect': 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้ กรุณาลองใหม่',
      'language': 'ภาษา',
      'thai': 'ไทย',
      'english': 'English',
      'chinese': '中文',
    },
    'en': <String, String>{
      'find_your_pace': 'Find Your Pace, Gather\nYour Crew.',
      'sign_up': 'Sign up',
      'log_in': 'Log in',
      'select_role': 'Select Role',
      'choose_where_to_enter': 'Choose where to enter',
      'who_are_you': 'Who are you?',
      'user': 'User',
      'admin': 'Admin',
      'back': 'Back',
      'email': 'Email:',
      'password': 'Password:',
      'confirm': 'Confirm',
      'create_new_account': 'Create new account',
      'enter_email': 'Email',
      'enter_password': 'Password',
      'please_enter_both': 'Please enter both email and password.',
      'incorrect_email_password':
          'Incorrect email or password. Please try again.',
      'inactive_account': 'This account is not active.',
      'suspended_account':
          'This account is temporarily suspended. Please contact the admin.',
      'deleted_account':
          'This account was deleted by the admin for breaking the rules. Please sign up again.',
      'login_response_missing_user_id': 'Login response missing user id.',
      'login_response_missing_admin_id': 'Login response missing admin id.',
      'user_login_api_not_found': 'User login API not found on server.',
      'unable_connect': 'Unable to connect to the server. Please try again.',
      'language': 'Language',
      'thai': 'ไทย',
      'english': 'English',
      'chinese': '中文',
    },
    'zh': <String, String>{
      'find_your_pace': '找到你的节奏，集结你的跑友',
      'sign_up': '注册',
      'log_in': '登录',
      'select_role': '选择角色',
      'choose_where_to_enter': '选择进入的身份',
      'who_are_you': '你是谁？',
      'user': '用户',
      'admin': '管理员',
      'back': '返回',
      'email': '邮箱：',
      'password': '密码：',
      'confirm': '确认',
      'create_new_account': '创建新账号',
      'enter_email': '邮箱',
      'enter_password': '密码',
      'please_enter_both': '请输入邮箱和密码。',
      'incorrect_email_password': '邮箱或密码不正确，请重试。',
      'inactive_account': '此账号尚未启用。',
      'suspended_account': '此账号已被暂时停用，请联系管理员。',
      'deleted_account': '此账号因违反规则已被管理员删除，请重新注册。',
      'login_response_missing_user_id': '登录结果中缺少用户 ID。',
      'login_response_missing_admin_id': '登录结果中缺少管理员 ID。',
      'user_login_api_not_found': '服务器上未找到用户登录 API。',
      'unable_connect': '无法连接到服务器，请稍后再试。',
      'language': '语言',
      'thai': 'ไทย',
      'english': 'English',
      'chinese': '中文',
    },
  };

  static String text(String key) {
    final code = UserLocaleController.languageCode.value;
    return _values[code]?[key] ??
        _values[UserLocaleController.fallbackLanguageCode]?[key] ??
        key;
  }

  static String languageLabel(String code) {
    switch (code) {
      case 'th':
        return 'ไทย';
      case 'zh':
        return '中文';
      default:
        return 'English';
    }
  }
}

class WelcomeTranslateButton extends StatelessWidget {
  const WelcomeTranslateButton({super.key, this.color = Colors.white});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: UserLocaleController.languageCode,
      builder: (context, currentCode, _) {
        return PopupMenuButton<String>(
          tooltip: WelcomeI18n.text('language'),
          icon: Icon(Icons.translate_rounded, color: color, size: 28),
          color: Colors.white.withOpacity(0.96),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          onSelected: UserLocaleController.setLanguage,
          itemBuilder: (context) {
            return UserLocaleController.supportedLanguageCodes.map((code) {
              final selected = code == currentCode;
              return PopupMenuItem<String>(
                value: code,
                child: Row(
                  children: [
                    Expanded(child: Text(WelcomeI18n.languageLabel(code))),
                    if (selected) const Icon(Icons.check_rounded, size: 18),
                  ],
                ),
              );
            }).toList();
          },
        );
      },
    );
  }
}
