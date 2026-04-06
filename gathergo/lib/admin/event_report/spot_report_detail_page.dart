import 'package:flutter/material.dart';

import 'report_models.dart';

class SpotReportDetailPage extends StatelessWidget {
  final SpotLeaveFeedbackRow row;

  const SpotReportDetailPage({
    super.key,
    required this.row,
  });

  String _targetLabel() {
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

  String _formatDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}-$month-$day $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      appBar: AppBar(
        title: const Text('Spot Report Detail'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
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
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    border: Border.all(color: Color(0xFFD92D20), width: 1.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Report Detail',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 16),
                _DetailBlock(label: 'Event', value: '${row.eventId}'),
                _DetailBlock(label: 'Event Title', value: row.eventTitle),
                _DetailBlock(
                  label: 'Reporter / Leaver',
                  value: row.leaverUserName,
                ),
                _DetailBlock(label: 'Reason', value: row.reasonText),
                _DetailBlock(label: 'Target', value: _targetLabel()),
                _DetailBlock(
                  label: 'Created At',
                  value: _formatDate(row.createdAt),
                ),
                _ReportDetailBlock(
                  label: 'Written Report Text',
                  value: row.reportDetailText ?? '-',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String label;
  final String value;

  const _DetailBlock({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: RichText(
          text: TextSpan(
            style: DefaultTextStyle.of(context).style.copyWith(fontSize: 14),
            children: [
              TextSpan(
                text: '$label: ',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              TextSpan(text: value),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportDetailBlock extends StatelessWidget {
  final String label;
  final String value;

  const _ReportDetailBlock({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RichText(
              text: TextSpan(
                style:
                    DefaultTextStyle.of(context).style.copyWith(fontSize: 14),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.topLeft,
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
