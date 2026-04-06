class ActivityExpiry {
  const ActivityExpiry._();

  static const Duration gracePeriod = Duration(hours: 24);

  static bool isExpiredAfterGrace(
    Map<String, dynamic> item, {
    DateTime? now,
  }) {
    final startAt = parseStartAt(item);
    if (startAt == null) return false;
    return (now ?? DateTime.now()).isAfter(startAt.add(gracePeriod));
  }

  static DateTime? parseStartAt(Map<String, dynamic> item) {
    final spotDate =
        (item['event_date'] ?? item['date'] ?? '').toString().trim();
    final spotTime =
        (item['event_time'] ?? item['time'] ?? '').toString().trim();

    if (spotDate.isNotEmpty) {
      return _parseDateTime(spotDate, timeText: spotTime);
    }

    final eventDate =
        (item['start_at'] ?? item['event_date'] ?? item['date'] ?? '')
            .toString()
            .trim();
    if (eventDate.isEmpty) return null;
    return _parseDateTime(eventDate);
  }

  static DateTime? _parseDateTime(String dateText, {String? timeText}) {
    final rawDate = dateText.trim();
    if (rawDate.isEmpty) return null;

    final normalizedTime = (timeText ?? '').trim();
    final hasExplicitTime = rawDate.contains('T') ||
        RegExp(r'\d{2}:\d{2}').hasMatch(rawDate) ||
        normalizedTime.isNotEmpty;

    final combined = normalizedTime.isNotEmpty && !rawDate.contains('T')
        ? '${rawDate}T$normalizedTime'
        : rawDate;

    final parsed = DateTime.tryParse(combined)?.toLocal() ??
        DateTime.tryParse(rawDate)?.toLocal() ??
        _parseSlashDateTime(rawDate, normalizedTime);
    if (parsed == null) return null;

    if (hasExplicitTime) return parsed;
    return DateTime(
      parsed.year,
      parsed.month,
      parsed.day,
      23,
      59,
      59,
      999,
    );
  }

  static DateTime? _parseSlashDateTime(String rawDate, String normalizedTime) {
    final match = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(rawDate);
    if (match == null) return null;

    final day = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final year = int.tryParse(match.group(3) ?? '');
    if (day == null || month == null || year == null) return null;

    var hour = 0;
    var minute = 0;
    if (normalizedTime.isNotEmpty) {
      final timeMatch =
          RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(normalizedTime);
      if (timeMatch == null) return null;
      hour = int.tryParse(timeMatch.group(1) ?? '') ?? 0;
      minute = int.tryParse(timeMatch.group(2) ?? '') ?? 0;
    }

    return DateTime(year, month, day, hour, minute);
  }
}
