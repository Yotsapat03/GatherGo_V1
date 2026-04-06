import 'dart:convert';

import 'package:flutter/material.dart';

import '../localization/admin_locale_controller.dart';
import '../localization/admin_strings.dart';
import 'spot_chat_moderation_api.dart';

class AdminSpotChatModerationQueuePage extends StatefulWidget {
  const AdminSpotChatModerationQueuePage({super.key});

  @override
  State<AdminSpotChatModerationQueuePage> createState() =>
      _AdminSpotChatModerationQueuePageState();
}

class _AdminSpotChatModerationQueuePageState
    extends State<AdminSpotChatModerationQueuePage> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _expandedIds = <int>{};
  final Set<int> _busyIds = <int>{};

  bool _loading = true;
  String? _error;
  SpotChatModerationSummary? _summary;
  OpenAIReasonedUsageReport? _usageReport;
  String? _usageError;
  SpotChatModerationTrends? _trends;
  String? _trendsError;
  String _trendsRange = '30d';
  List<SpotChatModerationAuditFeedItem> _auditFeed = const [];
  String? _auditFeedError;
  List<ModerationLearningQueueItem> _learningQueue = const [];
  String? _learningQueueError;
  int _auditFeedLimit = 20;
  String _statusFilter = 'pending';
  String _severityFilter = 'all';
  List<SpotChatModerationQueueItem> _rows = const [];

  @override
  void initState() {
    super.initState();
    AdminLocaleController.languageCode.addListener(_handleLanguageChanged);
    _loadQueue();
  }

  @override
  void dispose() {
    AdminLocaleController.languageCode.removeListener(_handleLanguageChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _handleLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _t(String key, {Map<String, String> params = const {}}) {
    return AdminStrings.text(key, params: params);
  }

  String _statusLabel(String status) => _t(status);

  String _severityLabel(String severity) => _t(severity);

  String _yesNoValue(bool value, {String? withValue}) {
    if (!value) return _t('no');
    if (withValue == null || withValue.isEmpty) return _t('yes');
    return '${_t('yes')} / $withValue';
  }

  Future<void> _loadQueue() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final summary = await SpotChatModerationApi.fetchSummary();
      OpenAIReasonedUsageReport? usageReport;
      String? usageError;
      final rows =
          await SpotChatModerationApi.fetchQueue(status: _statusFilter);
      SpotChatModerationTrends? trends;
      String? trendsError;
      List<SpotChatModerationAuditFeedItem> auditFeed = const [];
      String? auditFeedError;
      List<ModerationLearningQueueItem> learningQueue = const [];
      String? learningQueueError;
      try {
        usageReport = await SpotChatModerationApi.fetchOpenAIReasonedUsage();
      } catch (e) {
        usageError = e.toString();
      }
      try {
        trends = await SpotChatModerationApi.fetchTrends(
          range: _trendsRange,
          bucket: _bucketForRange(_trendsRange),
        );
      } catch (e) {
        trendsError = e.toString();
      }
      try {
        auditFeed = await SpotChatModerationApi.fetchAuditFeed(
          limit: _auditFeedLimit,
        );
      } catch (e) {
        auditFeedError = e.toString();
      }
      try {
        learningQueue = await SpotChatModerationApi.fetchLearningQueue();
      } catch (e) {
        learningQueueError = e.toString();
      }
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _usageReport = usageReport;
        _usageError = usageError;
        _trends = trends;
        _trendsError = trendsError;
        _auditFeed = auditFeed;
        _auditFeedError = auditFeedError;
        _learningQueue = learningQueue;
        _learningQueueError = learningQueueError;
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

  String _bucketForRange(String range) {
    return range == '90d' ? 'week' : 'day';
  }

  List<SpotChatModerationQueueItem> get _filteredRows {
    final search = _searchController.text.trim().toLowerCase();

    return _rows.where((item) {
      final severityMatches =
          _severityFilter == 'all' || item.severity == _severityFilter;
      if (!severityMatches) return false;

      if (search.isEmpty) return true;

      return item.userId.toString().contains(search) ||
          item.spotKey.toLowerCase().contains(search) ||
          item.rawMessage.toLowerCase().contains(search) ||
          item.normalizedMessage.toLowerCase().contains(search) ||
          item.detectedCategories.any((category) => category.contains(search));
    }).toList();
  }

  Color _severityColor(String severity) {
    switch (severity) {
      case 'critical':
        return const Color(0xFFD32F2F);
      case 'high':
        return const Color(0xFFF57C00);
      case 'medium':
        return const Color(0xFFFBC02D);
      case 'low':
        return const Color(0xFF90A4AE);
      default:
        return const Color(0xFFB0BEC5);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'dismissed':
        return const Color(0xFF78909C);
      case 'confirmed':
        return const Color(0xFF1976D2);
      case 'suspended':
        return const Color(0xFFD32F2F);
      case 'pending':
      case 'open':
      default:
        return const Color(0xFF5D4037);
    }
  }

  String _formatDateTime(DateTime? value) {
    if (value == null) return '-';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} ${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> _runAction(
    SpotChatModerationQueueItem item,
    String actionLabel,
    Future<void> Function() action,
  ) async {
    setState(() => _busyIds.add(item.id));
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'queue_action_completed',
              params: {'action': actionLabel, 'id': item.id.toString()},
            ),
          ),
        ),
      );
      await _loadQueue();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _busyIds.remove(item.id));
      }
    }
  }

  Future<void> _confirmSuspend(SpotChatModerationQueueItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(_t('suspend_user')),
        content: Text(
          _t(
            'suspend_user_confirm',
            params: {
              'userId': item.userId.toString(),
              'id': item.id.toString(),
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_t('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_t('suspend')),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _runAction(
        item,
        _t('suspend_user'),
        () => SpotChatModerationApi.suspendUserFromCase(item.id),
      );
    }
  }

  Future<void> _openLearningQueueDialog(
      SpotChatModerationQueueItem item) async {
    final noteController = TextEditingController();
    final termsController = TextEditingController(
      text: item.rawMessage.trim().isEmpty ? '' : item.rawMessage.trim(),
    );
    final categoriesController = TextEditingController(
      text: item.detectedCategories.join(', '),
    );
    String selectedAction =
        item.actionTaken.startsWith('block') ? 'block' : 'review';

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            title: Text(_t('send_to_learning_queue')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.rawMessage,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedAction,
                    decoration:
                        InputDecoration(labelText: _t('suggested_action')),
                    items: const [
                      DropdownMenuItem(value: 'allow', child: Text('allow')),
                      DropdownMenuItem(value: 'review', child: Text('review')),
                      DropdownMenuItem(value: 'block', child: Text('block')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setModalState(() => selectedAction = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: categoriesController,
                    decoration: InputDecoration(
                      labelText: _t('suggested_categories'),
                      hintText: 'hate_speech, protected_class_attack',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: termsController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: _t('candidate_terms_phrases'),
                      hintText: 'ladyboy country, country of ladyboys',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: _t('admin_note'),
                      hintText: _t('learning_note_hint'),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_t('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(_t('queue')),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true) return;

      final suggestedCategories = categoriesController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      final candidateTerms = termsController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();

      await SpotChatModerationApi.createLearningQueueItem(
        moderationQueueId: item.id,
        rawMessage: item.rawMessage,
        normalizedMessage: item.normalizedMessage,
        currentCategories: item.detectedCategories,
        suggestedAction: selectedAction,
        suggestedCategories: suggestedCategories,
        candidateTerms: candidateTerms,
        adminNote: noteController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'queued_case_for_learning',
              params: {'id': item.id.toString()},
            ),
          ),
        ),
      );
      await _loadQueue();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      noteController.dispose();
      termsController.dispose();
      categoriesController.dispose();
    }
  }

  Future<void> _openLearningImportDialog() async {
    final contentController = TextEditingController();
    final categoriesController = TextEditingController(text: 'scam_risk');
    final noteController = TextEditingController(
      text: _t('imported_external_admin_review'),
    );
    String selectedFormat = 'json';
    String selectedAction = 'review';

    const csvTemplate =
        'raw_message,suggested_categories,candidate_terms,admin_note\n'
        '"send ur passport pic","scam_risk","passport pic|passport","external scam list"\n'
        '"ladyboy country","hate_speech|protected_class_attack","ladyboy country","external hate phrase list"';
    const jsonTemplate = '[\n'
        '  {\n'
        '    "raw_message": "send ur passport pic",\n'
        '    "suggested_categories": ["scam_risk"],\n'
        '    "candidate_terms": ["passport pic", "passport"],\n'
        '    "admin_note": "external scam list"\n'
        '  }\n'
        ']';
    contentController.text = jsonTemplate;

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            title: Text(_t('import_external_terms')),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t('import_external_terms_hint'),
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedFormat,
                      decoration:
                          InputDecoration(labelText: _t('import_format')),
                      items: const [
                        DropdownMenuItem(value: 'json', child: Text('json')),
                        DropdownMenuItem(value: 'csv', child: Text('csv')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() {
                          selectedFormat = value;
                          contentController.text =
                              value == 'csv' ? csvTemplate : jsonTemplate;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedAction,
                      decoration: InputDecoration(
                        labelText: _t('default_suggested_action'),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'review', child: Text('review')),
                        DropdownMenuItem(value: 'block', child: Text('block')),
                        DropdownMenuItem(value: 'allow', child: Text('allow')),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() => selectedAction = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: categoriesController,
                      decoration: InputDecoration(
                        labelText: _t('default_categories'),
                        hintText: 'scam_risk, hate_speech',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      minLines: 2,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: _t('default_admin_note'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: contentController,
                      minLines: 10,
                      maxLines: 18,
                      decoration: InputDecoration(
                        labelText: _t('import_content'),
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_t('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(_t('import')),
              ),
            ],
          ),
        ),
      );

      if (confirmed != true) return;

      final defaultCategories = categoriesController.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();

      final importedCount =
          await SpotChatModerationApi.importLearningQueueItems(
        format: selectedFormat,
        content: contentController.text,
        defaultSuggestedAction: selectedAction,
        defaultSuggestedCategories: defaultCategories,
        defaultAdminNote: noteController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'imported_entries_learning_queue',
              params: {'count': importedCount.toString()},
            ),
          ),
        ),
      );
      await _loadQueue();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      contentController.dispose();
      categoriesController.dispose();
      noteController.dispose();
    }
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Colors.black : const Color(0xFFECECEC),
          borderRadius: BorderRadius.circular(20),
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

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.32)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _buildMetaLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 132,
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    final summary = _summary;
    if (summary == null) return const SizedBox.shrink();

    Widget stat(String label, int value, Color color) {
      return Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$value',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('moderation_summary'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              stat(_t('moderated'), summary.totalModeratedMessages,
                  const Color(0xFF37474F)),
              stat(_t('blocked'), summary.totalBlockedMessages,
                  const Color(0xFFD32F2F)),
              stat(_t('flagged'), summary.totalFlaggedMessages,
                  const Color(0xFFF9A825)),
              stat(_t('profanity'), summary.totalProfanityCases,
                  const Color(0xFF90A4AE)),
              stat(_t('hate_speech'), summary.totalHateSpeechCases,
                  const Color(0xFFEF6C00)),
              stat(_t('sexual_harassment'), summary.totalSexualHarassmentCases,
                  const Color(0xFFC62828)),
              stat(_t('scam_risk'), summary.totalScamRiskCases,
                  const Color(0xFF6A1B9A)),
              stat(_t('room_alerts'), summary.totalRoomAlertsCreated,
                  const Color(0xFFD84315)),
              stat(_t('dismissed'), summary.totalAdminDismissed,
                  const Color(0xFF546E7A)),
              stat(_t('confirmed'), summary.totalAdminConfirmed,
                  const Color(0xFF1565C0)),
              stat(
                  _t('suspended_users'),
                  summary.totalUsersSuspendedForModeration,
                  const Color(0xFFB71C1C)),
              stat(_t('ai_used'), summary.totalAiUsedCases,
                  const Color(0xFF283593)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatUsd(double value) {
    return '\$${value.toStringAsFixed(value >= 1 ? 2 : 4)}';
  }

  String _formatCompactNumber(num value) {
    if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
    return value.toStringAsFixed(0);
  }

  Widget _buildUsageCard() {
    final usage = _usageReport;
    if (usage == null && _usageError == null) return const SizedBox.shrink();

    Widget metric(String label, String value, Color color) {
      return Container(
        width: 150,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(label,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      );
    }

    Widget sourceLine(
        String label, OpenAIReasonedUsageTotals totals, Color color) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
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
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _t('openai_reasoned_usage'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(_usageError!, style: const TextStyle(color: Colors.black54)),
          ],
        ),
      );
    }

    final today = usage!.today;
    final month = usage.month;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
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
            style: const TextStyle(color: Colors.black54, fontSize: 12),
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
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendsSection() {
    final trends = _trends;

    Widget rangeChip(String label) {
      final selected = _trendsRange == label;
      return InkWell(
        onTap: () {
          if (selected) return;
          setState(() => _trendsRange = label);
          _loadQueue();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.black : const Color(0xFFECECEC),
            borderRadius: BorderRadius.circular(20),
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

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('moderation_trends'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              Wrap(
                spacing: 8,
                children: ['7d', '30d', '90d'].map(rangeChip).toList(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading && trends == null)
            const Center(child: CircularProgressIndicator())
          else if (_trendsError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_trendsError!,
                    style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _loadQueue,
                  child: Text(_t('retry')),
                ),
              ],
            )
          else if (trends == null || trends.points.isEmpty)
            Text(
              _t('no_moderation_trend_data'),
              style: const TextStyle(color: Colors.black54),
            )
          else ...[
            _TrendChartCard(
              title: _t('moderated_vs_blocked'),
              subtitle: '${trends.range} | ${_t(trends.bucket)}',
              primaryColor: const Color(0xFF1565C0),
              secondaryColor: const Color(0xFFD32F2F),
              primaryLabel: _t('moderated'),
              secondaryLabel: _t('blocked'),
              points: trends.points,
              primaryValue: (point) => point.totalModerated,
              secondaryValue: (point) => point.blocked,
            ),
            const SizedBox(height: 10),
            _TrendChartCard(
              title: _t('category_trends'),
              subtitle: _t('category_trends_subtitle'),
              primaryColor: const Color(0xFF6A1B9A),
              secondaryColor: const Color(0xFFC62828),
              tertiaryColor: const Color(0xFFEF6C00),
              quaternaryColor: const Color(0xFF90A4AE),
              primaryLabel: _t('scam'),
              secondaryLabel: _t('sexual'),
              tertiaryLabel: _t('hate'),
              quaternaryLabel: _t('profanity'),
              points: trends.points,
              primaryValue: (point) => point.scamRisk,
              secondaryValue: (point) => point.sexualHarassment,
              tertiaryValue: (point) => point.hateSpeech,
              quaternaryValue: (point) => point.profanity,
            ),
            const SizedBox(height: 10),
            _TrendChartCard(
              title: _t('ai_used_trend'),
              subtitle: _t('ai_used_trend_subtitle'),
              primaryColor: const Color(0xFF283593),
              primaryLabel: _t('ai_used'),
              points: trends.points,
              primaryValue: (point) => point.aiUsed,
            ),
          ],
        ],
      ),
    );
  }

  Color _activityColor(String action) {
    switch (action) {
      case 'USER_SUSPENDED_FOR_MODERATION':
      case 'SPOT_CHAT_QUEUE_SUSPEND_USER':
        return const Color(0xFFD32F2F);
      case 'SPOT_CHAT_ROOM_ALERT_CREATED':
        return const Color(0xFFE65100);
      case 'SPOT_CHAT_QUEUE_CONFIRMED':
        return const Color(0xFF1565C0);
      case 'SPOT_CHAT_QUEUE_DISMISSED':
        return const Color(0xFF546E7A);
      default:
        return const Color(0xFF6A1B9A);
    }
  }

  IconData _activityIcon(String action) {
    switch (action) {
      case 'USER_SUSPENDED_FOR_MODERATION':
      case 'SPOT_CHAT_QUEUE_SUSPEND_USER':
        return Icons.block;
      case 'SPOT_CHAT_ROOM_ALERT_CREATED':
        return Icons.warning_amber_rounded;
      case 'SPOT_CHAT_QUEUE_CONFIRMED':
        return Icons.gavel_outlined;
      case 'SPOT_CHAT_QUEUE_DISMISSED':
        return Icons.check_circle_outline;
      default:
        return Icons.history;
    }
  }

  String _activitySummary(SpotChatModerationAuditFeedItem item) {
    final metadata = item.metadataJson;
    final targetUser = metadata['target_user_id'] ?? item.userId;
    final queueId = metadata['moderation_queue_id'];
    final spotKey = metadata['spot_key'];
    final severity = metadata['severity'];

    final parts = <String>[
      if (targetUser != null && '$targetUser'.isNotEmpty)
        '${_t('user')} $targetUser',
      if (queueId != null && '$queueId'.isNotEmpty) '${_t('queue')} #$queueId',
      if (spotKey != null && '$spotKey'.isNotEmpty) 'Spot $spotKey',
      if (severity != null && '$severity'.isNotEmpty)
        '${_t('severity')} ${_severityLabel('$severity')}',
    ];
    return parts.isEmpty ? _t('no_extra_metadata') : parts.join(' | ');
  }

  Widget _buildActivityTimeline() {
    Widget limitChip(int value) {
      final selected = _auditFeedLimit == value;
      return InkWell(
        onTap: () {
          if (selected) return;
          setState(() => _auditFeedLimit = value);
          _loadQueue();
        },
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? Colors.black : const Color(0xFFECECEC),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$value',
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('recent_moderation_activity'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              Wrap(
                spacing: 8,
                children: [10, 20, 50].map(limitChip).toList(),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading && _auditFeed.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_auditFeedError != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_auditFeedError!,
                    style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _loadQueue,
                  child: Text(_t('retry')),
                ),
              ],
            )
          else if (_auditFeed.isEmpty)
            Text(
              _t('no_recent_moderation_activity'),
              style: const TextStyle(color: Colors.black54),
            )
          else
            Column(
              children: _auditFeed.map((item) {
                final color = _activityColor(item.action);
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withValues(alpha: 0.22)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_activityIcon(item.action),
                            color: color, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.action,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: color,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _activitySummary(item),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatDateTime(item.createdAt),
                              style: const TextStyle(
                                color: Colors.black54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildLearningQueueSection() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('learning_queue'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w900),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _openLearningImportDialog,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(_t('import_csv_json')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _t('learning_queue_description'),
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (_loading && _learningQueue.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_learningQueueError != null)
            Text(_learningQueueError!,
                style: const TextStyle(color: Colors.black54))
          else if (_learningQueue.isEmpty)
            Text(_t('no_pending_learning_items'),
                style: const TextStyle(color: Colors.black54))
          else
            Column(
              children: _learningQueue.take(8).map((item) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F7F7),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.rawMessage,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(
                        '${_t('action')}: ${item.suggestedAction} | ${_t('categories')}: ${item.suggestedCategories.join(", ")}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      if (item.candidateTerms.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${_t('terms')}: ${item.candidateTerms.join(", ")}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black54),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: !item.isPending
                                ? null
                                : () => _runLearningQueueAction(
                                      item,
                                      _t('apply_learning'),
                                      () => SpotChatModerationApi
                                          .applyLearningQueueItem(item.id),
                                    ),
                            icon: const Icon(Icons.auto_fix_high),
                            label: Text(_t('apply')),
                          ),
                          OutlinedButton.icon(
                            onPressed: !item.isPending
                                ? null
                                : () => _runLearningQueueAction(
                                      item,
                                      _t('reject_learning'),
                                      () => SpotChatModerationApi
                                          .rejectLearningQueueItem(item.id),
                                    ),
                            icon: const Icon(Icons.close),
                            label: Text(_t('reject')),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Future<void> _runLearningQueueAction(
    ModerationLearningQueueItem item,
    String actionLabel,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              'learning_action_completed',
              params: {'action': actionLabel, 'id': item.id.toString()},
            ),
          ),
        ),
      );
      await _loadQueue();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Widget _buildJsonBlock(String title, Object? value) {
    final pretty = const JsonEncoder.withIndent('  ').convert(value ?? {});
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7F7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
          const SizedBox(height: 8),
          SelectableText(
            pretty,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaseCard(SpotChatModerationQueueItem item) {
    final expanded = _expandedIds.contains(item.id);
    final busy = _busyIds.contains(item.id);
    final severityColor = _severityColor(item.severity);
    final statusColor = _statusColor(item.queueStatus);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.rawMessage.isEmpty ? '-' : item.rawMessage,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildChip(
                              _severityLabel(item.severity).toUpperCase(),
                              severityColor),
                          _buildChip(
                              _statusLabel(item.queueStatus).toUpperCase(),
                              statusColor),
                          _buildChip(item.actionTaken, Colors.black87),
                          if (item.alertRoom)
                            _buildChip(
                              _t('room_alert'),
                              const Color(0xFFD84315),
                            ),
                          if (item.suspensionRequired)
                            _buildChip(_t('suspension_required'),
                                const Color(0xFFC62828)),
                          if (item.aiUsed)
                            _buildChip(
                              item.aiConfidence == null
                                  ? _t('ai_used')
                                  : 'AI ${item.aiConfidence!.toStringAsFixed(2)}',
                              const Color(0xFF1565C0),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      if (expanded) {
                        _expandedIds.remove(item.id);
                      } else {
                        _expandedIds.add(item.id);
                      }
                    });
                  },
                  icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildMetaLine(_t('user_id'), '${item.userId}'),
            _buildMetaLine(_t('spot_key'), item.spotKey),
            _buildMetaLine(
                _t('spot_event_id'), item.spotEventId?.toString() ?? '-'),
            _buildMetaLine(
              _t('detected_categories'),
              item.detectedCategories.isEmpty
                  ? '-'
                  : item.detectedCategories.join(', '),
            ),
            _buildMetaLine(_t('created_at'), _formatDateTime(item.createdAt)),
            _buildMetaLine(
              _t('ai_used_confidence'),
              _yesNoValue(
                item.aiUsed,
                withValue: item.aiConfidence?.toStringAsFixed(2),
              ),
            ),
            if (expanded) ...[
              const Divider(height: 22),
              _buildMetaLine(
                  _t('normalized_message'),
                  item.normalizedMessage.isEmpty
                      ? '-'
                      : item.normalizedMessage),
              _buildMetaLine(_t('priority'), item.priority),
              _buildMetaLine(_t('message_id'),
                  item.messageId?.toString() ?? _t('blocked_null')),
              _buildMetaLine(
                  _t('reviewed_at'), _formatDateTime(item.reviewedAt)),
              _buildMetaLine(_t('reviewed_by_admin'),
                  item.reviewedByAdminId?.toString() ?? '-'),
              _buildMetaLine(_t('review_note'), item.reviewNote ?? '-'),
              if (item.alertRoom)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3E0),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _t('scam_risk_case_notice'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE65100),
                    ),
                  ),
                ),
              if (item.suspensionRequired)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _t('severe_case_notice'),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFC62828),
                    ),
                  ),
                ),
              _buildJsonBlock(_t('rule_hits'), item.ruleHits),
              _buildJsonBlock(_t('ai_result'), item.aiResultJson),
              _buildJsonBlock(_t('review_payload'), item.reviewPayload),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy || !item.isActive
                      ? null
                      : () => _runAction(
                            item,
                            _t('dismiss'),
                            () => SpotChatModerationApi.dismissCase(item.id),
                          ),
                  icon: busy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(_t('dismiss')),
                ),
                ElevatedButton.icon(
                  onPressed: busy || !item.isActive
                      ? null
                      : () => _runAction(
                            item,
                            _t('confirm_violation'),
                            () => SpotChatModerationApi.confirmCase(item.id),
                          ),
                  icon: const Icon(Icons.gavel_outlined),
                  label: Text(_t('confirm_violation')),
                ),
                ElevatedButton.icon(
                  onPressed: busy || !item.isActive
                      ? null
                      : () => _confirmSuspend(item),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.block),
                  label: Text(_t('suspend_user')),
                ),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _openLearningQueueDialog(item),
                  icon: const Icon(Icons.school_outlined),
                  label: Text(_t('send_to_learning')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(
          _t('spot_chat_moderation'),
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            onPressed: _loadQueue,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: RefreshIndicator(
            onRefresh: _loadQueue,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _buildSummaryCard(),
                _buildUsageCard(),
                _buildTrendsSection(),
                _buildActivityTimeline(),
                _buildLearningQueueSection(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _t('moderation_queue'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: _t('moderation_search_hint'),
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: const Color(0xFFF7F7F7),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _t('status'),
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final status in [
                            'pending',
                            'confirmed',
                            'dismissed',
                            'suspended',
                            'all'
                          ])
                            _buildFilterChip(
                              label: _statusLabel(status),
                              selected: _statusFilter == status,
                              onTap: () {
                                setState(() => _statusFilter = status);
                                _loadQueue();
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _t('severity'),
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final severity in [
                            'all',
                            'low',
                            'medium',
                            'high',
                            'critical'
                          ])
                            _buildFilterChip(
                              label: _severityLabel(severity),
                              selected: _severityFilter == severity,
                              onTap: () =>
                                  setState(() => _severityFilter = severity),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!, textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _loadQueue,
                            child: Text(_t('retry')),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (rows.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        _t('no_moderation_cases_found'),
                        style: TextStyle(color: Colors.black54),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  ...rows.map(_buildCaseCard),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrendChartCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color primaryColor;
  final String primaryLabel;
  final Color? secondaryColor;
  final String? secondaryLabel;
  final Color? tertiaryColor;
  final String? tertiaryLabel;
  final Color? quaternaryColor;
  final String? quaternaryLabel;
  final List<SpotChatModerationTrendPoint> points;
  final int Function(SpotChatModerationTrendPoint point) primaryValue;
  final int Function(SpotChatModerationTrendPoint point)? secondaryValue;
  final int Function(SpotChatModerationTrendPoint point)? tertiaryValue;
  final int Function(SpotChatModerationTrendPoint point)? quaternaryValue;

  const _TrendChartCard({
    required this.title,
    required this.subtitle,
    required this.primaryColor,
    required this.primaryLabel,
    this.secondaryColor,
    this.secondaryLabel,
    this.tertiaryColor,
    this.tertiaryLabel,
    this.quaternaryColor,
    this.quaternaryLabel,
    required this.points,
    required this.primaryValue,
    this.secondaryValue,
    this.tertiaryValue,
    this.quaternaryValue,
  });

  @override
  Widget build(BuildContext context) {
    final values = <int>[
      ...points.map(primaryValue),
      if (secondaryValue != null) ...points.map(secondaryValue!),
      if (tertiaryValue != null) ...points.map(tertiaryValue!),
      if (quaternaryValue != null) ...points.map(quaternaryValue!),
    ];
    final maxValue =
        values.fold<int>(0, (best, next) => next > best ? next : best);
    final safeMax = maxValue <= 0 ? 1 : maxValue;

    Widget legend(String label, Color color) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      );
    }

    Widget bar(Color color, int value) {
      final height = (value / safeMax) * 72;
      return Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            height: height < 4 && value > 0 ? 4 : height,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      );
    }

    String shortDate(String value) {
      if (value.length >= 10) {
        return value.substring(5);
      }
      return value;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3EAF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              legend(primaryLabel, primaryColor),
              if (secondaryColor != null && secondaryLabel != null)
                legend(secondaryLabel!, secondaryColor!),
              if (tertiaryColor != null && tertiaryLabel != null)
                legend(tertiaryLabel!, tertiaryColor!),
              if (quaternaryColor != null && quaternaryLabel != null)
                legend(quaternaryLabel!, quaternaryColor!),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: points.map((point) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              bar(primaryColor, primaryValue(point)),
                              if (secondaryValue != null &&
                                  secondaryColor != null) ...[
                                const SizedBox(width: 2),
                                bar(secondaryColor!, secondaryValue!(point)),
                              ],
                              if (tertiaryValue != null &&
                                  tertiaryColor != null) ...[
                                const SizedBox(width: 2),
                                bar(tertiaryColor!, tertiaryValue!(point)),
                              ],
                              if (quaternaryValue != null &&
                                  quaternaryColor != null) ...[
                                const SizedBox(width: 2),
                                bar(quaternaryColor!, quaternaryValue!(point)),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          shortDate(point.date),
                          style: const TextStyle(
                              fontSize: 10, color: Colors.black54),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
