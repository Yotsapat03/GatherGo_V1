const { loadActiveModerationVocabulary, normalizeVocabularyTerm } = require("./vocabulary.js");

const BUILTIN_KNOWLEDGE_ENTRIES = [
  {
    id: "threat_self_harm_kys",
    source: "builtin",
    title: "Self-harm encouragement slang",
    category: "threat",
    severity: "critical",
    action_hint: "block",
    rationale: "Common shorthand encouraging self-harm should be blocked immediately.",
    aliases: ["kys", "kill yourself"],
  },
  {
    id: "sexual_harassment_nudes_variants",
    source: "builtin",
    title: "Sexual solicitation variants",
    category: "sexual_harassment",
    severity: "critical",
    action_hint: "block",
    rationale: "Requests for explicit images or sexual acts are disallowed.",
    aliases: ["send noods", "send nudes", "n00ds", "boob pic"],
  },
  {
    id: "sexual_ambiguous_th_horny",
    source: "builtin",
    title: "Thai sexual slang",
    category: "sexual_ambiguous",
    severity: "medium",
    action_hint: "review",
    rationale: "Sexual slang often needs context review before allowing chat delivery.",
    aliases: ["เงี่ยน", "หื่น"],
  },
  {
    id: "hate_speech_homophobic_variants",
    source: "builtin",
    title: "Homophobic slur variants",
    category: "hate_speech",
    severity: "high",
    action_hint: "block",
    rationale: "Protected-class slurs should be treated as hate speech even when obfuscated.",
    aliases: ["fag", "fa99ot", "faggot"],
  },
  {
    id: "hate_speech_transphobic_country_stereotype",
    source: "builtin",
    title: "Transphobic country stereotype",
    category: "hate_speech",
    severity: "high",
    action_hint: "block",
    rationale: "Gender-identity slurs combined with country stereotyping should be blocked.",
    aliases: ["ladyboy country", "country of ladyboys"],
  },
  {
    id: "scam_off_platform_contact_variants",
    source: "builtin",
    title: "Off-platform payment/contact bait",
    category: "scam_risk",
    severity: "high",
    action_hint: "review",
    rationale: "Moving payment or contact off-platform is a strong fraud signal.",
    aliases: ["ทักไลน์", "แอดไลน์", "line id", "telegram me", "dm telegram", "wa.me"],
  },
];

const SEVERITY_RANK = {
  none: 0,
  low: 1,
  medium: 2,
  high: 3,
  critical: 4,
};

function buildPattern(term) {
  const normalized = normalizeVocabularyTerm(term);
  const latinLike = /^[a-z0-9\s'-]+$/iu.test(normalized);
  const escaped = normalized.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  if (latinLike) {
    return new RegExp(`\\b${escaped}\\b`, "giu");
  }
  return new RegExp(escaped, "gu");
}

function buildCompactValue(value) {
  return normalizeVocabularyTerm(value).replace(/[\s\W_]+/gu, "");
}

function compileEntry(entry) {
  const aliases = Array.from(
    new Set(
      [entry.term, ...(entry.aliases ?? [])]
        .map((value) => normalizeVocabularyTerm(value))
        .filter(Boolean)
    )
  );

  return {
    ...entry,
    aliases,
    patterns: aliases.map((alias) => ({
      alias,
      compact: buildCompactValue(alias),
      pattern: buildPattern(alias),
    })),
  };
}

function getHigherSeverity(first, second) {
  return (SEVERITY_RANK[second] ?? 0) > (SEVERITY_RANK[first] ?? 0) ? second : first;
}

function scoreMatch({ alias, compactAlias, normalizedText, compactText, matchCount }) {
  if (!alias) return 0;
  if (matchCount > 0) {
    return alias.includes(" ") ? 0.99 : 0.96;
  }
  if (compactAlias && compactAlias.length >= 3 && compactText.includes(compactAlias)) {
    if (compactAlias === compactText) return 0.9;
    if (normalizedText.includes(alias)) return 0.88;
    return 0.8;
  }
  return 0;
}

function createKnowledgeHits(match) {
  return (match.matched_aliases ?? []).map((alias) => ({
    rule_id: `knowledge_${match.id}`,
    category: match.category,
    severity: match.severity,
    severity_score: SEVERITY_RANK[match.severity] ?? 0,
    match_type: "knowledge",
    matched_value: alias,
    knowledge_id: match.id,
    knowledge_source: match.source,
    rationale: match.rationale,
    score: match.score,
  }));
}

function retrieveFromEntries(entries, normalizedText) {
  const compactText = buildCompactValue(normalizedText);
  const matches = [];

  for (const entry of entries) {
    const matchedAliases = [];
    let bestScore = 0;

    for (const candidate of entry.patterns) {
      candidate.pattern.lastIndex = 0;
      const patternMatches = [...normalizedText.matchAll(candidate.pattern)];
      const score = scoreMatch({
        alias: candidate.alias,
        compactAlias: candidate.compact,
        normalizedText,
        compactText,
        matchCount: patternMatches.length,
      });

      if (score <= 0) continue;
      matchedAliases.push(candidate.alias);
      bestScore = Math.max(bestScore, score);
    }

    if (matchedAliases.length === 0) continue;

    matches.push({
      id: entry.id,
      source: entry.source,
      title: entry.title ?? entry.term ?? entry.id,
      category: entry.category,
      severity: entry.severity ?? "medium",
      action_hint: entry.action_hint ?? null,
      rationale: entry.rationale ?? null,
      matched_aliases: Array.from(new Set(matchedAliases)),
      score: Number(bestScore.toFixed(2)),
    });
  }

  matches.sort((left, right) => {
    if (right.score !== left.score) return right.score - left.score;
    return (SEVERITY_RANK[right.severity] ?? 0) - (SEVERITY_RANK[left.severity] ?? 0);
  });

  return matches;
}

function buildVocabularyKnowledgeEntries(vocabularyEntries) {
  return vocabularyEntries.map((entry) =>
    compileEntry({
      id: `vocabulary_${entry.id}`,
      source: "vocabulary",
      title: entry.term,
      term: entry.term,
      category: entry.category,
      severity: entry.severity,
      action_hint:
        entry.severity === "critical" || entry.severity === "high" ? "block" : "review",
      rationale: `Matched internal moderation vocabulary for ${entry.category}.`,
      aliases: [entry.normalized_term],
    })
  );
}

async function retrieveModerationKnowledge(normalizedText) {
  const builtinEntries = BUILTIN_KNOWLEDGE_ENTRIES.map(compileEntry);
  const vocabularyEntries = await loadActiveModerationVocabulary().catch(() => []);
  const knowledgeEntries = [
    ...builtinEntries,
    ...buildVocabularyKnowledgeEntries(vocabularyEntries),
  ];
  const matches = retrieveFromEntries(knowledgeEntries, normalizedText).slice(0, 8);

  const categories = Array.from(new Set(matches.map((match) => match.category)));
  const actionHints = Array.from(
    new Set(matches.map((match) => match.action_hint).filter(Boolean))
  );
  let severity = "none";
  for (const match of matches) {
    severity = getHigherSeverity(severity, match.severity);
  }

  return {
    matches,
    hits: matches.flatMap(createKnowledgeHits),
    categories,
    severity,
    action_hints: actionHints,
  };
}

module.exports = {
  BUILTIN_KNOWLEDGE_ENTRIES,
  retrieveModerationKnowledge,
};
