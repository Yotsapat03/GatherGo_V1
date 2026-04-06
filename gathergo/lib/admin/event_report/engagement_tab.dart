import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import 'engagement_api.dart';
import 'report_widgets.dart';

class EngagementTab extends StatefulWidget {
  const EngagementTab({super.key});

  @override
  State<EngagementTab> createState() => _EngagementTabState();
}

class _EngagementTabState extends State<EngagementTab> {
  static const List<Color> _palette = <Color>[
    Color(0xFF2E7D32),
    Color(0xFF1565C0),
    Color(0xFFF9A825),
    Color(0xFF6A1B9A),
    Color(0xFFD84315),
    Color(0xFF00838F),
    Color(0xFF5D4037),
    Color(0xFFAD1457),
    Color(0xFF283593),
    Color(0xFF558B2F),
  ];

  static const Color _maleColor = Color(0xFF4FC3F7);
  static const Color _femaleColor = Color(0xFFFF7EB6);
  static const List<Color> _rainbowColors = <Color>[
    Color(0xFFFF1A1A),
    Color(0xFFFF7A00),
    Color(0xFFFFFF00),
    Color(0xFF20C71A),
    Color(0xFF20B8E8),
    Color(0xFF4338CA),
    Color(0xFFD000FF),
  ];
  static const Color _otherFallbackColor = Color(0xFFFF4FC3);

  bool _loading = true;
  String? _error;
  String _selectedGroupBy = 'gender';
  late int _selectedMonth;
  late int _selectedYear;
  List<int> _availableYears = const <int>[];
  int _totalUsers = 0;
  List<EngagementSlice> _rows = const <EngagementSlice>[];

  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    _selectedMonth = now.month;
    _selectedYear = now.year;
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

  List<String> get _groupLabelsLocalized => <String>[
        _t('gender'),
        _t('age'),
        _t('occupation'),
        _t('province_label'),
      ];

