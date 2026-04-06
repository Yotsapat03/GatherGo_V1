const OpenAI = require("openai");

const MODERATION_MODEL = "omni-moderation-latest";

let cachedClient = null;

function getClient() {
  const apiKey = String(process.env.OPENAI_API_KEY ?? "").trim();
  if (!apiKey) return null;
  if (!cachedClient) {
    cachedClient = new OpenAI({ apiKey });
  }
  return cachedClient;
}

function emptyModerationResult(extra = {}) {
  return {
    attempted: false,
    provider: "openai",
    model: MODERATION_MODEL,
    flagged: false,
    categories: {},
    category_scores: {},
    category_applied_input_types: null,
    error: null,
    ...extra,
  };
}

async function moderateText(text) {
  const input = String(text ?? "").trim();
  if (!input) {
    return emptyModerationResult({
      error: { code: "empty_input", message: "Text is empty." },
    });
  }

  const client = getClient();
  if (!client) {
    return emptyModerationResult({
      error: {
        code: "missing_api_key",
        message: "OPENAI_API_KEY is not configured.",
      },
    });
  }

  try {
    const response = await client.moderations.create({
      model: MODERATION_MODEL,
      input,
    });

    const result = response?.results?.[0] ?? {};
    return {
      attempted: true,
      provider: "openai",
      model: MODERATION_MODEL,
      flagged: result.flagged === true,
      categories: result.categories ?? {},
      category_scores: result.category_scores ?? {},
      category_applied_input_types: result.category_applied_input_types ?? null,
      error: null,
    };
  } catch (error) {
    return emptyModerationResult({
      attempted: true,
      error: {
        code: error?.code ?? error?.name ?? "openai_error",
        message:
          error?.status && typeof error.status === "number"
            ? `Moderation request failed (${error.status}).`
            : "Moderation request failed.",
      },
    });
  }
}

module.exports = {
  MODERATION_MODEL,
  moderateText,
};
