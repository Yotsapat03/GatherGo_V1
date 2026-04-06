import 'dart:typed_data';

enum PaymentMethod { promptPay }

PaymentMethod paymentMethodFromString(String? v) {
  return PaymentMethod.promptPay;
}

String paymentMethodToString(PaymentMethod m) {
  return 'promptPay';
}

String _two(int n) => n.toString().padLeft(2, '0');

class BigEvent {
  final String id;
  final String orgId;

  final String detail;
  final String location;

  /// ✅ วัน+เวลาเริ่มงาน (ตรงกับ DB: start_at)
  final DateTime startAt;

  /// จำนวนจำกัดผู้เข้าร่วม (ตรงกับ DB: max_participants)
  final int limitJoiner;

  final PaymentMethod paymentMethod;

  // =========================
  // ✅ Cover Image
  // =========================
  final Uint8List? coverBytes; // runtime only
  final String? coverUrl;      // from API/DB

  // =========================
  // ✅ QR
  // =========================
  final Uint8List? qrBytes; // runtime only
  final String? qrPath;     // runtime only
  final String? qrUrl;      // from API/DB

  // รูปงาน (ตอนนี้เก็บแค่จำนวนไว้ก่อน)
  final int imageCount;
  final double? distancePerLap;
  final int? numberOfLaps;
  final double? totalDistance;
  final String? legacyDistance;

  BigEvent({
    required this.id,
    required this.orgId,
    required this.detail,
    required this.location,
    required this.startAt,
    required this.limitJoiner,
    required this.paymentMethod,
    this.coverBytes,
    this.coverUrl,
    this.qrBytes,
    this.qrPath,
    this.qrUrl,
    required this.imageCount,
    this.distancePerLap,
    this.numberOfLaps,
    this.totalDistance,
    this.legacyDistance,
  });

  // =========================
  // ✅ Backward compatible
  // =========================
  // บางหน้าคุณอาจยังเรียก eventDate อยู่ -> ให้ไม่พัง
  DateTime get eventDate => startAt;

  // =========================
  // ✅ Text helpers (เอาไปโชว์ในหน้า list/detail ได้เลย)
  // =========================
  String get eventDateText => '${startAt.day}/${startAt.month}/${startAt.year}';

  String get startTimeText => '${_two(startAt.hour)}:${_two(startAt.minute)}';

  String get startAtText =>
      '${_two(startAt.day)}/${_two(startAt.month)}/${startAt.year} ${_two(startAt.hour)}:${_two(startAt.minute)}';

  String get paymentMethodLabel =>
      'PromptPay';

  // =========================
  // ✅ JSON
  // =========================
  factory BigEvent.fromJson(Map<String, dynamic> j) {
    final coverUrl = (j['cover_url'] ?? j['coverUrl'])?.toString();
    final qrUrl = (j['qr_url'] ?? j['qrUrl'])?.toString();

    // ✅ อ่านวัน+เวลาเริ่มงาน (รองรับหลาย key)
    final rawStart = j['start_at'] ?? j['startAt'] ?? j['event_date'] ?? j['eventDate'];

    DateTime parsedStart;
    if (rawStart is String && rawStart.trim().isNotEmpty) {
      parsedStart = DateTime.parse(rawStart);
    } else if (rawStart is int) {
      // บาง backend ส่งเป็น epoch millis
      parsedStart = DateTime.fromMillisecondsSinceEpoch(rawStart);
    } else {
      parsedStart = DateTime.now();
    }

    // limit รองรับหลาย key
    final rawLimit = j['limit_joiner'] ??
        j['limitJoiner'] ??
        j['max_participants'] ??
        j['maxParticipants'];

    // payment method รองรับหลาย key
    final pmRaw = j['payment_method'] ?? j['paymentMethod'];
    final distancePerLap = double.tryParse('${j['distance_per_lap'] ?? ''}');
    final numberOfLaps = int.tryParse('${j['number_of_laps'] ?? ''}');
    final totalDistance = double.tryParse('${j['total_distance'] ?? ''}');

    return BigEvent(
      id: '${j['id']}',
      orgId:
          '${j['org_id'] ?? j['orgId'] ?? j['organization_id'] ?? j['organizationId'] ?? ''}',
      detail: (j['detail'] ?? j['description'] ?? '').toString(),
      location: (j['location'] ?? j['meeting_point'] ?? j['meetingPoint'] ?? '').toString(),
      startAt: parsedStart,
      limitJoiner: int.tryParse('${rawLimit ?? 0}') ?? 0,
      paymentMethod: paymentMethodFromString(pmRaw?.toString()),
      coverUrl: (coverUrl != null && coverUrl.trim().isNotEmpty) ? coverUrl.trim() : null,
      qrUrl: (qrUrl != null && qrUrl.trim().isNotEmpty) ? qrUrl.trim() : null,
      imageCount: int.tryParse('${j['image_count'] ?? j['imageCount'] ?? 0}') ?? 0,
      distancePerLap: distancePerLap,
      numberOfLaps: numberOfLaps,
      totalDistance: totalDistance,
      legacyDistance: (j['distance'] ?? '').toString(),

      // bytes/path จะไม่มาจาก json ปกติ
      coverBytes: null,
      qrBytes: null,
      qrPath: null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'org_id': orgId,
      'detail': detail,
      'location': location,

      // ✅ ใช้ start_at ให้ตรง backend/DB
      'start_at': startAt.toIso8601String(),

      // รองรับระบบเดิมถ้ามีบางจุดใช้ event_date (optional)
      'event_date': startAt.toIso8601String(),

      'max_participants': limitJoiner,
      'limit_joiner': limitJoiner,

      'payment_method': paymentMethodToString(paymentMethod),

      'cover_url': coverUrl,
      'qr_url': qrUrl,
      'distance_per_lap': distancePerLap,
      'number_of_laps': numberOfLaps,
      'total_distance': totalDistance,

      'image_count': imageCount,
    };
  }

  BigEvent copyWith({
    String? id,
    String? orgId,
    String? detail,
    String? location,
    DateTime? startAt,
    int? limitJoiner,
    PaymentMethod? paymentMethod,
    Uint8List? coverBytes,
    String? coverUrl,
    Uint8List? qrBytes,
    String? qrPath,
    String? qrUrl,
    int? imageCount,
    double? distancePerLap,
    int? numberOfLaps,
    double? totalDistance,
    String? legacyDistance,
  }) {
    return BigEvent(
      id: id ?? this.id,
      orgId: orgId ?? this.orgId,
      detail: detail ?? this.detail,
      location: location ?? this.location,
      startAt: startAt ?? this.startAt,
      limitJoiner: limitJoiner ?? this.limitJoiner,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      coverBytes: coverBytes ?? this.coverBytes,
      coverUrl: coverUrl ?? this.coverUrl,
      qrBytes: qrBytes ?? this.qrBytes,
      qrPath: qrPath ?? this.qrPath,
      qrUrl: qrUrl ?? this.qrUrl,
      imageCount: imageCount ?? this.imageCount,
      distancePerLap: distancePerLap ?? this.distancePerLap,
      numberOfLaps: numberOfLaps ?? this.numberOfLaps,
      totalDistance: totalDistance ?? this.totalDistance,
      legacyDistance: legacyDistance ?? this.legacyDistance,
    );
  }
}
