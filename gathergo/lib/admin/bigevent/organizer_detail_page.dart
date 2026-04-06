import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import '../data/event_api.dart';
import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import '../models/organization.dart';
import '../utils/url_utils.dart';
import 'create_big_event_page.dart';
import 'big_event_detail_page.dart';

class OrganizerDetailPage extends StatefulWidget {
  final Organization? org;
  const OrganizerDetailPage({super.key, this.org});

  @override
  State<OrganizerDetailPage> createState() => _OrganizerDetailPageState();
}

class _OrganizerDetailPageState extends State<OrganizerDetailPage> {
  late Organization org;

  final _search = TextEditingController();
  Future<List<_DbEvent>>? _future;
  final Map<String, String> _locationLabelCache = <String, String>{};

  bool _deleting = false;
  bool _updatingImage = false;

  String get _baseUrl => ConfigService.getBaseUrl();

  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    AdminLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _search.dispose();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _t(String key, {Map<String, String> params = const {}}) {
    return AdminStrings.text(key, params: params);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    org = widget.org ??
        (ModalRoute.of(context)!.settings.arguments as Organization);
    _future ??= _load();
  }

  Future<List<_DbEvent>> _load() async {
    final orgId = int.tryParse(org.id) ?? 0;
    if (orgId == 0) return [];

    final list = await EventApi.instance.listEventsByOrg(orgId);
    final items = list
        .map((e) => _DbEvent.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    await _hydrateEventLocations(items);
    return items;
  }

  String _locationCacheKey(_DbEvent event) {
    if (event.id > 0) return 'event:${event.id}';
    return 'coord:${event.locationLat ?? ''},${event.locationLng ?? ''}';
  }

  String _extractProvinceFromPlacemark(Placemark placemark) {
    return (placemark.administrativeArea ??
            placemark.subAdministrativeArea ??
            placemark.locality ??
            '')
        .trim();
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

  Future<void> _hydrateEventLocations(List<_DbEvent> events) async {
    final pending = <Future<void>>[];

    for (final event in events) {
      if (event.locationText != 'Location not specified') {
        _locationLabelCache[_locationCacheKey(event)] = event.locationText;
        continue;
      }

      final lat = event.locationLat;
      final lng = event.locationLng;
      if (lat == null || lng == null) continue;

      pending.add(() async {
        try {
          await setLocaleIdentifier('en');
          final placemarks = await placemarkFromCoordinates(lat, lng);
          if (placemarks.isEmpty) return;
          final placemark = placemarks.first;
          final province = _extractProvinceFromPlacemark(placemark);
          final district = _extractDistrictFromPlacemark(placemark, province);
          if (province.isEmpty && district.isEmpty) return;
          _locationLabelCache[_locationCacheKey(event)] = district.isEmpty
              ? province
              : province.isEmpty
                  ? district
                  : '$district, $province';
        } catch (_) {}
      }());
    }

    if (pending.isNotEmpty) {
      await Future.wait(pending);
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  List<_DbEvent> _filtered(List<_DbEvent> items) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return items;

    bool match(String? s) => (s ?? "").toLowerCase().contains(q);

    return items.where((e) {
      return match(e.title) ||
          match(e.description) ||
          match(e.meetingPoint) ||
          match(e.locationDisplay) ||
          match(e.district) ||
          match(e.city) ||
          match(e.province) ||
          match(e.status) ||
          match(e.type) ||
          match(e.startDateText) ||
          match(e.startTimeText);
    }).toList();
  }

  Future<void> _goCreateBigEvent() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateBigEventPage(orgId: org.id)),
    );

    if (result == true) {
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_t('publish'))),
        );
      }
    }
  }

  // ✅ Dialog ยืนยันลบ
  Future<void> _confirmDeleteOrganization() async {
    if (_deleting) return;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          title: Text(_t("delete_organization")),
          content: Text(_t("delete_organization_confirm")),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("No, I don’t"),
            ),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(context, true),
              child: const Text("Yes, I do"),
            ),
          ],
        );
      },
    );

    if (ok == true) {
      await _deleteOrganization();
    }
  }

  // ✅ ลบ organization
  Future<void> _deleteOrganization() async {
    final orgId = int.tryParse(org.id) ?? 0;
    if (orgId == 0) return;

    setState(() => _deleting = true);

    try {
      final adminId = await AdminSessionService.getCurrentAdminId();
      if (adminId == null || adminId <= 0) {
        throw Exception("No active admin session");
      }

      final uri = Uri.parse("$_baseUrl/api/admin/organizations/$orgId")
          .replace(queryParameters: {"admin_id": adminId.toString()});
      final res = await http.delete(
        uri,
        headers: {
          "Accept": "application/json",
          "x-admin-id": adminId.toString(),
        },
      );

      if (res.statusCode == 200 || res.statusCode == 204) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Organization deleted")),
        );
        Navigator.pop(context, true);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Delete failed (${res.statusCode})")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Delete error: $e")),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<String> _uploadOrgImageBytes(Uint8List bytes, String? fileName) async {
    final uri = Uri.parse("$_baseUrl/api/upload/org-image");
    final req = http.MultipartRequest("POST", uri);
    final adminId = await AdminSessionService.getCurrentAdminId();
    if (adminId != null && adminId > 0) {
      req.headers["x-admin-id"] = adminId.toString();
    }
    req.files.add(
      http.MultipartFile.fromBytes(
        "file",
        bytes,
        filename: (fileName == null || fileName.trim().isEmpty)
            ? "org_image_${DateTime.now().millisecondsSinceEpoch}.jpg"
            : fileName.trim(),
      ),
    );

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 201) {
      throw Exception("Upload image failed (${res.statusCode}): ${res.body}");
    }

    final body = jsonDecode(res.body);
    final url = (body is Map ? body["image_url"] : null)?.toString().trim();
    if (url == null || url.isEmpty) {
      throw Exception("Upload image failed: missing image_url");
    }
    return url;
  }

  Future<void> _editCompanyImage() async {
    if (_updatingImage) return;

    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_t('update_organizer_profile_image')),
        content: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 180,
            width: 300,
            child: Image.memory(bytes, fit: BoxFit.cover),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('save_update')),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _updatingImage = true);
    try {
      final adminId = await AdminSessionService.getCurrentAdminId();
      final orgId = int.tryParse(org.id) ?? 0;
      if (orgId == 0) throw Exception("Invalid organization ID");

      final newImageUrl = await _uploadOrgImageBytes(bytes, file.name);
      final uri = Uri.parse("$_baseUrl/api/organizations/$orgId");
      final payload = <String, dynamic>{
        "name": org.name,
        "description": org.businessProfile,
        "phone": org.phone,
        "email": org.email,
        "address": org.address,
        "image_url": newImageUrl,
      };

      final res = await http.put(
        uri,
        headers: {
          "Content-Type": "application/json",
          if (adminId != null && adminId > 0) "x-admin-id": adminId.toString(),
        },
        body: jsonEncode(payload),
      );
      if (res.statusCode != 200) {
        throw Exception(
            "Update organization failed (${res.statusCode}): ${res.body}");
      }

      final body = jsonDecode(res.body);
      final persistedUrl =
          (body is Map ? body["image_url"] : null)?.toString().trim();
      if (!mounted) return;
      setState(() {
        org = org.copyWith(
            imageUrl: (persistedUrl == null || persistedUrl.isEmpty)
                ? newImageUrl
                : persistedUrl);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t("organizer_profile_image_updated"))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_t("image_update_failed", params: {"error": "$e"}))),
      );
    } finally {
      if (mounted) setState(() => _updatingImage = false);
    }
  }

  Future<void> _editOrganizerInfo() async {
    final nameController = TextEditingController(text: org.name);
    final emailController = TextEditingController(text: org.email);
    final phoneController = TextEditingController(text: org.phone);
    final addressController = TextEditingController(text: org.address);
    final profileController = TextEditingController(text: org.businessProfile);

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(_t('edit_organizer_info')),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration:
                        InputDecoration(labelText: _t('organization_name')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    decoration: InputDecoration(labelText: _t('email')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: phoneController,
                    decoration: InputDecoration(labelText: _t('phone')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: addressController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(labelText: _t('address')),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: profileController,
                    minLines: 3,
                    maxLines: 5,
                    decoration:
                        InputDecoration(labelText: _t('organizer_profile')),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(_t('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(_t('save')),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      final adminId = await AdminSessionService.getCurrentAdminId();
      final orgId = int.tryParse(org.id) ?? 0;
      if (orgId == 0) throw Exception("Invalid organization ID");

      final uri = Uri.parse("$_baseUrl/api/organizations/$orgId");
      final payload = <String, dynamic>{
        "name": nameController.text.trim(),
        "description": profileController.text.trim(),
        "phone": phoneController.text.trim(),
        "email": emailController.text.trim(),
        "address": addressController.text.trim(),
        "image_url": org.imageUrl,
      };

      final res = await http.put(
        uri,
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          if (adminId != null && adminId > 0) "x-admin-id": adminId.toString(),
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode != 200) {
        throw Exception(
            "Update organizer failed (${res.statusCode}): ${res.body}");
      }

      final body = jsonDecode(res.body);
      if (!mounted) return;
      setState(() {
        org = Organization.fromJson(Map<String, dynamic>.from(body as Map));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t("organizer_info_updated"))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t("update_organizer_info_failed", params: {"error": "$e"}),
          ),
        ),
      );
    } finally {
      nameController.dispose();
      emailController.dispose();
      phoneController.dispose();
      addressController.dispose();
      profileController.dispose();
    }
  }

  // =========================
  // UI helpers
  // =========================
  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      padding: padding ?? const EdgeInsets.all(14),
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
      child: child,
    );
  }

  InputDecoration _searchDec(String hint) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.black12),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.black12),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
            color: Theme.of(context).colorScheme.primary, width: 1.4),
      ),
    );
  }

  Widget _infoLine(String label, String value) {
    final v = value.trim().isEmpty ? "-" : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                  color: Colors.black54, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(
                  color: Colors.black87, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderImage({double height = 190}) {
    return Container(
      height: height,
      width: double.infinity,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      child: const Icon(Icons.apartment, size: 68, color: Colors.black45),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ รูปจาก DB มาก่อน
    final net = (org.imageUrl ?? '').trim();
    final netUrl = net.isEmpty ? null : fixLocalhostForEmulator(net);

    // ✅ สร้าง image widget
    final Widget imageWidget = (netUrl != null)
        ? Image.network(
            netUrl,
            height: 190,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholderImage(),
          )
        : _placeholderImage();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        title: Text(_t('organizer_detail')),
        actions: [
          IconButton(
              tooltip: _t("refresh"),
              onPressed: _refresh,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          // ===== Header image + delete button =====
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: imageWidget,
              ),
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black12),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: TextButton.icon(
                    onPressed: _updatingImage ? null : _editCompanyImage,
                    icon: _updatingImage
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.edit_outlined),
                    label: Text(_t("edit_image")),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.92),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.black12),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 2)),
                    ],
                  ),
                  child: _deleting
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : IconButton(
                          tooltip: _t("delete_organization"),
                          icon: const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                          onPressed: _confirmDeleteOrganization,
                        ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _updatingImage ? null : _editOrganizerInfo,
              icon: _updatingImage
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.edit_outlined),
              label: Text(_t('edit_organizer_info')),
            ),
          ),

          const SizedBox(height: 12),

          // ===== Organizer title =====
          Text(
            org.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),

          // ===== Organizer info card =====
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoLine(_t("email"), org.email),
                _infoLine(_t("phone"), org.phone),
                if (org.address.trim().isNotEmpty)
                  _infoLine(_t("address"), org.address),
                if (org.businessProfile.trim().isNotEmpty)
                  _infoLine(_t("profile"), org.businessProfile),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ===== Search =====
          TextField(
            controller: _search,
            decoration: _searchDec(_t('search_big_events_hint')),
          ),

          const SizedBox(height: 14),

          // ===== Events list =====
          FutureBuilder<List<_DbEvent>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Load events error: ${snap.error}',
                    style: const TextStyle(color: Colors.red),
                  ),
                );
              }

              final all = snap.data ?? [];
              final items = _filtered(all);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _t('list_of_big_events'),
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w900),
                        ),
                      ),
                      Text('${_t('total')}: ${items.length}',
                          style: const TextStyle(
                              color: Colors.black54,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (items.isEmpty)
                    _card(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _t('no_big_event_posts_yet'),
                        style: TextStyle(
                            color: Colors.black54, fontWeight: FontWeight.w600),
                      ),
                    )
                  else
                    ...items.map(
                      (e) => _EventTile(
                        event: e,
                        locationLabel:
                            _locationLabelCache[_locationCacheKey(e)],
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    BigEventDetailPage(eventId: e.id)),
                          );
                          await _refresh();
                        },
                      ),
                    ),
                  const SizedBox(height: 80),
                ],
              );
            },
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton.large(
        onPressed: _goCreateBigEvent,
        backgroundColor: Colors.redAccent,
        child: const Icon(Icons.add, size: 40),
      ),
    );
  }
}

