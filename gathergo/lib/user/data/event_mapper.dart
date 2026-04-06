class EventMapper {
  static int id(Map<String, dynamic> e, {int fallback = 0}) {
    final raw = e['eventId'] ?? e['id'] ?? e['event_id'] ?? fallback;
    if (raw is int) return raw;
    return int.tryParse(raw.toString()) ?? fallback;
  }

  static String title(Map<String, dynamic> e) {
    return (e['title'] ?? e['name'] ?? e['event_name'] ?? 'Big Event').toString();
  }

  static double fee(Map<String, dynamic> e) {
    final raw = e['fee'] ?? e['price'] ?? e['cost'] ?? 0;
    if (raw is num) return raw.toDouble();
    return double.tryParse(raw.toString()) ?? 0.0;
  }
}