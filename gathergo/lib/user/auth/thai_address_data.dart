class ThaiDistrictOption {
  final String name;
  final String postalCode;

  const ThaiDistrictOption({
    required this.name,
    required this.postalCode,
  });
}

class ThaiProvinceOption {
  final String name;
  final List<ThaiDistrictOption> districts;

  const ThaiProvinceOption({
    required this.name,
    required this.districts,
  });
}

const List<ThaiProvinceOption> thaiSignupProvinces = [
  ThaiProvinceOption(
    name: 'Bangkok',
    districts: [
      ThaiDistrictOption(name: 'Phra Nakhon', postalCode: '10200'),
      ThaiDistrictOption(name: 'Dusit', postalCode: '10300'),
      ThaiDistrictOption(name: 'Nong Chok', postalCode: '10530'),
      ThaiDistrictOption(name: 'Bang Rak', postalCode: '10500'),
      ThaiDistrictOption(name: 'Bang Khen', postalCode: '10220'),
      ThaiDistrictOption(name: 'Bang Kapi', postalCode: '10240'),
      ThaiDistrictOption(name: 'Pathum Wan', postalCode: '10330'),
      ThaiDistrictOption(name: 'Pom Prap Sattru Phai', postalCode: '10100'),
      ThaiDistrictOption(name: 'Phra Khanong', postalCode: '10260'),
      ThaiDistrictOption(name: 'Min Buri', postalCode: '10510'),
      ThaiDistrictOption(name: 'Lat Krabang', postalCode: '10520'),
      ThaiDistrictOption(name: 'Yan Nawa', postalCode: '10120'),
      ThaiDistrictOption(name: 'Samphanthawong', postalCode: '10100'),
      ThaiDistrictOption(name: 'Phaya Thai', postalCode: '10400'),
      ThaiDistrictOption(name: 'Thon Buri', postalCode: '10600'),
      ThaiDistrictOption(name: 'Bangkok Yai', postalCode: '10600'),
      ThaiDistrictOption(name: 'Huai Khwang', postalCode: '10310'),
      ThaiDistrictOption(name: 'Khlong San', postalCode: '10600'),
      ThaiDistrictOption(name: 'Taling Chan', postalCode: '10170'),
      ThaiDistrictOption(name: 'Bangkok Noi', postalCode: '10700'),
      ThaiDistrictOption(name: 'Bang Khun Thian', postalCode: '10150'),
      ThaiDistrictOption(name: 'Phasi Charoen', postalCode: '10160'),
      ThaiDistrictOption(name: 'Nong Khaem', postalCode: '10160'),
      ThaiDistrictOption(name: 'Rat Burana', postalCode: '10140'),
      ThaiDistrictOption(name: 'Bang Phlat', postalCode: '10700'),
      ThaiDistrictOption(name: 'Din Daeng', postalCode: '10400'),
      ThaiDistrictOption(name: 'Bueng Kum', postalCode: '10230'),
      ThaiDistrictOption(name: 'Sathon', postalCode: '10120'),
      ThaiDistrictOption(name: 'Bang Sue', postalCode: '10800'),
      ThaiDistrictOption(name: 'Chatuchak', postalCode: '10900'),
      ThaiDistrictOption(name: 'Bang Kho Laem', postalCode: '10120'),
      ThaiDistrictOption(name: 'Prawet', postalCode: '10250'),
      ThaiDistrictOption(name: 'Khlong Toei', postalCode: '10110'),
      ThaiDistrictOption(name: 'Suan Luang', postalCode: '10250'),
      ThaiDistrictOption(name: 'Chom Thong', postalCode: '10150'),
      ThaiDistrictOption(name: 'Don Mueang', postalCode: '10210'),
      ThaiDistrictOption(name: 'Ratchathewi', postalCode: '10400'),
      ThaiDistrictOption(name: 'Lat Phrao', postalCode: '10230'),
      ThaiDistrictOption(name: 'Watthana', postalCode: '10110'),
      ThaiDistrictOption(name: 'Bang Khae', postalCode: '10160'),
      ThaiDistrictOption(name: 'Lak Si', postalCode: '10210'),
      ThaiDistrictOption(name: 'Sai Mai', postalCode: '10220'),
      ThaiDistrictOption(name: 'Khan Na Yao', postalCode: '10230'),
      ThaiDistrictOption(name: 'Saphan Sung', postalCode: '10240'),
      ThaiDistrictOption(name: 'Wang Thonglang', postalCode: '10310'),
      ThaiDistrictOption(name: 'Khlong Sam Wa', postalCode: '10510'),
      ThaiDistrictOption(name: 'Bang Na', postalCode: '10260'),
      ThaiDistrictOption(name: 'Thawi Watthana', postalCode: '10170'),
      ThaiDistrictOption(name: 'Thung Khru', postalCode: '10140'),
      ThaiDistrictOption(name: 'Bang Bon', postalCode: '10150'),
    ],
  ),
  ThaiProvinceOption(
    name: 'Nakhon Pathom',
    districts: [
      ThaiDistrictOption(name: 'Mueang Nakhon Pathom', postalCode: '73000'),
      ThaiDistrictOption(name: 'Kamphaeng Saen', postalCode: '73140'),
      ThaiDistrictOption(name: 'Nakhon Chai Si', postalCode: '73120'),
      ThaiDistrictOption(name: 'Don Tum', postalCode: '73150'),
      ThaiDistrictOption(name: 'Bang Len', postalCode: '73130'),
      ThaiDistrictOption(name: 'Sam Phran', postalCode: '73110'),
      ThaiDistrictOption(name: 'Phutthamonthon', postalCode: '73170'),
    ],
  ),
];
