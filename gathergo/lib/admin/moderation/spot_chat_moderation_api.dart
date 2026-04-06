import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';

class SpotChatModerationApi {
  static String get _baseUrl => ConfigService.getApiBaseUrl();

  static Future<List<SpotChatModerationQueueItem>> fetchQueue({
    String status = 'pending',
  }) async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse('$_baseUrl/api/admin/spot-chat/moderation-queue')
        .replace(queryParameters: {
      'admin_id': adminId.toString(),
      'status': status,
      'limit': '200',
    });

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'x-admin-id': adminId.toString(),
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(_extractMessage(response.body) ??
          'Failed to load moderation queue (${response.statusCode})');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid moderation queue response');
    }

    return decoded
        .whereType<Map>()
        .map((item) => SpotChatModerationQueueItem.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  static Future<void> dismissCase(int queueId, {String? reviewNote}) async {
    await _patchAction(queueId, 'dismiss', reviewNote: reviewNote);
  }

  static Future<void> confirmCase(int queueId, {String? reviewNote}) async {
    await _patchAction(queueId, 'confirm', reviewNote: reviewNote);
  }

  static Future<void> suspendUserFromCase(int queueId,
      {String? reviewNote}) async {
    await _patchAction(queueId, 'suspend-user', reviewNote: reviewNote);
  }

  static Future<SpotChatModerationSummary> fetchSummary() async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri =
        Uri.parse('$_baseUrl/api/admin/spot-chat/moderation-report-summary')
            .replace(queryParameters: {
      'admin_id': adminId.toString(),
    });

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'x-admin-id': adminId.toString(),
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ??
            'Failed to load moderation summary (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid moderation summary response');
    }

    return SpotChatModerationSummary.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  static Future<SpotChatModerationTrends> fetchTrends({
    String range = '30d',
    String bucket = 'day',
  }) async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri =
        Uri.parse('$_baseUrl/api/admin/spot-chat/moderation-report-trends')
            .replace(queryParameters: {
      'admin_id': adminId.toString(),
      'range': range,
      'bucket': bucket,
    });

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'x-admin-id': adminId.toString(),
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ??
            'Failed to load moderation trends (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid moderation trends response');
    }

    return SpotChatModerationTrends.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  static Future<List<SpotChatModerationAuditFeedItem>> fetchAuditFeed({
    int limit = 20,
  }) async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse('$_baseUrl/api/admin/spot-chat/moderation-audit-feed')
        .replace(queryParameters: {
      'admin_id': adminId.toString(),
      'limit': limit.toString(),
    });

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'x-admin-id': adminId.toString(),
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ??
            'Failed to load moderation audit feed (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid moderation audit feed response');
    }

    return decoded
        .whereType<Map>()
        .map((item) => SpotChatModerationAuditFeedItem.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  static Future<OpenAIReasonedUsageReport> fetchOpenAIReasonedUsage() async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse('$_baseUrl/api/admin/spot-chat/openai-reasoned-usage')
        .replace(queryParameters: {
      'admin_id': adminId.toString(),
    });

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'x-admin-id': adminId.toString(),
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ??
            'Failed to load OpenAI reasoned usage (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid OpenAI reasoned usage response');
    }

    return OpenAIReasonedUsageReport.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  static Future<List<ModerationLearningQueueItem>> fetchLearningQueue({
    String status = 'pending',
  }) async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse('$_baseUrl/api/admin/spot-chat/learning-queue')
        .replace(queryParameters: {
      'admin_id': adminId.toString(),
      'status': status,
    });

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'x-admin-id': adminId.toString(),
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ??
            'Failed to load moderation learning queue (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Invalid moderation learning queue response');
    }

    return decoded
        .whereType<Map>()
        .map((item) => ModerationLearningQueueItem.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .toList();
  }

  static Future<void> createLearningQueueItem({
    required int moderationQueueId,
    required String rawMessage,
    required String normalizedMessage,
    required List<String> currentCategories,
    required String suggestedAction,
    required List<String> suggestedCategories,
    required List<String> candidateTerms,
    String? adminNote,
  }) async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse('$_baseUrl/api/admin/spot-chat/learning-queue');
    final response = await http
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'x-admin-id': adminId.toString(),
          },
          body: jsonEncode({
            'admin_id': adminId,
            'source_type': 'moderation_queue',
            'moderation_queue_id': moderationQueueId,
            'raw_message': rawMessage,
            'normalized_message': normalizedMessage,
            'current_categories': currentCategories,
            'suggested_action': suggestedAction,
            'suggested_categories': suggestedCategories,
            'candidate_terms': candidateTerms,
            if (adminNote != null && adminNote.trim().isNotEmpty)
              'admin_note': adminNote.trim(),
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 201) {
      throw Exception(
        _extractMessage(response.body) ??
            'Failed to create learning queue item (${response.statusCode})',
      );
    }
  }

  static Future<int> importLearningQueueItems({
    required String format,
    required String content,
    required String defaultSuggestedAction,
    required List<String> defaultSuggestedCategories,
    String? defaultAdminNote,
  }) async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri =
        Uri.parse('$_baseUrl/api/admin/spot-chat/learning-queue/import');
    final response = await http
        .post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'x-admin-id': adminId.toString(),
          },
          body: jsonEncode({
            'admin_id': adminId,
            'format': format,
            'content': content,
            'default_suggested_action': defaultSuggestedAction,
            'default_suggested_categories': defaultSuggestedCategories,
            if (defaultAdminNote != null && defaultAdminNote.trim().isNotEmpty)
              'default_admin_note': defaultAdminNote.trim(),
          }),
        )
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 201) {
      throw Exception(
        _extractMessage(response.body) ??
            'Failed to import learning queue items (${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Invalid learning queue import response');
    }

    return int.tryParse('${decoded['imported_count'] ?? 0}') ?? 0;
  }

  static Future<void> applyLearningQueueItem(int learningId,
      {String? adminNote}) async {
    await _patchLearningQueueAction(learningId, 'apply', adminNote: adminNote);
  }

  static Future<void> rejectLearningQueueItem(int learningId,
      {String? adminNote}) async {
    await _patchLearningQueueAction(learningId, 'reject', adminNote: adminNote);
  }

  static Future<void> _patchAction(
    int queueId,
    String action, {
    String? reviewNote,
  }) async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse(
        '$_baseUrl/api/admin/spot-chat/moderation-queue/$queueId/$action');
    final response = await http
        .patch(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'x-admin-id': adminId.toString(),
          },
          body: jsonEncode({
            'admin_id': adminId,
            if (reviewNote != null && reviewNote.trim().isNotEmpty)
              'review_note': reviewNote.trim(),
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ??
            'Moderation action failed (${response.statusCode})',
      );
    }
  }

  static Future<void> _patchLearningQueueAction(
    int learningId,
    String action, {
    String? adminNote,
  }) async {
    final adminId = await AdminSessionService.getAdminId();
    if (adminId == null || adminId <= 0) {
      throw Exception('No active admin session');
    }

    final uri = Uri.parse(
        '$_baseUrl/api/admin/spot-chat/learning-queue/$learningId/$action');
    final response = await http
        .patch(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'x-admin-id': adminId.toString(),
          },
          body: jsonEncode({
            'admin_id': adminId,
            if (adminNote != null && adminNote.trim().isNotEmpty)
              'admin_note': adminNote.trim(),
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw Exception(
        _extractMessage(response.body) ??
            'Learning queue action failed (${response.statusCode})',
      );
    }
  }

  static String? _extractMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {}
    return null;
  }
}

