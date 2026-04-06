const {
  MULTILINGUAL_REPLACEMENTS,
  normalizeText,
} = require("./normalize.js");

function normalizeModerationText(rawText) {
  const result = normalizeText(rawText);

  return {
    raw: result.rawText,
    normalized: result.normalizedText,
    replacements: MULTILINGUAL_REPLACEMENTS,
    debug: result.debug,
  };
}

module.exports = {
  MULTILINGUAL_REPLACEMENTS,
  normalizeModerationText,
};
