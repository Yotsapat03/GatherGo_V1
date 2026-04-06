const fs = require("fs");
const path = require("path");

const { RULES } = require("./rules.js");
const { SEED_VOCABULARY, detectVocabularyLanguage, normalizeVocabularyTerm } = require("./vocabulary.js");
const { BUILTIN_KNOWLEDGE_ENTRIES } = require("./knowledge.js");

function csvEscape(value) {
  const text = String(value ?? "");
  if (/[",\r\n]/u.test(text)) {
    return `"${text.replace(/"/gu, '""')}"`;
  }
  return text;
}

function normalizeCategory(category) {
  return String(category ?? "").trim().toLowerCase();
}

function addRecord(records, seen, record) {
  const normalizedTerm = normalizeVocabularyTerm(record.term);
  const category = normalizeCategory(record.category);
  if (!normalizedTerm || !category) return;

  const key = [
    normalizedTerm,
    category,
    String(record.source_module ?? "").trim().toLowerCase(),
    String(record.source_id ?? "").trim().toLowerCase(),
  ].join("|");

  if (seen.has(key)) return;
  seen.add(key);

  records.push({
    term: String(record.term ?? "").trim(),
    normalized_term: normalizedTerm,
    category,
    severity: String(record.severity ?? "medium").trim().toLowerCase(),
    language:
      String(record.language ?? "").trim().toLowerCase() ||
      detectVocabularyLanguage(record.term),
    source_module: String(record.source_module ?? "").trim(),
    source_id: String(record.source_id ?? "").trim(),
    entry_type: String(record.entry_type ?? "term").trim().toLowerCase(),
  });
}

function collectVocabulary(records, seen) {
  for (const entry of SEED_VOCABULARY) {
    addRecord(records, seen, {
      term: entry.term,
      category: entry.category,
      severity: entry.severity,
      language: entry.language,
      source_module: "vocabulary",
      source_id: "seed_vocabulary",
      entry_type: "seed_term",
    });
  }
}

function collectKnowledge(records, seen) {
  for (const entry of BUILTIN_KNOWLEDGE_ENTRIES) {
    for (const alias of entry.aliases ?? []) {
      addRecord(records, seen, {
        term: alias,
        category: entry.category,
        severity: entry.severity,
        source_module: "knowledge",
        source_id: entry.id,
        entry_type: "alias",
      });
    }
  }
}

function collectKeywordRules(records, seen) {
  for (const rule of RULES) {
    if (rule.type !== "keyword" || !Array.isArray(rule.values)) continue;
    for (const value of rule.values) {
      addRecord(records, seen, {
        term: value,
        category: rule.category,
        severity: rule.severity,
        source_module: "rules",
        source_id: rule.id,
        entry_type: "keyword",
      });
    }
  }
}

function buildCategorySummary(records) {
  const summary = {};
  for (const record of records) {
    summary[record.category] = (summary[record.category] ?? 0) + 1;
  }

  return Object.entries(summary)
    .sort((left, right) => left[0].localeCompare(right[0]))
    .map(([category, count]) => ({ category, count }));
}

function writeExports(records) {
  const exportDir = path.join(__dirname, "export");
  fs.mkdirSync(exportDir, { recursive: true });

  const sortedRecords = [...records].sort((left, right) => {
    const categoryCompare = left.category.localeCompare(right.category);
    if (categoryCompare !== 0) return categoryCompare;
    return left.normalized_term.localeCompare(right.normalized_term);
  });

  const payload = {
    generated_at: new Date().toISOString(),
    total_terms: sortedRecords.length,
    category_summary: buildCategorySummary(sortedRecords),
    notes: [
      "This export contains explicit keyword and alias entries used by the internal moderation system.",
      "Regex-only rules are not included here because they are pattern-based rather than literal terms.",
      "Some legacy source entries may require cleanup if the repository contains historical encoding issues.",
    ],
    items: sortedRecords,
  };

  fs.writeFileSync(
    path.join(exportDir, "moderation_terms.json"),
    `${JSON.stringify(payload, null, 2)}\n`,
    "utf8"
  );

  const csvHeader = [
    "term",
    "normalized_term",
    "category",
    "severity",
    "language",
    "source_module",
    "source_id",
    "entry_type",
  ];
  const csvLines = [csvHeader.join(",")];
  for (const record of sortedRecords) {
    csvLines.push(
      [
        record.term,
        record.normalized_term,
        record.category,
        record.severity,
        record.language,
        record.source_module,
        record.source_id,
        record.entry_type,
      ]
        .map(csvEscape)
        .join(",")
    );
  }
  fs.writeFileSync(
    path.join(exportDir, "moderation_terms.csv"),
    `${csvLines.join("\n")}\n`,
    "utf8"
  );
}

function main() {
  const records = [];
  const seen = new Set();

  collectVocabulary(records, seen);
  collectKnowledge(records, seen);
  collectKeywordRules(records, seen);
  writeExports(records);

  console.log(`Exported ${records.length} moderation terms to backend/moderation/export`);
}

main();
