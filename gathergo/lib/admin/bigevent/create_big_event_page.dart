import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/services/admin_session_service.dart';
import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import '../data/event_api.dart';
import 'big_event_location_picker_page.dart';

enum BigEventPaymentMode { stripeAuto }

class CreateBigEventPage extends StatefulWidget {
  final String orgId;
  const CreateBigEventPage({super.key, required this.orgId});

  @override
  State<CreateBigEventPage> createState() => _CreateBigEventPageState();
}

class _CreateBigEventPageState extends State<CreateBigEventPage> {
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
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _detail = TextEditingController();
  final _meetingPointNote = TextEditingController();
  final _limitJoiner = TextEditingController(text: '1');
  final _baseAmount = TextEditingController();
  final _distancePerLap = TextEditingController();
  final _numberOfLaps = TextEditingController();
  final _totalDistance = TextEditingController();

  DateTime? _eventDate;
  double? _locationLat;
  double? _locationLng;
  String _locationProvince = '';
  String _locationDistrict = '';
  String _locationDisplay = '';
  TimeOfDay? _startTime;

  BigEventPaymentMode _paymentMode = BigEventPaymentMode.stripeAuto;
  bool _enablePromptpay = true;
  final List<XFile> _eventImages = [];
  final List<_DraftRewardImage> _guaranteedRewardItems = <_DraftRewardImage>[];
  final List<_DraftRewardImage> _competitionRewardItems = <_DraftRewardImage>[];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _distancePerLap.addListener(_recomputeTotalDistance);
    _numberOfLaps.addListener(_recomputeTotalDistance);
    _baseAmount.addListener(_paymentInputsChanged);
    _limitJoiner.addListener(_paymentInputsChanged);
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _t(String key, {Map<String, String> params = const {}}) {
    return AdminStrings.text(key, params: params);
  }

  String _rewardTypeLabel(String type) {
    final languageCode = AdminLocaleController.languageCode.value;
    final labels = _rewardTypeLabels[type] ?? _rewardTypeLabels['other']!;
    return labels[languageCode] ?? labels['en'] ?? type;
  }

  Map<String, String> _buildI18nMap(String value) {
    final trimmed = value.trim();
    return <String, String>{
      'th': trimmed,
      'en': trimmed,
      'zh': trimmed,
    };
  }

  void _recomputeTotalDistance() {
    final d = double.tryParse(_distancePerLap.text.trim());
    final n = int.tryParse(_numberOfLaps.text.trim());
    if (d != null && d > 0 && n != null && n > 0) {
      final total = d * n;
      _totalDistance.text = total.toStringAsFixed(total % 1 == 0 ? 0 : 2);
    } else {
      _totalDistance.text = '';
    }
  }

  void _paymentInputsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  double? _parseMoney(TextEditingController controller) {
    return double.tryParse(controller.text.trim());
  }

  double _roundMoney(double value) => (value * 100).round() / 100;

  double? get _baseAmountValue => _parseMoney(_baseAmount);

  int? get _participantLimitValue => int.tryParse(_limitJoiner.text.trim());

  double? get _promptpayAmountThb {
    final baseAmount = _baseAmountValue;
    if (baseAmount == null || baseAmount <= 0) return null;
    return _roundMoney(baseAmount);
  }

  double? get _totalCollectAmountThb {
    final baseAmount = _baseAmountValue;
    final limit = _participantLimitValue;
    if (baseAmount == null || baseAmount <= 0) return null;
    if (limit == null || limit <= 0) return null;
    return _roundMoney(baseAmount * limit);
  }

  String _moneyText(double? value, String currency) {
    if (value == null) return '-';
    return '${value.toStringAsFixed(2)} $currency';
  }

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

