import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gathergo/app_routes.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/config_service.dart';
import '../../core/services/google_maps_support.dart';
import '../../core/services/session_service.dart';
import '../data/user_booking_store.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';

class BigEventDetailPage extends StatefulWidget {
  final Map<String, dynamic> event;

  const BigEventDetailPage({super.key, required this.event});

  @override
  State<BigEventDetailPage> createState() => _BigEventDetailPageState();
}

class _BigEventDetailPageState extends State<BigEventDetailPage> {
  static const int _galleryLoopBasePage = 10000;
  static const List<String> _defaultShirtSizes = <String>[
    'XS',
    'S',
    'M',
    'L',
    'XL',
  ];

  final PageController _galleryController =
      PageController(initialPage: _galleryLoopBasePage);
  Timer? _galleryTimer;
  List<String> _imageUrls = <String>[];
  int _galleryIndex = 0;
  int _galleryLoadVersion = 0;
  List<_RewardGalleryItem> _guaranteedItems = <_RewardGalleryItem>[];
  List<_RewardGalleryItem> _competitionRewardItems = <_RewardGalleryItem>[];
  String? _selectedShirtSize;

  Map<String, dynamic> get event => widget.event;
  String get _baseUrl => ConfigService.getBaseUrl();

  static const Map<String, Map<String, String>> _rewardTypeLabels =
      <String, Map<String, String>>{
    'shirt': <String, String>{
      'th': 'เสื้อวิ่ง',
      'en': 'Running shirt',
      'zh': '跑步衣',
    },
    'bib_pack': <String, String>{
      'th': 'ชุดบิบ',
      'en': 'Bib pack',
      'zh': '号码布套装',
    },
    'wristband': <String, String>{
      'th': 'สายรัดข้อมือ',
      'en': 'Wristband',
      'zh': '腕带',
    },
    'tote_bag': <String, String>{
      'th': 'ถุงผ้า',
      'en': 'Tote bag',
      'zh': '帆布袋',
    },
    'souvenir': <String, String>{
      'th': 'ของที่ระลึก',
      'en': 'Souvenir',
      'zh': '纪念品',
    },
    'snack': <String, String>{
      'th': 'อาหารว่าง',
      'en': 'Snack',
      'zh': '零食',
    },
    'medal': <String, String>{
      'th': 'เหรียญรางวัล',
      'en': 'Medal',
      'zh': '奖牌',
    },
    'trophy': <String, String>{
      'th': 'ถ้วยรางวัล',
      'en': 'Trophy',
      'zh': '奖杯',
    },
    'finisher_award': <String, String>{
      'th': 'รางวัลผู้เข้าเส้นชัย',
      'en': 'Finisher award',
      'zh': '完赛奖励',
    },
    'rank_award': <String, String>{
      'th': 'รางวัลอันดับ',
      'en': 'Rank award',
      'zh': '名次奖励',
    },
    'certificate': <String, String>{
      'th': 'ประกาศนียบัตร',
      'en': 'Certificate',
      'zh': '证书',
    },
    'other': <String, String>{
      'th': 'ของรางวัล',
      'en': 'Reward item',
      'zh': '奖励物品',
    },
  };