class SpotChatModerationSummary {
  final int totalModeratedMessages;
  final int totalFlaggedMessages;
  final int totalBlockedMessages;
  final int totalProfanityCases;
  final int totalHateSpeechCases;
  final int totalSexualHarassmentCases;
  final int totalScamRiskCases;
  final int totalRoomAlertsCreated;
  final int totalAdminDismissed;
  final int totalAdminConfirmed;
  final int totalUsersSuspendedForModeration;
  final int totalAiUsedCases;

  const SpotChatModerationSummary({
    required this.totalModeratedMessages,
    required this.totalFlaggedMessages,
    required this.totalBlockedMessages,
    required this.totalProfanityCases,
    required this.totalHateSpeechCases,
    required this.totalSexualHarassmentCases,
    required this.totalScamRiskCases,
    required this.totalRoomAlertsCreated,
    required this.totalAdminDismissed,
    required this.totalAdminConfirmed,
    required this.totalUsersSuspendedForModeration,
    required this.totalAiUsedCases,
  });

  factory SpotChatModerationSummary.fromJson(Map<String, dynamic> json) {
    int parseInt(String key) => int.tryParse('${json[key] ?? 0}') ?? 0;

    return SpotChatModerationSummary(
      totalModeratedMessages: parseInt('total_moderated_messages'),
      totalFlaggedMessages: parseInt('total_flagged_messages'),
      totalBlockedMessages: parseInt('total_blocked_messages'),
      totalProfanityCases: parseInt('total_profanity_cases'),
      totalHateSpeechCases: parseInt('total_hate_speech_cases'),
      totalSexualHarassmentCases: parseInt('total_sexual_harassment_cases'),
      totalScamRiskCases: parseInt('total_scam_risk_cases'),
      totalRoomAlertsCreated: parseInt('total_room_alerts_created'),
      totalAdminDismissed: parseInt('total_admin_dismissed'),
      totalAdminConfirmed: parseInt('total_admin_confirmed'),
      totalUsersSuspendedForModeration:
          parseInt('total_users_suspended_for_moderation'),
      totalAiUsedCases: parseInt('total_ai_used_cases'),
    );
  }
}

