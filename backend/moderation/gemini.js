const ALLOWED_CATEGORIES = [
  "profanity",
  "targeted_abuse",
  "hate_speech",
  "sexual_ambiguous",
  "sexual_harassment",
  "threat",
  "scam_risk",
];

const ALLOWED_SEVERITIES = ["low", "medium", "high", "critical"];
const DEFAULT_GEMINI_MODEL = process.env.GEMINI_MODEL?.trim() || "gemini-2.5-flash-lite";
const DEFAULT_TIMEOUT_MS = Number(process.env.GEMINI_TIMEOUT_MS ?? 2500) || 2500;
const DEBUG_GEMINI_PROMPT = String(process.env.GEMINI_DEBUG_PROMPT ?? "").trim().toLowerCase() === "true";

let hasLoggedMissingKey = false;
let hasLoggedMissingFetch = false;

function logGeminiUnavailableOnce(message) {
  if (message === "missing_api_key" && hasLoggedMissingKey) return;
  if (message === "missing_fetch" && hasLoggedMissingFetch) return;

  console.warn(`[moderation][gemini] ${message}`);
  if (message === "missing_api_key") hasLoggedMissingKey = true;
  if (message === "missing_fetch") hasLoggedMissingFetch = true;
}

function buildGeminiResponseSchema() {
  return {
    type: "object",
    additionalProperties: false,
    properties: {
      is_flagged: { type: "boolean" },
      categories: {
        type: "array",
        items: {
          type: "string",
          enum: ALLOWED_CATEGORIES,
        },
      },
      severity: {
        type: "string",
        enum: ALLOWED_SEVERITIES,
      },
      reason: { type: "string" },
      confidence: { type: "number" },
      suggested_terms: {
        type: "array",
        items: { type: "string" },
      },
    },
    required: ["is_flagged", "categories", "severity", "reason", "confidence"],
  };
}

function sanitizePromptValue(value) {
  return String(value ?? "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .trim();
}

function buildGeminiModerationPrompt({ rawMessage, normalizedMessage, ruleAnalysis, aiReasons }) {
  const finalRawMessage = sanitizePromptValue(rawMessage);
  const finalNormalizedMessage = sanitizePromptValue(normalizedMessage);

  return [
    "You are a multilingual chat moderation classifier for a running community app.",
    "Analyze only the content inside the <message> block.",
    "Do not classify instructions, policy text, or examples outside the <message> block.",
    "Analyze Thai, English, Chinese, and mixed-language chat text.",
    "Detect only these categories: profanity, targeted_abuse, hate_speech, sexual_ambiguous, sexual_harassment, threat, scam_risk.",
    "Return JSON only.",
    "Treat disguised spellings, obfuscations, slang, transliteration, and mixed-language wording as valid signals.",
    "Do not over-classify normal running coordination, meetup logistics, pace discussion, route discussion, or harmless scheduling.",
    "Profanity is less severe than targeted abuse, hate speech, sexual content violations, threats, and scam risk.",
    "Profanity means ordinary swearing that is not clearly targeted at a person.",
    "Targeted abuse includes direct insults, aggressive profanity aimed at another person, commands like 'fuck you', 'fuck off', 'go to hell', and equivalent Thai or Chinese direct attacks.",
    "Sexual ambiguous means suggestive or sexualized wording that is inappropriate but not clearly coercive, threatening, or persistent harassment.",
    "Scam risk includes transfer requests, suspicious links, off-platform contact bait, fake urgency, fraud-like persuasion, and attempts to move payment outside the app.",
    "Sexual harassment includes coercive sexual requests, unwanted sexualized comments, pressure for intimacy, and threatening sexual language.",
    "Threat includes threats of harm, violent intimidation, 'go die', and similar violent language.",
    "Hate speech includes demeaning or discriminatory attacks against protected groups.",
    "If you identify abusive or harmful wording that seems new or not explicitly covered by the rule hits, include short lowercase suggestion terms in suggested_terms.",
    "",
    `Raw message: ${JSON.stringify(finalRawMessage)}`,
    `Normalized message: ${JSON.stringify(finalNormalizedMessage)}`,
    `Rule categories: ${JSON.stringify(ruleAnalysis.categories ?? [])}`,
    `Rule hits: ${JSON.stringify((ruleAnalysis.hits ?? []).map((hit) => ({
      rule_id: hit.rule_id,
      category: hit.category,
      severity: hit.severity,
    })))}`,
    `Why AI was requested: ${JSON.stringify(aiReasons ?? [])}`,
    "",
    "If no policy issue is present, return:",
    '{"is_flagged":false,"categories":[],"severity":"low","reason":"No policy issue detected","confidence":0.90}',
    "",
    "<message>",
    `RAW: ${JSON.stringify(finalRawMessage)}`,
    `NORMALIZED: ${JSON.stringify(finalNormalizedMessage)}`,
    "</message>",
  ].join("\n");
}

function sanitizeGeminiClassification(parsed) {
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("Gemini response must be a JSON object");
  }

  const isFlagged = Boolean(parsed.is_flagged);
  const categories = Array.isArray(parsed.categories)
    ? parsed.categories.filter((value) => ALLOWED_CATEGORIES.includes(value))
    : [];
  const severity = ALLOWED_SEVERITIES.includes(parsed.severity) ? parsed.severity : "low";
  const reason = typeof parsed.reason === "string" && parsed.reason.trim()
    ? parsed.reason.trim()
    : "No policy issue detected";

  let confidence = Number(parsed.confidence);
  if (!Number.isFinite(confidence)) confidence = 0;
  confidence = Math.max(0, Math.min(confidence, 1));

  return {
    is_flagged: isFlagged,
    categories,
    severity,
    reason,
    confidence,
    suggested_terms: Array.isArray(parsed.suggested_terms)
      ? parsed.suggested_terms
          .map((value) => (typeof value === "string" ? value.trim().toLowerCase() : ""))
          .filter(Boolean)
          .slice(0, 5)
      : [],
  };
}

