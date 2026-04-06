const { pool } = require("../db.js");

const CACHE_TTL_MS = 60 * 1000;

const SEED_VOCABULARY = [
  { term: "fuck", language: "en", category: "profanity", severity: "medium" },
  { term: "shit", language: "en", category: "profanity", severity: "medium" },
  { term: "bastard", language: "en", category: "profanity", severity: "medium" },
  { term: "motherfucker", language: "en", category: "profanity", severity: "high" },
  { term: "dickhead", language: "en", category: "targeted_abuse", severity: "high" },
  { term: "piece of shit", language: "en", category: "targeted_abuse", severity: "high" },
  { term: "idiot", language: "en", category: "targeted_abuse", severity: "medium" },
  { term: "moron", language: "en", category: "targeted_abuse", severity: "medium" },
  { term: "go die", language: "en", category: "threat", severity: "critical" },
  { term: "i will hurt you", language: "en", category: "threat", severity: "critical" },
  { term: "sexy", language: "en", category: "sexual_ambiguous", severity: "medium" },
  { term: "hot body", language: "en", category: "sexual_ambiguous", severity: "medium" },
  { term: "pervert", language: "en", category: "sexual_harassment", severity: "high" },
  { term: "ควย", language: "th", category: "profanity", severity: "medium" },
  { term: "เหี้ย", language: "th", category: "profanity", severity: "medium" },
  { term: "สัส", language: "th", category: "profanity", severity: "medium" },
  { term: "ไอ้สัส", language: "th", category: "targeted_abuse", severity: "high" },
  { term: "อีเหี้ย", language: "th", category: "targeted_abuse", severity: "high" },
  { term: "ดอกทอง", language: "th", category: "targeted_abuse", severity: "high" },
  { term: "มึง", language: "th", category: "targeted_abuse", severity: "medium" },
  { term: "เย็ดแม่", language: "th", category: "targeted_abuse", severity: "high" },
  { term: "操", language: "zh", category: "profanity", severity: "medium" },
  { term: "傻逼", language: "zh", category: "targeted_abuse", severity: "high" },
  { term: "滚开", language: "zh", category: "targeted_abuse", severity: "high" },
  { term: "去死", language: "zh", category: "targeted_abuse", severity: "high" },
  { term: "à¹„à¸›à¸•à¸²à¸¢", language: "th", category: "threat", severity: "critical" },
  { term: "à¸«à¸¸à¹ˆà¸™à¸”à¸µ", language: "th", category: "sexual_ambiguous", severity: "medium" },
  { term: "åŽ»æ­»", language: "zh", category: "threat", severity: "critical" },
  { term: "ä½ å¥½éªš", language: "zh", category: "sexual_ambiguous", severity: "medium" },
];

let vocabularyCache = {
  loadedAt: 0,
  entries: [],
};

function normalizeVocabularyTerm(term) {
  return String(term ?? "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\u200B-\u200D\uFEFF]/gu, "")
    .trim()
    .replace(/\s+/gu, " ");
}

function detectVocabularyLanguage(term) {
  const text = normalizeVocabularyTerm(term);
  if (!text) return "mixed";
  if (/[\u0E00-\u0E7F]/u.test(text)) return "th";
  if (/[\u4E00-\u9FFF]/u.test(text)) return "zh";
  if (/[a-z]/iu.test(text)) return "en";
  return "mixed";
}

function escapeRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function buildVocabularyPattern(term) {
  const normalized = normalizeVocabularyTerm(term);
  const latinLike = /^[a-z0-9\s'-]+$/iu.test(normalized);
  if (latinLike) {
    return new RegExp(`\\b${escapeRegex(normalized)}\\b`, "giu");
  }
  return new RegExp(escapeRegex(normalized), "gu");
}

async function ensureModerationVocabularySeed() {
  for (const entry of SEED_VOCABULARY) {
    const normalizedTerm = normalizeVocabularyTerm(entry.term);
    if (!normalizedTerm) continue;
    await pool.query(
      `
      INSERT INTO public.moderation_vocabulary
        (term, normalized_term, language, category, severity, is_active, source, created_at, updated_at)
      VALUES
        ($1, $2, $3, $4, $5, TRUE, 'seed', NOW(), NOW())
      ON CONFLICT (normalized_term, category, language)
      DO NOTHING
      `,
      [
        entry.term,
        normalizedTerm,
        entry.language,
        entry.category,
        entry.severity,
      ]
    );
  }
  vocabularyCache.loadedAt = 0;
}

async function loadActiveModerationVocabulary({ forceRefresh = false } = {}) {
  const now = Date.now();
  if (!forceRefresh && vocabularyCache.entries.length > 0 && now - vocabularyCache.loadedAt < CACHE_TTL_MS) {
    return vocabularyCache.entries;
  }

  const q = await pool.query(
    `
    SELECT id, term, normalized_term, language, category, severity, source
    FROM public.moderation_vocabulary
    WHERE is_active = TRUE
    ORDER BY updated_at DESC, id DESC
    `
  );

  vocabularyCache = {
    loadedAt: now,
    entries: q.rows.map((row) => ({
      id: row.id,
      term: row.term,
      normalized_term: row.normalized_term,
      language: row.language,
      category: row.category,
      severity: row.severity,
      source: row.source,
      pattern: buildVocabularyPattern(row.normalized_term),
    })),
  };

  return vocabularyCache.entries;
}

function analyzeVocabularyModeration(normalizedText, entries, getSeverityScore) {
  const hits = [];
  for (const entry of entries) {
    entry.pattern.lastIndex = 0;
    const matches = [...normalizedText.matchAll(entry.pattern)];
    for (const match of matches) {
      hits.push({
        rule_id: `vocabulary_${entry.id}`,
        category: entry.category,
        severity: entry.severity,
        severity_score: getSeverityScore(entry.severity),
        match_type: "vocabulary",
        matched_value: match[0],
        vocabulary_id: entry.id,
        vocabulary_source: entry.source,
      });
    }
  }

  return hits;
}

module.exports = {
  SEED_VOCABULARY,
  analyzeVocabularyModeration,
  detectVocabularyLanguage,
  ensureModerationVocabularySeed,
  loadActiveModerationVocabulary,
  normalizeVocabularyTerm,
};
