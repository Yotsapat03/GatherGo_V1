import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../app_routes.dart';
import '../localization/user_locale_controller.dart';
import 'thai_address_data.dart';

class SignupStep1Page extends StatefulWidget {
  const SignupStep1Page({super.key});

  @override
  State<SignupStep1Page> createState() => _SignupStep1PageState();
}

class _SignupStep1PageState extends State<SignupStep1Page> {
  static const List<String> _genderOptions = ["Male", "Female", "Other"];
  static const List<String> _occupationOptions = [
    "Student",
    "Office Worker",
    "Freelancer",
    "Business Owner",
    "Government Officer",
    "Doctor/Nurse",
    "Teacher/Lecturer",
    "Engineer",
    "Designer/Creative",
    "Service Staff",
    "Other - Please specify",
  ];
  static const Map<String, Map<String, String>> _texts =
      <String, Map<String, String>>{
    'en': <String, String>{
      'signup': 'Sign Up',
      'upload': 'Upload',
      'change': 'Change',
      'profile_image': 'Profile Image*',
      'name': 'Name*',
      'name_hint': 'Enter your name',
      'birth_year': 'Birth Year (CE)*',
      'birth_year_hint': 'e.g. 1998',
      'gender': 'Gender*',
      'gender_hint': 'Select gender',
      'occupation': 'Occupation*',
      'occupation_hint': 'Select occupation',
      'occupation_other': 'Specify Occupation*',
      'occupation_other_hint': 'Enter occupation',
      'email': 'Email*',
      'email_hint': 'Enter your email',
      'phone': 'Phone Number*',
      'phone_hint': 'Enter phone number',
      'address': 'Address*',
      'address_details': 'Address Details',
      'house_no': 'House No.',
      'floor': 'Floor',
      'building': 'Building',
      'road': 'Road',
      'subdistrict': 'Subdistrict',
      'province_hint': 'Select province',
      'district_hint': 'Select district',
      'postal_code': 'Postal Code',
      'national_id': 'National ID Card*',
      'no_file': 'No file selected',
      'submit': 'Submit',
      'select_language': 'Select language',
      'required_error': 'Please complete all required fields.',
      'email_error': 'Please enter a valid email.',
      'birth_year_error': 'Please enter a valid birth year in CE format.',
      'occupation_error': 'Please specify your occupation.',
    },
    'th': <String, String>{
      'signup': 'สมัครสมาชิก',
      'upload': 'อัปโหลด',
      'change': 'เปลี่ยน',
      'profile_image': 'รูปโปรไฟล์*',
      'name': 'ชื่อ*',
      'name_hint': 'กรอกชื่อของคุณ',
      'birth_year': 'ปีเกิด (ค.ศ.)*',
      'birth_year_hint': 'เช่น 1998',
      'gender': 'เพศ*',
      'gender_hint': 'เลือกเพศ',
      'occupation': 'อาชีพ*',
      'occupation_hint': 'เลือกอาชีพ',
      'occupation_other': 'ระบุอาชีพ*',
      'occupation_other_hint': 'กรอกอาชีพ',
      'email': 'อีเมล*',
      'email_hint': 'กรอกอีเมลของคุณ',
      'phone': 'หมายเลขโทรศัพท์*',
      'phone_hint': 'กรอกหมายเลขโทรศัพท์',
      'address': 'ที่อยู่*',
      'address_details': 'รายละเอียดที่อยู่',
      'house_no': 'บ้านเลขที่',
      'floor': 'ชั้น',
      'building': 'อาคาร',
      'road': 'ถนน',
      'subdistrict': 'ตำบล',
      'province_hint': 'เลือกจังหวัด',
      'district_hint': 'เลือกอำเภอ',
      'postal_code': 'รหัสไปรษณีย์',
      'national_id': 'บัตรประชาชน*',
      'no_file': 'ยังไม่ได้เลือกรูป',
      'submit': 'ถัดไป',
      'select_language': 'เลือกภาษา',
      'required_error': 'กรุณากรอกข้อมูลที่จำเป็นให้ครบถ้วน',
      'email_error': 'กรุณากรอกอีเมลให้ถูกต้อง',
      'birth_year_error': 'กรุณากรอกปีเกิด (ค.ศ.) ให้ถูกต้อง',
      'occupation_error': 'กรุณาระบุอาชีพ',
    },
    'zh': <String, String>{
      'signup': '注册',
      'upload': '上传',
      'change': '更换',
      'profile_image': '头像*',
      'name': '姓名*',
      'name_hint': '请输入您的姓名',
      'birth_year': '出生年份（公历）*',
      'birth_year_hint': '例如 1998',
      'gender': '性别*',
      'gender_hint': '请选择性别',
      'occupation': '职业*',
      'occupation_hint': '请选择职业',
      'occupation_other': '填写职业*',
      'occupation_other_hint': '请输入职业',
      'email': '电子邮箱*',
      'email_hint': '请输入您的邮箱',
      'phone': '电话号码*',
      'phone_hint': '请输入电话号码',
      'address': '地址*',
      'address_details': '地址详情',
      'house_no': '门牌号',
      'floor': '楼层',
      'building': '楼宇',
      'road': '道路',
      'subdistrict': '分区',
      'province_hint': '请选择省份',
      'district_hint': '请选择地区',
      'postal_code': '邮政编码',
      'national_id': '身份证*',
      'no_file': '未选择文件',
      'submit': '下一步',
      'select_language': '选择语言',
      'required_error': '请完整填写所有必填信息。',
      'email_error': '请输入有效的电子邮箱。',
      'birth_year_error': '请输入有效的公历出生年份。',
      'occupation_error': '请填写您的职业。',
    },
  };
  static const Map<String, Map<String, String>> _genderLabels =
      <String, Map<String, String>>{
    'Male': {'en': 'Male', 'th': 'ชาย', 'zh': '男'},
    'Female': {'en': 'Female', 'th': 'หญิง', 'zh': '女'},
    'Other': {'en': 'Other', 'th': 'อื่น ๆ', 'zh': '其他'},
  };
  static const Map<String, Map<String, String>> _occupationLabels =
      <String, Map<String, String>>{
    'Student': {'en': 'Student', 'th': 'นักเรียน/นักศึกษา', 'zh': '学生'},
    'Office Worker': {
      'en': 'Office Worker',
      'th': 'พนักงานออฟฟิศ',
      'zh': '上班族'
    },
    'Freelancer': {'en': 'Freelancer', 'th': 'ฟรีแลนซ์', 'zh': '自由职业者'},
    'Business Owner': {
      'en': 'Business Owner',
      'th': 'เจ้าของธุรกิจ',
      'zh': '企业主'
    },
    'Government Officer': {
      'en': 'Government Officer',
      'th': 'ข้าราชการ',
      'zh': '公务员'
    },
    'Doctor/Nurse': {'en': 'Doctor/Nurse', 'th': 'แพทย์/พยาบาล', 'zh': '医生/护士'},
    'Teacher/Lecturer': {
      'en': 'Teacher/Lecturer',
      'th': 'ครู/อาจารย์',
      'zh': '教师/讲师'
    },
    'Engineer': {'en': 'Engineer', 'th': 'วิศวกร', 'zh': '工程师'},
    'Designer/Creative': {
      'en': 'Designer/Creative',
      'th': 'นักออกแบบ/ครีเอทีฟ',
      'zh': '设计/创意工作者'
    },
    'Service Staff': {
      'en': 'Service Staff',
      'th': 'พนักงานบริการ',
      'zh': '服务人员'
    },
    'Other - Please specify': {
      'en': 'Other - Please specify',
      'th': 'อื่น ๆ - โปรดระบุ',
      'zh': '其他 - 请填写'
    },
  };

