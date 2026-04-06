import 'dart:convert';

import 'package:http/http.dart' as http;

import '../model/chat_message_model.dart';

class SpotChatService {
  final String baseUrl;
  final http.Client _client;

  SpotChatService({
    required this.baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<List<Map<String, dynamic>>> fetchMessageRowsFromUri(
    Uri uri, {
    Map<String, String>? headers,
  }) async {
    final response = await _client.get(uri, headers: headers);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid response format');
    }

    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<ChatMessageModel>> fetchMessages({
    required String chatId,
  }) async {
    final uri = Uri.parse('$baseUrl/api/spot-chats/$chatId/messages');
    final response = await _client.get(uri);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load chat messages (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    return parseChatMessagesFromJson(decoded);
  }

  List<ChatMessageModel> parseChatMessagesFromJson(dynamic decoded) {
    if (decoded is List) {
      return ChatMessageModel.listFromJson(decoded);
    }

    if (decoded is Map<String, dynamic>) {
      final items = decoded['messages'] ?? decoded['data'] ?? decoded['rows'];
      return ChatMessageModel.listFromJson(items);
    }

    return const <ChatMessageModel>[];
  }

  Future<List<ChatMessageModel>> fetchMessagesMock({
    required String chatId,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final mockJson = <Map<String, dynamic>>[
      {
        'id': '101',
        'user_id': 'u1',
        'body': 'Morning run starts at 6:30',
        'created_at': DateTime.now()
            .subtract(const Duration(minutes: 10))
            .toIso8601String(),
        'contains_url': false,
        'moderation_status': 'visible',
        'risk_level': 'safe',
        'phishing_scan_status': 'not_scanned',
      },
      {
        'id': '102',
        'client_message_key': 'cmk-demo-102',
        'user_id': 'u2',
        'body': 'Check this race discount link',
        'created_at': DateTime.now()
            .subtract(const Duration(minutes: 7))
            .toIso8601String(),
        'contains_url': true,
        'moderation_status': 'warning',
        'risk_level': 'suspicious',
        'phishing_scan_status': 'scanned',
        'phishing_scan_reason':
            'This link looks unusual. Please verify before opening.',
      },
      {
        'id': '103',
        'user_id': 'u3',
        'body': 'Blocked by moderation',
        'created_at': DateTime.now()
            .subtract(const Duration(minutes: 5))
            .toIso8601String(),
        'contains_url': true,
        'moderation_status': 'blocked',
        'risk_level': 'phishing',
        'phishing_scan_status': 'scanned',
        'phishing_scan_reason':
            'Matched a known phishing signal from the backend.',
      },
    ];

    return ChatMessageModel.listFromJson(mockJson);
  }

  void dispose() {
    _client.close();
  }
}

class SpotChatRepository {
  final SpotChatService service;
  final bool useMockApi;

  SpotChatRepository({
    required this.service,
    this.useMockApi = true,
  });

  Future<List<ChatMessageModel>> fetchMessages({
    required String chatId,
  }) {
    if (useMockApi) {
      return service.fetchMessagesMock(chatId: chatId);
    }
    return service.fetchMessages(chatId: chatId);
  }
}
