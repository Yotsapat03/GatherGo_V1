import 'package:flutter/material.dart';
import '../../app_routes.dart';
import '../../user/localization/user_locale_controller.dart';
import 'welcome_i18n.dart';

class RolePage extends StatefulWidget {
  final bool isSignUp;
  final bool postLogin;
  final String selectedRole;
  final Map<String, dynamic> user;

  const RolePage({
    super.key,
    required this.isSignUp,
    this.postLogin = false,
    this.selectedRole = 'user',
    this.user = const {},
  });

  @override
  State<RolePage> createState() => _RolePageState();
}

class _RolePageState extends State<RolePage> {
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

  void _handleBackNavigation(BuildContext context) {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }

    Navigator.pushReplacementNamed(context, AppRoutes.welcome);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isSignUp) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        Navigator.pushReplacementNamed(context, AppRoutes.userSignupStep1);
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    final titleFontSize = (w * 0.10).clamp(40.0, 84.0);
    final subtitleFontSize = (w * 0.065).clamp(22.0, 48.0);
    final topGap = (h * 0.12).clamp(28.0, 120.0);
    final middleGap = (h * 0.18).clamp(40.0, 180.0);
    final bottomGap = (h * 0.10).clamp(24.0, 72.0);

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/welcome.png',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
          Container(color: Colors.black.withOpacity(0.35)),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: w * 0.10),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => _handleBackNavigation(context),
                            icon: const Icon(Icons.arrow_back),
                            color: Colors.white,
                            tooltip: WelcomeI18n.text('back'),
                          ),
                          const Spacer(),
                          const WelcomeTranslateButton(),
                        ],
                      ),
                      SizedBox(height: topGap),
                      Text(
                        widget.postLogin
                            ? WelcomeI18n.text('select_role')
                            : WelcomeI18n.text('log_in'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w800,
                          shadows: const [
                            Shadow(blurRadius: 12, color: Colors.black54),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        widget.postLogin
                            ? WelcomeI18n.text('choose_where_to_enter')
                            : WelcomeI18n.text('who_are_you'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.95),
                          fontSize: subtitleFontSize,
                          fontWeight: FontWeight.w600,
                          shadows: const [
                            Shadow(blurRadius: 12, color: Colors.black54),
                          ],
                        ),
                      ),
                      SizedBox(height: middleGap),
                      _RoleButton(
                        text: WelcomeI18n.text('user'),
                        onTap: () {
                          if (widget.postLogin) {
                            Navigator.pushReplacementNamed(
                              context,
                              AppRoutes.userHome,
                              arguments: {
                                'user': widget.user,
                                'selectedRole': 'user',
                              },
                            );
                            return;
                          }
                          Navigator.pushNamed(
                            context,
                            AppRoutes.adminLogin,
                            arguments: {
                              'isSignUp': widget.isSignUp,
                              'selectedRole': 'user',
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 14),
                      _RoleButton(
                        text: WelcomeI18n.text('admin'),
                        onTap: () {
                          if (widget.postLogin) {
                            Navigator.pushReplacementNamed(
                              context,
                              AppRoutes.adminHome,
                              arguments: {
                                'user': widget.user,
                                'selectedRole': 'admin',
                              },
                            );
                            return;
                          }
                          Navigator.pushNamed(
                            context,
                            AppRoutes.adminLogin,
                            arguments: {
                              'isSignUp': widget.isSignUp,
                              'selectedRole': 'admin',
                            },
                          );
                        },
                      ),
                      SizedBox(height: bottomGap),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _RoleButton({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.92),
          foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        onPressed: onTap,
        child: Text(text),
      ),
    );
  }
}
