const { normalizeText } = require("./normalize.js");
const { detectRuleHits, getSeverityScore } = require("./rules.js");
const { moderateText } = require("./openaiModeration.js");

const SEVERE_OPENAI_BLOCK_CATEGORIES = new Set([
  "harassment/threatening",
  "hate/threatening",
  "sexual/minors",
  "self-harm/instructions",
  "self-harm/intent",
  "violence/graphic",
]);

const MODERATE_OPENAI_REVIEW_CATEGORIES = new Set([
  "hate",
  "harassment",
  "sexual",
  "violence",
  "illicit/violent",
  "self-harm",
]);

function unique(values) {
  return Array.from(new Set(values.filter(Boolean)));
}

function getFlaggedModerationCategories(moderation) {
  return Object.entries(moderation?.categories ?? {})
    .filter(([, value]) => value === true)
    .map(([key]) => key);
}

function topCategoryScore(categoryScores = {}) {
  return Object.values(categoryScores).reduce((max, value) => {
    return typeof value === "number" && value > max ? value : max;
  }, 0);
}

function summarizeRuleRisk(ruleHits) {
  const scamHits = ruleHits.filter((hit) => hit.category === "scam_risk");
  const highSeverityCount = ruleHits.filter(
    (hit) => getSeverityScore(hit.severity) >= getSeverityScore("high")
  ).length;

  return {
    totalHits: ruleHits.length,
    scamHits: scamHits.length,
    highSeverityCount,
    labels: unique(ruleHits.map((hit) => hit.label)),
  };
}

function buildReasons({ ruleHits, flaggedModerationCategories, moderation }) {
  const reasons = [];

  for (const hit of ruleHits) {
    reasons.push(`rule:${hit.label}`);
  }

  for (const category of flaggedModerationCategories) {
    reasons.push(`openai:${category}`);
  }

  if (moderation?.error?.code === "missing_api_key") {
    reasons.push("openai:missing_api_key");
  } else if (moderation?.error) {
    reasons.push("openai:unavailable");
  }

  return unique(reasons);
}

function decideAction({ ruleHits, moderation, flaggedModerationCategories }) {
  const ruleRisk = summarizeRuleRisk(ruleHits);
  const topScore = topCategoryScore(moderation?.category_scores);
  const hasSevereOpenAIBlock = flaggedModerationCategories.some((category) =>
    SEVERE_OPENAI_BLOCK_CATEGORIES.has(category)
  );
  if (hasSevereOpenAIBlock) {
    return "block";
  }

  const hasSevereRuleBlock = ruleHits.some(
    (hit) =>
      hit.category === "threat" ||
      hit.category === "hate_speech" ||
      hit.category === "sexual_harassment"
  );
  if (hasSevereRuleBlock) {
    return "block";
  }

  const hasStrongScamPattern =
    ruleRisk.scamHits >= 3 ||
    (ruleRisk.scamHits >= 2 && ruleRisk.highSeverityCount >= 1);
  if (hasStrongScamPattern) {
    return "block";
  }

  const hasReviewOpenAIFlag = flaggedModerationCategories.some((category) =>
    MODERATE_OPENAI_REVIEW_CATEGORIES.has(category)
  );
  if (hasReviewOpenAIFlag) {
    return "review";
  }

  if (moderation?.flagged === true && topScore >= 0.35) {
    return "review";
  }

  if (ruleHits.length > 0) {
    return "warn";
  }

  if (moderation?.flagged === true || topScore >= 0.2) {
    return "review";
  }

  return "allow";
}

function buildRiskSummary({
  ruleHits,
  moderation,
  flaggedModerationCategories,
  action,
}) {
  const ruleRisk = summarizeRuleRisk(ruleHits);
  return {
    action,
    ruleLabels: ruleRisk.labels,
    ruleHitCount: ruleRisk.totalHits,
    scamSignalCount: ruleRisk.scamHits,
    openaiFlagged: moderation?.flagged === true,
    openaiFlaggedCategories: flaggedModerationCategories,
    topOpenAIScore: topCategoryScore(moderation?.category_scores),
  };
}

function buildUserMessage(action, riskSummary) {
  if (action === "block") {
    return "This message was blocked by moderation policy.";
  }
  if (action === "warn") {
    if (riskSummary.scamSignalCount > 0) {
      return "This message looks suspicious. Please confirm before sending.";
    }
    return "This message may violate chat guidelines. Please confirm before sending.";
  }
  if (action === "review") {
    return "This message may need moderation review. You can still continue with caution.";
  }
  return null;
}

async function classifyMessage(rawMessage) {
  const normalization = normalizeText(rawMessage);
  const ruleHits = detectRuleHits(normalization.normalizedText);
  const moderation = await moderateText(normalization.normalizedText);
  const flaggedModerationCategories = getFlaggedModerationCategories(moderation);
  const action = decideAction({
    ruleHits,
    moderation,
    flaggedModerationCategories,
  });
  const reasons = buildReasons({
    ruleHits,
    flaggedModerationCategories,
    moderation,
  });
  const riskSummary = buildRiskSummary({
    ruleHits,
    moderation,
    flaggedModerationCategories,
    action,
  });

  return {
    rawMessage: String(rawMessage ?? ""),
    normalizedMessage: normalization.normalizedText,
    normalizationDebug: normalization.debug,
    ruleHits,
    moderation,
    action,
    reasons,
    riskSummary,
    userMessage: buildUserMessage(action, riskSummary),
  };
}

module.exports = {
  classifyMessage,
};
