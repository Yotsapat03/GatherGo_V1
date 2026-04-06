import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../core/services/config_service.dart';
import '../../core/services/admin_session_service.dart';
import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import '../bigevent/organizer_detail_page.dart';
import '../models/organization.dart';
import '../user/user_detail_loader_page.dart';
import '../widgets/bidirectional_table_scroller.dart';
import 'registrations_api.dart';
import 'report_models.dart';
import 'report_widgets.dart';

class RegistrationsTab extends StatefulWidget {
  const RegistrationsTab({super.key});

  @override
  State<RegistrationsTab> createState() => _RegistrationsTabState();
}

class _RegistrationsTabState extends State<RegistrationsTab> {
  static const List<String> _monthKeys = <String>[
    '',
    'january',
    'february',
    'march',
    'april',
    'may',
    'june',
    'july',
    'august',
    'september',
    'october',
    'november',
    'december',
  ];

  int? selectedIndex;
  bool _loading = true;
  bool _showChart = false;
  String? _error;
  RegistrationSummary _summary = const RegistrationSummary(
    totalUsersExcludingAdmin: 0,
    totalRegistrationsTodayBangkok: 0,
    totalEvents: 0,
    totalSpot: 0,
    totalBigEvent: 0,
  );
  List<ReportRow> _rows = const [];

