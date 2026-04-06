import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import '../widgets/bidirectional_table_scroller.dart';
import 'payments_api.dart';
import 'report_models.dart';
import 'report_widgets.dart';
import '../user/user_detail_loader_page.dart';

enum _PaymentViewLevel { companies, events, users }

class PaymentsTab extends StatefulWidget {
  const PaymentsTab({super.key});

  @override
  State<PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<PaymentsTab> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _verticalScrollController = ScrollController();
  final ScrollController _horizontalScrollController = ScrollController();

  bool _loading = true;
  String? _error;
  PaymentSummary _summary = const PaymentSummary(
    totalCompany: 0,
    totalRegistrations: 0,
    totalBigEvents: 0,
  );
  List<PaymentCompanyRow> _companies = const [];
  List<PaymentCompanyEventRow> _events = const [];
  List<PaymentEventUserRow> _users = const [];

  bool _hasText(String value) => value.trim().isNotEmpty;

  bool _isPaidStatus(String value) {
    final normalized = value.trim().toLowerCase();
    return const <String>{
      'paid',
      'completed',
      'success',
      'succeeded',
      'done',
      'confirmed',
    }.contains(normalized);
  }

  String _formatRatio(int numerator, int denominator) {
    return '$numerator/${denominator <= 0 ? 0 : denominator}';
  }

  String _formatMoneyRatio(double actual, double expected) {
    String money(double value) => '${value.toStringAsFixed(2)} THB';
    return '${money(actual)}/${money(expected <= 0 ? 0 : expected)}';
  }

  String _extractDistrictProvince(String rawAddress) {
    final normalized = rawAddress.trim();
    if (normalized.isEmpty || normalized == '-') return '-';

    final parts = normalized
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '-';
    if (parts.length == 1) return parts.first;

    final province = parts.last;
    final district = parts.length >= 2 ? parts[parts.length - 2] : '';
    if (district.isEmpty) return province;
    return '$district, $province';
  }

  Widget _buildUserLevelSummaryCard() {
    final selectedEvent = _selectedEvent;
    if (selectedEvent == null) {
      return const SizedBox.shrink();
    }

    final capacity = selectedEvent.maxParticipants;
    final paidUsers =
        _users.where((row) => _isPaidStatus(row.paymentStatus)).length;
    final unpaidBookedUsers =
        _users.where((row) => !_isPaidStatus(row.paymentStatus)).length;
    final actualRevenue = _users
        .where((row) => _isPaidStatus(row.paymentStatus))
        .fold<double>(0, (sum, row) => sum + row.price);
    final expectedRevenue = selectedEvent.fee * (capacity <= 0 ? 0 : capacity);

    return CardShell(
      child: Column(
        children: [
          SummaryField(
            label: _t('actual_joined_capacity'),
            value: _formatRatio(paidUsers, capacity),
          ),
          const SizedBox(height: 8),
          SummaryField(
            label: _t('actual_revenue_full_revenue'),
            value: _formatMoneyRatio(actualRevenue, expectedRevenue),
          ),
          const SizedBox(height: 8),
          SummaryField(
            label: _t('booked_unpaid_capacity'),
            value: _formatRatio(unpaidBookedUsers, capacity),
          ),
        ],
      ),
    );
  }

  Future<void> _openReceiptUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  _PaymentViewLevel _viewLevel = _PaymentViewLevel.companies;
  PaymentCompanyRow? _selectedCompany;
  PaymentCompanyEventRow? _selectedEvent;

  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
    _loadCompanies();
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

  void _resetTableScroll() {
    if (_verticalScrollController.hasClients) {
      _verticalScrollController.jumpTo(0);
    }
    if (_horizontalScrollController.hasClients) {
      _horizontalScrollController.jumpTo(0);
    }
  }

