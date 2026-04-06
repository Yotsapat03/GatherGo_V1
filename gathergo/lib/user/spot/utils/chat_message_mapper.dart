import '../model/chat_message_model.dart';

enum ChatMessageUiState {
  safe,
  suspicious,
  phishing,
  hidden,
  scanning,
}

class ChatMessageUiData {
  final ChatMessageUiState state;
  final String? helperText;
  final bool showRiskBadge;

  const ChatMessageUiData({
    required this.state,
    this.helperText,
    this.showRiskBadge = false,
  });
}

ChatMessageUiData mapChatMessageToUiState(ChatMessageModel message) {
  if (message.moderationStatus == ModerationStatus.hidden) {
    return const ChatMessageUiData(
      state: ChatMessageUiState.hidden,
      helperText: 'Message hidden for safety',
    );
  }

  if (message.moderationStatus == ModerationStatus.blocked ||
      message.riskLevel == RiskLevel.phishing) {
    return ChatMessageUiData(
      state: ChatMessageUiState.phishing,
      helperText: _buildReason(
        message.phishingScanReason,
        'This message may contain a dangerous phishing link.',
      ),
      showRiskBadge: true,
    );
  }

  if (message.containsUrl &&
      message.phishingScanStatus == PhishingScanStatus.scanning) {
    return const ChatMessageUiData(
      state: ChatMessageUiState.scanning,
      helperText: 'Scanning link...',
    );
  }

  if (message.moderationStatus == ModerationStatus.warning ||
      message.riskLevel == RiskLevel.suspicious) {
    return ChatMessageUiData(
      state: ChatMessageUiState.suspicious,
      helperText: _buildReason(
        message.phishingScanReason,
        'Be careful. This message may contain a suspicious link.',
      ),
      showRiskBadge: true,
    );
  }

  return const ChatMessageUiData(state: ChatMessageUiState.safe);
}

String _buildReason(String? value, String fallback) {
  final text = value?.trim();
  return (text == null || text.isEmpty) ? fallback : text;
}
