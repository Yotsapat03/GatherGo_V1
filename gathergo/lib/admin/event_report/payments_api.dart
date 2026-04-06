import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import 'report_models.dart';

class PaymentCompanyRow {
  final int organizationId;
  final String companyId;
  final String name;
  final String email;
  final String phone;
  final String address;
  final int numberOfEvents;

  const PaymentCompanyRow({
    required this.organizationId,
    required this.companyId,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.numberOfEvents,
  });

  factory PaymentCompanyRow.fromJson(Map<String, dynamic> json) {
    final id = ReportRow.parseRequiredInt(
      json['organization_id'],
      fieldName: 'organization_id',
    );
    return PaymentCompanyRow(
      organizationId: id,
      companyId: 'ORG-$id',
      name: (json['organization_name'] ?? '-').toString(),
      email: (json['organization_email'] ?? '-').toString(),
      phone: (json['organization_phone'] ?? '-').toString(),
      address: (json['organization_address'] ?? '-').toString(),
      numberOfEvents: ReportRow.parseInt(json['number_of_events']),
    );
  }
}

class PaymentCompanyListResponse {
  final PaymentSummary summary;
  final List<PaymentCompanyRow> rows;

  const PaymentCompanyListResponse({
    required this.summary,
    required this.rows,
  });

  factory PaymentCompanyListResponse.fromJson(Map<String, dynamic> json) {
    final summaryJson = (json['summary'] is Map)
        ? Map<String, dynamic>.from(json['summary'] as Map)
        : const <String, dynamic>{};
    final rowsJson = (json['rows'] is List) ? json['rows'] as List : const [];

    return PaymentCompanyListResponse(
      summary: PaymentSummary.fromJson(summaryJson),
      rows: rowsJson
          .map(
            (row) => PaymentCompanyRow.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(),
    );
  }
}

class PaymentCompanyEventRow {
  final int eventNumericId;
  final String eventId;
  final String eventName;
  final DateTime? time;
  final DateTime? createdAt;
  final int maxParticipants;
  final double fee;
  final int paymentCount;
  final bool hasShirtSize;

  const PaymentCompanyEventRow({
    required this.eventNumericId,
    required this.eventId,
    required this.eventName,
    required this.time,
    required this.createdAt,
    required this.maxParticipants,
    required this.fee,
    required this.paymentCount,
    required this.hasShirtSize,
  });

  factory PaymentCompanyEventRow.fromJson(Map<String, dynamic> json) {
    return PaymentCompanyEventRow(
      eventNumericId: ReportRow.parseRequiredInt(json['id'], fieldName: 'id'),
      eventId: (json['display_code'] ?? json['id'] ?? '-').toString(),
      eventName: (json['title'] ?? '-').toString(),
      time: DateTime.tryParse((json['start_at'] ?? '').toString()),
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      maxParticipants: ReportRow.parseInt(json['max_participants']),
      fee: (num.tryParse('${json['fee'] ?? 0}') ?? 0).toDouble(),
      paymentCount: ReportRow.parseInt(json['payment_count']),
      hasShirtSize: json['has_shirt_size'] == true,
    );
  }
}

class PaymentEventUserRow {
  final int userId;
  final String userCode;
  final String userName;
  final DateTime? actionAt;
  final String status;
  final double price;
  final String paymentId;
  final String bookingId;
  final String paymentMethod;
  final String provider;
  final String providerTxnId;
  final String paymentStatus;
  final DateTime? paidAt;
  final String receiptNo;
  final String receiptIssueDate;
  final String receiptUrl;
  final String shirtSize;

  const PaymentEventUserRow({
    required this.userId,
    required this.userCode,
    required this.userName,
    required this.actionAt,
    required this.status,
    required this.price,
    required this.paymentId,
    required this.bookingId,
    required this.paymentMethod,
    required this.provider,
    required this.providerTxnId,
    required this.paymentStatus,
    required this.paidAt,
    required this.receiptNo,
    required this.receiptIssueDate,
    required this.receiptUrl,
    required this.shirtSize,
  });