class _DbEvent {
  final int id;
  final String? type;
  final String? title;
  final String? description;
  final String? meetingPoint;
  final String? locationDisplay;
  final String? district;
  final String? city;
  final String? province;
  final double? locationLat;
  final double? locationLng;
  final DateTime? startAt;
  final int? maxParticipants;
  final String? status;
  final String? coverUrl;
  final double? distancePerLap;
  final int? numberOfLaps;
  final double? totalDistance;
  final String? legacyDistance;

  _DbEvent({
    required this.id,
    this.type,
    this.title,
    this.description,
    this.meetingPoint,
    this.locationDisplay,
    this.district,
    this.city,
    this.province,
    this.locationLat,
    this.locationLng,
    this.startAt,
    this.maxParticipants,
    this.status,
    this.coverUrl,
    this.distancePerLap,
    this.numberOfLaps,
    this.totalDistance,
    this.legacyDistance,
  });

  String get startDateText {
    if (startAt == null) return '';
    return '${startAt!.day}/${startAt!.month}/${startAt!.year}';
  }

  String get startTimeText {
    if (startAt == null) return '';
    return '${startAt!.hour.toString().padLeft(2, '0')}:${startAt!.minute.toString().padLeft(2, '0')}';
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

  bool _looksLikeCoordinateText(String value) {
    final text = value.trim();
    if (text.isEmpty) return false;
    if (RegExp(r'lat|lng|latitude|longitude', caseSensitive: false)
        .hasMatch(text)) {
      return true;
    }
    return RegExp(r'^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$').hasMatch(text);
  }

  String get locationText {
    final directDisplay = (locationDisplay ?? '').trim();
    if (directDisplay.isNotEmpty && !_looksLikeCoordinateText(directDisplay)) {
      return directDisplay;
    }

    final directDistrict = (district ?? '').trim();
    final directProvince = (province ?? '').trim();
    if (directDistrict.isNotEmpty || directProvince.isNotEmpty) {
      return [directDistrict, directProvince]
          .where((part) => part.isNotEmpty)
          .join(', ');
    }

    final point = (meetingPoint ?? '').trim();
    if (point.isNotEmpty && !_looksLikeCoordinateText(point)) {
      return point;
    }

    return AdminStrings.text('location_not_specified');
  }

  factory _DbEvent.fromJson(Map<String, dynamic> j) {
    DateTime? parseDT(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    double? parseDouble(dynamic v) {
      if (v == null) return null;
      return double.tryParse(v.toString());
    }

    return _DbEvent(
      id: (j["id"] is int) ? j["id"] as int : int.tryParse("${j["id"]}") ?? 0,
      type: j["type"]?.toString(),
      title: j["title"]?.toString(),
      description: j["description"]?.toString(),
      meetingPoint: j["meeting_point"]?.toString(),
      locationDisplay:
          (j["location_display"] ?? j["locationDisplay"])?.toString(),
      district:
          (j["district"] ?? j["amphoe"] ?? j["district_name"])?.toString(),
      city: j["city"]?.toString(),
      province: j["province"]?.toString(),
      locationLat: parseDouble(j["location_lat"] ?? j["latitude"]),
      locationLng: parseDouble(j["location_lng"] ?? j["longitude"]),
      startAt: parseDT(j["start_at"]),
      maxParticipants: (j["max_participants"] is int)
          ? j["max_participants"] as int
          : int.tryParse("${j["max_participants"] ?? ""}"),
      status: j["status"]?.toString(),
      coverUrl:
          (j["cover_url"] ?? j["coverUrl"] ?? j["image_url"] ?? j["image"])
              ?.toString(),
      distancePerLap: parseDouble(j["distance_per_lap"]),
      numberOfLaps: (j["number_of_laps"] is int)
          ? j["number_of_laps"] as int
          : int.tryParse("${j["number_of_laps"] ?? ""}"),
      totalDistance: parseDouble(j["total_distance"]),
      legacyDistance: (j["distance"] ?? j["totalDistanceLegacy"])?.toString(),
    );
  }
}

class _EventTile extends StatelessWidget {
  final _DbEvent event;
  final String? locationLabel;
  final VoidCallback onTap;
  const _EventTile({
    required this.event,
    required this.onTap,
    this.locationLabel,
  });

  String _distanceWithKm(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == '-') return '-';
    return normalized.toUpperCase().contains('KM')
        ? normalized
        : '$normalized KM';
  }

  Widget _chip(String k, String v) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        '$k: $v',
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w800, color: Colors.black87),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = (event.title != null && event.title!.trim().isNotEmpty)
        ? event.title!.trim()
        : (event.description ?? '').trim();

