import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app_routes.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/spot_map_launcher.dart';
import '../../widgets/common/app_nav_bar.dart';
import '../data/mock_store.dart';
import '../data/user_event_store.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';
import '../services/activity_completion_service.dart';
import '../utils/activity_expiry.dart';

class JoinedSpotPage extends StatefulWidget {
  const JoinedSpotPage({super.key});

  @override
  State<JoinedSpotPage> createState() => _JoinedSpotPageState();
}

class _JoinedSpotPageState extends State<JoinedSpotPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _spots = [];
  List<Map<String, dynamic>> _allSpots = [];
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    _searchCtrl.addListener(_handleSearchChanged);
    _fetchJoinedSpots();
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _searchCtrl
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
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

  String _spotHistoryTitle() {
    switch (UserLocaleController.languageCode.value) {
      case 'th':
        return 'ประวัติ Spot ที่เข้าร่วม';
      case 'zh':
        return '已加入 Spot 历史';
      default:
        return 'Spot Joined History';
    }
  }

  String _spotHistoryEmpty() {
    switch (UserLocaleController.languageCode.value) {
      case 'th':
        return 'ยังไม่มีประวัติ Spot ที่เข้าร่วม';
      case 'zh':
        return '还没有已加入 Spot 的历史记录';
      default:
        return 'No spot joined history yet';
    }
  }

  List<_LeaveReasonOption> get _leaveReasons => [
        _LeaveReasonOption(
            'SCHEDULE_CONFLICT', tr('leave_reason_schedule_conflict')),
        _LeaveReasonOption(
            'LOCATION_TOO_FAR', tr('leave_reason_location_too_far')),
        _LeaveReasonOption(
            'NO_LONGER_INTERESTED', tr('leave_reason_no_longer_interested')),
        _LeaveReasonOption('HEALTH_INJURY', tr('leave_reason_health_injury')),
        _LeaveReasonOption('FOUND_ANOTHER_ACTIVITY',
            tr('leave_reason_found_another_activity')),
        _LeaveReasonOption('HOST_PROBLEM_PARTICIPANTS',
            tr('leave_reason_host_problem_participants')),
        _LeaveReasonOption('SAFETY_CONCERN', tr('leave_reason_safety_concern')),
        _LeaveReasonOption('OTHER', tr('other')),
      ];

  void _handleSearchChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Map<String, dynamic> _pendingSpotPayload(Map<String, dynamic> spot) {
    final payload = Map<String, dynamic>.from(spot);
    final pendingKey = UserEventStore.spotPendingKey(
      taskType: 'spot_joined',
      title: (payload['title'] ?? 'Spot').toString(),
      date: (payload['date'] ?? '').toString(),
      time: (payload['time'] ?? '').toString(),
      location: (payload['location'] ?? '').toString(),
    );
    payload['pendingKey'] = pendingKey;
    payload['taskType'] = 'spot_joined';
    return payload;
  }

  String _formatSpotTotalDistance(Map<String, dynamic> row) {
    final direct =
        double.tryParse((row['total_distance'] ?? '').toString().trim());
    if (direct != null && direct >= 0) {
      return direct == direct.roundToDouble()
          ? direct.toStringAsFixed(0)
          : direct.toStringAsFixed(2);
    }

    final kmPerRound =
        double.tryParse((row['km_per_round'] ?? '').toString().trim()) ?? 0;
    final round =
        double.tryParse((row['round_count'] ?? '').toString().trim()) ?? 0;
    final total = kmPerRound * round;
    return total == total.roundToDouble()
        ? total.toStringAsFixed(0)
        : total.toStringAsFixed(2);
  }

  Map<String, dynamic> _mapBackendSpot(Map<String, dynamic> row) {
    final kmPerRound = (row["km_per_round"] ?? "").toString();
    final round = (row["round_count"] ?? "").toString();
    final totalDistance = _formatSpotTotalDistance(row);
    final imageBase64 = (row["image_base64"] ?? "").toString();
    final imageUrl = (row["image_url"] ?? "").toString().trim();
    final creatorName = (row["creator_name"] ?? "User").toString();
    final creatorUserId = (row["created_by_user_id"] ?? "").toString();
    final eventDate = (row["event_date"] ?? "").toString();
    final eventTime = (row["event_time"] ?? "").toString();
    final province = (row["province"] ?? row["changwat"] ?? "").toString();
    final district =
        (row["district"] ?? row["amphoe"] ?? row["district_name"] ?? "")
            .toString();

    return {
      "backendSpotId": row["id"],
      "spotKey": (row["spot_key"] ?? "").toString(),
      "spot_key": (row["spot_key"] ?? "").toString(),
      "title": (row["title"] ?? "").toString(),
      "description": (row["description"] ?? "").toString(),
      "location": (row["location"] ?? "").toString(),
      "locationLink": (row["location_link"] ?? "").toString(),
      "location_lat": row["location_lat"],
      "location_lng": row["location_lng"],
      "locationLat": row["location_lat"],
      "locationLng": row["location_lng"],
      "province": province,
      "district": district,
      "date": eventDate,
      "time": eventTime,
      "kmPerRound": kmPerRound,
      "round": round,
      "total_distance": totalDistance,
      "distance": "$totalDistance KM",
      "maxPeople": (row["max_people"] ?? "").toString(),
      "imageBase64": imageBase64,
      "image": imageUrl.isNotEmpty ? ConfigService.resolveUrl(imageUrl) : '',
      "host": creatorName,
      "hostName": creatorName,
      "creatorName": creatorName,
      "creatorUserId": creatorUserId,
      "creatorRole": (row["creator_role"] ?? "user").toString(),
      "status": (row["status"] ?? "completed").toString(),
      "completed_at": (row["completed_at"] ?? "").toString(),
      "completed_distance_km": (row["completed_distance_km"] ?? "").toString(),
      "isJoined": true,
    };
  }

  bool _isDbCompleted(Map<String, dynamic> spot) {
    final completedAt = (spot["completed_at"] ?? "").toString().trim();
    return completedAt.isNotEmpty;
  }

  bool _isExpired(Map<String, dynamic> spot) {
    return ActivityExpiry.isExpiredAfterGrace(spot);
  }

  bool _isActiveSpot(Map<String, dynamic> spot) {
    return !_isDbCompleted(spot) && !_isExpired(spot);
  }

  Future<void> _fetchJoinedSpots() async {
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
          "${ConfigService.getBaseUrl()}/api/spots/joined?user_id=$userId");
      final res = await http.get(
        uri,
        headers: {
          "Accept": "application/json",
          "x-user-id": userId.toString(),
        },
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        throw Exception("HTTP ${res.statusCode}: ${res.body}");
      }
      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw Exception("Invalid response format");
      }
      final rows = decoded
          .map<Map<String, dynamic>>(
              (e) => _mapBackendSpot(Map<String, dynamic>.from(e as Map)))
          .toList();
      final visibleRows =
          rows.where(_isActiveSpot).toList(growable: false);
      if (!mounted) return;
      setState(() {
        _allSpots = rows;
        _spots = visibleRows;
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

  Future<void> _leaveSpot(
    Map<String, dynamic> spot, {
    required _LeaveReasonOption reason,
    String? customReasonText,
  }) async {
    final userId = await SessionService.getCurrentUserId();
    final spotId = int.tryParse((spot["backendSpotId"] ?? "").toString());
    if (userId == null || userId <= 0 || spotId == null || spotId <= 0) {
      _showSnack(tr('cannot_leave_this_spot'));
      return;
    }

    try {
      final uri =
          Uri.parse("${ConfigService.getBaseUrl()}/api/spots/$spotId/leave");
      final res = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "x-user-id": userId.toString(),
        },
        body: jsonEncode({
          "user_id": userId,
          "reason_code": reason.code,
          if ((customReasonText ?? "").trim().isNotEmpty)
            "reason_text": customReasonText!.trim(),
        }),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception("HTTP ${res.statusCode}: ${res.body}");
      }

      MockStore.unjoinSpot(spot);
      if (!mounted) return;
      await _fetchJoinedSpots();
      if (!mounted) return;
      _showSnack(tr('left_spot_successfully'));
    } catch (e) {
      _showSnack(tr('leave_failed', params: {'error': e.toString()}));
    }
  }

  Future<void> _openLeaveFlow(Map<String, dynamic> spot) async {
    final payload = await showModalBottomSheet<_LeaveReasonPayload>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LeaveReasonSheet(reasons: _leaveReasons),
    );
    if (payload == null) return;
    await _leaveSpot(
      spot,
      reason: payload.reason,
      customReasonText: payload.customReasonText,
    );
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _markSpotCompleted(Map<String, dynamic> spot) async {
    if (_completing) return;
    setState(() => _completing = true);
    final payload = _pendingSpotPayload(spot);
    bool savedToDb = false;
    try {
      savedToDb = await ActivityCompletionService.completeSpot(payload);
    } catch (e) {
      if (mounted) {
        _showSnack(tr('save_failed', params: {'error': e.toString()}));
      }
    }
    if (!savedToDb) {
      if (mounted) {
        setState(() => _completing = false);
        _showSnack(
            tr('save_failed', params: {'error': 'completion_not_saved'}));
      }
      return;
    }
    await _fetchJoinedSpots();
    if (!mounted) return;
    setState(() => _completing = false);
    _showSnack(UserStrings.text('completed'));
  }

  List<Map<String, dynamic>> _filteredSpots() {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _spots;

    return _spots.where((spot) {
      final fields = [
        (spot["title"] ?? "").toString(),
        (spot["host"] ?? "").toString(),
        (spot["date"] ?? "").toString(),
        (spot["time"] ?? "").toString(),
        (spot["location"] ?? "").toString(),
      ];

      return fields.any((value) => value.toLowerCase().contains(query));
    }).toList();
  }

  List<Map<String, dynamic>> _historySpots() {
    return _allSpots
        .where((spot) => _isDbCompleted(spot) || _isExpired(spot))
        .map((spot) => <String, dynamic>{
              ...Map<String, dynamic>.from(spot),
              'taskType': 'spot_joined',
              'pendingKey':
                  (_pendingSpotPayload(spot)['pendingKey'] ?? '').toString(),
              'historyStatus': _isDbCompleted(spot) ? 'completed' : 'expired',
            })
        .toList(growable: false);
  }

  Future<void> _openHistory() async {
    await _fetchJoinedSpots();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _SpotJoinedHistoryPage(
          title: _spotHistoryTitle(),
          emptyText: _spotHistoryEmpty(),
          expiredLabel: _expiredLabel(),
          items: _historySpots(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredSpots = _filteredSpots();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: SafeArea(
        child: Column(
          children: [
            AppNavBar(
              title: tr('spot_joined'),
              showBack: true,
              backgroundColor: const Color(0xFF9FA1FF),
              foregroundColor: Colors.black,
              actions: [
                IconButton(
                  onPressed: _openHistory,
                  icon: const Icon(Icons.history_rounded),
                  color: Colors.black,
                  tooltip: _spotHistoryTitle(),
                ),
              ],
              onBack: () => Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.userHome,
                (route) => false,
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFD9E0EA)),
                ),
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: tr('search'),
                    prefixIcon: Icon(Icons.search, color: Colors.grey),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tr('load_failed', params: {'error': _error!}),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              ElevatedButton(
                                onPressed: _fetchJoinedSpots,
                                child: Text(tr('retry')),
                              ),
                            ],
                          ),
                        )
                      : filteredSpots.isEmpty
                          ? Center(
                              child: Text(
                                _searchCtrl.text.trim().isEmpty
                                    ? tr('no_joined_spots')
                                    : tr('no_matching_spots'),
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _fetchJoinedSpots,
                              child: ListView.separated(
                                padding: const EdgeInsets.only(bottom: 16),
                                itemCount: filteredSpots.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 12),
                                itemBuilder: (context, index) {
                                  final spot = filteredSpots[index];
                                  return _JoinedSpotItem(
                                    spot: spot,
                                    onLeave: () => _openLeaveFlow(spot),
                                    onComplete: () => _markSpotCompleted(spot),
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

class _SpotJoinedHistoryPage extends StatelessWidget {
  final String title;
  final String emptyText;
  final String expiredLabel;
  final List<Map<String, dynamic>> items;

  const _SpotJoinedHistoryPage({
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
              backgroundColor: const Color(0xFF9FA1FF),
              foregroundColor: Colors.black,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text(emptyText))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _SpotHistoryItem(
                          item: item,
                          expiredLabel: expiredLabel,
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

class _SpotHistoryItem extends StatelessWidget {
  final Map<String, dynamic> item;
  final String expiredLabel;

  const _SpotHistoryItem({
    required this.item,
    required this.expiredLabel,
  });

  String _statusLabel() {
    final status = (item['historyStatus'] ?? '').toString();
    if (status == 'expired') return expiredLabel;
    return UserStrings.text('completed');
  }

  Color _statusColor() {
    final status = (item['historyStatus'] ?? '').toString();
    return status == 'expired'
        ? const Color(0xFFD92D20)
        : const Color(0xFF00C9A7);
  }

  String _distanceWithKm(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') return '-';
    return normalized.toUpperCase().contains('KM')
        ? normalized
        : '$normalized KM';
  }

  String _totalKmLabel() {
    final rawCompleted =
        (item["completed_distance_km"] ?? "").toString().trim();
    final parsedCompleted = double.tryParse(rawCompleted);
    if (parsedCompleted != null && parsedCompleted >= 0) {
      final text = parsedCompleted == parsedCompleted.roundToDouble()
          ? parsedCompleted.toStringAsFixed(0)
          : parsedCompleted.toStringAsFixed(3);
      return _distanceWithKm(text);
    }

    final rawTotal = (item["total_distance"] ?? "").toString().trim();
    final parsedTotal = double.tryParse(rawTotal);
    if (parsedTotal != null && parsedTotal > 0) {
      final text = parsedTotal == parsedTotal.roundToDouble()
          ? parsedTotal.toStringAsFixed(0)
          : parsedTotal.toStringAsFixed(2);
      return _distanceWithKm(text);
    }
    final kmPerRound = double.tryParse(
      (item["kmPerRound"] ?? item["km_per_round"] ?? "").toString().trim(),
    );
    final round = double.tryParse(
      (item["round"] ?? item["round_count"] ?? "").toString().trim(),
    );
    if (kmPerRound != null && round != null) {
      final total = kmPerRound * round;
      final text = total == total.roundToDouble()
          ? total.toStringAsFixed(0)
          : total.toStringAsFixed(2);
      return _distanceWithKm(text);
    }
    return '-';
  }

  void _openDetail(BuildContext context) {
    Navigator.pushNamed(
      context,
      AppRoutes.userSpotDetail,
      arguments: item,
    );
  }

  Widget _buildSpotImage() {
    final b64 = (item["imageBase64"] ?? "").toString().trim();
    if (b64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(b64),
          width: 92,
          height: 92,
          fit: BoxFit.cover,
        );
      } catch (_) {}
    }
    final image = (item["image"] ?? "").toString().trim();
    if (image.isEmpty) {
      return Container(
        width: 92,
        height: 92,
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported),
      );
    }
    final isNet = image.startsWith("http://") || image.startsWith("https://");
    if (isNet) {
      return Image.network(
        image,
        width: 92,
        height: 92,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 92,
          height: 92,
          color: Colors.black12,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported),
        ),
      );
    }
    return Image.asset(
      image,
      width: 92,
      height: 92,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: 92,
        height: 92,
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (item["title"] ?? UserStrings.spotTerm).toString();
    final date = (item["date"] ?? "-").toString();
    final time = (item["time"] ?? "-").toString();
    final location = (item["location"] ?? "-").toString();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _openDetail(context),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildSpotImage(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _statusColor().withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _statusLabel(),
                              style: TextStyle(
                                color: _statusColor(),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _HistoryChip(UserStrings.text('date_with_value',
                              params: {'value': date})),
                          _HistoryChip(UserStrings.text('time_with_value',
                              params: {'value': time})),
                          _HistoryChip(UserStrings.text('location_with_value',
                              params: {'value': location})),
                          _HistoryChip(UserStrings.text('total_with_value',
                              params: {'value': _totalKmLabel()})),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryChip extends StatelessWidget {
  final String text;

  const _HistoryChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black87,
        ),
      ),
    );
  }
}

class _JoinedSpotItem extends StatelessWidget {
  final Map<String, dynamic> spot;
  final Future<void> Function() onLeave;
  final Future<void> Function() onComplete;

  const _JoinedSpotItem({
    required this.spot,
    required this.onLeave,
    required this.onComplete,
  });

  String _spotKey() {
    final explicit =
        (spot["spotKey"] ?? spot["spot_key"] ?? "").toString().trim();
    if (explicit.isNotEmpty) return explicit;
    final stableId =
        (spot["backendSpotId"] ?? spot["id"] ?? "").toString().trim();
    if (stableId.isNotEmpty) return 'spot:$stableId';
    final title = (spot["title"] ?? "").toString().trim().toLowerCase();
    final date = (spot["date"] ?? "").toString().trim().toLowerCase();
    final time = (spot["time"] ?? "").toString().trim().toLowerCase();
    final location = (spot["location"] ?? "").toString().trim().toLowerCase();
    return "$title|$date|$time|$location";
  }

  String _totalKmLabel() {
    final completedKm = double.tryParse(
          (spot["completed_distance_km"] ?? "").toString(),
        ) ??
        -1;
    if (completedKm >= 0) {
      final value = completedKm % 1 == 0
          ? completedKm.toStringAsFixed(0)
          : completedKm.toStringAsFixed(3);
      return UserStrings.text('total_with_value',
          params: {'value': '$value KM'});
    }

    final kmPerRound = double.tryParse(
          (spot["kmPerRound"] ?? spot["km_per_round"] ?? "").toString(),
        ) ??
        0;
    final round = double.tryParse(
          (spot["round"] ?? spot["round_count"] ?? "").toString(),
        ) ??
        0;
    final total = kmPerRound * round;
    final value =
        total % 1 == 0 ? total.toStringAsFixed(0) : total.toStringAsFixed(2);
    return UserStrings.text('total_with_value', params: {'value': '$value KM'});
  }

  String _shortLocation() {
    final province = (spot["province"] ?? "").toString().trim();
    final district = (spot["district"] ?? "").toString().trim();

    if (province.isNotEmpty && district.isNotEmpty) {
      return '$province, $district';
    }
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;

    final raw = (spot["location"] ?? "").toString().trim();
    if (raw.isEmpty) return "-";

    final parts = raw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    String? foundProvince;
    String? foundDistrict;

    for (final part in parts) {
      final lower = part.toLowerCase();
      if (foundDistrict == null &&
          (lower.startsWith('amphoe ') ||
              lower.startsWith('khet ') ||
              lower.startsWith('district '))) {
        foundDistrict = part;
      }
      if (foundProvince == null &&
          !lower.startsWith('amphoe ') &&
          !lower.startsWith('khet ') &&
          !lower.startsWith('district ') &&
          !lower.startsWith('tambon ') &&
          !lower.startsWith('khwaeng ') &&
          !RegExp(r'^\d').hasMatch(part)) {
        foundProvince = part;
      }
    }

    if (foundProvince != null && foundDistrict != null) {
      return '$foundProvince, $foundDistrict';
    }

    if (parts.length >= 2) {
      return '${parts[parts.length - 1]}, ${parts[parts.length - 2]}';
    }

    return raw;
  }

  Future<void> _openMap(BuildContext context) async {
    final ok = await SpotMapLauncher.open(
      latitude: spot["locationLat"] ?? spot["location_lat"],
      longitude: spot["locationLng"] ?? spot["location_lng"],
      locationText: spot["location"],
    );
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(UserStrings.text('location_not_available'))),
      );
  }

  void _openDetail(BuildContext context) {
    Navigator.pushNamed(
      context,
      AppRoutes.userSpotDetail,
      arguments: spot,
    );
  }

  Widget _buildSpotImage() {
    final b64 = (spot["imageBase64"] ?? "").toString().trim();
    if (b64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(b64),
          width: 92,
          height: 92,
          fit: BoxFit.cover,
        );
      } catch (_) {}
    }
    final image = (spot["image"] ?? "").toString();
    final isNet = image.startsWith("http://") || image.startsWith("https://");
    if (isNet) {
      return Image.network(
        image,
        width: 92,
        height: 92,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 92,
          height: 92,
          color: Colors.black12,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported),
        ),
      );
    }
    return Image.asset(
      image,
      width: 92,
      height: 92,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: 92,
        height: 92,
        color: Colors.black12,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _openDetail(context),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 92,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: _buildSpotImage(),
                            ),
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
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
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (spot["title"] ?? UserStrings.spotTerm)
                                  .toString(),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _infoChip(UserStrings.text('host') +
                                    ': ${(spot["host"] ?? "-").toString()}'),
                                _infoChip(UserStrings.text('date_with_value',
                                    params: {
                                      'value': (spot["date"] ?? "-").toString()
                                    })),
                                _infoChip(UserStrings.text('time_with_value',
                                    params: {
                                      'value': (spot["time"] ?? "-").toString()
                                    })),
                                _infoChip(UserStrings.text(
                                    'location_with_value',
                                    params: {'value': _shortLocation()})),
                                _infoChip(_totalKmLabel()),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _openMap(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(
                        color: Color(0xFF2563EB),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(UserStrings.text('view_map')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      if (ActivityExpiry.isExpiredAfterGrace(spot)) {
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                UserStrings.text(
                                  'chat_room_not_available_for_spot',
                                ),
                              ),
                            ),
                          );
                        return;
                      }
                      final payload = Map<String, dynamic>.from(spot)
                        ..["spotKey"] = _spotKey()
                        ..["spot_key"] = _spotKey();
                      Navigator.pushNamed(
                        context,
                        AppRoutes.userSpotChatGroup,
                        arguments: {"spot": payload},
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(
                        color: Color(0xFF00C9A7),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(UserStrings.text('chat')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onLeave,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(
                        color: Color(0xFFFF4444),
                        width: 1.5,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(UserStrings.text('leave')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _line(String label, dynamic value) {
    return Text(
      "$label: ${value ?? "-"}",
      style: const TextStyle(fontSize: 12.5, color: Colors.black54),
    );
  }

  Widget _infoChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          color: Colors.black87,
        ),
      ),
    );
  }
}