  Widget _buildXFilePreview(
    XFile file, {
    double? width,
    double? height,
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

  @override
  void dispose() {
    AdminLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _title.dispose();
    _detail.dispose();
    _meetingPointNote.dispose();
    _limitJoiner.dispose();
    _baseAmount.dispose();
    _distancePerLap.dispose();
    _numberOfLaps.dispose();
    _totalDistance.dispose();
    _disposeRewardItems(_guaranteedRewardItems);
    _disposeRewardItems(_competitionRewardItems);
    super.dispose();
  }

  void _disposeRewardItems(List<_DraftRewardImage> items) {
    for (final item in items) {
      item.dispose();
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      initialDate: _eventDate ?? now,
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeOfDay.now(),
    );
    if (picked != null) setState(() => _startTime = picked);
  }

  Future<void> _pickEventPictures() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage();
    if (files.isEmpty) return;

    final remaining = 10 - _eventImages.length;
    final take = _filterPreviewableImages(files).take(remaining).toList();
    if (take.isEmpty) return;

    setState(() {
      _eventImages.addAll(take);
    });
  }

  void _setEventCover(int index) {
    if (index <= 0 || index >= _eventImages.length) return;
    setState(() {
      final selected = _eventImages.removeAt(index);
      _eventImages.insert(0, selected);
    });
  }

  void _removeEventImage(int index) {
    if (index < 0 || index >= _eventImages.length) return;
    setState(() {
      _eventImages.removeAt(index);
    });
  }

  Future<void> _pickRewardPictures(List<_DraftRewardImage> items) async {
    final remaining = 10 - items.length;
    if (remaining <= 0) return;

    final picker = ImagePicker();
    final files = await picker.pickMultiImage();
    if (files.isEmpty) return;

    final selected =
        _filterPreviewableImages(files).take(remaining).toList(growable: false);
    if (selected.isEmpty) return;
    if (!mounted) return;
    setState(() {
      final defaults = identical(items, _competitionRewardItems)
          ? _competitionRewardOptions.first.value
          : _guaranteedRewardOptions.first.value;
      items.addAll(selected.map((file) => _DraftRewardImage(file, defaults)));
    });
  }

  void _moveRewardItem(List<_DraftRewardImage> items, int index, int delta) {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= items.length) return;
    setState(() {
      final item = items.removeAt(index);
      items.insert(newIndex, item);
    });
  }

  void _removeRewardItem(List<_DraftRewardImage> items, int index) {
    final removed = items.removeAt(index);
    removed.dispose();
    setState(() {});
  }

  Future<void> _uploadRewardSection({
    required int eventId,
    required String section,
    required List<_DraftRewardImage> items,
  }) async {
    if (items.isEmpty) return;
    await EventApi.instance.uploadRewardItems(
      eventId: eventId,
      section: section,
      files: items.map((item) => item.file).toList(growable: false),
      itemTypes: items.map((item) => item.selectedType).toList(growable: false),
      captions: items
          .map((item) => item.captionController.text.trim())
          .toList(growable: false),
      sortOrders: List<int>.generate(items.length, (index) => index + 1),
    );
  }