  @override
  void initState() {
    super.initState();
    final incomingShirtSize = (event['shirt_size'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    if (incomingShirtSize.isNotEmpty) {
      _selectedShirtSize = incomingShirtSize;
    }
    _loadGallery();
    _loadRewardItems();
  }

  @override
  void dispose() {
    _galleryTimer?.cancel();
    _galleryController.dispose();
    super.dispose();
  }

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  String _rewardTypeLabel(String type) {
    final languageCode = UserLocaleController.languageCode.value;
    final labels = _rewardTypeLabels[type] ?? _rewardTypeLabels['other']!;
    return labels[languageCode] ?? labels['en'] ?? 'Reward item';
  }

  bool get _requiresShirtSize {
    if (event['requires_shirt_size'] == true) return true;
    for (final item in _guaranteedItems) {
      if (_isShirtItem(item)) return true;
    }
    return false;
  }

  List<String> get _shirtSizeOptions {
    final raw = event['shirt_size_options'];
    if (raw is List) {
      final values = raw
          .map((item) => item.toString().trim().toUpperCase())
          .where((item) => item.isNotEmpty)
          .toList();
      if (values.isNotEmpty) return values;
    }
    return _defaultShirtSizes;
  }

  bool _isShirtItem(_RewardGalleryItem item) {
    return item.itemType.trim().toLowerCase() == 'shirt';
  }

  Future<void> _toggleFavorite(BuildContext context) async {
    final isFavorite = await UserBookingStore.toggleFavoriteBigEvent(event);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            isFavorite
                ? tr('booking_saved_successfully')
                : tr('removed_from_favorites'),
          ),
        ),
      );
  }

  Future<void> _showSnack(BuildContext context, String message) async {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _prettyDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return "${dt.year}-${two(dt.month)}-${two(dt.day)}";
    } catch (_) {
      return iso;
    }
  }

  String _prettyTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      return "${two(dt.hour)}:${two(dt.minute)}";
    } catch (_) {
      return "-";
    }
  }

  String _distanceWithKm(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') return '-';
    return normalized.toUpperCase().contains('KM')
        ? normalized
        : '$normalized KM';
  }

  num _toNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v;
    return num.tryParse(v.toString()) ?? 0;
  }

  int? _expectedImageCount() {
    final raw =
        (event["image_count"] ?? event["imageCount"] ?? event["media_count"])
            .toString()
            .trim();
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  String _galleryDedupKey(String raw) {
    final normalized = _toFullUrl(raw);
    if (normalized.isEmpty) return '';

    final uri = Uri.tryParse(normalized);
    if (uri == null) return normalized.toLowerCase();

    final path = uri.path.toLowerCase().replaceAll(RegExp('/+'), '/');
    return uri.replace(query: '', fragment: '').resolve(path).toString();
  }

  String _toFullUrl(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return "";
    if (s.startsWith("http://") || s.startsWith("https://")) return s;
    if (s.startsWith("/")) return "$_baseUrl$s";
    return "$_baseUrl/$s";
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Future<void> _openInGoogleMaps(double lat, double lng) async {
    final uri =
        Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$lng");
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw Exception("Could not launch Google Maps");
    }
  }

  Future<void> _openJoinFlow(BuildContext context) async {
    final eventId = event['id'] ?? event['event_id'];
    if (eventId == null) return;
    final userId = await SessionService.getCurrentUserId();
    debugPrint("[JoinBigEvent] session userId=$userId");
    if (userId == null || userId <= 0) {
      if (context.mounted) {
        await _showSnack(context, tr('please_log_in_again'));
      }
      return;
    }

    Navigator.pushNamed(
      context,
      AppRoutes.userEventPayment,
      arguments: {
        'baseUrl': _baseUrl,
        'base_url': _baseUrl,
        'event': event,
        'eventId': eventId,
        'event_id': eventId,
        'bookingId': null,
        'booking_id': null,
        'userId': userId,
        'user_id': userId,
        'paymentMode': event['payment_mode'],
        'payment_mode': event['payment_mode'],
        'eventTitle': event['title'],
        'event_title': event['title'],
        'eventDate': event['start_at'] ?? event['date'],
        'event_date': event['start_at'] ?? event['date'],
        'amount': event['fee'] ?? event['price'],
        'price': event['fee'] ?? event['price'],
        'currency': event['currency'] ?? 'THB',
        'shirt_size': _selectedShirtSize,
      },
    );
  }

  void _restartGalleryTimer() {
    _galleryTimer?.cancel();
    if (!mounted || _imageUrls.length <= 1) return;

    _galleryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted ||
          !_galleryController.hasClients ||
          _imageUrls.length <= 1) {
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
    if (_imageUrls.length <= 1 || !_galleryController.hasClients) return;
    final currentPage =
        _galleryController.page?.round() ?? _galleryLoopBasePage;
    _galleryController.animateToPage(
      currentPage + delta,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  Future<void> _loadGallery() async {
    final loadVersion = ++_galleryLoadVersion;
    final urls = <String>[];
    final seenKeys = <String>{};

    void addUrl(String rawUrl) {
      final normalized = _toFullUrl(rawUrl);
      final dedupKey = _galleryDedupKey(rawUrl);
      if (normalized.isEmpty || dedupKey.isEmpty || !seenKeys.add(dedupKey)) {
        return;
      }
      urls.add(normalized);
    }

    addUrl((event["image"] ?? event["cover_url"] ?? "").toString());

    final eventId = int.tryParse('${event["id"] ?? event["event_id"] ?? ""}');
    if (eventId != null) {
      try {
        final res = await http.get(
          Uri.parse("$_baseUrl/api/events/$eventId/media"),
          headers: const {'Accept': 'application/json'},
        );
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is! Map) continue;
              final kind = (item["kind"] ?? "").toString().trim().toLowerCase();
              if (kind.isNotEmpty && kind != "cover" && kind != "gallery") {
                continue;
              }
              addUrl((item["file_url"] ?? item["fileUrl"] ?? "").toString());
            }
          }
        }
      } catch (_) {}
    }

    final expectedCount = _expectedImageCount();
    final normalizedUrls =
        (expectedCount != null && urls.length > expectedCount)
            ? urls.take(expectedCount).toList(growable: false)
            : urls;

    if (!mounted || loadVersion != _galleryLoadVersion) return;
    setState(() {
      _imageUrls = normalizedUrls;
      _galleryIndex = 0;
    });
    if (_galleryController.hasClients) {
      _galleryController.jumpToPage(_galleryLoopBasePage);
    }
    _restartGalleryTimer();
  }

  List<_RewardGalleryItem> _parseRewardItems(dynamic rawItems) {
    if (rawItems is! List) return const <_RewardGalleryItem>[];

    final items = <_RewardGalleryItem>[];
    for (final rawItem in rawItems) {
      if (rawItem is! Map) continue;
      final item = Map<String, dynamic>.from(rawItem);
      final imageUrl = _toFullUrl(
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

    final eventId = int.tryParse('${event["id"] ?? event["event_id"] ?? ""}');
    if (eventId == null) return;

    try {
      final res = await http.get(
        Uri.parse("$_baseUrl/api/events/$eventId"),
        headers: const {'Accept': 'application/json'},
      );
      if (res.statusCode != 200) return;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return;
      final detail = Map<String, dynamic>.from(decoded);
      final guaranteed = _parseRewardItems(detail['guaranteed_items']);
      final competition = _parseRewardItems(detail['competition_reward_items']);

      if (!mounted) return;
      setState(() {
        _guaranteedItems = guaranteed;
        _competitionRewardItems = competition;
      });
    } catch (_) {}
  }

  Future<void> _showRewardPreview(_RewardGalleryItem item) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final showShirtSizePicker =
                _requiresShirtSize && _isShirtItem(item);
            final shirtSizes = _shirtSizeOptions;
            return Dialog(
              insetPadding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.displayLabel(_rewardTypeLabel),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: InteractiveViewer(
                        child: Image.network(
                          item.imageUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Container(
                            height: 220,
                            color: const Color(0xFFF1F4FA),
                            alignment: Alignment.center,
                            child: const Icon(Icons.image_not_supported),
                          ),
                        ),
                      ),
                    ),
                    if (showShirtSizePicker) ...[
                      const SizedBox(height: 14),
                      Text(
                        tr('choose_shirt_size'),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: shirtSizes.map((size) {
                          final selected = _selectedShirtSize == size;
                          return ChoiceChip(
                            label: Text(size),
                            selected: selected,
                            onSelected: (_) {
                              setState(() => _selectedShirtSize = size);
                              setDialogState(() {});
                            },
                            selectedColor: const Color(0xFFDDEAFF),
                            labelStyle: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? const Color(0xFF1D4ED8)
                                  : Colors.black87,
                            ),
                            side: BorderSide(
                              color: selected
                                  ? const Color(0xFF60A5FA)
                                  : Colors.black12,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (item.caption.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        item.caption,
                        style: const TextStyle(color: Color(0xFF4B5563)),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _galleryFallback() {
    return Container(
      color: const Color(0xFFF1F4FA),
      alignment: Alignment.center,
      child: const Icon(Icons.image_not_supported),
    );
  }

  Widget _buildEventGallery() {
    if (_imageUrls.isEmpty) {
      return _galleryFallback();
    }

    if (_imageUrls.length == 1) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _imageUrls.first,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _galleryFallback(),
          ),
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
            final imageIndex = index % _imageUrls.length;
            return Image.network(
              _imageUrls[imageIndex],
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _galleryFallback(),
            );
          },
          onPageChanged: (index) {
            if (!mounted) return;
            setState(() => _galleryIndex = index % _imageUrls.length);
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
            label: '${_galleryIndex + 1}/${_imageUrls.length}',
          ),
        ),
      ],
    );
  }

  Widget _buildWebMapSetupMessage() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4FA),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      alignment: Alignment.centerLeft,
      child: Text(
        tr('google_maps_web_not_configured'),
      ),
    );
  }

  Widget _infoField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(color: Color(0xFF111827)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE6EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }

  Widget _buildRewardSection({
    required String title,
    required List<_RewardGalleryItem> items,
  }) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return _sectionCard(
      title: title,
      children: [
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              return InkWell(
                onTap: () => _showRewardPreview(item),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 156,
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 112,
                          width: double.infinity,
                          color: Colors.white,
                          padding: const EdgeInsets.all(8),
                          child: Image.network(
                            item.imageUrl,
                            fit: BoxFit.contain,
                            alignment: Alignment.center,
                            errorBuilder: (_, __, ___) => _galleryFallback(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _RewardTypeChip(label: _rewardTypeLabel(item.itemType)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: UserLocaleController.languageCode,
      builder: (context, _, __) {
        final String title =
            (event["title"] ?? UserStrings.bigEventTerm).toString();
        final String organizer =
            (event["organization_name"] ?? event["organizer"] ?? "-")
                .toString();
        final String rawLocationName =
            (event["location_name"] ?? event["meeting_point"] ?? "")
                .toString()
                .trim();
        final String locationName = rawLocationName.isEmpty
            ? tr('location_not_specified')
            : rawLocationName;
        final String meetingPointNote =
            (event["meeting_point_note"] ?? "").toString().trim();
        final String date =
            (event["start_at"] ?? event["date"] ?? event["event_date"] ?? "-")
                .toString();

        final double? distancePerLapNum =
            double.tryParse((event["distance_per_lap"] ?? "").toString());
        final int? numberOfLapsNum =
            int.tryParse((event["number_of_laps"] ?? "").toString());
        final double? totalDistanceNum =
            double.tryParse((event["total_distance"] ?? "").toString());
        final String fallbackTotalDistance = (event["total_distance"] ??
                event["display_code"] ??
                event["code"] ??
                "0")
            .toString();

        String fmtDouble(double v) =>
            (v % 1 == 0) ? v.toStringAsFixed(0) : v.toStringAsFixed(2);
        final String distancePerLapText = distancePerLapNum == null
            ? "-"
            : _distanceWithKm(fmtDouble(distancePerLapNum));
        final String numberOfLapsText =
            numberOfLapsNum == null ? "-" : numberOfLapsNum.toString();
        final String totalDistanceText = (distancePerLapNum != null &&
                numberOfLapsNum != null)
            ? _distanceWithKm(fmtDouble(distancePerLapNum * numberOfLapsNum))
            : (totalDistanceNum != null
                ? _distanceWithKm(fmtDouble(totalDistanceNum))
                : _distanceWithKm(fallbackTotalDistance));

        final num feeNum = _toNum(event["promptpay_amount_thb"] ??
            event["fee"] ??
            event["price"] ??
            0);
        final String feeText = feeNum.toStringAsFixed(2);
        final String desc = (event["description"] ?? "-").toString();
        final double? lat =
            _parseDouble(event["location_lat"] ?? event["latitude"]);
        final double? lng =
            _parseDouble(event["location_lng"] ?? event["longitude"]);
        final bool canRenderEmbeddedMap = !kIsWeb || isGoogleMapsAvailable();

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFF),
          appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              title,
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          body: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionCard(
                    title: tr('event_information'),
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          height: 190,
                          width: double.infinity,
                          child: _buildEventGallery(),
                        ),
                      ),
                      const SizedBox(height: 14),
                      _infoField(tr('organizer'), organizer),
                      _infoField(tr('location'), locationName),
                      Row(
                        children: [
                          Expanded(
                            child: _infoField(
                              tr('date'),
                              date == "-" ? "-" : _prettyDate(date),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _infoField(
                              tr('time'),
                              date == "-" ? "-" : _prettyTime(date),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: _infoField(
                              tr('distance_per_lap'),
                              _distanceWithKm(distancePerLapText),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _infoField(
                              tr('number_of_laps'),
                              numberOfLapsText,
                            ),
                          ),
                        ],
                      ),
                      _infoField(
                        tr('total_distance'),
                        _distanceWithKm(totalDistanceText),
                      ),
                      _infoField(tr('fee'), "$feeText THB"),
                      _infoField(tr('description'), desc),
                    ],
                  ),
                  if (_guaranteedItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildRewardSection(
                      title: tr('guaranteed_items'),
                      items: _guaranteedItems,
                    ),
                  ],
                  if (_competitionRewardItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _buildRewardSection(
                      title: tr('competition_rewards'),
                      items: _competitionRewardItems,
                    ),
                  ],
                  const SizedBox(height: 12),
                  _sectionCard(
                    title: tr('location'),
                    children: [
                      if (lat != null && lng != null && canRenderEmbeddedMap)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            height: 220,
                            child: GoogleMap(
                              initialCameraPosition: CameraPosition(
                                target: LatLng(lat, lng),
                                zoom: 15,
                              ),
                              markers: {
                                Marker(
                                  markerId: const MarkerId('event_location'),
                                  position: LatLng(lat, lng),
                                ),
                              },
                              zoomControlsEnabled: true,
                              myLocationButtonEnabled: false,
                            ),
                          ),
                        )
                      else if (lat != null && lng != null)
                        _buildWebMapSetupMessage()
                      else
                        Container(
                          height: 120,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F4FA),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(tr('location_not_specified')),
                        ),
                      const SizedBox(height: 10),
                      Text(
                        locationName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        meetingPointNote.isEmpty
                            ? tr('meeting_point_not_provided')
                            : tr(
                                'meeting_point_with_value',
                                params: {'value': meetingPointNote},
                              ),
                        style: const TextStyle(color: Color(0xFF4B5563)),
                      ),
                      const SizedBox(height: 12),
                      if (lat != null && lng != null)
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await _openInGoogleMaps(lat, lng);
                            } catch (e) {
                              if (!context.mounted) return;
                              await _showSnack(
                                context,
                                tr(
                                  'open_map_failed',
                                  params: {'error': e.toString()},
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.open_in_new),
                          label: Text(tr('open_in_google_maps')),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          bottomSheet: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFF),
              border: Border(
                top: BorderSide(color: Color(0xFFE5E7EB)),
              ),
            ),
            child: Row(
              children: [
                ValueListenableBuilder<List<Map<String, dynamic>>>(
                  valueListenable: UserBookingStore.favoriteBigEvents,
                  builder: (context, _, __) {
                    final isFavorite = UserBookingStore.isFavorite(event);
                    return SizedBox(
                      width: 76,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () => _toggleFavorite(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: isFavorite
                              ? const Color(0xFFE5486B)
                              : const Color(0xFF111827),
                          elevation: 0,
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        child: Icon(
                          isFavorite ? Icons.favorite : Icons.favorite_border,
                          size: 28,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () => _openJoinFlow(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF4C542),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: Text(
                        tr('join'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Colors.black,
                          fontSize: 18,
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