  Future<void> _loadCompanies() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await PaymentsApi.fetchPaymentCompanies();
      if (!mounted) return;
      setState(() {
        _summary = response.summary;
        _companies = response.rows;
        _events = const [];
        _users = const [];
        _selectedCompany = null;
        _selectedEvent = null;
        _viewLevel = _PaymentViewLevel.companies;
        _loading = false;
      });
      _resetTableScroll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openCompany(PaymentCompanyRow company) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await PaymentsApi.fetchCompanyEvents(company.organizationId);
      if (!mounted) return;
      setState(() {
        _selectedCompany = company;
        _selectedEvent = null;
        _events = rows;
        _users = const [];
        _viewLevel = _PaymentViewLevel.events;
        _loading = false;
      });
      _resetTableScroll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _openEvent(PaymentCompanyEventRow event) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final rows = await PaymentsApi.fetchEventUsers(event.eventNumericId);
      if (!mounted) return;
      setState(() {
        _selectedEvent = event;
        _users = rows;
        _viewLevel = _PaymentViewLevel.users;
        _loading = false;
      });
      _resetTableScroll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _goBackOneLevel() {
    setState(() {
      _error = null;
      _searchController.clear();
      if (_viewLevel == _PaymentViewLevel.users) {
        _viewLevel = _PaymentViewLevel.events;
        _selectedEvent = null;
        _users = const [];
      } else if (_viewLevel == _PaymentViewLevel.events) {
        _viewLevel = _PaymentViewLevel.companies;
        _selectedCompany = null;
        _events = const [];
      }
    });
    _resetTableScroll();
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '-';
    final bangkok = (value.isUtc ? value : value.toUtc()).add(
      const Duration(hours: 7),
    );
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(bangkok.day)}/${two(bangkok.month)}/${bangkok.year} ${two(bangkok.hour)}:${two(bangkok.minute)}';
  }

  Future<void> _openUserDetail(PaymentEventUserRow row) async {
    final actionAt = row.actionAt;
    final fallbackRegDate =
        actionAt == null ? '-' : _formatDateTime(actionAt).split(' ').first;
    final fallbackRegTime = actionAt == null
        ? '-'
        : _formatDateTime(actionAt).split(' ').skip(1).join(' ');

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => UserDetailLoaderPage(
          userId: row.userId.toString(),
          fallbackName: row.userName,
          fallbackRegDate: fallbackRegDate,
          fallbackRegTime: fallbackRegTime,
          fallbackProblem: 0,
        ),
      ),
    );
  }

  List<PaymentCompanyRow> get _filteredCompanies {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _companies;
    return _companies.where((row) {
      return row.companyId.toLowerCase().contains(query) ||
          row.name.toLowerCase().contains(query) ||
          row.email.toLowerCase().contains(query);
    }).toList();
  }

  List<PaymentCompanyEventRow> get _filteredEvents {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _events;
    return _events.where((row) {
      return row.eventId.toLowerCase().contains(query) ||
          row.eventName.toLowerCase().contains(query) ||
          _formatDateTime(row.time).toLowerCase().contains(query) ||
          _formatDateTime(row.createdAt).toLowerCase().contains(query);
    }).toList();
  }

  List<PaymentEventUserRow> get _filteredUsers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _users;
    return _users.where((row) {
      return row.userCode.toLowerCase().contains(query) ||
          row.userName.toLowerCase().contains(query) ||
          row.status.toLowerCase().contains(query) ||
          row.shirtSize.toLowerCase().contains(query) ||
          row.paymentId.toLowerCase().contains(query) ||
          row.bookingId.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _showBillDialog(PaymentEventUserRow row) async {
    final hasReceiptSection = _hasText(row.receiptNo) ||
        _hasText(row.receiptIssueDate) ||
        _hasText(row.receiptUrl);

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(_t('bill_detail')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _dialogSection(
                _t('user_information'),
                [
                  _dialogLine(_t('user_id'), row.userCode),
                  _dialogLine(_t('user_name'), row.userName),
                ],
              ),
              const SizedBox(height: 8),
              _dialogSection(
                _t('payment_information'),
                [
                  _dialogLine(_t('booking_reference'), row.bookingId),
                  _dialogLine(_t('payment_reference'), row.paymentId),
                  if (_hasText(row.status))
                    _dialogLine(_t('booking_status'), row.status),
                  if (_selectedEvent?.hasShirtSize == true &&
                      _hasText(row.shirtSize))
                    _dialogLine(_t('shirt_size'), row.shirtSize),
                  if (_hasText(row.paymentStatus))
                    _dialogLine(_t('payment_status'), row.paymentStatus),
                  _dialogLine(
                      _t('price'), '${row.price.toStringAsFixed(2)} THB'),
                  if (_hasText(row.paymentMethod))
                    _dialogLine(_t('method'), row.paymentMethod),
                  if (_hasText(row.provider))
                    _dialogLine(_t('provider'), row.provider),
                  if (_hasText(row.providerTxnId))
                    _dialogLine(_t('provider_txn_id'), row.providerTxnId),
                  if (row.paidAt != null)
                    _dialogLine(_t('paid_at'), _formatDateTime(row.paidAt)),
                ],
              ),
              if (hasReceiptSection) ...[
                const SizedBox(height: 8),
                _dialogSection(
                  _t('receipt_information'),
                  [
                    if (_hasText(row.receiptNo))
                      _dialogLine(_t('receipt_no'), row.receiptNo),
                    if (_hasText(row.receiptIssueDate))
                      _dialogLine(_t('receipt_date'), row.receiptIssueDate),
                    if (_hasText(row.receiptUrl))
                      _dialogLine(_t('receipt_url'), row.receiptUrl),
                    if (_hasText(row.receiptUrl))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: OutlinedButton(
                          onPressed: () => _openReceiptUrl(row.receiptUrl),
                          child: Text(_t('open_receipt')),
                        ),
                      ),
                  ],
                ),
              ],
            ],
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

  Widget _dialogLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(color: Colors.black87, fontSize: 13),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _dialogSection(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _buildBreadcrumb() {
    final labels = <String>[_t('company_payments')];
    if (_selectedCompany != null) {
      labels.add(_selectedCompany!.name);
    }
    if (_selectedEvent != null) {
      labels.add(_selectedEvent!.eventName);
    }

    return Row(
      children: [
        if (_viewLevel != _PaymentViewLevel.companies)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              height: 34,
              child: OutlinedButton.icon(
                onPressed: _goBackOneLevel,
                icon: const Icon(Icons.arrow_back, size: 16),
                label: Text(_t('back')),
              ),
            ),
          ),
        Expanded(
          child: Text(
            labels.join(' / '),
            style: const TextStyle(fontWeight: FontWeight.w800),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildCompaniesTable(List<PaymentCompanyRow> rows) {
    return _buildTableShell(
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 52,
        columnSpacing: 24,
        columns: [
          DataColumn(label: Text(_t('id'))),
          DataColumn(label: Text(_t('name'))),
          DataColumn(label: Text(_t('phone'))),
          DataColumn(label: Text(_t('district_province'))),
          DataColumn(label: Text(_t('email'))),
          DataColumn(label: Text(_t('number_of_events'))),
          DataColumn(label: Text(_t('events_payments'))),
        ],
        rows: rows.map((row) {
          return DataRow(
            cells: [
              DataCell(Text(row.companyId)),
              DataCell(
                SizedBox(
                  width: 220,
                  child: Text(
                    row.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 140,
                  child: Text(
                    row.phone,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 220,
                  child: Text(
                    _extractDistrictProvince(row.address),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 220,
                  child: Text(
                    row.email,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(Text(row.numberOfEvents.toString())),
              DataCell(
                SizedBox(
                  width: 160,
                  child: OutlinedButton(
                    onPressed: () => _openCompany(row),
                    child: Text(_t('see_events')),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEventsTable(List<PaymentCompanyEventRow> rows) {
    return _buildTableShell(
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 52,
        columnSpacing: 24,
        columns: [
          DataColumn(label: Text(_t('event_id'))),
          DataColumn(label: Text(_t('event_name'))),
          DataColumn(label: Text(_t('time'))),
          DataColumn(label: Text(_t('created'))),
          DataColumn(label: Text(_t('payment'))),
        ],
        rows: rows.map((row) {
          return DataRow(
            cells: [
              DataCell(Text(row.eventId)),
              DataCell(
                SizedBox(
                  width: 220,
                  child: Text(
                    row.eventName,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(Text(_formatDateTime(row.time))),
              DataCell(Text(_formatDateTime(row.createdAt))),
              DataCell(
                SizedBox(
                  width: 150,
                  child: OutlinedButton(
                    onPressed: () => _openEvent(row),
                    child: Text('${_t('see_payments')} (${row.paymentCount})'),
                  ),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUsersTable(List<PaymentEventUserRow> rows) {
    final showShirtSizeColumn = _selectedEvent?.hasShirtSize == true ||
        rows.any((row) => _hasText(row.shirtSize));
    return _buildTableShell(
      child: DataTable(
        headingRowHeight: 36,
        dataRowMinHeight: 46,
        dataRowMaxHeight: 54,
        columnSpacing: 20,
        columns: [
          DataColumn(label: Text(_t('user_id'))),
          DataColumn(label: Text(_t('user_name'))),
          DataColumn(label: Text(_t('date_time'))),
          DataColumn(label: Text(_t('booking_status'))),
          if (showShirtSizeColumn) DataColumn(label: Text(_t('shirt_size'))),
          DataColumn(label: Text(_t('price'))),
          DataColumn(label: Text(_t('payment_id'))),
          DataColumn(label: Text(_t('bill'))),
        ],
        rows: rows.map((row) {
          final normalizedPaymentStatus =
              row.paymentStatus.trim().toLowerCase();
          final canViewBill = const <String>{
                'paid',
                'completed',
                'success',
                'succeeded',
                'done',
                'confirmed',
              }.contains(normalizedPaymentStatus) &&
              row.paymentId.trim().isNotEmpty &&
              row.paymentId.trim() != '-';
          return DataRow(
            cells: [
              DataCell(
                InkWell(
                  onTap: () => _openUserDetail(row),
                  child: Text(
                    row.userCode,
                    style: const TextStyle(
                      color: Colors.blue,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              DataCell(
                SizedBox(
                  width: 180,
                  child: InkWell(
                    onTap: () => _openUserDetail(row),
                    child: Text(
                      row.userName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              DataCell(Text(_formatDateTime(row.actionAt))),
              DataCell(Text(row.status)),
              if (showShirtSizeColumn)
                DataCell(Text(_hasText(row.shirtSize) ? row.shirtSize : '-')),
              DataCell(Text('${row.price.toStringAsFixed(2)} THB')),
              DataCell(Text(row.paymentId)),
              DataCell(
                SizedBox(
                  width: 120,
                  child: canViewBill
                      ? OutlinedButton(
                          onPressed: () => _showBillDialog(row),
                          child: Text(_t('see_bill')),
                        )
                      : const Center(child: Text('-')),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTableShell({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEAEAEA),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(8),
      child: BidirectionalTableScroller(
        horizontalController: _horizontalScrollController,
        verticalController: _verticalScrollController,
        minWidth: _viewLevel == _PaymentViewLevel.users
            ? (_selectedEvent?.hasShirtSize == true ? 1100 : 980)
            : 920,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final companies = _filteredCompanies;
    final events = _filteredEvents;
    final users = _filteredUsers;

    Widget content;
    if (_loading) {
      content =
          const Expanded(child: Center(child: CircularProgressIndicator()));
    } else if (_error != null) {
      content = Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _viewLevel == _PaymentViewLevel.companies
                    ? _loadCompanies
                    : _goBackOneLevel,
                child: Text(_t('retry')),
              ),
            ],
          ),
        ),
      );
    } else {
      final isEmpty = _viewLevel == _PaymentViewLevel.companies
          ? companies.isEmpty
          : _viewLevel == _PaymentViewLevel.events
              ? events.isEmpty
              : users.isEmpty;

      content = Expanded(
        child: Column(
          children: [
            SearchBarMini(controller: _searchController),
            const SizedBox(height: 8),
            _buildBreadcrumb(),
            const SizedBox(height: 10),
            Expanded(
              child: isEmpty
                  ? const EmptyInfo()
                  : _viewLevel == _PaymentViewLevel.companies
                      ? _buildCompaniesTable(companies)
                      : _viewLevel == _PaymentViewLevel.events
                          ? _buildEventsTable(events)
                          : _buildUsersTable(users),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (_viewLevel == _PaymentViewLevel.companies) ...[
            CardShell(
              child: Column(
                children: [
                  SummaryField(
                    label: _t('total_company'),
                    value: _summary.totalCompany.toString().padLeft(2, '0'),
                  ),
                  const SizedBox(height: 8),
                  SummaryField(
                    label: _t('total_registrations'),
                    value:
                        _summary.totalRegistrations.toString().padLeft(2, '0'),
                  ),
                  const SizedBox(height: 8),
                  SummaryField(
                    label: _t('total_big_event'),
                    value: _summary.totalBigEvents.toString().padLeft(2, '0'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ] else if (_viewLevel == _PaymentViewLevel.events) ...[
            CardShell(
              child: SummaryField(
                label: _t('total_big_event'),
                value: events.length.toString().padLeft(2, '0'),
              ),
            ),
            const SizedBox(height: 12),
          ] else if (_viewLevel == _PaymentViewLevel.users) ...[
            _buildUserLevelSummaryCard(),
            const SizedBox(height: 12),
          ],
          content,
        ],
      ),
    );
  }
}