  List<String> get _monthLabelsLocalized => <String>[
        '',
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await EngagementApi.fetchReport(
        groupBy: _selectedGroupBy,
        month: _selectedMonth,
        year: _selectedYear,
      );
      if (!mounted) return;
      final years = response.availableYears.isEmpty
          ? <int>[_selectedYear]
          : response.availableYears;
      setState(() {
        _availableYears = years;
        _selectedYear =
            years.contains(response.year) ? response.year : years.first;
        _totalUsers = response.totalUsers;
        _rows = response.rows;
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

  Future<void> _changeGroupBy(String value) async {
    if (_selectedGroupBy == value) return;
    setState(() {
      _selectedGroupBy = value;
    });
    await _load();
  }

  Future<void> _changeMonth(int value) async {
    if (_selectedMonth == value) return;
    setState(() {
      _selectedMonth = value;
    });
    await _load();
  }

  Future<void> _changeYear(int value) async {
    if (_selectedYear == value) return;
    setState(() {
      _selectedYear = value;
    });
    await _load();
  }

  _EngagementLegendItem _buildSection(EngagementSlice row, int index) {
    final label = row.label.trim().toLowerCase();
    if (_selectedGroupBy == 'gender') {
      if (label == 'male') {
        return _EngagementLegendItem(
          label: _t('male'),
          value: row.totalUsers,
          color: _maleColor,
        );
      }
      if (label == 'female') {
        return _EngagementLegendItem(
          label: _t('female'),
          value: row.totalUsers,
          color: _femaleColor,
        );
      }
      return _EngagementLegendItem(
        label: _normalizeOtherGenderLabel(row.label),
        value: row.totalUsers,
        color: _otherFallbackColor,
        gradient: const SweepGradient(
          colors: <Color>[
            Color(0xFFFF1A1A),
            Color(0xFFFF7A00),
            Color(0xFFFFFF00),
            Color(0xFF20C71A),
            Color(0xFF20B8E8),
            Color(0xFF4338CA),
            Color(0xFFD000FF),
            Color(0xFFFF1A1A),
          ],
          stops: <double>[0.0, 0.16, 0.32, 0.48, 0.64, 0.80, 0.92, 1.0],
        ),
      );
    }

    return _EngagementLegendItem(
      label: row.label,
      value: row.totalUsers,
      color: _palette[index % _palette.length],
    );
  }

  String _normalizeOtherGenderLabel(String rawLabel) {
    final label = rawLabel.trim();
    final normalized = label.toLowerCase();
    const aliases = <String>{
      'other',
      'others',
      'unknown',
      'not specified',
      'prefer not to say',
      'non-binary',
      'non binary',
      'lgbtq+',
      'lgbtq',
    };
    if (aliases.contains(normalized)) {
      return _t('other');
    }
    return label.isEmpty ? _t('other') : label;
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (_loading) {
      body = const Expanded(child: Center(child: CircularProgressIndicator()));
    } else if (_error != null) {
      body = Expanded(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _load,
                child: Text(_t('retry')),
              ),
            ],
          ),
        ),
      );
    } else if (_rows.isEmpty) {
      body = const Expanded(child: EmptyInfo());
    } else {
      final sections = List<_EngagementLegendItem>.generate(
        _rows.length,
        (index) => _buildSection(_rows[index], index),
      );

      body = Expanded(
        child: SingleChildScrollView(
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
                        label: _t('category'),
                        value: _selectedGroupBy == 'gender'
                            ? _t('gender')
                            : _selectedGroupBy == 'age'
                                ? _t('age')
                                : _selectedGroupBy == 'occupation'
                                    ? _t('occupation')
                                    : _t('province_label'),
                      ),
                      const SizedBox(height: 8),
                      SummaryField(
                        label: _t('month'),
                        value: _monthLabelsLocalized[_selectedMonth],
                      ),
                      const SizedBox(height: 8),
                      SummaryField(
                        label: _t('total_users'),
                        value: _totalUsers.toString(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: _EngagementPieChart(
                    sections: sections,
                    total: _totalUsers,
                  ),
                ),
                const SizedBox(height: 16),
                _EngagementLegend(
                  sections: sections,
                  total: _totalUsers,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: MiniDropdown(
                  value: _selectedGroupBy == 'gender'
                      ? _t('gender')
                      : _selectedGroupBy == 'age'
                          ? _t('age')
                          : _selectedGroupBy == 'occupation'
                              ? _t('occupation')
                              : _t('province_label'),
                  items: _groupLabelsLocalized,
                  onChanged: (value) {
                    final selected = value == _t('gender')
                        ? 'gender'
                        : value == _t('age')
                            ? 'age'
                            : value == _t('occupation')
                                ? 'occupation'
                                : 'province';
                    _changeGroupBy(selected);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MiniDropdown(
                  value: _monthLabelsLocalized[_selectedMonth],
                  items: _monthLabelsLocalized.skip(1).toList(),
                  onChanged: (value) {
                    final month = _monthLabelsLocalized.indexOf(value);
                    if (month > 0) {
                      _changeMonth(month);
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: MiniDropdown(
                  value: _selectedYear.toString(),
                  items: _availableYears.isEmpty
                      ? <String>[_selectedYear.toString()]
                      : _availableYears.map((year) => year.toString()).toList(),
                  onChanged: (value) {
                    final year = int.tryParse(value);
                    if (year != null) {
                      _changeYear(year);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}

class _EngagementLegendItem {
  final String label;
  final int value;
  final Color? color;
  final Gradient? gradient;

  const _EngagementLegendItem({
    required this.label,
    required this.value,
    this.color,
    this.gradient,
  });
}

class _EngagementPieChart extends StatelessWidget {
  final List<_EngagementLegendItem> sections;
  final int total;

  const _EngagementPieChart({
    required this.sections,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      height: 240,
      child: CustomPaint(
        painter: _EngagementPiePainter(
          sections: sections,
          total: total,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AdminStrings.text('top_10'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '$total ${AdminStrings.text('users_suffix')}',
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EngagementLegend extends StatelessWidget {
  final List<_EngagementLegendItem> sections;
  final int total;

  const _EngagementLegend({
    required this.sections,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: sections.map((section) {
        final percent = total == 0 ? 0 : (section.value / total) * 100;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: section.gradient == null ? section.color : null,
                  gradient: section.gradient,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  section.label,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text('${section.value}'),
              const SizedBox(width: 8),
              Text('${percent.toStringAsFixed(1)}%'),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _EngagementPiePainter extends CustomPainter {
  final List<_EngagementLegendItem> sections;
  final int total;

  const _EngagementPiePainter({
    required this.sections,
    required this.total,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 36
      ..strokeCap = StrokeCap.butt;

    if (total <= 0 || sections.isEmpty) {
      paint.color = Colors.black12;
      canvas.drawCircle(center, radius, paint);
      return;
    }

    double startAngle = -math.pi / 2;
    for (final section in sections) {
      final sweepAngle = (section.value / total) * math.pi * 2;
      paint
        ..shader = null
        ..color = section.color ?? Colors.transparent;
      if (section.gradient != null) {
        paint.shader = section.gradient!.createShader(rect);
      }
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _EngagementPiePainter oldDelegate) {
    return oldDelegate.sections != sections || oldDelegate.total != total;
  }
}
