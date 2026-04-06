import 'dart:async';
import 'package:flutter/material.dart';
import '../../app_routes.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';

class SuccessPage extends StatefulWidget {
  final String title;
  final String subtitle;
  final String buttonText;
  final String? titleKey;
  final String? subtitleKey;
  final String? buttonTextKey;

  /// ถ้ากำหนด จะกดปุ่ม/auto แล้ว pop กลับไปจนถึง route นี้
  final String? popUntilRouteName;

  /// กันกด back ของระบบ (Android)
  final bool blockSystemBack;

  /// ถ้าใส่ จะ auto ทำงานภายในกี่วินาที
  final int? autoSeconds;

  const SuccessPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.buttonText,
    this.titleKey,
    this.subtitleKey,
    this.buttonTextKey,
    this.popUntilRouteName,
    this.blockSystemBack = false,
    this.autoSeconds,
  });

  @override
  State<SuccessPage> createState() => _SuccessPageState();
}

class _SuccessPageState extends State<SuccessPage> {
  Timer? _timer;

  bool get _showActionButton => widget.autoSeconds == null;

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);

    if (widget.autoSeconds != null) {
      _timer = Timer(Duration(seconds: widget.autoSeconds!), _goNext);
    }
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _timer?.cancel();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _resolveText(String? key, String fallback) {
    final normalizedKey = (key ?? '').trim();
    if (normalizedKey.isEmpty) return fallback;
    return UserStrings.text(normalizedKey);
  }

  void _goNext() {
    if (!mounted) return;

    // ✅ กลับไปจนถึง route ที่กำหนด
    final target = widget.popUntilRouteName;
    if (target != null && target.trim().isNotEmpty) {
      bool found = false;
      Navigator.popUntil(context, (route) {
        final isTarget = route.settings.name == target;
        if (isTarget) found = true;
        return isTarget;
      });

      if (!mounted) return;
      if (!found) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          target,
          (r) => false,
        );
      }
      return;
    }

    // ✅ default: กลับ Home
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.userHome,
      (r) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _resolveText(widget.titleKey, widget.title);
    final subtitle = _resolveText(widget.subtitleKey, widget.subtitle);
    final buttonText = _resolveText(widget.buttonTextKey, widget.buttonText);

    return PopScope(
      canPop: !widget.blockSystemBack,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFF),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 92, color: Colors.green),
                const SizedBox(height: 14),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.black54),
                ),
                if (_showActionButton) ...[
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _goNext,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD25C),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        buttonText,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
