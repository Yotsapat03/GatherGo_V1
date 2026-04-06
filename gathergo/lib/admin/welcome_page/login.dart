import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app_routes.dart';
import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../../user/auth/user_account_guard_service.dart';
import '../../user/localization/user_locale_controller.dart';
import 'welcome_i18n.dart';

class AdminLoginPage extends StatefulWidget {
  final bool isSignUp;
  final String selectedRole;
  final String prefillEmail;

  const AdminLoginPage({
    super.key,
    required this.isSignUp,
    this.selectedRole = 'admin',
    this.prefillEmail = '',
  });

  @override
  State<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends State<AdminLoginPage> {
  final email = TextEditingController();
  final pass = TextEditingController();

  bool _loading = false;
  String? _error;
  late String _role;

  String get baseUrl => ConfigService.getApiBaseUrl();

  Uri _apiUri(String path) {
    final base = baseUrl.trim();
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final baseUri = Uri.tryParse(base);
    if (baseUri != null && baseUri.hasScheme && baseUri.host.isNotEmpty) {
      return baseUri.resolve(normalizedPath);
    }
    return Uri.parse('http://localhost:3000$normalizedPath');
  }

  bool _isWrongTarget404(Uri primary, http.Response res, String path) {
    if (!kIsWeb || !kDebugMode) return false;
    if (res.statusCode != 404) return false;
    final body = res.body.toLowerCase();
    final p = path.toLowerCase();
    final cannotPostPath = body.contains("cannot post") && body.contains(p);
    if (!cannotPostPath) return false;

    final webOrigin = ConfigService.getWebOrigin();
    final isWebOrigin =
        webOrigin != null && ConfigService.isSameHostPort(primary, webOrigin);
    final isLikelyFlutterPort = ConfigService.isLikelyFlutterDevPort(primary);
    return isWebOrigin || isLikelyFlutterPort;
  }

  String _extractErrorMessage(http.Response res) {
    try {
      final data = jsonDecode(res.body);
      if (data is Map &&
          data["message"] is String &&
          (data["message"] as String).trim().isNotEmpty) {
        return data["message"].toString();
      }
      if (data is Map &&
          data["error"] is String &&
          (data["error"] as String).trim().isNotEmpty) {
        return data["error"].toString();
      }
    } catch (_) {}

    final body = res.body.trim();
    if (body.isNotEmpty) {
      final shortBody =
          body.length > 180 ? "${body.substring(0, 180)}..." : body;
      return "HTTP ${res.statusCode}: $shortBody";
    }
    return "HTTP ${res.statusCode}";
  }

  String _normalizeRole(dynamic rawRole) {
    final role = (rawRole ?? '').toString().trim().toLowerCase();
    if (role.isEmpty) return '';
    if (role == 'admin' || role == 'administrator') return 'admin';
    if (role == 'user' ||
        role == 'runner' ||
        role == 'normal user' ||
        role == 'normal_user') {
      return 'user';
    }
    return role;
  }

  String _extractAuthenticatedRole(Map<String, dynamic> data) {
    final candidates = <dynamic>[
      data['role'],
      data['user_role'],
      data['account_role'],
      data['account_type'],
      data['type'],
      data['kind'],
      (data['user'] is Map) ? (data['user'] as Map)['role'] : null,
      (data['user'] is Map) ? (data['user'] as Map)['type'] : null,
      (data['admin'] is Map) ? (data['admin'] as Map)['role'] : null,
      (data['admin'] is Map) ? (data['admin'] as Map)['type'] : null,
    ];

    for (final candidate in candidates) {
      final normalized = _normalizeRole(candidate);
      if (normalized == 'admin' || normalized == 'user') {
        return normalized;
      }
    }

    if (data['admin'] is Map) return 'admin';
    if (data['user'] is Map) return 'user';
    return '';
  }

  String _extractStatusFromErrorBody(http.Response res) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map<String, dynamic>) {
        return UserAccountGuardService.extractStatusFromLoginPayload(decoded);
      }
    } catch (_) {}

    final body = res.body.toLowerCase();
    if (body.contains('deleted')) return 'deleted';
    if (body.contains('suspend') || body.contains('blocked')) {
      return 'suspended';
    }
    return 'active';
  }

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    _role = widget.selectedRole;
    if (widget.prefillEmail.trim().isNotEmpty) {
      email.text = widget.prefillEmail.trim();
    }
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _handleBackNavigation() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.pushReplacementNamed(
      context,
      AppRoutes.role,
      arguments: {
        'isSignUp': widget.isSignUp,
        'selectedRole': widget.selectedRole,
      },
    );
  }

  Future<http.Response> _postLogin(String path) async {
    final primary = _apiUri(path);
    ConfigService.log("Login request URL: $primary");
    var res = await http.post(
      primary,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "email": email.text.trim(),
        "password": pass.text,
      }),
    );

    // Wrong-target fallback: Flutter web dev server responds 404 "Cannot POST ...".
    if (_isWrongTarget404(primary, res, path)) {
      final fallback = ConfigService.getDevFallbackUri(path);
      if (fallback != null && fallback != primary) {
        ConfigService.log(
            "Login wrong-target detected (HTTP ${res.statusCode}). Retrying URL: $fallback");
        res = await http.post(
          fallback,
          headers: {"Content-Type": "application/json"},
          body: jsonEncode({
            "email": email.text.trim(),
            "password": pass.text,
          }),
        );
      }
    }

    return res;
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (email.text.trim().isEmpty || pass.text.isEmpty) {
        _showSnack(WelcomeI18n.text('please_enter_both'));
        setState(() {
          _loading = false;
          _error = WelcomeI18n.text('please_enter_both');
        });
        return;
      }

      http.Response res;

      if (_role == 'admin') {
        res = await _postLogin("/api/admin/login");
      } else {
        res = await _postLogin("/api/auth/login");
        // Some existing accounts were created through legacy user auth flow.
        // If modern endpoint fails with 401/404, retry legacy endpoint.
        if (res.statusCode == 404 || res.statusCode == 401) {
          res = await _postLogin("/api/login");
        }
      }

      if (!mounted) return;

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final data =
            decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
        final authenticatedRole = _extractAuthenticatedRole(data);
        final destinationRole = authenticatedRole.isNotEmpty
            ? authenticatedRole
            : (_role == 'admin' ? 'admin' : 'user');

        if (destinationRole == 'admin') {
          final admin = (data is Map && data['admin'] is Map)
              ? Map<String, dynamic>.from(data['admin'] as Map)
              : <String, dynamic>{};
          final adminId = int.tryParse((admin['id'] ?? '').toString());
          final adminEmail = (admin['email'] ?? email.text).toString().trim();
          if (adminId == null || adminId <= 0) {
            final msg = WelcomeI18n.text('login_response_missing_admin_id');
            _showSnack(msg);
            setState(() => _error = "[admin] $msg");
            return;
          }
          await SessionService.clearSession();
          await AdminSessionService.clearSession();
          await AdminSessionService.setSession(
            adminId: adminId,
            email: adminEmail,
          );
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, AppRoutes.adminHome);
        } else {
          final user = (data is Map && data['user'] is Map)
              ? Map<String, dynamic>.from(data['user'] as Map)
              : <String, dynamic>{};
          final accountStatus =
              UserAccountGuardService.extractStatusFromLoginPayload(data);
          if (accountStatus == 'suspended') {
            _showSnack(WelcomeI18n.text('suspended_account'));
            setState(() => _error = '[user] suspended');
            return;
          }
          if (accountStatus == 'deleted') {
            _showSnack(WelcomeI18n.text('deleted_account'));
            setState(() => _error = '[user] deleted');
            return;
          }
          final userId = int.tryParse((user['id'] ?? '').toString());
          final emailValue = (user['email'] ?? email.text).toString().trim();
          if (userId == null || userId <= 0) {
            final msg = WelcomeI18n.text('login_response_missing_user_id');
            _showSnack(msg);
            setState(() => _error = "[user] $msg");
            return;
          }
          await AdminSessionService.clearSession();
          await SessionService.clearSession();
          await SessionService.setSession(userId: userId, email: emailValue);
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, AppRoutes.userHome);
        }
        return;
      }

      final msg = _extractErrorMessage(res);

      if (res.statusCode == 401) {
        _showSnack(WelcomeI18n.text('incorrect_email_password'));
      } else if (res.statusCode == 400) {
        _showSnack(WelcomeI18n.text('please_enter_both'));
      } else if (res.statusCode == 403) {
        final blockedStatus = _extractStatusFromErrorBody(res);
        if (blockedStatus == 'deleted') {
          _showSnack(WelcomeI18n.text('deleted_account'));
        } else if (blockedStatus == 'suspended') {
          _showSnack(WelcomeI18n.text('suspended_account'));
        } else {
          _showSnack(WelcomeI18n.text('inactive_account'));
        }
      } else if (res.statusCode == 404) {
        _showSnack(WelcomeI18n.text('user_login_api_not_found'));
      } else {
        _showSnack(msg);
      }

      setState(() => _error = "[$_role] $msg (HTTP ${res.statusCode})");
    } catch (e) {
      if (!mounted) return;
      final msg = WelcomeI18n.text('unable_connect');
      _showSnack(msg);
      setState(() => _error = "Cannot connect to server: $e");
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
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.08),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _loading ? null : _handleBackNavigation,
                        icon: const Icon(Icons.arrow_back),
                        color: Colors.white,
                        tooltip: WelcomeI18n.text('back'),
                      ),
                      const Spacer(),
                      const WelcomeTranslateButton(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.isSignUp
                        ? WelcomeI18n.text('sign_up')
                        : WelcomeI18n.text('log_in'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: w * 0.11,
                      fontWeight: FontWeight.w800,
                      shadows: const [
                        Shadow(blurRadius: 12, color: Colors.black54),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
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
                        Text(
                          WelcomeI18n.text('email'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        _Field(
                          controller: email,
                          hint: WelcomeI18n.text('enter_email'),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          WelcomeI18n.text('password'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        _Field(
                          controller: pass,
                          hint: WelcomeI18n.text('enter_password'),
                          obscure: true,
                        ),
                        const SizedBox(height: 12),
                        if (_error != null)
                          Text(
                            _error!,
                            style: const TextStyle(
                                color: Colors.red, fontWeight: FontWeight.w700),
                          ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.black.withOpacity(0.85),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(28),
                              ),
                            ),
                            onPressed: _loading ? null : _login,
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Text(
                                    WelcomeI18n.text('confirm'),
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.center,
                          child: TextButton(
                            onPressed: _loading
                                ? null
                                : () => Navigator.pushNamed(
                                    context, AppRoutes.userSignupStep1),
                            child: Text(
                              WelcomeI18n.text('create_new_account'),
                              style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
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
