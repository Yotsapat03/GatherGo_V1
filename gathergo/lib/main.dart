import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_routes.dart';
import 'user/data/mock_store.dart';
import 'user/data/user_booking_store.dart';
import 'user/data/user_event_store.dart';
import 'user/localization/user_locale_controller.dart';

const _kOneTimeLocalResetDone = 'gathergo_one_time_local_reset_v1';

Future<void> _resetLegacyLocalStateOnce() async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kOneTimeLocalResetDone) == true) return;
  await MockStore.clearSessionState();
  await UserBookingStore.clearAll();
  await UserEventStore.clearAll();
  await prefs.setBool(_kOneTimeLocalResetDone, true);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MockStore.init();
  await UserBookingStore.init();
  await UserEventStore.init();
  await _resetLegacyLocalStateOnce();
  await UserLocaleController.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      // ✅ เริ่มที่หน้า welcome
      initialRoute: AppRoutes.welcome,

      // ✅ route แบบ map (หน้าไม่มี required args)
      routes: AppRoutes.routes,

      // ✅ route ที่ต้องการ args หรือบังคับให้ส่ง settings.arguments แน่ๆ
      onGenerateRoute: AppRoutes.onGenerateRoute,

      // ✅ กัน route สะกดผิด/หาไม่เจอ จะได้รู้ทันที
      onUnknownRoute: (settings) {
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text("Route not found")),
            body: Center(
              child: Text(
                "No route defined for:\n${settings.name}",
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },

      // (ไม่จำเป็น) ใส่ theme เบา ๆ
      theme: ThemeData(
        useMaterial3: false,
        fontFamily: null,
      ),
    );
  }
}
