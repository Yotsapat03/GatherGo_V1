import 'dart:convert';

import 'package:flutter/material.dart';

import '../localization/admin_strings.dart';

class UserDetailModel {
  final String userId;
  final String name;
  final String email;
  final String phone;

  final DateTime lastActiveAt;
  final String address;
  final String houseNo;
  final String floor;
  final String building;
  final String road;
  final String subdistrict;
  final String district;
  final String province;
  final String postalCode;

  final int postCount;
  final int joinedSpotCount;
  final int joinedBigEventCount;
  final int joinedCount;

  final List<UserEventMini> createdEvents;
  final List<UserEventMini> joinedEvents;
  final List<UserProblemCase> problemCases;

  final int problemReportCount;
  final double totalKm;

  final String status;

  const UserDetailModel({
    required this.userId,
    required this.name,
    required this.email,
    required this.phone,
    required this.lastActiveAt,
    required this.address,
    required this.houseNo,
    required this.floor,
    required this.building,
    required this.road,
    required this.subdistrict,
    required this.district,
    required this.province,
    required this.postalCode,
    required this.postCount,
    required this.joinedSpotCount,
    required this.joinedBigEventCount,
    required this.joinedCount,
    required this.createdEvents,
    required this.joinedEvents,
    required this.problemCases,
    required this.problemReportCount,
    required this.totalKm,
    required this.status,
  });
}

class UserProblemCase {
  final int id;
  final String spotKey;
  final String rawMessage;
  final String severity;
  final String queueStatus;
  final List<String> detectedCategories;
  final DateTime? createdAt;

  const UserProblemCase({
    required this.id,
    required this.spotKey,
    required this.rawMessage,
    required this.severity,
    required this.queueStatus,
    required this.detectedCategories,
    required this.createdAt,
  });
}

class UserEventMini {
  final String type;
  final int id;
  final String title;
  final String description;
  final String location;
  final String date;
  final String time;
  final String status;
  final String imageBase64;
  final String? subtitle;
  final String? imageUrl;
  const UserEventMini({
    required this.type,
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.date,
    required this.time,
    required this.status,
    required this.imageBase64,
    this.subtitle,
    this.imageUrl,
  });

  factory UserEventMini.fromJson(Map<String, dynamic> json) {
    final type = (json["type"] ?? json["item_type"] ?? "SPOT").toString();
    final date = (json["date"] ?? "").toString().trim();
    final time = (json["time"] ?? "").toString().trim();
    final location = (json["location"] ?? "").toString().trim();
    final subtitleParts = <String>[
      if (date.isNotEmpty) date,
      if (time.isNotEmpty) time,
      if (location.isNotEmpty) location,
    ];
    return UserEventMini(
      type: type,
      id: int.tryParse("${json["id"] ?? 0}") ?? 0,
      title: (json["title"] ?? "-").toString(),
      description: (json["description"] ?? "").toString().trim(),
      location: location,
      date: date,
      time: time,
      status: (json["status"] ?? "").toString().trim(),
      imageBase64:
          (json["image_base64"] ?? json["imageBase64"] ?? "").toString().trim(),
      subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(" - "),
      imageUrl: (json["image_url"] ?? json["imageUrl"] ?? "").toString().trim(),
    );
  }
}

/// ✅ Content only (ไม่มี Scaffold / ไม่มี AppBar)
class UserDetailPage extends StatelessWidget {
  final UserDetailModel user;

  final VoidCallback? onSuspend;
  final VoidCallback? onDelete;
  final VoidCallback? onSeeProblems;

  const UserDetailPage({
    super.key,
    required this.user,
    this.onSuspend,
    this.onDelete,
    this.onSeeProblems,
  });

