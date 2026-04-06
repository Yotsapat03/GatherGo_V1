import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/services/admin_session_service.dart';
import '../../core/services/config_service.dart';
import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import '../moderation/spot_chat_moderation_api.dart';
import '../widgets/bidirectional_table_scroller.dart';
import 'user_detail_loader_page.dart';

class UserListPage extends StatefulWidget {
  const UserListPage({super.key});

  @override
  State<UserListPage> createState() => _UserListPageState();
}

class _UserListPageState extends State<UserListPage> {
  int _tabIndex = 0; // 0=Active, 1=Suspension
  int? _selectedRow;
  bool _loading = true;
  String? _error;
  List<_UserRow> _rows = const [];
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
    _loadUsers();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    AdminLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _searchController.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _t(String key, {Map<String, String> params = const {}}) {
    return AdminStrings.text(key, params: params);
  }

  List<_UserRow> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    List<_UserRow> statusFiltered;
    switch (_tabIndex) {
      case 1:
        statusFiltered = _rows
            .where((row) => row.isSuspended || row.problemReport > 0)
            .toList();
        statusFiltered.sort((a, b) {
          final problemCompare = b.problemReport.compareTo(a.problemReport);
          if (problemCompare != 0) return problemCompare;
          return a.userId.compareTo(b.userId);
        });
        break;
      case 0:
      default:
        statusFiltered = _rows.where((row) => !row.isSuspended).toList();
        break;
    }

    if (query.isEmpty) return statusFiltered;