class _LeaveReasonOption {
  final String code;
  final String label;

  const _LeaveReasonOption(this.code, this.label);
}

class _LeaveReasonPayload {
  final _LeaveReasonOption reason;
  final String? customReasonText;

  const _LeaveReasonPayload({
    required this.reason,
    this.customReasonText,
  });
}

class _LeaveReasonSheet extends StatefulWidget {
  final List<_LeaveReasonOption> reasons;

  const _LeaveReasonSheet({required this.reasons});

  @override
  State<_LeaveReasonSheet> createState() => _LeaveReasonSheetState();
}

class _LeaveReasonSheetState extends State<_LeaveReasonSheet> {
  _LeaveReasonOption? _selectedReason;
  final TextEditingController _otherCtrl = TextEditingController();

  bool get _requiresDetails {
    const detailReasonCodes = {
      'HOST_PROBLEM_PARTICIPANTS',
      'SAFETY_CONCERN',
      'OTHER',
    };
    return detailReasonCodes.contains(_selectedReason?.code);
  }

  String get _detailsText => _otherCtrl.text.trim();

  bool get _hasValidDetails => _detailsText.length >= 5;

  String get _detailsHintText {
    switch (_selectedReason?.code) {
      case 'HOST_PROBLEM_PARTICIPANTS':
        return UserStrings.text('please_describe_issue');
      case 'SAFETY_CONCERN':
        return UserStrings.text('please_describe_safety_concern');
      default:
        return UserStrings.text('please_provide_more_details');
    }
  }

