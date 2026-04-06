import 'package:flutter/material.dart';
import '../../app_routes.dart';
import '../../user/localization/user_locale_controller.dart';
import 'welcome_i18n.dart';

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  static const String _bg = 'assets/images/welcome.png';
  static const String _logo = 'assets/images/logo.png';

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ✅ Background image (กันพังด้วย errorBuilder)
          Image.asset(
            _bg,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (context, error, stack) {
              return Container(
                color: const Color(0xFF0F172A), // fallback สีเข้ม
                alignment: Alignment.center,
                child: const Text(
                  'Background image not found',
                  style: TextStyle(color: Colors.white70),
                ),
              );
            },
          ),

          // ✅ Overlay
          Container(color: Colors.black.withOpacity(0.35)),

          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: w * 0.10),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: const [
                      WelcomeTranslateButton(),
                    ],
                  ),
                  SizedBox(height: h * 0.04),

                  // ✅ Logo (กันพังด้วย errorBuilder)
                  SizedBox(
                    width: w * 0.26,
                    height: w * 0.26,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: ClipOval(
                          child: Image.asset(
                            _logo,
                            fit: BoxFit.contain,
                            semanticLabel: 'GatherGo logo',
                            errorBuilder: (context, error, stack) {
                              return const Center(
                                child: Text(
                                  'logo.png\nnot found',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white70),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    WelcomeI18n.text('find_your_pace'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: (w * 0.07).clamp(22, 34), // ✅ กันใหญ่/เล็กเกิน
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      shadows: const [
                        Shadow(blurRadius: 10, color: Colors.black54),
                      ],
                    ),
                  ),

                  const Spacer(),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.70),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () {
                        Navigator.pushNamed(context, AppRoutes.userSignupStep1);
                      },
                      child: Text(WelcomeI18n.text('sign_up')),
                    ),
                  ),

                  const SizedBox(height: 14),

                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.black.withOpacity(0.70),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () {
                        Navigator.pushNamed(
                          context,
                          AppRoutes.role,
                          arguments: {
                            'isSignUp': false,
                          },
                        );
                      },
                      child: Text(WelcomeI18n.text('log_in')),
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
