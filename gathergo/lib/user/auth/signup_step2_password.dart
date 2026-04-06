import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_routes.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../localization/user_locale_controller.dart';

class SignupStep2PasswordPage extends StatefulWidget {
  final Map<String, dynamic> signupData;

  const SignupStep2PasswordPage({super.key, required this.signupData});

  @override
  State<SignupStep2PasswordPage> createState() =>
      _SignupStep2PasswordPageState();
}

class _SignupStep2PasswordPageState extends State<SignupStep2PasswordPage> {
  static const Map<String, Map<String, String>> _texts =
      <String, Map<String, String>>{
    'en': <String, String>{
      'title': 'Create Password',
      'password': 'Password*',
      'password_hint': 'Enter password',
      'confirm_password': 'Confirm Password*',
      'confirm_password_hint': 'Confirm password',
      'create_account': 'Create Account',
      'select_language': 'Select language',
      'password_short': 'Password must be at least 8 characters.',
      'password_mismatch': 'Password and confirm password do not match.',
      'signup_incomplete':
          'Signup data is incomplete. Please go back to Step 1.',
      'missing_user_id': 'Signup response missing user id.',
      'connect_error': 'Unable to connect to server. Please try again.',
    },
    'th': <String, String>{
      'title': 'สร้างรหัสผ่าน',
      'password': 'รหัสผ่าน*',
      'password_hint': 'กรอกรหัสผ่าน',
      'confirm_password': 'ยืนยันรหัสผ่าน*',
      'confirm_password_hint': 'ยืนยันรหัสผ่าน',
      'create_account': 'สร้างบัญชี',
      'select_language': 'เลือกภาษา',
      'password_short': 'รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร',
      'password_mismatch': 'รหัสผ่านและการยืนยันรหัสผ่านไม่ตรงกัน',
      'signup_incomplete': 'ข้อมูลสมัครสมาชิกไม่ครบ กรุณากลับไปกรอก Step 1',
      'missing_user_id': 'ข้อมูลตอบกลับจากระบบไม่มี user id',
      'connect_error': 'ไม่สามารถเชื่อมต่อเซิร์ฟเวอร์ได้ กรุณาลองใหม่อีกครั้ง',
    },
    'zh': <String, String>{
      'title': '创建密码',
      'password': '密码*',
      'password_hint': '请输入密码',
      'confirm_password': '确认密码*',
      'confirm_password_hint': '请再次输入密码',
      'create_account': '创建账号',
      'select_language': '选择语言',
      'password_short': '密码长度至少需要 8 个字符。',
      'password_mismatch': '密码与确认密码不一致。',
      'signup_incomplete': '注册资料不完整，请返回第 1 步重新填写。',
      'missing_user_id': '注册响应中缺少 user id。',
      'connect_error': '无法连接服务器，请稍后再试。',
    },
  };
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _loading = false;
  String? _error;

  String get _baseUrl => ConfigService.getApiBaseUrl();
  String get _languageCode => UserLocaleController.languageCode.value;

  Uri _apiUri(String path) {
    final base = _baseUrl.trim();
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final baseUri = Uri.tryParse(base);
    if (baseUri != null && baseUri.hasScheme && baseUri.host.isNotEmpty) {
      return baseUri.resolve(normalizedPath);
    }
    // Hard fallback to backend default when base URL is invalid.
    return Uri.parse('http://localhost:3000$normalizedPath');
  }

  String _t(String key) {
    final lang = _texts[_languageCode] ?? _texts['en']!;
    return lang[key] ?? _texts['en']![key] ?? key;
  }

  bool _looksLikeCannotPost404(http.Response res) {
    if (res.statusCode != 404) return false;
    final body = res.body.toLowerCase();
    return body.contains("cannot post") && body.contains("/api/auth/signup");
  }

  bool _shouldRetryToBackend(Uri primary, http.Response res, String apiPath) {
    if (!kIsWeb || !kDebugMode) return false;
    if (res.statusCode != 404) return false;

    final body = res.body.toLowerCase();
    final cannotPostPath =
        body.contains("cannot post") && body.contains(apiPath.toLowerCase());
    if (!cannotPostPath) return false;

    final webOrigin = ConfigService.getWebOrigin();
    final isWebOrigin =
        webOrigin != null && ConfigService.isSameHostPort(primary, webOrigin);
    final isLikelyFlutterPort = ConfigService.isLikelyFlutterDevPort(primary);
    return isWebOrigin || isLikelyFlutterPort;
  }

