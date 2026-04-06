const { normalizeText } = require("./normalizer.js");
const { analyzeRules } = require("./rules.js");
const { buildDecision } = require("./decision.js");

function inferTargetType(matchedRules) {
  if (matchedRules.some((rule) => rule.protected_class)) {
    return "protected_class";
  }
  if (matchedRules.some((rule) => rule.category === "threat")) {
    return "individual_or_group";
  }
  if (matchedRules.length > 0) {
    return "individual";
  }
  return "none";
}

function inferProtectedClass(matchedRules) {
  const values = matchedRules
    .map((rule) => rule.protected_class)
    .filter(Boolean);
  return values.length > 0 ? Array.from(new Set(values)) : [];
}

function analyzeMessage(message, metadata = {}) {
  const normalized = normalizeText(message);
  const ruleAnalysis = analyzeRules(normalized);
  const decision = buildDecision({
    matchedRules: ruleAnalysis.matched_rules,
    context: ruleAnalysis.context,
  });

  return {
    normalized_text: normalized.normalized_text,
    categories: decision.categories,
    severity: decision.severity,
    confidence: decision.confidence,
    target_type: inferTargetType(ruleAnalysis.matched_rules),
    protected_class: inferProtectedClass(ruleAnalysis.matched_rules),
    action: decision.action,
    rationale: decision.rationale,
    matched_rules: ruleAnalysis.matched_rules.map((rule) => ({
      id: rule.id,
      category: rule.category,
      severity: rule.severity,
      protected_class: rule.protected_class,
      matched_text: rule.matched_text,
      rationale: rule.rationale,
    })),
    needs_human_review: decision.needs_human_review,
    metadata: {
      ...metadata,
      context: ruleAnalysis.context,
      protected_references: ruleAnalysis.protected_references,
    },
  };
}

module.exports = {
  analyzeMessage,
};