    final cover = (event.coverUrl != null && event.coverUrl!.trim().isNotEmpty)
        ? fixLocalhostForEmulator(event.coverUrl!.trim())
        : null;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 12,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 64,
                  width: 64,
                  color: Colors.grey.shade200,
                  child: cover == null
                      ? const Icon(Icons.event, color: Colors.black54)
                      : Image.network(
                          cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? AdminStrings.text('no_title') : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _chip(
                          AdminStrings.text('location'),
                          (locationLabel ?? '').trim().isNotEmpty
                              ? locationLabel!.trim()
                              : event.locationText,
                        ),
                        if (event.startAt != null)
                          _chip(AdminStrings.text('date'), event.startDateText),
                        if (event.startAt != null)
                          _chip(AdminStrings.text('time'), event.startTimeText),
                        if (event.maxParticipants != null)
                          _chip(
                            AdminStrings.text('limit'),
                            '${event.maxParticipants} ${AdminStrings.text('people_unit')}',
                          ),
                        _chip(AdminStrings.text('lap'),
                            _distanceWithKm(event.distancePerLapText)),
                        _chip(
                            AdminStrings.text('laps'), event.numberOfLapsText),
                        _chip(AdminStrings.text('total'),
                            _distanceWithKm(event.totalDistanceText)),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
