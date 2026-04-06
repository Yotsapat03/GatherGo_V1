import 'package:flutter/material.dart';
import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import 'engagement_tab.dart';
import 'registrations_tab.dart';
import 'payments_tab.dart';

class AdminEventReportPage extends StatefulWidget {
  const AdminEventReportPage({super.key});

  @override
  State<AdminEventReportPage> createState() => _AdminEventReportPageState();
}

class _AdminEventReportPageState extends State<AdminEventReportPage> {
  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
  }

  @override
  void dispose() {
    AdminLocaleController.languageCode.removeListener(_handleLanguageChanged);
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final args =
        (ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?) ??
            const <String, dynamic>{};
    final initialTab =
        int.tryParse((args['initialTab'] ?? '0').toString()) ?? 0;
    final safeInitialTab = initialTab.clamp(0, 2);

    return DefaultTabController(
      length: 3,
      initialIndex: safeInitialTab,
      child: Scaffold(
        backgroundColor: const Color(0xFFF3F3F3),
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(AdminStrings.text('event_report_page')),
          bottom: TabBar(
            isScrollable: true,
            indicatorColor: Color(0xFF6C63FF),
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            tabs: [
              Tab(text: AdminStrings.text('registrations')),
              Tab(text: AdminStrings.text('payment')),
              Tab(text: AdminStrings.text('engagement')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            RegistrationsTab(),
            PaymentsTab(),
            EngagementTab(),
          ],
        ),
      ),
    );
  }
}
