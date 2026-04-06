import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app_routes.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../../widgets/common/app_nav_bar.dart';
import '../big_event/big_event_detail_page.dart';
import '../data/user_booking_store.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';
import '../spot/spot_detail_page.dart';

class BookingPage extends StatefulWidget {
  const BookingPage({super.key});

  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _bookedSpots = [];

  String get _baseUrl => ConfigService.getBaseUrl();

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    _loadBookedSpots();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  Future<void> _loadBookedSpots() async {
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

      final uri = Uri.parse('$_baseUrl/api/spots');
      final res = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'x-user-id': userId.toString(),
        },
      ).timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        throw Exception('HTTP ${res.statusCode}: ${res.body}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw Exception('Invalid response format');
      }

      final items = decoded
          .whereType<Map>()
          .map((row) => _mapBackendSpot(Map<String, dynamic>.from(row)))
          .where((spot) => spot['isBooked'] == true && spot['isJoined'] != true)
          .toList();

      if (!mounted) return;
      setState(() {
        _bookedSpots = items;
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
    final imageUrl = (row['image_url'] ?? '').toString().trim();
    final directTotal =
        double.tryParse((row['total_distance'] ?? '').toString().trim());
    final kmPerRound =
        double.tryParse((row['km_per_round'] ?? '').toString().trim()) ?? 0;
    final roundCount =
        double.tryParse((row['round_count'] ?? '').toString().trim()) ?? 0;
    final computedTotal = directTotal ?? (kmPerRound * roundCount);
    final totalDistanceText = computedTotal == computedTotal.roundToDouble()
        ? computedTotal.toStringAsFixed(0)
        : computedTotal.toStringAsFixed(2);
    return {
      ...row,
      'backendSpotId': row['id'],
      'id': row['id'],
      'spotKey': (row['spot_key'] ?? '').toString(),
      'spot_key': (row['spot_key'] ?? '').toString(),
      'title': (row['title'] ?? '').toString(),
      'description': (row['description'] ?? '').toString(),
      'location': (row['location'] ?? '').toString(),
      'locationLink': (row['location_link'] ?? '').toString(),
      'location_lat': row['location_lat'],
      'location_lng': row['location_lng'],
      'locationLat': row['location_lat'],
      'locationLng': row['location_lng'],
      'province': (row['province'] ?? '').toString(),
      'district': (row['district'] ?? '').toString(),
      'date': (row['event_date'] ?? '').toString(),
      'time': (row['event_time'] ?? '').toString(),
      'kmPerRound': (row['km_per_round'] ?? '').toString(),
      'round': (row['round_count'] ?? '').toString(),
      'total_distance': totalDistanceText,
      'distance': '$totalDistanceText KM',
      'creatorName': (row['creator_name'] ?? 'User').toString(),
      'creatorUserId': (row['created_by_user_id'] ?? '').toString(),
      'creatorRole': (row['creator_role'] ?? 'user').toString(),
      'image': imageUrl.isNotEmpty ? ConfigService.resolveUrl(imageUrl) : '',
      'imageBase64': (row['image_base64'] ?? '').toString(),
      'isBooked': row['is_booked'] == true,
      'is_booked': row['is_booked'] == true,
      'isJoined': row['is_joined'] == true,
      'is_joined': row['is_joined'] == true,
      'booking_reference': (row['booking_reference'] ?? '').toString(),
    };
  }

  String _totalKmLabel(Map<String, dynamic> spot) {
    final perRound =
        double.tryParse((spot['kmPerRound'] ?? '').toString().trim()) ?? 0;
    final rounds =
        double.tryParse((spot['round'] ?? '').toString().trim()) ?? 0;
    final total = perRound * rounds;
    final text =
        total % 1 == 0 ? total.toStringAsFixed(0) : total.toStringAsFixed(2);
    return '$text KM';
  }

  Widget _buildSpotImage(Map<String, dynamic> spot) {
    final b64 = (spot['imageBase64'] ?? '').toString().trim();
    if (b64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(b64),
          width: 88,
          height: 88,
          fit: BoxFit.cover,
        );
      } catch (_) {}
    }

    final image = (spot['image'] ?? '').toString();
    if (image.isEmpty) {
      return _imageFallback();
    }
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return Image.network(
        image,
        width: 88,
        height: 88,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imageFallback(),
      );
    }

    return Image.asset(
      image,
      width: 88,
      height: 88,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _imageFallback(),
    );
  }

  Widget _imageFallback() {
    return Container(
      width: 88,
      height: 88,
      color: const Color(0xFFF1F4FA),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported),
    );
  }

  Future<void> _removeFavorite(Map<String, dynamic> item) async {
    await UserBookingStore.removeFavoriteBigEvent(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(tr('removed_from_favorites'))));
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: SafeArea(
        child: Column(
          children: [
            AppNavBar(
              title: tr('booking'),
              showBack: true,
              onBack: () => Navigator.pushNamedAndRemoveUntil(
                context,
                AppRoutes.userHome,
                (route) => false,
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadBookedSpots,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                  children: [
                    _SectionTitle(
                      title: tr('spot_booking'),
                      subtitle: tr('booked_spots_waiting_join'),
                    ),
                    const SizedBox(height: 10),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_error != null)
                      _ErrorCard(
                        message: _error!,
                        onRetry: _loadBookedSpots,
                      )
                    else if (_bookedSpots.isEmpty)
                      _EmptyCard(
                        text: tr('no_pending_spot_bookings_yet'),
                      )
                    else
                      ..._bookedSpots.map(
                        (spot) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SpotBookingCard(
                            spot: spot,
                            totalKmLabel: _totalKmLabel(spot),
                            image: _buildSpotImage(spot),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const SpotDetailPage(),
                                  settings: RouteSettings(arguments: spot),
                                ),
                              ).then((_) => _loadBookedSpots());
                            },
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    _SectionTitle(
                      title: tr('big_event_favorite'),
                      subtitle: tr('saved_big_events_unpaid'),
                    ),
                    const SizedBox(height: 10),
                    ValueListenableBuilder<List<Map<String, dynamic>>>(
                      valueListenable: UserBookingStore.favoriteBigEvents,
                      builder: (context, favorites, _) {
                        if (favorites.isEmpty) {
                          return _EmptyCard(
                            text: tr('no_favorite_big_events_yet'),
                          );
                        }

                        return Column(
                          children: favorites
                              .map(
                                (item) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _BigEventFavoriteCard(
                                    item: item,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              BigEventDetailPage(event: item),
                                        ),
                                      );
                                    },
                                    onRemove: () => _removeFavorite(item),
                                  ),
                                ),
                              )
                              .toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String text;

  const _EmptyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.black54,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD6D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            UserStrings.text('load_failed', params: {'error': message}),
            style: const TextStyle(color: Colors.red),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onRetry,
            child: Text(UserStrings.text('retry')),
          ),
        ],
      ),
    );
  }
}