  factory PaymentEventUserRow.fromJson(Map<String, dynamic> json) {
    String optionalText(dynamic value) => (value ?? '').toString().trim();

    return PaymentEventUserRow(
      userId: ReportRow.parseRequiredInt(json['user_id'], fieldName: 'user_id'),
      userCode:
          (json['user_display_code'] ?? json['user_id'] ?? '-').toString(),
      userName: (json['user_name'] ?? '-').toString(),
      actionAt: DateTime.tryParse((json['action_at'] ?? '').toString()),
      status: optionalText(json['status']),
      price: (num.tryParse('${json['price'] ?? 0}') ?? 0).toDouble(),
      paymentId: optionalText(json['payment_reference'] ?? json['payment_id']),
      bookingId: optionalText(json['booking_reference'] ?? json['booking_id']),
      paymentMethod: optionalText(json['payment_method']),
      provider: optionalText(json['provider']),
      providerTxnId: optionalText(json['provider_txn_id'] ??
          json['provider_charge_id'] ??
          json['provider_payment_intent_id']),
      paymentStatus: optionalText(json['payment_status']),
      paidAt: DateTime.tryParse((json['paid_at'] ?? '').toString()),
      receiptNo: optionalText(json['receipt_no']),
      receiptIssueDate: optionalText(json['receipt_issue_date']),
      receiptUrl: optionalText(json['receipt_url']),
      shirtSize: optionalText(json['shirt_size']),
    );
  }
}

class PaymentsApi {
  static String get _baseUrl => ConfigService.getApiBaseUrl();

  static bool _isWrongTarget404(Uri primary, http.Response res, String path) {
    if (!kIsWeb || !kDebugMode) return false;
    if (res.statusCode != 404) return false;

    final body = res.body.toLowerCase();
    final cannotGetPath = body.contains('cannot get') && body.contains(path);
    if (!cannotGetPath) return false;

    final webOrigin = ConfigService.getWebOrigin();
    final isWebOrigin =
        webOrigin != null && ConfigService.isSameHostPort(primary, webOrigin);
    final isLikelyFlutterPort = ConfigService.isLikelyFlutterDevPort(primary);
    return isWebOrigin || isLikelyFlutterPort;
  }

  static Future<http.Response> _get(String path) async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: {
      'admin_id': adminId.toString(),
    });

    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'x-admin-id': adminId.toString(),
    };

    var response = await http
        .get(
          uri,
          headers: headers,
        )
        .timeout(const Duration(seconds: 20));

    if (_isWrongTarget404(uri, response, path)) {
      final fallback = ConfigService.getDevFallbackUri(path)?.replace(
        queryParameters: {'admin_id': adminId.toString()},
      );
      if (fallback != null && fallback != uri) {
        response = await http
            .get(
              fallback,
              headers: headers,
            )
            .timeout(const Duration(seconds: 20));
      }
    }

    if (response.statusCode != 200) {
      throw Exception(
        'Fetch payments report failed: ${response.statusCode} ${response.body}',
      );
    }

    return response;
  }

  static Future<PaymentCompanyListResponse> fetchPaymentCompanies() async {
    final response = await _get('/api/admin/event-report/payments');
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid payment companies response');
    }
    return PaymentCompanyListResponse.fromJson(
        Map<String, dynamic>.from(decoded));
  }

  static Future<List<PaymentCompanyEventRow>> fetchCompanyEvents(
    int organizationId,
  ) async {
    final response = await _get(
      '/api/admin/event-report/payments/companies/$organizationId/events',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid company events response');
    }
    final rowsJson =
        (decoded['rows'] is List) ? decoded['rows'] as List : const [];
    return rowsJson
        .map(
          (row) => PaymentCompanyEventRow.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }

  static Future<List<PaymentEventUserRow>> fetchEventUsers(int eventId) async {
    final response = await _get(
      '/api/admin/event-report/payments/events/$eventId/users',
    );
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid event payment users response');
    }
    final rowsJson =
        (decoded['rows'] is List) ? decoded['rows'] as List : const [];
    return rowsJson
        .map(
          (row) => PaymentEventUserRow.fromJson(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList();
  }
}
