import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';

class AddOrganizerPage extends StatefulWidget {
  const AddOrganizerPage({super.key});

  @override
  State<AddOrganizerPage> createState() => _AddOrganizerPageState();
}

class _AddOrganizerPageState extends State<AddOrganizerPage> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _organizer = TextEditingController(); // ยังไม่ส่งเข้า DB
  final _address = TextEditingController(); // ไม่ใช้กรอกแล้ว
  final _businessProfile =
      TextEditingController(); // ส่งเข้า DB เป็น description
  final _phone = TextEditingController();

  String? _province;
  String? _district;
  String _postcode = '';
  final _postcodeCtrl = TextEditingController();

  final _subdistrict = TextEditingController();
  final _road = TextEditingController();
  final _building = TextEditingController();
  final _floor = TextEditingController();
  final _houseNo = TextEditingController();

  final Map<String, List<String>> _districtsByProvince = const {
    'Bangkok': [
      'Phra Nakhon',
      'Dusit',
      'Nong Chok',
      'Bang Rak',
      'Bang Khen',
      'Bang Kapi',
      'Pathum Wan',
      'Pom Prap Sattru Phai',
      'Phra Khanong',
      'Min Buri',
      'Lat Krabang',
      'Yan Nawa',
      'Samphanthawong',
      'Phaya Thai',
      'Thon Buri',
      'Bangkok Yai',
      'Huai Khwang',
      'Khlong San',
      'Taling Chan',
      'Bangkok Noi',
      'Bang Khun Thian',
      'Phasi Charoen',
      'Nong Khaem',
      'Rat Burana',
      'Bang Phlat',
      'Din Daeng',
      'Bueng Kum',
      'Sathon',
      'Bang Sue',
      'Chatuchak',
      'Bang Kho Laem',
      'Prawet',
      'Khlong Toei',
      'Suan Luang',
      'Chom Thong',
      'Don Mueang',
      'Ratchathewi',
      'Lat Phrao',
      'Watthana',
      'Bang Khae',
      'Lak Si',
      'Sai Mai',
      'Khan Na Yao',
      'Saphan Sung',
      'Wang Thonglang',
      'Khlong Sam Wa',
      'Bang Na',
      'Thawi Watthana',
      'Thung Khru',
      'Bang Bon',
    ],
    'Nakhon Pathom': [
      'Mueang Nakhon Pathom',
      'Kamphaeng Saen',
      'Nakhon Chai Si',
      'Don Tum',
      'Bang Len',
      'Sam Phran',
      'Phutthamonthon',
    ],
  };

  final Map<String, String> _postcodeByDistrict = const {
    'Phra Nakhon': '10200',
    'Dusit': '10300',
    'Nong Chok': '10530',
    'Bang Rak': '10500',
    'Bang Khen': '10220',
    'Bang Kapi': '10240',
    'Pathum Wan': '10330',
    'Pom Prap Sattru Phai': '10100',
    'Phra Khanong': '10260',
    'Min Buri': '10510',
    'Lat Krabang': '10520',
    'Yan Nawa': '10120',
    'Samphanthawong': '10100',
    'Phaya Thai': '10400',
    'Thon Buri': '10600',
    'Bangkok Yai': '10600',
    'Huai Khwang': '10310',
    'Khlong San': '10600',
    'Taling Chan': '10170',
    'Bangkok Noi': '10700',
    'Bang Khun Thian': '10150',
    'Phasi Charoen': '10160',
    'Nong Khaem': '10160',
    'Rat Burana': '10140',
    'Bang Phlat': '10700',
    'Din Daeng': '10400',
    'Bueng Kum': '10230',
    'Sathon': '10120',
    'Bang Sue': '10800',
    'Chatuchak': '10900',
    'Bang Kho Laem': '10120',
    'Prawet': '10250',
    'Khlong Toei': '10110',
    'Suan Luang': '10250',
    'Chom Thong': '10150',
    'Don Mueang': '10210',
    'Ratchathewi': '10400',
    'Lat Phrao': '10230',
    'Watthana': '10110',
    'Bang Khae': '10160',
    'Lak Si': '10210',
    'Sai Mai': '10220',
    'Khan Na Yao': '10230',
    'Saphan Sung': '10240',
    'Wang Thonglang': '10310',
    'Khlong Sam Wa': '10510',
    'Bang Na': '10260',
    'Thawi Watthana': '10170',
    'Thung Khru': '10140',
    'Bang Bon': '10150',
    'Mueang Nakhon Pathom': '73000',
    'Kamphaeng Saen': '73140',
    'Nakhon Chai Si': '73120',
    'Don Tum': '73150',
    'Bang Len': '73130',
    'Sam Phran': '73110',
    'Phutthamonthon': '73170',
  };

  String? _pickedImagePath;
  Uint8List? _pickedImageBytes;
  String? _pickedImageName;

  bool _saving = false;
  String? _error;

  String get _baseUrl => ConfigService.getBaseUrl();

  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
  }

  @override
  void dispose() {
    AdminLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _name.dispose();
    _email.dispose();
    _organizer.dispose();
    _address.dispose();
    _businessProfile.dispose();
    _phone.dispose();

    _postcodeCtrl.dispose();
    _subdistrict.dispose();
    _road.dispose();
    _building.dispose();
    _floor.dispose();
    _houseNo.dispose();

    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _t(String key, {Map<String, String> params = const {}}) {
    return AdminStrings.text(key, params: params);
  }

  Map<String, String> _buildI18nMap(String value) {
    final trimmed = value.trim();
    return <String, String>{
      'th': trimmed,
      'en': trimmed,
      'zh': trimmed,
    };
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    setState(() {
      _pickedImagePath = file.path;
      _pickedImageBytes = bytes;
      _pickedImageName = file.name;
    });
  }

  Future<String?> _uploadOrgImage() async {
    final path = _pickedImagePath;
    final bytes = _pickedImageBytes;
    if ((path == null || path.isEmpty) && (bytes == null || bytes.isEmpty)) {
      return null;
    }

    final uri = Uri.parse("$_baseUrl/api/upload/org-image");
    final req = http.MultipartRequest("POST", uri);
    final adminId = await AdminSessionService.getCurrentAdminId();
    if (adminId != null && adminId > 0) {
      req.headers["x-admin-id"] = adminId.toString();
    }
    if (bytes != null && bytes.isNotEmpty) {
      req.files.add(http.MultipartFile.fromBytes(
        "file",
        bytes,
        filename: (_pickedImageName == null || _pickedImageName!.trim().isEmpty)
            ? "org_image_${DateTime.now().millisecondsSinceEpoch}.jpg"
            : _pickedImageName!.trim(),
      ));
    } else if (path != null && path.isNotEmpty) {
      req.files.add(await http.MultipartFile.fromPath("file", path));
    }

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode != 201) {
      throw "Upload image failed (${res.statusCode}): ${res.body}";
    }

    final j = jsonDecode(res.body);
    final url = (j is Map ? j["image_url"] : null)?.toString().trim();
    return (url == null || url.isEmpty) ? null : url;
  }

  String _buildAddressString() {
    final parts = <String>[];

    final no = _houseNo.text.trim();
    final floor = _floor.text.trim();
    final building = _building.text.trim();
    final road = _road.text.trim();
    final subd = _subdistrict.text.trim();

    if (no.isNotEmpty) parts.add('No. $no');
    if (floor.isNotEmpty) parts.add('Floor $floor');
    if (building.isNotEmpty) parts.add('Building $building');
    if (road.isNotEmpty) parts.add('Road $road');
    if (subd.isNotEmpty) parts.add('Subdistrict $subd');

    if ((_district ?? '').trim().isNotEmpty)
      parts.add('District ${_district!.trim()}');
    if ((_province ?? '').trim().isNotEmpty)
      parts.add('Province ${_province!.trim()}');
    if (_postcode.trim().isNotEmpty) parts.add('Postcode ${_postcode.trim()}');

    return parts.join(', ');
  }

  Future<void> _saveToDb() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final adminId = await AdminSessionService.getCurrentAdminId();
      final imageUrl = await _uploadOrgImage();
      final uri = Uri.parse("$_baseUrl/api/organizations");

      final payload = <String, dynamic>{
        "name": _name.text.trim(),
        "email": _email.text.trim(),
        "phone": _phone.text.trim(),
        "address": _buildAddressString(),
        "description": _businessProfile.text.trim(),
        "image_url": imageUrl,
        "name_i18n": _buildI18nMap(_name.text),
        "description_i18n": _buildI18nMap(_businessProfile.text),
        "address_i18n": _buildI18nMap(_buildAddressString()),
      };

      final res = await http.post(
        uri,
        headers: {
          "Content-Type": "application/json",
          if (adminId != null && adminId > 0) "x-admin-id": adminId.toString(),
        },
        body: jsonEncode(payload),
      );

      if (res.statusCode == 201) {
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      String msg = "Create failed (${res.statusCode})";
      try {
        final j = jsonDecode(res.body);
        if (j is Map && j["message"] is String) msg = j["message"];
      } catch (_) {}
      if (mounted) setState(() => _error = msg);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = _t(
            'network_server_error',
            params: <String, String>{'error': '$e'},
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // =========================
  // UI Helpers (ใหม่)
  // =========================
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

  Widget _sectionTitle(String title, {String? subtitle, IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: Colors.black87),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w800)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12.5, color: Colors.black54)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: child,
    );
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? _t('required') : null;

  String? _emailVal(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return _t('required');
    // simple email check
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s))
      return _t('invalid_email');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final preview = (_pickedImageBytes != null && _pickedImageBytes!.isNotEmpty)
        ? Image.memory(_pickedImageBytes!, fit: BoxFit.cover)
        : Image.asset('assets/images/big_event/add_picture.png',
            fit: BoxFit.cover);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        title: Text(_t('create_organization_detail')),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                              style: const TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // =========================
                // Company Image
                // =========================
                _sectionTitle(
                  _t('company_image'),
                  subtitle: _t('upload_logo_cover'),
                  icon: Icons.image_outlined,
                ),
                _card(
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(height: 76, width: 76, child: preview),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _pickImage,
                          icon: const Icon(Icons.upload),
                          label: Text(_t('upload_company_image')),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                vertical: 14, horizontal: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            side: const BorderSide(color: Colors.black12),
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // =========================
                // Organization Info
                // =========================
                _sectionTitle(_t('organization_info'), icon: Icons.apartment),
                _card(
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _name,
                        decoration: _dec(_t('organization_name')),
                        validator: _req,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _email,
                        decoration: _dec(_t('email')),
                        keyboardType: TextInputType.emailAddress,
                        validator: _emailVal,
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _organizer,
                        decoration: _dec(
                          _t('organizer_optional'),
                          hint: _t('person_in_charge_optional'),
                        ),
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phone,
                        decoration: _dec(_t('phone_number')),
                        keyboardType: TextInputType.phone,
                        validator: _req,
                        textInputAction: TextInputAction.next,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // =========================
                // Address
                // =========================
                _sectionTitle(
                  _t('organization_address'),
                  icon: Icons.location_on_outlined,
                ),
                _card(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              value: _province,
                              decoration: _dec(_t('province')),
                              items: const [
                                DropdownMenuItem(
                                    value: 'Bangkok', child: Text('Bangkok')),
                                DropdownMenuItem(
                                    value: 'Nakhon Pathom',
                                    child: Text('Nakhon Pathom')),
                              ],
                              onChanged: (v) {
                                setState(() {
                                  _province = v;
                                  _district = null;
                                  _postcode = '';
                                  _postcodeCtrl.text = _postcode;
                                });
                              },
                              validator: _req,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _postcodeCtrl,
                              readOnly: true,
                              decoration: _dec(_t('postcode')),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: DropdownButtonFormField<String>(
                              value: _district,
                              decoration: _dec(_t('district')),
                              items: (_province == null)
                                  ? const []
                                  : (_districtsByProvince[_province] ??
                                          const [])
                                      .map((d) => DropdownMenuItem(
                                          value: d, child: Text(d)))
                                      .toList(),
                              onChanged: (_province == null)
                                  ? null
                                  : (v) => setState(() {
                                        _district = v;
                                        _postcode =
                                            _postcodeByDistrict[v ?? ''] ?? '';
                                        _postcodeCtrl.text = _postcode;
                                      }),
                              validator: _req,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _subdistrict,
                              decoration: _dec(_t('subdistrict')),
                              validator: _req,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _road,
                              decoration: _dec(_t('road')),
                              validator: _req,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _building,
                              decoration: _dec(_t('building')),
                              validator: _req,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _floor,
                              decoration: _dec(_t('floor')),
                              validator: _req,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _houseNo,
                              decoration: _dec(_t('house_no')),
                              validator: _req,
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // =========================
                // Business Profile
                // =========================
                _sectionTitle(
                  _t('business_profile'),
                  subtitle: _t('business_profile_subtitle'),
                  icon: Icons.description_outlined,
                ),
                _card(
                  child: TextFormField(
                    controller: _businessProfile,
                    maxLines: 5,
                    decoration: _dec(
                      _t('business_profile'),
                      hint: _t('describe_business'),
                    ),
                    validator: _req,
                  ),
                ),

                const SizedBox(height: 18),

                // =========================
                // Create button
                // =========================
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveToDb,
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _t('create'),
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                  ),
                ),

                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
