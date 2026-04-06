function escapeRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

const CANONICAL_SUBSTITUTIONS = {
  "0": "o",
  "1": "i",
  "!": "i",
  "3": "e",
  "4": "a",
  "@": "a",
  "5": "s",
  "$": "s",
  "7": "t",
};

const MULTI_CHAR_REPLACEMENTS = [
  { from: /\bf[\W_]*u[\W_]*c[\W_]*k\b/giu, to: "fuck" },
  { from: /\bb[\W_]*i[\W_]*t[\W_]*c[\W_]*h\b/giu, to: "bitch" },
  { from: /\bn[\W_]*i[\W_]*g[\W_]*g[\W_]*e[\W_]*r\b/giu, to: "nigger" },
  { from: /\bn[\W_]*i[\W_]*g[\W_]*g[\W_]*a\b/giu, to: "nigga" },
  { from: /\bs[\W_]*p[\W_]*i[\W_]*c\b/giu, to: "spic" },
  { from: /\bk[\W_]*i[\W_]*k[\W_]*e\b/giu, to: "kike" },
  { from: /\br[\W_]*e[\W_]*t[\W_]*a[\W_]*r[\W_]*d\b/giu, to: "retard" },
];

function collapseRepeats(value) {
  return value.replace(/([a-z])\1{2,}/g, "$1$1");
}

function applySubstitutions(value) {
  return value.replace(/[013457!@$]/g, (char) => CANONICAL_SUBSTITUTIONS[char] || char);
}

function buildTokenVariants(token) {
  const raw = String(token ?? "").trim();
  if (!raw) return [];

  const lower = raw.toLowerCase();
  const substituted = applySubstitutions(lower);
  const collapsed = collapseRepeats(substituted);
  const stripped = collapsed.replace(/[^a-z0-9]/g, "");

  return Array.from(new Set([lower, substituted, collapsed, stripped].filter(Boolean)));
}

function tokenizePreservingQuotes(text) {
  return text.match(/"[^"]+"|'[^']+'|\S+/g) ?? [];
}

function normalizeText(rawText) {
  const raw = String(rawText ?? "");
  const debug = [];

  let normalized = raw.normalize("NFKC");
  const push = (step, before, after) => {
    if (before !== after) {
      debug.push({ step, before, after });
    }
    return after;
  };

  normalized = push("remove_zero_width", normalized, normalized.replace(/[\u200B-\u200D\uFEFF]/gu, ""));
  normalized = push("lowercase", normalized, normalized.toLowerCase());
  normalized = push("canonical_spacing", normalized, normalized.replace(/[\r\n\t]+/g, " "));

  for (const replacement of MULTI_CHAR_REPLACEMENTS) {
    normalized = push(
      `multi_char:${replacement.to}`,
      normalized,
      normalized.replace(replacement.from, replacement.to)
    );
  }

  normalized = push("symbol_substitution", normalized, applySubstitutions(normalized));
  normalized = push("collapse_repeats", normalized, collapseRepeats(normalized));
  normalized = push("collapse_spacing", normalized, normalized.replace(/\s+/g, " ").trim());

  const collapsedAlnum = normalized.replace(/[^a-z0-9\s]/g, " ");
  const compact = normalized.replace(/[^a-z0-9]/g, "");
  const tokens = tokenizePreservingQuotes(normalized).map((token) => ({
    raw: token,
    variants: buildTokenVariants(token),
  }));

  return {
    raw_text: raw,
    normalized_text: normalized,
    collapsed_alnum_text: collapsedAlnum.replace(/\s+/g, " ").trim(),
    compact_text: compact,
    tokens,
    debug,
  };
}

module.exports = {
  escapeRegex,
  normalizeText,
  buildTokenVariants,
};
