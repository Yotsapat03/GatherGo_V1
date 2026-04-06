const OpenAI = require("openai");

const DEFAULT_MODEL = String(process.env.OPENAI_LLM_MODERATION_MODEL ?? "gpt-5-mini").trim() || "gpt-5-mini";
const DEFAULT_TIMEOUT_MS = Number(process.env.OPENAI_LLM_MODERATION_TIMEOUT_MS ?? 4000) || 4000;
const MAX_RAW_CHARS = Number(process.env.OPENAI_LLM_MODERATION_MAX_RAW_CHARS ?? 500) || 500;
const MAX_CONTEXT_ITEMS = Number(process.env.OPENAI_LLM_MODERATION_MAX_CONTEXT_ITEMS ?? 5) || 5;

let cachedClient = null;

function getClient() {
  const apiKey = String(process.env.OPENAI_API_KEY ?? "").trim();
  if (!apiKey) return null;
  if (!cachedClient) {
    cachedClient = new OpenAI({ apiKey });
  }
  return cachedClient;
}

function isEnabled() {
  return String(process.env.OPENAI_LLM_MODERATION_ENABLED ?? "").trim().toLowerCase() === "true";
}

function buildSchema() {
  return {
    name: "moderation_decision",
    schema: {
      type: "object",
      additionalProperties: false,
      properties: {
        is_flagged: { type: "boolean" },
        categories: {
          type: "array",
          items: {
            type: "string",
            enum: [
              "profanity",
              "targeted_abuse",
              "hate_speech",
              "sexual_ambiguous",
              "sexual_harassment",
              "threat",
              "scam_risk",
            ],
          },
        },
        severity: {
          type: "string",
          enum: ["low", "medium", "high", "critical"],
        },
        action: {
          type: "string",
          enum: ["allow", "review", "block"],
        },
        reason: { type: "string" },
        confidence: { type: "number" },
      },
      required: ["is_flagged", "categories", "severity", "action", "reason", "confidence"],
    },
  };
}

function clampMessage(text) {
  const input = String(text ?? "").trim();
  return input.length <= MAX_RAW_CHARS ? input : input.slice(0, MAX_RAW_CHARS);
}

function buildPrompt({ rawMessage, normalizedMessage, ruleAnalysis, knowledge, safety, aiReasons }) {
  const compactKnowledge = (knowledge?.matches ?? []).slice(0, MAX_CONTEXT_ITEMS).map((item) => ({
    title: item.title,
    category: item.category,
    severity: item.severity,
    rationale: item.rationale,
    matched_aliases: item.matched_aliases,
  }));

  return [
    "You are a multilingual moderation classifier for a running community chat app.",
    "Classify only the user message. Supporting context is provided to improve accuracy.",
    "Return strict JSON matching the schema.",
    "Allowed categories: profanity, targeted_abuse, hate_speech, sexual_ambiguous, sexual_harassment, threat, scam_risk.",
    "Use action=allow for clean content, review for borderline/ambiguous content, and block for unsafe content.",
    "Normal running coordination and harmless scheduling should be allow.",
    "",
    `Raw message: ${JSON.stringify(clampMessage(rawMessage))}`,
    `Normalized message: ${JSON.stringify(normalizedMessage)}`,
    `Rule categories: ${JSON.stringify(ruleAnalysis?.categories ?? [])}`,
    `Rule hits: ${JSON.stringify((ruleAnalysis?.hits ?? []).slice(0, 8).map((hit) => ({
      category: hit.category,
      severity: hit.severity,
      matched_value: hit.matched_value,
      match_type: hit.match_type,
    })))}`,
    `Knowledge evidence: ${JSON.stringify(compactKnowledge)}`,
    `Safety result: ${JSON.stringify({
      action: safety?.action ?? null,
      categories: safety?.categories ?? [],
      severity: safety?.severity ?? null,
      rationale: safety?.rationale ?? null,
    })}`,
    `Escalation reasons: ${JSON.stringify(aiReasons ?? [])}`,
  ].join("\n");
}

function sanitizeResult(parsed) {
  const safe = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
  const categories = Array.isArray(safe.categories) ? safe.categories.filter(Boolean).slice(0, 5) : [];
  let confidence = Number(safe.confidence);
  if (!Number.isFinite(confidence)) confidence = 0;
  confidence = Math.max(0, Math.min(confidence, 1));

  return {
    is_flagged: Boolean(safe.is_flagged),
    categories,
    severity: ["low", "medium", "high", "critical"].includes(safe.severity) ? safe.severity : "low",
    action: ["allow", "review", "block"].includes(safe.action) ? safe.action : "allow",
    reason: typeof safe.reason === "string" && safe.reason.trim() ? safe.reason.trim() : "No policy issue detected",
    confidence,
  };
}

async function classifyWithOpenAIReasoning(input) {
  if (!isEnabled()) {
    return {
      attempted: false,
      used: false,
      provider: "openai_responses",
      model: DEFAULT_MODEL,
      skipped_reason: "disabled",
      result: null,
      error: null,
    };
  }

  const client = getClient();
  if (!client) {
    return {
      attempted: false,
      used: false,
      provider: "openai_responses",
      model: DEFAULT_MODEL,
      skipped_reason: "missing_api_key",
      result: null,
      error: "OPENAI_API_KEY is not configured",
    };
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);

  try {
    const response = await client.responses.create(
      {
        model: DEFAULT_MODEL,
        input: buildPrompt(input),
        text: {
          format: {
            type: "json_schema",
            ...buildSchema(),
          },
        },
        reasoning: { effort: "low" },
      },
      {
        signal: controller.signal,
      }
    );

    const content = response.output_text?.trim();
    if (!content) {
      return {
        attempted: true,
        used: false,
        provider: "openai_responses",
        model: DEFAULT_MODEL,
        skipped_reason: "empty_response",
        result: null,
        error: "OpenAI Responses returned no text output",
      };
    }

    let parsed;
    try {
      parsed = JSON.parse(content);
    } catch (_) {
      return {
        attempted: true,
        used: false,
        provider: "openai_responses",
        model: DEFAULT_MODEL,
        skipped_reason: "invalid_json",
        result: null,
        error: "OpenAI Responses returned invalid JSON",
        raw_text: content,
      };
    }

    return {
      attempted: true,
      used: true,
      provider: "openai_responses",
      model: DEFAULT_MODEL,
      skipped_reason: null,
      result: sanitizeResult(parsed),
      error: null,
      usage: response.usage ?? null,
      response_id: response.id ?? null,
    };
  } catch (error) {
    return {
      attempted: true,
      used: false,
      provider: "openai_responses",
      model: DEFAULT_MODEL,
      skipped_reason: error?.name === "AbortError" ? "timeout" : "api_error",
      result: null,
      error:
        error?.status && typeof error.status === "number"
          ? `OpenAI reasoning moderation failed (${error.status}).`
          : String(error?.message ?? error),
    };
  } finally {
    clearTimeout(timer);
  }
}

module.exports = {
  classifyWithOpenAIReasoning,
  isOpenAIReasonedModerationEnabled: isEnabled,
};