class SpotChatModerationTrendPoint {
  final String date;
  final int totalModerated;
  final int flagged;
  final int blocked;
  final int profanity;
  final int hateSpeech;
  final int sexualHarassment;
  final int scamRisk;
  final int aiUsed;

  const SpotChatModerationTrendPoint({
    required this.date,
    required this.totalModerated,
    required this.flagged,
    required this.blocked,
    required this.profanity,
    required this.hateSpeech,
    required this.sexualHarassment,
    required this.scamRisk,
    required this.aiUsed,
  });

  factory SpotChatModerationTrendPoint.fromJson(Map<String, dynamic> json) {
    int parseInt(String key) => int.tryParse('${json[key] ?? 0}') ?? 0;

    return SpotChatModerationTrendPoint(
      date: (json['date'] ?? '-').toString(),
      totalModerated: parseInt('total_moderated'),
      flagged: parseInt('flagged'),
      blocked: parseInt('blocked'),
      profanity: parseInt('profanity'),
      hateSpeech: parseInt('hate_speech'),
      sexualHarassment: parseInt('sexual_harassment'),
      scamRisk: parseInt('scam_risk'),
      aiUsed: parseInt('ai_used'),
    );
  }
}

class SpotChatModerationTrends {
  final String range;
  final String bucket;
  final List<SpotChatModerationTrendPoint> points;

  const SpotChatModerationTrends({
    required this.range,
    required this.bucket,
    required this.points,
  });

  factory SpotChatModerationTrends.fromJson(Map<String, dynamic> json) {
    final rawPoints =
        json['points'] is List ? json['points'] as List : const [];
    return SpotChatModerationTrends(
      range: (json['range'] ?? '30d').toString(),
      bucket: (json['bucket'] ?? 'day').toString(),
      points: rawPoints
          .whereType<Map>()
          .map((e) => SpotChatModerationTrendPoint.fromJson(
                Map<String, dynamic>.from(e),
              ))
          .toList(),
    );
  }
}

class OpenAIReasonedUsageTotals {
  final int attempts;
  final int used;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final double estimatedCostUsd;

  const OpenAIReasonedUsageTotals({
    required this.attempts,
    required this.used,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.estimatedCostUsd,
  });

