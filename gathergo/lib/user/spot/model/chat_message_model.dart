enum ModerationStatus {
  visible,
  warning,
  hidden,
  blocked,
}

enum RiskLevel {
  safe,
  suspicious,
  phishing,
}

enum PhishingScanStatus {
  notScanned,
  scanning,
  scanned,
  failed,
}

class ChatMessageModel {
  final String id;
  final String? clientMessageKey;
  final String userId;
  final String body;
  final DateTime createdAt;
  final bool containsUrl;
  final ModerationStatus moderationStatus;
  final RiskLevel riskLevel;
  final PhishingScanStatus phishingScanStatus;
  final String? phishingScanReason;

  const ChatMessageModel({
    required this.id,
    this.clientMessageKey,
    required this.userId,
    required this.body,
    required this.createdAt,
    required this.containsUrl,
    required this.moderationStatus,
    required this.riskLevel,
    required this.phishingScanStatus,
    this.phishingScanReason,
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final rawReason = _readValue(
      json,
      const ['phishingScanReason', 'phishing_scan_reason'],
    );

    return ChatMessageModel(
      id: _asString(_readValue(json, const ['id'])),
      clientMessageKey: _asNullableString(
        _readValue(
          json,
          const [
            'clientMessageKey',
            'client_message_key',
            'clientMessageId',
            'client_message_id',
          ],
        ),
      ),
      userId: _asString(_readValue(json, const ['userId', 'user_id'])),
      body: _asString(_readValue(json, const ['body', 'message'])),
      createdAt: _parseDateTime(
            _readValue(json, const ['createdAt', 'created_at']),
          ) ??
          DateTime.now(),
      containsUrl: _parseBool(
            _readValue(json, const ['containsUrl', 'contains_url']),
          ) ??
          false,
      moderationStatus: _parseModerationStatus(
        _asString(
          _readValue(json, const ['moderationStatus', 'moderation_status']),
        ),
      ),
      riskLevel: _parseRiskLevel(
        _asString(_readValue(json, const ['riskLevel', 'risk_level'])),
      ),
      phishingScanStatus: _parsePhishingScanStatus(
        _asString(
          _readValue(
            json,
            const ['phishingScanStatus', 'phishing_scan_status'],
          ),
        ),
      ),
      phishingScanReason: _asNullableString(rawReason),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'client_message_key': clientMessageKey,
      'user_id': userId,
      'body': body,
      'created_at': createdAt.toIso8601String(),
      'contains_url': containsUrl,
      'moderation_status': moderationStatus.name,
      'risk_level': riskLevel.name,
      'phishing_scan_status': _scanStatusToJson(phishingScanStatus),
      'phishing_scan_reason': phishingScanReason,
    };
  }

  static List<ChatMessageModel> listFromJson(dynamic raw) {
    if (raw is! List) return const <ChatMessageModel>[];
    return raw
        .whereType<Map>()
        .map((item) => ChatMessageModel.fromJson(Map<String, dynamic>.from(item)))
        .toList();
  }

  static dynamic _readValue(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (json.containsKey(key)) {
        return json[key];
      }
    }
    return null;
  }

  static String _asString(dynamic value) {
    if (value == null) return '';
    return value.toString().trim();
  }

  static String? _asNullableString(dynamic value) {
    final text = _asString(value);
    return text.isEmpty ? null : text;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  static bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    if (value is num) return value == 1;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true' || normalized == '1') return true;
      if (normalized == 'false' || normalized == '0') return false;
    }
    return null;
  }

  static ModerationStatus _parseModerationStatus(String value) {
    switch (value.toLowerCase()) {
      case 'warning':
        return ModerationStatus.warning;
      case 'hidden':
        return ModerationStatus.hidden;
      case 'blocked':
        return ModerationStatus.blocked;
      case 'visible':
      default:
        return ModerationStatus.visible;
    }
  }

  static RiskLevel _parseRiskLevel(String value) {
    switch (value.toLowerCase()) {
      case 'suspicious':
        return RiskLevel.suspicious;
      case 'phishing':
        return RiskLevel.phishing;
      case 'safe':
      default:
        return RiskLevel.safe;
    }
  }

  static PhishingScanStatus _parsePhishingScanStatus(String value) {
    switch (value.toLowerCase()) {
      case 'scanning':
        return PhishingScanStatus.scanning;
      case 'scanned':
        return PhishingScanStatus.scanned;
      case 'failed':
        return PhishingScanStatus.failed;
      case 'not_scanned':
      default:
        return PhishingScanStatus.notScanned;
    }
  }

  static String _scanStatusToJson(PhishingScanStatus status) {
    switch (status) {
      case PhishingScanStatus.notScanned:
        return 'not_scanned';
      case PhishingScanStatus.scanning:
        return 'scanning';
      case PhishingScanStatus.scanned:
        return 'scanned';
      case PhishingScanStatus.failed:
        return 'failed';
    }
  }
}
