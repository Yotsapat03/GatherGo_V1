class ReportRow {
  final String eventId;
  final String date;
  final DateTime? eventDateBangkok;
  final String name;
  final int registeredUsers;
  final String type; // Spot / Big event
  final String status;
  final String creatorId;
  final String creatorKind;
  final String creator;

  // For payment tab
  final String totalPaid;

  const ReportRow({
    required this.eventId,
    required this.date,
    required this.eventDateBangkok,
    required this.name,
    required this.registeredUsers,
    required this.type,
    required this.status,
    required this.creatorId,
    required this.creatorKind,
    required this.creator,
    this.totalPaid = '',
  });

  static int parseInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return fallback;
      final parsed = int.tryParse(trimmed);
      if (parsed != null) return parsed;
    }
    throw FormatException('Unable to parse int from value: $value');
  }

  static int parseRequiredInt(dynamic value, {required String fieldName}) {
    if (value == null) {
      throw FormatException('Missing required integer field: $fieldName');
    }
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        throw FormatException('Missing required integer field: $fieldName');
      }
      final parsed = int.tryParse(trimmed);
      if (parsed != null) return parsed;
    }
    throw FormatException(
        'Unable to parse required integer field $fieldName from value: $value');
  }

  factory ReportRow.fromRegistrationJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? '').toString().toUpperCase();
    final rawDate = (json['start_at'] ?? json['created_at'] ?? '').toString();
    final parsedDate = DateTime.tryParse(rawDate);
    final bangkokDate = parsedDate == null
        ? null
        : (parsedDate.isUtc ? parsedDate : parsedDate.toUtc())
            .add(const Duration(hours: 7));
    final formattedDate = parsedDate == null
        ? '-'
        : '${bangkokDate!.day.toString().padLeft(2, '0')}/${bangkokDate.month.toString().padLeft(2, '0')}/${bangkokDate.year}';

    return ReportRow(
      eventId: (json['display_code'] ?? json['id'] ?? '-').toString(),
      date: formattedDate,
      eventDateBangkok: bangkokDate,
      name: (json['title'] ?? '-').toString(),
      registeredUsers: parseInt(json['registered_users']),
      type: rawType == 'SPOT' ? 'Spot' : 'Big event',
      status: (json['status'] ?? '-').toString(),
      creatorId: (json['creator_id'] ?? '-').toString(),
      creatorKind: (json['creator_kind'] ?? '').toString(),
      creator: (json['creator_name'] ?? '-').toString(),
    );
  }

  factory ReportRow.fromPaymentJson(Map<String, dynamic> json) {
    final rawDate = (json['start_at'] ?? json['created_at'] ?? '').toString();
    final parsedDate = DateTime.tryParse(rawDate);
    final bangkokDate = parsedDate == null
        ? null
        : (parsedDate.isUtc ? parsedDate : parsedDate.toUtc())
            .add(const Duration(hours: 7));
    final formattedDate = parsedDate == null
        ? '-'
        : '${bangkokDate!.day.toString().padLeft(2, '0')}/${bangkokDate.month.toString().padLeft(2, '0')}/${bangkokDate.year}';

    return ReportRow(
      eventId: (json['display_code'] ?? json['id'] ?? '-').toString(),
      date: formattedDate,
      eventDateBangkok: bangkokDate,
      name: (json['title'] ?? '-').toString(),
      registeredUsers: parseInt(json['registered_users']),
      type: 'Big event',
      status: (json['payment_status'] ?? 'pending').toString(),
      creatorId: (json['creator_id'] ?? '-').toString(),
      creatorKind: (json['creator_kind'] ?? '').toString(),
      totalPaid:
          '${(num.tryParse('${json['total_paid_amount'] ?? 0}') ?? 0).toStringAsFixed(2)} THB',
      creator: (json['creator_name'] ?? '-').toString(),
    );
  }
}

class RegistrationSummary {
  final int totalUsersExcludingAdmin;
  final int totalRegistrationsTodayBangkok;
  final int totalEvents;
  final int totalSpot;
  final int totalBigEvent;

  const RegistrationSummary({
    required this.totalUsersExcludingAdmin,
    required this.totalRegistrationsTodayBangkok,
    required this.totalEvents,
    required this.totalSpot,
    required this.totalBigEvent,
  });

  factory RegistrationSummary.fromJson(Map<String, dynamic> json) {
    return RegistrationSummary(
      totalUsersExcludingAdmin:
          ReportRow.parseInt(json['total_users_excluding_admin']),
      totalRegistrationsTodayBangkok:
          ReportRow.parseInt(json['total_registrations_today_bangkok']),
      totalEvents: ReportRow.parseInt(json['total_events']),
      totalSpot: ReportRow.parseInt(json['total_spot']),
      totalBigEvent: ReportRow.parseInt(json['total_big_event']),
    );
  }
}

class RegistrationReportResponse {
  final RegistrationSummary summary;
  final List<ReportRow> rows;

  const RegistrationReportResponse({
    required this.summary,
    required this.rows,
  });

  factory RegistrationReportResponse.fromJson(Map<String, dynamic> json) {
    final summaryJson = (json['summary'] is Map)
        ? Map<String, dynamic>.from(json['summary'] as Map)
        : const <String, dynamic>{};
    final rowsJson = (json['rows'] is List) ? json['rows'] as List : const [];

    return RegistrationReportResponse(
      summary: RegistrationSummary.fromJson(summaryJson),
      rows: rowsJson
          .map(
            (row) => ReportRow.fromRegistrationJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
    );
  }
}

class PaymentSummary {
  final int totalCompany;
  final int totalRegistrations;
  final int totalBigEvents;