  factory OpenAIReasonedUsageTotals.fromJson(Map<String, dynamic> json) {
    int parseInt(String key) => int.tryParse('${json[key] ?? 0}') ?? 0;
    double parseDouble(String key) => double.tryParse('${json[key] ?? 0}') ?? 0;

    return OpenAIReasonedUsageTotals(
      attempts: parseInt('attempts'),
      used: parseInt('used'),
      inputTokens: parseInt('input_tokens'),
      outputTokens: parseInt('output_tokens'),
      totalTokens: parseInt('total_tokens'),
      estimatedCostUsd: parseDouble('estimated_cost_usd'),
    );
  }
}

class OpenAIReasonedUsageBucket {
  final OpenAIReasonedUsageTotals total;
  final OpenAIReasonedUsageTotals preview;
  final OpenAIReasonedUsageTotals spotChat;

  const OpenAIReasonedUsageBucket({
    required this.total,
    required this.preview,
    required this.spotChat,
  });

  factory OpenAIReasonedUsageBucket.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> asMap(String key) =>
        Map<String, dynamic>.from((json[key] as Map?) ?? const {});

    return OpenAIReasonedUsageBucket(
      total: OpenAIReasonedUsageTotals.fromJson(asMap('total')),
      preview: OpenAIReasonedUsageTotals.fromJson(asMap('preview')),
      spotChat: OpenAIReasonedUsageTotals.fromJson(asMap('spot_chat')),
    );
  }
}

class OpenAIReasonedUsagePoint {
  final String source;
  final String label;
  final int attempts;
  final int used;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final double estimatedCostUsd;

  const OpenAIReasonedUsagePoint({
    required this.source,
    required this.label,
    required this.attempts,
    required this.used,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.estimatedCostUsd,
  });

  factory OpenAIReasonedUsagePoint.fromJson(Map<String, dynamic> json) {
    int parseInt(String key) => int.tryParse('${json[key] ?? 0}') ?? 0;
    double parseDouble(String key) => double.tryParse('${json[key] ?? 0}') ?? 0;

    return OpenAIReasonedUsagePoint(
      source: (json['source'] ?? 'preview').toString(),
      label: (json['date'] ?? json['month'] ?? '-').toString(),
      attempts: parseInt('attempts'),
      used: parseInt('used'),
      inputTokens: parseInt('input_tokens'),
      outputTokens: parseInt('output_tokens'),
      totalTokens: parseInt('total_tokens'),
      estimatedCostUsd: parseDouble('estimated_cost_usd'),
    );
  }
}

class OpenAIReasonedUsageReport {
  final double inputUsdPer1MTokens;
  final double outputUsdPer1MTokens;
  final OpenAIReasonedUsageBucket today;
  final OpenAIReasonedUsageBucket month;
  final OpenAIReasonedUsageBucket allTime;
  final List<OpenAIReasonedUsagePoint> daily;
  final List<OpenAIReasonedUsagePoint> monthly;

  const OpenAIReasonedUsageReport({
    required this.inputUsdPer1MTokens,
    required this.outputUsdPer1MTokens,
    required this.today,
    required this.month,
    required this.allTime,
    required this.daily,
    required this.monthly,
  });

  factory OpenAIReasonedUsageReport.fromJson(Map<String, dynamic> json) {
    double parseDouble(Object? value) => double.tryParse('$value') ?? 0;
    final pricing =
        Map<String, dynamic>.from((json['pricing'] as Map?) ?? const {});
    final overview =
        Map<String, dynamic>.from((json['overview'] as Map?) ?? const {});

    List<OpenAIReasonedUsagePoint> parsePoints(String key) {
      final list = (json[key] as List?) ?? const [];
      return list
          .whereType<Map>()
          .map((item) => OpenAIReasonedUsagePoint.fromJson(
              Map<String, dynamic>.from(item)))
          .toList();
    }

    return OpenAIReasonedUsageReport(
      inputUsdPer1MTokens: parseDouble(pricing['input_usd_per_1m_tokens']),
      outputUsdPer1MTokens: parseDouble(pricing['output_usd_per_1m_tokens']),
      today: OpenAIReasonedUsageBucket.fromJson(
        Map<String, dynamic>.from((overview['today'] as Map?) ?? const {}),
      ),
      month: OpenAIReasonedUsageBucket.fromJson(
        Map<String, dynamic>.from((overview['month'] as Map?) ?? const {}),
      ),
      allTime: OpenAIReasonedUsageBucket.fromJson(
        Map<String, dynamic>.from((overview['all_time'] as Map?) ?? const {}),
      ),
      daily: parsePoints('daily'),
      monthly: parsePoints('monthly'),
    );
  }
}

