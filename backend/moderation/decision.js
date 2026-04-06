const ACTION_PRIORITY = {
  allow: 0,
  censor_and_warn: 1,
  block_and_flag: 2,
  block_and_report: 3,
  block_and_alert_room: 4,
  block_remove_and_report: 5,
};

const CATEGORY_ACTION_MAP = {
  profanity: "censor_and_warn",
  targeted_abuse: "block_and_report",
  hate_speech: "block_and_report",
  harassment: "block_and_flag",
  protected_class_attack: "block_and_report",
  dehumanization: "block_and_report",
  sexual_ambiguous: "block_and_flag",
  sexual_harassment: "block_remove_and_report",
  threat: "block_remove_and_report",
  scam_risk: "block_and_alert_room",
};
const PHISHING_OWNED_CATEGORIES = new Set(["scam_risk"]);
const PHISHING_OWNED_AI_REASONS = new Set([
  "ambiguous_scam_signal",
  "weak_scam_signal",
  "possible_obfuscation",
]);

function severityFromAction(action) {
  switch (action) {
    case "block_remove_and_report":
      return "critical";
    case "block_and_alert_room":
      return "high";
    case "block_and_report":
      return "high";
    case "block_and_flag":
      return "medium";
    case "censor_and_warn":
      return "medium";
    default:
      return "none";
  }
}

function splitSpotChatModerationSignals({
  categories,
  aiReasons,
} = {}) {
  const inputCategories = Array.isArray(categories) ? categories.filter(Boolean) : [];
  const inputAiReasons = Array.isArray(aiReasons) ? aiReasons.filter(Boolean) : [];

  const phishingOwnedCategories = inputCategories.filter((category) =>
    PHISHING_OWNED_CATEGORIES.has(category)
  );
  const harmfulLanguageCategories = inputCategories.filter(
    (category) => !PHISHING_OWNED_CATEGORIES.has(category)
  );

  const phishingOwnedAiReasons = inputAiReasons.filter((reason) =>
    PHISHING_OWNED_AI_REASONS.has(reason)
  );
  const harmfulLanguageAiReasons = inputAiReasons.filter(
    (reason) => !PHISHING_OWNED_AI_REASONS.has(reason)
  );

  return {
    phishingOwnedCategories,
    harmfulLanguageCategories,
    phishingOwnedAiReasons,
    harmfulLanguageAiReasons,
    hasOnlyPhishingOwnedSignals:
      harmfulLanguageCategories.length === 0 &&
      (phishingOwnedCategories.length > 0 || phishingOwnedAiReasons.length > 0) &&
      harmfulLanguageAiReasons.length === 0,
  };
}

function decideModerationAction({ categories, ruleSeverity, needsAiReview }) {
  if (!Array.isArray(categories) || categories.length === 0) {
    const action = "allow";
    return {
      action,
      severity: needsAiReview ? "medium" : "none",
      primary_category: null,
      save_message: true,
      enqueue_admin_review: needsAiReview,
      suspension_required: false,
      alert_room: false,
      remove_from_room: false,
      close_room_if_owner: false,
      visible_message_mode: "raw",
    };
  }

  let selectedAction = "allow";
  let primaryCategory = null;
  for (const category of categories) {
    const nextAction = CATEGORY_ACTION_MAP[category] ?? "allow";
    if (ACTION_PRIORITY[nextAction] > ACTION_PRIORITY[selectedAction]) {
      selectedAction = nextAction;
      primaryCategory = category;
    }
  }

  return {
    action: selectedAction,
    severity: ruleSeverity !== "none" ? ruleSeverity : severityFromAction(selectedAction),
    primary_category: primaryCategory,
    save_message: selectedAction === "allow" || selectedAction === "censor_and_warn",
    enqueue_admin_review: selectedAction !== "allow",
    suspension_required: selectedAction === "block_remove_and_report",
    alert_room: selectedAction === "block_and_alert_room",
    remove_from_room: selectedAction === "block_remove_and_report",
    close_room_if_owner: selectedAction === "block_remove_and_report",
    visible_message_mode: selectedAction === "censor_and_warn" ? "censored" : "raw",
  };
}

function decideSpotChatModerationAction({
  categories,
  aiReasons,
  ruleSeverity,
  needsAiReview,
}) {
  const signalSplit = splitSpotChatModerationSignals({ categories, aiReasons });

  // Spot chat uses language moderation for abuse/safety and delegates URL/scam
  // authority to the phishing scan pipeline. scam_risk-only signals should not
  // cause a moderation block/403 on their own.
  const languageDecision = decideModerationAction({
    categories: signalSplit.harmfulLanguageCategories,
    ruleSeverity:
      signalSplit.harmfulLanguageCategories.length > 0 ? ruleSeverity : "none",
    needsAiReview:
      Boolean(needsAiReview) && signalSplit.harmfulLanguageAiReasons.length > 0,
  });

  return {
    ...languageDecision,
    signal_split: signalSplit,
    phishing_delegated: signalSplit.hasOnlyPhishingOwnedSignals,
  };
}

module.exports = {
  CATEGORY_ACTION_MAP,
  PHISHING_OWNED_CATEGORIES,
  PHISHING_OWNED_AI_REASONS,
  decideModerationAction,
  decideSpotChatModerationAction,
  splitSpotChatModerationSignals,
};
