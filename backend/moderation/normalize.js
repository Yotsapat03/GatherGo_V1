const MULTILINGUAL_REPLACEMENTS = {
  thai: [
    ["à¸‚à¸§à¸¢", "à¸„à¸§à¸¢"],
    ["à¸„à¹ˆà¸§à¸¢", "à¸„à¸§à¸¢"],
    ["hee", "à¸«à¸µ"],
    ["hii", "à¸«à¸µ"],
  ],
  english: [
    ["fuk", "fuck"],
    ["fck", "fuck"],
    ["n1gger", "nigger"],
    ["nigga", "nigger"],
    ["niggra", "nigger"],
    ["niggre", "nigger"],
    ["s3x", "sex"],
  ],
  chinese: [
    ["è‰¹", "æ“"],
    ["cao", "æ“"],
  ],
};

function pushDebug(debug, transform, before, after) {
  if (before === after) return after;
  debug.push({
    transform,
    before,
    after,
  });
  return after;
}

function applyReplacement(text, debug, transform, pattern, replacement) {
  const next = text.replace(pattern, replacement);
  return pushDebug(debug, transform, text, next);
}

function escapeRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function replaceWithDictionary(text, replacements) {
  let next = text;
  for (const [from, to] of replacements) {
    const latinLike = /^[a-z0-9]+$/i.test(from);
    const pattern = latinLike
      ? new RegExp(`\\b${escapeRegex(from)}\\b`, "gu")
      : new RegExp(escapeRegex(from), "gu");
    next = next.replace(pattern, to);
  }
  return next;
}

function applyDictionaryReplacements(text, debug, transform, replacements) {
  const next = replaceWithDictionary(text, replacements);
  return pushDebug(debug, transform, text, next);
}

function applyCanonicalPatterns(text, debug, transform, canonical, patterns) {
  let next = text;
  for (const pattern of patterns) {
    next = next.replace(pattern, canonical);
  }
  return pushDebug(debug, transform, text, next);
}

