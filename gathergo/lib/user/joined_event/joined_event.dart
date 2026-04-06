import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app_routes.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/payment_booking_status.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';
import '../services/activity_completion_service.dart';
import '../utils/activity_expiry.dart';
import '../../widgets/common/app_nav_bar.dart';
import '../../widgets/common/event_list_card.dart';
import 'joined_event_detail_page.dart';

class JoinedEventPage extends StatefulWidget {
  const JoinedEventPage({super.key});

  @override
  State<JoinedEventPage> createState() => _JoinedEventPageState();
}

class _JoinedEventPageState extends State<JoinedEventPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _joinedBigEvents = [];
  List<Map<String, dynamic>> _allJoinedBigEvents = [];
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    _loadJoinedEvents();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  String _expiredLabel() {
    switch (UserLocaleController.languageCode.value) {
      case 'th':
        return 'หมดอายุ';
      case 'zh':
        return '已过期';
      default:
        return 'EXPIRED';
    }
  }

  String _bigEventHistoryTitle() {
    switch (UserLocaleController.languageCode.value) {
      case 'th':
        return '${UserStrings.bigEventTerm} ที่เข้าร่วม - ประวัติ';
      case 'zh':
        return '已参加 ${UserStrings.bigEventTerm} 历史';
      default:
        return '${UserStrings.bigEventTerm} Joined History';
    }
  }

  String _bigEventHistoryEmpty() {
    switch (UserLocaleController.languageCode.value) {
      case 'th':
        return 'ยังไม่มีประวัติ${UserStrings.bigEventTerm}ที่เข้าร่วม';
      case 'zh':
        return '还没有已参加活动历史';
      default:
        return 'No joined event history yet';
    }
  }

  Future<void> _loadJoinedEvents() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final userId = await SessionService.getCurrentUserId();
      if (userId == null || userId <= 0) {
        throw Exception(tr('no_active_user_session'));
      }
      final uri = Uri.parse(
          '${ConfigService.getBaseUrl()}/api/user/joined-events?user_id=$userId');
      final res = await http.get(uri, headers: {
        'Accept': 'application/json',
        'x-user-id': userId.toString(),
      });
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw Exception('Invalid joined-events response');
      }
      final items = decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .map(_mapBackendJoinedEvent)
          .toList();
      final visibleItems =
          items.where(_isActiveJoinedEvent).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _allJoinedBigEvents = items;
        _joinedBigEvents = visibleItems;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    super.dispose();
  }

  String _composeDistrictProvince(String district, String province) {
    if (district.isNotEmpty && province.isNotEmpty) {
      return '$province, $district';
    }
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;
    return '';
  }

  String _eventLocationLabel(Map<String, dynamic> event) {
    final district = (event['district'] ??
            event['district_name'] ??
            event['amphoe'] ??
            event['city'] ??
            '')
        .toString()
        .trim();
    final province = (event['province'] ?? '').toString().trim();
    final districtProvince = _composeDistrictProvince(district, province);
    if (districtProvince.isNotEmpty) return districtProvince;

    final meetingPoint = (event['meeting_point'] ?? '').toString().trim();
    if (meetingPoint.isNotEmpty &&
        !RegExp(r'lat|lng|latitude|longitude', caseSensitive: false)
            .hasMatch(meetingPoint)) {
      return meetingPoint;
    }

    final location = (event['location'] ?? '').toString().trim();
    if (location.isNotEmpty &&
        !RegExp(r'lat|lng|latitude|longitude', caseSensitive: false)
            .hasMatch(location)) {
      return location;
    }

    return '-';
  }

  Map<String, dynamic> _mapBackendJoinedEvent(Map<String, dynamic> e) {
    final eventId = int.tryParse((e["id"] ?? "").toString()) ?? 0;
    final bookingId =
        int.tryParse((e["booking_id"] ?? e["bookingId"] ?? "").toString()) ?? 0;
    final location = _eventLocationLabel(e);
    final pendingKey = bookingId > 0
        ? "${eventId}_$bookingId"
        : "big_event_joined|$eventId|${e["title"]}|${e["start_at"]}|$location";
    return {
      ...e,
      "eventId": eventId,
      "bookingId": bookingId,
      "taskType": "big_event_joined",
      "pendingKey": pendingKey,
      "title": (e["title"] ?? "-").toString(),
      "date": (e["start_at"] ?? e["date"] ?? "-").toString(),
      "location": location,
      "meeting_point": (e["meeting_point"] ?? "").toString(),
      "city": (e["city"] ?? "").toString(),
      "province": (e["province"] ?? "").toString(),
      "total_distance": (e["total_distance"] ?? "0").toString(),
      "shirt_size": (e["shirt_size"] ?? "").toString(),
      "completed_at": (e["completed_at"] ?? "").toString(),
      "completed_distance_km": (e["completed_distance_km"] ?? "").toString(),
      "image": (e["cover_url"] ?? "").toString().trim().isEmpty
          ? "assets/images/user/events/event1.png"
          : (e["cover_url"] ?? "").toString(),
      "source_type": "BIG_EVENT",
      "status": PaymentBookingStatus.isPaymentSuccessful(e["payment_status"])
          ? "PAID"
          : "JOINED",
    };
  }

  bool _isDbCompleted(Map<String, dynamic> event) {
    final completedAt = (event["completed_at"] ?? "").toString().trim();
    return completedAt.isNotEmpty;
  }

  bool _isExpired(Map<String, dynamic> event) {
    return ActivityExpiry.isExpiredAfterGrace(event);
  }

  bool _isActiveJoinedEvent(Map<String, dynamic> event) {
    return !_isDbCompleted(event) && !_isExpired(event);
  }

  Future<void> _markCompleted(Map<String, dynamic> event) async {
    if (_completing) return;
    setState(() => _completing = true);
    bool savedToDb = false;
    try {
      savedToDb = await ActivityCompletionService.completeBigEvent(event);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(tr('save_failed', params: {'error': e.toString()})),
            ),
          );
      }
    }
    if (!savedToDb) {
      if (mounted) {
        setState(() => _completing = false);
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                tr('save_failed',
                    params: {'error': 'big_event_completion_not_saved'}),
              ),
            ),
          );
      }
      return;
    }
    await _loadJoinedEvents();
    if (!mounted) return;
    setState(() => _completing = false);
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(UserStrings.text('completed'))),
      );
  }

  List<Map<String, dynamic>> _historyEvents() {
    return _allJoinedBigEvents
        .where((event) => _isDbCompleted(event) || _isExpired(event))
        .map((event) => <String, dynamic>{
              ...Map<String, dynamic>.from(event),
              'historyStatus':
                  _isDbCompleted(event) ? 'completed' : 'expired',
            })
        .toList(growable: false);
  }

  Future<void> _openHistory() async {
    await _loadJoinedEvents();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _JoinedEventHistoryPage(
          title: _bigEventHistoryTitle(),
          emptyText: _bigEventHistoryEmpty(),
          expiredLabel: _expiredLabel(),
          items: _historyEvents(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: SafeArea(
        child: Column(
          children: [
            AppNavBar(
              title: tr('big_event_joined_receipt'),
              showBack: true,
              actions: [
                IconButton(
                  onPressed: _openHistory,
                  icon: const Icon(Icons.history_rounded),
                  color: Colors.black,
                  tooltip: _bigEventHistoryTitle(),
                ),
              ],
              onBack: () => Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.userHome,
                (route) => false,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  tr('load_failed', params: {'error': _error!}),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                ElevatedButton(
                                  onPressed: _loadJoinedEvents,
                                  child: Text(tr('retry')),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _joinedBigEvents.isEmpty
                          ? Center(
                              child: Text(tr('no_completed_joined_events_yet')),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadJoinedEvents,
                              child: ListView.separated(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                itemCount: _joinedBigEvents.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final event = _joinedBigEvents[index];
                                  return _JoinedEventCard(
                                    event: event,
                                    onComplete: () => _markCompleted(event),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => JoinedEventDetailPage(
                                            event: event,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinedEventHistoryPage extends StatelessWidget {
  final String title;
  final String emptyText;
  final String expiredLabel;
  final List<Map<String, dynamic>> items;

  const _JoinedEventHistoryPage({
    required this.title,
    required this.emptyText,
    required this.expiredLabel,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: SafeArea(
        child: Column(
          children: [
            AppNavBar(
              title: title,
              showBack: true,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text(emptyText))
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final statusOverride =
                            (item['historyStatus'] ?? '').toString() ==
                                    'expired'
                                ? expiredLabel
                                : UserStrings.text('completed');
                        return _JoinedEventCard(
                          event: item,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    JoinedEventDetailPage(event: item),
                              ),
                            );
                          },
                          onComplete: null,
                          statusOverride: statusOverride,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinedEventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback onTap;
  final Future<void> Function()? onComplete;
  final String? statusOverride;

  const _JoinedEventCard({
    required this.event,
    required this.onTap,
    this.onComplete,
    this.statusOverride,
  });

  String _prettyDateOnly(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return iso;
    }
  }

  String _prettyTimeOnly(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int n) => n.toString().padLeft(2, "0");
      return '${two(dt.hour)}:${two(dt.minute)}';
    } catch (_) {
      return '-';
    }
  }

  Widget _buildImage(String image, String imageBase64) {
    if (imageBase64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(imageBase64),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            color: const Color(0xFFF1F4FA),
            alignment: Alignment.center,
            child: const Icon(Icons.image_not_supported),
          ),
        );
      } catch (_) {}
    }

    final isNet = image.startsWith("http://") || image.startsWith("https://");
    if (isNet) {
      return Image.network(
        image,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFFF1F4FA),
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported),
        ),
      );
    }

    return Image.asset(
      image,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFFF1F4FA),
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    String distanceWithKm(String value) {
      final normalized = value.trim();
      if (normalized.isEmpty || normalized == '-') return '-';
      return normalized.toUpperCase().contains('KM')
          ? normalized
          : '$normalized KM';
    }

    String computeTotalDistanceLabel() {
      final rawCompleted =
          (event["completed_distance_km"] ?? "").toString().trim();
      final parsedCompleted = double.tryParse(rawCompleted);
      if (parsedCompleted != null && parsedCompleted >= 0) {
        final text = parsedCompleted == parsedCompleted.roundToDouble()
            ? parsedCompleted.toStringAsFixed(0)
            : parsedCompleted.toStringAsFixed(3);
        return distanceWithKm(text);
      }

      final rawTotal = (event["total_distance"] ?? "").toString().trim();
      final parsedTotal = double.tryParse(rawTotal);
      if (parsedTotal != null && parsedTotal > 0) {
        final text = parsedTotal == parsedTotal.roundToDouble()
            ? parsedTotal.toStringAsFixed(0)
            : parsedTotal.toStringAsFixed(3);
        return distanceWithKm(text);
      }

      final perRound = double.tryParse(
        (event["kmPerRound"] ?? event["km_per_round"] ?? "").toString().trim(),
      );
      final round = double.tryParse(
        (event["round"] ?? event["round_count"] ?? "").toString().trim(),
      );
      if (perRound != null && perRound > 0 && round != null && round > 0) {
        final total = perRound * round;
        final text = total == total.roundToDouble()
            ? total.toStringAsFixed(0)
            : total.toStringAsFixed(3);
        return distanceWithKm(text);
      }

      if (rawTotal.isNotEmpty && rawTotal != '-') {
        return distanceWithKm(rawTotal);
      }
      return '-';
    }

    final title = (event["title"] ?? "-").toString();
    final date = (event["date"] ?? "-").toString();
    final location = (event["location"] ?? "-").toString();
    final totalDistanceLabel = computeTotalDistanceLabel();
    final image = (event["image"] ?? "").toString();
    final imageBase64 = (event["imageBase64"] ?? "").toString();
    final statusKey = (event["status"] ?? "PAID").toString().toUpperCase();
    final isExpiredHistory =
        (event["historyStatus"] ?? "").toString() == 'expired';
    final status = statusOverride ??
        switch (statusKey) {
          'PAID' => UserStrings.text('paid'),
          'COMPLETED' => UserStrings.text('completed'),
          _ => statusKey,
        };
    final isSpot =
        (event["source_type"] ?? "").toString().toUpperCase() == "SPOT";
    final String rawPrice = (event["payment_amount"] ??
            event["amount"] ??
            event["fee"] ??
            event["price"] ??
            "0")
        .toString()
        .trim();
    final String currency =
        (event["currency"] ?? event["fee_currency"] ?? "THB").toString();
    final num? priceValue = num.tryParse(rawPrice);
    final String priceLabel = priceValue == null
        ? '$rawPrice $currency'
        : '${priceValue % 1 == 0 ? priceValue.toStringAsFixed(0) : priceValue.toStringAsFixed(2)} $currency';

    return EventListCard(
      onTap: onTap,
      image: _buildImage(image, imageBase64),
      imageFooter: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.black),
            ),
            child: Text(
              priceLabel,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.black,
              ),
            ),
          ),
          if (onComplete != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onComplete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00C9A7),
                  side: const BorderSide(
                    color: Color(0xFF00C9A7),
                    width: 1.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'OK',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
      title: title,
      badge: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isExpiredHistory
              ? const Color(0xFFFFF1F0)
              : (isSpot ? const Color(0xFFEFF3FF) : const Color(0xFFE9FFF8)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          status,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: isExpiredHistory
                ? const Color(0xFFD92D20)
                : (isSpot ? const Color(0xFF2C5CC5) : const Color(0xFF00C9A7)),
          ),
        ),
      ),
      chips: [
        UserStrings.text('date_with_value',
            params: {'value': date == "-" ? "-" : _prettyDateOnly(date)}),
        UserStrings.text('time_with_value',
            params: {'value': date == "-" ? "-" : _prettyTimeOnly(date)}),
        UserStrings.text('location_with_value', params: {'value': location}),
        UserStrings.text('total_with_value',
            params: {'value': totalDistanceLabel}),
      ],
    );
  }
}
