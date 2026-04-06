import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';

import '../../core/services/config_service.dart';
import '../../core/services/admin_session_service.dart';
import '../data/event_api.dart';
import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';

String get baseUrl => ConfigService.getBaseUrl();

String _two(int n) => n.toString().padLeft(2, '0');
String formatDateTH(DateTime dt) =>
    "${_two(dt.day)}/${_two(dt.month)}/${dt.year}";
String formatTimeTH(DateTime dt) => "${_two(dt.hour)}:${_two(dt.minute)}";

class BigEventDetailPage extends StatefulWidget {
  final int eventId;
  const BigEventDetailPage({super.key, required this.eventId});

  @override
  State<BigEventDetailPage> createState() => _BigEventDetailPageState();
}

class _BigEventDetailPageState extends State<BigEventDetailPage> {
  static const int _galleryLoopBasePage = 10000;
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
      'th': 'อื่น ๆ',
      'en': 'Other',
      'zh': '其他',
    },
  };
  bool _loading = true;
  String? _error;
  BigEventDto? _event;
  final PageController _galleryController =
      PageController(initialPage: _galleryLoopBasePage);
  Timer? _galleryTimer;
  List<String> _imageUrls = <String>[];
  int _galleryIndex = 0;
  bool _deleting = false;
  bool _paymentLoading = false;
  bool _savingPayment = false;
  String? _paymentError;
  String _paymentMode = 'stripe_auto';
  bool _promptpayEnabled = true;
  bool _stripeEnabled = false;
  String? _manualPromptpayQrUrl;
  bool _uploadingPromptpayQr = false;
  final TextEditingController _baseAmount = TextEditingController();

  String _normalizeAdminPaymentMode(String? rawMode) {
    switch ((rawMode ?? '').trim()) {
      case 'stripe_auto':
      case 'manual_qr':
      case 'hybrid':
        return (rawMode ?? '').trim();
      default:
        return 'stripe_auto';
    }
  }

  String _distanceWithKm(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') return '-';
    return normalized.toUpperCase().contains('KM')
        ? normalized
        : '$normalized KM';
  }

  String _t(String key, {Map<String, String> params = const {}}) =>
      AdminStrings.text(key, params: params);

  String _rewardTypeLabel(String type) {
    final normalized = type.trim().toLowerCase();
    final code = AdminLocaleController.languageCode.value;
    final labels = _rewardTypeLabels[normalized] ?? _rewardTypeLabels['other']!;
    return labels[code] ?? labels['en'] ?? normalized;
  }

  @override
  void initState() {
    super.initState();
    _baseAmount.addListener(_paymentInputsChanged);
    _load();
  }

  @override
  void dispose() {
    _galleryTimer?.cancel();
    _galleryController.dispose();
    _baseAmount.dispose();
    super.dispose();
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

  void _paymentInputsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  double? _parseMoney(TextEditingController controller) =>
      double.tryParse(controller.text.trim());

  double _roundMoney(double value) => (value * 100).round() / 100;

  double? get _promptpayAmountThb {
    final baseAmount = _parseMoney(_baseAmount);
    if (baseAmount == null || baseAmount <= 0) return null;
    return _roundMoney(baseAmount);
  }

  int get _currentParticipantCount {
    final value = _event?.joinedCount;
    if (value == null || value < 0) return 0;
    return value;
  }

  int? get _participantLimitCount {
    final value = _event?.maxParticipants;
    if (value == null || value <= 0) return null;
    return value;
  }

  double? get _currentCollectedAmountThb {
    final baseAmount = _parseMoney(_baseAmount);
    if (baseAmount == null || baseAmount <= 0) return null;
    return _roundMoney(baseAmount * _currentParticipantCount);
  }

  double? get _totalCollectAmountThb {
    final baseAmount = _parseMoney(_baseAmount);
    final participantCount = _participantLimitCount;
    if (baseAmount == null || baseAmount <= 0) return null;
    if (participantCount == null || participantCount <= 0) return null;
    return _roundMoney(baseAmount * participantCount);
  }

  String _moneyText(double? value, String currency) =>
      value == null ? '-' : '${value.toStringAsFixed(2)} $currency';

  String get _totalCollectAmountLabel {
    switch (AdminLocaleController.languageCode.value) {
      case 'th':
        return 'จำนวนเงินที่จะเก็บได้ (THB)';
      case 'zh':
        return '可收取总金额（THB）';
      default:
        return 'Total Amount To Collect (THB)';
    }
  }

  String get _totalCollectFormulaText {
    final participantCount = _participantLimitCount;
    final amountPerRunner = _promptpayAmountThb;
    final totalAmount = _totalCollectAmountThb;
    if (participantCount == null ||
        amountPerRunner == null ||
        totalAmount == null) {
      return '-';
    }
    return '$participantCount x ${amountPerRunner.toStringAsFixed(2)} = ${totalAmount.toStringAsFixed(2)} THB';
  }

  String get _currentAndLimitPeopleLabel {
    final current = _currentParticipantCount;
    final limit = _participantLimitCount;
    final unit = AdminStrings.text('people_unit');
    if (limit == null) {
      return '$current $unit';
    }
    return '$current/$limit $unit';
  }

  String get _currentAndExpectedAmountLabel {
    final current = _currentCollectedAmountThb;
    final expected = _totalCollectAmountThb;
    if (current == null && expected == null) return '-';
    return '${_moneyText(current, 'THB')} / ${_moneyText(expected, 'THB')}';
  }

  String get _currentAndExpectedAmountFormulaText {
    final amountPerRunner = _promptpayAmountThb;
    final currentAmount = _currentCollectedAmountThb;
    final expectedAmount = _totalCollectAmountThb;
    final expectedCount = _participantLimitCount;
    if (amountPerRunner == null ||
        currentAmount == null ||
        expectedAmount == null ||
        expectedCount == null) {
      return '-';
    }
    return '$_currentParticipantCount x ${amountPerRunner.toStringAsFixed(2)} = ${currentAmount.toStringAsFixed(2)} THB / $expectedCount x ${amountPerRunner.toStringAsFixed(2)} = ${expectedAmount.toStringAsFixed(2)} THB';
  }

  String _currentOverLimitLabel(String key) {
    switch (AdminLocaleController.languageCode.value) {
      case 'th':
        if (key == 'runners')
          return 'จำนวนผู้วิ่งปัจจุบัน / จำนวนผู้วิ่งสูงสุด';
        return 'จำนวนเงินปัจจุบัน / จำนวนเงินคาดว่าจะได้รับ (THB)';
      case 'zh':
        if (key == 'runners') return '当前跑者 / 人数上限';
        return '当前金额 / 预计总金额（THB）';
      default:
        if (key == 'runners') return 'Current Runners / Runner Limit';
        return 'Current Amount / Expected Amount (THB)';
    }
  }

  int? get _expectedImageCount => null;

  String _galleryDedupKey(String? rawUrl) {
    final normalized = ConfigService.resolveUrl((rawUrl ?? '').trim());
    if (normalized.isEmpty) return '';

    final uri = Uri.tryParse(normalized);
    if (uri == null) return normalized.toLowerCase();

    final normalizedPath = uri.path.toLowerCase().replaceAll(RegExp('/+'), '/');
    return uri
        .replace(path: normalizedPath, query: '', fragment: '')
        .toString();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res =
          await http.get(Uri.parse("$baseUrl/api/events/${widget.eventId}"));
      if (res.statusCode != 200) {
        setState(() {
          _error = _t('load_failed', params: {
            'statusCode': '${res.statusCode}',
            'body': res.body,
          });
          _loading = false;
        });
        return;
      }

      final map = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _event = BigEventDto.fromJson(map);
        _loading = false;
      });
      await _loadMedia();
      await _hydrateMeetingPointFromCoordinates();
      await _loadPaymentMethods();
    } catch (e) {
      setState(() {
        _error = _t('load_error', params: {'error': '$e'});
        _loading = false;
      });
    }
  }

  Future<void> _goEdit() async {
    if (_event == null) return;

    final ok = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditBigEventPage(initial: _event!)),
    );

    if (ok == true) {
      await _load();
    }
  }

  Future<void> _loadPaymentMethods() async {
    setState(() {
      _paymentLoading = true;
      _paymentError = null;
    });
    try {
      final data = await EventApi.instance
          .getAdminPaymentMethods(eventId: widget.eventId);
      final methods = (data['methods'] is List)
          ? List<Map<String, dynamic>>.from(data['methods'])
          : <Map<String, dynamic>>[];
      final promptpay = methods
          .where((m) =>
              (m['method_type'] ?? '').toString().toUpperCase() == 'PROMPTPAY')
          .toList();
      setState(() {
        final loadedPaymentMode = (data['event'] is Map)
            ? ((data['event']['payment_mode'] ?? 'stripe_auto').toString())
            : 'stripe_auto';
        _paymentMode = _normalizeAdminPaymentMode(loadedPaymentMode);
        _promptpayEnabled =
            promptpay.isEmpty ? true : promptpay.first['is_active'] == true;
        _stripeEnabled = (data['event'] is Map)
            ? (data['event']['stripe_enabled'] == true)
            : true;
        _manualPromptpayQrUrl = (data['event'] is Map)
            ? (data['event']['manual_promptpay_qr_url']?.toString())
            : null;
        _baseAmount.text =
            ((data['event'] is Map ? data['event']['base_amount'] : null) ?? '')
                .toString();
        _paymentLoading = false;
      });
    } catch (e) {
      setState(() {
        _paymentLoading = false;
        _paymentError =
            _t('load_payment_methods_failed', params: {'error': '$e'});
      });
    }
  }

  Future<void> _savePaymentSettings() async {
    if (_savingPayment) return;
    setState(() {
      _savingPayment = true;
      _paymentError = null;
    });
    try {
      final baseAmount = _parseMoney(_baseAmount);
      final promptpayAmountThb = _promptpayAmountThb;
      if (baseAmount == null || baseAmount <= 0) {
        throw Exception(_t('amount_required'));
      }
      if (promptpayAmountThb == null || promptpayAmountThb <= 0) {
        throw Exception(_t('promptpay_amount_could_not_be_derived'));
      }
      if (_manualModeVisible &&
          _promptpayEnabled &&
          (_manualPromptpayQrUrl ?? '').trim().isEmpty) {
        throw Exception(_t('promptpay_qr_required_for_manual_mode'));
      }
      if (_paymentMode == 'stripe_auto' && !_stripeEnabled) {
        throw Exception(_t('stripe_must_be_enabled_for_stripe_auto'));
      }
      await EventApi.instance.updateAdminPaymentMethods(
        eventId: widget.eventId,
        paymentMode: _normalizeAdminPaymentMode(_paymentMode),
        enablePromptpay: _promptpayEnabled,
        stripeEnabled: _stripeEnabled,
        baseAmount: baseAmount,
        promptpayAmountThb: promptpayAmountThb,
        manualPromptpayQrUrl: _manualPromptpayQrUrl,
      );
      await _loadPaymentMethods();
      if (!mounted) return;
      setState(() {
        _savingPayment = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('payment_settings_updated'))),
      );
    } catch (e) {
      setState(() {
        _savingPayment = false;
        _paymentError =
            _t('update_payment_settings_failed', params: {'error': '$e'});
      });
    }
  }

  bool get _manualModeVisible =>
      _paymentMode == 'manual_qr' || _paymentMode == 'hybrid';

  bool get _stripeModeVisible =>
      _paymentMode == 'stripe_auto' || _paymentMode == 'hybrid';

  Future<void> _uploadManualQr(String methodType) async {
    final isPromptpay = methodType.toLowerCase() == 'promptpay';
    if (_uploadingPromptpayQr) return;
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (file == null) return;
      setState(() {
        if (isPromptpay) {
          _uploadingPromptpayQr = true;
        }
        _paymentError = null;
      });

      final resp = await EventApi.instance.uploadManualQr(
        eventId: widget.eventId,
        file: file,
        methodType: methodType,
      );

      if (!mounted) return;
      setState(() {
        if (isPromptpay) {
          _manualPromptpayQrUrl = (resp['manual_promptpay_qr_url'] ??
                  resp['qr_url'] ??
                  resp['full_url'])
              ?.toString();
          _uploadingPromptpayQr = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('promptpay_qr_uploaded_successfully')),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (isPromptpay) {
          _uploadingPromptpayQr = false;
        }
        _paymentError =
            _t('upload_promptpay_qr_failed', params: {'error': '$e'});
      });
    }
  }

  Widget _buildQrPreview(String title, String? imageUrl) {
    if ((imageUrl ?? '').trim().isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F6F6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
        ),
        child: Text('$title: ${_t('not_uploaded')}',
            style: const TextStyle(color: Colors.black54)),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              imageUrl!,
              height: 180,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                height: 180,
                color: const Color(0xFFF6F6F6),
                alignment: Alignment.center,
                child: Text(_t('qr_preview_unavailable')),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(
            imageUrl,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    if (_deleting || _event == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_t('delete_big_event')),
        content: Text(_t('delete_big_event_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('delete')),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _deleteEvent();
    }
  }

  Future<void> _deleteEvent() async {
    final e = _event;
    if (e == null) return;

    setState(() => _deleting = true);
    try {
      await EventApi.instance.deleteEvent(e.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('delete_error', params: {'error': '$err'}))),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _loadMedia() async {
    final coverUrl = _event?.coverUrl;

    try {
      final res = await http.get(
        Uri.parse("$baseUrl/api/events/${widget.eventId}/media"),
      );

      if (res.statusCode != 200) {
        if (!mounted) return;
        setState(() {
          _imageUrls = coverUrl == null || coverUrl.isEmpty
              ? <String>[]
              : <String>[coverUrl];
          _galleryIndex = 0;
        });
        return;
      }

      final decoded = jsonDecode(res.body);
      final urls = <String>[];
      final seenKeys = <String>{};

      void addUrl(String? rawUrl) {
        final normalized = ConfigService.resolveUrl((rawUrl ?? '').trim());
        final dedupKey = _galleryDedupKey(rawUrl);
        if (normalized.isEmpty || dedupKey.isEmpty || !seenKeys.add(dedupKey)) {
          return;
        }
        urls.add(normalized);
      }

      addUrl(coverUrl);

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

      final expectedCount = _expectedImageCount;
      final normalizedUrls =
          (expectedCount != null && urls.length > expectedCount)
              ? urls.take(expectedCount).toList(growable: false)
              : urls;

      if (!mounted) return;
      setState(() {
        _imageUrls = normalizedUrls;
        _galleryIndex = 0;
      });
      if (_galleryController.hasClients) {
        _galleryController.jumpToPage(_galleryLoopBasePage);
      }
      _restartGalleryTimer();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _imageUrls = coverUrl == null || coverUrl.isEmpty
            ? <String>[]
            : <String>[coverUrl];
        _galleryIndex = 0;
      });
      _restartGalleryTimer();
    }
  }

  Widget _buildEventGallery() {
    if (_imageUrls.isEmpty) {
      return Container(
        height: 210,
        color: Colors.grey.shade200,
        child: const Center(child: Icon(Icons.image_outlined, size: 60)),
      );
    }

    if (_imageUrls.length == 1) {
      return SizedBox(
        height: 210,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(
                _imageUrls.first,
                height: 210,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 210,
                  color: Colors.grey.shade200,
                  child: Center(child: Text(_t('image_load_error'))),
                ),
              ),
            ),
            const Positioned(
              right: 12,
              bottom: 12,
              child: _GalleryCountBadge(label: '1/1'),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 210,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: PageView.builder(
              controller: _galleryController,
              itemBuilder: (_, index) {
                final imageIndex = index % _imageUrls.length;
                return Image.network(
                  _imageUrls[imageIndex],
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey.shade200,
                    child: Center(child: Text(_t('image_load_error'))),
                  ),
                );
              },
              onPageChanged: (index) {
                if (!mounted) return;
                setState(() => _galleryIndex = index % _imageUrls.length);
                _restartGalleryTimer();
              },
            ),
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
      ),
    );
  }

  Future<void> _hydrateMeetingPointFromCoordinates() async {
    final event = _event;
    if (event == null) return;
    if ((event.province ?? '').trim().isNotEmpty &&
        (event.district ?? '').trim().isNotEmpty) {
      return;
    }

    final lat = event.locationLat;
    final lng = event.locationLng;
    if (lat == null || lng == null) return;

    try {
      await setLocaleIdentifier('en');
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (!mounted || placemarks.isEmpty) return;

      final placemark = placemarks.first;
      final province = (placemark.administrativeArea ??
              placemark.subAdministrativeArea ??
              placemark.locality ??
              '')
          .trim();
      final districtCandidates = <String>[
        (placemark.subLocality ?? '').trim(),
        (placemark.locality ?? '').trim(),
        (placemark.subAdministrativeArea ?? '').trim(),
        (placemark.thoroughfare ?? '').trim(),
      ];

      String district = '';
      for (final candidate in districtCandidates) {
        if (candidate.isEmpty) continue;
        if (province.isNotEmpty &&
            candidate.toLowerCase() == province.toLowerCase()) {
          continue;
        }
        district = candidate;
        break;
      }

      if (province.isEmpty && district.isEmpty) return;

      setState(() {
        _event = event.copyWith(
          province: province.isNotEmpty ? province : event.province,
          district: district.isNotEmpty ? district : event.district,
          locationDisplay: [province, district]
              .where((part) => part.trim().isNotEmpty)
              .join(', '),
        );
      });
    } catch (_) {}
  }

  Widget _buildRewardSection({
    required String title,
    required List<BigEventRewardDto> items,
  }) {
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF6F6F6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.black12),
        ),
        child: Text(
          _t('reward_items_empty_optional'),
          style: TextStyle(color: Colors.black54),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 182,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, index) {
              final item = items[index];
              return InkWell(
                onTap: () => _showRewardDetailCard(
                  sectionTitle: title,
                  item: item,
                ),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 150,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            item.imageUrl,
                            width: 130,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 130,
                              color: Colors.grey.shade200,
                              alignment: Alignment.center,
                              child: const Icon(
                                Icons.image_not_supported_outlined,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8EEF9),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _rewardTypeLabel(item.itemType),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
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

  Future<void> _showRewardDetailCard({
    required String sectionTitle,
    required BigEventRewardDto item,
  }) async {
    final caption = item.caption.trim();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        sectionTitle,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.network(
                    item.imageUrl,
                    width: double.infinity,
                    height: 220,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      height: 220,
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: const Icon(Icons.image_not_supported_outlined),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8EEF9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _rewardTypeLabel(item.itemType),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  caption.isEmpty ? '-' : caption,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRewardsCard(BigEventDto e) {
    final guaranteed = e.guaranteedItems;
    final competition = e.competitionRewardItems;
    final hasAny = guaranteed.isNotEmpty || competition.isNotEmpty;
    return _CardShell(
      title: _t('event_rewards'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  hasAny
                      ? _t('event_rewards_available_subtitle')
                      : _t('event_rewards_empty_subtitle'),
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _deleting ? null : _goEdit,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(_t('edit_rewards')),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _buildRewardSection(
            title: _t('guaranteed_items'),
            items: guaranteed,
          ),
          const SizedBox(height: 14),
          _buildRewardSection(
            title: _t('competition_rewards'),
            items: competition,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = _event;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        title: Text(_t('detail_big_event')),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh))
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_error != null)
              ? Center(child: Text(_error!))
              : (e == null)
                  ? Center(child: Text(_t('no_data')))
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // ===== Cover =====
                        _buildEventGallery(),

                        const SizedBox(height: 14),

                        // ===== Title + Edit =====
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                e.title ?? "-",
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w900),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _deleting ? null : _confirmDelete,
                              icon: _deleting
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.delete_outline,
                                      size: 18, color: Colors.redAccent),
                              label: Text(_t('delete'),
                                  style:
                                      const TextStyle(color: Colors.redAccent)),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white,
                                side: const BorderSide(color: Colors.redAccent),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _deleting ? null : _goEdit,
                              icon: const Icon(Icons.edit, size: 18),
                              label: Text(_t('edit')),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white,
                                side: const BorderSide(color: Colors.black12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(999)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // ===== Info =====
                        _CardShell(
                          title: _t('info'),
                          child: Column(
                            children: [
                              _kv(_t('event_id'), "${e.id}"),
                              _kv(_t('type'), e.type ?? "-"),
                              _kv(_t('status'), e.status ?? "-"),
                              _kv(_t('visibility'), e.visibility ?? "-"),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ===== Event Details =====
                        _CardShell(
                          title: _t('event_details'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _kv(_t('meeting_point'), e.meetingPointDisplay),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _infoBox(
                                      _t('start_date'),
                                      e.startAtDateTime == null
                                          ? "-"
                                          : formatDateTH(e.startAtDateTime!),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _infoBox(
                                      _t('start_time'),
                                      e.startAtDateTime == null
                                          ? "-"
                                          : formatTimeTH(e.startAtDateTime!),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _kv(
                                _currentOverLimitLabel('runners'),
                                _currentAndLimitPeopleLabel,
                              ),
                              const SizedBox(height: 10),
                              _kv(
                                _t('distance_per_lap'),
                                _distanceWithKm(e.distancePerLapText),
                              ),
                              _kv(_t('number_of_laps'), e.numberOfLapsText),
                              _kv(
                                _t('total_distance'),
                                _distanceWithKm(e.totalDistanceText),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 12),

                        // ===== Description =====
                        _CardShell(
                          title: _t('description'),
                          child: Text(e.description ?? "-"),
                        ),

                        const SizedBox(height: 12),

                        _buildRewardsCard(e),

                        const SizedBox(height: 12),

                        _CardShell(
                          title: _t('payment_settings'),
                          child: _paymentLoading
                              ? const Center(child: CircularProgressIndicator())
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (_paymentError != null) ...[
                                      Text(
                                        _paymentError!,
                                        style:
                                            const TextStyle(color: Colors.red),
                                      ),
                                      const SizedBox(height: 8),
                                    ],
                                    DropdownButtonFormField<String>(
                                      value: _paymentMode,
                                      decoration: InputDecoration(
                                        labelText: _t('payment_mode'),
                                        border: OutlineInputBorder(),
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'manual_qr',
                                            child: Text('manual_qr')),
                                        DropdownMenuItem(
                                            value: 'hybrid',
                                            child: Text('hybrid')),
                                        DropdownMenuItem(
                                            value: 'stripe_auto',
                                            child: Text('stripe_auto')),
                                      ],
                                      onChanged: _savingPayment
                                          ? null
                                          : (v) => setState(() {
                                                _paymentMode =
                                                    _normalizeAdminPaymentMode(
                                                        v);
                                                if (_paymentMode ==
                                                    'manual_qr') {
                                                  _stripeEnabled = false;
                                                } else {
                                                  _stripeEnabled = true;
                                                }
                                              }),
                                    ),
                                    const SizedBox(height: 8),
                                    SwitchListTile(
                                      value: _promptpayEnabled,
                                      title: Text(_t('promptpay_enabled')),
                                      subtitle: Text(
                                        _t('use_promptpay_as_payment_option'),
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      onChanged: _savingPayment
                                          ? null
                                          : (v) => setState(
                                              () => _promptpayEnabled = v),
                                    ),
                                    SwitchListTile(
                                      value: _stripeEnabled,
                                      title: Text(_t(
                                          'enable_stripe_automatic_payments')),
                                      subtitle: Text(_t(
                                          'used_for_stripe_generated_payment_flow')),
                                      contentPadding: EdgeInsets.zero,
                                      onChanged: _savingPayment
                                          ? null
                                          : (v) => setState(
                                              () => _stripeEnabled = v),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _manualModeVisible
                                          ? _t(
                                              'manual_modes_require_promptpay_qr_uploads')
                                          : _t('stripe_auto_checkout_note'),
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: _baseAmount,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      decoration: InputDecoration(
                                        labelText: _t('amount_thb'),
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    InputDecorator(
                                      decoration: InputDecoration(
                                        labelText:
                                            _currentOverLimitLabel('amount'),
                                        border: OutlineInputBorder(),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(_currentAndExpectedAmountLabel),
                                          if (_participantLimitCount != null &&
                                              _promptpayAmountThb != null) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              _currentAndExpectedAmountFormulaText,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    if (_manualModeVisible) ...[
                                      const SizedBox(height: 12),
                                      const Divider(),
                                      const SizedBox(height: 8),
                                      Text(
                                        _t('manual_qr_configuration'),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 8),
                                      if (_promptpayEnabled) ...[
                                        _buildQrPreview('PromptPay QR',
                                            _manualPromptpayQrUrl),
                                        const SizedBox(height: 8),
                                        SizedBox(
                                          width: double.infinity,
                                          child: OutlinedButton.icon(
                                            onPressed: _savingPayment ||
                                                    _uploadingPromptpayQr
                                                ? null
                                                : () => _uploadManualQr(
                                                    'promptpay'),
                                            icon: _uploadingPromptpayQr
                                                ? const SizedBox(
                                                    width: 16,
                                                    height: 16,
                                                    child:
                                                        CircularProgressIndicator(
                                                            strokeWidth: 2),
                                                  )
                                                : const Icon(
                                                    Icons.qr_code_2_outlined),
                                            label:
                                                Text(_t('upload_promptpay_qr')),
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                    ],
                                    if (_stripeModeVisible) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8FAFF),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border:
                                              Border.all(color: Colors.black12),
                                        ),
                                        child: Text(
                                          _t('use_provider_checkout_for_promptpay'),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton(
                                        onPressed: _savingPayment
                                            ? null
                                            : _savePaymentSettings,
                                        child: _savingPayment
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2),
                                              )
                                            : Text(_t('save_payment_settings')),
                                      ),
                                    ),
                                  ],
                                ),
                        ),

                        const SizedBox(height: 20),
                      ],
                    ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text("$k:",
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: Colors.black54)),
          ),
          Expanded(
              child:
                  Text(v, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }

  Widget _infoBox(String title, String value) {
    return Container(
      height: 78,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(title,
              style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  final String title;
  final Widget child;
  const _CardShell({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w900))),
          const SizedBox(height: 12),
          child,
        ],
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

class _EditableEventImage {
  final int? id;
  final String url;
  final bool isCover;

  const _EditableEventImage({
    required this.id,
    required this.url,
    required this.isCover,
  });
}

class _EditableRewardItem {
  final int? id;
  final XFile? file;
  final String? existingUrl;
  String selectedType;
  final TextEditingController captionController;

  _EditableRewardItem.existing({
    required this.id,
    required this.existingUrl,
    required String itemType,
    required String caption,
  })  : file = null,
        selectedType = itemType,
        captionController = TextEditingController(text: caption);

  _EditableRewardItem.newFile(
    XFile pickedFile, {
    required String itemType,
    String caption = '',
  })  : id = null,
        file = pickedFile,
        existingUrl = null,
        selectedType = itemType,
        captionController = TextEditingController(text: caption);

  bool get isExisting => id != null;

  void dispose() {
    captionController.dispose();
  }
}

/// --------------------------
/// Edit Page (Update DB แบบทับของเดิม)
/// --------------------------
class EditBigEventPage extends StatefulWidget {
  final BigEventDto initial;
  const EditBigEventPage({super.key, required this.initial});

  @override
  State<EditBigEventPage> createState() => _EditBigEventPageState();
}

class _EditBigEventPageState extends State<EditBigEventPage> {
  static const List<_RewardTypeOption> _guaranteedRewardOptions =
      <_RewardTypeOption>[
    _RewardTypeOption('shirt'),
    _RewardTypeOption('bib_pack'),
    _RewardTypeOption('wristband'),
    _RewardTypeOption('tote_bag'),
    _RewardTypeOption('souvenir'),
    _RewardTypeOption('snack'),
    _RewardTypeOption('other'),
  ];
  static const List<_RewardTypeOption> _competitionRewardOptions =
      <_RewardTypeOption>[
    _RewardTypeOption('medal'),
    _RewardTypeOption('trophy'),
    _RewardTypeOption('finisher_award'),
    _RewardTypeOption('rank_award'),
    _RewardTypeOption('certificate'),
    _RewardTypeOption('other'),
  ];
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
      'th': 'อื่น ๆ',
      'en': 'Other',
      'zh': '其他',
    },
  };

  String _defaultRewardTypeForSection(String section) {
    return section == 'competition'
        ? _competitionRewardOptions.first.value
        : _guaranteedRewardOptions.first.value;
  }

  String _rewardTypeLabel(String type) {
    final languageCode = AdminLocaleController.languageCode.value;
    final labels = _rewardTypeLabels[type] ?? _rewardTypeLabels['other']!;
    return labels[languageCode] ?? labels['en'] ?? type;
  }

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController title;
  late final TextEditingController description;
  late final TextEditingController meetingPoint;
  late final TextEditingController maxParticipants;
  late final TextEditingController distancePerLap;
  late final TextEditingController numberOfLaps;
  late final TextEditingController totalDistance;

  DateTime? _startAtLocal;
  String _status = "draft";

  bool _saving = false;
  String? _error;

  XFile? _picked;
  String? _pickedWebBytesBase64;
  final List<_EditableEventImage> _existingImages = <_EditableEventImage>[];
  final List<XFile> _newGalleryImages = <XFile>[];
  final Set<int> _deletingMediaIds = <int>{};
  final List<_EditableRewardItem> _guaranteedRewardItems =
      <_EditableRewardItem>[];
  final List<_EditableRewardItem> _competitionRewardItems =
      <_EditableRewardItem>[];
  final Set<int> _pendingRewardDeletionIds = <int>{};

  String _t(String key, {Map<String, String> params = const {}}) =>
      AdminStrings.text(key, params: params);

  int get _currentParticipantCount {
    final value = widget.initial.joinedCount;
    if (value == null || value < 0) return 0;
    return value;
  }

  int? get _participantLimitCount =>
      int.tryParse(maxParticipants.text.trim()) ??
      widget.initial.maxParticipants;

  String _participantSummaryLabel() {
    final limit = _participantLimitCount;
    final unit = AdminStrings.text('people_unit');
    if (limit == null) return '$_currentParticipantCount $unit';
    return '$_currentParticipantCount/$limit $unit';
  }

  String _currentRunnersLabel() {
    switch (AdminLocaleController.languageCode.value) {
      case 'th':
        return 'จำนวนผู้วิ่งปัจจุบัน';
      case 'zh':
        return '当前跑者';
      default:
        return 'Current Runners';
    }
  }

  String _limitCannotBeLowerError() {
    switch (AdminLocaleController.languageCode.value) {
      case 'th':
        return 'จำนวนผู้วิ่งสูงสุดต้องไม่น้อยกว่าจำนวนผู้วิ่งปัจจุบัน';
      case 'zh':
        return '人数上限不能低于当前跑者数量';
      default:
        return 'Runner limit cannot be lower than current runners.';
    }
  }

  @override
  void initState() {
    super.initState();
    final e = widget.initial;

    title = TextEditingController(text: e.title ?? "");
    description = TextEditingController(text: e.description ?? "");
    meetingPoint = TextEditingController(text: e.meetingPoint ?? "");
    maxParticipants =
        TextEditingController(text: (e.maxParticipants ?? "").toString());
    distancePerLap = TextEditingController(
      text: e.distancePerLap == null ? "" : e.distancePerLapText,
    );
    numberOfLaps = TextEditingController(
      text: e.numberOfLaps == null ? "" : e.numberOfLaps.toString(),
    );
    totalDistance = TextEditingController(
        text: e.totalDistanceText == "-" ? "" : e.totalDistanceText);
    maxParticipants.addListener(_handleMaxParticipantsChanged);
    distancePerLap.addListener(_recomputeTotalDistance);
    numberOfLaps.addListener(_recomputeTotalDistance);

    _status = (e.status ?? "draft");
    _startAtLocal = e.startAtDateTime;
    _seedRewardItems();
    _loadExistingMedia();
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    meetingPoint.dispose();
    maxParticipants.removeListener(_handleMaxParticipantsChanged);
    maxParticipants.dispose();
    distancePerLap.dispose();
    numberOfLaps.dispose();
    totalDistance.dispose();
    _disposeRewardItems(_guaranteedRewardItems);
    _disposeRewardItems(_competitionRewardItems);
    super.dispose();
  }

  void _seedRewardItems() {
    _disposeRewardItems(_guaranteedRewardItems);
    _disposeRewardItems(_competitionRewardItems);
    _guaranteedRewardItems
      ..clear()
      ..addAll(
        widget.initial.guaranteedItems.map(
          (item) => _EditableRewardItem.existing(
            id: item.id,
            existingUrl: item.imageUrl,
            itemType: item.itemType.isEmpty
                ? _defaultRewardTypeForSection('guaranteed')
                : item.itemType,
            caption: item.caption,
          ),
        ),
      );
    _competitionRewardItems
      ..clear()
      ..addAll(
        widget.initial.competitionRewardItems.map(
          (item) => _EditableRewardItem.existing(
            id: item.id,
            existingUrl: item.imageUrl,
            itemType: item.itemType.isEmpty
                ? _defaultRewardTypeForSection('competition')
                : item.itemType,
            caption: item.caption,
          ),
        ),
      );
  }

  void _disposeRewardItems(List<_EditableRewardItem> items) {
    for (final item in items) {
      item.dispose();
    }
  }

  void _handleMaxParticipantsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _recomputeTotalDistance() {
    final d = double.tryParse(distancePerLap.text.trim());
    final n = int.tryParse(numberOfLaps.text.trim());
    if (d != null && d > 0 && n != null && n > 0) {
      final total = d * n;
      totalDistance.text = total.toStringAsFixed(total % 1 == 0 ? 0 : 2);
    } else {
      totalDistance.text = '';
    }
  }

  // ===== UI helpers =====
  InputDecoration _dec(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF6F6F6),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.black12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.black12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final f =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (f == null) return;
    if (_isWebUnsupportedImage(f)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This browser cannot preview HEIC/HEIF files. Please choose JPG or PNG instead.',
          ),
        ),
      );
      return;
    }

    if (kIsWeb) {
      final bytes = await f.readAsBytes();
      _pickedWebBytesBase64 = base64Encode(bytes);
    }

    setState(() => _picked = f);
  }

  Future<void> _loadExistingMedia() async {
    try {
      final res = await http.get(
        Uri.parse("$baseUrl/api/events/${widget.initial.id}/media"),
      );

      final images = <_EditableEventImage>[];

      void addImage({
        required String? rawUrl,
        required bool isCover,
        int? id,
      }) {
        final normalized = ConfigService.resolveUrl((rawUrl ?? '').trim());
        if (normalized.isEmpty ||
            images.any((item) => item.url == normalized)) {
          return;
        }
        images.add(
          _EditableEventImage(
            id: id,
            url: normalized,
            isCover: isCover,
          ),
        );
      }

      addImage(rawUrl: widget.initial.coverUrl, isCover: true);

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final kind = (item['kind'] ?? '').toString().trim().toLowerCase();
            if (kind.isNotEmpty && kind != 'cover' && kind != 'gallery') {
              continue;
            }
            addImage(
              id: int.tryParse('${item['id'] ?? ''}'),
              rawUrl: (item['file_url'] ?? item['fileUrl'] ?? '').toString(),
              isCover: (item['kind'] ?? '').toString() == 'cover',
            );
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _existingImages
          ..clear()
          ..addAll(images);
      });
    } catch (_) {
      if (!mounted) return;
      final coverUrl = widget.initial.coverUrl;
      setState(() {
        _existingImages
          ..clear()
          ..addAll(
            (coverUrl == null || coverUrl.isEmpty)
                ? <_EditableEventImage>[]
                : <_EditableEventImage>[
                    _EditableEventImage(
                      id: null,
                      url: coverUrl,
                      isCover: true,
                    ),
                  ],
          );
      });
    }
  }

  int get _totalImageCount {
    final existingCount = _existingImages.length;
    final baseCount = existingCount == 0 && _picked != null ? 1 : existingCount;
    return baseCount + _newGalleryImages.length;
  }

  int get _remainingImageSlots {
    final remaining = 10 - _totalImageCount;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _pickAdditionalImages() async {
    final remaining = _remainingImageSlots;
    if (remaining <= 0) return;

    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;

    final take = _filterPreviewableImages(files).take(remaining).toList();
    if (take.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _newGalleryImages.addAll(take);
    });
  }

  Future<void> _deleteExistingImage(_EditableEventImage image) async {
    final mediaId = image.id;
    if (mediaId == null || _saving || _deletingMediaIds.contains(mediaId))
      return;

    setState(() => _deletingMediaIds.add(mediaId));
    try {
      final adminId = await AdminSessionService.getCurrentAdminId();
      final res = await http.delete(
        Uri.parse("$baseUrl/api/events/${widget.initial.id}/media/$mediaId"),
        headers: {
          "Accept": "application/json",
          if (adminId != null && adminId > 0) "x-admin-id": adminId.toString(),
        },
      );

      if (res.statusCode != 200) {
        throw Exception("Delete failed (${res.statusCode})");
      }

      if (!mounted) return;
      setState(() {
        _existingImages.removeWhere((item) => item.id == mediaId);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_t('delete_image_failed', params: {'error': '$e'}))),
      );
    } finally {
      if (mounted) {
        setState(() => _deletingMediaIds.remove(mediaId));
      }
    }
  }

  Future<void> _pickRewardImages(List<_EditableRewardItem> items) async {
    final remaining = 10 - items.length;
    if (remaining <= 0) return;

    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 85);
    if (files.isEmpty) return;
    final previewable = _filterPreviewableImages(files);
    if (previewable.isEmpty) return;

    if (!mounted) return;
    setState(() {
      items.addAll(
        previewable
            .take(remaining)
            .map(
              (file) => _EditableRewardItem.newFile(
                file,
                itemType: identical(items, _competitionRewardItems)
                    ? _competitionRewardOptions.first.value
                    : _guaranteedRewardOptions.first.value,
              ),
            )
            .toList(growable: false),
      );
    });
  }

  void _moveRewardItem(List<_EditableRewardItem> items, int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= items.length) return;
    setState(() {
      final item = items.removeAt(index);
      items.insert(newIndex, item);
    });
  }

  void _removeRewardItem(List<_EditableRewardItem> items, int index) {
    final removed = items.removeAt(index);
    final mediaId = removed.id;
    if (mediaId != null) {
      _pendingRewardDeletionIds.add(mediaId);
    }
    removed.dispose();
    setState(() {});
  }

  Future<void> _deleteEventMediaById(int mediaId) async {
    final adminId = await AdminSessionService.getCurrentAdminId();
    final res = await http.delete(
      Uri.parse("$baseUrl/api/events/${widget.initial.id}/media/$mediaId"),
      headers: {
        "Accept": "application/json",
        if (adminId != null && adminId > 0) "x-admin-id": adminId.toString(),
      },
    );

    if (res.statusCode != 200) {
      throw Exception("Delete failed (${res.statusCode})");
    }
  }

  Future<void> _flushPendingRewardDeletes() async {
    if (_pendingRewardDeletionIds.isEmpty) return;
    final pending = _pendingRewardDeletionIds.toList(growable: false);
    for (final mediaId in pending) {
      await _deleteEventMediaById(mediaId);
      _pendingRewardDeletionIds.remove(mediaId);
    }
  }

  Future<void> _syncRewardSection({
    required String section,
    required List<_EditableRewardItem> items,
  }) async {
    final newItems =
        items.where((item) => item.id == null).toList(growable: false);
    List<BigEventRewardDto> uploadedItems = const <BigEventRewardDto>[];

    if (newItems.isNotEmpty) {
      final response = await EventApi.instance.uploadRewardItems(
        eventId: widget.initial.id,
        section: section,
        files: newItems.map((item) => item.file!).toList(growable: false),
        itemTypes:
            newItems.map((item) => item.selectedType).toList(growable: false),
        captions: newItems
            .map((item) => item.captionController.text.trim())
            .toList(growable: false),
        sortOrders: List<int>.generate(newItems.length, (index) => index + 1),
      );

      final rawItems = response['items'];
      if (rawItems is List) {
        uploadedItems = rawItems
            .whereType<Map>()
            .map((item) =>
                BigEventRewardDto.fromJson(Map<String, dynamic>.from(item)))
            .toList(growable: false);
      }
    }

    var uploadedIndex = 0;
    final payload = <Map<String, dynamic>>[];
    for (var index = 0; index < items.length; index++) {
      final item = items[index];
      var mediaId = item.id;
      if (mediaId == null) {
        if (uploadedIndex >= uploadedItems.length) {
          throw Exception('Uploaded reward item metadata is incomplete');
        }
        mediaId = uploadedItems[uploadedIndex].id;
        uploadedIndex += 1;
      }
      payload.add(<String, dynamic>{
        'id': mediaId,
        'item_type': item.selectedType,
        'caption': item.captionController.text.trim(),
        'sort_order': index + 1,
      });
    }

    await EventApi.instance.updateRewardItems(
      eventId: widget.initial.id,
      section: section,
      items: payload,
    );
  }

  Widget _buildXFilePreview(
    XFile file, {
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
  }) {
    Widget fallback() => Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported_outlined),
        );

    if (kIsWeb) {
      return FutureBuilder<Uint8List>(
        future: file.readAsBytes(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return fallback();
          }
          if (snapshot.hasData &&
              snapshot.connectionState == ConnectionState.done) {
            return Image.memory(
              snapshot.data!,
              width: width,
              height: height,
              fit: fit,
              errorBuilder: (_, __, ___) => fallback(),
            );
          }
          return SizedBox(
            width: width,
            height: height,
            child:
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
      );
    }

    return Image.file(
      io.File(file.path),
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => fallback(),
    );
  }

  bool _isWebUnsupportedImage(XFile file) {
    if (!kIsWeb) return false;
    final name = file.name.toLowerCase();
    return name.endsWith('.heic') || name.endsWith('.heif');
  }

  List<XFile> _filterPreviewableImages(List<XFile> files) {
    if (!kIsWeb || files.isEmpty) return files;
    final supported = files
        .where((file) => !_isWebUnsupportedImage(file))
        .toList(growable: false);
    final skippedCount = files.length - supported.length;
    if (skippedCount > 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Some images were skipped because this browser cannot preview HEIC/HEIF files.',
          ),
        ),
      );
    }
    return supported;
  }

  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final base = _startAtLocal ?? now;

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(base.year, base.month, base.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked == null) return;

    final cur = _startAtLocal ?? now;
    setState(() {
      _startAtLocal =
          DateTime(picked.year, picked.month, picked.day, cur.hour, cur.minute);
    });
  }

  Future<void> _pickStartTime() async {
    final now = DateTime.now();
    final base = _startAtLocal ?? now;

    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
    );
    if (picked == null) return;

    final cur = _startAtLocal ?? now;
    setState(() {
      _startAtLocal =
          DateTime(cur.year, cur.month, cur.day, picked.hour, picked.minute);
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    if (_startAtLocal == null) {
      setState(() => _error =
          '${_t('please_select_event_date')} / ${_t('please_select_start_time')}');
      return;
    }

    final dText = distancePerLap.text.trim();
    final nText = numberOfLaps.text.trim();
    final hasD = dText.isNotEmpty;
    final hasN = nText.isNotEmpty;
    if (hasD != hasN) {
      setState(() => _error = _t('distance_and_laps_must_be_filled_together'));
      return;
    }
    if (hasD && hasN) {
      final d = double.tryParse(dText);
      final n = int.tryParse(nText);
      if (d == null || d <= 0 || n == null || n <= 0) {
        setState(() => _error =
            '${_t('please_enter_valid_distance_per_lap')} / ${_t('please_enter_valid_number_of_laps')}');
        return;
      }
    }

    final limitValue = int.tryParse(maxParticipants.text.trim()) ?? 0;
    if (limitValue < _currentParticipantCount) {
      setState(() => _error = _limitCannotBeLowerError());
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final adminId = await AdminSessionService.getCurrentAdminId();
      final body = {
        "title": title.text.trim(),
        "description": description.text.trim(),
        "meeting_point": meetingPoint.text.trim(),
        "start_at": _startAtLocal!.toIso8601String(),
        "max_participants": int.tryParse(maxParticipants.text.trim()) ?? 0,
        "distance_per_lap": distancePerLap.text.trim().isEmpty
            ? null
            : double.tryParse(distancePerLap.text.trim()),
        "number_of_laps": numberOfLaps.text.trim().isEmpty
            ? null
            : int.tryParse(numberOfLaps.text.trim()),
        "status": _status,
        "city": null,
        "province": null,
      };

      final res = await http.put(
        Uri.parse("$baseUrl/api/events/${widget.initial.id}"),
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          if (adminId != null && adminId > 0) "x-admin-id": adminId.toString(),
        },
        body: jsonEncode(body),
      );

      if (res.statusCode != 200) {
        setState(() {
          _error = _t('save_error', params: {
            'error': 'Save failed (${res.statusCode}): ${res.body}'
          });
          _saving = false;
        });
        return;
      }

      // ✅ upload cover (เหมือนเดิม)
      if (_picked != null) {
        final req = http.MultipartRequest(
          "POST",
          Uri.parse("$baseUrl/api/events/${widget.initial.id}/cover"),
        );
        req.headers["Accept"] = "application/json";
        if (adminId != null && adminId > 0) {
          req.headers["x-admin-id"] = adminId.toString();
        }

        if (kIsWeb) {
          final bytes = base64Decode(_pickedWebBytesBase64!);
          req.files.add(http.MultipartFile.fromBytes("file", bytes,
              filename: _picked!.name));
        } else {
          req.files
              .add(await http.MultipartFile.fromPath("file", _picked!.path));
        }

        final streamed = await req.send();
        final coverRes = await http.Response.fromStream(streamed);

        if (coverRes.statusCode != 201 && coverRes.statusCode != 200) {
          setState(() {
            _error = _t('save_error', params: {
              'error':
                  'Upload cover failed (${coverRes.statusCode}): ${coverRes.body}'
            });
            _saving = false;
          });
          return;
        }
      }

      if (_newGalleryImages.isNotEmpty) {
        await EventApi.instance.uploadGallery(
          eventId: widget.initial.id,
          files: _newGalleryImages,
        );
      }

      await _flushPendingRewardDeletes();
      await _syncRewardSection(
        section: 'guaranteed',
        items: _guaranteedRewardItems,
      );
      await _syncRewardSection(
        section: 'competition',
        items: _competitionRewardItems,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error = _t('save_error', params: {'error': '$e'});
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.initial;
    final start = _startAtLocal;

    final startDateText = (start == null) ? "-" : formatDateTH(start);
    final startTimeText = (start == null) ? "-" : formatTimeTH(start);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(title: Text(_t('edit_big_event'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.red.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(color: Colors.red))),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _card(
                title: _t('event_info'),
                child: Column(
                  children: [
                    TextFormField(
                      controller: title,
                      decoration: _dec(_t('title')),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? _t('required')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: meetingPoint,
                      decoration: _dec(_t('meeting_point')),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? _t('required')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _status,
                      decoration: _dec(_t('status')),
                      items: const [
                        DropdownMenuItem(value: "draft", child: Text("draft")),
                        DropdownMenuItem(
                            value: "published", child: Text("published")),
                        DropdownMenuItem(
                            value: "closed", child: Text("closed")),
                        DropdownMenuItem(
                            value: "cancelled", child: Text("cancelled")),
                      ],
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _status = v ?? "draft"),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _card(
                title: _t('date_and_time'),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _saving ? null : _pickStartDate,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 74,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F6F6),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(startDateText,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900)),
                              const SizedBox(height: 6),
                              Text(_t('start_date'),
                                  style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: _saving ? null : _pickStartTime,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 74,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF6F6F6),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(startTimeText,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900)),
                              const SizedBox(height: 6),
                              Text(_t('start_time'),
                                  style: TextStyle(
                                      color: Colors.black54,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _card(
                title: AdminStrings.text('runners_and_description'),
                child: Column(
                  children: [
                    TextFormField(
                      key: ValueKey(
                          'current-runners-${_participantSummaryLabel()}'),
                      initialValue: _participantSummaryLabel(),
                      readOnly: true,
                      decoration: _dec(_currentRunnersLabel()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: maxParticipants,
                      decoration: _dec(AdminStrings.text('number_of_runners')),
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        final parsed = int.tryParse((v ?? '').trim());
                        if (parsed == null || parsed <= 0) {
                          return _t('required');
                        }
                        if (parsed < _currentParticipantCount) {
                          return _limitCannotBeLowerError();
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: distancePerLap,
                            decoration: _dec(_t('distance_per_lap')),
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: numberOfLaps,
                            decoration: _dec(_t('number_of_laps')),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: totalDistance,
                      readOnly: true,
                      decoration: _dec(_t('total_distance'),
                          hint: _t('auto_calculated')),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: description,
                      decoration: _dec(_t('description')),
                      maxLines: 4,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? _t('required')
                          : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildRewardEditorCard(
                title: _t('guaranteed_items'),
                subtitle: _t('guaranteed_items_edit_subtitle'),
                items: _guaranteedRewardItems,
              ),
              const SizedBox(height: 12),
              _buildRewardEditorCard(
                title: _t('competition_reward_items'),
                subtitle: _t('competition_reward_items_edit_subtitle'),
                items: _competitionRewardItems,
              ),
              const SizedBox(height: 12),
              _card(
                title: _t('cover_image'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_picked != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: FutureBuilder(
                          future: _picked!.readAsBytes(),
                          builder: (context, snapshot) {
                            Widget fallback() => Container(
                                  height: 180,
                                  width: double.infinity,
                                  color: Colors.grey.shade200,
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.image_not_supported_outlined,
                                  ),
                                );

                            if (snapshot.hasError) {
                              return fallback();
                            }
                            if (snapshot.hasData &&
                                snapshot.connectionState ==
                                    ConnectionState.done) {
                              return Image.memory(
                                snapshot.data as Uint8List,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => fallback(),
                              );
                            }
                            return const SizedBox(
                              height: 180,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          },
                        ),
                      ),
                    ] else if ((e.coverUrl ?? "").isNotEmpty) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.network(
                          e.coverUrl!,
                          height: 180,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => SizedBox(
                              height: 180,
                              child:
                                  Center(child: Text(_t('image_load_error')))),
                        ),
                      ),
                    ] else ...[
                      Text(_t('no_cover'),
                          style: TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w700)),
                    ],
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _pickImage,
                      icon: const Icon(Icons.image),
                      label: Text(_t('change_cover')),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: Colors.black12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 14),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _t('event_images',
                                params: {'count': '$_totalImageCount'}),
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _saving || _remainingImageSlots <= 0
                              ? null
                              : _pickAdditionalImages,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(44, 44),
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.white,
                            side: const BorderSide(color: Colors.black12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: Icon(
                            _remainingImageSlots <= 0 ? Icons.block : Icons.add,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (_existingImages.isNotEmpty)
                      SizedBox(
                        height: 84,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _existingImages.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, index) {
                            final image = _existingImages[index];
                            final deleting = image.id != null &&
                                _deletingMediaIds.contains(image.id);
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    image.url,
                                    width: 84,
                                    height: 84,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      width: 84,
                                      height: 84,
                                      color: Colors.grey.shade200,
                                      alignment: Alignment.center,
                                      child: const Icon(
                                        Icons.image_not_supported_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                                if (image.isCover)
                                  Positioned(
                                    left: 6,
                                    top: 6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        _t('cover'),
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  right: 4,
                                  top: 4,
                                  child: InkWell(
                                    onTap: deleting
                                        ? null
                                        : () => _deleteExistingImage(image),
                                    borderRadius: BorderRadius.circular(999),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: const BoxDecoration(
                                        color: Colors.black54,
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: deleting
                                          ? const SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.close,
                                              color: Colors.white,
                                              size: 14,
                                            ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    if (_newGalleryImages.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 84,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _newGalleryImages.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, index) => Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: _buildXFilePreview(
                                  _newGalleryImages[index],
                                  width: 84,
                                  height: 84,
                                ),
                              ),
                              Positioned(
                                left: 6,
                                top: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _t('new'),
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 4,
                                top: 4,
                                child: InkWell(
                                  onTap: _saving
                                      ? null
                                      : () => setState(
                                            () => _newGalleryImages
                                                .removeAt(index),
                                          ),
                                  borderRadius: BorderRadius.circular(999),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(_t('save_update_db'),
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRewardEditorCard({
    required String title,
    required String subtitle,
    required List<_EditableRewardItem> items,
  }) {
    final typeOptions = identical(items, _competitionRewardItems)
        ? _competitionRewardOptions
        : _guaranteedRewardOptions;
    return _card(
      title: '$title (${items.length}/10)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: const TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _saving || items.length >= 10
                  ? null
                  : () => _pickRewardImages(items),
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: Text(_t('add_images')),
            ),
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF6F6F6),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12),
              ),
              child: Text(
                _t('reward_items_empty_optional'),
                style: const TextStyle(color: Colors.black54),
              ),
            )
          else
            Column(
              children: List<Widget>.generate(items.length, (index) {
                final item = items[index];
                final imageUrl = item.existingUrl;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == items.length - 1 ? 0 : 12,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: imageUrl != null && imageUrl.isNotEmpty
                              ? Image.network(
                                  imageUrl,
                                  width: 84,
                                  height: 84,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    width: 84,
                                    height: 84,
                                    color: Colors.grey.shade200,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.image_not_supported_outlined,
                                    ),
                                  ),
                                )
                              : _buildXFilePreview(
                                  item.file!,
                                  width: 84,
                                  height: 84,
                                ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF4FF),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      _t('sort_number',
                                          params: {'number': '${index + 1}'}),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  if (!item.isExisting)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDBEAFE),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        _t('new'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  const Spacer(),
                                  IconButton(
                                    onPressed: _saving || index == 0
                                        ? null
                                        : () => _moveRewardItem(
                                              items,
                                              index,
                                              -1,
                                            ),
                                    icon: const Icon(Icons.arrow_upward),
                                    tooltip: _t('move_up'),
                                  ),
                                  IconButton(
                                    onPressed:
                                        _saving || index == items.length - 1
                                            ? null
                                            : () => _moveRewardItem(
                                                  items,
                                                  index,
                                                  1,
                                                ),
                                    icon: const Icon(Icons.arrow_downward),
                                    tooltip: _t('move_down'),
                                  ),
                                  IconButton(
                                    onPressed: _saving
                                        ? null
                                        : () => _removeRewardItem(items, index),
                                    icon: const Icon(Icons.delete_outline),
                                    tooltip: _t('remove'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: item.selectedType,
                                decoration: _dec(_t('item_type')),
                                items: typeOptions
                                    .map(
                                      (option) => DropdownMenuItem<String>(
                                        value: option.value,
                                        child: Text(
                                          _rewardTypeLabel(option.value),
                                        ),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: _saving
                                    ? null
                                    : (value) {
                                        if (value == null) return;
                                        setState(() {
                                          item.selectedType = value;
                                        });
                                      },
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: item.captionController,
                                decoration: _dec(_t('custom_label_optional')),
                                maxLength: 80,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class BigEventDto {
  final int id;

  final String? type;
  final String? status;
  final String? visibility;

  final String? title;
  final String? description;

  final String? meetingPoint;
  final String? locationDisplay;
  final String? province;
  final String? district;
  final double? locationLat;
  final double? locationLng;

  final String? startAtIso;
  final int? maxParticipants;
  final int? joinedCount;
  final String? coverUrl;
  final double? distancePerLap;
  final int? numberOfLaps;
  final double? totalDistance;
  final String? legacyDistance;
  final List<BigEventRewardDto> guaranteedItems;
  final List<BigEventRewardDto> competitionRewardItems;

  BigEventDto({
    required this.id,
    this.type,
    this.status,
    this.visibility,
    this.title,
    this.description,
    this.meetingPoint,
    this.locationDisplay,
    this.province,
    this.district,
    this.locationLat,
    this.locationLng,
    this.startAtIso,
    this.maxParticipants,
    this.joinedCount,
    this.coverUrl,
    this.distancePerLap,
    this.numberOfLaps,
    this.totalDistance,
    this.legacyDistance,
    this.guaranteedItems = const <BigEventRewardDto>[],
    this.competitionRewardItems = const <BigEventRewardDto>[],
  });

  DateTime? get startAtDateTime {
    final s = startAtIso;
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }

  String _fmtDouble(double v) {
    if (v % 1 == 0) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  String get distancePerLapText =>
      distancePerLap == null ? '-' : _fmtDouble(distancePerLap!);
  String get numberOfLapsText => numberOfLaps == null ? '-' : '$numberOfLaps';
  String get totalDistanceText {
    if (distancePerLap != null && numberOfLaps != null) {
      return _fmtDouble(distancePerLap! * numberOfLaps!);
    }
    if (totalDistance != null) return _fmtDouble(totalDistance!);
    final legacy = (legacyDistance ?? '').trim();
    return legacy.isEmpty ? '-' : legacy;
  }

  String get meetingPointDisplay {
    final directDisplay = (locationDisplay ?? '').trim();
    if (directDisplay.isNotEmpty) return directDisplay;

    final directProvince = (province ?? '').trim();
    final directDistrict = (district ?? '').trim();
    if (directProvince.isNotEmpty || directDistrict.isNotEmpty) {
      return [directProvince, directDistrict]
          .where((part) => part.isNotEmpty)
          .join(', ');
    }

    final fallback = (meetingPoint ?? '').trim();
    return fallback.isEmpty ? '-' : fallback;
  }

  factory BigEventDto.fromJson(Map<String, dynamic> j) {
    int parseId(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      return int.tryParse(v.toString()) ?? 0;
    }

    double? parseDouble(dynamic v) {
      if (v == null) return null;
      return double.tryParse(v.toString());
    }

    final rawCover =
        (j["cover_url"] ?? j["coverUrl"] ?? j["image_url"] ?? j["image"] ?? "")
            .toString()
            .trim();
    List<BigEventRewardDto> parseRewards(dynamic rawItems) {
      if (rawItems is! List) return const <BigEventRewardDto>[];
      return rawItems
          .whereType<Map>()
          .map((item) =>
              BigEventRewardDto.fromJson(Map<String, dynamic>.from(item)))
          .toList(growable: false);
    }

    return BigEventDto(
      id: parseId(j["id"]),
      type: j["type"]?.toString(),
      status: j["status"]?.toString(),
      visibility: j["visibility"]?.toString(),
      title: j["title"]?.toString(),
      description: j["description"]?.toString(),
      meetingPoint: j["meeting_point"]?.toString(),
      locationDisplay:
          (j["location_display"] ?? j["locationDisplay"])?.toString(),
      province: (j["province"] ?? j["changwat"])?.toString(),
      district:
          (j["district"] ?? j["amphoe"] ?? j["district_name"])?.toString(),
      locationLat:
          parseDouble(j["location_lat"] ?? j["latitude"] ?? j["locationLat"]),
      locationLng:
          parseDouble(j["location_lng"] ?? j["longitude"] ?? j["locationLng"]),
      startAtIso: j["start_at"]?.toString(),
      maxParticipants: (j["max_participants"] is int)
          ? j["max_participants"] as int
          : int.tryParse((j["max_participants"] ?? "").toString()),
      joinedCount: (j["joined_count"] is int)
          ? j["joined_count"] as int
          : int.tryParse((j["joined_count"] ??
                  j["current_participants"] ??
                  j["participant_count"] ??
                  "")
              .toString()),
      coverUrl: rawCover.isEmpty ? null : ConfigService.resolveUrl(rawCover),
      distancePerLap: parseDouble(j["distance_per_lap"]),
      numberOfLaps: (j["number_of_laps"] is int)
          ? j["number_of_laps"] as int
          : int.tryParse((j["number_of_laps"] ?? "").toString()),
      totalDistance: parseDouble(j["total_distance"]),
      legacyDistance: (j["distance"] ?? j["totalDistanceLegacy"])?.toString(),
      guaranteedItems: parseRewards(j["guaranteed_items"]),
      competitionRewardItems: parseRewards(j["competition_reward_items"]),
    );
  }

  BigEventDto copyWith({
    int? id,
    String? type,
    String? status,
    String? visibility,
    String? title,
    String? description,
    String? meetingPoint,
    String? locationDisplay,
    String? province,
    String? district,
    double? locationLat,
    double? locationLng,
    String? startAtIso,
    int? maxParticipants,
    int? joinedCount,
    String? coverUrl,
    double? distancePerLap,
    int? numberOfLaps,
    double? totalDistance,
    String? legacyDistance,
    List<BigEventRewardDto>? guaranteedItems,
    List<BigEventRewardDto>? competitionRewardItems,
  }) {
    return BigEventDto(
      id: id ?? this.id,
      type: type ?? this.type,
      status: status ?? this.status,
      visibility: visibility ?? this.visibility,
      title: title ?? this.title,
      description: description ?? this.description,
      meetingPoint: meetingPoint ?? this.meetingPoint,
      locationDisplay: locationDisplay ?? this.locationDisplay,
      province: province ?? this.province,
      district: district ?? this.district,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      startAtIso: startAtIso ?? this.startAtIso,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      joinedCount: joinedCount ?? this.joinedCount,
      coverUrl: coverUrl ?? this.coverUrl,
      distancePerLap: distancePerLap ?? this.distancePerLap,
      numberOfLaps: numberOfLaps ?? this.numberOfLaps,
      totalDistance: totalDistance ?? this.totalDistance,
      legacyDistance: legacyDistance ?? this.legacyDistance,
      guaranteedItems: guaranteedItems ?? this.guaranteedItems,
      competitionRewardItems:
          competitionRewardItems ?? this.competitionRewardItems,
    );
  }
}

class BigEventRewardDto {
  final int id;
  final String section;
  final String itemType;
  final String imageUrl;
  final String caption;
  final int sortOrder;

  const BigEventRewardDto({
    required this.id,
    required this.section,
    required this.itemType,
    required this.imageUrl,
    required this.caption,
    required this.sortOrder,
  });

  factory BigEventRewardDto.fromJson(Map<String, dynamic> json) {
    return BigEventRewardDto(
      id: int.tryParse('${json["id"] ?? 0}') ?? 0,
      section: (json["section"] ?? "").toString(),
      itemType: (json["item_type"] ?? json["itemType"] ?? "").toString(),
      imageUrl: ConfigService.resolveUrl(
        (json["image_url"] ?? json["imageUrl"] ?? "").toString(),
      ),
      caption: (json["caption"] ?? "").toString(),
      sortOrder:
          int.tryParse('${json["sort_order"] ?? json["sortOrder"] ?? 0}') ?? 0,
    );
  }
}

class _RewardTypeOption {
  final String value;

  const _RewardTypeOption(this.value);
}
