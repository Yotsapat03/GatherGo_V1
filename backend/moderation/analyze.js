const { normalizeModerationText } = require("./normalizer.js");
const { analyzeRuleBasedModeration, getSeverityScore } = require("./rules.js");
const { decideSpotChatModerationAction } = require("./decision.js");
const { classifyWithGemini } = require("./gemini.js");
const { moderateText } = require("./openaiModeration.js");
const { classifyWithOpenAIReasoning } = require("./openaiReasonedModeration.js");
const { analyzeMessage: analyzeSafetyMessage } = require("./safety/analyzer.js");
const {
  analyzeVocabularyModeration,
  loadActiveModerationVocabulary,
} = require("./vocabulary.js");
const { retrieveModerationKnowledge } = require("./knowledge.js");

const HIGH_CONFIDENCE_THRESHOLD = 0.8;
const MEDIUM_CONFIDENCE_THRESHOLD = 0.65;
const STRONG_RULE_BLOCK_CATEGORIES = new Set([
  "targeted_abuse",
  "hate_speech",
  "threat",
  "sexual_harassment",
  "scam_risk",
]);
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
  "hate/threatening",
  "harassment",
  "harassment/threatening",
  "sexual",
  "sexual/minors",
  "violence",
  "violence/graphic",
  "illicit/violent",
  "self-harm",
  "self-harm/intent",
  "self-harm/instructions",
]);
const SEVERITY_ORDER = ["none", "low", "medium", "high", "critical"];
const GEMINI_MODERATE_ALL_MESSAGES = true;
const OPENAI_REASONED_MODERATE_ALL_MESSAGES = true;
const OPENAI_MODERATE_ALL_MESSAGES = true;

function getHigherSeverity(first, second) {
  const firstIndex = SEVERITY_ORDER.indexOf(first);
  const secondIndex = SEVERITY_ORDER.indexOf(second);
  return secondIndex > firstIndex ? second : first;
}

function mergeRuleAnalyses(baseAnalysis, vocabularyHits) {
  const hits = [...(baseAnalysis.hits ?? []), ...vocabularyHits];
  const categories = new Set(baseAnalysis.categories ?? []);
  const categoryScores = { ...(baseAnalysis.category_scores ?? {}) };
  let severity = baseAnalysis.severity ?? "none";

  for (const hit of vocabularyHits) {
    categories.add(hit.category);
    categoryScores[hit.category] = Math.max(
      categoryScores[hit.category] ?? 0,
      hit.severity_score ?? getSeverityScore(hit.severity)
    );
    severity = getHigherSeverity(severity, hit.severity ?? "low");
  }

  return {
    ...baseAnalysis,
    hits,
    categories: Array.from(categories),
    category_scores: categoryScores,
    severity,
    vocabulary_hits: vocabularyHits,
  };
}

function mergeKnowledgeSignals(baseAnalysis, knowledge) {
  const hits = [...(baseAnalysis.hits ?? []), ...(knowledge?.hits ?? [])];
  const categories = new Set([
    ...(baseAnalysis.categories ?? []),
    ...(knowledge?.categories ?? []),
  ]);
  const categoryScores = { ...(baseAnalysis.category_scores ?? {}) };
  let severity = baseAnalysis.severity ?? "none";

  for (const hit of knowledge?.hits ?? []) {
    categoryScores[hit.category] = Math.max(
      categoryScores[hit.category] ?? 0,
      hit.severity_score ?? getSeverityScore(hit.severity)
    );
    severity = getHigherSeverity(severity, hit.severity ?? "low");
  }

  return {
    ...baseAnalysis,
    hits,
    categories: Array.from(categories),
    category_scores: categoryScores,
    severity,
    knowledge_hits: knowledge?.hits ?? [],
    knowledge_matches: knowledge?.matches ?? [],
  };
}

