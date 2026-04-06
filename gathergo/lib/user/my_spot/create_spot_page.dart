import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../app_routes.dart';
import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import '../../core/services/session_service.dart';
import '../data/mock_store.dart';
import '../localization/user_locale_controller.dart';
import '../localization/user_strings.dart';
import '../../admin/bigevent/big_event_location_picker_page.dart';

class CreateSpotPage extends StatefulWidget {
  const CreateSpotPage({super.key});

  @override
  State<CreateSpotPage> createState() => _CreateSpotPageState();
}

class _CreateSpotPageState extends State<CreateSpotPage> {
  final _formKey = GlobalKey<FormState>();

  final _nameCtrl = TextEditingController();
  final _locationNoteCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _timeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _kmCtrl = TextEditingController();
  final _roundCtrl = TextEditingController();
  final _maxPeopleCtrl = TextEditingController(text: '1');

  Uint8List? _pickedImageBytes;
  final List<XFile> _pendingSpotImages = <XFile>[];
  final List<_EditableSpotImage> _existingImages = <_EditableSpotImage>[];
  final List<XFile> _newGalleryImages = <XFile>[];
  final Set<int> _deletingMediaIds = <int>{};
  bool _publishing = false;
  double? _locationLat;
  double? _locationLng;
  double? _totalKm;
  String _locationProvince = '';
  String _locationDistrict = '';
  bool _didLoadArgs = false;
  bool _isEditMode = false;
  Map<String, dynamic>? _editingSpot;
  static const String _legacyFallbackAsset =
      'assets/images/user/spots/spot1.png';

