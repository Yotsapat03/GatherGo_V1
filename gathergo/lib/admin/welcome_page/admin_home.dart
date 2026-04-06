// lib/welcome_page/admin_home.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_routes.dart';
import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import '../bigevent/big_event_detail_page.dart';
import '../audit_log/audit_log_select_page.dart';
import '../moderation/app_asset_page.dart';
import '../user/user_list_page.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  static const String _kReadNotificationKeys = 'admin_read_notifications_v1';
  static const int _promoLoopBasePage = 10000;
  final PageController _promoController =
      PageController(initialPage: _promoLoopBasePage);
  Timer? _promoTimer;
  List<Map<String, dynamic>> _promoBigEvents = const [];
  List<_AdminNotificationItem> _notifications = const [];
  Set<String> _readNotificationKeys = const <String>{};

  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
    _loadReadNotificationKeys();
    _loadNotifications();
    _loadPromoBigEvents();
  }

  @override
  void dispose() {
    AdminLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _promoTimer?.cancel();
    _promoController.dispose();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
    _loadNotifications();
  }

  Future<void> _loadReadNotificationKeys() async {
    final prefs = await SharedPreferences.getInstance();
    final stored =
        prefs.getStringList(_kReadNotificationKeys) ?? const <String>[];
    if (!mounted) return;
    setState(() {
      _readNotificationKeys = stored.toSet();
    });
  }

  Future<void> _persistReadNotificationKeys(Set<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kReadNotificationKeys, keys.toList()..sort());
  }

  int _maxParticipantsOf(Map<String, dynamic> event) {
    final raw = event['max_participants'] ?? event['maxParticipants'] ?? 0;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  DateTime? _parsePromoDate(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  String _formatNotificationDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} ${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> _loadNotifications() async {
    try {
      final adminId = await AdminSessionService.getCurrentAdminId();
      final headers = <String, String>{'Accept': 'application/json'};
      if (adminId != null && adminId > 0) {
        headers['x-admin-id'] = adminId.toString();
      }

      final res = await http
          .get(Uri.parse('${ConfigService.getBaseUrl()}/api/big-events'),
              headers: headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      final List<dynamic> data;
      if (decoded is List) {
        data = decoded;
      } else if (decoded is Map<String, dynamic> && decoded['data'] is List) {
        data = List<dynamic>.from(decoded['data'] as List);
      } else {
        return;
      }

      final now = DateTime.now();
      final deadline = now.add(const Duration(hours: 48));
      final items = <_AdminNotificationItem>[];

      for (final raw in data.whereType<Map>()) {
        final event = Map<String, dynamic>.from(raw);
        final eventId =
            int.tryParse((event['id'] ?? event['event_id'] ?? '').toString()) ??
                0;
        final startAt = _parsePromoDate(event['start_at'] ?? event['date']);
        if (eventId <= 0 ||
            startAt == null ||
            startAt.isBefore(now) ||
            startAt.isAfter(deadline)) {
          continue;
        }

        items.add(
          _AdminNotificationItem(
            title: (event['title'] ?? 'Big Event').toString(),
            subtitle: AdminStrings.text(
              'big_event_starts_at',
              params: {'date': _formatNotificationDateTime(startAt)},
            ),
            startsAt: startAt,
            eventId: eventId,
            payload: event,
          ),
        );
      }

      items.sort((a, b) => a.startsAt.compareTo(b.startsAt));
      final validKeys = items.map((item) => item.storageKey).toSet();
      final nextReadKeys = _readNotificationKeys.intersection(validKeys);
      if (nextReadKeys.length != _readNotificationKeys.length) {
        await _persistReadNotificationKeys(nextReadKeys);
      }

      if (!mounted) return;
      setState(() {
        _notifications = items;
        _readNotificationKeys = nextReadKeys;
      });
    } catch (_) {}
  }

  bool _isNotificationRead(_AdminNotificationItem item) {
    return _readNotificationKeys.contains(item.storageKey);
  }

  bool get _hasUnreadNotifications {
    return _notifications.any((item) => !_isNotificationRead(item));
  }

  Future<void> _markNotificationAsRead(_AdminNotificationItem item) async {
    if (_readNotificationKeys.contains(item.storageKey)) return;
    final nextKeys = {..._readNotificationKeys, item.storageKey};
    await _persistReadNotificationKeys(nextKeys);
    if (!mounted) return;
    setState(() {
      _readNotificationKeys = nextKeys;
    });
  }

  Future<void> _openNotifications() async {
    await _loadNotifications();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AdminStrings.text('notifications'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (_notifications.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      AdminStrings.text('no_upcoming_notifications'),
                      style: const TextStyle(color: Colors.black54),
                    ),
                  )
                else
                  ..._notifications.map((item) {
                    final isRead = _isNotificationRead(item);
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        await _markNotificationAsRead(item);
                        if (!mounted) return;
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => BigEventDetailPage(
                              eventId: item.eventId,
                            ),
                          ),
                        ).then((_) => _loadNotifications());
                      },
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isRead
                              ? const Color(0xFFF4F6F8)
                              : const Color(0xFFF8FAFF),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE9FFF8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.directions_run,
                                size: 20,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.subtitle,
                                    style: TextStyle(
                                      color: isRead
                                          ? Colors.black45
                                          : Colors.black54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Colors.black38,
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isPromoActive(Map<String, dynamic> event) {
    final rawDate =
        (event['start_at'] ?? event['date'] ?? '').toString().trim();
    final eventDate = _parsePromoDate(rawDate);
    if (eventDate == null) return false;
    final hasExplicitTime =
        rawDate.contains('T') || RegExp(r'\d{2}:\d{2}').hasMatch(rawDate);
    final cutoff = hasExplicitTime
        ? eventDate
        : DateTime(
            eventDate.year,
            eventDate.month,
            eventDate.day,
            23,
            59,
            59,
            999,
          );
    return !cutoff.isBefore(DateTime.now());
  }

  int _promoDateDistanceMillis(Map<String, dynamic> event) {
    final eventDate = _parsePromoDate(event['start_at'] ?? event['date']);
    if (eventDate == null) return 1 << 30;
    return eventDate.difference(DateTime.now()).inMilliseconds.abs();
  }

  void _restartPromoTimer() {
    _promoTimer?.cancel();
    if (!mounted || _promoBigEvents.length <= 1) return;

    _promoTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted ||
          !_promoController.hasClients ||
          _promoBigEvents.length <= 1) {
        return;
      }
      final currentPage = _promoController.page?.round() ?? _promoLoopBasePage;
      _promoController.animateToPage(
        currentPage + 1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  void _movePromoBy(int delta) {
    if (_promoBigEvents.length <= 1 || !_promoController.hasClients) return;
    final currentPage = _promoController.page?.round() ?? _promoLoopBasePage;
    _promoController.animateToPage(
      currentPage + delta,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _loadPromoBigEvents() async {
    try {
      final adminId = await AdminSessionService.getCurrentAdminId();
      final headers = <String, String>{'Accept': 'application/json'};
      if (adminId != null && adminId > 0) {
        headers['x-admin-id'] = adminId.toString();
      }

      final res = await http
          .get(Uri.parse('${ConfigService.getBaseUrl()}/api/big-events'),
              headers: headers)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      final List<dynamic> data;
      if (decoded is List) {
        data = decoded;
      } else if (decoded is Map<String, dynamic> && decoded['data'] is List) {
        data = List<dynamic>.from(decoded['data'] as List);
      } else {
        return;
      }

      final mapped = data
          .whereType<Map>()
          .map((raw) {
            final e = Map<String, dynamic>.from(raw);
            final rawCover = (e['cover_url'] ??
                    e['coverUrl'] ??
                    e['image_url'] ??
                    e['imageUrl'] ??
                    '')
                .toString();
            return <String, dynamic>{
              ...e,
              'id': int.tryParse((e['id'] ?? e['event_id'] ?? '').toString()) ??
                  0,
              'title': (e['title'] ?? e['name'] ?? 'Big Event').toString(),
              'image': ConfigService.resolveUrl(rawCover),
              'start_at': (e['start_at'] ?? e['date'] ?? '').toString(),
              'max_participants':
                  e['max_participants'] ?? e['maxParticipants'] ?? 0,
            };
          })
          .where((event) => (event['image'] ?? '').toString().trim().isNotEmpty)
          .where(_isPromoActive)
          .toList();

      mapped.sort((a, b) {
        final maxCompare =
            _maxParticipantsOf(b).compareTo(_maxParticipantsOf(a));
        if (maxCompare != 0) return maxCompare;

        final dateCompare =
            _promoDateDistanceMillis(a).compareTo(_promoDateDistanceMillis(b));
        if (dateCompare != 0) return dateCompare;

        final aDate = _parsePromoDate(a['start_at']);
        final bDate = _parsePromoDate(b['start_at']);
        if (aDate == null && bDate == null) return 0;
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });

      final topTen = mapped.take(10).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _promoBigEvents = topTen;
      });
      if (_promoController.hasClients) {
        _promoController.jumpToPage(_promoLoopBasePage);
      }
      _restartPromoTimer();
    } catch (_) {}
  }

  void _openPromoEvent(Map<String, dynamic> event) {
    final eventId = event['id'] is int
        ? event['id'] as int
        : int.tryParse('${event['id']}') ?? 0;
    if (eventId <= 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BigEventDetailPage(eventId: eventId),
      ),
    );
  }

  Widget _buildPromoBanner() {
    if (_promoBigEvents.isEmpty) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 150,
        width: double.infinity,
        child: Stack(
          children: [
            PageView.builder(
              controller: _promoController,
              itemBuilder: (_, index) {
                final event = _promoBigEvents[index % _promoBigEvents.length];
                final image = (event['image'] ?? '').toString();
                return InkWell(
                  onTap: () => _openPromoEvent(event),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      image.startsWith('http')
                          ? Image.network(
                              image,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFFF7F7F7),
                              ),
                            )
                          : Image.asset(
                              image,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: const Color(0xFFF7F7F7),
                              ),
                            ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              Colors.black.withOpacity(0.46),
                              Colors.black.withOpacity(0.14),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AdminStrings.text('big_event'),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 20,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    (event['title'] ?? 'Big Event').toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${AdminStrings.text('max_participants')}: ${_maxParticipantsOf(event)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => Navigator.pushNamed(
                                  context, AppRoutes.bigEventList),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Text(
                                  'ดูเพิ่มเติม',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
              onPageChanged: (index) {
                if (!mounted) return;
                _restartPromoTimer();
              },
            ),
            if (_promoBigEvents.length > 1)
              Positioned(
                left: 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _AdminPromoNavButton(
                    icon: Icons.chevron_left,
                    onTap: () => _movePromoBy(-1),
                  ),
                ),
              ),
            if (_promoBigEvents.length > 1)
              Positioned(
                right: 10,
                top: 0,
                bottom: 0,
                child: Center(
                  child: _AdminPromoNavButton(
                    icon: Icons.chevron_right,
                    onTap: () => _movePromoBy(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final side = w >= 420 ? 18.0 : 14.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const gap = 14.0;
            final contentWidth = constraints.maxWidth - (side * 2);
            final tileW = (contentWidth - gap) / 2;

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(side, 10, side, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _SettingsPopupButton(
                        asset: 'assets/images/home/setting_icon.png',
                        fallback: Icons.settings_outlined,
                        tooltipKey: 'settings',
                      ),
                      Row(
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _SquareIconButton(
                                asset: '',
                                fallback: Icons.notifications_none_rounded,
                                tooltip: AdminStrings.text('notifications'),
                                onTap: _openNotifications,
                              ),
                              if (_hasUnreadNotifications)
                                Positioned(
                                  right: -2,
                                  top: -2,
                                  child: Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF3B30),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (_promoBigEvents.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _Card(
                      child: Column(
                        children: [
                          Text(
                            AdminStrings.text('overall_information'),
                            style: TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 16),
                          ),
                          const SizedBox(height: 10),
                          _buildPromoBanner(),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Text(
                    AdminStrings.text('quick_menu'),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      _MenuTileClean(
                        width: tileW,
                        title: AdminStrings.text('user'),
                        subtitle: AdminStrings.text('manage_users'),
                        asset: 'assets/images/home/user.png',
                        fallback: Icons.people_outline,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const UserListPage(),
                            ),
                          );
                        },
                      ),
                      _MenuTileClean(
                        width: tileW,
                        title: AdminStrings.text('event_report'),
                        subtitle: AdminStrings.text('reports_overview'),
                        asset: 'assets/images/home/event_report.png',
                        fallback: Icons.insert_chart_outlined,
                        onTap: () {
                          Navigator.pushNamed(
                              context, AppRoutes.adminEventReport);
                        },
                      ),
                      _MenuTileClean(
                        width: tileW,
                        title: AdminStrings.text('big_event'),
                        subtitle: AdminStrings.text('organizations_events'),
                        asset: 'assets/images/home/big_event.png',
                        fallback: Icons.event_available_outlined,
                        onTap: () {
                          Navigator.pushNamed(context, AppRoutes.bigEventList);
                        },
                      ),
                      _MenuTileClean(
                        width: tileW,
                        title: AdminStrings.text('audit_log'),
                        subtitle: AdminStrings.text('track_activities'),
                        asset: '',
                        fallback: Icons.key_outlined,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AuditLogSelectPage(),
                            ),
                          );
                        },
                      ),
                      _MenuTileClean(
                        width: tileW,
                        title: AdminStrings.text('moderation'),
                        subtitle: AdminStrings.text('review_chat_cases'),
                        asset: 'assets/images/home/audit.png',
                        fallback: Icons.shield_outlined,
                        onTap: () {
                          Navigator.pushNamed(
                            context,
                            AppRoutes.adminSpotChatModeration,
                          );
                        },
                      ),
                      _MenuTileClean(
                        width: tileW,
                        title: AdminStrings.text('app_asset'),
                        subtitle: AdminStrings.text('usage_trends_activity'),
                        asset: '',
                        fallback: Icons.analytics_outlined,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const AppAssetPage(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final String asset;
  final IconData fallback;
  final String tooltip;

  const _CircleIconButton({
    required this.asset,
    required this.fallback,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Center(
          child: asset.isEmpty
              ? Icon(fallback, size: 24, color: Colors.black87)
              : Image.asset(
                  asset,
                  width: 24,
                  height: 24,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      Icon(fallback, size: 24, color: Colors.black87),
                ),
        ),
      ),
    );
  }
}

class _SettingsPopupButton extends StatelessWidget {
  final String asset;
  final IconData fallback;
  final String tooltipKey;

  const _SettingsPopupButton({
    required this.asset,
    required this.fallback,
    required this.tooltipKey,
  });

  Future<void> _logout(BuildContext context) async {
    final adminId = await AdminSessionService.getCurrentAdminId();
    final adminEmail = await AdminSessionService.getCurrentAdminEmail();
    if (adminId != null && adminId > 0) {
      final uri = Uri.parse('${ConfigService.getBaseUrl()}/api/admin/logout')
          .replace(queryParameters: {
        'admin_id': adminId.toString(),
      });
      try {
        await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'x-admin-id': adminId.toString(),
          },
          body: jsonEncode({
            'admin_id': adminId,
            if (adminEmail != null && adminEmail.isNotEmpty)
              'admin_email': adminEmail,
          }),
        );
      } catch (_) {}
    }
    await AdminSessionService.clearSession();
    if (!context.mounted) return;
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.adminLogin,
      (route) => false,
    );
  }

  Future<void> _openLanguageMenu(BuildContext context) async {
    final currentCode = AdminLocaleController.languageCode.value;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: Text(AdminStrings.text('language')),
          children: AdminLocaleController.supportedLanguageCodes.map((code) {
            final selected = code == currentCode;
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, code),
              child: Row(
                children: [
                  Expanded(child: Text(AdminStrings.languageLabel(code))),
                  if (selected) const Icon(Icons.check_rounded, size: 18),
                ],
              ),
            );
          }).toList(),
        );
      },
    );

    if (selected == null) return;
    await AdminLocaleController.setLanguage(selected);
  }

  @override
  Widget build(BuildContext context) {
    final tooltip = AdminStrings.text(tooltipKey);
    return Tooltip(
      message: tooltip,
      child: PopupMenuButton<String>(
        tooltip: tooltip,
        offset: const Offset(0, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: (value) async {
          if (value == 'language') {
            await _openLanguageMenu(context);
            return;
          }
          if (value == 'logout') {
            await _logout(context);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<String>(
            value: 'logout',
            child: Row(
              children: [
                const Icon(Icons.logout, size: 20),
                const SizedBox(width: 10),
                Text(AdminStrings.text('logout')),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'language',
            child: Row(
              children: [
                const Icon(Icons.translate_rounded, size: 20),
                const SizedBox(width: 10),
                Text(AdminStrings.text('language')),
              ],
            ),
          ),
        ],
        child: _CircleIconButton(
          asset: asset,
          fallback: fallback,
          tooltip: tooltip,
        ),
      ),
    );
  }
}

class _SquareIconButton extends StatelessWidget {
  final String asset;
  final IconData fallback;
  final String tooltip;
  final VoidCallback onTap;

  const _SquareIconButton({
    required this.asset,
    required this.fallback,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: asset.isEmpty
                ? Icon(fallback, size: 22, color: Colors.white)
                : Image.asset(
                    asset,
                    width: 22,
                    height: 22,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        Icon(fallback, size: 22, color: Colors.white),
                  ),
          ),
        ),
      ),
    );
  }
}

class _MenuTileClean extends StatelessWidget {
  final double width;
  final String title;
  final String subtitle;
  final String asset;
  final IconData fallback;
  final VoidCallback onTap;

  const _MenuTileClean({
    required this.width,
    required this.title,
    required this.subtitle,
    required this.asset,
    required this.fallback,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 126,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEDEBFF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Center(
                    child: asset.isEmpty
                        ? Icon(fallback, size: 28, color: Colors.black87)
                        : Image.asset(
                            asset,
                            width: 30,
                            height: 30,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                Icon(fallback, size: 28, color: Colors.black87),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black54,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.black38),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminPromoNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _AdminPromoNavButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black38,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _AdminNotificationItem {
  final String title;
  final String subtitle;
  final DateTime startsAt;
  final int eventId;
  final Map<String, dynamic> payload;

  const _AdminNotificationItem({
    required this.title,
    required this.subtitle,
    required this.startsAt,
    required this.eventId,
    required this.payload,
  });

  String get storageKey =>
      'big_event_upcoming|$eventId|${startsAt.toUtc().toIso8601String()}';
}
