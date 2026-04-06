class Organization {
  final String id;
  final String name;
  final String email;
  final String phone;
  final String address;
  final String businessProfile;
  final String organizer;

  // ✅ NEW: รูปจาก DB/API (image_url)
  final String? imageUrl;

  // (ถ้าคุณยังใช้รูป local อยู่ ก็เก็บไว้ได้)
  final String? imagePath;

  Organization({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.businessProfile,
    required this.organizer,
    this.imageUrl,   // ✅ เพิ่ม named parameter นี้
    this.imagePath,
  });

  factory Organization.fromJson(Map<String, dynamic> j) {
    return Organization(
      id: (j["id"] ?? "").toString(),
      name: (j["name"] ?? "").toString(),
      email: (j["email"] ?? "").toString(),
      phone: (j["phone"] ?? "").toString(),
      address: (j["address"] ?? "").toString(),
      businessProfile: (j["description"] ?? "").toString(),
      organizer: (j["organizer"] ?? "").toString(), // DB ยังไม่มี ก็จะเป็น ""
      imageUrl: j["image_url"]?.toString(),         // ✅ จุดสำคัญ
      imagePath: null,
    );
  }

  Organization copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? address,
    String? businessProfile,
    String? organizer,
    String? imageUrl,
    String? imagePath,
  }) {
    return Organization(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      businessProfile: businessProfile ?? this.businessProfile,
      organizer: organizer ?? this.organizer,
      imageUrl: imageUrl ?? this.imageUrl,
      imagePath: imagePath ?? this.imagePath,
    );
  }
}