class _SpotBookingCard extends StatelessWidget {
  final Map<String, dynamic> spot;
  final String totalKmLabel;
  final Widget image;
  final VoidCallback onTap;

  const _SpotBookingCard({
    required this.spot,
    required this.totalKmLabel,
    required this.image,
    required this.onTap,
  });

  String _shortLocation() {
    final province = (spot['province'] ?? '').toString().trim();
    final district = (spot['district'] ?? '').toString().trim();

    if (province.isNotEmpty && district.isNotEmpty) {
      return '$province, $district';
    }
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;

    final raw = (spot['location'] ?? '-').toString().trim();
    if (raw.isEmpty) return '-';

    final parts = raw
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 2) {
      return '${parts[parts.length - 1]}, ${parts[parts.length - 2]}';
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFD7DEE8)),
        ),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 88,
                    height: 88,
                    child: image,
                  ),
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
                              (spot['title'] ?? '-').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF222222),
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF97A0AF),
                            size: 26,
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        UserStrings.text(
                          'location_with_value',
                          params: {'value': _shortLocation()},
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        UserStrings.text(
                          'date_with_value',
                          params: {
                            'value': (spot['date'] ?? '-').toString(),
                          },
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        UserStrings.text(
                          'total_with_value',
                          params: {'value': totalKmLabel},
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BigEventFavoriteCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _BigEventFavoriteCard({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  Widget _buildImage() {
    final image = (item['image'] ?? item['cover_url'] ?? '').toString();
    if (image.startsWith('http://') || image.startsWith('https://')) {
      return Image.network(
        image,
        width: 88,
        height: 88,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return Image.asset(
      image.isEmpty ? 'assets/images/user/events/event1.png' : image,
      width: 88,
      height: 88,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _fallback(),
    );
  }

  Widget _fallback() {
    return Container(
      width: 88,
      height: 88,
      color: const Color(0xFFF1F4FA),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported),
    );
  }

  String _priceLabel() {
    final raw = (item['fee'] ?? item['price'] ?? '0').toString();
    final currency =
        (item['currency'] ?? item['fee_currency'] ?? 'THB').toString();
    final value = num.tryParse(raw);
    if (value == null) return '$raw $currency';
    final price =
        value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
    return '$price $currency';
  }

  List<String> _chips() {
    final location =
        (item['location_display'] ?? item['location'] ?? '').toString().trim();
    final code =
        (item['distance'] ?? item['display_code'] ?? item['code'] ?? '')
            .toString()
            .trim();
    final lap = (item['distance_per_lap'] ?? '').toString().trim();
    final organizer = (item['organizer'] ?? '').toString().trim();

    return [
      if (location.isNotEmpty) 'Location: $location',
      if (code.isNotEmpty) 'Code: $code',
      if (lap.isNotEmpty) 'Lap: $lap',
      if (organizer.isNotEmpty) 'Organizer: $organizer',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final chips = _chips();

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 14, 18, 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD8DEE8)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 88,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _buildImage(),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.black),
                    ),
                    child: Text(
                      _priceLabel(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.black,
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            (item['title'] ?? '-').toString(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: onRemove,
                        icon: const Icon(
                          Icons.favorite,
                          color: Color(0xFFE5486B),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        splashRadius: 20,
                        tooltip: UserStrings.text('remove_favorite'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: chips
                        .map(
                          (chip) => Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xFFE0E0E0),
                              ),
                            ),
                            child: Text(
                              chip,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                  if (chips.isEmpty)
                    const Text(
                      '-',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
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
}
