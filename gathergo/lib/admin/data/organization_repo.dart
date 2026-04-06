import '../models/organization.dart';

class OrganizationRepo {
  OrganizationRepo._();
  static final OrganizationRepo instance = OrganizationRepo._();

  final List<Organization> _items = [];

  // ✅ แก้ Error 2: ให้หน้า list เรียก OrganizationRepo.instance.items ได้
  List<Organization> get items => List.unmodifiable(_items);

  void add(Organization org) => _items.add(org);

  // (ไม่บังคับ) ถ้าต้องการลบ
  void delete(String id) => _items.removeWhere((o) => o.id == id);
}
