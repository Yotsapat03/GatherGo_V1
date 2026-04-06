class UserProfile {
  final int id;
  final String name;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String address;
  final String addressHouseNo;
  final String addressFloor;
  final String addressBuilding;
  final String addressRoad;
  final String addressSubdistrict;
  final String addressPostalCode;
  final String province;
  final String district;
  final String profileImageUrl;
  final String nationalIdImageUrl;
  final double? totalKm;
  final int joinedCount;
  final int postCount;
  final String status;
  final Map<String, dynamic> raw;

  const UserProfile({
    required this.id,
    required this.name,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.address,
    required this.addressHouseNo,
    required this.addressFloor,
    required this.addressBuilding,
    required this.addressRoad,
    required this.addressSubdistrict,
    required this.addressPostalCode,
    required this.province,
    required this.district,
    required this.profileImageUrl,
    required this.nationalIdImageUrl,
    required this.totalKm,
    required this.joinedCount,
    required this.postCount,
    required this.status,
    required this.raw,
  });

  String get displayName {
    final fn = firstName.trim();
    final ln = lastName.trim();
    final full = [fn, ln].where((x) => x.isNotEmpty).join(' ').trim();
    if (full.isNotEmpty) return full;
    if (name.trim().isNotEmpty) return name.trim();
    return "User";
  }

  String get publicLocation {
    final parts = <String>[
      district.trim(),
      province.trim(),
    ].where((value) => value.isNotEmpty).toList();
    return parts.join(', ');
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: int.tryParse((json["id"] ?? "").toString()) ?? 0,
      name: (json["name"] ?? "").toString(),
      firstName: (json["first_name"] ?? json["firstName"] ?? "").toString(),
      lastName: (json["last_name"] ?? json["lastName"] ?? "").toString(),
      email: (json["email"] ?? "").toString(),
      phone: (json["phone"] ?? "").toString(),
      address: (json["address"] ?? "").toString(),
      addressHouseNo:
          (json["address_house_no"] ?? json["addressHouseNo"] ?? "").toString(),
      addressFloor:
          (json["address_floor"] ?? json["addressFloor"] ?? "").toString(),
      addressBuilding:
          (json["address_building"] ?? json["addressBuilding"] ?? "")
              .toString(),
      addressRoad:
          (json["address_road"] ?? json["addressRoad"] ?? "").toString(),
      addressSubdistrict:
          (json["address_subdistrict"] ?? json["addressSubdistrict"] ?? "")
              .toString(),
      addressPostalCode:
          (json["address_postal_code"] ?? json["addressPostalCode"] ?? "")
              .toString(),
      province: (json["province"] ?? "").toString(),
      district: (json["district"] ?? "").toString(),
      profileImageUrl:
          (json["profile_image_url"] ?? json["profileImageUrl"] ?? "")
              .toString(),
      nationalIdImageUrl:
          (json["national_id_image_url"] ?? json["nationalIdImageUrl"] ?? "")
              .toString(),
      totalKm: double.tryParse(
        (json["total_km"] ?? json["totalKm"] ?? "").toString(),
      ),
      joinedCount: int.tryParse(
              (json["joined_count"] ?? json["joinedCount"] ?? "0")
                  .toString()) ??
          0,
      postCount: int.tryParse(
              (json["post_count"] ?? json["postCount"] ?? "0").toString()) ??
          0,
      status: (json["status"] ?? "").toString(),
      raw: json,
    );
  }
}