class SpotChatModerationAuditFeedItem {
  final int id;
  final String action;
  final String actorType;
  final int? adminUserId;
  final int? userId;
  final String? entityTable;
  final int? entityId;
  final Map<String, dynamic> metadataJson;
  final DateTime? createdAt;

  const SpotChatModerationAuditFeedItem({
    required this.id,
    required this.action,
    required this.actorType,
    required this.adminUserId,
    required this.userId,
    required this.entityTable,
    required this.entityId,
    required this.metadataJson,
    required this.createdAt,
  });

  factory SpotChatModerationAuditFeedItem.fromJson(Map<String, dynamic> json) {
    return SpotChatModerationAuditFeedItem(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      action: (json['action'] ?? '-').toString(),
      actorType: (json['actor_type'] ?? 'system').toString(),
      adminUserId: int.tryParse('${json['admin_user_id'] ?? ''}'),
      userId: int.tryParse('${json['user_id'] ?? ''}'),
      entityTable: json['entity_table']?.toString(),
      entityId: int.tryParse('${json['entity_id'] ?? ''}'),
      metadataJson: json['metadata_json'] is Map
          ? Map<String, dynamic>.from(json['metadata_json'] as Map)
          : const <String, dynamic>{},
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
    );
  }
}

class SpotChatModerationQueueItem {
  final int id;
  final int moderationLogId;
  final int? messageId;
  final int userId;
  final String spotKey;
  final int? spotEventId;
  final String rawMessage;
  final String normalizedMessage;
  final List<String> detectedCategories;
  final String severity;
  final String actionTaken;
  final bool aiUsed;
  final double? aiConfidence;
  final Map<String, dynamic>? aiResultJson;
  final List<dynamic> ruleHits;
  final String queueStatus;
  final String priority;
  final bool alertRoom;
  final bool suspensionRequired;
  final Map<String, dynamic>? reviewPayload;
  final int? reviewedByAdminId;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final DateTime? createdAt;

  const SpotChatModerationQueueItem({
    required this.id,
    required this.moderationLogId,
    required this.messageId,
    required this.userId,
    required this.spotKey,
    required this.spotEventId,
    required this.rawMessage,
    required this.normalizedMessage,
    required this.detectedCategories,
    required this.severity,
    required this.actionTaken,
    required this.aiUsed,
    required this.aiConfidence,
    required this.aiResultJson,
    required this.ruleHits,
    required this.queueStatus,
    required this.priority,
    required this.alertRoom,
    required this.suspensionRequired,
    required this.reviewPayload,
    required this.reviewedByAdminId,
    required this.reviewedAt,
    required this.reviewNote,
    required this.createdAt,
  });

  bool get isActive => queueStatus == 'pending' || queueStatus == 'open';

