import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../widgets/bidirectional_table_scroller.dart';
import '../bigevent/big_event_detail_page.dart';
import '../bigevent/organizer_detail_page.dart';
import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import '../models/organization.dart';
import '../../core/services/config_service.dart';
import '../data/audit_log/audit_log_api.dart';

class AdminAuditLogPage extends StatefulWidget {
  const AdminAuditLogPage({super.key});

  @override
  State<AdminAuditLogPage> createState() => _AdminAuditLogPageState();
}

class _AdminAuditLogPageState extends State<AdminAuditLogPage> {
  static const List<String> _monthKeys = [
    'all_months',
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

  final _search = TextEditingController();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();
  Future<List<AuditLogEntry>>? _future;
  String _selectedTab = 'Normal';
  String _selectedNormalActionFilter = 'all';
  String _selectedCrudActionFilter = 'all';
  late int _selectedMonthIndex;
  late String _selectedYear;

  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
    _selectedMonthIndex =
        DateTime.now().toUtc().add(const Duration(hours: 7)).month;
    _selectedYear =
        DateTime.now().toUtc().add(const Duration(hours: 7)).year.toString();
    _future = AuditLogApi.fetchAdminLogs();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    AdminLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _search.dispose();
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
  List<String> get _monthOptions =>
      _monthKeys.map((key) => _t(key)).toList(growable: false);
  String get _selectedMonth => _monthOptions[_selectedMonthIndex];

  Future<void> _reload() async {
    setState(() {
      _future = AuditLogApi.fetchAdminLogs();
    });
  }

  String _normalizedAction(String action) {
    final value = action.trim().toUpperCase();
    if (value.contains('LOGIN')) return 'LOGIN';
    if (value.contains('LOGOUT')) return 'LOGOUT';
    if (value.contains('ACCOUNT_CREATED')) return 'ACCOUNT_CREATED';
    if (value.contains('CREATE') || value.contains('REGISTER'))
      return 'CREATED';
    if (value.contains('DELETE') || value.contains('REMOVE')) return 'DELETED';
    if (value.contains('EDIT') || value.contains('UPDATE')) return 'EDITED';
    if (value.contains('SUSPEND') || value.contains('BLOCK')) return 'BLOCKED';
    return value;
  }

  bool _matchesTab(AuditLogEntry entry) {
    final rawAction = entry.action.trim().toUpperCase();
    final entityType = (entry.entityType ?? '').trim().toUpperCase();

    switch (_selectedTab) {
      case 'Normal':
        return rawAction == 'LOGIN' ||
            rawAction == 'LOGOUT' ||
            rawAction == 'ACCOUNT_CREATED' ||
            rawAction.contains('DELETE_ACCOUNT');
      case 'Big Event':
        final isBigEvent =
            rawAction.contains('BIG_EVENT') || entityType.contains('EVENT');
        final isCrud = rawAction.contains('CREATE') ||
            rawAction.contains('UPDATE') ||
            rawAction.contains('EDIT') ||
            rawAction.contains('DELETE');
        return isBigEvent && isCrud;
      case 'Organizer':
        final isOrganizer = rawAction.contains('ORGANIZATION') ||
            rawAction.contains('ORGANIZER') ||
            entityType.contains('ORGANIZATION') ||
            entityType.contains('ORGANIZER');
        final isCrud = rawAction.contains('CREATE') ||
            rawAction.contains('UPDATE') ||
            rawAction.contains('EDIT') ||
            rawAction.contains('DELETE') ||
            rawAction.contains('REMOVE');
        return isOrganizer && isCrud;
      default:
        return true;
    }
  }

  int? get _selectedMonthNumber {
    if (_selectedMonth == _allMonths) return null;
    return _selectedMonthIndex <= 0 ? null : _selectedMonthIndex;
  }

  List<int> _availableYears(List<AuditLogEntry> items) {
    final years = <int>{};
    for (final entry in items) {
      final dt = entry.createdAt.toUtc().add(const Duration(hours: 7));
      years.add(dt.year);
    }
    final sorted = years.toList()..sort((a, b) => b.compareTo(a));
    return sorted;
  }

  List<String> _yearOptions(List<AuditLogEntry> items) {
    return [
      _allYears,
      ..._availableYears(items).map((year) => year.toString()),
    ];
  }

  bool _matchesMonthYear(AuditLogEntry entry) {
    final dt = entry.createdAt.toUtc().add(const Duration(hours: 7));
    final selectedMonth = _selectedMonthNumber;
    final selectedYear =
        _selectedYear == _allYears ? null : int.tryParse(_selectedYear);

    final monthMatches = selectedMonth == null || dt.month == selectedMonth;
    final yearMatches = selectedYear == null || dt.year == selectedYear;
    return monthMatches && yearMatches;
  }

  String _resolveSelectedYear(
      List<AuditLogEntry> items, String currentSelection) {
    if (currentSelection == _allYears) return _allYears;
    final years = _availableYears(items);
    if (years.isEmpty) return _allYears;
    final labels = years.map((year) => year.toString()).toSet();
    if (labels.contains(currentSelection)) return currentSelection;
    return years.first.toString();
  }

  List<AuditLogEntry> _filteredItems(List<AuditLogEntry> items) {
    final query = _search.text.trim().toLowerCase();

    return items.where((entry) {
      final matchesTab = _matchesTab(entry);
      final matchesMonthYear = _matchesMonthYear(entry);
      final normalizedAction = _normalizedAction(entry.action);
      final matchesNormalAction = !_isNormalTab ||
          _selectedNormalActionFilter == 'all' ||
          normalizedAction.toLowerCase() ==
              _selectedNormalActionFilter.toLowerCase();
      final matchesCrudAction = !(_isBigEventTab || _isOrganizerTab) ||
          _selectedCrudActionFilter == 'all' ||
          normalizedAction.toLowerCase() ==
              _selectedCrudActionFilter.toLowerCase();
      final matchesSearch = query.isEmpty ||
          entry.actorEmail.toLowerCase().contains(query) ||
          entry.actorName.toLowerCase().contains(query) ||
          (entry.actorId?.toString() ?? '').contains(query) ||
          entry.actorCode.toLowerCase().contains(query) ||
          entry.action.toLowerCase().contains(query);
      return matchesTab &&
          matchesMonthYear &&
          matchesNormalAction &&
          matchesCrudAction &&
          matchesSearch;
    }).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  double get _tableMinWidth {
    if (_isBigEventTab) return 1520;
    if (_isOrganizerTab) return 1520;
    return 860;
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}/'
        '${dt.year}';
  }

  String _formatTime(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'CREATED':
      case 'ACCOUNT_CREATED':
        return const Color(0xFF2E7D32);
      case 'EDITED':
        return const Color(0xFF1565C0);
      case 'DELETED':
        return const Color(0xFFC62828);
      case 'LOGIN':
        return const Color(0xFF6A1B9A);
      case 'LOGOUT':
        return const Color(0xFFEF6C00);
      case 'BLOCKED':
        return const Color(0xFFB71C1C);
      default:
        return const Color(0xFF455A64);
    }
  }

