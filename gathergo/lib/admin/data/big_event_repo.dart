import '../models/big_event.dart';

class BigEventRepo {
  BigEventRepo._();
  static final BigEventRepo instance = BigEventRepo._();

  final List<BigEvent> _items = [];

  List<BigEvent> listByOrg(String orgId) {
    return _items.where((e) => e.orgId == orgId).toList()
      ..sort((a, b) => b.eventDate.compareTo(a.eventDate));
  }

  void add(BigEvent e) => _items.add(e);

  void delete(String id) => _items.removeWhere((e) => e.id == id);
}