  final _name = TextEditingController();
  final _birthYear = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _houseNo = TextEditingController();
  final _floor = TextEditingController();
  final _building = TextEditingController();
  final _road = TextEditingController();
  final _subdistrict = TextEditingController();
  final _postalCode = TextEditingController();
  final _occupationOther = TextEditingController();

  final _picker = ImagePicker();
  Uint8List? _profileBytes;
  String? _profileName;
  Uint8List? _nationalIdBytes;
  String? _nationalIdName;

  bool _submitting = false;
  String? _error;
  String? _selectedGender;
  String? _selectedOccupation;
  String? _selectedProvince = thaiSignupProvinces.first.name;
  String? _selectedDistrict;

  String get _languageCode => UserLocaleController.languageCode.value;

  @override
  void initState() {
    super.initState();
    UserLocaleController.languageCode.addListener(_handleLanguageChanged);
    _syncPostalCode();
  }

  @override
  void dispose() {
    UserLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _name.dispose();
    _birthYear.dispose();
    _email.dispose();
    _phone.dispose();
    _houseNo.dispose();
    _floor.dispose();
    _building.dispose();
    _road.dispose();
    _subdistrict.dispose();
    _postalCode.dispose();
    _occupationOther.dispose();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _t(String key) {
    final lang = _texts[_languageCode] ?? _texts['en']!;
    return lang[key] ?? _texts['en']![key] ?? key;
  }

  String _genderLabel(String value) =>
      _genderLabels[value]?[_languageCode] ??
      _genderLabels[value]?['en'] ??
      value;

  String _occupationLabel(String value) =>
      _occupationLabels[value]?[_languageCode] ??
      _occupationLabels[value]?['en'] ??
      value;

  String? _genderValueFromLabel(String? label) {
    if (label == null) return null;
    for (final value in _genderOptions) {
      if (_genderLabel(value) == label) return value;
    }
    return null;
  }

  String? _occupationValueFromLabel(String? label) {
    if (label == null) return null;
    for (final value in _occupationOptions) {
      if (_occupationLabel(value) == label) return value;
    }
    return null;
  }

  Map<String, String> _localizedTripletFromRaw(String rawValue) {
    final value = rawValue.trim();
    return <String, String>{'th': value, 'en': value, 'zh': value};
  }

  Map<String, String> _genderTriplet(String value) => <String, String>{
        'th': _genderLabels[value]?['th'] ?? value,
        'en': _genderLabels[value]?['en'] ?? value,
        'zh': _genderLabels[value]?['zh'] ?? value,
      };

  Map<String, String> _occupationTriplet(String value, {String? customValue}) {
    if (value == "Other - Please specify") {
      return _localizedTripletFromRaw(customValue ?? "");
    }
    return <String, String>{
      'th': _occupationLabels[value]?['th'] ?? value,
      'en': _occupationLabels[value]?['en'] ?? value,
      'zh': _occupationLabels[value]?['zh'] ?? value,
    };
  }

  Future<void> _pickProfileImage() async {
    final XFile? x =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _profileBytes = bytes;
      _profileName = x.name;
    });
  }

  Future<void> _pickNationalIdImage() async {
    final XFile? x =
        await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    if (!mounted) return;
    setState(() {
      _nationalIdBytes = bytes;
      _nationalIdName = x.name;
    });
  }

  bool _isValidEmail(String s) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
  }

  bool _isValidBirthYear(String s) {
    if (!RegExp(r'^\d{4}$').hasMatch(s)) return false;
    final year = int.tryParse(s);
    final currentYear = DateTime.now().year;
    return year != null && year >= 1900 && year <= currentYear;
  }

  ThaiProvinceOption get _currentProvinceOption {
    return thaiSignupProvinces.firstWhere(
      (province) => province.name == _selectedProvince,
      orElse: () => thaiSignupProvinces.first,
    );
  }

  void _syncPostalCode() {
    final district = _selectedDistrict;
    if (district == null || district.isEmpty) {
      _postalCode.clear();
      return;
    }

    String postalCode = "";
    for (final item in _currentProvinceOption.districts) {
      if (item.name == district) {
        postalCode = item.postalCode;
        break;
      }
    }
    _postalCode.text = postalCode;
  }

  String _buildFullAddress([String languageCode = 'en']) {
    final labels = <String, Map<String, String>>{
      'house_no': {'en': 'House No.', 'th': 'บ้านเลขที่', 'zh': '门牌号'},
      'floor': {'en': 'Floor', 'th': 'ชั้น', 'zh': '楼层'},
      'building': {'en': 'Building', 'th': 'อาคาร', 'zh': '楼宇'},
      'road': {'en': 'Road', 'th': 'ถนน', 'zh': '道路'},
      'subdistrict': {'en': 'Subdistrict', 'th': 'ตำบล', 'zh': '分区'},
      'district': {'en': 'District', 'th': 'อำเภอ', 'zh': '地区'},
      'province': {'en': 'Province', 'th': 'จังหวัด', 'zh': '省份'},
      'postal_code': {'en': 'Postal Code', 'th': 'รหัสไปรษณีย์', 'zh': '邮政编码'},
    };
    String label(String key) =>
        labels[key]?[languageCode] ?? labels[key]!['en']!;
    return [
      '${label('house_no')} ${_houseNo.text.trim()}',
      '${label('floor')} ${_floor.text.trim()}',
      '${label('building')} ${_building.text.trim()}',
      '${label('road')} ${_road.text.trim()}',
      '${label('subdistrict')} ${_subdistrict.text.trim()}',
      '${label('district')} ${(_selectedDistrict ?? "").trim()}',
      '${label('province')} ${(_selectedProvince ?? "").trim()}',
      '${label('postal_code')} ${_postalCode.text.trim()}',
    ].join(', ');
  }

  void _submitStep1() {
    final name = _name.text.trim();
    final birthYear = _birthYear.text.trim();
    final email = _email.text.trim().toLowerCase();
    final phone = _phone.text.trim();
    final houseNo = _houseNo.text.trim();
    final floor = _floor.text.trim();
    final building = _building.text.trim();
    final road = _road.text.trim();
    final subdistrict = _subdistrict.text.trim();
    final district = (_selectedDistrict ?? "").trim();
    final province = (_selectedProvince ?? "").trim();
    final postalCode = _postalCode.text.trim();
    final address = _buildFullAddress('en');
    final gender = (_selectedGender ?? "").trim();
    final occupationSelection = (_selectedOccupation ?? "").trim();
    final occupationOther = _occupationOther.text.trim();
    final occupation = occupationSelection == "Other - Please specify"
        ? occupationOther
        : occupationSelection;
    final nameI18n = _localizedTripletFromRaw(name);
    final genderI18n = _genderTriplet(gender);
    final occupationI18n = _occupationTriplet(
      occupationSelection,
      customValue: occupationOther,
    );
    final addressI18n = <String, String>{
      'th': _buildFullAddress('th'),
      'en': _buildFullAddress('en'),
      'zh': _buildFullAddress('zh'),
    };

    if (name.isEmpty ||
        birthYear.isEmpty ||
        gender.isEmpty ||
        occupationSelection.isEmpty ||
        email.isEmpty ||
        phone.isEmpty ||
        houseNo.isEmpty ||
        floor.isEmpty ||
        building.isEmpty ||
        road.isEmpty ||
        subdistrict.isEmpty ||
        district.isEmpty ||
        province.isEmpty ||
        postalCode.isEmpty ||
        _profileBytes == null ||
        _nationalIdBytes == null) {
      setState(() => _error = _t('required_error'));
      return;
    }

    if (!_isValidEmail(email)) {
      setState(() => _error = _t('email_error'));
      return;
    }

    if (!_isValidBirthYear(birthYear)) {
      setState(() => _error = _t('birth_year_error'));
      return;
    }

    if (occupationSelection == "Other - Please specify" &&
        occupationOther.isEmpty) {
      setState(() => _error = _t('occupation_error'));
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    Navigator.pushNamed(
      context,
      AppRoutes.userSignupStep2,
      arguments: {
        "name": name,
        "nameI18n": nameI18n,
        "birthYear": birthYear,
        "gender": gender,
        "genderI18n": genderI18n,
        "occupation": occupation,
        "occupationI18n": occupationI18n,
        "email": email,
        "phone": phone,
        "address": address,
        "addressI18n": addressI18n,
        "addressHouseNo": houseNo,
        "addressFloor": floor,
        "addressBuilding": building,
        "addressRoad": road,
        "addressSubdistrict": subdistrict,
        "addressDistrict": district,
        "addressProvince": province,
        "addressPostalCode": postalCode,
        "profileImageBytes": _profileBytes,
        "profileImageName": _profileName ?? "profile.jpg",
        "nationalIdImageBytes": _nationalIdBytes,
        "nationalIdImageName": _nationalIdName ?? "national_id.jpg",
      },
    ).then((_) {
      if (!mounted) return;
      setState(() => _submitting = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final genderItems = _genderOptions.map(_genderLabel).toList();
    final occupationItems = _occupationOptions.map(_occupationLabel).toList();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/welcome.png',
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
          Container(color: Colors.black.withOpacity(0.25)),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(w * 0.08, 24, w * 0.08, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        tooltip: _t('select_language'),
                        icon: const Icon(
                          Icons.translate_rounded,
                          color: Colors.white,
                        ),
                        onSelected: UserLocaleController.setLanguage,
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'en', child: Text('English')),
                          PopupMenuItem(value: 'zh', child: Text('中文')),
                          PopupMenuItem(value: 'th', child: Text('ไทย')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _t('signup'),
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: w * 0.11,
                      fontWeight: FontWeight.w800,
                      shadows: const [
                        Shadow(blurRadius: 12, color: Colors.black54),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 72, 18, 18),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(18),
                          border:
                              Border.all(color: Colors.white.withOpacity(0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.center,
                              child: OutlinedButton(
                                onPressed: _pickProfileImage,
                                child: Text(
                                  _profileBytes == null
                                      ? _t('upload')
                                      : _t('change'),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Align(
                              alignment: Alignment.center,
                              child: Text(
                                _profileName ?? _t('profile_image'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _t('name'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            _Field(controller: _name, hint: _t('name_hint')),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _t('birth_year'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _Field(
                                        controller: _birthYear,
                                        hint: _t('birth_year_hint'),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _t('gender'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      _DropdownField(
                                        value: _selectedGender == null
                                            ? null
                                            : _genderLabel(_selectedGender!),
                                        hint: _t('gender_hint'),
                                        items: genderItems,
                                        onChanged: (value) {
                                          setState(() {
                                            _selectedGender =
                                                _genderValueFromLabel(value);
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _t('occupation'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            _DropdownField(
                              value: _selectedOccupation == null
                                  ? null
                                  : _occupationLabel(_selectedOccupation!),
                              hint: _t('occupation_hint'),
                              items: occupationItems,
                              onChanged: (value) {
                                setState(() {
                                  _selectedOccupation =
                                      _occupationValueFromLabel(value);
                                  if (_selectedOccupation !=
                                      "Other - Please specify") {
                                    _occupationOther.clear();
                                  }
                                });
                              },
                            ),
                            if (_selectedOccupation ==
                                "Other - Please specify") ...[
                              const SizedBox(height: 12),
                              Text(
                                _t('occupation_other'),
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 8),
                              _Field(
                                controller: _occupationOther,
                                hint: _t('occupation_other_hint'),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              _t('email'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            _Field(
                              controller: _email,
                              hint: _t('email_hint'),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _t('phone'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            _Field(
                              controller: _phone,
                              hint: _t('phone_hint'),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _t('address'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.28),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.55),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _t('address_details'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  _Field(
                                    controller: _houseNo,
                                    hint: _t('house_no'),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _Field(
                                          controller: _floor,
                                          hint: _t('floor'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _Field(
                                          controller: _building,
                                          hint: _t('building'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  _Field(
                                    controller: _road,
                                    hint: _t('road'),
                                  ),
                                  const SizedBox(height: 10),
                                  _Field(
                                    controller: _subdistrict,
                                    hint: _t('subdistrict'),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: _DropdownField(
                                          value: _selectedProvince,
                                          hint: _t('province_hint'),
                                          items: thaiSignupProvinces
                                              .map((item) => item.name)
                                              .toList(),
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedProvince = value;
                                              _selectedDistrict = null;
                                              _syncPostalCode();
                                            });
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _DropdownField(
                                          value: _selectedDistrict,
                                          hint: _t('district_hint'),
                                          items: _currentProvinceOption
                                              .districts
                                              .map((item) => item.name)
                                              .toList(),
                                          onChanged: (value) {
                                            setState(() {
                                              _selectedDistrict = value;
                                              _syncPostalCode();
                                            });
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  _Field(
                                    controller: _postalCode,
                                    hint: _t('postal_code'),
                                    keyboardType: TextInputType.number,
                                    readOnly: true,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _t('national_id'),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: Colors.white70,
                                    borderRadius: BorderRadius.circular(8),
                                    image: _nationalIdBytes == null
                                        ? null
                                        : DecorationImage(
                                            image:
                                                MemoryImage(_nationalIdBytes!),
                                            fit: BoxFit.cover,
                                          ),
                                  ),
                                  child: _nationalIdBytes == null
                                      ? const Icon(Icons.badge_outlined)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    _nationalIdName ?? _t('no_file'),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: _pickNationalIdImage,
                                  child: Text(_t('upload')),
                                ),
                              ],
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor:
                                      Colors.black.withOpacity(0.85),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                ),
                                onPressed: _submitting ? null : _submitStep1,
                                child: _submitting
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        _t('submit'),
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        top: -32,
                        child: Center(
                          child: Container(
                            width: 86,
                            height: 86,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 3),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x33000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 4),
                                ),
                              ],
                              image: _profileBytes == null
                                  ? null
                                  : DecorationImage(
                                      image: MemoryImage(_profileBytes!),
                                      fit: BoxFit.cover,
                                    ),
                            ),
                            child: _profileBytes == null
                                ? const Icon(
                                    Icons.person,
                                    size: 40,
                                    color: Colors.black54,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final bool readOnly;

  const _Field({
    required this.controller,
    required this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white.withOpacity(0.85),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String? value;
  final String hint;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  const _DropdownField({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: value,
      onChanged: onChanged,
      isExpanded: true,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white.withOpacity(0.85),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
    );
  }
}
