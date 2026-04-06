/// Event API Service - Web & Native Compatible
/// Handles all event-related API calls
/// Supports file uploads on both web and native platforms
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';

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

  /// Create Big Event (Admin Only)
  /// - If visible to users: status = published, visibility = public
  /// - If private: status = draft or visibility = private
  Future<Map<String, dynamic>> createEvent({
    required int organizationId,
    required String description,
    required String meetingPoint,
    required DateTime startAt,
    required double distancePerLap,
    required int numberOfLaps,
    String? title,
    int? maxParticipants,
    int createdBy = 1,
    double? fee,
    String visibility = 'public', // public / private
    String status = 'published', // draft / published / closed / cancelled
    String type = 'BIG_EVENT', // BIG_EVENT / SPOT
  }) async {
    final uri = Uri.parse('$baseUrl/api/events');
    final effectiveAdminId = await AdminSessionService.getCurrentAdminId();

    final payload = <String, dynamic>{
      'organization_id': organizationId,
      'title': (title != null && title.trim().isNotEmpty) ? title.trim() : null,
      'description': description.trim(),
      'meeting_point': meetingPoint.trim(),
      'start_at': startAt.toIso8601String(),
      'max_participants': maxParticipants,
      'created_by': createdBy,
      'distance_per_lap': distancePerLap,
      'number_of_laps': numberOfLaps,
      'type': type,
      'visibility': visibility,
      'status': status,
      if (fee != null) 'fee': fee,
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
          .timeout(ConfigService.requestTimeout);

      if (res.statusCode != 201) {
        throw Exception(_err('POST', uri, res));
      }
      return _decodeMap(res.body);
    } catch (e) {
      rethrow;
    }
  }

  /// List events by organization
  Future<List<dynamic>> listEventsByOrg(int orgId) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final uri = Uri.parse('$baseUrl/api/organizations/$orgId/events?_ts=$ts');
    final fallbackUri = Uri.parse('$baseUrl/api/organizations/$orgId/events');

    try {
      http.Response res;
      try {
        res = await http.get(uri, headers: {
          'Accept': 'application/json',
        }).timeout(ConfigService.requestTimeout);
      } on Exception {
        res = await http.get(fallbackUri, headers: {
          'Accept': 'application/json',
        }).timeout(ConfigService.requestTimeout);
      }

      if (res.statusCode != 200) {
        throw Exception(_err('GET', uri, res));
      }
      return _decodeList(res.body);
    } catch (e) {
      rethrow;
    }
  }

  /// Get all big events (user-facing)
  Future<List<dynamic>> listBigEvents() async {
    final uri = Uri.parse('$baseUrl/api/big-events');

    try {
      final res = await http.get(uri, headers: {
        'Accept': 'application/json'
      }).timeout(ConfigService.requestTimeout);

      if (res.statusCode != 200) {
        throw Exception(_err('GET', uri, res));
      }
      return _decodeList(res.body);
    } catch (e) {
      rethrow;
    }
  }

  /// Upload event cover image (Admin Only)
  /// Web-compatible: accepts both File (native) and bytes (web)
  Future<Map<String, dynamic>> uploadCover({
    required int eventId,
    dynamic file, // Can be File (native) or XFile
  }) async {
    final uri = Uri.parse('$baseUrl/api/events/$eventId/cover');
    final req = http.MultipartRequest('POST', uri);

    try {
      // Handle different file types
      if (kIsWeb && file is XFile) {
        // Web: use bytes
        final bytes = await file.readAsBytes();
        req.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name,
        ));
      } else if (!kIsWeb && file is XFile) {
        // Native: use file path if available
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

  /// Upload payment QR code image (Admin Only)
  /// Web-compatible: accepts both File (native) and bytes (web)
  /// Returns updated event with qrUrl
  Future<Map<String, dynamic>> uploadQr({
    required int eventId,
    dynamic file, // Can be File (native) or XFile
    String paymentMethod = 'promptPay',
  }) async {
    final uri = Uri.parse('$baseUrl/api/admin/events/$eventId/qr');
    final req = http.MultipartRequest('POST', uri);

    try {
      // Handle different file types
      if (kIsWeb && file is XFile) {
        // Web: use bytes
        final bytes = await file.readAsBytes();
        req.files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: file.name,
        ));
      } else if (!kIsWeb && file is XFile) {
        // Native: use file path if available
        req.files.add(await http.MultipartFile.fromPath('file', file.path));
      } else {
        throw ArgumentError('Unsupported file type: $file');
      }

      req.fields['payment_method'] = paymentMethod;
      req.headers['Accept'] = 'application/json';
      final effectiveAdminId = await AdminSessionService.getCurrentAdminId();
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

  /// Upload event gallery images (Admin Only)
  /// Web-compatible: accepts both File (native) and bytes (web)
  Future<List<dynamic>> uploadGallery({
    required int eventId,
    required List<dynamic> files, // Can be List<File> (native) or List<XFile>
  }) async {
    final uri = Uri.parse('$baseUrl/api/events/$eventId/gallery');
    final req = http.MultipartRequest('POST', uri);

    try {
      for (final file in files) {
        if (kIsWeb && file is XFile) {
          // Web: use bytes
          final bytes = await file.readAsBytes();
          req.files.add(http.MultipartFile.fromBytes(
            'files',
            bytes,
            filename: file.name,
          ));
        } else if (!kIsWeb && file is XFile) {
          // Native: use file path
          req.files.add(
            await http.MultipartFile.fromPath('files', file.path),
          );
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
}