  const PaymentSummary({
    required this.totalCompany,
    required this.totalRegistrations,
    required this.totalBigEvents,
  });

  factory PaymentSummary.fromJson(Map<String, dynamic> json) {
    return PaymentSummary(
      totalCompany: ReportRow.parseInt(json['total_company']),
      totalRegistrations: ReportRow.parseInt(json['total_registrations']),
      totalBigEvents: ReportRow.parseInt(json['total_big_events']),
    );
  }
}

class PaymentReportResponse {
  final PaymentSummary summary;
  final List<ReportRow> rows;

  const PaymentReportResponse({
    required this.summary,
    required this.rows,
  });

  factory PaymentReportResponse.fromJson(Map<String, dynamic> json) {
    final summaryJson = (json['summary'] is Map)
        ? Map<String, dynamic>.from(json['summary'] as Map)
        : const <String, dynamic>{};
    final rowsJson = (json['rows'] is List) ? json['rows'] as List : const [];

    return PaymentReportResponse(
      summary: PaymentSummary.fromJson(summaryJson),
      rows: rowsJson
          .map(
            (row) => ReportRow.fromPaymentJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
    );
  }
}

class SpotLeaveFeedbackRow {
  final int id;
  final int eventId;
  final String eventTitle;
  final int leaverUserId;
  final String leaverUserName;
  final String reasonCode;
  final String reasonText;
  final String? reportDetailText;
  final String category;
  final String reportedTargetType;
  final int? reportedTargetUserId;
  final String? reportedTargetUserName;
  final DateTime createdAt;

  const SpotLeaveFeedbackRow({
    required this.id,
    required this.eventId,
    required this.eventTitle,
    required this.leaverUserId,
    required this.leaverUserName,
    required this.reasonCode,
    required this.reasonText,
    required this.reportDetailText,
    required this.category,
    required this.reportedTargetType,
    required this.reportedTargetUserId,
    required this.reportedTargetUserName,
    required this.createdAt,
  });

  bool get hasReportDetail => (reportDetailText ?? '').trim().isNotEmpty;

  static int? _parseNullableInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      final parsed = int.tryParse(trimmed);
      if (parsed != null) return parsed;
    }
    throw FormatException('Unable to parse nullable int from value: $value');
  }

  factory SpotLeaveFeedbackRow.fromJson(Map<String, dynamic> json) {
    return SpotLeaveFeedbackRow(
      id: ReportRow.parseRequiredInt(json['id'], fieldName: 'id'),
      eventId:
          ReportRow.parseRequiredInt(json['event_id'], fieldName: 'event_id'),
      eventTitle: (json['event_title'] ?? '-').toString(),
      leaverUserId: ReportRow.parseRequiredInt(json['leaver_user_id'],
          fieldName: 'leaver_user_id'),
      leaverUserName: (json['leaver_user_name'] ?? '-').toString(),
      reasonCode: (json['reason_code'] ?? '').toString(),
      reasonText: (json['reason_text'] ?? '').toString(),
      reportDetailText: json['report_detail_text']?.toString(),
      category: (json['category'] ?? '').toString(),
      reportedTargetType: (json['reported_target_type'] ?? 'none').toString(),
      reportedTargetUserId: _parseNullableInt(json['reported_target_user_id']),
      reportedTargetUserName: json['reported_target_user_name']?.toString(),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class AllEventsPieReport {
  final int year;
  final int month;
  final int bigEventCount;
  final int spotCount;

  const AllEventsPieReport({
    required this.year,
    required this.month,
    required this.bigEventCount,
    required this.spotCount,
  });

  int get totalCount => bigEventCount + spotCount;

  factory AllEventsPieReport.fromJson(Map<String, dynamic> json) {
    return AllEventsPieReport(
      year: ReportRow.parseRequiredInt(json['year'], fieldName: 'year'),
      month: ReportRow.parseRequiredInt(json['month'], fieldName: 'month'),
      bigEventCount: ReportRow.parseInt(json['bigEventCount']),
      spotCount: ReportRow.parseInt(json['spotCount']),
    );
  }
}

class AvailablePeriodsResponse {
  final int minYear;
  final int maxYear;
  final Map<int, List<int>> monthsByYear;

  const AvailablePeriodsResponse({
    required this.minYear,
    required this.maxYear,
    required this.monthsByYear,
  });

  List<int> get years {
    final values = monthsByYear.keys.toList()..sort((a, b) => b.compareTo(a));
    return values;
  }

  factory AvailablePeriodsResponse.fromJson(Map<String, dynamic> json) {
    final rawMonthsByYear = json['monthsByYear'];
    final monthsByYear = <int, List<int>>{};

    if (rawMonthsByYear is Map) {
      for (final entry in rawMonthsByYear.entries) {
        final year = int.tryParse(entry.key.toString());
        if (year == null) continue;

        final rawMonths = entry.value;
        if (rawMonths is! List) {
          monthsByYear[year] = const [];
          continue;
        }

        final parsedMonths = rawMonths
            .map((value) => ReportRow.parseInt(value, fallback: -1))
            .where((value) => value >= 1 && value <= 12)
            .toSet()
            .toList()
          ..sort();
        monthsByYear[year] = parsedMonths;
      }
    }

    return AvailablePeriodsResponse(
      minYear:
          ReportRow.parseRequiredInt(json['minYear'], fieldName: 'minYear'),
      maxYear:
          ReportRow.parseRequiredInt(json['maxYear'], fieldName: 'maxYear'),
      monthsByYear: monthsByYear,
    );
  }
}
