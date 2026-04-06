import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../../core/utils/payment_booking_status.dart';
import '../../widgets/common/event_list_card.dart';
import '../../widgets/common/search_filters_bottom_sheet.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';
import '../utils/activity_expiry.dart';
import 'big_event_detail_page.dart';

class BigEventListPage extends StatefulWidget {
  const BigEventListPage({super.key});

  @override
  State<BigEventListPage> createState() => _BigEventListPageState();
}

class _BigEventListPageState extends State<BigEventListPage> {
  String get _baseUrl => ConfigService.getBaseUrl();
  final Map<String, String> _locationLabelCache = <String, String>{};
  final TextEditingController _searchCtrl = TextEditingController();

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _events = [];
  DistanceFilterRange? _selectedDistanceRange;
  String? _selectedProvince;
  List<String> _availableProvinces = const ['Bangkok', 'Nakhon Pathom'];

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    debugPrint('### BigEventListPage initState');
    _fetchEvents();
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _resolveUrl(String? input) {
    final raw = (input ?? '').trim();
    if (raw.isEmpty) return '';
    return ConfigService.resolveUrl(raw);
  }

  bool _isEventJoined(Map<String, dynamic> event) {
    return event['is_joined'] == true ||
        event['isJoined'] == true ||
        PaymentBookingStatus.isBookingConfirmed(event['booking_status']) ||
        PaymentBookingStatus.isPaymentSuccessful(event['payment_status']);
  }

  double _eventTotalKm(Map<String, dynamic> event) {
    final totalRaw = (event['total_distance'] ?? '').toString().trim();
    final total = double.tryParse(totalRaw);
    if (total != null) return total;

    final perLap = (event['distance_per_lap'] is num)
        ? (event['distance_per_lap'] as num).toDouble()
        : double.tryParse((event['distance_per_lap'] ?? '').toString());
    final laps = (event['number_of_laps'] is num)
        ? (event['number_of_laps'] as num).toDouble()
        : double.tryParse((event['number_of_laps'] ?? '').toString());

    if (perLap != null && laps != null) return perLap * laps;
    return 0;
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

  String _eventProvince(Map<String, dynamic> event) {
    final direct =
        _normalizeProvinceName((event['province'] ?? '').toString().trim());
    if (direct.isNotEmpty) return direct;

    final locationDisplay = (event['location_display'] ?? '').toString().trim();
    if (_looksLikeCoordinateText(locationDisplay)) return '';
    final parts = locationDisplay
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) return _normalizeProvinceName(parts.first);
    return '';
  }

