class BigEvent {
  final String id;
  final String title;
  final String description;
  final String meetingPoint;
  final String city;
  final String province;
  final String startAt;
  final String endAt;

  BigEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.meetingPoint,
    required this.city,
    required this.province,
    required this.startAt,
    required this.endAt,
  });

  factory BigEvent.fromJson(Map<String, dynamic> j) {
    return BigEvent(
      id: j["id"].toString(),
      title: (j["title"] ?? "").toString(),
      description: (j["description"] ?? "").toString(),
      meetingPoint: (j["meeting_point"] ?? "").toString(),
      city: (j["city"] ?? "").toString(),
      province: (j["province"] ?? "").toString(),
      startAt: (j["start_at"] ?? "").toString(),
      endAt: (j["end_at"] ?? "").toString(),
    );
  }
}