// lib/constants/asset_path.dart
class AssetPath {
  const AssetPath._();

  /// แปลง path เก่าที่หลงเหลือ ให้เป็น path ใหม่ที่ถูกต้อง
  static String normalize(String p) {
    p = p.trim();
    if (p.isEmpty) return p;

    // กันเคสหลุดมาเป็น Windows path
    p = p.replaceAll('\\', '/');

    // ✅ เคสโค้ดเก่า: assets/icons/xxx.png
    if (p.startsWith('assets/icons/')) {
      final name = p.replaceFirst('assets/icons/', '');
      return 'assets/images/user/icons/$name';
    }

    // ✅ เคสโค้ดเก่า: assets/images/icons/xxx.png
    if (p.startsWith('assets/images/icons/')) {
      final name = p.replaceFirst('assets/images/icons/', '');
      return 'assets/images/user/icons/$name';
    }

    // ✅ เคส spot เก่า: assets/images/spots/xxx.png
    if (p.startsWith('assets/images/spots/')) {
      final name = p.replaceFirst('assets/images/spots/', '');
      return 'assets/images/user/spots/$name';
    }

    // ✅ เคส event เก่า: assets/images/events/xxx.png
    if (p.startsWith('assets/images/events/')) {
      final name = p.replaceFirst('assets/images/events/', '');
      return 'assets/images/user/events/$name';
    }

    // ✅ ถ้าเป็นของถูกอยู่แล้ว ให้คืนค่าเดิม
    if (p.startsWith('assets/images/')) return p;

    return p;
  }
}