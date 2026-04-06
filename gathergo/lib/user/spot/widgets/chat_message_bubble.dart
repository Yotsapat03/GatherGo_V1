import 'package:flutter/material.dart';

import '../model/chat_message_model.dart';
import '../utils/chat_message_mapper.dart';
import 'risk_badge.dart';

class ChatMessageBubble extends StatelessWidget {
  final ChatMessageModel message;
  final bool isMe;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final ui = mapChatMessageToUiState(message);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              _buildContent(ui),
              const SizedBox(height: 4),
              Text(
                _formatTime(message.createdAt),
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ChatMessageUiData ui) {
    switch (ui.state) {
      case ChatMessageUiState.hidden:
        return _HiddenCard(
          text: ui.helperText ?? 'Message hidden for safety',
        );
      case ChatMessageUiState.phishing:
        return _PhishingCard(
          text: ui.helperText,
          riskLevel: message.riskLevel,
        );
      case ChatMessageUiState.suspicious:
        return Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            _NormalBubble(
              message: message.body,
              isMe: isMe,
              badge: RiskBadge(riskLevel: message.riskLevel),
            ),
            const SizedBox(height: 6),
            _InfoBanner(
              icon: Icons.warning_amber_rounded,
              color: const Color(0xFFB26A00),
              backgroundColor: const Color(0xFFFFF8E1),
              borderColor: const Color(0xFFFFCA28),
              text: ui.helperText ?? 'Be careful. This link may be suspicious.',
            ),
          ],
        );
      case ChatMessageUiState.scanning:
        return Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            _NormalBubble(
              message: message.body,
              isMe: isMe,
            ),
            const SizedBox(height: 6),
            _StatusText(text: ui.helperText ?? 'Scanning link...'),
          ],
        );
      case ChatMessageUiState.safe:
        return _NormalBubble(
          message: message.body,
          isMe: isMe,
        );
    }
  }

  String _formatTime(DateTime value) {
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _NormalBubble extends StatelessWidget {
  final String message;
  final bool isMe;
  final Widget? badge;

  const _NormalBubble({
    required this.message,
    required this.isMe,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor =
        isMe ? const Color(0xFFDCF8E8) : Colors.white;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EAF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badge != null) ...[
            badge!,
            const SizedBox(height: 8),
          ],
          Text(
            message,
            style: const TextStyle(
              fontSize: 15.5,
              height: 1.35,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _PhishingCard extends StatelessWidget {
  final String? text;
  final RiskLevel riskLevel;

  const _PhishingCard({
    required this.text,
    required this.riskLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEBEE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE57373)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RiskBadge(riskLevel: riskLevel),
          const SizedBox(height: 10),
          const Row(
            children: [
              Icon(Icons.block, color: Color(0xFFC62828), size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Blocked suspicious link',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFC62828),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text ?? 'This message was blocked for safety.',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF7F1D1D),
            ),
          ),
        ],
      ),
    );
  }
}

class _HiddenCard extends StatelessWidget {
  final String text;

  const _HiddenCard({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEEEE),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.visibility_off, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.black54,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color backgroundColor;
  final Color borderColor;
  final String text;

  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.backgroundColor,
    required this.borderColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusText extends StatelessWidget {
  final String text;

  const _StatusText({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 12,
          height: 12,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}
