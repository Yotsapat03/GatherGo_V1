import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

import '../../app_routes.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../../widgets/common/event_list_card.dart';
import '../data/mock_store.dart';
import '../../widgets/common/search_filters_bottom_sheet.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';
import '../utils/activity_expiry.dart';

class SpotPage extends StatefulWidget {
  const SpotPage({super.key});

  @override
  State<SpotPage> createState() => _SpotPageState();
}

class _SpotPageState extends State<SpotPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Map<String, String> _locationLabelCache = <String, String>{};
  bool _loading = false;
  String? _error;
  int? _currentUserId;
  DistanceFilterRange? _selectedDistanceRange;
  String? _selectedProvince;
  List<String> _availableProvinces = const ['Bangkok', 'Nakhon Pathom'];

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    _searchCtrl.addListener(_applyFilter);
    _syncSpotsFromBackend();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  void _applyFilter() {
    setState(() {});
  }

  String _formatDistanceText(
      dynamic directValue, dynamic kmPerRoundValue, dynamic roundValue) {
    final direct = double.tryParse((directValue ?? '').toString().trim());
    if (direct != null && direct >= 0) {
      final text = direct == direct.roundToDouble()
          ? direct.toStringAsFixed(0)
          : direct.toStringAsFixed(2);
      return text;
    }

    final kmPerRound =
        double.tryParse((kmPerRoundValue ?? '').toString().trim()) ?? 0;
    final round = double.tryParse((roundValue ?? '').toString().trim()) ?? 0;
    final total = kmPerRound * round;
    final text = total == total.roundToDouble()
        ? total.toStringAsFixed(0)
        : total.toStringAsFixed(2);
    return text;
  }

  double _spotTotalKm(Map<String, dynamic> spot) {
    final direct = double.tryParse(
      (spot["total_distance"] ?? spot["completed_distance_km"] ?? "")
          .toString(),
    );
    if (direct != null) return direct;

    final kmPerRound = double.tryParse(
            (spot["kmPerRound"] ?? spot["km_per_round"] ?? "").toString()) ??
        0;
    final round = double.tryParse(
            (spot["round"] ?? spot["round_count"] ?? "").toString()) ??
        0;
    return kmPerRound * round;
  }

  bool _matchesDistanceRange(Map<String, dynamic> spot) {
    final selected = _selectedDistanceRange;
    if (selected == null) return true;

    final totalKm = _spotTotalKm(spot);
    final min = selected.minKm;
    final max = selected.maxKm;

    final minOk = min == null
        ? true
        : (selected.includeMin ? totalKm >= min : totalKm > min);
    final maxOk = max == null ? true : totalKm <= max;
    return minOk && maxOk;
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

  String _normalizeProvinceName(String value) {
    final province = value.trim();
    if (province.isEmpty) return '';

    final normalized = province
        .toLowerCase()
        .replaceFirst(RegExp(r'^province\s+'), '')
        .replaceFirst(RegExp(r'^จังหวัด'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (normalized == 'bangkok' ||
        normalized == 'krung thep maha nakhon' ||
        normalized == 'krungthepmahanakhon' ||
        normalized == 'กรุงเทพมหานคร') {
      return 'Bangkok';
    }

    return province;
  }

  String _spotProvince(Map<String, dynamic> spot) {
    final direct =
        _normalizeProvinceName((spot["province"] ?? "").toString().trim());
    if (direct.isNotEmpty) return direct;

    final location = (spot["location"] ?? "").toString().trim();
    if (_looksLikeCoordinateText(location)) return "";
    final parts = location.split(',');
    if (parts.length >= 2) {
      return _normalizeProvinceName(parts.last.trim());
    }
    return "";
  }

  String _spotDistrict(Map<String, dynamic> spot) {
    final direct = (spot["district"] ?? "").toString().trim();
    if (direct.isNotEmpty) return direct;

    final location = (spot["location"] ?? "").toString().trim();
    if (_looksLikeCoordinateText(location)) return "";
    final province = _spotProvince(spot);
    final parts = location
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.length >= 3) {
      return parts[parts.length - 2];
    }

    if (parts.length == 2 &&
        province.isNotEmpty &&
        parts[1].toLowerCase() == province.toLowerCase()) {
      return parts[0];
    }

    return "";
  }

  String _spotLocationLabel(Map<String, dynamic> spot) {
    final cached = _locationLabelCache[_locationCacheKey(spot)];
    if (cached != null && cached.trim().isNotEmpty) {
      return _looksLikeCoordinateText(cached) ? "-" : cached;
    }

    final province = _spotProvince(spot);
    final district = _spotDistrict(spot);

    if (province.isEmpty && district.isEmpty) return "-";
    if (province.isEmpty) return district;
    if (district.isEmpty) return province;
    return '$province, $district';
  }

  bool _matchesProvince(Map<String, dynamic> spot) {
    final selected = (_selectedProvince ?? "").trim();
    if (selected.isEmpty) return true;
    return _spotProvince(spot).toLowerCase() == selected.toLowerCase();
  }

  String _locationCacheKey(Map<String, dynamic> spot) {
    final id = (spot["backendSpotId"] ?? spot["id"] ?? "").toString().trim();
    if (id.isNotEmpty) return 'spot:$id';

    final lat =
        (spot["locationLat"] ?? spot["location_lat"] ?? "").toString().trim();
    final lng =
        (spot["locationLng"] ?? spot["location_lng"] ?? "").toString().trim();
    return 'coord:$lat,$lng';
  }

  double? _parseCoordinate(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  Future<void> _hydrateSpotLocations(List<Map<String, dynamic>> spots) async {
    final pending = <Future<void>>[];

    for (final spot in spots) {
      final cacheKey = _locationCacheKey(spot);
      final currentLabel = _spotLocationLabel(spot);
      if (currentLabel != '-') {
        _locationLabelCache[cacheKey] = currentLabel;
        continue;
      }

      final lat = _parseCoordinate(spot["locationLat"] ?? spot["location_lat"]);
      final lng = _parseCoordinate(spot["locationLng"] ?? spot["location_lng"]);
      if (lat == null || lng == null) {
        continue;
      }

      final cached = _locationLabelCache[cacheKey];
      if (cached != null && cached.trim().isNotEmpty) {
        final parts = cached.split(',').map((part) => part.trim()).toList();
        if (parts.isNotEmpty) {
          spot["province"] = parts.first;
        }
        if (parts.length > 1) {
          spot["district"] = parts.sublist(1).join(', ');
        }
        continue;
      }

      pending.add(() async {
        try {
          final placemarks = await placemarkFromCoordinates(lat, lng);
          if (placemarks.isEmpty) return;

          final placemark = placemarks.first;
          final province = _normalizeProvinceName(
              (placemark.administrativeArea ?? '').trim());
          final district = (placemark.subAdministrativeArea ??
                  placemark.locality ??
                  placemark.subLocality ??
                  '')
              .trim();

          if (province.isEmpty && district.isEmpty) return;

          spot["province"] = province;
          spot["district"] = district;
          _locationLabelCache[cacheKey] = district.isEmpty
              ? province
              : province.isEmpty
                  ? district
                  : '$province, $district';
        } catch (_) {}
      }());
    }

    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }
  }

  int? _spotId(Map<String, dynamic> spot) {
    return int.tryParse((spot["backendSpotId"] ?? spot["id"] ?? "").toString());
  }

  Future<void> _hydrateSpotImages(List<Map<String, dynamic>> spots) async {
    await Future.wait(spots.map(_applySpotPreviewImage));
  }

  Future<void> _applySpotPreviewImage(Map<String, dynamic> spot) async {
    final spotId = _spotId(spot);
    if (spotId == null || spotId <= 0) return;

    if ((spot["imageBase64"] ?? "").toString().trim().isNotEmpty) {
      return;
    }
    if ((spot["image"] ?? "").toString().trim().isNotEmpty) {
      return;
    }

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
            final resolved = ConfigService.resolveUrl(
              (item['file_url'] ?? item['fileUrl'] ?? '').toString(),
            );
            if (resolved.isEmpty) continue;
            spot["imageBase64"] = '';
            spot["image"] = resolved;
            return;
          }
        }
      }
    } catch (_) {}

    await _applySpotPreviewFromDetail(spotId, spot);
  }

  Future<void> _applySpotPreviewFromDetail(
    int spotId,
    Map<String, dynamic> spot,
  ) async {
    try {
      final res = await http.get(
        Uri.parse('${ConfigService.getBaseUrl()}/api/spots/$spotId'),
        headers: {
          'Accept': 'application/json',
          if (_currentUserId != null) 'x-user-id': _currentUserId.toString(),
        },
      );
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return;

      final imageBase64 =
          (decoded['image_base64'] ?? decoded['imageBase64'] ?? '')
              .toString()
              .trim();
      final imageUrl = ConfigService.resolveUrl(
        (decoded['image_url'] ?? decoded['imageUrl'] ?? '').toString(),
      );

      if (imageBase64.isNotEmpty) {
        spot["imageBase64"] = imageBase64;
        spot["image"] = '';
        return;
      }
      if (imageUrl.isNotEmpty) {
        spot["imageBase64"] = '';
        spot["image"] = imageUrl;
      }
    } catch (_) {}
  }

  Future<void> _syncSpotsFromBackend() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final userId = await SessionService.getCurrentUserId();
      _currentUserId = userId;
      final queryParams = <String, String>{};
      final selectedRange = _selectedDistanceRange;
      if (selectedRange?.minKm != null) {
        queryParams["min_km"] = selectedRange!.minKm!.toString();
      }
      if (selectedRange?.maxKm != null) {
        queryParams["max_km"] = selectedRange!.maxKm!.toString();
      }
      if ((_selectedProvince ?? "").trim().isNotEmpty) {
        queryParams["province"] = _selectedProvince!.trim();
      }

      final uri = Uri.parse("${ConfigService.getBaseUrl()}/api/spots")
          .replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final res = await http.get(
        uri,
        headers: {
          "Accept": "application/json",
          if (userId != null) "x-user-id": userId.toString(),
        },
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        throw Exception("HTTP ${res.statusCode}: ${res.body}");
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw Exception("Invalid response format");
      }

      final backendSpots = decoded
          .map<Map<String, dynamic>>(
              (e) => _mapBackendSpot(Map<String, dynamic>.from(e as Map)))
          .toList();

      await _hydrateSpotLocations(backendSpots);
      await _hydrateSpotImages(backendSpots);

      final dynamicProvinces = backendSpots
          .map((e) => _spotProvince(e))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      if (dynamicProvinces.isNotEmpty) {
        _availableProvinces = dynamicProvinces;
      }

      MockStore.mergeSpotsFromBackend(backendSpots);

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Map<String, dynamic> _mapBackendSpot(Map<String, dynamic> row) {
    final kmPerRound = (row["km_per_round"] ?? "").toString();
    final round = (row["round_count"] ?? "").toString();
    final totalDistance = _formatDistanceText(
        row["total_distance"], row["km_per_round"], row["round_count"]);
    final imageBase64 =
        (row["image_base64"] ?? row["imageBase64"] ?? "").toString();
    final imageUrl =
        (row["image_url"] ?? row["imageUrl"] ?? "").toString().trim();
    final creatorName = (row["creator_name"] ?? "User").toString();
    final creatorUserId = (row["created_by_user_id"] ?? "").toString();
    final eventDate = (row["event_date"] ?? "").toString();
    final eventTime = (row["event_time"] ?? "").toString();

    return {
      "backendSpotId": row["id"],
      "id": row["id"],
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
      "province": (row["province"] ?? row["changwat"] ?? "").toString(),
      "district":
          (row["district"] ?? row["amphoe"] ?? row["district_name"] ?? "")
              .toString(),
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
      "joined_count": row["joined_count"],
      "joinedCount": (row["joined_count"] ?? 0).toString(),
      "is_booked": row["is_booked"] == true,
      "isBooked": row["is_booked"] == true,
      "booking_reference": (row["booking_reference"] ?? "").toString(),
      "is_joined": row["is_joined"] == true,
      "isJoined": row["is_joined"] == true,
    };
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _searchCtrl.removeListener(_applyFilter);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _openDetail(Map<String, dynamic> spot) {
    Navigator.pushNamed(
      context,
      AppRoutes.userSpotDetail,
      arguments: spot,
    );
  }

  void _goHome() {
    Navigator.pushReplacementNamed(context, AppRoutes.userHome);
  }

  Future<void> _openFilters() async {
    final result = await showSearchFiltersBottomSheet(
      context: context,
      selectedDistanceRange: _selectedDistanceRange,
      selectedProvince: _selectedProvince,
      provinces: _availableProvinces,
    );
    if (result == null || !mounted) {
      return;
    }
    setState(() {
      _selectedDistanceRange = result.distanceRange;
      _selectedProvince = result.province;
    });
    await _syncSpotsFromBackend();
  }

  Widget _buildSpotImage(Map<String, dynamic> spot) {
    final b64 = (spot["imageBase64"] ?? spot["image_base64"] ?? "")
        .toString()
        .trim()
        .replaceFirst(RegExp(r'^data:image\/[^;]+;base64,'), '')
        .replaceAll(RegExp(r'\s+'), '');
    if (b64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(b64),
          width: 120,
          height: 80,
          fit: BoxFit.cover,
        );
      } catch (_) {}
    }

    final imagePath = (spot["image"] ?? "").toString();
    if (imagePath.isEmpty) {
      return Container(
        width: 120,
        height: 80,
        color: const Color(0xFFE5E7EB),
        child: const Icon(Icons.image),
      );
    }

    final isNet =
        imagePath.startsWith("http://") || imagePath.startsWith("https://");
    if (isNet) {
      return Image.network(
        imagePath,
        width: 120,
        height: 80,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 120,
          height: 80,
          color: const Color(0xFFE5E7EB),
          child: const Icon(Icons.image),
        ),
      );
    }

    return Image.asset(
      imagePath,
      width: 120,
      height: 80,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: 120,
        height: 80,
        color: const Color(0xFFE5E7EB),
        child: const Icon(Icons.image),
      ),
    );
  }

  double _parseDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String _formatNumber(double value) {
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFBFEFE7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: _goHome,
        ),
        titleSpacing: 0,
        title: Text(
          UserStrings.spotTerm,
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: tr('search'),
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => _searchCtrl.clear(),
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
                const SizedBox(width: 8),
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: (_selectedDistanceRange != null ||
                            (_selectedProvince ?? "").isNotEmpty)
                        ? const Color(0xFFEAF2FF)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.filter_list),
                    onPressed: _openFilters,
                    tooltip: tr('filters'),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: Colors.red),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      tr('sync_failed', params: {'error': _error!}),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: ValueListenableBuilder<List<Map<String, dynamic>>>(
              valueListenable: MockStore.spots,
              builder: (context, allSpots, _) {
                final q = _searchCtrl.text.trim().toLowerCase();
                final filtered = allSpots.where((e) {
                  final creatorId = int.tryParse(
                      (e["creatorUserId"] ?? e["created_by_user_id"] ?? "")
                          .toString());
                  final isMine = _currentUserId != null &&
                      _currentUserId! > 0 &&
                      creatorId != null &&
                      creatorId == _currentUserId;
                  final isJoined =
                      e["isJoined"] == true || e["is_joined"] == true;
                  if (isMine ||
                      isJoined ||
                      ActivityExpiry.isExpiredAfterGrace(e)) {
                    return false;
                  }

                  final hay = [
                    (e["title"] ?? "").toString(),
                    (e["hostName"] ?? e["host"] ?? "").toString(),
                    (e["date"] ?? "").toString(),
                    (e["time"] ?? "").toString(),
                    (e["location"] ?? "").toString(),
                    _spotProvince(e),
                    (e["description"] ?? "").toString(),
                    (e["creatorName"] ?? "").toString(),
                    (e["creatorUserId"] ?? "").toString(),
                  ].join(" ").toLowerCase();
                  final searchOk = q.isEmpty || hay.contains(q);
                  return searchOk &&
                      _matchesDistanceRange(e) &&
                      _matchesProvince(e);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      tr('no_spot_found'),
                      style: TextStyle(color: Colors.black54),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: _syncSpotsFromBackend,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      final spot = filtered[i];
                      final totalDistance = _spotTotalKm(spot);
                      return EventListCard(
                        onTap: () => _openDetail(spot),
                        image: _buildSpotImage(spot),
                        title: (spot["title"] ?? "-").toString(),
                        chips: [
                          tr('date_with_value', params: {
                            'value': (spot["date"] ?? "-").toString()
                          }),
                          tr('time_with_value', params: {
                            'value': (spot["time"] ?? "-").toString()
                          }),
                          tr('location_with_value',
                              params: {'value': _spotLocationLabel(spot)}),
                          tr('total_with_value', params: {
                            'value': '${_formatNumber(totalDistance)} KM'
                          }),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