  Future<void> _pickLocationOnMap() async {
    final picked = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => BigEventLocationPickerPage(
          initialLat: _locationLat,
          initialLng: _locationLng,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _locationLat = (picked['latitude'] as num?)?.toDouble();
      _locationLng = (picked['longitude'] as num?)?.toDouble();
      _locationProvince = (picked['province'] ?? '').toString().trim();
      _locationDistrict = (picked['district'] ?? '').toString().trim();
      _locationDisplay = (picked['location_display'] ?? '').toString().trim();
    });
  }

  String get _locationPreviewText {
    if (_locationLat == null || _locationLng == null) {
      return _t('location_not_set');
    }

    if (_locationDisplay.isNotEmpty) return _locationDisplay;
    if (_locationProvince.isNotEmpty || _locationDistrict.isNotEmpty) {
      return [_locationProvince, _locationDistrict]
          .where((part) => part.isNotEmpty)
          .join(', ');
    }

    return 'Lat ${_locationLat!.toStringAsFixed(5)}, '
        'Lng ${_locationLng!.toStringAsFixed(5)}';
  }

  String get _paymentModeValue => switch (_paymentMode) {
        BigEventPaymentMode.stripeAuto => 'stripe_auto',
      };

  Future<void> _publish() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    final baseAmount = _baseAmountValue;
    final promptpayAmountThb = _promptpayAmountThb;
    final fee = promptpayAmountThb ?? 0;
    final distancePerLap = double.tryParse(_distancePerLap.text.trim());
    final numberOfLaps = int.tryParse(_numberOfLaps.text.trim());
    final adminId = await AdminSessionService.getCurrentAdminId();

    final orgIdInt = int.tryParse(widget.orgId) ?? 0;
    if (orgIdInt == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('invalid_organization_id'))),
      );
      return;
    }

    if (adminId == null || adminId <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('please_log_in_admin_again'))),
      );
      return;
    }

    if (_eventDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('please_select_event_date'))),
      );
      return;
    }

    if (_startTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('please_select_start_time'))),
      );
      return;
    }

    if (!_enablePromptpay) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('promptpay_required_big_event'))),
      );
      return;
    }

    if (baseAmount == null || baseAmount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('please_enter_valid_amount_thb'))),
      );
      return;
    }

    if (promptpayAmountThb == null || promptpayAmountThb <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('unable_to_derive_promptpay_amount'))),
      );
      return;
    }

    if (_locationLat == null || _locationLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('please_pick_location_on_map'))),
      );
      return;
    }

    if (distancePerLap == null || distancePerLap <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('please_enter_valid_distance_per_lap'))),
      );
      return;
    }

    if (numberOfLaps == null || numberOfLaps <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('please_enter_valid_number_of_laps'))),
      );
      return;
    }

    final limit = int.tryParse(_limitJoiner.text.trim()) ?? 1;
    final startAt = DateTime(
      _eventDate!.year,
      _eventDate!.month,
      _eventDate!.day,
      _startTime!.hour,
      _startTime!.minute,
    );

    setState(() => _saving = true);

    try {
      final created = await EventApi.instance.createEvent(
        organizationId: orgIdInt,
        title: _title.text.trim(),
        description: _detail.text.trim(),
        locationName: _locationPreviewText,
        startAt: startAt,
        distancePerLap: distancePerLap,
        numberOfLaps: numberOfLaps,
        maxParticipants: limit,
        createdBy: adminId,
        locationLat: _locationLat,
        locationLng: _locationLng,
        province: _locationProvince,
        district: _locationDistrict,
        locationDisplay: _locationDisplay.isNotEmpty
            ? _locationDisplay
            : _locationPreviewText,
        meetingPointNote: _meetingPointNote.text.trim(),
        fee: fee,
        baseAmount: baseAmount,
        promptpayEnabled: true,
        promptpayAmountThb: promptpayAmountThb,
        titleI18n: _buildI18nMap(_title.text),
        descriptionI18n: _buildI18nMap(_detail.text),
        meetingPointI18n: _buildI18nMap(_locationPreviewText),
        locationNameI18n: _buildI18nMap(_locationPreviewText),
        meetingPointNoteI18n: _buildI18nMap(_meetingPointNote.text),
      );

      final eventId = (created['id'] is int)
          ? created['id'] as int
          : int.tryParse('${created['id']}') ?? 0;

      if (eventId == 0) throw Exception('Create success but eventId missing');

      if (_eventImages.isNotEmpty) {
        await EventApi.instance.uploadCover(
          eventId: eventId,
          file: _eventImages.first,
        );
      }

      await EventApi.instance.updateAdminPaymentMethods(
        eventId: eventId,
        adminId: adminId,
        paymentMode: _paymentModeValue,
        enablePromptpay: _enablePromptpay,
        stripeEnabled: true,
        baseAmount: baseAmount,
        promptpayAmountThb: promptpayAmountThb,
        manualPromptpayQrUrl: null,
      );

      final galleryImages = _eventImages.length > 1
          ? _eventImages.skip(1).toList(growable: false)
          : const <XFile>[];
      if (galleryImages.isNotEmpty) {
        await EventApi.instance
            .uploadGallery(eventId: eventId, files: galleryImages);
      }

      await _uploadRewardSection(
        eventId: eventId,
        section: 'guaranteed',
        items: _guaranteedRewardItems,
      );
      await _uploadRewardSection(
        eventId: eventId,
        section: 'competition',
        items: _competitionRewardItems,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t('publish_failed', params: <String, String>{'error': '$e'}),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateText = _eventDate == null
        ? _t('event_date')
        : '${_eventDate!.day}/${_eventDate!.month}/${_eventDate!.year}';
    final timeText =
        _startTime == null ? _t('start_time') : _startTime!.format(context);

    const double boxH = 84;
    const double gap = 10;

    return Scaffold(
      appBar: AppBar(
        title: Text(_t('create_big_event')),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 8),
            child: AdminTranslateButton(
              iconColor: Colors.black87,
              backgroundColor: Colors.transparent,
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        const Icon(Icons.image_outlined,
                            size: 56, color: Colors.black54),
                        const SizedBox(height: 8),
                        Text(
                          '${_t('upload_big_event_pictures')} (${_eventImages.length}/10)',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _saving ? null : _pickEventPictures,
                          child: Text(_t('select_pictures')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_eventImages.isEmpty)
                    Container(
                      height: 180,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.black12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Select images, then choose which one should be the cover before publishing.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700),
                      ),
                    )
                  else ...[
                    Text(
                      'Cover image',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: _buildXFilePreview(
                            _eventImages.first,
                            width: double.infinity,
                            height: 190,
                          ),
                        ),
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Cover',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: InkWell(
                            onTap: _saving ? null : () => _removeEventImage(0),
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.black54,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_eventImages.length > 1) ...[
                      const SizedBox(height: 12),
                      Text(
                        'More images',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 94,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _eventImages.length - 1,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 10),
                          itemBuilder: (_, i) {
                            final actualIndex = i + 1;
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: _buildXFilePreview(
                                    _eventImages[actualIndex],
                                    width: 94,
                                    height: 94,
                                  ),
                                ),
                                Positioned(
                                  left: 6,
                                  bottom: 6,
                                  child: InkWell(
                                    onTap: _saving
                                        ? null
                                        : () => _setEventCover(actualIndex),
                                    borderRadius: BorderRadius.circular(999),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: const Text(
                                        'Set cover',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: InkWell(
                                    onTap: _saving
                                        ? null
                                        : () => _removeEventImage(actualIndex),
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
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('participant_limit'),
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: SizedBox(
                      width: 180,
                      child: TextFormField(
                        controller: _limitJoiner,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: _t('limit_number_of_joiner'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _t('event_name'),
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _title,
                    decoration: InputDecoration(
                      hintText: _t('event_name'),
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? _t('required') : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _CardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      _t('distance'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _distancePerLap,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                            labelText: _t('distance_per_lap'),
                            hintText: 'e.g. 5.0',
                            filled: true,
                            fillColor: Colors.grey.shade200,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (v) {
                            final n = double.tryParse((v ?? '').trim());
                            if (n == null || n <= 0) return _t('required');
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _numberOfLaps,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: _t('number_of_laps'),
                            hintText: 'e.g. 3',
                            filled: true,
                            fillColor: Colors.grey.shade200,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          validator: (v) {
                            final n = int.tryParse((v ?? '').trim());
                            if (n == null || n <= 0) return _t('required');
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _totalDistance,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: _t('total_distance'),
                      hintText: _t('auto_calculated'),
                      filled: true,
                      fillColor: Colors.grey.shade300,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _CardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Text(
                      _t('event_details'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _detail,
                    decoration: InputDecoration(
                      hintText: _t('description'),
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? _t('required') : null,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            InkWell(
                              onTap: _saving ? null : _pickDate,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: boxH,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(dateText,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    Text(
                                      _t('event_date'),
                                      style: TextStyle(
                                          color: Colors.black54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: gap),
                            InkWell(
                              onTap: _saving ? null : _pickStartTime,
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: boxH,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(timeText,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 6),
                                    Text(
                                      _t('start_time'),
                                      style: TextStyle(
                                          color: Colors.black54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.place_outlined, color: Colors.black54),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _locationPreviewText,
                            style: TextStyle(
                              color:
                                  _locationLat == null || _locationLng == null
                                      ? Colors.black54
                                      : Colors.black87,
                              fontWeight:
                                  _locationLat == null || _locationLng == null
                                      ? FontWeight.w400
                                      : FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _pickLocationOnMap,
                      icon: const Icon(Icons.map_outlined),
                      label: Text(_t('pick_location_on_map')),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _meetingPointNote,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: _t('meeting_point_note'),
                      hintText: _t('meeting_point_hint'),
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildRewardSectionCard(
              title: _t('guaranteed_items'),
              subtitle: _t('guaranteed_items_create_subtitle'),
              count: _guaranteedRewardItems.length,
              items: _guaranteedRewardItems,
            ),
            const SizedBox(height: 14),
            _buildRewardSectionCard(
              title: _t('competition_reward_items'),
              subtitle: _t('competition_reward_items_create_subtitle'),
              count: _competitionRewardItems.length,
              items: _competitionRewardItems,
            ),
            const SizedBox(height: 14),
            _CardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t('payment_setup'),
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<BigEventPaymentMode>(
                    value: _paymentMode,
                    decoration: InputDecoration(
                      labelText: _t('payment_mode'),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: BigEventPaymentMode.stripeAuto,
                        child: Text('stripe_auto'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) {
                            if (v == null) return;
                            setState(() => _paymentMode = v);
                          },
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _enablePromptpay,
                    title: Text(_t('promptpay_enabled')),
                    subtitle: Text(_t('promptpay_required_big_event')),
                    onChanged: null,
                  ),
                  Text(
                    _t('promptpay_only_note'),
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _baseAmount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _t('amount_thb'),
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final t = (v ?? '').trim();
                      if (t.isEmpty) return _t('required');
                      final n = double.tryParse(t);
                      if (n == null || n <= 0) return _t('invalid_amount');
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: _totalCollectAmountLabel,
                      border: OutlineInputBorder(),
                    ),
                    child: Text(_moneyText(_totalCollectAmountThb, 'THB')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(_t('cancel')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _saving ? null : _publish,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_t('publish')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardSectionCard({
    required String title,
    required String subtitle,
    required int count,
    required List<_DraftRewardImage> items,
  }) {
    final typeOptions = identical(items, _competitionRewardItems)
        ? _competitionRewardOptions
        : _guaranteedRewardOptions;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$title ($count/10)',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _saving || count >= 10
                    ? null
                    : () => _pickRewardPictures(items),
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(_t('add')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black12),
              ),
              child: Text(
                _t('reward_items_empty_hidden'),
                style: TextStyle(color: Colors.grey.shade700),
              ),
            )
          else
            Column(
              children: List<Widget>.generate(items.length, (index) {
                final item = items[index];
                final order = index + 1;
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == items.length - 1 ? 0 : 12,
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: _buildXFilePreview(
                            item.file,
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
                                          params: {'number': '$order'}),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
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
                                decoration: InputDecoration(
                                  labelText: _t('item_type'),
                                  filled: true,
                                  fillColor: Colors.grey.shade100,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
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
                                decoration: InputDecoration(
                                  labelText: _t('custom_label_optional'),
                                  hintText: _t('custom_label_hint'),
                                  filled: true,
                                  fillColor: Colors.grey.shade100,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
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

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: child,
    );
  }
}

class _DraftRewardImage {
  final XFile file;
  String selectedType;
  final TextEditingController captionController = TextEditingController();

  _DraftRewardImage(this.file, this.selectedType);

  void dispose() {
    captionController.dispose();
  }
}

class _RewardTypeOption {
  final String value;

  const _RewardTypeOption(this.value);
}
