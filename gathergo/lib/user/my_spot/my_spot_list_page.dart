import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app_routes.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/spot_map_launcher.dart';
import '../data/mock_store.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';
import '../services/activity_completion_service.dart';
import '../utils/activity_expiry.dart';

class MySpotListPage extends StatefulWidget {
  const MySpotListPage({super.key});

  @override
  State<MySpotListPage> createState() => _MySpotListPageState();
}

class _MySpotListPageState extends State<MySpotListPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _mySpots = const [];
  List<Map<String, dynamic>> _allSpots = const [];
  final Set<int> _busySpotIds = <int>{};

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    _loadMySpots();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  String _formatSpotDistanceValue({
    required String ownerCompletedDistance,
    required dynamic directTotalDistance,
    required String kmPerRound,
    required String roundCount,
  }) {
    final completedDistance = double.tryParse(ownerCompletedDistance);
    if (completedDistance != null && completedDistance > 0) {
      return completedDistance == completedDistance.roundToDouble()
          ? completedDistance.toStringAsFixed(0)
          : completedDistance.toStringAsFixed(3);
    }

    final directDistance =
        double.tryParse((directTotalDistance ?? '').toString().trim());
    if (directDistance != null && directDistance >= 0) {
      return directDistance == directDistance.roundToDouble()
          ? directDistance.toStringAsFixed(0)
          : directDistance.toStringAsFixed(3);
    }

    final km = double.tryParse(kmPerRound);
    final round = double.tryParse(roundCount);
    if (km != null && km > 0 && round != null && round > 0) {
      final total = km * round;
      return total == total.roundToDouble()
          ? total.toStringAsFixed(0)
          : total.toStringAsFixed(3);
    }

    return '';
  }

  Future<void> _loadMySpots() async {
    if (!mounted) return;
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
          '${ConfigService.getBaseUrl()}/api/spots/mine?user_id=$userId');
      final res = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'x-user-id': userId.toString(),
        },
      );
      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw Exception('Invalid response format');
      }

      final mapped = decoded
          .whereType<Map>()
          .map((row) => _mapBackendSpot(Map<String, dynamic>.from(row)))
          .toList();
      final visibleMapped = mapped.where(_isActiveSpot).toList(growable: false);
      await _hydratePreviewImages(mapped);

      MockStore.mySpots.value = List<Map<String, dynamic>>.from(visibleMapped);

      if (!mounted) return;
      setState(() {
        _allSpots = List<Map<String, dynamic>>.from(mapped);
        _mySpots = visibleMapped;
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

  Map<String, dynamic> _mapBackendSpot(Map<String, dynamic> row) {
    final kmPerRound = (row['km_per_round'] ?? '').toString();
    final roundCount = (row['round_count'] ?? '').toString();
    final creatorName = (row['creator_name'] ?? 'User').toString();
    final province = (row['province'] ?? row['changwat'] ?? '').toString();
    final district =
        (row['district'] ?? row['amphoe'] ?? row['district_name'] ?? '')
            .toString();
    final ownerCompletedAt = (row['owner_completed_at'] ?? '').toString();
    final ownerCompletedDistance =
        (row['owner_completed_distance_km'] ?? '').toString().trim();
    final totalDistance = _formatSpotDistanceValue(
      ownerCompletedDistance: ownerCompletedDistance,
      directTotalDistance: row['total_distance'],
      kmPerRound: kmPerRound,
      roundCount: roundCount,
    );

    return {
      'backendSpotId': row['id'],
      'id': row['id'],
      'title': (row['title'] ?? '').toString(),
      'description': (row['description'] ?? '').toString(),
      'location': (row['location'] ?? '').toString(),
      'locationLink': (row['location_link'] ?? '').toString(),
      'location_lat': row['location_lat'],
      'location_lng': row['location_lng'],
      'locationLat': row['location_lat'],
      'locationLng': row['location_lng'],
      'province': province,
      'district': district,
      'date': (row['event_date'] ?? '').toString(),
      'time': (row['event_time'] ?? '').toString(),
      'kmPerRound': kmPerRound,
      'round': roundCount,
      'distance': '${totalDistance.isEmpty ? '0' : totalDistance} KM',
      'total_distance': totalDistance,
      'maxPeople': (row['max_people'] ?? '').toString(),
      'imageBase64': (row['image_base64'] ?? '').toString(),
      'image': ConfigService.resolveUrl((row['image_url'] ?? '').toString()),
      'host': creatorName,
      'hostName': creatorName,
      'creatorName': creatorName,
      'creatorUserId': (row['created_by_user_id'] ?? '').toString(),
      'creatorRole': (row['creator_role'] ?? 'user').toString(),
      'status': (row['status'] ?? 'active').toString(),
      'owner_completed_at': ownerCompletedAt,
      'owner_completed_distance_km': ownerCompletedDistance,
      'completed_at': ownerCompletedAt,
      'completed_distance_km': ownerCompletedDistance,
      'joined_count': row['joined_count'],
      'joinedCount': (row['joined_count'] ?? 0).toString(),
      'is_joined': row['is_joined'] == true,
      'isJoined': row['is_joined'] == true,
    };
  }

  int? _spotId(Map<String, dynamic> spot) {
    return int.tryParse((spot["backendSpotId"] ?? spot["id"] ?? "").toString());
  }

  Future<void> _hydratePreviewImages(List<Map<String, dynamic>> spots) async {
    await Future.wait(spots.map(_applyPreviewImageFromGallery));
  }

  Future<void> _applyPreviewImageFromGallery(Map<String, dynamic> spot) async {
    final spotId = _spotId(spot);
    if (spotId == null || spotId <= 0) return;

    if ((spot['imageBase64'] ?? '').toString().trim().isNotEmpty) {
      return;
    }
    if ((spot['image'] ?? '').toString().trim().isNotEmpty) {
      return;
    }

    try {
      final res = await http.get(
        Uri.parse('${ConfigService.getBaseUrl()}/api/spots/$spotId/media'),
        headers: const {'Accept': 'application/json'},
      );
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      if (decoded is! List || decoded.isEmpty) return;

      for (final item in decoded) {
        if (item is! Map) continue;
        final rawUrl = (item['file_url'] ?? item['fileUrl'] ?? '').toString();
        final resolved = ConfigService.resolveUrl(rawUrl);
        if (resolved.isEmpty) continue;

        spot['imageBase64'] = '';
        spot['image'] = resolved;
        return;
      }
    } catch (_) {}

    await _applyPreviewImageFromSpotDetail(spotId, spot);
  }

  Future<void> _applyPreviewImageFromSpotDetail(
    int spotId,
    Map<String, dynamic> spot,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('${ConfigService.getBaseUrl()}/api/spots/$spotId'),
        headers: const {'Accept': 'application/json'},
      );
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return;

      final imageBase64 = (decoded['image_base64'] ?? '').toString().trim();
      final imageUrl =
          ConfigService.resolveUrl((decoded['image_url'] ?? '').toString());

      if (imageBase64.isNotEmpty) {
        spot['imageBase64'] = imageBase64;
        spot['image'] = '';
        return;
      }
      if (imageUrl.isNotEmpty) {
        spot['imageBase64'] = '';
        spot['image'] = imageUrl;
      }
    } catch (_) {}
  }

  bool _isDbCompleted(Map<String, dynamic> spot) {
    return (spot['owner_completed_at'] ?? spot['completed_at'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
  }

  bool _isExpired(Map<String, dynamic> spot) {
    return ActivityExpiry.isExpiredAfterGrace(spot);
  }

  bool _isActiveSpot(Map<String, dynamic> spot) {
    return !_isDbCompleted(spot) && !_isExpired(spot);
  }

  String _createdSpotHistoryTitle() {
    switch (UserLocaleController.languageCode.value) {
      case 'th':
        return 'ประวัติ Spot ที่สร้างและเสร็จแล้ว';
      case 'zh':
        return '已完成的已创建 Spot 历史';
      default:
        return 'Created Spot History';
    }
  }

  String _createdSpotHistoryEmpty() {
    switch (UserLocaleController.languageCode.value) {
      case 'th':
        return 'ยังไม่มีประวัติ Spot ที่สร้างและเสร็จแล้ว';
      case 'zh':
        return '还没有已完成的已创建 Spot 历史记录';
      default:
        return 'No completed created spots yet';
    }
  }

  String _noActiveCreatedSpotsText() {
    switch (UserLocaleController.languageCode.value) {
      case 'th':
        return 'ไม่มี Spot ที่กำลังดำเนินอยู่';
      case 'zh':
        return '没有进行中的已创建 Spot';
      default:
        return 'No active created spots';
    }
  }

  Future<void> _openCreateSpot() async {
    final result = await Navigator.pushNamed(context, AppRoutes.userCreateSpot);
    if (!mounted) return;
    await _loadMySpots();
    if (result is Map && result['refresh'] == true) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(tr('spot_published_successfully'))),
        );
    }
  }

  Future<void> _openSpotDetail(Map<String, dynamic> spot) async {
    final result = await Navigator.pushNamed(
      context,
      AppRoutes.userSpotDetail,
      arguments: spot,
    );
    if (!mounted) return;
    if (result is Map && result["refresh"] == true) {
      await _loadMySpots();
    }
  }

  String _spotKey(Map<String, dynamic> spot) {
    final explicit =
        (spot["spotKey"] ?? spot["spot_key"] ?? "").toString().trim();
    if (explicit.isNotEmpty) {
      return explicit;
    }
    final stableId =
        (spot["backendSpotId"] ?? spot["id"] ?? "").toString().trim();
    if (stableId.isNotEmpty) {
      return 'spot:$stableId';
    }
    final title = (spot["title"] ?? "").toString().trim().toLowerCase();
    final date = (spot["date"] ?? "").toString().trim().toLowerCase();
    final time = (spot["time"] ?? "").toString().trim().toLowerCase();
    final location = (spot["location"] ?? "").toString().trim().toLowerCase();
    return "$title|$date|$time|$location";
  }

  Map<String, dynamic> _pendingSpotPayload(Map<String, dynamic> spot) {
    final payload = Map<String, dynamic>.from(spot);
    payload["pendingKey"] =
        "spot_created|${payload["title"] ?? "Spot"}|${payload["date"] ?? ""}|${payload["time"] ?? ""}|${payload["location"] ?? ""}";
    payload["taskType"] = "spot_created";
    return payload;
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openMap(Map<String, dynamic> spot) async {
    final ok = await SpotMapLauncher.open(
      latitude: spot["locationLat"] ?? spot["location_lat"],
      longitude: spot["locationLng"] ?? spot["location_lng"],
      locationText: spot["location"],
    );
    if (!ok) {
      _showSnack(tr('location_not_available'));
    }
  }

  void _openChat(Map<String, dynamic> spot) {
    if (ActivityExpiry.isExpiredAfterGrace(spot)) {
      _showSnack(tr('chat_room_not_available_for_spot'));
      return;
    }
    final spotKey = _spotKey(spot);
    if (spotKey.isEmpty) {
      _showSnack(tr('chat_room_not_available_for_spot'));
      return;
    }

    final payload = Map<String, dynamic>.from(spot)
      ..["spotKey"] = spotKey
      ..["spot_key"] = spotKey;
    Navigator.pushNamed(
      context,
      AppRoutes.userSpotChatGroup,
      arguments: {"spot": payload},
    );
  }

  Future<void> _deleteSpot(Map<String, dynamic> spot) async {
    final userId = await SessionService.getCurrentUserId();
    final spotId = _spotId(spot);
    if (!mounted) return;
    if (userId == null || userId <= 0 || spotId == null) {
      _showSnack(tr('cannot_delete_this_spot'));
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr('delete_spot_question')),
        content: Text(tr('delete_spot_for_everyone')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _busySpotIds.add(spotId));
    try {
      final uri = Uri.parse(
          "${ConfigService.getBaseUrl()}/api/spots/$spotId?user_id=$userId");
      final res = await http.delete(
        uri,
        headers: {
          "Accept": "application/json",
          "x-user-id": userId.toString(),
        },
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception("HTTP ${res.statusCode}: ${res.body}");
      }

      MockStore.removeSpot(spot);
      if (!mounted) return;
      setState(() {
        _mySpots = _mySpots
            .where((item) => _spotId(item) != spotId)
            .toList(growable: false);
      });
      _showSnack(tr('spot_deleted'));
    } catch (e) {
      _showSnack(tr('delete_failed', params: {'error': e.toString()}));
    } finally {
      if (mounted) {
        setState(() => _busySpotIds.remove(spotId));
      }
    }
  }

  Future<void> _markSpotCompleted(Map<String, dynamic> spot) async {
    final payload = _pendingSpotPayload(spot);
    final savedToDb = await ActivityCompletionService.completeSpot(payload);
    if (!savedToDb) {
      _showSnack(tr('save_failed', params: {'error': 'completion_not_saved'}));
      return;
    }
    await _loadMySpots();
    if (!mounted) return;
    _showSnack(tr('completed'));
  }

  List<Map<String, dynamic>> _historySpots() {
    return _allSpots
        .where((spot) => _isDbCompleted(spot) || _isExpired(spot))
        .map((spot) => <String, dynamic>{
              ...Map<String, dynamic>.from(spot),
              'taskType': 'spot_created',
              'pendingKey':
                  (_pendingSpotPayload(spot)['pendingKey'] ?? '').toString(),
              'historyStatus': _isDbCompleted(spot) ? 'completed' : 'expired',
            })
        .toList(growable: false);
  }

  Future<void> _openHistory() async {
    await _loadMySpots();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _CreatedSpotHistoryPage(
          title: _createdSpotHistoryTitle(),
          emptyText: _createdSpotHistoryEmpty(),
          items: _historySpots(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final filteredSpots = _mySpots.where((spot) {
      if (query.isEmpty) return true;
      final haystack = [
        (spot["title"] ?? "").toString(),
        (spot["location"] ?? "").toString(),
        (spot["date"] ?? "").toString(),
        (spot["time"] ?? "").toString(),
        (spot["joinedCount"] ?? "").toString(),
      ].join(" ").toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE7C7FF),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Text(
          tr('create_spot'),
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _openHistory,
            icon: const Icon(Icons.history_rounded, color: Colors.black),
            tooltip: _createdSpotHistoryTitle(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFFF2B4D),
        onPressed: _openCreateSpot,
        child: const Icon(Icons.add, color: Colors.white, size: 34),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: tr('search'),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchCtrl.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                        ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  tr('load_failed', params: {'error': _error!}),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: _loadMySpots,
                                  child: Text(tr('retry')),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _allSpots.isEmpty
                          ? const _EmptyState()
                          : filteredSpots.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          query.isEmpty
                                              ? _noActiveCreatedSpotsText()
                                              : tr('no_matching_spots'),
                                          style: const TextStyle(
                                            color: Colors.black54,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        if (query.isEmpty &&
                                            _historySpots().isNotEmpty) ...[
                                          const SizedBox(height: 12),
                                          OutlinedButton.icon(
                                            onPressed: _openHistory,
                                            icon: const Icon(
                                              Icons.history_rounded,
                                            ),
                                            label: Text(
                                              _createdSpotHistoryTitle(),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _loadMySpots,
                                  child: ListView.separated(
                                    padding: const EdgeInsets.all(16),
                                    itemCount: filteredSpots.length,
                                    separatorBuilder: (_, __) =>
                                        const SizedBox(height: 12),
                                    itemBuilder: (context, index) {
                                      final spot = filteredSpots[index];
                                      final spotId = _spotId(spot);
                                      return _SpotCard(
                                        spot: spot,
                                        busy: spotId != null &&
                                            _busySpotIds.contains(spotId),
                                        onTap: () => _openSpotDetail(spot),
                                        onOpenMap: () => _openMap(spot),
                                        onOpenChat: () => _openChat(spot),
                                        onComplete: () =>
                                            _markSpotCompleted(spot),
                                        onDelete: () => _deleteSpot(spot),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    String tr(String key, {Map<String, String> params = const {}}) {
      return UserStrings.text(key, params: params);
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.event_note_outlined, size: 86),
            const SizedBox(height: 12),
            Text(
              tr('no_spots_created_yet'),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              tr('tap_to_create_first_spot'),
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreatedSpotHistoryPage extends StatelessWidget {
  final String title;
  final String emptyText;
  final List<Map<String, dynamic>> items;

  const _CreatedSpotHistoryPage({
    required this.title,
    required this.emptyText,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE7C7FF),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: items.isEmpty
            ? Center(child: Text(emptyText))
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  return _CreatedSpotHistoryItem(item: items[index]);
                },
              ),
      ),
    );
  }
}

class _CreatedSpotHistoryItem extends StatelessWidget {
  final Map<String, dynamic> item;

  const _CreatedSpotHistoryItem({
    required this.item,
  });

  String _distanceWithKm(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') return '-';
    return normalized.toUpperCase().contains('KM')
        ? normalized
        : '$normalized KM';
  }

  String _completedTotalLabel() {
    final rawCompleted = (item["owner_completed_distance_km"] ??
            item["completed_distance_km"] ??
            "")
        .toString()
        .trim();
    final parsedCompleted = double.tryParse(rawCompleted);
    if (parsedCompleted != null && parsedCompleted > 0) {
      final text = parsedCompleted == parsedCompleted.roundToDouble()
          ? parsedCompleted.toStringAsFixed(0)
          : parsedCompleted.toStringAsFixed(3);
      return _distanceWithKm(text);
    }

    final rawTotal = (item["total_distance"] ?? "").toString().trim();
    final parsedTotal = double.tryParse(rawTotal);
    if (parsedTotal != null && parsedTotal >= 0) {
      final text = parsedTotal == parsedTotal.roundToDouble()
          ? parsedTotal.toStringAsFixed(0)
          : parsedTotal.toStringAsFixed(3);
      return _distanceWithKm(text);
    }

    final kmPerRound = double.tryParse(
      (item["kmPerRound"] ?? item["km_per_round"] ?? "").toString().trim(),
    );
    final round = double.tryParse(
      (item["round"] ?? item["round_count"] ?? "").toString().trim(),
    );
    if (kmPerRound != null && kmPerRound > 0 && round != null && round > 0) {
      final total = kmPerRound * round;
      final text = total == total.roundToDouble()
          ? total.toStringAsFixed(0)
          : total.toStringAsFixed(3);
      return _distanceWithKm(text);
    }

    return '-';
  }

  Widget _buildSpotImage() {
    final b64 = (item["imageBase64"] ?? "")
        .toString()
        .trim()
        .replaceFirst(RegExp(r'^data:image\/[^;]+;base64,'), '')
        .replaceAll(RegExp(r'\s+'), '');
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
    if (image.startsWith("http://") || image.startsWith("https://")) {
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

  void _openDetail(BuildContext context) {
    Navigator.pushNamed(
      context,
      AppRoutes.userSpotDetail,
      arguments: item,
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (item["title"] ?? UserStrings.spotTerm).toString();
    final date = (item["date"] ?? "-").toString();
    final time = (item["time"] ?? "-").toString();
    final location = (item["location"] ?? "-").toString();

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () => _openDetail(context),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD7DEE8)),
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
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00C9A7).withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            UserStrings.text('completed'),
                            style: const TextStyle(
                              color: Color(0xFF00C9A7),
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
                        _HistoryChip(
                          UserStrings.text(
                            'date_with_value',
                            params: {'value': date},
                          ),
                        ),
                        _HistoryChip(
                          UserStrings.text(
                            'time_with_value',
                            params: {'value': time},
                          ),
                        ),
                        _HistoryChip(
                          UserStrings.text(
                            'location_with_value',
                            params: {'value': location},
                          ),
                        ),
                        _HistoryChip(
                          UserStrings.text(
                            'total_with_value',
                            params: {'value': _completedTotalLabel()},
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
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

class _SpotCard extends StatelessWidget {
  final Map<String, dynamic> spot;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenChat;
  final Future<void> Function() onComplete;
  final VoidCallback onDelete;

  const _SpotCard({
    required this.spot,
    required this.busy,
    required this.onTap,
    required this.onOpenMap,
    required this.onOpenChat,
    required this.onComplete,
    required this.onDelete,
  });

  Widget _buildSpotImage() {
    final b64 = (spot["imageBase64"] ?? "")
        .toString()
        .trim()
        .replaceFirst(RegExp(r'^data:image\/[^;]+;base64,'), '')
        .replaceAll(RegExp(r'\s+'), '');
    if (b64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(b64),
          fit: BoxFit.cover,
          width: 92,
          height: 92,
        );
      } catch (_) {}
    }

    final imagePath = (spot["image"] ?? "").toString();
    if (imagePath.isEmpty) {
      return const Icon(Icons.image_outlined);
    }
    if (imagePath.startsWith("http://") || imagePath.startsWith("https://")) {
      return Image.network(
        imagePath,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
      );
    }
    return Image.asset(
      imagePath,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported),
    );
  }

  @override
  Widget build(BuildContext context) {
    String tr(String key, {Map<String, String> params = const {}}) {
      return UserStrings.text(key, params: params);
    }

    final String title = (spot["title"] ?? "Your Spot").toString();
    final String distance = (spot["distance"] ?? "8 KM").toString();
    final String date = (spot["date"] ?? "-").toString();
    final String time = (spot["time"] ?? "-").toString();
    final String location = _shortLocation();
    final String maxPeople = (spot["maxPeople"] ?? "0").toString();
    final String joined = (spot["joinedCount"] ?? "0").toString();
    final totalLabel = _totalLabel();

    Widget actionButton({
      required String label,
      required Color color,
      required VoidCallback onPressed,
    }) {
      return Expanded(
        child: OutlinedButton(
          onPressed: busy ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black,
            side: BorderSide(color: color, width: 1.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(label),
        ),
      );
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFD7DEE8)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 108,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: 108,
                            height: 108,
                            child: ColoredBox(
                              color: const Color(0xFFF1F4FA),
                              child: _buildSpotImage(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: busy ? null : onComplete,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF00C9A7),
                              side: const BorderSide(
                                color: Color(0xFF00C9A7),
                                width: 1.5,
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
                    ),
                  ),
                  const SizedBox(width: 14),
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
                                  color: Color(0xFF222222),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.chevron_right_rounded,
                              color: Color(0xFF97A0AF),
                              size: 26,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _infoChip(
                              tr('date_with_value', params: {'value': date}),
                            ),
                            _infoChip(
                              tr('time_with_value', params: {'value': time}),
                            ),
                            _infoChip(
                              tr('location_with_value',
                                  params: {'value': location}),
                              maxWidth: 248,
                            ),
                            _infoChip(
                              tr('total_with_value',
                                  params: {'value': totalLabel}),
                            ),
                            _infoChip(
                              tr('people_with_value',
                                  params: {'value': '$joined/$maxPeople'}),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  actionButton(
                    label: tr('view_map'),
                    color: const Color(0xFF2563EB),
                    onPressed: onOpenMap,
                  ),
                  const SizedBox(width: 10),
                  actionButton(
                    label: tr('chat'),
                    color: const Color(0xFF00C9A7),
                    onPressed: onOpenChat,
                  ),
                  const SizedBox(width: 10),
                  actionButton(
                    label: busy ? tr('deleting') : tr('delete'),
                    color: const Color(0xFFFF4444),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _distanceWithKm(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') return '-';
    return normalized.toUpperCase().contains('KM')
        ? normalized
        : '$normalized KM';
  }

  String _totalLabel() {
    final rawTotal = (spot["total_distance"] ?? "").toString().trim();
    final parsedTotal = double.tryParse(rawTotal);
    if (parsedTotal != null && parsedTotal > 0) {
      final text = parsedTotal == parsedTotal.roundToDouble()
          ? parsedTotal.toStringAsFixed(0)
          : parsedTotal.toStringAsFixed(3);
      return _distanceWithKm(text);
    }

    final kmPerRound = double.tryParse(
      (spot["kmPerRound"] ?? spot["km_per_round"] ?? "").toString().trim(),
    );
    final round = double.tryParse(
      (spot["round"] ?? spot["round_count"] ?? "").toString().trim(),
    );
    if (kmPerRound != null && kmPerRound > 0 && round != null && round > 0) {
      final total = kmPerRound * round;
      final text = total == total.roundToDouble()
          ? total.toStringAsFixed(0)
          : total.toStringAsFixed(3);
      return _distanceWithKm(text);
    }

    if (rawTotal.isNotEmpty) return _distanceWithKm(rawTotal);
    return '-';
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
    if (raw.isEmpty) return '-';

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

  Widget _infoChip(String text, {double? maxWidth}) {
    final content = Container(
      constraints: maxWidth == null ? null : BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F3),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD8D8D8)),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 12.5,
          color: Color(0xFF424242),
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    return maxWidth == null
        ? content
        : SizedBox(
            width: maxWidth,
            child: content,
          );
  }
}