    return statusFiltered.where((row) {
      return row.userId.toLowerCase().contains(query) ||
          row.userName.toLowerCase().contains(query) ||
          row.regDate.toLowerCase().contains(query) ||
          row.regTime.toLowerCase().contains(query) ||
          row.problemReport.toString().contains(query) ||
          row.status.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final adminId = await AdminSessionService.getCurrentAdminId();
      if (adminId == null || adminId <= 0) {
        throw Exception('No active admin session');
      }

      final uri = Uri.parse('${ConfigService.getBaseUrl()}/api/admin/users')
          .replace(queryParameters: {'admin_id': adminId.toString()});
      final results = await Future.wait([
        http.get(
          uri,
          headers: {
            'Accept': 'application/json',
            'x-admin-id': adminId.toString(),
          },
        ),
        _fetchProblemCaseSummary(),
      ]);
      final res = results[0] as http.Response;
      final problemSummary = results[1] as _ProblemSummary;

      if (res.statusCode != 200) {
        throw Exception(_extractMessage(res.body) ??
            'Load users failed (${res.statusCode})');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! List) {
        throw Exception('Unexpected users response');
      }

      final rows = decoded
          .whereType<Map>()
          .map((raw) => Map<String, dynamic>.from(raw))
          .map(_UserRow.fromJson)
          .map(
            (row) => row.copyWith(
              problemReport:
                  row.problemReport > (problemSummary.counts[row.lookupId] ?? 0)
                      ? row.problemReport
                      : (problemSummary.counts[row.lookupId] ?? 0),
              status: problemSummary.suspendedUserIds.contains(row.lookupId)
                  ? 'suspended'
                  : row.status,
            ),
          )
          .toList();

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _selectedRow = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<_ProblemSummary> _fetchProblemCaseSummary() async {
    final statuses = ['pending', 'open', 'confirmed', 'suspended'];
    final queueLists = await Future.wait(
      statuses
          .map((status) => SpotChatModerationApi.fetchQueue(status: status)),
    );

    final counts = <String, int>{};
    final suspendedUserIds = <String>{};
    final seenCaseIds = <int>{};

    for (final queue in queueLists.expand((items) => items)) {
      if (!seenCaseIds.add(queue.id)) continue;
      final userId = queue.userId.toString();
      counts[userId] = (counts[userId] ?? 0) + 1;
      if (queue.queueStatus.toLowerCase() == 'suspended') {
        suspendedUserIds.add(userId);
      }
    }

    return _ProblemSummary(
      counts: counts,
      suspendedUserIds: suspendedUserIds,
    );
  }

  String? _extractMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['message'] is String) {
        return decoded['message'] as String;
      }
    } catch (_) {}
    return null;
  }

  void _goDetail(_UserRow row) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserDetailLoaderPage(
          userId: row.lookupId,
          fallbackName: row.userName,
          fallbackRegDate: row.regDate,
          fallbackRegTime: row.regTime,
          fallbackProblem: row.problemReport,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Text(
          _t('user_page'),
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: _t('user_search_hint'),
                  prefixIcon: const Icon(Icons.search, color: Colors.black45),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFDDDDDD)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFBDBDBD)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _chip(_t('active'), 0, color: const Color(0xFF00C853)),
                  const SizedBox(width: 8),
                  _chip(_t('suspension'), 1, color: const Color(0xFFFF7043)),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFDDDDDD)),
                  ),
                  child: _buildBody(data),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(List<_UserRow> data) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loadUsers,
              child: Text(_t('retry')),
            ),
          ],
        ),
      );
    }

    return _buildTable(data);
  }

  Widget _chip(String text, int index, {required Color color}) {
    final active = _tabIndex == index;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _tabIndex = index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color : const Color(0xFFEFEFEF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: active ? Colors.black : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTable(List<_UserRow> data) {
    if (data.isEmpty) {
      return Center(
        child: Text(_t('no_users_found'),
            style: const TextStyle(color: Colors.black54)),
      );
    }

    return BidirectionalTableScroller(
      horizontalController: _horizontalScrollController,
      verticalController: _verticalScrollController,
      minWidth: 460,
      child: DataTable(
        headingRowHeight: 44,
        dataRowMinHeight: 52,
        dataRowMaxHeight: 52,
        columnSpacing: 12,
        headingTextStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
        dataTextStyle: const TextStyle(fontSize: 11),
        columns: [
          DataColumn(label: _tableHeader(_t('user_id'), width: 70)),
          DataColumn(label: _tableHeader(_t('user'), width: 110)),
          DataColumn(
              label: _tableHeader('${_t('date')} &\n${_t('time')}', width: 92)),
          DataColumn(
              label: _tableHeader('${_t('problem_report')}\n', width: 58)),
          DataColumn(label: _tableHeader(_t('information'), width: 72)),
        ],
        rows: List.generate(data.length, (i) {
          final row = data[i];
          final selected = _selectedRow == i;

          return DataRow(
            selected: selected,
            onSelectChanged: (selectedRow) {
              setState(() => _selectedRow = i);
              if (selectedRow == true) {
                _goDetail(row);
              }
            },
            cells: [
              DataCell(SizedBox(width: 70, child: Text(row.userId))),
              DataCell(
                SizedBox(
                  width: 110,
                  child: Text(
                    row.userName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(_dateTimeCell(row)),
              DataCell(
                SizedBox(
                  width: 58,
                  child: Text(
                    '${row.problemReport}',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 72,
                  child: InkWell(
                    onTap: () => _goDetail(row),
                    child: Text(
                      _t('detail'),
                      style: TextStyle(
                        color: Color(0xFF3D5AFE),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _tableHeader(String text, {required double width}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        softWrap: true,
      ),
    );
  }

  Widget _dateTimeCell(_UserRow row) {
    return SizedBox(
      width: 92,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            row.regDate,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            row.regTime,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _UserRow {
  final String lookupId;
  final String userId;
  final String userName;
  final String regDate;
  final String regTime;
  final int problemReport;
  final int companyEventCount;
  final String status;

  const _UserRow({
    required this.lookupId,
    required this.userId,
    required this.userName,
    required this.regDate,
    required this.regTime,
    required this.problemReport,
    required this.companyEventCount,
    required this.status,
  });

  _UserRow copyWith({
    int? problemReport,
    String? status,
  }) {
    return _UserRow(
      lookupId: lookupId,
      userId: userId,
      userName: userName,
      regDate: regDate,
      regTime: regTime,
      problemReport: problemReport ?? this.problemReport,
      companyEventCount: companyEventCount,
      status: status ?? this.status,
    );
  }

  bool get isSuspended => status.toLowerCase() == 'suspended';

  factory _UserRow.fromJson(Map<String, dynamic> json) {
    final registeredAt =
        DateTime.tryParse((json['registered_at'] ?? '').toString())?.toLocal();
    return _UserRow(
      lookupId: (json['user_id'] ?? json['id'] ?? '').toString(),
      userId: (json['user_code'] ?? json['user_id'] ?? json['id'] ?? '-')
          .toString(),
      userName: (json['name'] ?? json['email'] ?? '-').toString(),
      regDate: _formatDate(registeredAt),
      regTime: _formatTime(registeredAt),
      problemReport: int.tryParse('${json['problem_count'] ?? 0}') ?? 0,
      companyEventCount:
          int.tryParse('${json['company_event_count'] ?? 0}') ?? 0,
      status: (json['status'] ?? 'active').toString(),
    );
  }

  static String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '-';
    final day = dateTime.day.toString().padLeft(2, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final year = dateTime.year.toString();
    return '$day/$month/$year';
  }

  static String _formatTime(DateTime? dateTime) {
    if (dateTime == null) return '-';
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _ProblemSummary {
  final Map<String, int> counts;
  final Set<String> suspendedUserIds;

  const _ProblemSummary({
    required this.counts,
    required this.suspendedUserIds,
  });
}
