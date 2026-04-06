const CATEGORY_ACTION_ORDER = {
  allow: 0,
  review: 1,
  warn: 2,
  block: 3,
};

const SEVERITY_ORDER = {
  low: 0,
  medium: 1,
  high: 2,
  critical: 3,
};

function maxSeverity(first, second) {
  return SEVERITY_ORDER[second] > SEVERITY_ORDER[first] ? second : first;
}

function buildDecision({ matchedRules, context }) {
  if (!matchedRules.length) {
    return {
      categories: ["allow"],
      severity: "low",
      confidence: 0.05,
      action: "allow",
      needs_human_review: false,
      rationale: ["No harmful rule matched after normalization and context checks."],
    };
  }

  let severity = "low";
  let action = "allow";
  const categories = new Set();
  const rationale = [];

  for (const rule of matchedRules) {
    categories.add(rule.category);
    severity = maxSeverity(severity, rule.severity);
    rationale.push(rule.rationale);

    if (rule.category === "threat") {
      action = "block";
    } else if (
      ["hate_speech", "protected_class_attack", "dehumanization"].includes(rule.category)
    ) {
      if (CATEGORY_ACTION_ORDER[action] < CATEGORY_ACTION_ORDER.block) {
        action = "block";
      }
    } else if (
      ["targeted_abuse", "harassment"].includes(rule.category) &&
      CATEGORY_ACTION_ORDER[action] < CATEGORY_ACTION_ORDER.review
    ) {
      action = "review";
    }
  }

  if (
    context.is_reporting ||
    context.is_educational ||
    context.contains_quote ||
    context.is_reclaimed
  ) {
    if (action === "block") {
      action = "review";
    }
    if (SEVERITY_ORDER[severity] > SEVERITY_ORDER.medium) {
      severity = "medium";
    }
    rationale.push("Context markers indicate discussion, evidence, or self-referential usage.");
  }

  const confidence =
    action === "block" ? 0.92 : action === "review" ? 0.72 : 0.55;

  return {
    categories: Array.from(categories),
    severity,
    confidence,
    action,
    needs_human_review: action === "review",
    rationale: Array.from(new Set(rationale)),
  };
}

module.exports = {
  buildDecision,
};
