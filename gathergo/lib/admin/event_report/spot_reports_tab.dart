import 'package:flutter/material.dart';

import '../../core/services/admin_session_service.dart';
import '../widgets/bidirectional_table_scroller.dart';
import 'report_models.dart';
import 'report_widgets.dart';
import 'spot_report_detail_page.dart';
import 'spot_reports_api.dart';

class SpotReportsTab extends StatefulWidget {
  const SpotReportsTab({super.key});

  @override
  State<SpotReportsTab> createState() => _SpotReportsTabState();
}

class _SpotReportsTabState extends State<SpotReportsTab> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  bool _loading = true;
  String? _error;
  List<SpotLeaveFeedbackRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _verticalScrollController.dispose();
    _horizontalScrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final adminId = await AdminSessionService.getAdminId();
      if (adminId == null || adminId <= 0) {
        if (!mounted) return;
        setState(() {
          _rows = const [];
          _error = 'Please login as admin.';
          _loading = false;
        });
        return;
      }

      final rows = await SpotReportsApi.fetchBehaviorSafetyLeaveFeedback();
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  List<SpotLeaveFeedbackRow> get _filteredRows {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return _rows;

    return _rows.where((row) {
      return row.eventId.toString().contains(q) ||
          row.eventTitle.toLowerCase().contains(q) ||
          row.leaverUserName.toLowerCase().contains(q) ||
          row.reasonText.toLowerCase().contains(q) ||
          row.reasonCode.toLowerCase().contains(q) ||
          (row.reportedTargetUserName ?? '').toLowerCase().contains(q);
    }).toList();
  }

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }

  String _targetLabel(SpotLeaveFeedbackRow row) {
    if (row.reportedTargetType == 'creator') {
      return 'Creator: ${row.reportedTargetUserName ?? row.reportedTargetUserId ?? '-'}';
    }
    if (row.reportedTargetType == 'participant') {
      final target = row.reportedTargetUserName ??
          row.reportedTargetUserId?.toString() ??
          'Unknown';
      return 'Participant: $target';
    }
    return 'None';
  }

  void _openReportDetail(SpotLeaveFeedbackRow row) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SpotReportDetailPage(row: row),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          CardShell(
            child: Column(
              children: [
                SummaryField(
                    label: 'Behavior/Safety Reports', value: '${_rows.length}'),
                const SizedBox(height: 8),
                SummaryField(
                  label: 'Reported Participants',
                  value:
                      '${_rows.where((row) => row.reportedTargetType == 'participant').length}',
                ),
                const SizedBox(height: 8),
                SummaryField(
                  label: 'Reported Creators',
                  value:
                      '${_rows.where((row) => row.reportedTargetType == 'creator').length}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SearchBarMini(
            controller: _search,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            if (_error != 'Please login as admin.')
                              ElevatedButton(
                                onPressed: _load,
                                child: const Text('Retry'),
                              ),
                          ],
                        ),
                      )
                    : rows.isEmpty
                        ? const EmptyInfo()
                        : Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAEAEA),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.all(8),
                            child: BidirectionalTableScroller(
                              horizontalController: _horizontalScrollController,
                              verticalController: _verticalScrollController,
                              minWidth: 920,
                              child: DataTable(
                                headingRowHeight: 32,
                                dataRowMinHeight: 44,
                                dataRowMaxHeight: 56,
                                headingTextStyle: const TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w700),
                                dataTextStyle: const TextStyle(fontSize: 11),
                                columns: const [
                                  DataColumn(label: Text('Event')),
                                  DataColumn(label: Text('Title')),
                                  DataColumn(label: Text('Leaver')),
                                  DataColumn(label: Text('Reason')),
                                  DataColumn(label: Text('Created At')),
                                  DataColumn(label: Text('Target')),
                                  DataColumn(label: Text('Report Detail')),
                                ],
                                rows: rows
                                    .map(
                                      (row) => DataRow(
                                        cells: [
                                          DataCell(Text('${row.eventId}')),
                                          DataCell(SizedBox(
                                              width: 150,
                                              child: Text(row.eventTitle))),
                                          DataCell(Text(row.leaverUserName)),
                                          DataCell(SizedBox(
                                              width: 180,
                                              child: Text(row.reasonText))),
                                          DataCell(
                                              Text(_formatDate(row.createdAt))),
                                          DataCell(SizedBox(
                                              width: 160,
                                              child: Text(_targetLabel(row)))),
                                          DataCell(
                                            row.hasReportDetail
                                                ? InkWell(
                                                    onTap: () =>
                                                        _openReportDetail(row),
                                                    child: const Text(
                                                      'View',
                                                      style: TextStyle(
                                                        color:
                                                            Color(0xFF2563EB),
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        decoration:
                                                            TextDecoration
                                                                .underline,
                                                      ),
                                                    ),
                                                  )
                                                : const Text('-'),
                                          ),
                                        ],
                                      ),
                                    )
                                    .toList(),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