async function classifyWithGemini({ rawMessage, normalizedMessage, ruleAnalysis, aiReasons }) {
  const apiKey = String(process.env.GEMINI_API_KEY ?? "").trim();
  if (!apiKey) {
    logGeminiUnavailableOnce("missing_api_key");
    return {
      attempted: false,
      used: false,
      provider: "gemini",
      model: DEFAULT_GEMINI_MODEL,
      skipped_reason: "missing_api_key",
      result: null,
      error: "GEMINI_API_KEY is not configured",
    };
  }

  if (typeof fetch !== "function") {
    logGeminiUnavailableOnce("missing_fetch");
    return {
      attempted: false,
      used: false,
      provider: "gemini",
      model: DEFAULT_GEMINI_MODEL,
      skipped_reason: "missing_fetch",
      result: null,
      error: "Global fetch is unavailable in this Node runtime",
    };
  }

  const model = String(process.env.GEMINI_MODEL ?? DEFAULT_GEMINI_MODEL).trim() || DEFAULT_GEMINI_MODEL;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);

  try {
    const finalPrompt = buildGeminiModerationPrompt({
      rawMessage,
      normalizedMessage,
      ruleAnalysis,
      aiReasons,
    });
    if (DEBUG_GEMINI_PROMPT) {
      console.debug("[moderation][gemini] prompt_debug", {
        rawMessage: sanitizePromptValue(rawMessage),
        normalizedMessage: sanitizePromptValue(normalizedMessage),
        hasRawPlaceholder: finalPrompt.includes("{{raw_message}}"),
        hasNormalizedPlaceholder: finalPrompt.includes("{{normalized_message}}"),
        finalPrompt,
      });
    }

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(apiKey)}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        signal: controller.signal,
        body: JSON.stringify({
          contents: [
            {
              role: "user",
              parts: [
                {
                  text: finalPrompt,
                },
              ],
            },
          ],
          generationConfig: {
            temperature: 0.1,
            maxOutputTokens: 256,
            responseMimeType: "application/json",
            responseJsonSchema: buildGeminiResponseSchema(),
          },
        }),
      }
    );

    const payload = await response.json().catch(() => null);
    if (!response.ok) {
      return {
        attempted: true,
        used: false,
        provider: "gemini",
        model,
        skipped_reason: "api_error",
        result: null,
        error: payload?.error?.message || `Gemini HTTP ${response.status}`,
      };
    }

    const text = payload?.candidates?.[0]?.content?.parts
      ?.map((part) => part?.text ?? "")
      .join("")
      .trim();
    if (!text) {
      return {
        attempted: true,
        used: false,
        provider: "gemini",
        model,
        skipped_reason: "empty_response",
        result: null,
        error: "Gemini returned no text content",
      };
    }

    let parsed;
    try {
      parsed = JSON.parse(text);
    } catch (_) {
      return {
        attempted: true,
        used: false,
        provider: "gemini",
        model,
        skipped_reason: "invalid_json",
        result: null,
        error: "Gemini returned non-JSON content",
        raw_text: text,
      };
    }
    const result = sanitizeGeminiClassification(parsed);

    return {
      attempted: true,
      used: true,
      provider: "gemini",
      model,
      skipped_reason: null,
      result,
      error: null,
      raw_text: text,
    };
  } catch (error) {
    const isAbort = error?.name === "AbortError";
    return {
      attempted: true,
      used: false,
      provider: "gemini",
      model,
      skipped_reason: isAbort ? "timeout" : "request_failed",
      result: null,
      error: String(error?.message ?? error),
    };
  } finally {
    clearTimeout(timer);
  }
}

module.exports = {
  ALLOWED_CATEGORIES,
  ALLOWED_SEVERITIES,
  DEFAULT_GEMINI_MODEL,
  buildGeminiModerationPrompt,
  buildGeminiResponseSchema,
  classifyWithGemini,
  sanitizeGeminiClassification,
};
