import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:geocoding/geocoding.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/config_service.dart';
import '../../core/services/spot_map_launcher.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';

class JoinedEventDetailPage extends StatefulWidget {
  final Map<String, dynamic> event;

  const JoinedEventDetailPage({
    super.key,
    required this.event,
  });

  @override
  State<JoinedEventDetailPage> createState() => _JoinedEventDetailPageState();
}

class _JoinedEventDetailPageState extends State<JoinedEventDetailPage> {
  static const int _galleryLoopBasePage = 10000;

  String? _resolvedLocation;
  bool _resolvingLocation = false;
  final PageController _galleryController =
      PageController(initialPage: _galleryLoopBasePage);
  Timer? _galleryTimer;
  List<Map<String, dynamic>> _galleryItems = <Map<String, dynamic>>[];
  int _galleryIndex = 0;
  int _galleryLoadVersion = 0;
  List<_RewardGalleryItem> _guaranteedItems = <_RewardGalleryItem>[];
  List<_RewardGalleryItem> _competitionRewardItems = <_RewardGalleryItem>[];

  Map<String, dynamic> get event => widget.event;

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    _resolveLocationLabel();
    _loadGallery();
    _loadRewardItems();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
    _resolveLocationLabel();
  }

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _galleryTimer?.cancel();
    _galleryController.dispose();
    super.dispose();
  }

  DateTime? _parseDateTime(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty || text == '-') return null;
    return DateTime.tryParse(text)?.toLocal();
  }

  String _formatDate(DateTime? value) {
    if (value == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)}';
  }

  String _formatTime(DateTime? value) {
    if (value == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.hour)}:${two(value.minute)}';
  }

  String _valueOf(dynamic value) => (value ?? '').toString().trim();

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
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

  bool _containsThai(String value) {
    return RegExp(r'[\u0E00-\u0E7F]').hasMatch(value);
  }

  String _networkDedupKey(String rawUrl) {
    final resolved = ConfigService.resolveUrl(rawUrl.trim());
    if (resolved.isEmpty) return '';

    final uri = Uri.tryParse(resolved);
    if (uri == null) return resolved.toLowerCase();

    final normalizedPath = uri.path.toLowerCase().replaceAll(RegExp('/+'), '/');
    return uri
        .replace(path: normalizedPath, query: '', fragment: '')
        .toString();
  }

  bool _isAssetPath(String value) => value.trim().startsWith('assets/');

  String _composeDistrictProvince(String district, String province) {
    if (district.isNotEmpty && province.isNotEmpty) {
      return '$province, $district';
    }
    if (province.isNotEmpty) return province;
    if (district.isNotEmpty) return district;
    return '';
  }

  String _displayLocation() {
    if ((_resolvedLocation ?? '').trim().isNotEmpty) {
      return _resolvedLocation!.trim();
    }

    final district = _valueOf(
      event['district'] ??
          event['district_name'] ??
          event['amphoe'] ??
          event['city'],
    );
    final province = _valueOf(event['province']);
    final districtProvince = _composeDistrictProvince(district, province);
    if (districtProvince.isNotEmpty) return districtProvince;

    final meetingPoint = _valueOf(event['meeting_point']);
    if (meetingPoint.isNotEmpty) return meetingPoint;
    final location = _valueOf(event['location']);
    if (location.isNotEmpty) return location;
    return '-';
  }

  Future<void> _resolveLocationLabel() async {
    final district = _valueOf(
      event['district'] ??
          event['district_name'] ??
          event['amphoe'] ??
          event['city'],
    );
    final province = _valueOf(event['province']);
    final directLabel = _composeDistrictProvince(district, province);
    final shouldUseDirectLabel =
        directLabel.isNotEmpty && !_containsThai(directLabel);

    if (shouldUseDirectLabel) {
      setState(() => _resolvedLocation = directLabel);
      return;
    }

    final lat = _asDouble(event['location_lat'] ?? event['latitude']);
    final lng = _asDouble(event['location_lng'] ?? event['longitude']);
    if (lat == null || lng == null) return;

    setState(() => _resolvingLocation = true);
    try {
      await setLocaleIdentifier('en_US');
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (!mounted || placemarks.isEmpty) return;

      final placemark = placemarks.first;
      final provinceName = _valueOf(
        placemark.administrativeArea ?? placemark.subAdministrativeArea,
      );
      final districtName = _valueOf(
        placemark.subAdministrativeArea ??
            placemark.locality ??
            placemark.subLocality,
      );
      final label = districtName.isNotEmpty && provinceName.isNotEmpty
          ? '$provinceName, $districtName'
          : (provinceName.isNotEmpty ? provinceName : districtName);
      if (label.isNotEmpty) {
        setState(() => _resolvedLocation = label);
      } else if (directLabel.isNotEmpty && mounted) {
        setState(() => _resolvedLocation = directLabel);
      }
    } catch (_) {
      if (directLabel.isNotEmpty && mounted) {
        setState(() => _resolvedLocation = directLabel);
      }
    } finally {
      if (mounted) {
        setState(() => _resolvingLocation = false);
      }
    }
  }

  String _displayMethod(String value) {
    switch (value.trim().toUpperCase()) {
      case 'PROMPTPAY':
        return 'PromptPay';
      default:
        return value.trim();
    }
  }

  String _displayProvider(String value) {
    switch (value.trim().toUpperCase()) {
      case 'STRIPE':
        return 'Stripe';
      case 'MANUAL_QR':
        return 'Manual QR';
      default:
        return value.trim();
    }
  }

  bool _hasValue(dynamic value) =>
      _valueOf(value).isNotEmpty && _valueOf(value) != '-';

  String _distanceWithKm(dynamic value) {
    final normalized = _valueOf(value);
    if (normalized.isEmpty || normalized == '-') return '-';
    return normalized.toUpperCase().contains('KM')
        ? normalized
        : '$normalized KM';
  }

  String _rewardTypeLabel(String type) {
    switch (type.trim().toLowerCase()) {
      case 'shirt':
        return tr('shirt_size');
      case 'bib_pack':
        return 'Bib pack';
      case 'wristband':
        return 'Wristband';
      case 'tote_bag':
        return 'Tote bag';
      case 'souvenir':
        return 'Souvenir';
      case 'snack':
        return 'Snack';
      case 'medal':
        return 'Medal';
      case 'trophy':
        return 'Trophy';
      case 'finisher_award':
        return 'Finisher award';
      case 'rank_award':
        return 'Rank award';
      case 'certificate':
        return 'Certificate';
      default:
        return 'Reward item';
    }
  }

  bool _isShirtItem(_RewardGalleryItem item) {
    return item.itemType.trim().toLowerCase() == 'shirt';
  }

  int? _expectedImageCount() {
    final raw = _valueOf(
      event['image_count'] ?? event['imageCount'] ?? event['media_count'],
    );
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  bool _looksLikeImage(String url) {
    final lower = url.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp');
  }

  List<_RewardGalleryItem> _parseRewardItems(dynamic rawItems) {
    if (rawItems is! List) return const <_RewardGalleryItem>[];

    final items = <_RewardGalleryItem>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final imageUrl = ConfigService.resolveUrl(
        (item['image_url'] ?? item['imageUrl'] ?? '').toString(),
      );
      if (imageUrl.isEmpty) continue;
      items.add(
        _RewardGalleryItem(
          imageUrl: imageUrl,
          itemType: (item['item_type'] ?? item['itemType'] ?? '').toString(),
          caption: (item['caption'] ?? '').toString().trim(),
          sortOrder:
              int.tryParse('${item['sort_order'] ?? item['sortOrder'] ?? 0}') ??
                  0,
        ),
      );
    }

    items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return items;
  }

  Future<void> _loadRewardItems() async {
    final initialGuaranteed = _parseRewardItems(event['guaranteed_items']);
    final initialCompetition =
        _parseRewardItems(event['competition_reward_items']);

    if (mounted) {
      setState(() {
        _guaranteedItems = initialGuaranteed;
        _competitionRewardItems = initialCompetition;
      });
    }

    final eventId = int.tryParse(
      _valueOf(event['eventId']).isNotEmpty
          ? _valueOf(event['eventId'])
          : _valueOf(event['id']),
    );
    if (eventId == null || eventId <= 0) return;

    try {
      final res = await http.get(
        Uri.parse('${ConfigService.getBaseUrl()}/api/events/$eventId'),
        headers: const {'Accept': 'application/json'},
      );
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return;
      final detail = Map<String, dynamic>.from(decoded);
      if (!mounted) return;
      setState(() {
        _guaranteedItems = _parseRewardItems(detail['guaranteed_items']);
        _competitionRewardItems =
            _parseRewardItems(detail['competition_reward_items']);
      });
    } catch (_) {}
  }

  Widget _buildRewardSection({
    required String title,
    required List<_RewardGalleryItem> items,
    String? selectedShirtSize,
  }) {
    if (items.isEmpty && (selectedShirtSize ?? '').trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return _SectionCard(
      title: title,
      subtitle: title == tr('competition_rewards')
          ? tr('competition_rewards_subtitle')
          : tr('guaranteed_items_subtitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (items.isNotEmpty)
            SizedBox(
              height: 250,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final isShirt = _isShirtItem(item);
                  final detailText = title == tr('competition_rewards')
                      ? tr('competition_rewards_subtitle')
                      : tr('guaranteed_items_subtitle');
                  return Container(
                    width: 176,
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFF),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x0F0F172A),
                          blurRadius: 14,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 112,
                            width: double.infinity,
                            color: Colors.white,
                            padding: const EdgeInsets.all(8),
                            child: Image.network(
                              item.imageUrl,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _imageFallback(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.displayLabel(_rewardTypeLabel),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (isShirt && (selectedShirtSize ?? '').trim().isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE0ECFF),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${tr('shirt_size')}: ${selectedShirtSize!.trim()}',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                          ),
                        if (isShirt && (selectedShirtSize ?? '').trim().isNotEmpty)
                          const SizedBox(height: 6),
                        Expanded(
                          child: Text(
                            detailText,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openUrl(BuildContext context, String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(tr('could_not_open_link'))));
  }

  Future<void> _openLocation(BuildContext context, String location) async {
    final ok = await SpotMapLauncher.open(
      latitude: event['location_lat'] ?? event['latitude'],
      longitude: event['location_lng'] ?? event['longitude'],
      locationText: location,
    );
    if (!context.mounted || ok) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(tr('location_not_available'))));
  }

  Future<void> _loadGallery() async {
    final loadVersion = ++_galleryLoadVersion;
    final items = <Map<String, dynamic>>[];
    final seenKeys = <String>{};

    void addMemory(String rawBase64) {
      final cleaned = rawBase64
          .trim()
          .replaceFirst(RegExp(r'^data:image\/[^;]+;base64,'), '');
      if (cleaned.isEmpty) return;
      try {
        final bytes = base64Decode(cleaned);
        final encoded = base64Encode(bytes);
        if (!seenKeys.add('memory:$encoded')) return;
        items.add({
          'key': encoded,
          'type': 'memory',
          'bytes': bytes,
        });
      } catch (_) {}
    }

    void addUrl(String rawUrl, {bool asset = false}) {
      final trimmed = rawUrl.trim();
      if (trimmed.isEmpty) return;

      final resolved = asset ? trimmed : ConfigService.resolveUrl(trimmed);
      final dedupKey = asset ? 'asset:$trimmed' : _networkDedupKey(trimmed);
      if (resolved.isEmpty || dedupKey.isEmpty || !seenKeys.add(dedupKey)) {
        return;
      }

      items.add({
        'key': dedupKey,
        'type': asset ? 'asset' : 'network',
        'url': resolved,
      });
    }

    final imageBase64 = _valueOf(event['imageBase64']);
    final image = _valueOf(event['image']).isNotEmpty
        ? _valueOf(event['image'])
        : _valueOf(event['cover_url']);

    if (imageBase64.isNotEmpty) {
      addMemory(imageBase64);
    } else if (_isAssetPath(image)) {
      addUrl(image, asset: true);
    } else if (image.isNotEmpty) {
      addUrl(image);
    }

    final eventId = int.tryParse(
      _valueOf(event['eventId']).isNotEmpty
          ? _valueOf(event['eventId'])
          : _valueOf(event['id']),
    );

    if (eventId != null && eventId > 0) {
      try {
        final res = await http.get(
          Uri.parse('${ConfigService.getBaseUrl()}/api/events/$eventId/media'),
          headers: const {'Accept': 'application/json'},
        );
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is! Map) continue;
              final kind = (item['kind'] ?? '').toString().trim().toLowerCase();
              if (kind.isNotEmpty && kind != 'cover' && kind != 'gallery') {
                continue;
              }
              addUrl((item['file_url'] ?? item['fileUrl'] ?? '').toString());
            }
          }
        }
      } catch (_) {}
    }

    final expectedCount = _expectedImageCount();
    final normalizedItems =
        (expectedCount != null && items.length > expectedCount)
            ? items.take(expectedCount).toList(growable: false)
            : items;

    if (!mounted || loadVersion != _galleryLoadVersion) return;
    setState(() {
      _galleryItems = normalizedItems;
      _galleryIndex = 0;
    });
    if (_galleryController.hasClients) {
      _galleryController.jumpToPage(_galleryLoopBasePage);
    }
    _restartGalleryTimer();
  }

  Widget _buildGalleryImage(Map<String, dynamic> item) {
    final type = (item['type'] ?? '').toString();
    if (type == 'memory') {
      return Image.memory(
        item['bytes'] as Uint8List,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imageFallback(),
      );
    }
    if (type == 'asset') {
      return Image.asset(
        (item['url'] ?? '').toString(),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _imageFallback(),
      );
    }
    return Image.network(
      (item['url'] ?? '').toString(),
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _imageFallback(),
    );
  }

  Widget _buildImage() {
    if (_galleryItems.isEmpty) {
      final imageBase64 = _valueOf(event['imageBase64'])
          .replaceFirst(RegExp(r'^data:image\/[^;]+;base64,'), '');
      if (imageBase64.isNotEmpty) {
        try {
          return Image.memory(
            base64Decode(imageBase64),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _imageFallback(),
          );
        } catch (_) {}
      }

      final image = _valueOf(event['image']).isNotEmpty
          ? _valueOf(event['image'])
          : _valueOf(event['cover_url']);
      if (_isAssetPath(image)) {
        return Image.asset(
          image,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _imageFallback(),
        );
      }
      if (image.isNotEmpty) {
        return Image.network(
          image,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _imageFallback(),
        );
      }
      return _imageFallback();
    }

    if (_galleryItems.length == 1) {
      return Stack(
        fit: StackFit.expand,
        children: [
          _buildGalleryImage(_galleryItems.first),
          const Positioned(
            right: 12,
            bottom: 12,
            child: _GalleryCountBadge(label: '1/1'),
          ),
        ],
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          controller: _galleryController,
          itemBuilder: (_, index) {
            final imageIndex = index % _galleryItems.length;
            return _buildGalleryImage(_galleryItems[imageIndex]);
          },
          onPageChanged: (index) {
            if (!mounted) return;
            setState(() => _galleryIndex = index % _galleryItems.length);
            _restartGalleryTimer();
          },
        ),
        Positioned(
          top: 10,
          left: 10,
          child: _GalleryNavButton(
            icon: Icons.chevron_left,
            onTap: () => _moveGalleryBy(-1),
          ),
        ),
        Positioned(
          top: 10,
          right: 10,
          child: _GalleryNavButton(
            icon: Icons.chevron_right,
            onTap: () => _moveGalleryBy(1),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: _GalleryCountBadge(
            label: '${_galleryIndex + 1}/${_galleryItems.length}',
          ),
        ),
      ],
    );
  }

  Widget _imageFallback() {
    return Container(
      color: const Color(0xFFF1F4FA),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _valueOf(event['title']).isEmpty
        ? tr('joined_event_detail')
        : _valueOf(event['title']);
    final location = _displayLocation();
    final organizer = _valueOf(event['organization_name']).isNotEmpty
        ? _valueOf(event['organization_name'])
        : (_valueOf(event['organizer']).isNotEmpty
            ? _valueOf(event['organizer'])
            : null);
    final description = _valueOf(event['description']);
    final eventDateTime = _parseDateTime(
      event['start_at'] ?? event['date'] ?? event['event_date'],
    );
    final paidAt = _parseDateTime(event['paid_at'] ?? event['payment_date']);
    final paymentStatus = _valueOf(event['payment_status']);
    final paymentMethod = _valueOf(event['payment_method_type']).isNotEmpty
        ? _valueOf(event['payment_method_type'])
        : _valueOf(event['payment_method']);
    final amount = _valueOf(event['payment_amount']);
    final currency = _valueOf(event['currency']);
    final bookingId = _valueOf(event['booking_reference']).isNotEmpty
        ? _valueOf(event['booking_reference'])
        : _valueOf(event['booking_id']);
    final paymentId = _valueOf(event['payment_reference']).isNotEmpty
        ? _valueOf(event['payment_reference'])
        : _valueOf(event['payment_id']);
    final providerTxnId = _valueOf(event['provider_txn_id']);
    final provider = _valueOf(event['payment_provider']).isNotEmpty
        ? _valueOf(event['payment_provider'])
        : _valueOf(event['provider']);
    final receiptNo = _valueOf(event['receipt_no']);
    final receiptIssueDate = _valueOf(event['receipt_issue_date']);
    final slipUrl = _valueOf(event['slip_url']);
    final receiptUrl = _valueOf(event['receipt_url']);
    final selectedShirtSize = _valueOf(event['shirt_size']);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        title: Text(tr('joined_event_detail')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _SectionCard(
              title: tr('event_information'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: 190,
                      width: double.infinity,
                      child: _buildImage(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _InfoRow(
                      label: tr('date'), value: _formatDate(eventDateTime)),
                  if (eventDateTime != null)
                    _InfoRow(
                        label: tr('time'), value: _formatTime(eventDateTime)),
                  _InfoRow(
                    label: tr('location'),
                    value: _resolvingLocation && location == '-'
                        ? tr('resolving_location')
                        : location,
                    onTap: () => _openLocation(context, location),
                    trailing: const Icon(
                      Icons.map_outlined,
                      size: 18,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                  _InfoRow(
                    label: tr('total_distance'),
                    value: _hasValue(event['total_distance'])
                        ? _distanceWithKm(event['total_distance'])
                        : '-',
                  ),
                  if (organizer != null)
                    _InfoRow(label: tr('organizer'), value: organizer),
                  if (description.isNotEmpty)
                    _InfoRow(label: tr('description'), value: description),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _SectionCard(
              title: tr('receipt_payment_information'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_hasValue(paymentStatus))
                    _InfoRow(label: tr('payment_status'), value: paymentStatus),
                  if (_hasValue(paymentMethod))
                    _InfoRow(
                        label: tr('payment_method'),
                        value: _displayMethod(paymentMethod)),
                  if (_hasValue(provider))
                    _InfoRow(
                        label: tr('payment_provider'),
                        value: _displayProvider(provider)),
                  if (_hasValue(amount))
                    _InfoRow(
                      label: tr('amount_paid'),
                      value: currency.isEmpty ? amount : '$amount $currency',
                    ),
                  if (paidAt != null)
                    _InfoRow(
                      label: tr('payment_date'),
                      value: '${_formatDate(paidAt)} ${_formatTime(paidAt)}',
                    ),
                  if (_hasValue(bookingId))
                    _InfoRow(label: tr('booking_reference'), value: bookingId),
                  if (_hasValue(paymentId))
                    _InfoRow(label: tr('payment_reference'), value: paymentId),
                  if (_hasValue(receiptNo))
                    _InfoRow(label: tr('receipt_reference'), value: receiptNo),
                  if (_hasValue(receiptIssueDate))
                    _InfoRow(
                        label: tr('receipt_date'), value: receiptIssueDate),
                  if (_hasValue(providerTxnId))
                    _InfoRow(
                        label: tr('transaction_reference'),
                        value: providerTxnId),
                  if (_hasValue(event['booking_status']))
                    _InfoRow(
                      label: tr('booking_status'),
                      value: _valueOf(event['booking_status']),
                    ),
                  if (slipUrl.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      tr('slip_proof'),
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 220,
                        width: double.infinity,
                        child: Image.network(
                          slipUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: const Color(0xFFF1F4FA),
                            alignment: Alignment.center,
                            child: Text(tr('slip_preview_unavailable')),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () => _openUrl(context, slipUrl),
                      icon: const Icon(Icons.open_in_new),
                      label: Text(tr('open_slip')),
                    ),
                  ],
                  if (receiptUrl.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _openUrl(context, receiptUrl),
                      icon: Icon(
                        _looksLikeImage(receiptUrl)
                            ? Icons.image_outlined
                            : Icons.receipt_long_outlined,
                      ),
                      label: Text(tr('open_receipt')),
                    ),
                  ],
                  if (paymentStatus.isEmpty &&
                      paymentMethod.isEmpty &&
                      amount.isEmpty &&
                      bookingId.isEmpty &&
                      paymentId.isEmpty &&
                      slipUrl.isEmpty &&
                      receiptUrl.isEmpty &&
                      receiptNo.isEmpty &&
                      providerTxnId.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Text(
                        tr('no_receipt_details_available'),
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                ],
              ),
            ),
            if (_guaranteedItems.isNotEmpty || selectedShirtSize.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildRewardSection(
                title: tr('guaranteed_items'),
                items: _guaranteedItems,
                selectedShirtSize: selectedShirtSize,
              ),
            ],
            if (_competitionRewardItems.isNotEmpty) ...[
              const SizedBox(height: 14),
              _buildRewardSection(
                title: tr('competition_rewards'),
                items: _competitionRewardItems,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RewardGalleryItem {
  final String imageUrl;
  final String itemType;
  final String caption;
  final int sortOrder;

  const _RewardGalleryItem({
    required this.imageUrl,
    required this.itemType,
    required this.caption,
    required this.sortOrder,
  });

  String displayLabel(String Function(String type) resolveTypeLabel) {
    final label = caption.trim();
    if (label.isNotEmpty) return label;
    return resolveTypeLabel(itemType);
  }
}

class _RewardTypeChip extends StatelessWidget {
  final String label;

  const _RewardTypeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF1D4ED8),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SectionCard({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          if ((subtitle ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!.trim(),
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _InfoRow({
    required this.label,
    required this.value,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  value,
                  style: TextStyle(
                    color: onTap == null
                        ? Colors.black87
                        : const Color(0xFF1D4ED8),
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: content,
      ),
    );
  }
}

class _GalleryNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GalleryNavButton({
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

class _GalleryCountBadge extends StatelessWidget {
  final String label;

  const _GalleryCountBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