function collectSemanticAiReasons(rawMessage, normalizedMessage, ruleAnalysis, knowledge) {
  const reasons = new Set(ruleAnalysis.ai_reasons ?? []);
  const hasStrongRuleBlock = (ruleAnalysis.categories ?? []).some((category) =>
    STRONG_RULE_BLOCK_CATEGORIES.has(category)
  );
  if (hasStrongRuleBlock) {
    return [];
  }

  const looksObfuscated =
    /[a-z][0-9@_$*.-]+[a-z]/iu.test(rawMessage) ||
    /\b(?:[a-z][\W_]+){2,}[a-z]\b/iu.test(rawMessage);
  if (rawMessage !== normalizedMessage && looksObfuscated) {
    reasons.add("possible_obfuscation");
  }

  if (/(line|telegram|wechat|weixin|promptpay|transfer|deposit|crypto|bank transfer|dm me|call me)/iu.test(normalizedMessage)) {
    reasons.add("weak_scam_signal");
  }

  if (/(private tonight|sleep with me|show yourself|é™ªæˆ‘|å¼€ä¸ªæˆ¿|à¸„à¸·à¸™à¸™à¸µà¹‰à¹€à¸ˆà¸­à¸à¸±à¸™à¸ªà¸­à¸‡à¸„à¸™|à¸‚à¸­à¸­à¸¢à¸¹à¹ˆà¸”à¹‰à¸§à¸¢à¸ªà¸­à¸‡à¸„à¸™)/iu.test(normalizedMessage)) {
    reasons.add("contextual_sexual_coercion");
  }

  if (/(sexy|hot body|turn me on|private tonight|à¸«à¸¸à¹ˆà¸™à¸”à¸µ|à¹€à¸‹à¹‡à¸à¸‹à¸µà¹ˆ|ä½ å¥½éªš|å¥½æ€§æ„Ÿ)/iu.test(normalizedMessage)) {
    reasons.add("contextual_sexual_ambiguity");
  }

  if (/(your kind|people like you|stupid gay|dirty chinese|your country.{0,24}eat\s+(cat|cats|dog|dogs|meow|meaw)|ladyboy country|country of ladyboys|à¸žà¸§à¸.*(à¸ˆà¸µà¸™|à¹€à¸à¸¢à¹Œ|à¸”à¸³))/iu.test(normalizedMessage)) {
    reasons.add("contextual_hate_signal");
  }

  if (/(go die|i will hurt you|watch your back|à¹„à¸›à¸•à¸²à¸¢|à¸ˆà¸°à¸†à¹ˆà¸²|åŽ»æ­»|æˆ‘è¦æ‰“ä½ |æˆ‘è¦æ€äº†ä½ )/iu.test(normalizedMessage)) {
    reasons.add("contextual_threat_signal");
  }

  if (
    ((ruleAnalysis.categories ?? []).includes("profanity") ||
      (ruleAnalysis.categories ?? []).includes("targeted_abuse")) &&
    /\b(you|your|u)\b|à¸¡à¸¶à¸‡|à¹à¸|à¸„à¸¸à¸“|ä½ |ä½ ä»¬/u.test(normalizedMessage)
  ) {
    reasons.add("contextual_direct_abuse");
  }

  if ((ruleAnalysis.vocabulary_hits ?? []).length > 0) {
    reasons.add("vocabulary_signal");
  }

  if ((knowledge?.matches ?? []).length > 0) {
    reasons.add("knowledge_signal");
  }

  return Array.from(reasons);
}

function shouldInvokeGemini(ruleAnalysis, aiReasons) {
  if (GEMINI_MODERATE_ALL_MESSAGES) {
    return true;
  }

  const hasStrongRuleBlock = (ruleAnalysis.categories ?? []).some((category) =>
    STRONG_RULE_BLOCK_CATEGORIES.has(category)
  );
  if (hasStrongRuleBlock) {
    return false;
  }

  if (ruleAnalysis.needs_ai_review) {
    return true;
  }

  if ((ruleAnalysis.categories ?? []).includes("profanity") && aiReasons.length > 0) {
    return true;
  }

  if ((ruleAnalysis.categories ?? []).includes("sexual_ambiguous")) {
    return true;
  }

  return false;
}

function shouldInvokeOpenAI(ruleAnalysis, aiReasons) {
  if (OPENAI_MODERATE_ALL_MESSAGES) {
    return true;
  }

  const hasStrongRuleBlock = (ruleAnalysis.categories ?? []).some((category) =>
    STRONG_RULE_BLOCK_CATEGORIES.has(category)
  );
  if (hasStrongRuleBlock) {
    return false;
  }

  if (ruleAnalysis.needs_ai_review) {
    return true;
  }

  return aiReasons.length > 0;
}

function mapOpenAIModerationCategory(category) {
  switch (category) {
    case "harassment":
      return "targeted_abuse";
    case "harassment/threatening":
      return "threat";
    case "hate":
    case "hate/threatening":
      return "hate_speech";
    case "sexual":
      return "sexual_ambiguous";
    case "sexual/minors":
      return "sexual_harassment";
    case "violence":
    case "violence/graphic":
      return "threat";
    default:
      return null;
  }
}

function severityFromOpenAICategory(category) {
  if (category === "sexual/minors" || category === "violence/graphic") {
    return "critical";
  }
  if (category === "harassment/threatening" || category === "hate/threatening") {
    return "critical";
  }
  if (category === "hate" || category === "violence") {
    return "high";
  }
  if (category === "harassment" || category === "sexual") {
    return "medium";
  }
  return "low";
}

