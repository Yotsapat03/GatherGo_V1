import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_assets_keys.dart';
import '../../app_routes.dart';
import '../../core/services/session_service.dart';
import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import '../../core/utils/payment_booking_status.dart';
import 'spot/spot_detail_page.dart';
import 'joined_event/joined_event_detail_page.dart';
import 'big_event/big_event_detail_page.dart';
import 'auth/user_account_guard_service.dart';
import 'data/user_activity_change_store.dart';
import 'localization/user_locale_controller.dart';
import 'localization/user_strings.dart';
import 'profile/user_distance_service.dart';
import 'services/activity_stats_refresh_service.dart';
import 'utils/activity_expiry.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  List<_UserNotificationItem> _notifications = const [];
  Set<String> _readNotificationKeys = const <String>{};
  static const String _kReadNotificationKeys = 'user_read_notifications_v1';
  static const int _promoLoopBasePage = 10000;
  final PageController _promoController =
      PageController(initialPage: _promoLoopBasePage);
  Timer? _promoTimer;
  List<Map<String, dynamic>> _promoBigEvents = const [];
  bool _loadingPromoBigEvents = false;
  DistanceUserSummary? _homeSummary;
  UserAccountState? _accountState;
  bool _checkingAccountState = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    ActivityStatsRefreshService.revision.addListener(_handleStatsChanged);
    _loadReadNotificationKeys();
    _loadNotifications();
    _loadPromoBigEvents();
    _loadHomeSummary();
    _refreshAccountState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    ActivityStatsRefreshService.revision.removeListener(_handleStatsChanged);
    _promoTimer?.cancel();
    _promoController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _loadHomeSummary();
    _loadPromoBigEvents();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
    _loadNotifications();
  }

  void _handleStatsChanged() {
    if (!mounted) return;
    _loadHomeSummary();
  }

  Future<void> _loadHomeSummary() async {
    try {
      final summary = await UserDistanceService.fetchCurrentUserSummary();
      if (!mounted) return;
      setState(() {
        _homeSummary = summary;
      });
    } catch (_) {}
  }

  Future<void> _refreshAccountState() async {
    if (mounted) {
      setState(() {
        _checkingAccountState = true;
      });
    }
    try {
      final state = await UserAccountGuardService.fetchCurrentUserState();
      if (!mounted) return;
      setState(() {
        _accountState = state.isBlocked ? state : null;
        _checkingAccountState = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _accountState = null;
        _checkingAccountState = false;
      });
    }
  }

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  String _accountBlockedTitle() {
    final code = UserLocaleController.languageCode.value;
    if (_accountState?.isDeleted == true) {
      switch (code) {
        case 'th':
          return 'บัญชีนี้ถูกลบแล้ว';
        case 'zh':
          return '此账号已被删除';
        default:
          return 'This account was deleted.';
      }
    }
    switch (code) {
      case 'th':
        return 'บัญชีของคุณมีปัญหา';
      case 'zh':
        return '您的账号存在问题';
      default:
        return 'There is a problem with your account.';
    }
  }

  String _accountBlockedMessage() {
    final backendMessage = (_accountState?.message ?? '').trim();
    if (backendMessage.isNotEmpty) return backendMessage;

    final code = UserLocaleController.languageCode.value;
    if (_accountState?.isDeleted == true) {
      switch (code) {
        case 'th':
          return 'บัญชีนี้ถูกลบโดยแอดมินแล้วเนื่องจากทำผิดกฎ โปรดสมัครใหม่เพื่อใช้งานต่อ';
        case 'zh':
          return '此账号因违反规则已被管理员删除，请重新注册后再使用。';
        default:
          return 'This account was deleted by the admin for breaking the rules. Please sign up again.';
      }
    }
    switch (code) {
      case 'th':
        return 'บัญชีคุณมีปัญหา โปรดติดต่อแอดมิน ตอนนี้คุณยังไม่สามารถใช้งานส่วนอื่นของแอปได้';
      case 'zh':
        return '您的账号目前被暂时停用，请联系管理员。现在无法继续使用应用的其他功能。';
      default:
        return 'Your account is temporarily blocked. Please contact the admin. You cannot use the rest of the app right now.';
    }
  }

  String _accountPrimaryActionLabel() {
    final code = UserLocaleController.languageCode.value;
    if (_accountState?.isDeleted == true) {
      switch (code) {
        case 'th':
          return 'กลับไปหน้าเข้าสู่ระบบ';
        case 'zh':
          return '返回登录页';
        default:
          return 'Back to login';
      }
    }
    return tr('retry');
  }

  Future<void> _handleBlockedPrimaryAction() async {
    if (_accountState?.isDeleted == true) {
      await SessionService.clearSession();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.adminLogin,
        (route) => false,
        arguments: const {
          'isSignUp': false,
          'selectedRole': 'user',
        },
      );
      return;
    }
    await _refreshAccountState();
  }

  Widget _buildBlockedHome() {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFFFD2D2)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEFEF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      _accountState?.isDeleted == true
                          ? Icons.person_off_outlined
                          : Icons.warning_amber_rounded,
                      size: 38,
                      color: const Color(0xFFD32F2F),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _accountBlockedTitle(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _accountBlockedMessage(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.45,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleBlockedPrimaryAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFD32F2F),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        _accountPrimaryActionLabel(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _resolveUrl(String? raw) =>
      ConfigService.resolveUrl((raw ?? '').trim());

  DateTime? _parsePromoDate(dynamic value) =>
      DateTime.tryParse((value ?? '').toString().trim())?.toLocal();

  int _maxParticipantsOf(Map<String, dynamic> event) {
    final raw = event['max_participants'] ?? event['maxParticipants'] ?? 0;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  bool _isEventJoined(Map<String, dynamic> event) {
    return event['is_joined'] == true ||
        event['isJoined'] == true ||
        PaymentBookingStatus.isBookingConfirmed(event['booking_status']) ||
        PaymentBookingStatus.isPaymentSuccessful(event['payment_status']);
  }

  Future<void> _refreshPromoBigEventsIfNeeded() async {
    if (_promoBigEvents.isEmpty) return;
    final activeEvents = _promoBigEvents
        .where((event) => !ActivityExpiry.isExpiredAfterGrace(event))
        .toList(growable: false);
    if (activeEvents.length == _promoBigEvents.length) return;

    if (!mounted) return;
    setState(() {
      _promoBigEvents = activeEvents;
    });
    await _loadPromoBigEvents();
  }

  void _restartPromoTimer() {
    _promoTimer?.cancel();
    if (!mounted || _promoBigEvents.length <= 1) return;

    _promoTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshPromoBigEventsIfNeeded();
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
    if (_loadingPromoBigEvents) return;
    _loadingPromoBigEvents = true;
    try {
      final userId = await SessionService.getCurrentUserId();
      final headers = <String, String>{'Accept': 'application/json'};
      if (userId != null && userId > 0) {
        headers['x-user-id'] = userId.toString();
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
          .map((raw) => Map<String, dynamic>.from(raw))
          .map((e) {
            final rawCover = (e['cover_url'] ??
                    e['coverUrl'] ??
                    e['image_url'] ??
                    e['imageUrl'] ??
                    '')
                .toString();
            return <String, dynamic>{
              ...e,
              'id': (e['id'] ?? e['event_id'] ?? '').toString(),
              'title': (e['title'] ?? e['name'] ?? UserStrings.bigEventTerm)
                  .toString(),
              'image': _resolveUrl(rawCover).isNotEmpty
                  ? _resolveUrl(rawCover)
                  : AppAssets.user_images_bg,
              'cover_url': rawCover,
              'date': (e['start_at'] ?? e['date'] ?? '').toString(),
              'start_at': (e['start_at'] ?? e['date'] ?? '').toString(),
              'max_participants':
                  e['max_participants'] ?? e['maxParticipants'] ?? 0,
              'location': (e['location_display'] ??
                      e['location_name'] ??
                      e['meeting_point'] ??
                      '')
                  .toString(),
              'organizer': (e['organization_name'] ?? e['organizer_name'] ?? '')
                  .toString(),
            };
          })
          .where((event) => !ActivityExpiry.isExpiredAfterGrace(event))
          .where((event) => !_isEventJoined(event))
          .toList();

      mapped.sort((a, b) {
        final maxCompare =
            _maxParticipantsOf(b).compareTo(_maxParticipantsOf(a));
        if (maxCompare != 0) return maxCompare;

        final aDate = _parsePromoDate(a['start_at'] ?? a['date']);
        final bDate = _parsePromoDate(b['start_at'] ?? b['date']);
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
    } catch (_) {
    } finally {
      _loadingPromoBigEvents = false;
    }
  }

  void _openPromoEvent(Map<String, dynamic> event) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BigEventDetailPage(event: event),
      ),
    ).then((_) {
      _loadHomeSummary();
      _loadPromoBigEvents();
    });
  }

  Widget _buildBigEventPromoBanner() {
    if (_promoBigEvents.isEmpty) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.pushNamed(context, AppRoutes.userBigEvent),
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Colors.white,
            border: Border.all(color: Colors.black12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(
                AppAssets.user_images_bg,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.black12,
                  alignment: Alignment.center,
                  child: const Icon(Icons.image_not_supported),
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withOpacity(0.40),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      UserStrings.bigEventTerm,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tr('join_next_challenge_now'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 110,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
        border: Border.all(color: Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
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
                              color: Colors.black12,
                              alignment: Alignment.center,
                              child: const Icon(Icons.image_not_supported),
                            ),
                          )
                        : Image.asset(
                            image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: Colors.black12,
                              alignment: Alignment.center,
                              child: const Icon(Icons.image_not_supported),
                            ),
                          ),
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.black.withOpacity(0.48),
                            Colors.black.withOpacity(0.12),
                          ],
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                        child: Stack(
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: GestureDetector(
                                onTap: () => Navigator.pushNamed(
                                  context,
                                  AppRoutes.userBigEvent,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: Colors.white),
                                  ),
                                  child: Text(
                                    tr('see_other_big_events'),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              top: 18,
                              right: 150,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    UserStrings.bigEventTerm,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    (event['title'] ?? UserStrings.bigEventTerm)
                                        .toString(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${tr('max_participants')}: ${_maxParticipantsOf(event)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.14),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Colors.white),
                                ),
                                child: Text(
                                  tr('click_book_now'),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
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
                child: _PromoNavButton(
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
                child: _PromoNavButton(
                  icon: Icons.chevron_right,
                  onTap: () => _movePromoBy(1),
                ),
              ),
            ),
        ],
      ),
    );
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

  Future<void> _loadNotifications() async {
    try {
      final userId = await SessionService.getCurrentUserId();
      if (userId == null || userId <= 0) return;

      final baseUrl = ConfigService.getBaseUrl();
      final joinedEventsUri =
          Uri.parse('$baseUrl/api/user/joined-events?user_id=$userId');
      final joinedSpotsUri =
          Uri.parse('$baseUrl/api/spots/joined?user_id=$userId');

      final responses = await Future.wait([
        http.get(
          joinedEventsUri,
          headers: {
            'Accept': 'application/json',
            'x-user-id': userId.toString(),
          },
        ),
        http.get(
          joinedSpotsUri,
          headers: {
            'Accept': 'application/json',
            'x-user-id': userId.toString(),
          },
        ),
      ]);

      final items = <_UserNotificationItem>[];
      final now = DateTime.now();
      final deadline = now.add(const Duration(hours: 24));
      final joinedBigEvents = <Map<String, dynamic>>[];
      final joinedSpots = <Map<String, dynamic>>[];

      if (responses[0].statusCode == 200) {
        final decoded = jsonDecode(responses[0].body);
        if (decoded is List) {
          for (final raw in decoded.whereType<Map>()) {
            final row = Map<String, dynamic>.from(raw);
            joinedBigEvents.add(row);
            final startAt = DateTime.tryParse(
                    (row['start_at'] ?? row['date'] ?? '').toString())
                ?.toLocal();
            if (startAt == null ||
                startAt.isBefore(now) ||
                startAt.isAfter(deadline)) {
              continue;
            }
            items.add(
              _UserNotificationItem(
                title: (row['title'] ?? 'Big Event').toString(),
                subtitle: tr(
                  'big_event_starts_at',
                  params: {'date': _formatNotificationDateTime(startAt)},
                ),
                type: 'big_event_upcoming',
                startsAt: startAt,
                payload: row,
              ),
            );
          }
        }
      }

      if (responses[1].statusCode == 200) {
        final decoded = jsonDecode(responses[1].body);
        if (decoded is List) {
          for (final raw in decoded.whereType<Map>()) {
            final row = Map<String, dynamic>.from(raw);
            joinedSpots.add(row);
            final startAt = _parseSpotDateTime(
              (row['event_date'] ?? '').toString(),
              (row['event_time'] ?? '').toString(),
            );
            if (startAt == null ||
                startAt.isBefore(now) ||
                startAt.isAfter(deadline)) {
              continue;
            }
            items.add(
              _UserNotificationItem(
                title: (row['title'] ?? 'Spot').toString(),
                subtitle: tr(
                  'spot_starts_at',
                  params: {'date': _formatNotificationDateTime(startAt)},
                ),
                type: 'spot_upcoming',
                startsAt: startAt,
                payload: {
                  ...row,
                  'backendSpotId': row['id'],
                  'id': row['id'],
                  'spotKey': (row['spot_key'] ?? '').toString(),
                  'spot_key': (row['spot_key'] ?? '').toString(),
                  'date': (row['event_date'] ?? '').toString(),
                  'time': (row['event_time'] ?? '').toString(),
                  'kmPerRound': (row['km_per_round'] ?? '').toString(),
                  'round': (row['round_count'] ?? '').toString(),
                  'maxPeople': (row['max_people'] ?? '').toString(),
                  'creatorName': (row['creator_name'] ?? 'User').toString(),
                  'creatorUserId': (row['created_by_user_id'] ?? '').toString(),
                  'creatorRole': (row['creator_role'] ?? 'user').toString(),
                  'imageBase64': (row['image_base64'] ?? '').toString(),
                  'image': (row['image_url'] ?? '').toString().trim().isNotEmpty
                      ? ConfigService.resolveUrl(
                          (row['image_url'] ?? '').toString())
                      : '',
                  'isJoined': true,
                  'is_joined': true,
                },
              ),
            );
          }
        }
      }

      final changeNotifications = await UserActivityChangeStore.sync(
        joinedSpots: joinedSpots,
        joinedBigEvents: joinedBigEvents,
      );
      for (final item in changeNotifications) {
        final changedAt =
            DateTime.tryParse((item['changed_at'] ?? '').toString())
                    ?.toLocal() ??
                DateTime.now();
        final changeLines = (item['change_lines'] is List)
            ? List<String>.from(item['change_lines'] as List)
            : const <String>[];
        final idText =
            (item['display_code'] ?? item['entity_id'] ?? '-').toString();
        final changedSummary =
            changeLines.isEmpty ? tr('data_changed') : changeLines.first;
        items.add(
          _UserNotificationItem(
            title: '[${idText}] ${(item['title'] ?? 'Activity').toString()}',
            subtitle: '${tr('changed_on', params: {
                  'date': _formatNotificationDateTime(changedAt)
                })}\n$changedSummary',
            type: (item['type'] ?? 'activity_change').toString(),
            startsAt: changedAt,
            payload: item,
          ),
        );
      }

      items.sort((a, b) => b.startsAt.compareTo(a.startsAt));
      final validKeys = items.map(_notificationStorageKey).toSet();
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

  DateTime? _parseSpotDateTime(String date, String time) {
    final dateText = date.trim();
    if (dateText.isEmpty) return null;
    final timeText = time.trim().isEmpty ? '00:00' : time.trim();

    final iso = DateTime.tryParse('${dateText}T$timeText')?.toLocal();
    if (iso != null) return iso;

    final dateMatch =
        RegExp(r'^(\d{1,2})\/(\d{1,2})\/(\d{4})$').firstMatch(dateText);
    final timeMatch = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(timeText);
    if (dateMatch != null) {
      final day = int.tryParse(dateMatch.group(1) ?? '');
      final month = int.tryParse(dateMatch.group(2) ?? '');
      final year = int.tryParse(dateMatch.group(3) ?? '');
      final hour = int.tryParse(timeMatch?.group(1) ?? '0') ?? 0;
      final minute = int.tryParse(timeMatch?.group(2) ?? '0') ?? 0;
      if (day != null && month != null && year != null) {
        return DateTime(year, month, day, hour, minute);
      }
    }

    return null;
  }

  String _formatNotificationDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} ${two(value.hour)}:${two(value.minute)}';
  }

  String _notificationStorageKey(_UserNotificationItem item) {
    if (item.payload['notification_key'] != null) {
      return (item.payload['notification_key'] ?? '').toString();
    }

    final id = (item.payload['id'] ??
            item.payload['event_id'] ??
            item.payload['backendSpotId'] ??
            item.payload['entity_id'] ??
            item.payload['spot_key'] ??
            '')
        .toString();
    return '${item.type}|$id|${item.startsAt.toUtc().toIso8601String()}';
  }

  bool _isNotificationRead(_UserNotificationItem item) {
    return _readNotificationKeys.contains(_notificationStorageKey(item));
  }

  bool get _hasUnreadNotifications {
    return _notifications.any((item) => !_isNotificationRead(item));
  }

  Future<void> _markNotificationAsRead(_UserNotificationItem item) async {
    final key = _notificationStorageKey(item);
    if (_readNotificationKeys.contains(key)) return;

    final nextKeys = {..._readNotificationKeys, key};
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
                  tr('notifications'),
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
                      tr('no_upcoming_notifications'),
                      style: const TextStyle(color: Colors.black54),
                    ),
                  )
                else
                  ..._notifications.map(
                    (item) {
                      final rawLines = item.payload['change_lines'];
                      final changeLines = rawLines is List
                          ? List<String>.from(rawLines)
                          : const <String>[];
                      final isChange = item.payload['kind'] == 'change';
                      final isRead = _isNotificationRead(item);
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () async {
                          await _markNotificationAsRead(item);
                          if (!mounted) return;
                          Navigator.pop(context);
                          _openNotificationTarget(item);
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
                                  color: item.type.startsWith('spot')
                                      ? const Color(0xFFEAF2FF)
                                      : const Color(0xFFE9FFF8),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  item.type == 'spot_upcoming'
                                      ? Icons.chat_bubble_outline
                                      : item.type == 'big_event_upcoming'
                                          ? Icons.directions_run
                                          : Icons.edit_note_rounded,
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
                                    if (isChange && changeLines.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      ...changeLines.map(
                                        (line) => Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 2),
                                          child: Text(
                                            line,
                                            style: const TextStyle(
                                              color: Colors.black87,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
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
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openNotificationTarget(_UserNotificationItem item) {
    if (!mounted) return;

    if (item.type == 'spot_upcoming') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const SpotDetailPage(),
          settings: RouteSettings(arguments: item.payload),
        ),
      ).then((_) => _loadNotifications());
      return;
    }

    if (item.type == 'big_event_upcoming') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JoinedEventDetailPage(event: item.payload),
        ),
      ).then((_) => _loadNotifications());
      return;
    }

    final payload = item.payload['payload'] is Map
        ? Map<String, dynamic>.from(item.payload['payload'] as Map)
        : <String, dynamic>{};
    final innerType = (item.payload['type'] ?? '').toString();
    if (innerType == 'spot') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const SpotDetailPage(),
          settings: RouteSettings(arguments: payload),
        ),
      ).then((_) => _loadNotifications());
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JoinedEventDetailPage(event: payload),
      ),
    ).then((_) => _loadNotifications());
  }

  Future<void> _openLanguageMenu() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        final current = UserLocaleController.languageCode.value;

        Widget tile(String code) {
          final isSelected = current == code;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? const Color(0xFF00C9A7) : Colors.black45,
            ),
            title: Text(UserStrings.languageLabel(code)),
            onTap: () => Navigator.pop(context, code),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('select_language'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                tile('th'),
                tile('en'),
                tile('zh'),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null) return;
    await UserLocaleController.setLanguage(selected);
  }

  Future<void> _openAccountMenu() async {
    final action = await showModalBottomSheet<String>(
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
                  tr('account'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: Text(tr('user_info')),
                  onTap: () => Navigator.pop(context, "profile"),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.language),
                  title: Text(tr('language')),
                  trailing: Text(
                    UserStrings.languageLabel(
                      UserLocaleController.languageCode.value,
                    ),
                    style: const TextStyle(color: Colors.black54),
                  ),
                  onTap: () => Navigator.pop(context, "language"),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout),
                  title: Text(tr('logout')),
                  onTap: () => Navigator.pop(context, "logout"),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == "profile") {
      Navigator.pushNamed(context, AppRoutes.userProfile);
      return;
    }
    if (action == "language") {
      await _openLanguageMenu();
      return;
    }
    if (action == "logout") {
      await SessionService.clearSession();
      await AdminSessionService.clearSession();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.adminLogin,
        (route) => false,
        arguments: const {
          "isSignUp": false,
          "selectedRole": "user",
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingAccountState) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFF),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_accountState?.isBlocked == true) {
      return _buildBlockedHome();
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // =========================
              // TOP HEADER (Search)
              // =========================
              Container(
                color: const Color(0xFF00C9A7),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: _openAccountMenu,
                      child: const CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white,
                        child: Icon(Icons.person, color: Color(0xFF00C9A7)),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () =>
                          Navigator.pushNamed(context, AppRoutes.userBooking)
                              .then((_) => _loadHomeSummary()),
                      icon: const Icon(
                        Icons.favorite,
                        color: Colors.white,
                        size: 28,
                      ),
                      tooltip: tr('booking'),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _openNotifications,
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            const Center(
                              child: Icon(
                                Icons.notifications_none_rounded,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                            if (_hasUnreadNotifications)
                              Positioned(
                                top: 2,
                                left: 2,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF3B30),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: const Color(0xFF00C9A7),
                                      width: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // =========================
              // ✅ BIGEVENT AD (FULL WIDTH)
              // =========================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildBigEventPromoBanner(),
              ),

              const SizedBox(height: 10),

              // =========================
              // ✅ DISTANCE/POINTS (FULL WIDTH UNDER AD)
              // =========================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: Image.asset(
                          AppAssets.user_icons_wincup,
                          fit: BoxFit.contain,
                          alignment: Alignment.topCenter,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.emoji_events, size: 40),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            final totalKm =
                                (_homeSummary?.totalKm ?? 0).toStringAsFixed(1);
                            final completedDistanceText = '$totalKm KM';
                            final completedCount =
                                (_homeSummary?.completedCount ?? 0).toString();
                            final unrecorded =
                                (_homeSummary?.unrecordedCount ?? 0).toString();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  tr('you_did_it'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                _StatLine(
                                  label: tr('completed_distance'),
                                  value: completedDistanceText,
                                ),
                                _StatLine(
                                  label: tr('completed_events'),
                                  value: completedCount,
                                ),
                                _StatLine(
                                  label: tr('unrecorded'),
                                  value: unrecorded,
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // =========================
              // GRID BUTTONS (Spot / Big Event)
              // =========================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: _gridButton(
                        color: const Color(0xFFBFEFE7),
                        icon: Icons.chat_bubble_outline,
                        label: UserStrings.spotTerm,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.userSpot,
                        ).then((_) => _loadHomeSummary()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _gridButton(
                        color: const Color(0xFFFFF0A8),
                        icon: Icons.directions_run,
                        label: UserStrings.bigEventTerm,
                        onTap: () => Navigator.pushNamed(
                          context,
                          AppRoutes.userBigEvent,
                        ).then((_) => _loadHomeSummary()),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // =========================
              // LIST BUTTONS
              // =========================
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _listButton(
                      color: const Color(0xFFE7C7FF),
                      imagePath: AppAssets.user_icons_createevent,
                      text: tr('create_spot'),
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.userMySpot,
                      ).then((_) => _loadHomeSummary()),
                    ),
                    const SizedBox(height: 12),
                    _listButton(
                      color: const Color(0xFF9FA1FF),
                      imagePath: AppAssets.user_icons_myevent,
                      text: tr('spot_joined'),
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.userJoinedSpot,
                      ).then((_) => _loadHomeSummary()),
                    ),
                    const SizedBox(height: 12),
                    _listButton(
                      color: const Color(0xFFDDEAFB),
                      imagePath: AppAssets.user_icons_joinedevent,
                      text: tr('big_event_joined_receipt'),
                      onTap: () => Navigator.pushNamed(
                        context,
                        AppRoutes.userJoinedEvent,
                      ).then((_) => _loadHomeSummary()),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gridButton({
    required Color color,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 90,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: Colors.black87),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _listButton({
    required Color color,
    required String imagePath,
    required String text,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 86,
        decoration: BoxDecoration(
          color: color.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
        ),
        child: Row(
          children: [
            const SizedBox(width: 14),
            Container(
              width: 62,
              height: 62,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12),
              ),
              child: Image.asset(
                imagePath,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.image_not_supported),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 14),
          ],
        ),
      ),
    );
  }
}

class _PromoNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _PromoNavButton({
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

class _UserNotificationItem {
  final String title;
  final String subtitle;
  final String type;
  final DateTime startsAt;
  final Map<String, dynamic> payload;

  const _UserNotificationItem({
    required this.title,
    required this.subtitle,
    required this.type,
    required this.startsAt,
    required this.payload,
  });
}

class _StatLine extends StatelessWidget {
  final String label;
  final String value;

  const _StatLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
