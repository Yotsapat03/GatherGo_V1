import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_routes.dart';
import 'all_events_api.dart';
import 'registrations_api.dart';
import 'report_models.dart';
import 'report_widgets.dart';

class AllEventsTab extends StatefulWidget {
  const AllEventsTab({super.key});

  @override
  State<AllEventsTab> createState() => _AllEventsTabState();
}

class _AllEventsTabState extends State<AllEventsTab> {
  static const List<String> _monthLabels = [
    '',
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  bool _loadingPeriods = true;
  bool _loadingChart = false;
  String? _error;
  AvailablePeriodsResponse? _periods;
  AllEventsPieReport? _report;
  RegistrationSummary _summary = const RegistrationSummary(
    totalUsersExcludingAdmin: 0,
    totalRegistrationsTodayBangkok: 0,
    totalEvents: 0,
    totalSpot: 0,
    totalBigEvent: 0,
  );
  int? _selectedYear;
  int? _selectedMonth;

  @override
  void initState() {
    super.initState();
    _loadPeriods();
  }

  Future<void> _loadPeriods() async {
    setState(() {
      _loadingPeriods = true;
      _error = null;
    });

    try {
      final results = await Future.wait([
        AllEventsApi.fetchAvailablePeriods(),
        RegistrationsApi.fetchRegistrationsReport(),
      ]);
      final periods = results[0] as AvailablePeriodsResponse;
      final registrations = results[1] as RegistrationReportResponse;
      final initialYear = _pickInitialYear(periods);
      final initialMonth = _pickInitialMonth(periods, initialYear);
      final report = await AllEventsApi.fetchPieReport(
        year: initialYear,
        month: initialMonth,
      );

      if (!mounted) return;
      setState(() {
        _periods = periods;
        _selectedYear = initialYear;
        _selectedMonth = initialMonth;
        _report = report;
        _summary = registrations.summary;
        _loadingPeriods = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingPeriods = false;
      });
    }
  }

  int _pickInitialYear(AvailablePeriodsResponse periods) {
    final years = periods.years;
    if (years.isEmpty) return periods.maxYear;
    return years.first;
  }

  int _pickInitialMonth(AvailablePeriodsResponse periods, int year) {
    final months = periods.monthsByYear[year] ?? const <int>[];
    if (months.isEmpty) {
      return DateTime.now().toUtc().add(const Duration(hours: 7)).month;
    }
    return months.last;
  }

  Future<void> _loadChart() async {
    final year = _selectedYear;
    final month = _selectedMonth;
    if (year == null || month == null) return;

    setState(() {
      _loadingChart = true;
      _error = null;
    });

    try {
      final report =
          await AllEventsApi.fetchPieReport(year: year, month: month);
      if (!mounted) return;
      setState(() {
        _report = report;
        _loadingChart = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loadingChart = false;
      });
    }
  }

  Future<void> _onYearChanged(int year) async {
    if (_selectedYear == year) {
      return;
    }
    final periods = _periods;
    if (periods == null) return;

    final months = periods.monthsByYear[year] ?? const <int>[];
    final nextMonth = months.contains(_selectedMonth)
        ? _selectedMonth
        : (months.isEmpty ? null : months.last);

    setState(() {
      _selectedYear = year;
      _selectedMonth = nextMonth;
    });

    await _loadChart();
  }

  Future<void> _onMonthChanged(int month) async {
    if (_selectedMonth == month) {
      return;
    }
    setState(() {
      _selectedMonth = month;
    });
    await _loadChart();
  }

  void _openReportTab(int index) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      AppRoutes.adminEventReport,
      (route) => false,
      arguments: {'initialTab': index},
    );
  }

  @override
  Widget build(BuildContext context) {
    final periods = _periods;
    final selectedYear = _selectedYear;
    final selectedMonth = _selectedMonth;
    final availableYears = periods?.years ?? const <int>[];
    final availableMonths = selectedYear == null
        ? const <int>[]
        : (periods?.monthsByYear[selectedYear] ?? const <int>[]);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Builder(
        builder: (context) {
          if (_loadingPeriods) {
            return const Center(child: CircularProgressIndicator());
          }

          if (_error != null && _report == null) {
            return _buildErrorState();
          }

          return SingleChildScrollView(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReportTabsHeader(
                    onRegistrationsTap: () => _openReportTab(0),
                    onPaymentsTap: () => _openReportTab(1),
                    onSpotReportsTap: () => _openReportTab(2),
                  ),
                  const SizedBox(height: 16),
                  EventSummaryCard(summary: _summary),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 180,
                        child: _LabeledDropdown<int>(
                          label: 'Year',
                          value: selectedYear,
                          items: availableYears,
                          itemLabel: (value) => value.toString(),
                          onChanged: (value) {
                            if (value == null) return;
                            _onYearChanged(value);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 180,
                        child: _LabeledDropdown<int>(
                          label: 'Month',
                          value: selectedMonth,
                          items: availableMonths,
                          itemLabel: (value) => _monthLabels[value],
                          onChanged: (value) {
                            if (value == null) return;
                            _onMonthChanged(value);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_loadingChart)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null && _report == null)
                    _buildErrorState()
                  else
                    _buildChartBody(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildChartBody() {
    final report = _report;
    if (report == null) {
      return const EmptyInfo();
    }

    if (report.totalCount == 0) {
      return const Center(
        child: Text(
          'No big events or spots found for this period.',
          style: TextStyle(color: Colors.black54, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }

    final sections = [
      _PieLegendItem(
        label: 'Big Event',
        value: report.bigEventCount,
        color: report.bigEventCount > 0
            ? const Color(0xFF2E7D32)
            : const Color(0xFFBDBDBD),
      ),
      _PieLegendItem(
        label: 'Spot',
        value: report.spotCount,
        color: report.spotCount > 0
            ? const Color(0xFF1565C0)
            : const Color(0xFFBDBDBD),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumn = constraints.maxWidth < 760;
        final chart = _PieChartCard(
          sections: sections,
          total: report.totalCount,
        );
        final legend = _PieLegend(
          sections: sections,
          total: report.totalCount,
        );

        if (useColumn) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              chart,
              const SizedBox(height: 20),
              legend,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Center(child: chart)),
            const SizedBox(width: 24),
            SizedBox(
              width: 240,
              child: legend,
            ),
          ],
        );
      },
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error ?? 'Unable to load all-event report.',
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _loadPeriods,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ReportTabsHeader extends StatelessWidget {
  final VoidCallback onRegistrationsTap;
  final VoidCallback onPaymentsTap;
  final VoidCallback onSpotReportsTap;

  const _ReportTabsHeader({
    required this.onRegistrationsTap,
    required this.onPaymentsTap,
    required this.onSpotReportsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _ReportTabButton(
          label: 'Registrations',
          onTap: onRegistrationsTap,
        ),
        _ReportTabButton(
          label: 'Payment',
          onTap: onPaymentsTap,
        ),
        _ReportTabButton(
          label: 'Spot Reports',
          onTap: onSpotReportsTap,
        ),
      ],
    );
  }
}

class _ReportTabButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _ReportTabButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          backgroundColor: const Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _LabeledDropdown<T> extends StatelessWidget {
  final String label;
  final T? value;
  final List<T> items;
  final String Function(T value) itemLabel;
  final ValueChanged<T?> onChanged;

  const _LabeledDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.itemLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE0E0E0)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isExpanded: true,
              items: items
                  .map(
                    (item) => DropdownMenuItem<T>(
                      value: item,
                      child: Text(itemLabel(item)),
                    ),
                  )
                  .toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _PieChartCard extends StatelessWidget {
  final List<_PieLegendItem> sections;
  final int total;

  const _PieChartCard({
    required this.sections,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final chartSize = screenWidth < 380 ? 220.0 : 240.0;

    return SizedBox(
      width: chartSize,
      height: chartSize,
      child: CustomPaint(
        painter: _PieChartPainter(sections: sections, total: total),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'All Event',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                '$total',
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PieLegend extends StatelessWidget {
  final List<_PieLegendItem> sections;
  final int total;

  const _PieLegend({
    required this.sections,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: sections.map((section) {
        final percent = total == 0 ? 0 : (section.value * 100 / total);
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: section.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${section.value} (${percent.toStringAsFixed(1)}%)',
                style: const TextStyle(color: Colors.black87),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _PieLegendItem {
  final String label;
  final int value;
  final Color color;

  const _PieLegendItem({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _PieChartPainter extends CustomPainter {
  final List<_PieLegendItem> sections;
  final int total;

  const _PieChartPainter({
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
      ..color = const Color(0xFFE9E9E9);

    canvas.drawArc(chartRect, 0, math.pi * 2, false, backgroundPaint);

    if (total <= 0) return;

    var startAngle = -math.pi / 2;
    for (final section in sections) {
      if (section.value <= 0) continue;
      final sweepAngle = (section.value / total) * math.pi * 2;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.butt
        ..strokeWidth = strokeWidth
        ..color = section.color;
      canvas.drawArc(chartRect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) {
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