  @override
  void dispose() {
    _otherCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _selectedReason;
    if (reason == null) return;
    if (_requiresDetails && !_hasValidDetails) {
      return;
    }
    Navigator.pop(
      context,
      _LeaveReasonPayload(
        reason: reason,
        customReasonText: _requiresDetails ? _detailsText : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, bottomInset + 12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  UserStrings.text('why_are_you_leaving_this_spot'),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  UserStrings.text('feedback_shared_with_admin'),
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 14),
                ...widget.reasons.map(
                  (reason) => RadioListTile<_LeaveReasonOption>(
                    value: reason,
                    groupValue: _selectedReason,
                    contentPadding: EdgeInsets.zero,
                    title: Text(reason.label),
                    onChanged: (value) {
                      setState(() {
                        _selectedReason = value;
                      });
                    },
                  ),
                ),
                if (_requiresDetails) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _otherCtrl,
                    onChanged: (_) => setState(() {}),
                    minLines: 3,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: _detailsHintText,
                      errorText: _detailsText.isEmpty || _hasValidDetails
                          ? null
                          : UserStrings.text(
                              'please_enter_at_least_5_characters'),
                      filled: true,
                      fillColor: const Color(0xFFF5F7FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.black12),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(UserStrings.text('cancel')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _selectedReason == null ||
                                (_requiresDetails && !_hasValidDetails)
                            ? null
                            : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B6B),
                          foregroundColor: Colors.white,
                        ),
                        child: Text(UserStrings.text('confirm_leave')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
