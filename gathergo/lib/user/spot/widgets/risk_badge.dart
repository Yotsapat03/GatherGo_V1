import 'package:flutter/material.dart';

import '../model/chat_message_model.dart';

class RiskBadge extends StatelessWidget {
  final RiskLevel riskLevel;

  const RiskBadge({
    super.key,
    required this.riskLevel,
  });

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(riskLevel);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: style.backgroundColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        style.label,
        style: TextStyle(
          color: style.textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  _RiskBadgeStyle _styleFor(RiskLevel level) {
    switch (level) {
      case RiskLevel.suspicious:
        return const _RiskBadgeStyle(
          label: 'Suspicious',
          backgroundColor: Color(0xFFFFF3CD),
          textColor: Color(0xFF8A6D1D),
        );
      case RiskLevel.phishing:
        return const _RiskBadgeStyle(
          label: 'Phishing Risk',
          backgroundColor: Color(0xFFF8D7DA),
          textColor: Color(0xFF842029),
        );
      case RiskLevel.safe:
        return const _RiskBadgeStyle(
          label: 'Safe',
          backgroundColor: Color(0xFFD1E7DD),
          textColor: Color(0xFF0F5132),
        );
    }
  }
}

class _RiskBadgeStyle {
  final String label;
  final Color backgroundColor;
  final Color textColor;

  const _RiskBadgeStyle({
    required this.label,
    required this.backgroundColor,
    required this.textColor,
  });
}
