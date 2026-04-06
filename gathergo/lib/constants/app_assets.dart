class AssetPath {
  const AssetPath._();

  static String normalize(String p) {
    p = p.trim();
    if (p.isEmpty) return p;

    // กัน Windows path
    p = p.replaceAll('\\', '/');

    // โค้ดเก่า -> โค้ดใหม่
    if (p.startsWith('assets/icons/')) {
      final name = p.replaceFirst('assets/icons/', '');
      return 'assets/images/user/icons/$name';
    }

    if (p.startsWith('assets/images/icons/')) {
      final name = p.replaceFirst('assets/images/icons/', '');
      return 'assets/images/user/icons/$name';
    }

    if (p.startsWith('assets/images/spots/')) {
      final name = p.replaceFirst('assets/images/spots/', '');
      return 'assets/images/user/spots/$name';
    }

    if (p.startsWith('assets/images/events/')) {
      final name = p.replaceFirst('assets/images/events/', '');
      return 'assets/images/user/events/$name';
    }

    // ถ้าถูกแล้ว
    if (p.startsWith('assets/images/')) return p;

    return p;
  }
}