  factory SpotChatModerationQueueItem.fromJson(Map<String, dynamic> json) {
    return SpotChatModerationQueueItem(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      moderationLogId: int.tryParse('${json['moderation_log_id'] ?? 0}') ?? 0,
      messageId: int.tryParse('${json['message_id'] ?? ''}'),
      userId: int.tryParse('${json['user_id'] ?? 0}') ?? 0,
      spotKey: (json['spot_key'] ?? '-').toString(),
      spotEventId: int.tryParse('${json['spot_event_id'] ?? ''}'),
      rawMessage: (json['raw_message'] ?? '').toString(),
      normalizedMessage: (json['normalized_message'] ?? '').toString(),
      detectedCategories: (json['detected_categories'] is List)
          ? (json['detected_categories'] as List)
              .map((e) => e.toString())
              .toList()
          : const [],
      severity: (json['severity'] ?? 'none').toString(),
      actionTaken: (json['action_taken'] ?? 'allow').toString(),
      aiUsed: json['ai_used'] == true,
      aiConfidence: (json['ai_confidence'] is num)
          ? (json['ai_confidence'] as num).toDouble()
          : double.tryParse('${json['ai_confidence'] ?? ''}'),
      aiResultJson: json['ai_result_json'] is Map
          ? Map<String, dynamic>.from(json['ai_result_json'] as Map)
          : null,
      ruleHits: json['rule_hits'] is List
          ? List<dynamic>.from(json['rule_hits'] as List)
          : const [],
      queueStatus: (json['queue_status'] ?? 'pending').toString(),
      priority: (json['priority'] ?? 'normal').toString(),
      alertRoom: json['alert_room'] == true,
      suspensionRequired: json['suspension_required'] == true,
      reviewPayload: json['review_payload'] is Map
          ? Map<String, dynamic>.from(json['review_payload'] as Map)
          : null,
      reviewedByAdminId: int.tryParse('${json['reviewed_by_admin_id'] ?? ''}'),
      reviewedAt: DateTime.tryParse('${json['reviewed_at'] ?? ''}')?.toLocal(),
      reviewNote: (json['review_note'] ?? '').toString().trim().isEmpty
          ? null
          : (json['review_note'] ?? '').toString(),
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
    );
  }
}

class ModerationLearningQueueItem {
  final int id;
  final String sourceType;
  final int? moderationQueueId;
  final int? moderationLogId;
  final int? previewLogId;
  final int? userId;
  final String? spotKey;
  final String rawMessage;
  final String normalizedMessage;
  final List<String> currentCategories;
  final String suggestedAction;
  final List<String> suggestedCategories;
  final List<String> candidateTerms;
  final String? adminNote;
  final String status;
  final int? createdByAdminId;
  final int? reviewedByAdminId;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  const ModerationLearningQueueItem({
    required this.id,
    required this.sourceType,
    required this.moderationQueueId,
    required this.moderationLogId,
    required this.previewLogId,
    required this.userId,
    required this.spotKey,
    required this.rawMessage,
    required this.normalizedMessage,
    required this.currentCategories,
    required this.suggestedAction,
    required this.suggestedCategories,
    required this.candidateTerms,
    required this.adminNote,
    required this.status,
    required this.createdByAdminId,
    required this.reviewedByAdminId,
    required this.createdAt,
    required this.reviewedAt,
  });

  bool get isPending => status == 'pending';

  factory ModerationLearningQueueItem.fromJson(Map<String, dynamic> json) {
    List<String> parseList(String key) {
      final value = json[key];
      if (value is List) {
        return value.map((item) => item.toString()).toList();
      }
      return const [];
    }

    return ModerationLearningQueueItem(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      sourceType: (json['source_type'] ?? 'manual').toString(),
      moderationQueueId: int.tryParse('${json['moderation_queue_id'] ?? ''}'),
      moderationLogId: int.tryParse('${json['moderation_log_id'] ?? ''}'),
      previewLogId: int.tryParse('${json['preview_log_id'] ?? ''}'),
      userId: int.tryParse('${json['user_id'] ?? ''}'),
      spotKey: json['spot_key']?.toString(),
      rawMessage: (json['raw_message'] ?? '').toString(),
      normalizedMessage: (json['normalized_message'] ?? '').toString(),
      currentCategories: parseList('current_categories'),
      suggestedAction: (json['suggested_action'] ?? 'review').toString(),
      suggestedCategories: parseList('suggested_categories'),
      candidateTerms: parseList('candidate_terms'),
      adminNote: (json['admin_note'] ?? '').toString().trim().isEmpty
          ? null
          : (json['admin_note'] ?? '').toString(),
      status: (json['status'] ?? 'pending').toString(),
      createdByAdminId: int.tryParse('${json['created_by_admin_id'] ?? ''}'),
      reviewedByAdminId: int.tryParse('${json['reviewed_by_admin_id'] ?? ''}'),
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
      reviewedAt: DateTime.tryParse('${json['reviewed_at'] ?? ''}')?.toLocal(),
    );
  }
}