  bool get _isBigEventTab => _selectedTab == 'Big Event';
  bool get _isNormalTab => _selectedTab == 'Normal';
  bool get _isOrganizerTab => _selectedTab == 'Organizer';
  bool get _showsEntityColumns => _isBigEventTab || _isOrganizerTab;

  Widget _buildActionFilterChip({
    required String label,
    required String value,
  }) {
    final selected = _selectedNormalActionFilter == value;
    return InkWell(
      onTap: () => setState(() => _selectedNormalActionFilter = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? Colors.black : const Color(0xFFE2E2E2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  bool _supportsDetail(AuditLogEntry entry) {
    if (!_isBigEventTab && !_isOrganizerTab) return false;
    final action = _normalizedAction(entry.action);
    return action == 'CREATED' || action == 'EDITED';
  }

  bool _supportsNavigate(AuditLogEntry entry) {
    if (!_isBigEventTab && !_isOrganizerTab) return false;
    if (entry.entityId == null || entry.entityId! <= 0) return false;
    final action = _normalizedAction(entry.action);
    return action == 'CREATED' || action == 'EDITED';
  }

  List<String> _changedFields(AuditLogEntry entry) {
    final raw = entry.metadata['changed_fields'];
    if (raw is List) {
      return raw
          .map((value) => value.toString())
          .where((v) => v.isNotEmpty)
          .toList();
    }
    return const [];
  }

  String _prettyFieldName(String field) {
    switch (field) {
      case 'title':
        return 'Title';
      case 'description':
        return 'Description';
      case 'meeting_point':
        return 'Meeting point';
      case 'start_at':
        return 'Start date/time';
      case 'end_at':
        return 'End date/time';
      case 'status':
        return 'Status';
      case 'visibility':
        return 'Visibility';
      case 'max_participants':
        return 'Max participants';
      case 'distance_per_lap':
        return 'Distance per lap';
      case 'number_of_laps':
        return 'Number of laps';
      case 'total_distance':
        return 'Total distance';
      case 'location_name':
        return 'Location';
      case 'city':
        return 'City';
      case 'province':
        return 'Province';
      case 'name':
        return 'Name';
      case 'phone':
        return 'Phone';
      case 'email':
        return 'Email';
      case 'address':
        return 'Address';
      default:
        return field.replaceAll('_', ' ');
    }
  }

  String _stringifyValue(dynamic value) {
    if (value == null) return '-';
    final text = value.toString().trim();
    return text.isEmpty ? '-' : text;
  }

  String _detailSummary(AuditLogEntry entry) {
    final fields = _changedFields(entry);
    if (fields.isEmpty) return '-';
    return fields.map(_prettyFieldName).join(', ');
  }

  Future<void> _showDetailDialog(AuditLogEntry entry) async {
    final fields = _changedFields(entry);
    final oldValues = entry.metadata['old_values'] is Map
        ? Map<String, dynamic>.from(entry.metadata['old_values'] as Map)
        : const <String, dynamic>{};
    final newValues = entry.metadata['new_values'] is Map
        ? Map<String, dynamic>.from(entry.metadata['new_values'] as Map)
        : const <String, dynamic>{};

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_t('change_detail')),
        content: SizedBox(
          width: 520,
          child: fields.isEmpty
              ? Text(_t('no_change_detail_available'))
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: fields.map((field) {
                      final label = _prettyFieldName(field);
                      final before = _stringifyValue(oldValues[field]);
                      final after = _stringifyValue(newValues[field]);
                      final action = _normalizedAction(entry.action);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            if (action == 'CREATED')
                              Text('New: $after')
                            else
                              Text('$before -> $after'),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_t('close')),
          ),
        ],
      ),
    );
  }

  void _openBigEvent(AuditLogEntry entry) {
    final eventId = entry.entityId;
    if (eventId == null || eventId <= 0) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BigEventDetailPage(eventId: eventId),
      ),
    );
  }

  Future<Organization> _loadOrganizationById(AuditLogEntry entry) async {
    final organizerId = entry.entityId;
    final metadata = entry.metadata;
    final fallback = Organization(
      id: (organizerId ?? 0).toString(),
      name:
          (entry.entityName ?? metadata['organization_name'] ?? '-').toString(),
      email: (metadata['organization_email'] ?? '').toString(),
      phone: '',
      address: '',
      businessProfile: '',
      organizer: '',
    );

    if (organizerId == null || organizerId <= 0) return fallback;

    try {
      final uri = Uri.parse(
          '${ConfigService.getBaseUrl()}/api/organizations/$organizerId');
      final res = await http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      );
      if (res.statusCode != 200) return fallback;
      final decoded = jsonDecode(res.body);
      if (decoded is! Map) return fallback;
      return Organization.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _openOrganizer(AuditLogEntry entry) async {
    final organizerId = entry.entityId;
    if (organizerId == null || organizerId <= 0) return;
    final metadata = entry.metadata;
    final organization = await _loadOrganizationById(entry);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrganizerDetailPage(
          org: organization.copyWith(
            name: organization.name.isEmpty
                ? (entry.entityName ?? metadata['organization_name'] ?? '-')
                    .toString()
                : organization.name,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        centerTitle: true,
        title: Text(
          _t('admin_audit_log'),
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: _t('search_admin_audit_hint'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE6E6E6)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: Color(0xFFE6E6E6)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _AuditTabButton(
                        label: _t('normal'),
                        selected: _selectedTab == 'Normal',
                        onTap: () => setState(() => _selectedTab = 'Normal'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AuditTabButton(
                        label: _t('big_event'),
                        selected: _selectedTab == 'Big Event',
                        onTap: () => setState(() => _selectedTab = 'Big Event'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AuditTabButton(
                        label: _t('organizer'),
                        selected: _selectedTab == 'Organizer',
                        onTap: () => setState(() => _selectedTab = 'Organizer'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<AuditLogEntry>>(
                  future: _future,
                  builder: (context, snap) {
                    final baseItems = snap.data ?? const <AuditLogEntry>[];
                    final yearOptions = _yearOptions(baseItems);
                    final safeYear =
                        _resolveSelectedYear(baseItems, _selectedYear);
                    if (safeYear != _selectedYear) {
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (!mounted) return;
                        setState(() => _selectedYear = safeYear);
                      });
                    }
                    return Row(
                      children: [
                        Expanded(
                          child: _AuditFilterDropdown(
                            value: _selectedMonth,
                            items: _monthOptions,
                            onChanged: (value) => setState(() =>
                                _selectedMonthIndex =
                                    _monthOptions.indexOf(value)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _AuditFilterDropdown(
                            value: safeYear,
                            items: yearOptions,
                            onChanged: (value) =>
                                setState(() => _selectedYear = value),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (_isNormalTab) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildActionFilterChip(label: _t('all'), value: 'all'),
                        _buildActionFilterChip(
                            label: _t('login'), value: 'login'),
                        _buildActionFilterChip(
                            label: _t('logout'), value: 'logout'),
                      ],
                    ),
                  ),
                ] else if (_isBigEventTab || _isOrganizerTab) ...[
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        InkWell(
                          onTap: () =>
                              setState(() => _selectedCrudActionFilter = 'all'),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedCrudActionFilter == 'all'
                                  ? Colors.black
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _selectedCrudActionFilter == 'all'
                                    ? Colors.black
                                    : const Color(0xFFE2E2E2),
                              ),
                            ),
                            child: Text(
                              _t('all'),
                              style: TextStyle(
                                color: _selectedCrudActionFilter == 'all'
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(
                              () => _selectedCrudActionFilter = 'created'),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedCrudActionFilter == 'created'
                                  ? Colors.black
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _selectedCrudActionFilter == 'created'
                                    ? Colors.black
                                    : const Color(0xFFE2E2E2),
                              ),
                            ),
                            child: Text(
                              _t('created'),
                              style: TextStyle(
                                color: _selectedCrudActionFilter == 'created'
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(
                              () => _selectedCrudActionFilter = 'edited'),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedCrudActionFilter == 'edited'
                                  ? Colors.black
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _selectedCrudActionFilter == 'edited'
                                    ? Colors.black
                                    : const Color(0xFFE2E2E2),
                              ),
                            ),
                            child: Text(
                              _t('edited'),
                              style: TextStyle(
                                color: _selectedCrudActionFilter == 'edited'
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => setState(
                              () => _selectedCrudActionFilter = 'deleted'),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: _selectedCrudActionFilter == 'deleted'
                                  ? Colors.black
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: _selectedCrudActionFilter == 'deleted'
                                    ? Colors.black
                                    : const Color(0xFFE2E2E2),
                              ),
                            ),
                            child: Text(
                              _t('deleted'),
                              style: TextStyle(
                                color: _selectedCrudActionFilter == 'deleted'
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<AuditLogEntry>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text(snap.error.toString()));
                }

                final items = _filteredItems(snap.data ?? []);
                if (items.isEmpty) {
                  return Center(child: Text(_t('no_admin_audit_logs_found')));
                }

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFFE2E2E2)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: BidirectionalTableScroller(
                        horizontalController: _horizontalScrollController,
                        verticalController: _verticalScrollController,
                        minWidth: _tableMinWidth,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            const Color(0xFFF7F7F7),
                          ),
                          headingTextStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.black87,
                          ),
                          dataRowMinHeight: 56,
                          dataRowMaxHeight: 64,
                          columnSpacing: 24,
                          columns: _buildColumns(),
                          rows: _buildRows(items),
                        ),
                      ),
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

  List<DataColumn> _buildColumns() {
    return [
      DataColumn(label: Text(_t('admin_id'))),
      DataColumn(label: Text(_t('admin_name'))),
      DataColumn(label: Text(_t('email'))),
      DataColumn(label: Text(_t('date'))),
      DataColumn(label: Text(_t('time'))),
      DataColumn(label: Text(_t('action'))),
      if (_isBigEventTab) ...[
        DataColumn(label: Text(_t('big_event') + ' ID')),
        DataColumn(label: Text(_t('big_event') + ' ' + _t('name'))),
        DataColumn(label: Text(_t('detail'))),
        DataColumn(label: Text(_t('navigate'))),
      ],
      if (_isOrganizerTab) ...[
        DataColumn(label: Text(_t('organizer') + ' ID')),
        DataColumn(label: Text(_t('organizer') + ' ' + _t('name'))),
        DataColumn(label: Text(_t('detail'))),
        DataColumn(label: Text(_t('navigate'))),
      ],
    ];
  }

  List<DataRow> _buildRows(List<AuditLogEntry> items) {
    return items.map((entry) {
      final normalizedAction = _normalizedAction(entry.action);
      final color = _actionColor(normalizedAction);
      return DataRow(
        cells: [
          DataCell(
            Text(
              entry.actorId?.toString() ?? '-',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          DataCell(
            SizedBox(
              width: 180,
              child: Text(
                entry.actorName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          DataCell(
            SizedBox(
              width: 220,
              child: Text(
                entry.actorEmail,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          DataCell(Text(_formatDate(entry.createdAt))),
          DataCell(Text(_formatTime(entry.createdAt))),
          DataCell(
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: color.withOpacity(0.24),
                ),
              ),
              child: Text(
                normalizedAction,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          if (_showsEntityColumns) ...[
            DataCell(Text(entry.entityId?.toString() ?? '-')),
            DataCell(
              SizedBox(
                width: 220,
                child: Text(
                  (entry.entityName ?? '-').trim().isEmpty
                      ? '-'
                      : (entry.entityName ?? '-'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (_isBigEventTab || _isOrganizerTab)
              DataCell(
                SizedBox(
                  width: 220,
                  child: _supportsDetail(entry)
                      ? InkWell(
                          onTap: () => _showDetailDialog(entry),
                          child: Text(
                            _detailSummary(entry),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF1565C0),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        )
                      : const Text('-'),
                ),
              ),
            if (_isBigEventTab || _isOrganizerTab)
              DataCell(
                _supportsNavigate(entry)
                    ? TextButton(
                        onPressed: () => _isBigEventTab
                            ? _openBigEvent(entry)
                            : _openOrganizer(entry),
                        child: Text(_t('view')),
                      )
                    : const Text('-'),
              ),
          ],
        ],
      );
    }).toList();
  }
}

class _AuditTabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AuditTabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.black : const Color(0xFFE2E2E2),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _AuditFilterDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _AuditFilterDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E2E2)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: items
              .map((item) => DropdownMenuItem<String>(
                    value: item,
                    child: Text(item, overflow: TextOverflow.ellipsis),
                  ))
              .toList(),
          onChanged: (next) {
            if (next == null) return;
            onChanged(next);
          },
        ),
      ),
    );
  }
}