  String tr(String key, {Map<String, String> params = const {}}) {
    return UserStrings.text(key, params: params);
  }

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    _kmCtrl.addListener(_recomputeTotalKm);
    _roundCtrl.addListener(_recomputeTotalKm);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadArgs) return;
    _didLoadArgs = true;

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map<String, dynamic> && args["spot"] is Map) {
      final spot = Map<String, dynamic>.from(args["spot"] as Map);
      _editingSpot = spot;
      _isEditMode = true;
      _nameCtrl.text = (spot["title"] ?? "").toString();
      _locationNoteCtrl.text =
          (spot["locationLink"] ?? spot["location_link"] ?? "").toString();
      _dateCtrl.text = (spot["date"] ?? "").toString();
      _timeCtrl.text = (spot["time"] ?? "").toString();
      _descCtrl.text = (spot["description"] ?? "").toString();
      _kmCtrl.text =
          (spot["kmPerRound"] ?? spot["km_per_round"] ?? "").toString();
      _roundCtrl.text = (spot["round"] ?? spot["round_count"] ?? "").toString();
      _maxPeopleCtrl.text =
          (spot["maxPeople"] ?? spot["max_people"] ?? "1").toString();
      _locationLat = _asDouble(spot["locationLat"] ?? spot["location_lat"]);
      _locationLng = _asDouble(spot["locationLng"] ?? spot["location_lng"]);
      _locationProvince = (spot["province"] ?? "").toString();
      _locationDistrict = (spot["district"] ?? "").toString();
      final existingImagePath = (spot["image"] ?? "").toString().trim();
      if (existingImagePath.isEmpty ||
          existingImagePath.startsWith('assets/')) {
        final imageBase64 = (spot["imageBase64"] ?? spot["image_base64"] ?? "")
            .toString()
            .trim()
            .replaceFirst(RegExp(r'^data:image\/[^;]+;base64,'), '');
        if (imageBase64.isNotEmpty) {
          try {
            _pickedImageBytes = base64Decode(imageBase64);
          } catch (_) {}
        }
      }
      _loadExistingMedia();
      _recomputeTotalKm();
    }
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _nameCtrl.dispose();
    _locationNoteCtrl.dispose();
    _dateCtrl.dispose();
    _timeCtrl.dispose();
    _descCtrl.dispose();
    _kmCtrl.dispose();
    _roundCtrl.dispose();
    _maxPeopleCtrl.dispose();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 55);
    if (files.isEmpty) return;

    final remaining = _remainingImageSlots;
    if (remaining <= 0) {
      if (!mounted) return;
      _showSnack('You can upload up to 10 images.');
      return;
    }

    final selected = <XFile>[];
    for (final file in files.take(remaining)) {
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > 4 * 1024 * 1024) {
        if (!mounted) return;
        _showSnack(tr('selected_image_too_large'));
        continue;
      }
      selected.add(file);
    }
    if (!mounted || selected.isEmpty) return;
    setState(() {
      _pendingSpotImages.addAll(selected);
    });
    await _syncPendingCoverAndGallery();
  }

  Future<void> _pickAdditionalImages() async {
    await _pickImage();
  }

  Future<void> _syncPendingCoverAndGallery() async {
    if (_pendingSpotImages.isEmpty) {
      Uint8List? restoredCover;
      final existingBase64 =
          ((_editingSpot?["imageBase64"] ?? _editingSpot?["image_base64"] ?? "")
                  .toString())
              .trim()
              .replaceFirst(RegExp(r'^data:image\/[^;]+;base64,'), '');
      if (existingBase64.isNotEmpty) {
        try {
          restoredCover = base64Decode(existingBase64);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _pickedImageBytes = restoredCover;
        _newGalleryImages.clear();
      });
      return;
    }

    final coverBytes = await _pendingSpotImages.first.readAsBytes();
    if (!mounted) return;
    setState(() {
      _pickedImageBytes = coverBytes;
      _newGalleryImages
        ..clear()
        ..addAll(_pendingSpotImages.skip(1));
    });
  }

  Future<void> _setPendingCover(int index) async {
    if (index <= 0 || index >= _pendingSpotImages.length) return;
    final selected = _pendingSpotImages.removeAt(index);
    _pendingSpotImages.insert(0, selected);
    await _syncPendingCoverAndGallery();
  }

  Future<void> _removePendingSpotImage(int index) async {
    if (index < 0 || index >= _pendingSpotImages.length) return;
    _pendingSpotImages.removeAt(index);
    await _syncPendingCoverAndGallery();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
      initialDate: now,
    );
    if (picked == null) return;

    setState(() {
      _dateCtrl.text =
          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked == null) return;

    setState(() {
      _timeCtrl.text =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    });
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
      _locationLat = picked['latitude'];
      _locationLng = picked['longitude'];
      _locationProvince = (picked['province'] ?? '').toString();
      _locationDistrict = (picked['district'] ?? '').toString();
    });
  }

  void _recomputeTotalKm() {
    final kmPerRound = double.tryParse(_kmCtrl.text.trim());
    final round = double.tryParse(_roundCtrl.text.trim());
    setState(() {
      if (kmPerRound != null && kmPerRound > 0 && round != null && round > 0) {
        _totalKm = kmPerRound * round;
      } else {
        _totalKm = null;
      }
    });
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  String _composeLocationLabel({
    String? province,
    String? district,
    String? fallback,
  }) {
    final normalizedProvince = (province ?? '').toString().trim();
    final normalizedDistrict = (district ?? '').toString().trim();

    if (normalizedProvince.isNotEmpty || normalizedDistrict.isNotEmpty) {
      return [normalizedProvince, normalizedDistrict]
          .where((part) => part.isNotEmpty)
          .join(', ');
    }

    return (fallback ?? '').toString().trim();
  }

  String get _locationPreviewText {
    if (_locationLat == null || _locationLng == null) {
      return tr('location_not_specified');
    }
    final locationLabel = _composeLocationLabel(
      province: _locationProvince,
      district: _locationDistrict,
    );
    if (locationLabel.isNotEmpty) return locationLabel;
    return 'Lat ${_locationLat!.toStringAsFixed(5)}, '
        'Lng ${_locationLng!.toStringAsFixed(5)}';
  }

  String get _totalKmText {
    final totalKm = _totalKm;
    if (totalKm == null) return tr('auto_calculated_from_km_and_round');
    final decimals = totalKm % 1 == 0 ? 0 : 2;
    return '${totalKm.toStringAsFixed(decimals)} KM';
  }

  bool _isSyntheticFallbackImage(String path) {
    final normalized = path.trim();
    if (normalized.isEmpty) return false;
    return normalized == _legacyFallbackAsset;
  }

  bool get _hasExistingCover {
    final existingImagePath = (_editingSpot?["image"] ?? "").toString().trim();
    final existingImageBase64 =
        ((_editingSpot?["imageBase64"] ?? _editingSpot?["image_base64"] ?? "")
                .toString())
            .trim();

    return _pickedImageBytes != null ||
        existingImageBase64.isNotEmpty ||
        (existingImagePath.isNotEmpty &&
            !_isSyntheticFallbackImage(existingImagePath));
  }

  Future<void> _loadExistingMedia({int? spotId}) async {
    spotId ??= int.tryParse(
      (_editingSpot?["backendSpotId"] ?? _editingSpot?["id"] ?? "").toString(),
    );
    if (spotId == null) return;

    try {
      final res = await http.get(
        Uri.parse("${ConfigService.getBaseUrl()}/api/spots/$spotId/media"),
        headers: const {"Accept": "application/json"},
      );

      if (res.statusCode != 200) return;
      final decoded = jsonDecode(res.body);
      if (decoded is! List) return;

      final images = <_EditableSpotImage>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final url = ConfigService.resolveUrl(
          (item["file_url"] ?? item["fileUrl"] ?? "").toString(),
        );
        if (url.isEmpty || images.any((element) => element.url == url)) {
          continue;
        }
        images.add(
          _EditableSpotImage(
            id: int.tryParse('${item["id"] ?? ""}'),
            url: url,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _existingImages
          ..clear()
          ..addAll(images);
      });
    } catch (_) {}
  }

  int get _totalImageCount {
    if (_pendingSpotImages.isNotEmpty) {
      return _pendingSpotImages.length + _existingImages.length;
    }
    final coverCount = _hasExistingCover ? 1 : 0;
    return coverCount + _existingImages.length + _newGalleryImages.length;
  }

  int get _remainingImageSlots {
    final remaining = 10 - _totalImageCount;
    return remaining < 0 ? 0 : remaining;
  }

  Future<void> _uploadSpotGallery(int spotId) async {
    if (_newGalleryImages.isEmpty) return;

    final adminId = await AdminSessionService.getCurrentAdminId();
    final userId = await SessionService.getCurrentUserId();
    final req = http.MultipartRequest(
      'POST',
      Uri.parse("${ConfigService.getBaseUrl()}/api/spots/$spotId/gallery"),
    );
    req.headers["Accept"] = "application/json";
    if (adminId != null && adminId > 0) req.headers["x-admin-id"] = '$adminId';
    if (userId != null && userId > 0) req.headers["x-user-id"] = '$userId';

    for (final file in _newGalleryImages) {
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        req.files.add(
          http.MultipartFile.fromBytes('files', bytes, filename: file.name),
        );
      } else {
        req.files.add(await http.MultipartFile.fromPath('files', file.path));
      }
    }

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 201) {
      throw Exception("Upload gallery failed (${res.statusCode}): ${res.body}");
    }
  }

  Future<void> _deleteExistingImage(_EditableSpotImage image) async {
    final mediaId = image.id;
    final spotId = int.tryParse(
      (_editingSpot?["backendSpotId"] ?? _editingSpot?["id"] ?? "").toString(),
    );
    if (mediaId == null ||
        spotId == null ||
        _publishing ||
        _deletingMediaIds.contains(mediaId)) {
      return;
    }

    final adminId = await AdminSessionService.getCurrentAdminId();
    final userId = await SessionService.getCurrentUserId();

    setState(() => _deletingMediaIds.add(mediaId));
    try {
      final res = await http.delete(
        Uri.parse(
            "${ConfigService.getBaseUrl()}/api/spots/$spotId/media/$mediaId"),
        headers: {
          "Accept": "application/json",
          if (adminId != null && adminId > 0) "x-admin-id": '$adminId',
          if (userId != null && userId > 0) "x-user-id": '$userId',
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
      _showSnack("Delete image failed: $e");
    } finally {
      if (mounted) {
        setState(() => _deletingMediaIds.remove(mediaId));
      }
    }
  }

  Widget _buildXFilePreview(
    XFile file, {
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
  }) {
    if (!kIsWeb) {
      return Image.file(
        io.File(file.path),
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => Container(
          width: width,
          height: height,
          color: Colors.grey.shade200,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported_outlined),
        ),
      );
    }

    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (snapshot.hasData &&
            snapshot.connectionState == ConnectionState.done) {
          return Image.memory(
            snapshot.data!,
            width: width,
            height: height,
            fit: fit,
          );
        }
        return SizedBox(
          width: width,
          height: height,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _createSpotBackend(
    Map<String, dynamic> spot,
  ) async {
    final adminId = await AdminSessionService.getCurrentAdminId();
    final userId = await SessionService.getCurrentUserId();
    if ((adminId == null || adminId <= 0) && (userId == null || userId <= 0)) {
      throw Exception("User or admin session required to create a Spot.");
    }

    final uri = Uri.parse("${ConfigService.getBaseUrl()}/api/spots");
    final res = await http
        .post(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Accept": "application/json",
            if (adminId != null && adminId > 0)
              "x-admin-id": adminId.toString(),
            if (userId != null && userId > 0) "x-user-id": userId.toString(),
          },
          body: jsonEncode({
            "title": (spot["title"] ?? "").toString(),
            "description": (spot["description"] ?? "").toString(),
            "location": (spot["location"] ?? "").toString(),
            "location_link": (spot["locationLink"] ?? "").toString(),
            "location_lat": spot["locationLat"],
            "location_lng": spot["locationLng"],
            "province": (spot["province"] ?? "").toString(),
            "district": (spot["district"] ?? "").toString(),
            "event_date": (spot["date"] ?? "").toString(),
            "event_time": (spot["time"] ?? "").toString(),
            "km_per_round": (spot["kmPerRound"] ?? "").toString(),
            "round_count": (spot["round"] ?? "").toString(),
            "max_people": (spot["maxPeople"] ?? "").toString(),
            "image_base64": (spot["imageBase64"] ?? "").toString(),
            "image_url": "",
            "status": "active",
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 201) {
      throw Exception("HTTP ${res.statusCode}: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw Exception("Invalid backend response for /api/spots");
    }

    return Map<String, dynamic>.from(decoded);
  }

  Future<Map<String, dynamic>> _updateSpotBackend(
    int spotId,
    Map<String, dynamic> spot,
  ) async {
    final adminId = await AdminSessionService.getCurrentAdminId();
    final userId = await SessionService.getCurrentUserId();
    if ((adminId == null || adminId <= 0) && (userId == null || userId <= 0)) {
      throw Exception("User or admin session required to edit a Spot.");
    }

    final uri = Uri.parse("${ConfigService.getBaseUrl()}/api/spots/$spotId");
    final res = await http
        .put(
          uri,
          headers: {
            "Content-Type": "application/json",
            "Accept": "application/json",
            if (adminId != null && adminId > 0)
              "x-admin-id": adminId.toString(),
            if (userId != null && userId > 0) "x-user-id": userId.toString(),
          },
          body: jsonEncode({
            "title": (spot["title"] ?? "").toString(),
            "description": (spot["description"] ?? "").toString(),
            "location": (spot["location"] ?? "").toString(),
            "location_link": (spot["locationLink"] ?? "").toString(),
            "location_lat": spot["locationLat"],
            "location_lng": spot["locationLng"],
            "province": (spot["province"] ?? "").toString(),
            "district": (spot["district"] ?? "").toString(),
            "event_date": (spot["date"] ?? "").toString(),
            "event_time": (spot["time"] ?? "").toString(),
            "km_per_round": (spot["kmPerRound"] ?? "").toString(),
            "round_count": (spot["round"] ?? "").toString(),
            "max_people": (spot["maxPeople"] ?? "").toString(),
            "image_base64": (spot["imageBase64"] ?? "").toString(),
            "image_url": "",
            "status": "active",
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception("HTTP ${res.statusCode}: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map) {
      throw Exception("Invalid backend response for PUT /api/spots/:id");
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _publish() async {
    if (_publishing) return;
    if (!_formKey.currentState!.validate()) return;

    if (_locationLat == null || _locationLng == null) {
      _showSnack(tr('please_pick_location_on_map'));
      return;
    }
    if (_dateCtrl.text.trim().isEmpty) {
      _showSnack(tr('please_select_date'));
      return;
    }
    if (_timeCtrl.text.trim().isEmpty) {
      _showSnack(tr('please_select_time'));
      return;
    }

    final maxPeople =
        int.tryParse(_maxPeopleCtrl.text.trim())?.clamp(1, 9999) ?? 1;
    final existingImagePath = (_editingSpot?["image"] ?? "").toString().trim();
    final existingImageBase64 =
        ((_editingSpot?["imageBase64"] ?? _editingSpot?["image_base64"] ?? "")
                .toString())
            .trim();
    final hasNewCover = _pickedImageBytes != null;
    final existingCoverPath =
        _isSyntheticFallbackImage(existingImagePath) ? '' : existingImagePath;

    final spot = <String, dynamic>{
      "image": existingCoverPath,
      "imageBase64":
          hasNewCover ? base64Encode(_pickedImageBytes!) : existingImageBase64,
      "title": _nameCtrl.text.trim(),
      "distance": _totalKmText,
      "date": _dateCtrl.text.trim(),
      "time": _timeCtrl.text.trim(),
      "location": _locationPreviewText,
      "province": _locationProvince,
      "district": _locationDistrict,
      "locationLink": _locationNoteCtrl.text.trim(),
      "locationLat": _locationLat,
      "locationLng": _locationLng,
      "description": _descCtrl.text.trim(),
      "round": _roundCtrl.text.trim(),
      "kmPerRound": _kmCtrl.text.trim(),
      "maxPeople": maxPeople.toString(),
      "joinedCount": "0",
      "host": "You",
      "isJoined": false,
    };

    setState(() => _publishing = true);
    try {
      final backendSpot = _isEditMode && _editingSpot != null
          ? await _updateSpotBackend(
              int.parse((_editingSpot!["backendSpotId"] ?? _editingSpot!["id"])
                  .toString()),
              spot,
            )
          : await _createSpotBackend(spot);
      final savedSpotId =
          int.parse((backendSpot["id"] ?? spot["id"] ?? "").toString());
      await _uploadSpotGallery(savedSpotId);
      spot["backendSpotId"] = backendSpot["id"];
      spot["id"] = backendSpot["id"];
      spot["creatorUserId"] =
          (backendSpot["created_by_user_id"] ?? "").toString();
      spot["creatorRole"] = (backendSpot["creator_role"] ?? "user").toString();
      spot["spotKey"] = (backendSpot["spot_key"] ?? "").toString();
      spot["spot_key"] = (backendSpot["spot_key"] ?? "").toString();
      final creatorName = (backendSpot["creator_name"] ?? "User").toString();
      spot["creatorName"] = creatorName;
      spot["host"] = creatorName;
      spot["hostName"] = creatorName;
      spot["province"] =
          (backendSpot["province"] ?? spot["province"]).toString();
      spot["district"] =
          (backendSpot["district"] ?? spot["district"]).toString();
      spot["location"] = _composeLocationLabel(
        province: spot["province"]?.toString(),
        district: spot["district"]?.toString(),
        fallback: (backendSpot["location"] ?? spot["location"]).toString(),
      );
      spot["locationLink"] =
          (backendSpot["location_link"] ?? spot["locationLink"]).toString();
      spot["locationLat"] = backendSpot["location_lat"] ?? spot["locationLat"];
      spot["locationLng"] = backendSpot["location_lng"] ?? spot["locationLng"];
      spot["status"] = (backendSpot["status"] ?? "active").toString();
      if ((backendSpot["image_base64"] ?? "").toString().trim().isNotEmpty) {
        spot["imageBase64"] = (backendSpot["image_base64"] ?? "").toString();
      }
      final backendImageUrl =
          ConfigService.resolveUrl((backendSpot["image_url"] ?? "").toString());
      spot["image"] = backendImageUrl;
      if (_newGalleryImages.isNotEmpty) {
        await _loadExistingMedia(spotId: savedSpotId);
      }
      _newGalleryImages.clear();

      if (_isEditMode) {
        MockStore.updateSpot(spot);
      } else {
        MockStore.createMySpot(spot, alsoAddToBrowse: false);
      }

      if (!mounted) return;
      Navigator.pop(context, {
        "refresh": true,
        "spotId": backendSpot["id"],
        "spot": spot,
      });
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        tr(
          _isEditMode ? 'save_failed' : 'publish_failed',
          params: {'error': e.toString()},
        ),
      );
    } finally {
      if (mounted) setState(() => _publishing = false);
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildPickedImagePreview() {
    if (_pickedImageBytes == null) {
      return Container(
        height: 190,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(18),
        ),
        child: InkWell(
          onTap: _publishing ? null : _pickImage,
          borderRadius: BorderRadius.circular(18),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.image_outlined, size: 48, color: Colors.black54),
                SizedBox(height: 10),
                Text(
                  UserStrings.spotTerm == 'Spot'
                      ? tr('upload_spot_cover')
                      : tr('upload_cover'),
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 4),
                Text(
                  tr('choose_one_image_for_your_activity'),
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 190,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.memory(_pickedImageBytes!, fit: BoxFit.cover),
          ),
          Positioned(
            top: 12,
            right: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton.icon(
                  onPressed: _publishing ? null : _pickImage,
                  icon:
                      const Icon(Icons.add_photo_alternate_outlined, size: 18),
                  label: Text(tr('change')),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: _publishing || _pendingSpotImages.isEmpty
                      ? null
                      : () => _removePendingSpotImage(0),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.all(8),
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
              ],
            ),
          ),
          const Positioned(
            left: 12,
            top: 12,
            child: _SpotImageBadge(label: 'Cover'),
          ),
        ],
      ),
    );
  }

  Widget _buildGalleryManager() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Spot images ($_totalImageCount/10)',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            OutlinedButton(
              onPressed: _publishing || _remainingImageSlots <= 0
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
        if (_existingImages.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _existingImages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final image = _existingImages[index];
                final deleting =
                    image.id != null && _deletingMediaIds.contains(image.id);
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
                          child: const Icon(Icons.image_not_supported_outlined),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: InkWell(
                        onTap:
                            deleting ? null : () => _deleteExistingImage(image),
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
        ],
        if (_newGalleryImages.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 84,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _newGalleryImages.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final actualIndex = index + 1;
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _buildXFilePreview(
                        _newGalleryImages[index],
                        width: 84,
                        height: 84,
                      ),
                    ),
                    const Positioned(
                      left: 6,
                      top: 6,
                      child: _SpotImageBadge(label: 'New'),
                    ),
                    Positioned(
                      left: 6,
                      bottom: 6,
                      child: InkWell(
                        onTap: _publishing
                            ? null
                            : () => _setPendingCover(actualIndex),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(999),
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
                      right: 4,
                      top: 4,
                      child: InkWell(
                        onTap: _publishing
                            ? null
                            : () => _removePendingSpotImage(actualIndex),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F3F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF00C9A7),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEditMode ? tr('edit_spot') : tr('create_your_spot'),
          style:
              const TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
        ),
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
                  _SectionLabel(tr('spot_image')),
                  const SizedBox(height: 12),
                  _buildPickedImagePreview(),
                  const SizedBox(height: 12),
                  _buildGalleryManager(),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _CardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel(tr('basic_information')),
                  const SizedBox(height: 12),
                  _inputField(
                    controller: _nameCtrl,
                    label: tr('spot_name'),
                    hintText: tr('spot_name_hint'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _tapInfoField(
                          label: tr('date'),
                          value: _dateCtrl.text.isEmpty
                              ? tr('select_date')
                              : _dateCtrl.text,
                          icon: Icons.calendar_today_outlined,
                          onTap: _publishing ? null : _pickDate,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _tapInfoField(
                          label: tr('time'),
                          value: _timeCtrl.text.isEmpty
                              ? tr('select_time')
                              : _timeCtrl.text,
                          icon: Icons.access_time_outlined,
                          onTap: _publishing ? null : _pickTime,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _locationPreviewCard(),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _publishing ? null : _pickLocationOnMap,
                      icon: const Icon(Icons.map_outlined),
                      label: Text(tr('pick_location_on_map')),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFF00C9A7)),
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _inputField(
                    controller: _locationNoteCtrl,
                    label: tr('location_note'),
                    hintText: tr('location_note_hint'),
                    maxLines: 2,
                    required: false,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _CardShell(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SectionLabel(tr('activity_details')),
                  const SizedBox(height: 12),
                  _inputField(
                    controller: _descCtrl,
                    label: tr('description'),
                    hintText: tr('description_hint'),
                    maxLines: 4,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _inputField(
                          controller: _kmCtrl,
                          label: tr('km_per_round'),
                          hintText: '5',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _inputField(
                          controller: _roundCtrl,
                          label: tr('round'),
                          hintText: '3',
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _readOnlyInfoCard(
                    label: tr('total_distance'),
                    value: _totalKmText,
                    icon: Icons.directions_run_outlined,
                  ),
                  const SizedBox(height: 12),
                  _inputField(
                    controller: _maxPeopleCtrl,
                    label: tr('max_participants'),
                    hintText: '10',
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F4DE),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.volunteer_activism_outlined),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            tr('spot_is_free_no_payment_required'),
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _publishing ? null : _publish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFD25C),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: Colors.black26),
                  ),
                  elevation: 0,
                ),
                child: _publishing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        _isEditMode ? tr('save_changes') : tr('publish'),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _locationPreviewCard() {
    final hasLocation = _locationLat != null && _locationLng != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            hasLocation ? Icons.place : Icons.place_outlined,
            color: hasLocation ? const Color(0xFF00C9A7) : Colors.black54,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('picked_location'),
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _locationPreviewText,
                  style: TextStyle(
                    color: hasLocation ? Colors.black87 : Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool required = true,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        filled: true,
        fillColor: Colors.grey.shade200,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
      validator: (value) {
        if (!required) return null;
        if ((value ?? '').trim().isEmpty) return tr('required_field');
        return null;
      },
    );
  }

  Widget _tapInfoField({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.black54),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readOnlyInfoCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00C9A7)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 16,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: child,
    );
  }
}

class _EditableSpotImage {
  final int? id;
  final String url;

  const _EditableSpotImage({
    required this.id,
    required this.url,
  });
}

class _SpotImageBadge extends StatelessWidget {
  final String label;

  const _SpotImageBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.blueAccent,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