function extractOpenAIFlaggedCategories(openaiResult) {
  return Object.entries(openaiResult?.categories ?? {})
    .filter(([, flagged]) => flagged === true)
    .map(([category]) => category);
}

function buildOpenAIResultPlaceholder() {
  return {
    attempted: false,
    provider: "openai",
    model: "omni-moderation-latest",
    flagged: false,
    categories: {},
    category_scores: {},
    category_applied_input_types: null,
    error: null,
    used: false,
    skipped_reason: "not_needed",
  };
}

function applyStructuredAiResult(mergedCategories, mergedSeverity, ruleAnalysis, aiResult) {
  let strengthened = false;

  if (aiResult?.used && aiResult.result?.is_flagged) {
    const confidence = aiResult.result.confidence ?? 0;
    const canAddNewCategories =
      confidence >= HIGH_CONFIDENCE_THRESHOLD ||
      ((ruleAnalysis.categories ?? []).length > 0 && confidence >= MEDIUM_CONFIDENCE_THRESHOLD);

    if (canAddNewCategories) {
      for (const category of aiResult.result.categories ?? []) {
        mergedCategories.add(category);
      }
      mergedSeverity = getHigherSeverity(mergedSeverity, aiResult.result.severity);
      strengthened = true;
    }
  }

  return { mergedSeverity, strengthened };
}

function mergeRuleAndAiResults(ruleAnalysis, geminiResult, openaiReasonedResult, openaiResult, safetyResult) {
  const mergedCategories = new Set(ruleAnalysis.categories ?? []);
  let mergedSeverity = ruleAnalysis.severity ?? "none";
  let aiStrengthened = false;
  let openaiReasonedStrengthened = false;
  let openaiStrengthened = false;
  let safetyStrengthened = false;

  const geminiApplied = applyStructuredAiResult(
    mergedCategories,
    mergedSeverity,
    ruleAnalysis,
    geminiResult
  );
  mergedSeverity = geminiApplied.mergedSeverity;
  aiStrengthened = geminiApplied.strengthened;

  const openaiReasonedApplied = applyStructuredAiResult(
    mergedCategories,
    mergedSeverity,
    ruleAnalysis,
    openaiReasonedResult
  );
  mergedSeverity = openaiReasonedApplied.mergedSeverity;
  openaiReasonedStrengthened = openaiReasonedApplied.strengthened;

  const openaiFlaggedCategories = extractOpenAIFlaggedCategories(openaiResult);
  if (openaiResult?.attempted && openaiResult?.flagged === true) {
    const openaiTriggeredStrongBlock = openaiFlaggedCategories.some((category) =>
      SEVERE_OPENAI_BLOCK_CATEGORIES.has(category)
    );
    const canAddNewCategories =
      openaiTriggeredStrongBlock ||
      openaiFlaggedCategories.some((category) =>
        MODERATE_OPENAI_REVIEW_CATEGORIES.has(category)
      );

    if (canAddNewCategories) {
      for (const category of openaiFlaggedCategories) {
        const mappedCategory = mapOpenAIModerationCategory(category);
        if (!mappedCategory) continue;
        mergedCategories.add(mappedCategory);
        mergedSeverity = getHigherSeverity(
          mergedSeverity,
          severityFromOpenAICategory(category)
        );
        openaiStrengthened = true;
      }
    }
  }

  if ((ruleAnalysis.categories ?? []).length === 0 && geminiResult?.used && !geminiResult.result?.is_flagged) {
    const openaiIsClean = !openaiResult?.attempted || openaiResult?.flagged !== true;
    if (openaiIsClean) {
      mergedSeverity = "none";
    }
  }

  if (safetyResult?.action === "block") {
    for (const category of safetyResult.categories ?? []) {
      if (category === "allow" || category === "review" || category === "block") {
        continue;
      }
      mergedCategories.add(category);
      safetyStrengthened = true;
    }
    mergedSeverity = getHigherSeverity(
      mergedSeverity,
      safetyResult.severity ?? "medium"
    );
  }

  return {
    categories: Array.from(mergedCategories),
    severity: mergedSeverity,
    ai_strengthened: aiStrengthened,
    openai_reasoned_strengthened: openaiReasonedStrengthened,
    openai_strengthened: openaiStrengthened,
    safety_strengthened: safetyStrengthened,
    openai_flagged_categories: openaiFlaggedCategories,
  };
}