  String _fmtDateTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${two(dt.day)}/${two(dt.month)}/${dt.year}  ${two(dt.hour)}:${two(dt.minute)}";
  }

  String _displayAddress() {
    final parts = <String>[
      if (user.houseNo.isNotEmpty)
        '${AdminStrings.text('house_no_prefix')} ${user.houseNo}',
      if (user.floor.isNotEmpty)
        '${AdminStrings.text('floor_prefix')} ${user.floor}',
      if (user.building.isNotEmpty)
        '${AdminStrings.text('building_prefix')} ${user.building}',
      if (user.road.isNotEmpty)
        '${AdminStrings.text('road_prefix')} ${user.road}',
      if (user.subdistrict.isNotEmpty)
        '${AdminStrings.text('subdistrict_prefix')} ${user.subdistrict}',
      if (user.district.isNotEmpty)
        '${AdminStrings.text('district_prefix')} ${user.district}',
      if (user.province.isNotEmpty)
        '${AdminStrings.text('province_prefix')} ${user.province}',
      if (user.postalCode.isNotEmpty)
        '${AdminStrings.text('postal_code_prefix')} ${user.postalCode}',
    ];
    if (parts.isNotEmpty) return parts.join(', ');
    if (user.address.trim().isNotEmpty && user.address.trim() != '-') {
      return user.address;
    }
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    final isSuspended = user.status.toLowerCase() == 'suspended';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Card(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _AvatarCircle(name: user.name),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    _InfoLine(
                        label: AdminStrings.text("email"), value: user.email),
                    _InfoLine(
                        label: AdminStrings.text("phone"), value: user.phone),
                    _InfoLine(
                        label: AdminStrings.text("user_id"),
                        value: user.userId),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Card(
                child: _MiniBox(
                  title: AdminStrings.text("last_active"),
                  value: _fmtDateTime(user.lastActiveAt),
                  icon: Icons.schedule,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Card(
                child: _MiniBox(
                  title: AdminStrings.text("status"),
                  value: isSuspended
                      ? AdminStrings.text("suspended")
                      : AdminStrings.text("active"),
                  icon: isSuspended ? Icons.block : Icons.verified,
                  valueColor: isSuspended ? Colors.redAccent : Colors.green,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Card(
          title: AdminStrings.text("profile"),
          child: Column(
            children: [
              _LabelValue(
                label: AdminStrings.text("address"),
                child: Text(
                  _displayAddress(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _StatChip(
                    label: AdminStrings.text("posts"),
                    value: user.postCount.toString(),
                    icon: Icons.article_outlined,
                  ),
                  _StatChip(
                    label: AdminStrings.text("spot_joined"),
                    value: user.joinedSpotCount.toString(),
                    icon: Icons.group_outlined,
                  ),
                  _StatChip(
                    label: AdminStrings.text("big_event_joined"),
                    value: user.joinedBigEventCount.toString(),
                    icon: Icons.emoji_events_outlined,
                  ),
                  _StatChip(
                    label: AdminStrings.text("problems"),
                    value: user.problemReportCount.toString(),
                    icon: Icons.report_problem_outlined,
                    accentColor: const Color(0xFFFDECEC),
                    borderColor: const Color(0xFFF3B7B7),
                    iconColor: const Color(0xFFC62828),
                    valueColor: const Color(0xFFB71C1C),
                    labelColor: const Color(0xFF8A3030),
                    onTap: onSeeProblems,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Card(
            title: AdminStrings.text("created"),
            child: _HorizontalEventList(items: user.createdEvents)),
        const SizedBox(height: 12),
        _Card(
            title: AdminStrings.text("joined"),
            child: _HorizontalEventList(items: user.joinedEvents)),
        const SizedBox(height: 12),
        _Card(
          title: AdminStrings.text("records"),
          child: Column(
            children: [
              _RecordTile(
                title: AdminStrings.text("total_km_record"),
                value: "${user.totalKm.toStringAsFixed(0)} Km",
                subtitle: AdminStrings.text("completed_created_joined_only"),
                icon: Icons.route_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: onSuspend,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSuspended ? Colors.grey : Colors.orange,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: Icon(isSuspended ? Icons.lock_open : Icons.block),
                label: Text(isSuspended
                    ? AdminStrings.text("unsuspend")
                    : AdminStrings.text("suspension")),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => AlertDialog(
                      title: Text(AdminStrings.text("delete_account")),
                      content:
                          Text(AdminStrings.text("delete_account_confirm")),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(AdminStrings.text("cancel")),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent),
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(AdminStrings.text("delete")),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) onDelete?.call();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.delete_outline),
                label: Text(AdminStrings.text("delete")),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String? title;
  final Widget child;

  const _Card({required this.child, this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: title == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                    child: Text(title!,
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                const SizedBox(height: 12),
                child,
              ],
            ),
    );
  }
}

class _AvatarCircle extends StatelessWidget {
  final String name;
  const _AvatarCircle({required this.name});

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? "U" : name.trim()[0].toUpperCase();
    return Container(
      width: 62,
      height: 62,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.blue.withOpacity(0.12),
        border: Border.all(color: Colors.blue.withOpacity(0.18)),
      ),
      child: Center(
        child: Text(letter,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final String label;
  final String value;
  const _InfoLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final v = value.trim().isEmpty ? "-" : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 62,
            child: Text(
              "$label:",
              style: TextStyle(
                  color: Colors.grey.shade700, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniBox extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _MiniBox({
    required this.title,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.black54),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                value,
                style:
                    TextStyle(fontWeight: FontWeight.w800, color: valueColor),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final Widget child;
  const _LabelValue({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            "$label:",
            style: TextStyle(
                color: Colors.grey.shade700, fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? accentColor;
  final Color? borderColor;
  final Color? iconColor;
  final Color? valueColor;
  final Color? labelColor;
  final VoidCallback? onTap;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    this.accentColor,
    this.borderColor,
    this.iconColor,
    this.valueColor,
    this.labelColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      width: 150,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: accentColor ?? Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor ?? Colors.black12),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor ?? Colors.black54, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: labelColor ?? Colors.grey.shade700,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );

    return SizedBox(
      width: 150,
      child: onTap == null
          ? child
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: child,
            ),
    );
  }
}

class _HorizontalEventList extends StatefulWidget {
  final List<UserEventMini> items;
  const _HorizontalEventList({required this.items});

  @override
  State<_HorizontalEventList> createState() => _HorizontalEventListState();
}

class _HorizontalEventListState extends State<_HorizontalEventList> {
  late final ScrollController _scrollController;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_updateScrollButtons);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollButtons());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateScrollButtons)
      ..dispose();
    super.dispose();
  }

  void _updateScrollButtons() {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    final canLeft = position.pixels > 8;
    final canRight = position.pixels < position.maxScrollExtent - 8;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  Future<void> _scrollBy(double delta) async {
    if (!_scrollController.hasClients) return;
    final target = (_scrollController.offset + delta).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    await _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _showDetails(BuildContext context, UserEventMini item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EventDetailSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) {
      return Container(
        height: 88,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7F8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: Center(
          child: Text(
            AdminStrings.text("empty_information"),
            style: TextStyle(
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 252,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ScrollArrowButton(
                  icon: Icons.chevron_left_rounded,
                  enabled: _canScrollLeft,
                  onTap: () => _scrollBy(-220),
                ),
                const SizedBox(width: 8),
                _ScrollArrowButton(
                  icon: Icons.chevron_right_rounded,
                  enabled: _canScrollRight,
                  onTap: () => _scrollBy(220),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
              itemCount: widget.items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final it = widget.items[i];
                final typeLabel = it.type == "BIG_EVENT"
                    ? AdminStrings.text("big_event_label")
                    : AdminStrings.text("spot_label");
                return InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => _showDetails(context, it),
                  child: Container(
                    width: 148,
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.black12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(14),
                              child: SizedBox(
                                width: 132,
                                height: 132,
                                child: _ActivityImage(
                                  imageUrl: it.imageUrl,
                                  imageBase64: it.imageBase64,
                                ),
                              ),
                            ),
                            Positioned(
                              left: 8,
                              top: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.58),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  typeLabel,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              it.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ScrollArrowButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _ScrollArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? Colors.grey.shade200 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.black12),
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? Colors.black87 : Colors.black26,
        ),
      ),
    );
  }
}

class _ActivityImage extends StatelessWidget {
  final String? imageUrl;
  final String? imageBase64;

  const _ActivityImage({this.imageUrl, this.imageBase64});

  @override
  Widget build(BuildContext context) {
    final b64 = (imageBase64 ?? "")
        .trim()
        .replaceFirst(RegExp(r'^data:image\/[^;]+;base64,'), '');
    if (b64.isNotEmpty) {
      try {
        return Image.memory(
          base64Decode(b64),
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(),
        );
      } catch (_) {}
    }
    final image = (imageUrl ?? "").trim();
    if (image.startsWith("http://") || image.startsWith("https://")) {
      return Image.network(
        image,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    if (image.startsWith("assets/")) {
      return Image.asset(
        image,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Container(
      color: const Color(0xFFF1F3F5),
      child: const Center(
        child: Icon(Icons.image_outlined, color: Colors.black45, size: 34),
      ),
    );
  }
}

class _EventDetailSheet extends StatelessWidget {
  final UserEventMini item;

  const _EventDetailSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    final meta = <String>[
      if (item.type.isNotEmpty)
        item.type == "BIG_EVENT"
            ? AdminStrings.text("big_event_label")
            : AdminStrings.text("spot_label"),
      if (item.status.isNotEmpty) item.status,
    ].join(" - ");

    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    width: 220,
                    height: 220,
                    child: _ActivityImage(
                      imageUrl: item.imageUrl,
                      imageBase64: item.imageBase64,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                item.title,
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  meta,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ],
              if (item.date.isNotEmpty) ...[
                const SizedBox(height: 16),
                _DetailLine(label: AdminStrings.text("date"), value: item.date),
              ],
              if (item.time.isNotEmpty) ...[
                const SizedBox(height: 10),
                _DetailLine(label: AdminStrings.text("time"), value: item.time),
              ],
              if (item.location.isNotEmpty) ...[
                const SizedBox(height: 10),
                _DetailLine(
                    label: AdminStrings.text("location"), value: item.location),
              ],
              const SizedBox(height: 10),
              _DetailLine(
                label: AdminStrings.text("description"),
                value: item.description.isEmpty ? "-" : item.description,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  final String label;
  final String value;

  const _DetailLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _RecordTile extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData icon;

  const _RecordTile({
    required this.title,
    required this.value,
    this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.black54),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style:
                        TextStyle(color: Colors.grey.shade700, fontSize: 12)),
                const SizedBox(height: 6),
                Text(value,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
