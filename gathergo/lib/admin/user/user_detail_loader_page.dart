import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import '../moderation/spot_chat_moderation_api.dart';
import 'user_admin_service.dart';
import 'user_detail_page.dart';

String get baseUrl => ConfigService.getBaseUrl();

class UserDetailLoaderPage extends StatefulWidget {
  final String userId;

  // ✅ fallback จาก list
  final String fallbackName;
  final String fallbackRegDate;
  final String fallbackRegTime;
  final int fallbackProblem;

  const UserDetailLoaderPage({
    super.key,
    required this.userId,
    required this.fallbackName,
    required this.fallbackRegDate,
    required this.fallbackRegTime,
    required this.fallbackProblem,
  });

  @override
  State<UserDetailLoaderPage> createState() => _UserDetailLoaderPageState();
}

class _UserDetailLoaderPageState extends State<UserDetailLoaderPage> {
  bool _loading = true;
  String? _info;
  UserDetailModel? _user;

  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
    _load();
  }

  @override
  void dispose() {
    AdminLocaleController.languageCode.removeListener(_handleLanguageChanged);
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _t(String key, {Map<String, String> params = const {}}) {
    return AdminStrings.text(key, params: params);
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _info = null;
    });

    try {
      final adminId = await AdminSessionService.getCurrentAdminId();
      if (adminId == null || adminId <= 0) {
        throw Exception("No active admin session");
      }

      final uri = Uri.parse("$baseUrl/api/admin/users/${widget.userId}")
          .replace(queryParameters: {"admin_id": adminId.toString()});
      final results = await Future.wait([
        http.get(
          uri,
          headers: {
            "Accept": "application/json",
            "x-admin-id": adminId.toString(),
          },
        ),
        _fetchProblemCasesForUser(widget.userId),
      ]);
      final res = results[0] as http.Response;
      final problemCases = results[1] as List<UserProblemCase>;

      if (!mounted) return;

      if (res.statusCode == 200) {
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        final createdEvents = ((j["created_events"] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => UserEventMini.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        final joinedEvents = ((j["joined_events"] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => UserEventMini.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        final u = UserDetailModel(
          userId: (j["user_id"] ?? j["id"] ?? widget.userId).toString(),
          name: (j["name"] ?? j["username"] ?? "-").toString(),
          email: (j["email"] ?? "-").toString(),
          phone: (j["phone"] ?? "-").toString(),
          lastActiveAt:
              DateTime.tryParse((j["last_active_at"] ?? "").toString()) ??
                  DateTime.now(),
          address: (j["address"] ?? "-").toString(),
          houseNo: (j["address_house_no"] ?? "").toString().trim(),
          floor: (j["address_floor"] ?? "").toString().trim(),
          building: (j["address_building"] ?? "").toString().trim(),
          road: (j["address_road"] ?? "").toString().trim(),
          subdistrict: (j["address_subdistrict"] ?? "").toString().trim(),
          district: (j["address_district"] ?? "").toString().trim(),
          province: (j["address_province"] ?? "").toString().trim(),
          postalCode: (j["address_postal_code"] ?? "").toString().trim(),
          postCount: int.tryParse("${j["post_count"] ?? 0}") ?? 0,
          joinedSpotCount: int.tryParse("${j["joined_spot_count"] ?? 0}") ?? 0,
          joinedBigEventCount:
              int.tryParse("${j["joined_big_event_count"] ?? 0}") ?? 0,
          joinedCount: int.tryParse("${j["joined_count"] ?? 0}") ?? 0,
          createdEvents: createdEvents,
          joinedEvents: joinedEvents,
          problemCases: problemCases,
          problemReportCount: _effectiveProblemCount(
            backendCount: int.tryParse("${j["problem_count"] ?? 0}") ?? 0,
            cases: problemCases,
          ),
          totalKm: double.tryParse("${j["total_km"] ?? 0}") ?? 0,
          status: _effectiveStatus(
            backendStatus: (j["status"] ?? "active").toString(),
            cases: problemCases,
          ),
        );

        setState(() {
          _user = u;
          _loading = false;
        });
        return;
      }

      setState(() {
        _user = null;
        _info = _extractMessage(res.body) ??
            "Backend endpoint failed (${res.statusCode}).";
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _user = null;
        _info = "API error: $e";
        _loading = false;
      });
    }
  }

  int _effectiveProblemCount({
    required int backendCount,
    required List<UserProblemCase> cases,
  }) {
    if (cases.length > backendCount) return cases.length;
    return backendCount;
  }

  String _effectiveStatus({
    required String backendStatus,
    required List<UserProblemCase> cases,
  }) {
    if (backendStatus.toLowerCase() == 'suspended') return backendStatus;
    final hasSuspendedCase = cases.any(
      (item) => item.queueStatus.toLowerCase() == 'suspended',
    );
    return hasSuspendedCase ? 'suspended' : backendStatus;
  }

  Future<List<UserProblemCase>> _fetchProblemCasesForUser(String userId) async {
    final statuses = ['pending', 'open', 'confirmed', 'suspended'];
    final queueLists = await Future.wait(
      statuses
          .map((status) => SpotChatModerationApi.fetchQueue(status: status)),
    );

    final targetId = int.tryParse(userId) ?? 0;
    final byId = <int, UserProblemCase>{};
    for (final queue in queueLists.expand((items) => items)) {
      if (queue.userId != targetId) continue;
      byId[queue.id] = UserProblemCase(
        id: queue.id,
        spotKey: queue.spotKey,
        rawMessage: queue.rawMessage,
        severity: queue.severity,
        queueStatus: queue.queueStatus,
        detectedCategories: queue.detectedCategories,
        createdAt: queue.createdAt,
      );
    }

    final cases = byId.values.toList()
      ..sort((a, b) {
        final aTime = a.createdAt;
        final bTime = b.createdAt;
        if (aTime == null && bTime == null) return b.id.compareTo(a.id);
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
    return cases;
  }

  void _openProblemCases(UserDetailModel user) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProblemCasesSheet(user: user),
    );
  }

  Future<void> _handleSuspendAction(UserDetailModel user) async {
    final isSuspended = user.status.toLowerCase() == 'suspended';
    final actionLabel = isSuspended
        ? AdminStrings.text('unsuspend')
        : AdminStrings.text('suspension');
    final targetStatus = isSuspended
        ? AdminStrings.text('active')
        : AdminStrings.text('suspended');

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(actionLabel),
        content: Text(
          '${user.name}\n${AdminStrings.text('status')}: $targetStatus',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AdminStrings.text('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isSuspended ? Colors.green : Colors.orange,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;

    try {
      if (isSuspended) {
        await UserAdminService.unsuspendUser(user.userId);
      } else {
        await UserAdminService.suspendUser(user.userId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              isSuspended
                  ? '${user.name} ${AdminStrings.text('unsuspend')}'
                  : '${user.name} ${AdminStrings.text('suspended')}',
            ),
          ),
        );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _handleDeleteAction(UserDetailModel user) async {
    try {
      await UserAdminService.deleteUser(user.userId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text('${user.name} ${AdminStrings.text('deleted')}'),
          ),
        );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  String? _extractMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded["message"] is String) {
        return decoded["message"].toString();
      }
    } catch (_) {}
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final user = _user;
    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(_t("detail")),
          actions: [
            IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _info ?? _t("empty_information"),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: _load,
                  child: Text(_t("retry")),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_t("detail")),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Column(
        children: [
          if (_info != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              color: Colors.orangeAccent.withOpacity(0.18),
              child: Text(_info!, style: const TextStyle(fontSize: 12)),
            ),
          Expanded(
            child: UserDetailPage(
              user: user,
              onSuspend: () => _handleSuspendAction(user),
              onDelete: () => _handleDeleteAction(user),
              onSeeProblems: () {
                _openProblemCases(user);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ProblemCasesSheet extends StatelessWidget {
  final UserDetailModel user;

  const _ProblemCasesSheet({required this.user});

  String _formatDateTime(DateTime? value) {
    if (value == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year} ${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
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
              Text(
                '${AdminStrings.text("problem_reports")} (${user.problemReportCount})',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: user.problemCases.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(AdminStrings.text("empty_information")),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: user.problemCases.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = user.problemCases[index];
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        'Case #${item.id}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      item.queueStatus.toUpperCase(),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: item.queueStatus == 'suspended'
                                            ? Colors.redAccent
                                            : Colors.deepOrange,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  item.rawMessage.isEmpty
                                      ? '-'
                                      : item.rawMessage,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 8),
                                Text('Spot: ${item.spotKey}'),
                                Text('Severity: ${item.severity}'),
                                Text(
                                  'Categories: ${item.detectedCategories.isEmpty ? "-" : item.detectedCategories.join(", ")}',
                                ),
                                Text(
                                    'Date: ${_formatDateTime(item.createdAt)}'),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
