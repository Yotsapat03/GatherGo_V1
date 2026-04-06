import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/services/config_service.dart';
import '../../core/services/admin_session_service.dart';

class EventApi {
  EventApi._();
  static final instance = EventApi._();

  String get baseUrl => ConfigService.getBaseUrl();

  static const _jsonHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  Map<String, dynamic> _decodeMap(String body) {
    final j = jsonDecode(body);
    if (j is! Map<String, dynamic>) {
      throw Exception('Invalid response JSON (expected object): $j');
    }
    return j;
  }

  List<dynamic> _decodeList(String body) {
    final j = jsonDecode(body);
    if (j is! List) {
      throw Exception('Invalid response JSON (expected list): $j');
    }
    return j;
  }

  String _err(String method, Uri uri, http.Response res) {
    return '$method $uri failed: ${res.statusCode}\n${res.body}';
  }

  Future<int> _requireAdminId() async {
    final adminId = await AdminSessionService.getCurrentAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('Admin session missing');
    }
    return adminId;
  }

  Future<Map<String, dynamic>> createEvent({
    required int organizationId,
    required String description,
    required String locationName,
    required DateTime startAt,
    required double distancePerLap,
    required int numberOfLaps,
    double? locationLat,
    double? locationLng,
    String? province,
    String? district,
    String? locationDisplay,
    String? locationLink,
    String? meetingPointNote,
    String? title,
    int? maxParticipants,
    int createdBy = 1,
    double? fee,
    String visibility = 'public',
    String status = 'published',
    String type = 'BIG_EVENT',
    double? baseAmount,
    bool? promptpayEnabled,
    double? promptpayAmountThb,
    Map<String, String>? titleI18n,
    Map<String, String>? descriptionI18n,
    Map<String, String>? meetingPointI18n,
    Map<String, String>? locationNameI18n,
    Map<String, String>? meetingPointNoteI18n,
  }) async {
    final uri = Uri.parse('$baseUrl/api/events');
    final effectiveAdminId = await AdminSessionService.getCurrentAdminId();

    final payload = <String, dynamic>{
      'organization_id': organizationId,
      'title': (title != null && title.trim().isNotEmpty) ? title.trim() : null,
      'description': description.trim(),
      'meeting_point': locationName.trim(),
      'location_name': locationName.trim(),
      'start_at': startAt.toIso8601String(),
      'max_participants': maxParticipants,
      'created_by': createdBy,
      'distance_per_lap': distancePerLap,
      'number_of_laps': numberOfLaps,
      'type': type,
      'visibility': visibility,
      'status': status,
      if (locationLat != null) 'location_lat': locationLat,
      if (locationLng != null) 'location_lng': locationLng,
      if (province != null && province.trim().isNotEmpty)
        'province': province.trim(),
      if (district != null && district.trim().isNotEmpty)
        'district': district.trim(),
      if (locationDisplay != null && locationDisplay.trim().isNotEmpty)
        'location_display': locationDisplay.trim(),
      if (locationLink != null && locationLink.trim().isNotEmpty)
        'location_link': locationLink.trim(),
      if (meetingPointNote != null)
        'meeting_point_note': meetingPointNote.trim(),
      if (titleI18n != null) 'title_i18n': titleI18n,
      if (descriptionI18n != null) 'description_i18n': descriptionI18n,
      if (meetingPointI18n != null) 'meeting_point_i18n': meetingPointI18n,
      if (locationNameI18n != null) 'location_name_i18n': locationNameI18n,
      if (meetingPointNoteI18n != null)
        'meeting_point_note_i18n': meetingPointNoteI18n,
      if (fee != null) 'fee': fee,
      if (baseAmount != null) 'base_amount': baseAmount,
      if (promptpayEnabled != null) 'promptpay_enabled': promptpayEnabled,
      if (promptpayAmountThb != null)
        'promptpay_amount_thb': promptpayAmountThb,
    };

    try {
      final res = await http
          .post(
            uri,
            headers: {
              ..._jsonHeaders,
              if (effectiveAdminId != null && effectiveAdminId > 0)
                'x-admin-id': effectiveAdminId.toString(),
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 201) {
        throw Exception(_err('POST', uri, res));
      }
      return _decodeMap(res.body);
    } on Exception catch (e) {
      throw Exception('Network/Format error: $e');
    }
  }

  Future<List<dynamic>> listEventsByOrg(int orgId) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final uri = Uri.parse('$baseUrl/api/organizations/$orgId/events?_ts=$ts');
    final fallbackUri = Uri.parse('$baseUrl/api/organizations/$orgId/events');

    try {
      http.Response res;
      try {
        res = await http.get(uri, headers: {
          'Accept': 'application/json',
        }).timeout(
          const Duration(seconds: 20),
        );
      } on Exception {
        res = await http.get(fallbackUri, headers: {
          'Accept': 'application/json',
        }).timeout(
          const Duration(seconds: 20),
        );
      }

      if (res.statusCode != 200) {
        throw Exception(_err('GET', uri, res));
      }
      return _decodeList(res.body);
    } on Exception catch (e) {
      throw Exception('Network/Format error: $e');
    }
  }

  Future<Map<String, dynamic>> getEventDetail(int eventId) async {
    final uri = Uri.parse('$baseUrl/api/events/$eventId');

    try {
      final res = await http.get(uri, headers: {
        'Accept': 'application/json'
      }).timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        throw Exception(_err('GET', uri, res));
      }
      return _decodeMap(res.body);
    } on Exception catch (e) {
      throw Exception('Network/Format error: $e');
    }
  }

  Future<Map<String, dynamic>> updateEvent(
      int eventId, Map<String, dynamic> data) async {
    final uri = Uri.parse('$baseUrl/api/events/$eventId');
    final effectiveAdminId = await AdminSessionService.getCurrentAdminId();

    try {
      final res = await http
          .put(
            uri,
            headers: {
              ..._jsonHeaders,
              if (effectiveAdminId != null && effectiveAdminId > 0)
                'x-admin-id': effectiveAdminId.toString(),
            },
            body: jsonEncode(data),
          )
          .timeout(const Duration(seconds: 20));

      if (res.statusCode != 200) {
        throw Exception(_err('PUT', uri, res));
      }
      return _decodeMap(res.body);
    } on Exception catch (e) {
      throw Exception('Network/Format error: $e');
    }
  }

  Future<void> deleteEvent(int eventId) async {
    final effectiveAdminId = await AdminSessionService.getCurrentAdminId();
    final adminUri = Uri.parse('$baseUrl/api/admin/events/$eventId').replace(
      queryParameters: effectiveAdminId != null && effectiveAdminId > 0
          ? {'admin_id': effectiveAdminId.toString()}
          : null,
    );
    final fallbackUri = Uri.parse('$baseUrl/api/events/$eventId');

    try {
      final adminRes = await http.delete(
        adminUri,
        headers: {
          'Accept': 'application/json',
          if (effectiveAdminId != null && effectiveAdminId > 0)
            'x-admin-id': effectiveAdminId.toString(),
        },
      ).timeout(
        const Duration(seconds: 20),
      );

      if (adminRes.statusCode == 200 || adminRes.statusCode == 204) return;
      if (adminRes.statusCode != 404) {
        throw Exception(_err('DELETE', adminUri, adminRes));
      }

      final fallbackRes = await http.delete(fallbackUri).timeout(
            const Duration(seconds: 20),
          );

      if (fallbackRes.statusCode != 200 && fallbackRes.statusCode != 204) {
        throw Exception(_err('DELETE', fallbackUri, fallbackRes));
      }
    } on Exception catch (e) {
      throw Exception('Network error: $e');
    }
  }

  Future<Map<String, dynamic>> uploadCover({
    required int eventId,
    dynamic file,
  }) async {
    final uri = Uri.parse('$baseUrl/api/events/$eventId/cover');
    final req = http.MultipartRequest('POST', uri);

    try {
      if (kIsWeb && file is XFile) {
        final bytes = await file.readAsBytes();
        req.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name,
        ));
      } else if (!kIsWeb && file is XFile) {
        req.files.add(await http.MultipartFile.fromPath('file', file.path));
      } else {
        throw ArgumentError('Unsupported file type: $file');
      }

      req.headers['Accept'] = 'application/json';

      final resp = await req.send().timeout(ConfigService.requestTimeout);
      final body = await resp.stream.bytesToString();

      if (resp.statusCode != 201) {
        throw Exception('Upload cover failed: ${resp.statusCode}\n$body');
      }

      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> uploadQr({
    required int eventId,
    dynamic file,
    String paymentMethod = 'promptPay',
    int? adminId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/events/$eventId/qr');
    final req = http.MultipartRequest('POST', uri);

    try {
      if (kIsWeb && file is XFile) {
        final bytes = await file.readAsBytes();
        req.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name,
        ));
      } else if (!kIsWeb && file is XFile) {
        req.files.add(await http.MultipartFile.fromPath('file', file.path));
      } else {
        throw ArgumentError('Unsupported file type: $file');
      }

      req.fields['payment_method'] = paymentMethod;
      req.headers['Accept'] = 'application/json';
      final effectiveAdminId =
          adminId ?? await AdminSessionService.getCurrentAdminId();
      if (effectiveAdminId != null && effectiveAdminId > 0) {
        req.headers['x-admin-id'] = effectiveAdminId.toString();
      }

      final resp = await req.send().timeout(ConfigService.requestTimeout);
      final body = await resp.stream.bytesToString();

      if (resp.statusCode != 200 && resp.statusCode != 201) {
        throw Exception('Upload QR failed: ${resp.statusCode}\n$body');
      }

      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> getAdminPaymentMethods({
    required int eventId,
    int? adminId,
  }) async {
    final effectiveAdminId =
        adminId ?? await AdminSessionService.getCurrentAdminId();
    if (effectiveAdminId == null || effectiveAdminId <= 0) {
      throw Exception('Admin session missing');
    }

    final uri =
        Uri.parse('$baseUrl/api/admin/big-events/$eventId/payment-methods');
    final res = await http.get(uri, headers: {
      'Accept': 'application/json',
      'x-admin-id': effectiveAdminId.toString(),
    }).timeout(ConfigService.requestTimeout);

    if (res.statusCode != 200) {
      throw Exception(_err('GET', uri, res));
    }
    return _decodeMap(res.body);
  }

  Future<Map<String, dynamic>> updateAdminPaymentMethods({
    required int eventId,
    required String paymentMode,
    required bool enablePromptpay,
    required bool stripeEnabled,
    required double baseAmount,
    required double promptpayAmountThb,
    String? manualPromptpayQrUrl,
    int? adminId,
  }) async {
    final effectiveAdminId =
        adminId ?? await AdminSessionService.getCurrentAdminId();
    if (effectiveAdminId == null || effectiveAdminId <= 0) {
      throw Exception('Admin session missing');
    }

    final uri =
        Uri.parse('$baseUrl/api/admin/big-events/$eventId/payment-methods');
    final res = await http
        .put(
          uri,
          headers: {
            ..._jsonHeaders,
            'x-admin-id': effectiveAdminId.toString(),
          },
          body: jsonEncode({
            'payment_mode': paymentMode,
            'enable_promptpay': enablePromptpay,
            'stripe_enabled': stripeEnabled,
            'base_amount': baseAmount,
            'promptpay_amount_thb': promptpayAmountThb,
            if (manualPromptpayQrUrl != null)
              'manual_promptpay_qr_url': manualPromptpayQrUrl,
          }),
        )
        .timeout(ConfigService.requestTimeout);

    if (res.statusCode != 200) {
      throw Exception(_err('PUT', uri, res));
    }
    return _decodeMap(res.body);
  }

  Future<Map<String, dynamic>> uploadManualQr({
    required int eventId,
    required dynamic file,
    required String methodType,
    int? adminId,
  }) async {
    final effectiveAdminId =
        adminId ?? await AdminSessionService.getCurrentAdminId();
    if (effectiveAdminId == null || effectiveAdminId <= 0) {
      throw Exception('Admin session missing');
    }

    final normalizedMethodType = methodType.trim().toLowerCase();
    final uri = Uri.parse('$baseUrl/api/admin/events/$eventId/qr');
    final req = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..headers['x-admin-id'] = effectiveAdminId.toString()
      ..fields['payment_method'] = normalizedMethodType;

    if (kIsWeb && file is XFile) {
      final bytes = await file.readAsBytes();
      req.files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: file.name));
    } else if (!kIsWeb && file is XFile) {
      req.files.add(await http.MultipartFile.fromPath('file', file.path));
    } else {
      throw ArgumentError('Unsupported file type: $file');
    }

    final resp = await req.send().timeout(ConfigService.requestTimeout);
    final body = await resp.stream.bytesToString();
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('Upload QR failed: ${resp.statusCode}\n$body');
    }
    return jsonDecode(body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> uploadGallery({
    required int eventId,
    required List<dynamic> files,
  }) async {
    final uri = Uri.parse('$baseUrl/api/events/$eventId/gallery');
    final req = http.MultipartRequest('POST', uri);

    try {
      for (final file in files) {
        if (kIsWeb && file is XFile) {
          final bytes = await file.readAsBytes();
          req.files.add(http.MultipartFile.fromBytes(
            'files',
            bytes,
            filename: file.name,
          ));
        } else if (!kIsWeb && file is XFile) {
          req.files.add(await http.MultipartFile.fromPath('files', file.path));
        } else {
          throw ArgumentError('Unsupported file type: $file');
        }
      }

      req.headers['Accept'] = 'application/json';

      final resp = await req.send().timeout(const Duration(seconds: 60));
      final body = await resp.stream.bytesToString();

      if (resp.statusCode != 201) {
        throw Exception('Upload gallery failed: ${resp.statusCode}\n$body');
      }

      final decoded = jsonDecode(body);
      if (decoded is! List) {
        throw Exception('Upload gallery failed: invalid response shape');
      }
      return decoded;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> uploadRewardItems({
    required int eventId,
    required String section,
    required List<XFile> files,
    List<String>? itemTypes,
    List<String>? captions,
    List<int>? sortOrders,
  }) async {
    final adminId = await _requireAdminId();
    final uri = Uri.parse('$baseUrl/api/events/$eventId/rewards/$section');
    final req = http.MultipartRequest('POST', uri)
      ..headers['Accept'] = 'application/json'
      ..headers['x-admin-id'] = adminId.toString()
      ..fields['item_types_json'] = jsonEncode(itemTypes ?? const <String>[])
      ..fields['captions_json'] = jsonEncode(captions ?? const <String>[])
      ..fields['sort_orders_json'] = jsonEncode(sortOrders ?? const <int>[]);

    for (final file in files) {
      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        req.files.add(
          http.MultipartFile.fromBytes('files', bytes, filename: file.name),
        );
      } else {
        req.files.add(await http.MultipartFile.fromPath('files', file.path));
      }
    }

    final resp = await req.send().timeout(const Duration(seconds: 60));
    final body = await resp.stream.bytesToString();
    if (resp.statusCode != 201) {
      throw Exception('Upload reward items failed: ${resp.statusCode}\n$body');
    }
    return _decodeMap(body);
  }

  Future<Map<String, dynamic>> updateRewardItems({
    required int eventId,
    required String section,
    required List<Map<String, dynamic>> items,
  }) async {
    final adminId = await _requireAdminId();
    final uri = Uri.parse('$baseUrl/api/events/$eventId/rewards/$section');
    final res = await http
        .put(
          uri,
          headers: {
            ..._jsonHeaders,
            'x-admin-id': adminId.toString(),
          },
          body: jsonEncode({'items': items}),
        )
        .timeout(const Duration(seconds: 20));

    if (res.statusCode != 200) {
      throw Exception(_err('PUT', uri, res));
    }
    return _decodeMap(res.body);
  }
}