function normalizeText(rawText) {
  const raw = String(rawText ?? "");
  const debug = [];

  let normalized = raw.normalize("NFKC");
  normalized = applyReplacement(
    normalized,
    debug,
    "remove_zero_width",
    /[\u200B-\u200D\uFEFF]/gu,
    ""
  );
  normalized = pushDebug(
    debug,
    "lowercase",
    normalized,
    normalized.toLowerCase()
  );
  normalized = applyDictionaryReplacements(
    normalized,
    debug,
    "dictionary_replacements_thai",
    MULTILINGUAL_REPLACEMENTS.thai
  );
  normalized = applyDictionaryReplacements(
    normalized,
    debug,
    "dictionary_replacements_english",
    MULTILINGUAL_REPLACEMENTS.english
  );
  normalized = applyDictionaryReplacements(
    normalized,
    debug,
    "dictionary_replacements_chinese",
    MULTILINGUAL_REPLACEMENTS.chinese
  );
  normalized = applyReplacement(
    normalized,
    debug,
    "normalize_qr_variants",
    /\bq[\W_]*r[\W_]*(?:c[\W_]*o[\W_]*d[\W_]*e)?\b/giu,
    "qr code"
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_fuck_obfuscation",
    "fuck",
    [
      /\bf[\W_]*u[\W_]*c[\W_]*k\b/giu,
      /\bf[\W_]*[\*!@$#][\W_]*c[\W_]*k\b/giu,
      /\bfu[\W_]+ck\b/giu,
    ]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_bitch_obfuscation",
    "bitch",
    [
      /\bb[\W_]*i[\W_]*t[\W_]*c[\W_]*h\b/giu,
      /\bb[\W_]*[!1|l][\W_]*t[\W_]*c[\W_]*h\b/giu,
      /\bbi[\W_]+tch\b/giu,
    ]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_damn_obfuscation",
    "damn",
    [/\bd[\W_]*a[\W_]*m[\W_]*n\b/giu]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_shit_obfuscation",
    "shit",
    [
      /\bs[\W_]*h[\W_]*i[\W_]*t\b/giu,
      /\bs[\W_]*h[\W_]*[!1|l][\W_]*t\b/giu,
    ]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_pussy_obfuscation",
    "pussy",
    [
      /\bp[\W_]*[uuv][\W_]*[s5$][\W_]*[s5$][\W_]*[y1!i]\b/giu,
      /\bp[\W_]*[._*]?\s*[s5$][\W_]*[s5$][\W_]*[y1!i]\b/giu,
      /\bp[\W_]*s[\W_]*s[\W_]*y\b/giu,
    ]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_dick_obfuscation",
    "dick",
    [/\bd[\W_]*[i1!l][\W_]*c[\W_]*k\b/giu]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_cock_obfuscation",
    "cock",
    [/\bc[\W_]*[o0][\W_]*c[\W_]*k\b/giu]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_blowjob_obfuscation",
    "blowjob",
    [/\bb[\W_]*l[\W_]*[o0][\W_]*w[\W_]*j[\W_]*[o0][\W_]*b\b/giu]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_handjob_obfuscation",
    "handjob",
    [/\bh[\W_]*a[\W_]*n[\W_]*d[\W_]*j[\W_]*[o0][\W_]*b\b/giu]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_nigger_obfuscation",
    "nigger",
    [
      /\bn[\W_]*[i1!l][\W_]*g[\W_]*g[\W_]*[e3a@][\W_]*[rra4@]\b/giu,
      /\bn[\W_]*[i1!l][\W_]*g[\W_]*g[\W_]*[e3][\W_]*r\b/giu,
    ]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_chinese_cao_obfuscation",
    "\u64CD",
    [/\bc[\W_]*a[\W_]*o\b/giu]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_chinese_qusi_obfuscation",
    "\u53BB\u6B7B",
    [/\bq[\W_]*u[\W_]*s[\W_]*i\b/giu, /\u53BB[\W_]*s[\W_]*i/giu]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_chinese_yuepao_obfuscation",
    "\u7EA6\u70AE",
    [/\by[\W_]*u[\W_]*e[\W_]*p[\W_]*a[\W_]*o\b/giu, /\u7EA6[\W_]*p[\W_]*a[\W_]*o/giu]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_chinese_kaifang_obfuscation",
    "\u5F00\u623F",
    [/\bk[\W_]*a[\W_]*i[\W_]*f[\W_]*a[\W_]*n[\W_]*g\b/giu, /\bk[\W_]*a[\W_]*i[\W_]*\u623F/giu]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_kuay_obfuscation",
    "\u0E04\u0E27\u0E22",
    [
      /\bk[\W_]*u[\W_]*a[\W_]*y\b/giu,
      /\bq[\W_]*u[\W_]*a[\W_]*y\b/giu,
      /\u0E04[\W_]*u[\W_]*a[\W_]*y/giu,
    ]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_hee_translit_obfuscation",
    "\u0E2B\u0E35",
    [/\bh[\W_]*e[\W_]*e\b/giu, /\u0E2B[\W_]*e[\W_]*e/giu]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_thai_profanity_obfuscation",
    "\u0E04\u0E27\u0E22",
    [
      /\u0E04[\s._-]*\u0E27[\s._-]*\u0E22/gu,
      /\u0E04[\s._-]*\u0E27[\s._-]*\u0E31[\s._-]*\u0E22/gu,
    ]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_thai_hia_obfuscation",
    "\u0E40\u0E2B\u0E35\u0E49\u0E22",
    [
      /\bh[\W_]*i[\W_]*a\b/giu,
      /\u0E40[\W_]*h[\W_]*i[\W_]*a/giu,
      /\u0E40[\s._-]*\u0E2B[\s._-]*\u0E35[\s._-]*\u0E49[\s._-]*\u0E22/gu,
      /\u0E40[\s._-]*\u0E2B[\s._-]*\u0E35[\s._-]*\u0E22/gu,
    ]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_thai_doktong_obfuscation",
    "\u0E14\u0E2D\u0E01\u0E17\u0E2D\u0E07",
    [
      /\bd[\W_]*o[\W_]*k[\W_]*t[\W_]*[o0][\W_]*n[\W_]*g\b/giu,
      /\bd[\W_]*o[\W_]*k[\W_]*t[\W_]*h[\W_]*[o0][\W_]*n[\W_]*g\b/giu,
      /\b(?:e|ee|i)[\W_]+d[\W_]*o[\W_]*k[\W_]+t[\W_]*[o0][\W_]*n[\W_]*g\b/giu,
      /\b(?:e|ee|i)[\W_]+d[\W_]*o[\W_]*k[\W_]+t[\W_]*h[\W_]*[o0][\W_]*n[\W_]*g\b/giu,
      /\u0E14[\s._-]*\u0E2D[\s._-]*\u0E01[\s._-]*t[\W_]*[o0][\W_]*n[\W_]*g/giu,
      /\u0E14[\s._-]*\u0E2D[\s._-]*\u0E01[\s._-]*t[\W_]*h[\W_]*[o0][\W_]*n[\W_]*g/giu,
    ]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_thai_yed_obfuscation",
    "\u0E40\u0E22\u0E47\u0E14",
    [/\by[\W_]*e[\W_]*d\b/giu, /\u0E40[\W_]*y[\W_]*e[\W_]*d/giu, /\u0E40[\s._-]*\u0E22[\s._-]*\u0E47[\s._-]*\u0E14/gu]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_thai_hee_obfuscation",
    "\u0E2B\u0E35",
    [/\u0E2B[\s._-]*\u0E35/gu]
  );
  normalized = applyCanonicalPatterns(
    normalized,
    debug,
    "normalize_thai_horny_translit_obfuscation",
    "\u0E40\u0E07\u0E35\u0E48\u0E22\u0E19",
    [/\bn[\W_]*g[\W_]*i[\W_]*a[\W_]*n\b/giu, /\u0E07[\W_]*i[\W_]*a[\W_]*n/giu]
  );
  normalized = applyReplacement(
    normalized,
    debug,
    "normalize_punctuation_spacing",
    /\s*([,.;:!?(){}\[\]])\s*/gu,
    " $1 "
  );
  normalized = applyReplacement(
    normalized,
    debug,
    "collapse_whitespace",
    /\s+/gu,
    " "
  );
  normalized = pushDebug(debug, "trim", normalized, normalized.trim());

  return {
    rawText: raw,
    normalizedText: normalized,
    debug,
  };
}

module.exports = {
  MULTILINGUAL_REPLACEMENTS,
  normalizeText,
};