  String _eventDistrict(Map<String, dynamic> event) {
    final direct = (event['district'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;

    final locationDisplay = (event['location_display'] ?? '').toString().trim();
    if (_looksLikeCoordinateText(locationDisplay)) return '';
    final parts = locationDisplay
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) return parts[1];
    return '';
  }

  String _locationCacheKey(Map<String, dynamic> event) {
    final id = (event['id'] ?? event['event_id'] ?? '').toString().trim();
    if (id.isNotEmpty) return 'event:$id';

    final lat =
        (event['location_lat'] ?? event['latitude'] ?? '').toString().trim();
    final lng =
        (event['location_lng'] ?? event['longitude'] ?? '').toString().trim();
    return 'coord:$lat,$lng';
  }

  double? _parseCoordinate(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  String _extractProvinceFromPlacemark(Placemark placemark) {
    return _normalizeProvinceName(
      (placemark.administrativeArea ??
              placemark.subAdministrativeArea ??
              placemark.locality ??
              '')
          .trim(),
    );
  }

  String _extractDistrictFromPlacemark(Placemark placemark, String province) {
    final candidates = <String>[
      (placemark.subLocality ?? '').trim(),
      (placemark.locality ?? '').trim(),
      (placemark.subAdministrativeArea ?? '').trim(),
      (placemark.thoroughfare ?? '').trim(),
    ];

    for (final candidate in candidates) {
      if (candidate.isEmpty) continue;
      if (province.isNotEmpty &&
          candidate.toLowerCase() == province.toLowerCase()) {
        continue;
      }
      return candidate;
    }
    return '';
  }

  String _eventLocationLabel(Map<String, dynamic> event) {
    final cached = _locationLabelCache[_locationCacheKey(event)];
    if (cached != null && cached.trim().isNotEmpty) {
      return _looksLikeCoordinateText(cached)
          ? tr('location_not_specified')
          : cached;
    }

    final directDisplay = (event['location_display'] ?? event['location'] ?? '')
        .toString()
        .trim();
    if (directDisplay.isNotEmpty && !_looksLikeCoordinateText(directDisplay)) {
      final parts = directDisplay
          .split(',')
          .map((part) => part.trim())
          .where((part) => part.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        return '${parts.first}, ${parts[1]}';
      }
      return directDisplay;
    }

    final district = _eventDistrict(event);
    final province = _eventProvince(event);
    if (district.isEmpty && province.isEmpty) {
      return tr('location_not_specified');
    }
    if (province.isEmpty) return district;
    if (district.isEmpty) return province;
    return '$province, $district';
  }

  Future<void> _hydrateEventLocations(List<Map<String, dynamic>> events) async {
    final pending = <Future<void>>[];

    for (final event in events) {
      final cacheKey = _locationCacheKey(event);
      final currentLabel = _eventLocationLabel(event);
      if (currentLabel != tr('location_not_specified')) {
        _locationLabelCache[cacheKey] = currentLabel;
        continue;
      }

      final lat = _parseCoordinate(event['location_lat'] ?? event['latitude']);
      final lng = _parseCoordinate(event['location_lng'] ?? event['longitude']);
      if (lat == null || lng == null) continue;

      final cached = _locationLabelCache[cacheKey];
      if (cached != null && cached.trim().isNotEmpty) {
        final parts = cached.split(',').map((part) => part.trim()).toList();
        if (parts.isNotEmpty) {
          event['province'] = parts.first;
        }
        if (parts.length > 1) {
          event['district'] = parts.sublist(1).join(', ');
        }
        event['location_display'] = cached;
        continue;
      }

      pending.add(() async {
        try {
          await setLocaleIdentifier('en');
          final placemarks = await placemarkFromCoordinates(lat, lng);
          if (placemarks.isEmpty) return;

          final placemark = placemarks.first;
          final province = _extractProvinceFromPlacemark(placemark);
          final district = _extractDistrictFromPlacemark(placemark, province);

          if (province.isEmpty && district.isEmpty) return;

          event['province'] = province;
          event['district'] = district;
          event['location_display'] = province.isEmpty
              ? district
              : district.isEmpty
                  ? province
                  : '$province, $district';
          _locationLabelCache[cacheKey] =
              event['location_display'].toString().trim();
        } catch (_) {}
      }());
    }

    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }
  }

  bool _matchesDistanceRange(Map<String, dynamic> event) {
    final selected = _selectedDistanceRange;
    if (selected == null) return true;

    final totalKm = _eventTotalKm(event);
    final min = selected.minKm;
    final max = selected.maxKm;

    final minOk = min == null
        ? true
        : (selected.includeMin ? totalKm >= min : totalKm > min);
    final maxOk = max == null ? true : totalKm <= max;
    return minOk && maxOk;
  }

  bool _matchesProvince(Map<String, dynamic> event) {
    final selected = (_selectedProvince ?? '').trim();
    if (selected.isEmpty) return true;
    final province = _eventProvince(event);
    return province.toLowerCase() == selected.toLowerCase();
  }

  Future<void> _openFilters() async {
    final result = await showSearchFiltersBottomSheet(
      context: context,
      selectedDistanceRange: _selectedDistanceRange,
      selectedProvince: _selectedProvince,
      provinces: _availableProvinces,
    );
    if (result == null || !mounted) return;

    setState(() {
      _selectedDistanceRange = result.distanceRange;
      _selectedProvince = result.province;
    });
    await _fetchEvents();
  }

  Future<void> _fetchEvents() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final queryParams = <String, String>{};
      final selectedRange = _selectedDistanceRange;
      if (selectedRange?.minKm != null) {
        queryParams['min_km'] = selectedRange!.minKm!.toString();
      }
      if (selectedRange?.maxKm != null) {
        queryParams['max_km'] = selectedRange!.maxKm!.toString();
      }
      if ((_selectedProvince ?? '').trim().isNotEmpty) {
        queryParams['province'] = _selectedProvince!.trim();
      }

      final uri = Uri.parse('$_baseUrl/api/big-events')
          .replace(queryParameters: queryParams.isEmpty ? null : queryParams);
      final userId = await SessionService.getCurrentUserId();
      debugPrint('[BigEventList] fetch userId=${userId ?? '-'} uri=$uri');

      final headers = <String, String>{'Accept': 'application/json'};
      if (userId != null && userId > 0) {
        headers['x-user-id'] = userId.toString();
      }

      final res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final decoded = jsonDecode(res.body);

      final List<dynamic> data;
      if (decoded is List) {
        data = decoded;
      } else if (decoded is Map<String, dynamic> && decoded['data'] is List) {
        data = List<dynamic>.from(decoded['data'] as List);
      } else {
        throw Exception('Invalid response format: ${res.body}');
      }

      const defaultImage = 'assets/images/user/events/event1.png';

      final mapped = data
          .map<Map<String, dynamic>>((raw) {
            final e = Map<String, dynamic>.from(raw as Map);

            final id =
                (e['id'] ?? e['event_id'] ?? e['eventId'] ?? '').toString();
            final title = (e['title'] ?? e['name'] ?? '').toString();

            final locationName = (e['location_name'] ??
                    e['meeting_point'] ??
                    e['meetingPoint'] ??
                    '')
                .toString();
            final meetingPointNote =
                (e['meeting_point_note'] ?? e['meetingPointNote'] ?? '')
                    .toString();
            final city = (e['city'] ?? '').toString();
            final province = (e['province'] ?? '').toString().trim();
            final district = (e['district'] ??
                    e['amphoe'] ??
                    e['district_name'] ??
                    e['sub_administrative_area'] ??
                    '')
                .toString()
                .trim();
            final locationDisplay =
                (e['location_display'] ?? e['locationDisplay'] ?? '')
                    .toString()
                    .trim();

            final startAt = (e['start_at'] ?? e['startAt'] ?? '').toString();
            final displayCode =
                (e['display_code'] ?? e['displayCode'] ?? '').toString();

            final organizerId =
                (e['organization_id'] ?? e['organizationId'] ?? '').toString();
            final organizerName =
                (e['organization_name'] ?? e['organizer_name'] ?? '')
                    .toString();

            final rawCover = (e['cover_url'] ??
                    e['coverUrl'] ??
                    e['image_url'] ??
                    e['imageUrl'] ??
                    '')
                .toString();
            final resolvedImage = _resolveUrl(rawCover);
            final imageToUse =
                resolvedImage.isNotEmpty ? resolvedImage : defaultImage;

            final rawQr = (e['qr_url'] ?? e['qrUrl'] ?? '').toString();
            final qrUrl = _resolveUrl(rawQr);

            double? parseDouble(dynamic v) =>
                v == null ? null : double.tryParse(v.toString());

            final distancePerLap = parseDouble(e['distance_per_lap']);
            final numberOfLaps =
                int.tryParse((e['number_of_laps'] ?? '').toString());
            final totalDistance = parseDouble(e['total_distance']);
            final legacyDistanceRaw =
                (e['distance'] ?? e['total_distance'] ?? displayCode ?? '-')
                    .toString();

            String fmtDouble(double v) =>
                (v % 1 == 0) ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

            final totalDistanceText = (distancePerLap != null &&
                    numberOfLaps != null)
                ? fmtDouble(distancePerLap * numberOfLaps)
                : (totalDistance != null
                    ? fmtDouble(totalDistance)
                    : (legacyDistanceRaw.isEmpty ? '-' : legacyDistanceRaw));

            final location = locationDisplay.isNotEmpty
                ? locationDisplay
                : district.isNotEmpty || province.isNotEmpty
                    ? [province, district]
                        .where((part) => part.isNotEmpty)
                        .join(', ')
                    : city.isNotEmpty
                        ? city
                        : tr('location_not_specified');

            final organizerDisplay = organizerName.isNotEmpty
                ? organizerName
                : (organizerId.isNotEmpty
                    ? 'Org #$organizerId'
                    : UserStrings.text('organizer'));

            final isPaid = PaymentBookingStatus.isPaymentSuccessful(
              e['payment_status'] ?? e['status'],
            );
            final isJoined = e['is_joined'] == true ||
                e['isJoined'] == true ||
                isPaid ||
                PaymentBookingStatus.isBookingConfirmed(e['booking_status']);

            return <String, dynamic>{
              ...e,
              'id': id,
              'title': title,
              'description': (e['description'] ?? '').toString(),
              'meeting_point': locationName,
              'location_name': locationName,
              'meeting_point_note': meetingPointNote,
              'location_link': (e['location_link'] ?? '').toString(),
              'city': city,
              'province': province,
              'district': district,
              'location_display': location,
              'latitude': (e['location_lat'] ?? e['latitude'] ?? '').toString(),
              'longitude':
                  (e['location_lng'] ?? e['longitude'] ?? '').toString(),
              'location_lat':
                  (e['location_lat'] ?? e['latitude'] ?? '').toString(),
              'location_lng':
                  (e['location_lng'] ?? e['longitude'] ?? '').toString(),
              'start_at': startAt,
              'end_at': (e['end_at'] ?? e['endAt'] ?? '').toString(),
              'max_participants': e['max_participants'] ?? e['maxParticipants'],
              'fee': e['fee'] ?? 0,
              'image': imageToUse,
              'qrUrl': qrUrl,
              'distance': totalDistanceText,
              'display_code': displayCode,
              'distance_per_lap': distancePerLap,
              'number_of_laps': numberOfLaps,
              'total_distance': totalDistanceText,
              'date': startAt.isNotEmpty ? startAt : '-',
              'location': location,
              'organizer': organizerDisplay,
              'payment_status':
                  (e['payment_status'] ?? e['status'] ?? '').toString(),
              'booking_status': (e['booking_status'] ?? '').toString(),
              'isPaid': isPaid,
              'isJoined': isJoined,
            };
          })
          .where((event) => !ActivityExpiry.isExpiredAfterGrace(event))
          .where((event) => !_isEventJoined(event))
          .toList();

      await _hydrateEventLocations(mapped);

      final dynamicProvinces = mapped
          .map(_eventProvince)
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      setState(() {
        _events = mapped;
        if (dynamicProvinces.isNotEmpty) {
          _availableProvinces = dynamicProvinces;
        }
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchCtrl.text.trim().toLowerCase();

    final filtered = _events.where((e) {
      final title = (e['title'] ?? '').toString().toLowerCase();
      final location = _eventLocationLabel(e).toLowerCase();
      final organizer = (e['organizer'] ?? '').toString().toLowerCase();
      final province = _eventProvince(e).toLowerCase();
      final district = _eventDistrict(e).toLowerCase();
      final code = (e['distance'] ?? '').toString().toLowerCase();
      final totalKm = (e['total_distance'] ?? '').toString().toLowerCase();

      final searchOk = query.isEmpty ||
          title.contains(query) ||
          location.contains(query) ||
          province.contains(query) ||
          district.contains(query) ||
          organizer.contains(query) ||
          code.contains(query) ||
          totalKm.contains(query);
      return searchOk && _matchesDistanceRange(e) && _matchesProvince(e);
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF0A8),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          tr('big_event_title'),
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Expanded(
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
                        borderSide: const BorderSide(color: Color(0xFFE6EAF2)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE6EAF2)),
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
                            (_selectedProvince ?? '').isNotEmpty)
                        ? const Color(0xFFEAF2FF)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE6EAF2)),
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
                                tr(
                                  'load_failed',
                                  params: {'error': _error ?? ''},
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.red),
                              ),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: _fetchEvents,
                                child: Text(tr('retry')),
                              ),
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(child: Text(tr('no_big_events_found')))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final event = filtered[index];
                              return _BigEventCard(
                                event: event,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          BigEventDetailPage(event: event),
                                    ),
                                  ).then((_) {
                                    if (!mounted) return;
                                    debugPrint(
                                      '[BigEventList] return-from-detail refresh',
                                    );
                                    _fetchEvents();
                                  });
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _BigEventCard extends StatelessWidget {
  final Map<String, dynamic> event;
  final VoidCallback onTap;

  const _BigEventCard({required this.event, required this.onTap});

  Widget _buildEventImage(String img) {
    final isNet = img.startsWith('http://') || img.startsWith('https://');
    if (isNet) {
      return Image.network(
        img,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          color: const Color(0xFFF1F4FA),
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported),
        ),
      );
    }

    return Image.asset(
      img,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        color: const Color(0xFFF1F4FA),
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported),
      ),
    );
  }

  String _eventLocationLabel() {
    final province = (event['province'] ?? '').toString().trim();
    final district = (event['district'] ?? '').toString().trim();
    if (province.isNotEmpty || district.isNotEmpty) {
      return [province, district].where((part) => part.isNotEmpty).join(', ');
    }

    final location = (event['location_display'] ??
            event['location'] ??
            UserStrings.text('location_not_specified'))
        .toString()
        .trim();
    if (location.isEmpty) return UserStrings.text('location_not_specified');

    final parts = location
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts.first}, ${parts[1]}';
    }
    return location;
  }

  String _distanceWithKm(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value == '-') return '-';
    return value.toUpperCase().contains('KM') ? value : '$value KM';
  }

  @override
  Widget build(BuildContext context) {
    final bool isPaid = event['isPaid'] == true;
    final bool isJoined = event['isJoined'] == true;

    final String badgeText = isJoined
        ? (isPaid ? UserStrings.text('paid') : UserStrings.text('joined'))
        : (isPaid ? UserStrings.text('paid') : UserStrings.text('available'));

    final String title = (event['title'] ?? '-').toString();
    final String code =
        (event['distance'] ?? event['display_code'] ?? event['code'] ?? '-')
            .toString();
    final String totalDistance =
        _distanceWithKm((event['total_distance'] ?? '-').toString());
    final String location = _eventLocationLabel();
    final String organizer = (event['organizer'] ?? '-').toString();
    final String img = (event['image'] ?? '').toString();
    final String rawFee = (event['fee'] ?? event['price'] ?? '0').toString();
    final String currency =
        (event['currency'] ?? event['fee_currency'] ?? 'THB').toString();
    final num? feeValue = num.tryParse(rawFee);
    final String priceLabel = feeValue == null
        ? '$rawFee $currency'
        : '${feeValue % 1 == 0 ? feeValue.toStringAsFixed(0) : feeValue.toStringAsFixed(2)} $currency';

    return EventListCard(
      onTap: onTap,
      image: _buildEventImage(img),
      imageFooter: Container(
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
      title: title,
      badge: _StatusBadge(text: badgeText),
      chips: [
        UserStrings.text('location_with_value', params: {'value': location}),
        UserStrings.text('code_with_value', params: {'value': code}),
        '${UserStrings.text('total_km_caps')}: $totalDistance',
        UserStrings.text(
          'organizer_with_value',
          params: {'value': organizer},
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String text;

  const _StatusBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final t = text.toLowerCase();
    final bool isPaid = PaymentBookingStatus.isPaymentSuccessful(t) ||
        t == UserStrings.text('paid').toLowerCase();
    final bool isJoined =
        t == 'joined' || t == UserStrings.text('joined').toLowerCase();

    final Color bg = isPaid
        ? const Color(0xFFE9FFF8)
        : isJoined
            ? const Color(0xFFEAF2FF)
            : const Color(0xFFEFF3F8);

    final Color fg = isPaid
        ? const Color(0xFF00C9A7)
        : isJoined
            ? const Color(0xFF2E6BE6)
            : const Color(0xFF6B7A90);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }
}