  final TextEditingController search = TextEditingController();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  String _eventTypeFilterKey = 'all_event_created';
  int _selectedMonthValue =
      DateTime.now().toUtc().add(const Duration(hours: 7)).month;
  String _selectedYear =
      DateTime.now().toUtc().add(const Duration(hours: 7)).year.toString();

  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
    _load();
  }

  @override
  void dispose() {
    AdminLocaleController.languageCode.removeListener(_handleLanguageChanged);
    search.dispose();
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

  String get _allMonths => _t('all_months');
  String get _allYears => _t('all_years');
  String get _allEventCreated => _t('all_event_created');
  String get _allSpot => _t('all_spot');
  String get _onlyBigEvents => _t('only_big_events');
  List<String> get _monthOptions => <String>[
        _allMonths,
        _t('january'),
        _t('february'),
        _t('march'),
        _t('april'),
        _t('may'),
        _t('june'),
        _t('july'),
        _t('august'),
        _t('september'),
        _t('october'),
        _t('november'),
        _t('december'),
      ];
  String get _selectedMonth => _monthOptions[_selectedMonthValue];
  String get _eventTypeFilter {
    switch (_eventTypeFilterKey) {
      case 'all_spot':
        return _allSpot;
      case 'only_big_events':
        return _onlyBigEvents;
      default:
        return _allEventCreated;
    }
  }

  int? get _selectedMonthNumber {
    return _selectedMonthValue == 0 ? null : _selectedMonthValue;
  }

  List<int> get _availableYears {
    final years = <int>{};
    for (final row in _rows) {
      final eventDate = row.eventDateBangkok;
      if (eventDate != null) {
        years.add(eventDate.year);
      }
    }

    final sortedYears = years.toList()..sort((a, b) => b.compareTo(a));
    return sortedYears;
  }

  List<String> get _yearOptions {
    return [
      _allYears,
      ..._availableYears.map((year) => year.toString()),
    ];
  }

  void _resetTableScroll() {
    if (_verticalScrollController.hasClients) {
      _verticalScrollController.jumpTo(0);
    }
    if (_horizontalScrollController.hasClients) {
      _horizontalScrollController.jumpTo(0);
    }
  }

  void _applyFilterChange(VoidCallback update) {
    setState(update);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _resetTableScroll();
    });
  }

  String _resolveSelectedYear(String currentSelection) {
    if (currentSelection == _allYears) {
      return _allYears;
    }

    final availableYears = _availableYears;
    if (availableYears.isEmpty) {
      return _allYears;
    }

    final availableYearLabels =
        availableYears.map((year) => year.toString()).toSet();
    if (availableYearLabels.contains(currentSelection)) {
      return currentSelection;
    }

    return availableYears.first.toString();
  }

  bool _matchesMonthYear(ReportRow row) {
    final eventDate = row.eventDateBangkok;
    final selectedMonth = _selectedMonthNumber;
    final selectedYear =
        _selectedYear == _allYears ? null : int.tryParse(_selectedYear);

    if (selectedMonth == null && selectedYear == null) {
      return true;
    }

    if (eventDate == null) {
      return false;
    }

    final monthMatches =
        selectedMonth == null || eventDate.month == selectedMonth;
    final yearMatches = selectedYear == null || eventDate.year == selectedYear;
    return monthMatches && yearMatches;
  }

  bool _matchesEventType(ReportRow row) {
    switch (_eventTypeFilterKey) {
      case 'all_spot':
        return row.type == 'Spot';
      case 'only_big_events':
        return row.type == 'Big event';
      case 'all_event_created':
      default:
        return true;
    }
  }

  String _displayType(String rawType) {
    if (rawType.trim().toLowerCase() == 'spot') {
      return _t('spot_label');
    }
    if (rawType.trim().toLowerCase() == 'big event' ||
        rawType.trim().toLowerCase() == 'big_event') {
      return _t('big_event_label');
    }
    return rawType;
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
          _error = _t('please_log_in_admin_again');
          _loading = false;
        });
        return;
      }

      final response = await RegistrationsApi.fetchRegistrationsReport();
      if (!mounted) return;
      setState(() {
        _summary = response.summary;
        _rows = response.rows;
        _selectedYear = _resolveSelectedYear(_selectedYear);
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

  Future<void> _openCreatorDetail(ReportRow row) async {
    final kind = row.creatorKind.trim().toLowerCase();
    final creatorId = row.creatorId.trim();
    if (creatorId.isEmpty || creatorId == '-') return;

    if (kind == 'user') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => UserDetailLoaderPage(
            userId: creatorId,
            fallbackName: row.creator,
            fallbackRegDate: row.date,
            fallbackRegTime: '',
            fallbackProblem: 0,
          ),
        ),
      );
      return;
    }

    if (kind == 'organization') {
      final org = await _loadOrganizationForCreator(row);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrganizerDetailPage(org: org),
        ),
      );
    }
  }

  Future<Organization> _loadOrganizationForCreator(ReportRow row) async {
    final fallback = Organization(
      id: row.creatorId,
      name: row.creator,
      email: '',
      phone: '',
      address: '',
      businessProfile: '',
      organizer: '',
    );

    try {
      final uri = Uri.parse(
        '${ConfigService.getBaseUrl()}/api/organizations/${row.creatorId}',
      );
      final res = await http.get(
        uri,
        headers: const {
          'Accept': 'application/json',
        },
      );
      if (res.statusCode != 200) return fallback;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return fallback;
      return Organization.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return fallback;
    }
  }

  List<ReportRow> get filtered {
    final q = search.text.trim().toLowerCase();
    return _rows.where((r) {
      final monthYearOk = _matchesMonthYear(r);
      final typeOk = _matchesEventType(r);
      final haystack = [
        r.eventId,
        r.date,
        r.name,
        r.registeredUsers.toString(),
        r.type,
        r.status,
        r.creator,
      ].join(' ').toLowerCase();
      final textOk = q.isEmpty || haystack.contains(q);
      return monthYearOk && typeOk && textOk;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final data = filtered;

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 8),
                            if (_error != _t('please_log_in_admin_again'))
                              ElevatedButton(
                                onPressed: _load,
                                child: Text(_t('retry')),
                              ),
                          ],
                        ),
                      )
                    : data.isEmpty
                        ? Column(
                            children: [
                              EventSummaryCard(summary: _summary),
                              const SizedBox(height: 8),
                              _buildMonthYearFilters(),
                              const SizedBox(height: 8),
                              _buildViewToggle(),
                              const SizedBox(height: 8),
                              _buildEventTypeFilter(),
                              const SizedBox(height: 8),
                              const Expanded(child: EmptyInfo()),
                            ],
                          )
                        : Column(
                            children: [
                              _buildMonthYearFilters(),
                              const SizedBox(height: 8),
                              _buildViewToggle(),
                              const SizedBox(height: 8),
                              Expanded(
                                child: _showChart
                                    ? _buildChartView(data)
                                    : Column(
                                        children: [
                                          SearchBarMini(
                                            controller: search,
                                            onChanged: (_) => setState(() {}),
                                          ),
                                          const SizedBox(height: 8),
                                          EventSummaryCard(summary: _summary),
                                          const SizedBox(height: 8),
                                          Expanded(child: _buildTable(data)),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: 10),
                              _buildEventTypeFilter(),
                            ],
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(List<ReportRow> data) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEAEAEA),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(8),
      child: BidirectionalTableScroller(
        horizontalController: _horizontalScrollController,
        verticalController: _verticalScrollController,
        minWidth: 980,
        child: DataTable(
          headingRowHeight: 28,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 36,
          headingTextStyle:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          dataTextStyle: const TextStyle(fontSize: 11),
          columns: [
            DataColumn(label: Text(_t('event_id'))),
            DataColumn(label: Text(_t('date'))),
            DataColumn(label: Text(_t('spot_name'))),
            DataColumn(label: Text('${_t('registered_users')}\n')),
            DataColumn(label: Text(_t('type'))),
            DataColumn(label: Text(_t('status'))),
            DataColumn(label: Text(_t('creator_id'))),
            DataColumn(label: Text(_t('creator'))),
          ],
          rows: List.generate(data.length, (i) {
            final r = data[i];
            final canOpenUserDetail = r.creatorKind.toLowerCase() == 'user' &&
                r.creatorId.trim().isNotEmpty &&
                r.creatorId.trim() != '-';
            final canOpenOrganizationDetail =
                r.creatorKind.toLowerCase() == 'organization' &&
                    r.creatorId.trim().isNotEmpty &&
                    r.creatorId.trim() != '-';
            final canOpenCreatorDetail =
                canOpenUserDetail || canOpenOrganizationDetail;
            return DataRow(
              selected: selectedIndex == i,
              onSelectChanged: (_) => setState(() => selectedIndex = i),
              cells: [
                DataCell(Text(r.eventId,
                    style: const TextStyle(color: Color(0xFF3D5AFE)))),
                DataCell(Text(r.date)),
                DataCell(Text(r.name)),
                DataCell(Text('${r.registeredUsers}')),
                DataCell(Text(_displayType(r.type))),
                DataCell(Text(r.status)),
                DataCell(Text(r.creatorId)),
                DataCell(
                  canOpenCreatorDetail
                      ? InkWell(
                          onTap: () {
                            _openCreatorDetail(r);
                          },
                          child: Text(
                            r.creator,
                            style: const TextStyle(
                              color: Color(0xFF3D5AFE),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        )
                      : Text(
                          r.creator,
                          style: const TextStyle(color: Color(0xFF3D5AFE)),
                        ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  Widget _buildMonthYearFilters() {
    return Row(
      children: [
        Expanded(
          child: MiniDropdown(
            value: _selectedMonth,
            items: _monthOptions,
            onChanged: (value) => _applyFilterChange(() {
              _selectedMonthValue = _monthOptions.indexOf(value);
            }),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MiniDropdown(
            value: _selectedYear,
            items: _yearOptions,
            onChanged: (value) =>
                _applyFilterChange(() => _selectedYear = value),
          ),
        ),
      ],
    );
  }

  Widget _buildViewToggle() {
    return Row(
      children: [
        Expanded(
          child: _ViewModeButton(
            label: _t('table'),
            icon: Icons.table_rows_outlined,
            selected: !_showChart,
            onTap: () => setState(() => _showChart = false),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ViewModeButton(
            label: _t('graph'),
            icon: Icons.pie_chart_outline,
            selected: _showChart,
            onTap: () => setState(() => _showChart = true),
          ),
        ),
      ],
    );
  }

  Widget _buildChartView(List<ReportRow> data) {
    final totalCount = data.length;
    final totalSpot = data.where((row) => row.type == 'Spot').length;
    final totalBigEvent = data.where((row) => row.type == 'Big event').length;

    final sections = [
      _RegistrationLegendItem(
        label: _t('big_event_label'),
        value: totalBigEvent,
        color: totalBigEvent > 0
            ? const Color(0xFF2E7D32)
            : const Color(0xFFBDBDBD),
      ),
      _RegistrationLegendItem(
        label: _t('spot_label'),
        value: totalSpot,
        color:
            totalSpot > 0 ? const Color(0xFF1565C0) : const Color(0xFFBDBDBD),
      ),
    ];

    return SingleChildScrollView(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFEAEAEA),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardShell(
              child: Column(
                children: [
                  SummaryField(
                    label: _t('total_events'),
                    value: totalCount.toString().padLeft(2, '0'),
                  ),
                  const SizedBox(height: 8),
                  SummaryField(
                    label: _t('total_spot'),
                    value: totalSpot.toString().padLeft(2, '0'),
                  ),
                  const SizedBox(height: 8),
                  SummaryField(
                    label: _t('total_big_event'),
                    value: totalBigEvent.toString().padLeft(2, '0'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (totalCount == 0)
              SizedBox(
                height: 220,
                child: Center(
                  child: Text(
                    _t('no_events_selected_filters'),
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              )
            else ...[
              Center(
                child: _RegistrationDonutChart(
                  sections: sections,
                  total: totalCount,
                ),
              ),
              const SizedBox(height: 16),
              _RegistrationLegend(sections: sections, total: totalCount),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEventTypeFilter() {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: MiniDropdown(
          value: _eventTypeFilter,
          items: <String>[
            _allEventCreated,
            _allSpot,
            _onlyBigEvents,
          ],
          onChanged: (value) => _applyFilterChange(() {
            _eventTypeFilterKey = value == _allSpot
                ? 'all_spot'
                : value == _onlyBigEvents
                    ? 'only_big_events'
                    : 'all_event_created';
          }),
        ),
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ViewModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = selected ? const Color(0xFF6C63FF) : Colors.white;
    final fg = selected ? Colors.white : Colors.black87;

    return SizedBox(
      height: 36,
      child: ElevatedButton.icon(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: bg,
          foregroundColor: fg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: selected ? const Color(0xFF6C63FF) : Colors.black12,
            ),
          ),
        ),
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _RegistrationLegendItem {
  final String label;
  final int value;
  final Color color;

  const _RegistrationLegendItem({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _RegistrationDonutChart extends StatelessWidget {
  final List<_RegistrationLegendItem> sections;
  final int total;

  const _RegistrationDonutChart({
    required this.sections,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final chartSize = screenWidth < 380 ? 200.0 : 228.0;

    return SizedBox(
      width: chartSize,
      height: chartSize,
      child: CustomPaint(
        painter: _RegistrationDonutPainter(
          sections: sections,
          total: total,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AdminStrings.text('all_event'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$total',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegistrationLegend extends StatelessWidget {
  final List<_RegistrationLegendItem> sections;
  final int total;

  const _RegistrationLegend({
    required this.sections,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: sections.map((section) {
        final percent = total == 0 ? 0.0 : (section.value * 100 / total);
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F4F4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: section.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text('${section.value} (${percent.toStringAsFixed(1)}%)'),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _RegistrationDonutPainter extends CustomPainter {
  final List<_RegistrationLegendItem> sections;
  final int total;

  const _RegistrationDonutPainter({
    required this.sections,
    required this.total,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = size.width * 0.22;
    final rect = Offset.zero & size;
    final chartRect = Rect.fromCircle(
      center: rect.center,
      radius: math.min(size.width, size.height) / 2 - 8,
    );

    final backgroundPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = const Color(0xFFE0E0E0);

    canvas.drawArc(chartRect, 0, math.pi * 2, false, backgroundPaint);

    if (total <= 0) return;

    var startAngle = -math.pi / 2;
    for (final section in sections) {
      if (section.value <= 0) continue;
      final sweepAngle = (section.value / total) * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt
        ..color = section.color;
      canvas.drawArc(chartRect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _RegistrationDonutPainter oldDelegate) {
    if (oldDelegate.total != total) return true;
    if (oldDelegate.sections.length != sections.length) return true;
    for (var i = 0; i < sections.length; i++) {
      final current = sections[i];
      final old = oldDelegate.sections[i];
      if (current.label != old.label ||
          current.value != old.value ||
          current.color != old.color) {
        return true;
      }
    }
    return false;
  }
}
