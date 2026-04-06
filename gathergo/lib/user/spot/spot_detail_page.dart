import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app_routes.dart';
import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../../core/services/spot_map_launcher.dart';
import '../data/mock_store.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';
import '../utils/activity_expiry.dart';

class SpotDetailPage extends StatefulWidget {
  const SpotDetailPage({super.key});

  @override
  State<SpotDetailPage> createState() => _SpotDetailPageState();
}

class _SpotDetailPageState extends State<SpotDetailPage> {
  static const int _galleryLoopBasePage = 10000;
  bool _busy = false;
  Map<String, dynamic>? _currentSpot;
  bool _didLoadArgs = false;
  int _mediaLoadVersion = 0;
  final PageController _galleryController =
      PageController(initialPage: _galleryLoopBasePage);
  Timer? _galleryTimer;
  List<Map<String, dynamic>> _galleryItems = <Map<String, dynamic>>[];
  int _galleryIndex = 0;

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
  }

  @override
  void dispose() {
    _galleryTimer?.cancel();
    _galleryController.dispose();
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  String _chatUnavailableText() {
    final code = Localizations.localeOf(context).languageCode;
    switch (code) {
      case 'th':
        return 'ปิดแชทแล้ว';
      case 'zh':
        return '聊天已关闭。';
      default:
        return 'Chat closed.';
    }
  }

  String _distanceWithKm(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') return '-';
    return normalized.toUpperCase().contains('KM')
        ? normalized
        : '$normalized KM';
  }

  String _peopleWithUnit(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') return '-';
    switch (UserLocaleController.languageCode.value) {
      case 'th':
        return '$normalized คน';
      case 'zh':
        return '$normalized 人';
      default:
        return '$normalized people';
    }
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

  Future<List<Map<String, dynamic>>> _loadSpotMembers(
      Map<String, dynamic> spot) async {
    final spotId = _spotId(spot);
    if (spotId == null) {
      throw Exception('Spot ID not found');
    }

    final userId = await _currentUserId();
    final uri =
        Uri.parse('${ConfigService.getBaseUrl()}/api/spots/$spotId/members');
    final res = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        if (userId != null && userId > 0) 'x-user-id': userId.toString(),
      },
    );

    if (res.statusCode != 200) {
      throw Exception('Load members failed (${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return <Map<String, dynamic>>[];
    final rawMembers = decoded['members'];
    if (rawMembers is! List) return <Map<String, dynamic>>[];
    return rawMembers
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _showMemberList(Map<String, dynamic> spot) async {
    try {
      final members = await _loadSpotMembers(spot);
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('user_list'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (members.isEmpty)
                      Expanded(
                        child: Center(
                          child: Text(
                            tr('no_users_found_for_spot'),
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: members.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final member = members[index];
                            final name =
                                (member['display_name'] ?? '-').toString();
                            final role =
                                (member['role'] ?? 'user').toString().trim();
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: const Color(0xFFDDE6FF),
                                child: Text(
                                  name.trim().isNotEmpty
                                      ? name
                                          .trim()
                                          .substring(0, 1)
                                          .toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              title: Text(name),
                              subtitle: Text(
                                role == 'host' ? tr('host') : tr('user'),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } catch (e) {
      _showSnack(tr('unable_to_load_user_list', params: {'error': '$e'}));
    }
  }

  String _spotTotalKmLabel(Map<String, dynamic> spot) {
    final direct = (spot["totalDistance"] ?? spot["total_distance"] ?? "")
        .toString()
        .trim();
    if (direct.isNotEmpty) {
      return _distanceWithKm(direct);
    }

    final kmPerRound = double.tryParse(
      (spot["kmPerRound"] ?? spot["km_per_round"] ?? "").toString().trim(),
    );
    final round = double.tryParse(
      (spot["round"] ?? spot["round_count"] ?? "").toString().trim(),
    );

    if (kmPerRound == null || round == null) {
      return "-";
    }

    final total = kmPerRound * round;
    final value = total == total.roundToDouble()
        ? total.toStringAsFixed(0)
        : total.toStringAsFixed(3);
    return _distanceWithKm(value);
  }

  String _spotJoinerLimitLabel(Map<String, dynamic> spot) {
    final maxPeople =
        (spot["maxPeople"] ?? spot["max_people"] ?? "").toString().trim();
    if (maxPeople.isNotEmpty) return _peopleWithUnit(maxPeople);

    final joinedCount =
        (spot["joinedCount"] ?? spot["joined_count"] ?? "").toString().trim();
    if (joinedCount.isNotEmpty) return _peopleWithUnit(joinedCount);

    final fallback = (spot["maxParticipants"] ?? "").toString().trim();
    return fallback.isNotEmpty ? _peopleWithUnit(fallback) : "-";
  }

  Map<String, dynamic> _mapBackendSpot(Map<String, dynamic> row) {
    final creatorName = (row['creator_name'] ?? 'User').toString();
    final province = (row['province'] ?? row['changwat'] ?? '').toString();
    final district =
        (row['district'] ?? row['amphoe'] ?? row['district_name'] ?? '')
            .toString();
    final kmPerRound = (row['km_per_round'] ?? '').toString();
    final totalDistance = _formatSpotTotalDistance(row);

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
      'km_per_round': kmPerRound,
      'round': (row['round_count'] ?? '').toString(),
      'round_count': (row['round_count'] ?? '').toString(),
      'total_distance': totalDistance,
      'distance': '$totalDistance KM',
      'maxPeople': (row['max_people'] ?? '').toString(),
      'max_people': (row['max_people'] ?? '').toString(),
      'imageBase64': (row['image_base64'] ?? '').toString(),
      'image': ConfigService.resolveUrl((row['image_url'] ?? '').toString()),
      'host': creatorName,
      'hostName': creatorName,
      'creatorName': creatorName,
      'creatorUserId': (row['created_by_user_id'] ?? '').toString(),
      'created_by_user_id': (row['created_by_user_id'] ?? '').toString(),
      'creatorRole': (row['creator_role'] ?? 'user').toString(),
      'creator_role': (row['creator_role'] ?? 'user').toString(),
      'status': (row['status'] ?? 'completed').toString(),
      'joined_count': row['joined_count'],
      'joinedCount': (row['joined_count'] ?? 0).toString(),
      'is_joined': row['is_joined'] == true,
      'isJoined': row['is_joined'] == true,
      'completed_at': (row['completed_at'] ?? '').toString(),
      'completed_distance_km': (row['completed_distance_km'] ?? '').toString(),
      'is_booked': row['is_booked'] == true,
      'isBooked': row['is_booked'] == true,
      'booking_reference': (row['booking_reference'] ?? '').toString(),
      'spotKey': (row['spot_key'] ?? '').toString(),
      'spot_key': (row['spot_key'] ?? '').toString(),
    };
  }

  bool _looksLikeCoordinateText(String value) {
    final text = value.trim();
    if (text.isEmpty) return false;
    if (RegExp(r'lat|lng|latitude|longitude', caseSensitive: false)
        .hasMatch(text)) {
      return true;
    }
    return RegExp(r'^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$').hasMatch(text);
  }

  String _spotLocationLabel(Map<String, dynamic> spot) {
    final province = (spot["province"] ?? "").toString().trim();
    final district = (spot["district"] ?? "").toString().trim();

    if (province.isNotEmpty && district.isNotEmpty) {
      return '$province, $district';
    }
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;

    final location = (spot["location"] ?? "").toString().trim();
    if (location.isEmpty || _looksLikeCoordinateText(location)) {
      return "-";
    }
    return location;
  }

  void _restartGalleryTimer() {
    _galleryTimer?.cancel();
    if (!mounted || _galleryItems.length <= 1) return;

    _galleryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted ||
          !_galleryController.hasClients ||
          _galleryItems.length <= 1) {
        return;
      }
      final currentPage =
          _galleryController.page?.round() ?? _galleryLoopBasePage;
      _galleryController.animateToPage(
        currentPage + 1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    });
  }

  void _moveGalleryBy(int delta) {
    if (_galleryItems.length <= 1 || !_galleryController.hasClients) return;
    final currentPage =
        _galleryController.page?.round() ?? _galleryLoopBasePage;
    _galleryController.animateToPage(
      currentPage + delta,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _loadSpotMedia(Map<String, dynamic> spot) async {
    final loadVersion = ++_mediaLoadVersion;
    final items = <Map<String, dynamic>>[];

    void addMemory(String rawBase64) {
      final cleaned = rawBase64
          .trim()
          .replaceFirst(RegExp(r'^data:image\/[^;]+;base64,'), '');
      if (cleaned.isEmpty) return;
      try {
        final bytes = base64Decode(cleaned);
        final encoded = base64Encode(bytes);
        if (items.any((item) => item['key'] == encoded)) return;
        items.add({
          'key': encoded,
          'type': 'memory',
          'bytes': bytes,
        });
      } catch (_) {}
    }

    void addUrl(String rawUrl, {bool asset = false}) {
      final normalized = rawUrl.trim();
      if (normalized.isEmpty) return;
      final key = asset ? normalized : ConfigService.resolveUrl(normalized);
      if (key.isEmpty || items.any((item) => item['key'] == key)) return;
      items.add({
        'key': key,
        'type': asset ? 'asset' : 'network',
        'url': key,
      });
    }

    final imagePath = (spot["image"] ?? "").toString().trim();
    final imageBase64 =
        (spot["imageBase64"] ?? spot["image_base64"] ?? "").toString();

    // Always seed the gallery with the legacy cover first so the detail page
    // shows the selected cover plus any uploaded gallery images.
    if (imageBase64.trim().isNotEmpty) {
      addMemory(imageBase64);
    } else if (imagePath.startsWith("http://") ||
        imagePath.startsWith("https://")) {
      addUrl(imagePath);
    } else if (imagePath.isNotEmpty) {
      addUrl(imagePath, asset: true);
    }

    final spotId = _spotId(spot);
    if (spotId != null) {
      try {
        final res = await http.get(
          Uri.parse('${ConfigService.getBaseUrl()}/api/spots/$spotId/media'),
          headers: const {'Accept': 'application/json'},
        );
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is! Map) continue;
              addUrl((item['file_url'] ?? item['fileUrl'] ?? '').toString());
            }
          }
        }
      } catch (_) {}
    }

    if (!mounted || loadVersion != _mediaLoadVersion) return;
    setState(() {
      _galleryItems = items;
      _galleryIndex = 0;
    });
    if (_galleryController.hasClients) {
      _galleryController.jumpToPage(_galleryLoopBasePage);
    }
    _restartGalleryTimer();
  }

  Future<void> _refreshSpotFromBackend(
      [Map<String, dynamic>? fallbackSpot]) async {
    final seed = fallbackSpot ?? _currentSpot;
    if (seed == null) return;
    final spotId = _spotId(seed);
    if (spotId == null) return;

    try {
      final userId = await _currentUserId();
      final adminId = await _currentAdminId();
      final uri = Uri.parse('${ConfigService.getBaseUrl()}/api/spots/$spotId');
      final res = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (userId != null && userId > 0) 'x-user-id': userId.toString(),
          if (adminId != null && adminId > 0) 'x-admin-id': adminId.toString(),
        },
      );
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return;
      final freshSpot = _mapBackendSpot(Map<String, dynamic>.from(decoded));
      if (!mounted) return;
      setState(() {
        _currentSpot = freshSpot;
      });
      await _loadSpotMedia(freshSpot);
    } catch (_) {}
  }

  Widget _buildGalleryImage(Map<String, dynamic> item) {
    final type = (item['type'] ?? '').toString();
    if (type == 'memory') {
      return Image.memory(
        item['bytes'] as Uint8List,
        height: 170,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _galleryFallback(),
      );
    }
    if (type == 'asset') {
      return Image.asset(
        (item['url'] ?? '').toString(),
        height: 170,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _galleryFallback(),
      );
    }
    return Image.network(
      (item['url'] ?? '').toString(),
      height: 170,
      width: double.infinity,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _galleryFallback(),
    );
  }

  Widget _galleryFallback() {
    return Container(
      height: 170,
      width: double.infinity,
      color: const Color(0xFFE5E7EB),
      child: const Icon(Icons.image, size: 40),
    );
  }

  Widget _buildSpotGallery() {
    if (_galleryItems.isEmpty) {
      return _galleryFallback();
    }

    return Column(
      children: [
        SizedBox(
          height: 170,
          child: Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: PageView.builder(
                  controller: _galleryController,
                  itemBuilder: (_, index) {
                    final imageIndex = index % _galleryItems.length;
                    return _buildGalleryImage(_galleryItems[imageIndex]);
                  },
                  onPageChanged: (index) {
                    if (!mounted) return;
                    setState(
                        () => _galleryIndex = index % _galleryItems.length);
                    _restartGalleryTimer();
                  },
                ),
              ),
              if (_galleryItems.length > 1)
                Positioned(
                  top: 10,
                  left: 10,
                  child: _SpotGalleryNavButton(
                    icon: Icons.chevron_left,
                    onTap: () => _moveGalleryBy(-1),
                  ),
                ),
              if (_galleryItems.length > 1)
                Positioned(
                  top: 10,
                  right: 10,
                  child: _SpotGalleryNavButton(
                    icon: Icons.chevron_right,
                    onTap: () => _moveGalleryBy(1),
                  ),
                ),
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_galleryIndex + 1}/${_galleryItems.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_galleryItems.length > 1) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              _galleryItems.length,
              (index) => AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: index == _galleryIndex ? 18 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: index == _galleryIndex
                      ? Colors.blueAccent
                      : Colors.black26,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<int?> _currentUserId() => SessionService.getCurrentUserId();
  Future<int?> _currentAdminId() => AdminSessionService.getCurrentAdminId();

  int? _spotId(Map<String, dynamic> spot) {
    return int.tryParse((spot["backendSpotId"] ?? spot["id"] ?? "").toString());
  }

  bool _isCreator(Map<String, dynamic> spot, int userId) {
    final creator = int.tryParse(
        (spot["creatorUserId"] ?? spot["created_by_user_id"] ?? "").toString());
    return creator != null && creator == userId;
  }

  bool _isAdminCreator(Map<String, dynamic> spot, int adminId) {
    final creatorRole = (spot["creatorRole"] ?? spot["creator_role"] ?? "user")
        .toString()
        .toLowerCase();
    if (creatorRole != "admin") {
      return false;
    }
    final creator = int.tryParse(
        (spot["creatorUserId"] ?? spot["created_by_user_id"] ?? "").toString());
    return creator != null && creator == adminId;
  }

  bool _isJoined(Map<String, dynamic> spot) {
    return spot["isJoined"] == true || spot["is_joined"] == true;
  }

  bool _isBooked(Map<String, dynamic> spot) {
    return spot["isBooked"] == true || spot["is_booked"] == true;
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

  void _openChat(Map<String, dynamic> spot) {
    if (ActivityExpiry.isExpiredAfterGrace(spot)) {
      _showSnack(_chatUnavailableText());
      return;
    }
    if ((spot["completed_at"] ?? "").toString().trim().isNotEmpty) {
      _showSnack(_chatUnavailableText());
      return;
    }
    final spotKey = _spotKey(spot);
    if (spotKey.isEmpty) {
      _showSnack(_chatUnavailableText());
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

  Future<void> _joinSpot(Map<String, dynamic> spot) async {
    final userId = await _currentUserId();
    final spotId = _spotId(spot);
    if (userId == null || spotId == null) {
      _showSnack(tr('cannot_join_this_spot'));
      return;
    }

    setState(() => _busy = true);
    try {
      final uri =
          Uri.parse("${ConfigService.getBaseUrl()}/api/spots/$spotId/join");
      final res = await http
          .post(
            uri,
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
              "x-user-id": userId.toString(),
            },
            body: jsonEncode({"user_id": userId}),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception("HTTP ${res.statusCode}: ${res.body}");
      }

      final payload = Map<String, dynamic>.from(spot)..["isJoined"] = true;
      MockStore.joinSpot(payload);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(
        context,
        AppRoutes.userJoinedSpot,
        (route) => false,
      );
    } catch (e) {
      _showSnack(tr('join_failed', params: {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _bookSpot(Map<String, dynamic> spot) async {
    final userId = await _currentUserId();
    final spotId = _spotId(spot);
    if (userId == null || spotId == null) {
      _showSnack(tr('cannot_create_booking_for_spot'));
      return;
    }

    setState(() => _busy = true);
    try {
      final uri =
          Uri.parse("${ConfigService.getBaseUrl()}/api/spots/$spotId/bookings");
      final res = await http
          .post(
            uri,
            headers: {
              "Content-Type": "application/json",
              "Accept": "application/json",
              "x-user-id": userId.toString(),
            },
            body: jsonEncode({"user_id": userId}),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception("HTTP ${res.statusCode}: ${res.body}");
      }

      final decoded = jsonDecode(res.body);
      final updated = Map<String, dynamic>.from(spot)
        ..["isBooked"] = true
        ..["is_booked"] = true
        ..["booking_reference"] =
            (decoded is Map ? decoded["booking_reference"] : null) ??
                spot["booking_reference"];

      if (decoded is Map && decoded["spot"] is Map) {
        updated.addAll(Map<String, dynamic>.from(decoded["spot"] as Map));
        updated["isBooked"] = true;
        updated["is_booked"] = true;
      }

      MockStore.updateSpot(updated);
      if (!mounted) return;
      setState(() => _currentSpot = updated);
      _showSnack(tr('booking_saved_successfully'));
    } catch (e) {
      _showSnack(tr('booking_failed', params: {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unbookSpot(Map<String, dynamic> spot) async {
    final userId = await _currentUserId();
    final spotId = _spotId(spot);
    if (userId == null || spotId == null) {
      _showSnack(tr('cannot_cancel_booking_for_spot'));
      return;
    }

    setState(() => _busy = true);
    try {
      final uri = Uri.parse(
          "${ConfigService.getBaseUrl()}/api/spots/$spotId/bookings?user_id=$userId");
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

      final decoded = jsonDecode(res.body);
      final updated = Map<String, dynamic>.from(spot)
        ..["isBooked"] = false
        ..["is_booked"] = false
        ..remove("booking_reference");

      if (decoded is Map && decoded["spot"] is Map) {
        updated.addAll(Map<String, dynamic>.from(decoded["spot"] as Map));
      }
      updated["isBooked"] = false;
      updated["is_booked"] = false;
      updated.remove("booking_reference");

      MockStore.updateSpot(updated);
      if (!mounted) return;
      setState(() => _currentSpot = updated);
      _showSnack(tr('booking_removed_successfully'));
    } catch (e) {
      _showSnack(tr('cancel_booking_failed', params: {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _leaveSpot(Map<String, dynamic> spot) async {
    final userId = await _currentUserId();
    final spotId = _spotId(spot);
    if (userId == null || spotId == null) {
      _showSnack(tr('cannot_leave_this_spot'));
      return;
    }

    setState(() => _busy = true);
    try {
      final uri = Uri.parse(
          "${ConfigService.getBaseUrl()}/api/spots/$spotId/join?user_id=$userId");
      final res = await http.delete(
        uri,
        headers: {
          "Accept": "application/json",
          "x-user-id": userId.toString(),
        },
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode == 404) {
        // Treat stale local joined state as already-left.
      } else if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception("HTTP ${res.statusCode}: ${res.body}");
      }

      MockStore.unjoinSpot(spot);
      if (!mounted) return;
      Navigator.pushNamed(
        context,
        AppRoutes.userSuccess,
        arguments: {
          "title": tr('leave_spot'),
          "subtitle": tr('successful'),
          "buttonText": tr('back_to_home'),
          "popUntilRouteName": AppRoutes.userHome,
          "autoSeconds": 2,
          "blockSystemBack": true,
        },
      );
    } catch (e) {
      _showSnack(tr('leave_failed', params: {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSpot(Map<String, dynamic> spot) async {
    final userId = await _currentUserId();
    final adminId = await _currentAdminId();
    final spotId = _spotId(spot);
    if (!mounted) return;
    if ((userId == null && adminId == null) || spotId == null) {
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

    setState(() => _busy = true);
    try {
      final isAdminCreator = adminId != null && _isAdminCreator(spot, adminId);
      final query = isAdminCreator ? "admin_id=$adminId" : "user_id=$userId";
      final uri =
          Uri.parse("${ConfigService.getBaseUrl()}/api/spots/$spotId?$query");
      final res = await http.delete(
        uri,
        headers: {
          "Accept": "application/json",
          if (!isAdminCreator && userId != null) "x-user-id": userId.toString(),
          if (isAdminCreator) "x-admin-id": adminId.toString(),
        },
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        throw Exception("HTTP ${res.statusCode}: ${res.body}");
      }

      MockStore.removeSpot(spot);
      if (!mounted) return;
      Navigator.pop(context);
      _showSnack(tr('spot_deleted'));
    } catch (e) {
      _showSnack(tr('delete_failed', params: {'error': '$e'}));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
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

  Future<void> _editSpot(Map<String, dynamic> spot) async {
    final result = await Navigator.pushNamed(
      context,
      AppRoutes.userCreateSpot,
      arguments: {"spot": spot},
    );
    if (!mounted || result is! Map) return;
    final updated = result["spot"];
    if (updated is Map) {
      setState(() {
        _currentSpot = Map<String, dynamic>.from(updated);
      });
      await _refreshSpotFromBackend(_currentSpot);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_didLoadArgs) {
      final args =
          ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
      if (args != null) {
        _currentSpot = Map<String, dynamic>.from(args);
        if (_spotId(_currentSpot!) != null) {
          _refreshSpotFromBackend(_currentSpot);
        } else {
          _loadSpotMedia(_currentSpot!);
        }
      }
      _didLoadArgs = true;
    }
    final spot = _currentSpot;
    if (spot == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('spot_detail'))),
        body: Center(child: Text(tr('no_data'))),
      );
    }

    return FutureBuilder<List<int?>>(
      future: Future.wait<int?>([_currentUserId(), _currentAdminId()]),
      builder: (context, snapshot) {
        final ids = snapshot.data ?? const <int?>[];
        final userId = ids.isNotEmpty ? ids[0] : null;
        final adminId = ids.length > 1 ? ids[1] : null;
        final sessionLoaded = snapshot.connectionState == ConnectionState.done;
        final isCreator = ((userId ?? 0) > 0 && _isCreator(spot, userId!)) ||
            ((adminId ?? 0) > 0 && _isAdminCreator(spot, adminId!));
        final isJoined = _isJoined(spot);
        final isBooked = _isBooked(spot);

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFF),
          appBar: AppBar(
            title: Text(tr('spot_detail')),
            backgroundColor: Colors.white,
            elevation: 0.5,
            foregroundColor: Colors.black,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionCard(
                  children: [
                    _buildSpotGallery(),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (spot["title"] ?? "-").toString(),
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _spotLocationLabel(spot),
                                style: const TextStyle(
                                  color: Color(0xFF6B7280),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (sessionLoaded && isCreator)
                          OutlinedButton.icon(
                            onPressed: _busy ? null : () => _editSpot(spot),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            label: Text(tr('edit')),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black,
                              side: const BorderSide(color: Color(0xFF00C9A7)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _pill(
                          '${tr('host')}: ${(spot["creatorName"] ?? "-").toString()}',
                          active: true,
                        ),
                        _pill(
                          '${tr('role')}: ${(spot["creatorRole"] ?? "user").toString()}',
                          active: false,
                          onTap: () => _showMemberList(spot),
                        ),
                        if (isBooked) _pill(tr('booked'), active: true),
                        if (isJoined) _pill(tr('joined'), active: true),
                      ],
                    ),
                    if (isJoined) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : () => _openChat(spot),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: Text(tr('open_chat')),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  children: [
                    _sectionTitle(tr('event_information')),
                    _labelValue(tr('name_of_event'), spot["title"]),
                    _labelValue(tr('location'), spot["location"]),
                    if ((spot["locationLink"] ?? spot["location_link"] ?? "")
                        .toString()
                        .trim()
                        .isNotEmpty)
                      _labelValue(
                        tr('location_note'),
                        spot["locationLink"] ?? spot["location_link"],
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _openMap(spot),
                          icon: const Icon(Icons.map_outlined),
                          label: Text(tr('open_in_google_maps')),
                        ),
                      ),
                    ),
                    _labelValue(tr('date'), spot["date"]),
                    _labelValue(tr('time'), spot["time"]),
                    _labelValue(tr('description'), spot["description"]),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _labelValue(
                            tr('km_per_round'),
                            _distanceWithKm('${spot["kmPerRound"] ?? "-"}'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _labelValue(
                            tr('round'),
                            '${spot["round"] ?? "-"}',
                          ),
                        ),
                      ],
                    ),
                    _labelValue(tr('total_km_caps'), _spotTotalKmLabel(spot)),
                    const SizedBox(height: 10),
                    _labelValue(
                      tr('how_many_joiner'),
                      _spotJoinerLimitLabel(spot),
                    ),
                    if ((spot["booking_reference"] ?? "")
                        .toString()
                        .trim()
                        .isNotEmpty)
                      _labelValue(
                        tr('booking_reference'),
                        spot["booking_reference"],
                      ),
                  ],
                ),
              ],
            ),
          ),
          bottomSheet: !sessionLoaded || isCreator
              ? null
              : Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFF),
                    border: Border(
                      top: BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                  child: Row(
                    children: [
                      if (!isJoined) ...[
                        SizedBox(
                          width: 76,
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: isBooked
                                  ? const Color(0xFFE5486B)
                                  : const Color(0xFF111827),
                              disabledBackgroundColor: Colors.white,
                              disabledForegroundColor: isBooked
                                  ? const Color(0xFFE5486B)
                                  : const Color(0xFF9CA3AF),
                              elevation: 0,
                              side: const BorderSide(color: Color(0xFFE5E7EB)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: _busy
                                ? null
                                : () => isBooked
                                    ? _unbookSpot(spot)
                                    : _bookSpot(spot),
                            child: _busy
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFFE5486B),
                                    ),
                                  )
                                : Icon(
                                    isBooked
                                        ? Icons.favorite
                                        : Icons.favorite_border,
                                    size: 28,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isJoined
                                  ? const Color(0xFFE5E7EB)
                                  : const Color(0xFFF4C542),
                              foregroundColor: isJoined
                                  ? const Color(0xFF6B7280)
                                  : Colors.black,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                            ),
                            onPressed: _busy
                                ? null
                                : (isJoined
                                    ? null
                                    : () async {
                                        await _joinSpot(spot);
                                      }),
                            child: Text(
                              isJoined ? tr('joined') : tr('join'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  Widget _sectionCard({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF111827),
        ),
      ),
    );
  }

  Widget _labelValue(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(value?.toString() ?? '-',
                style: const TextStyle(color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text, {required bool active, VoidCallback? onTap}) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFDDE6FF) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: active ? Colors.black : Colors.black54,
        ),
      ),
    );

    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: child,
      ),
    );
  }
}

class _SpotGalleryNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SpotGalleryNavButton({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black45,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