  Future<http.Response> _postSignupMultipart({
    required Uri uri,
    required String name,
    required String birthYear,
    required String gender,
    required String genderI18n,
    required String occupation,
    required String occupationI18n,
    required String email,
    required String phone,
    required String address,
    required String nameI18n,
    required String addressI18n,
    required String addressHouseNo,
    required String addressFloor,
    required String addressBuilding,
    required String addressRoad,
    required String addressSubdistrict,
    required String addressDistrict,
    required String addressProvince,
    required String addressPostalCode,
    required String password,
    required Uint8List profileImageBytes,
    required String profileImageName,
    required Uint8List nationalIdImageBytes,
    required String nationalIdImageName,
  }) async {
    final req = http.MultipartRequest("POST", uri)
      ..fields["name"] = name
      ..fields["birthYear"] = birthYear
      ..fields["gender"] = gender
      ..fields["genderI18n"] = genderI18n
      ..fields["occupation"] = occupation
      ..fields["occupationI18n"] = occupationI18n
      ..fields["email"] = email
      ..fields["phone"] = phone
      ..fields["address"] = address
      ..fields["nameI18n"] = nameI18n
      ..fields["addressI18n"] = addressI18n
      ..fields["addressHouseNo"] = addressHouseNo
      ..fields["addressFloor"] = addressFloor
      ..fields["addressBuilding"] = addressBuilding
      ..fields["addressRoad"] = addressRoad
      ..fields["addressSubdistrict"] = addressSubdistrict
      ..fields["addressDistrict"] = addressDistrict
      ..fields["addressProvince"] = addressProvince
      ..fields["addressPostalCode"] = addressPostalCode
      ..fields["password"] = password
      ..files.add(
        http.MultipartFile.fromBytes(
          "profileImage",
          profileImageBytes,
          filename: profileImageName,
        ),
      )
      ..files.add(
        http.MultipartFile.fromBytes(
          "nationalIdImage",
          nationalIdImageBytes,
          filename: nationalIdImageName,
        ),
      );

    final streamed = await req.send().timeout(const Duration(seconds: 30));
    return http.Response.fromStream(streamed);
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _createAccount() async {
    final password = _password.text;
    final confirm = _confirmPassword.text;

    if (password.length < 8) {
      setState(() => _error = _t('password_short'));
      return;
    }
    if (password != confirm) {
      setState(() => _error = _t('password_mismatch'));
      return;
    }

    final name = (widget.signupData["name"] ?? "").toString().trim();
    final nameI18n = jsonEncode(widget.signupData["nameI18n"] ?? const {});
    final birthYear = (widget.signupData["birthYear"] ?? "").toString().trim();
    final gender = (widget.signupData["gender"] ?? "").toString().trim();
    final genderI18n = jsonEncode(widget.signupData["genderI18n"] ?? const {});
    final occupation =
        (widget.signupData["occupation"] ?? "").toString().trim();
    final occupationI18n =
        jsonEncode(widget.signupData["occupationI18n"] ?? const {});
    final email =
        (widget.signupData["email"] ?? "").toString().trim().toLowerCase();
    final phone = (widget.signupData["phone"] ?? "").toString().trim();
    final address = (widget.signupData["address"] ?? "").toString().trim();
    final addressI18n =
        jsonEncode(widget.signupData["addressI18n"] ?? const {});
    final addressHouseNo =
        (widget.signupData["addressHouseNo"] ?? "").toString().trim();
    final addressFloor =
        (widget.signupData["addressFloor"] ?? "").toString().trim();
    final addressBuilding =
        (widget.signupData["addressBuilding"] ?? "").toString().trim();
    final addressRoad =
        (widget.signupData["addressRoad"] ?? "").toString().trim();
    final addressSubdistrict =
        (widget.signupData["addressSubdistrict"] ?? "").toString().trim();
    final addressDistrict =
        (widget.signupData["addressDistrict"] ?? "").toString().trim();
    final addressProvince =
        (widget.signupData["addressProvince"] ?? "").toString().trim();
    final addressPostalCode =
        (widget.signupData["addressPostalCode"] ?? "").toString().trim();

    final Uint8List? profileImageBytes =
        widget.signupData["profileImageBytes"] as Uint8List?;
    final Uint8List? nationalIdImageBytes =
        widget.signupData["nationalIdImageBytes"] as Uint8List?;
    final profileImageName =
        (widget.signupData["profileImageName"] ?? "profile.jpg").toString();
    final nationalIdImageName =
        (widget.signupData["nationalIdImageName"] ?? "national_id.jpg")
            .toString();

    if (name.isEmpty ||
        birthYear.isEmpty ||
        gender.isEmpty ||
        occupation.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        address.isEmpty ||
        addressHouseNo.isEmpty ||
        addressFloor.isEmpty ||
        addressBuilding.isEmpty ||
        addressRoad.isEmpty ||
        addressSubdistrict.isEmpty ||
        addressDistrict.isEmpty ||
        addressProvince.isEmpty ||
        addressPostalCode.isEmpty ||
        profileImageBytes == null ||
        nationalIdImageBytes == null) {
      setState(() => _error = _t('signup_incomplete'));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final primary = _apiUri("/api/auth/signup");
      ConfigService.log("Signup request URL: $primary");
      var res = await _postSignupMultipart(
        uri: primary,
        name: name,
        nameI18n: nameI18n,
        birthYear: birthYear,
        gender: gender,
        genderI18n: genderI18n,
        occupation: occupation,
        occupationI18n: occupationI18n,
        email: email,
        phone: phone,
        address: address,
        addressI18n: addressI18n,
        addressHouseNo: addressHouseNo,
        addressFloor: addressFloor,
        addressBuilding: addressBuilding,
        addressRoad: addressRoad,
        addressSubdistrict: addressSubdistrict,
        addressDistrict: addressDistrict,
        addressProvince: addressProvince,
        addressPostalCode: addressPostalCode,
        password: password,
        profileImageBytes: profileImageBytes,
        profileImageName: profileImageName,
        nationalIdImageBytes: nationalIdImageBytes,
        nationalIdImageName: nationalIdImageName,
      );

      // If request accidentally hits Flutter web origin (:1482), retry backend default (:3000).
      if (_shouldRetryToBackend(primary, res, "/api/auth/signup")) {
        final fallback = ConfigService.getDevFallbackUri("/api/auth/signup");
        if (fallback != null && fallback != primary) {
          ConfigService.log(
              "Signup wrong-target detected (HTTP ${res.statusCode}). Retrying URL: $fallback");
          res = await _postSignupMultipart(
            uri: fallback,
            name: name,
            nameI18n: nameI18n,
            birthYear: birthYear,
            gender: gender,
            genderI18n: genderI18n,
            occupation: occupation,
            occupationI18n: occupationI18n,
            email: email,
            phone: phone,
            address: address,
            addressI18n: addressI18n,
            addressHouseNo: addressHouseNo,
            addressFloor: addressFloor,
            addressBuilding: addressBuilding,
            addressRoad: addressRoad,
            addressSubdistrict: addressSubdistrict,
            addressDistrict: addressDistrict,
            addressProvince: addressProvince,
            addressPostalCode: addressPostalCode,
            password: password,
            profileImageBytes: profileImageBytes,
            profileImageName: profileImageName,
            nationalIdImageBytes: nationalIdImageBytes,
            nationalIdImageName: nationalIdImageName,
          );
        }
      }

      if (res.statusCode == 200 || res.statusCode == 201) {
        final decoded = jsonDecode(res.body);
        final user = (decoded is Map && decoded["user"] is Map)
            ? Map<String, dynamic>.from(decoded["user"] as Map)
            : <String, dynamic>{};
        final userId = int.tryParse((user["id"] ?? "").toString());
        if (userId == null || userId <= 0) {
          setState(() => _error = _t('missing_user_id'));
          return;
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString("last_signup_email", email);
        await SessionService.clearSession();
        await SessionService.setSession(
          userId: userId,
          email: (user["email"] ?? email).toString(),
        );

        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          AppRoutes.userHome,
          (_) => false,
        );
        return;
      }

      String msg = "Signup failed";
      try {
        final data = jsonDecode(res.body);
        if (data is Map && data["message"] is String) {
          msg = data["message"].toString();
        } else if (data is Map && data["error"] is String) {
          msg = data["error"].toString();
        }
      } catch (_) {}
      if (msg == "Signup failed") {
        final body = res.body.trim();
        if (body.isNotEmpty) {
          final shortBody =
              body.length > 180 ? "${body.substring(0, 180)}..." : body;
          msg = "HTTP ${res.statusCode}: $shortBody";
        } else {
          msg = "HTTP ${res.statusCode}";
        }
      }
      setState(() => _error = msg);
    } catch (_) {
      setState(() => _error = _t('connect_error'));
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/welcome.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          Container(color: Colors.black.withOpacity(0.25)),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(w * 0.08, 24, w * 0.08, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        tooltip: _t('select_language'),
                        icon: const Icon(
                          Icons.translate_rounded,
                          color: Colors.white,
                        ),
                        onSelected: UserLocaleController.setLanguage,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'en', child: Text('English')),
                          PopupMenuItem(value: 'zh', child: Text('中文')),
                          PopupMenuItem(value: 'th', child: Text('ไทย')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t('title'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: w * 0.10,
                      fontWeight: FontWeight.w800,
                      shadows: const [
                        Shadow(blurRadius: 12, color: Colors.black54)
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.35)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_t('password'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        _Field(
                            controller: _password,
                            hint: _t('password_hint'),
                            obscure: true),
                        const SizedBox(height: 12),
                        Text(_t('confirm_password'),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        _Field(
                          controller: _confirmPassword,
                          hint: _t('confirm_password_hint'),
                          obscure: true,
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          Text(
                            _error!,
                            style: const TextStyle(
                                color: Colors.red, fontWeight: FontWeight.w700),
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.black.withOpacity(0.85),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(28)),
                            ),
                            onPressed: _loading ? null : _createAccount,
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Text(
                                    _t('create_account'),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;

  const _Field(
      {required this.controller, required this.hint, this.obscure = false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white.withOpacity(0.85),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