async function analyzeSpotChatMessage(rawMessage) {
  const normalization = normalizeModerationText(rawMessage);
  const baseRuleAnalysis = analyzeRuleBasedModeration(normalization.normalized);
  const vocabularyEntries = await loadActiveModerationVocabulary().catch(() => []);
  const vocabularyHits = analyzeVocabularyModeration(
    normalization.normalized,
    vocabularyEntries,
    getSeverityScore
  );
  const vocabularyAnalysis = mergeRuleAnalyses(baseRuleAnalysis, vocabularyHits);
  const knowledge = await retrieveModerationKnowledge(normalization.normalized).catch(() => ({
    matches: [],
    hits: [],
    categories: [],
    severity: "none",
    action_hints: [],
  }));
  const ruleAnalysis = mergeKnowledgeSignals(vocabularyAnalysis, knowledge);
  const aiReasons = collectSemanticAiReasons(
    normalization.raw,
    normalization.normalized,
    ruleAnalysis,
    knowledge
  );
  const safety = analyzeSafetyMessage(normalization.raw, {
    source: "spot_chat",
  });
  const shouldClassifyWithGemini = shouldInvokeGemini(ruleAnalysis, aiReasons);
  const shouldClassifyWithOpenAIReasoning =
    OPENAI_REASONED_MODERATE_ALL_MESSAGES ||
    shouldClassifyWithGemini ||
    (knowledge?.matches ?? []).length > 0 ||
    safety?.action === "review";
  const shouldClassifyWithOpenAI = shouldInvokeOpenAI(ruleAnalysis, aiReasons);
  const [ai, openaiReasoned, openai] = await Promise.all([
    shouldClassifyWithGemini
      ? classifyWithGemini({
          rawMessage: normalization.raw,
          normalizedMessage: normalization.normalized,
          ruleAnalysis,
          aiReasons,
        })
      : Promise.resolve({
          attempted: false,
          used: false,
          provider: "gemini",
          model: process.env.GEMINI_MODEL?.trim() || "gemini-2.5-flash-lite",
          skipped_reason: "not_needed",
          result: null,
          error: null,
        }),
    shouldClassifyWithOpenAIReasoning
      ? classifyWithOpenAIReasoning({
          rawMessage: normalization.raw,
          normalizedMessage: normalization.normalized,
          ruleAnalysis,
          knowledge,
          safety,
          aiReasons,
        })
      : Promise.resolve({
          attempted: false,
          used: false,
          provider: "openai_responses",
          model: process.env.OPENAI_LLM_MODERATION_MODEL?.trim() || "gpt-5-mini",
          skipped_reason: "not_needed",
          result: null,
          error: null,
        }),
    shouldClassifyWithOpenAI
      ? moderateText(normalization.normalized).then((result) => ({
          ...result,
          used: result.attempted === true && result.error == null,
          skipped_reason:
            result.attempted === true
              ? null
              : result.error?.code || "not_attempted",
        }))
      : Promise.resolve(buildOpenAIResultPlaceholder()),
  ]);

  const merged = mergeRuleAndAiResults(ruleAnalysis, ai, openaiReasoned, openai, safety);
  const hasRuleSignals =
    Array.isArray(ruleAnalysis.categories) && ruleAnalysis.categories.length > 0;
  const hasSafetySignals =
    safety?.action === "review" || safety?.action === "block";
  const unresolvedAiReview =
    (shouldClassifyWithGemini && !ai.used) ||
    (shouldClassifyWithOpenAIReasoning &&
      !openaiReasoned.used &&
      (hasRuleSignals || hasSafetySignals || aiReasons.length > 0)) ||
    (shouldClassifyWithOpenAI &&
      (openai.attempted !== true || openai.error != null) &&
      (hasRuleSignals || hasSafetySignals || aiReasons.length > 0)) ||
    safety?.needs_human_review === true;
  const decision = decideSpotChatModerationAction({
    categories: merged.categories,
    aiReasons,
    ruleSeverity: merged.severity,
    needsAiReview: unresolvedAiReview,
  });

  return {
    raw_message: normalization.raw,
    normalized_message: normalization.normalized,
    categories: merged.categories,
    rule_hits: ruleAnalysis.hits,
    vocabulary_hits: vocabularyHits,
    knowledge,
    rule_severity: ruleAnalysis.severity,
    final_severity: merged.severity,
    ai_reasons: aiReasons,
    ai,
    openai_reasoned: openaiReasoned,
    openai,
    safety,
    ai_used: Boolean(ai.used) || Boolean(openai.used) || Boolean(openaiReasoned.used),
    ai_confidence:
      ai.result?.confidence ??
      openaiReasoned.result?.confidence ??
      null,
    ai_suggested_terms: ai.result?.suggested_terms ?? [],
    merged,
    decision,
    signal_split: decision.signal_split,
    phishing_delegated: decision.phishing_delegated === true,
    needs_human_review: unresolvedAiReview,
  };
}

module.exports = {
  analyzeSpotChatMessage,
};
