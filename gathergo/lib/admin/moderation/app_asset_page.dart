import 'package:flutter/material.dart';

import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import 'spot_chat_moderation_api.dart';

class AppAssetPage extends StatefulWidget {
  const AppAssetPage({super.key});

  @override
  State<AppAssetPage> createState() => _AppAssetPageState();
}

class _AppAssetPageState extends State<AppAssetPage> {
  OpenAIReasonedUsageReport? _usageReport;
  String? _usageError;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
    _loadData();
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

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      OpenAIReasonedUsageReport? usageReport;
      String? usageError;

      try {
        usageReport = await SpotChatModerationApi.fetchOpenAIReasonedUsage();
      } catch (e) {
        usageError = e.toString();
      }

      if (!mounted) return;
      setState(() {
        _usageReport = usageReport;
        _usageError = usageError;
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

  String _formatUsd(double value) {
    return '\$${value.toStringAsFixed(4)}';
  }

  String _formatCompactNumber(int value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toString();
  }

  Widget _buildUsageCard() {
    final usage = _usageReport;

    Widget metric(String label, String value, Color color) {
      return Container(
        width: 188,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    Widget sourceLine(
      String label,
      OpenAIReasonedUsageTotals totals,
      Color color,
    ) {
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontWeight: FontWeight.w800, color: color),
              ),
            ),
            Text(
              '${totals.used}/${totals.attempts} ${_t('used_suffix')}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            const SizedBox(width: 10),
            Text(
              '${_formatCompactNumber(totals.totalTokens)} ${_t('tok_suffix')}',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
            const SizedBox(width: 10),
            Text(
              _formatUsd(totals.estimatedCostUsd),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ],
        ),
      );
    }

    if (_usageError != null && usage == null) {
      return _sectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('openai_reasoned_usage'),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(_usageError!, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      );
    }

    if (usage == null) {
      return _sectionCard(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Text(
                _t('no_usage_data_available'),
                style: TextStyle(color: Colors.black54),
              ),
      );
    }

    final today = usage.today;
    final month = usage.month;

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('openai_reasoned_usage'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            _t('openai_reasoned_usage_subtitle'),
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              metric(_t('today_cost'), _formatUsd(today.total.estimatedCostUsd),
                  const Color(0xFF1565C0)),
              metric(_t('month_cost'), _formatUsd(month.total.estimatedCostUsd),
                  const Color(0xFF6A1B9A)),
              metric(
                  _t('today_used'),
                  '${today.total.used}/${today.total.attempts}',
                  const Color(0xFF2E7D32)),
              metric(
                  _t('month_tokens'),
                  _formatCompactNumber(month.total.totalTokens),
                  const Color(0xFFEF6C00)),
            ],
          ),
          const SizedBox(height: 10),
          sourceLine(
              _t('today_preview'), today.preview, const Color(0xFF00897B)),
          sourceLine(
              _t('today_spot_chat'), today.spotChat, const Color(0xFF5E35B1)),
          sourceLine(
              _t('month_preview'), month.preview, const Color(0xFF00695C)),
          sourceLine(
              _t('month_spot_chat'), month.spotChat, const Color(0xFF4527A0)),
          const SizedBox(height: 10),
          Text(
            '${_t('pricing')}: input \$${usage.inputUsdPer1MTokens}/1M, output \$${usage.outputUsdPer1MTokens}/1M',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Text(
          _t('app_asset'),
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(onPressed: _loadData, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: _error != null
                ? ListView(
                    children: [
                      _sectionCard(
                        child: Column(
                          children: [
                            Text(
                              _error!,
                              style: const TextStyle(color: Colors.black54),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _loadData,
                              child: Text(_t('retry')),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _buildUsageCard(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
