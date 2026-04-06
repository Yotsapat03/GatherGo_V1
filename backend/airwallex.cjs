const crypto = require("crypto");
const https = require("https");

let cachedToken = null;
let cachedTokenExpiresAt = 0;
let inFlightTokenPromise = null;

function getBaseUrl() {
  return String(process.env.AIRWALLEX_BASE_URL ?? "https://api-demo.airwallex.com").trim();
}

function isConfigured() {
  return Boolean(
    String(process.env.AIRWALLEX_CLIENT_ID ?? "").trim() &&
    String(process.env.AIRWALLEX_API_KEY ?? "").trim()
  );
}

function requestJson(method, path, { headers = {}, body = null, timeoutMs = 15000 } = {}) {
  const url = new URL(path, getBaseUrl());
  return new Promise((resolve, reject) => {
    const payload = body == null ? null : JSON.stringify(body);
    const req = https.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port || undefined,
        path: `${url.pathname}${url.search}`,
        method,
        headers: {
          Accept: "application/json",
          ...(payload
            ? {
                "Content-Type": "application/json",
                "Content-Length": Buffer.byteLength(payload),
              }
            : {}),
          ...headers,
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          const rawBody = Buffer.concat(chunks).toString("utf8");
          let parsed = null;
          if (rawBody) {
            try {
              parsed = JSON.parse(rawBody);
            } catch (_) {
              parsed = null;
            }
          }

          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve({
              status: res.statusCode,
              data: parsed,
              rawBody,
              headers: res.headers,
            });
            return;
          }

          const err = new Error(
            parsed?.message ||
              parsed?.error ||
              `Airwallex API request failed (${res.statusCode})`
          );
          err.status = res.statusCode;
          err.response = parsed;
          err.rawBody = rawBody;
          reject(err);
        });
      }
    );

    req.setTimeout(timeoutMs, () => {
      req.destroy(new Error(`Airwallex API timeout after ${timeoutMs}ms`));
    });
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

async function getAccessToken() {
  const now = Date.now();
  if (cachedToken && now < cachedTokenExpiresAt - 30000) {
    return cachedToken;
  }
  if (inFlightTokenPromise) return inFlightTokenPromise;

  inFlightTokenPromise = (async () => {
    const response = await requestJson("POST", "/api/v1/authentication/login", {
      headers: {
        "x-client-id": String(process.env.AIRWALLEX_CLIENT_ID ?? "").trim(),
        "x-api-key": String(process.env.AIRWALLEX_API_KEY ?? "").trim(),
      },
    });
    const nextToken = String(
      response?.data?.token ?? response?.data?.access_token ?? ""
    ).trim();
    const expiresInSeconds = Number(response?.data?.expires_in ?? 300) || 300;
    if (!nextToken) {
      throw new Error("Airwallex authentication response did not include a token");
    }
    cachedToken = nextToken;
    cachedTokenExpiresAt = Date.now() + expiresInSeconds * 1000;
    return cachedToken;
  })();

  try {
    return await inFlightTokenPromise;
  } finally {
    inFlightTokenPromise = null;
  }
}

async function authorizedRequest(method, path, options = {}) {
  const token = await getAccessToken();
  return requestJson(method, path, {
    ...options,
    headers: {
      Authorization: `Bearer ${token}`,
      ...(options.headers ?? {}),
    },
  });
}

async function createPaymentIntent(payload) {
  const response = await authorizedRequest("POST", "/api/v1/pa/payment_intents/create", {
    body: payload,
  });
  return response.data;
}

async function confirmPaymentIntent(paymentIntentId, payload) {
  const response = await authorizedRequest(
    "POST",
    `/api/v1/pa/payment_intents/${encodeURIComponent(paymentIntentId)}/confirm`,
    { body: payload }
  );
  return response.data;
}

async function retrievePaymentIntent(paymentIntentId) {
  const response = await authorizedRequest(
    "GET",
    `/api/v1/pa/payment_intents/${encodeURIComponent(paymentIntentId)}`
  );
  return response.data;
}

function verifyWebhookSignature({ timestamp, signature, rawBody, secret }) {
  const normalizedTimestamp = String(timestamp ?? "").trim();
  const normalizedSignature = String(signature ?? "").trim();
  const normalizedSecret = String(secret ?? "").trim();
  if (!normalizedTimestamp || !normalizedSignature || !normalizedSecret) {
    return false;
  }
  if (!/^[0-9a-fA-F]+$/.test(normalizedSignature) || normalizedSignature.length % 2 !== 0) {
    return false;
  }

  const payloadText = Buffer.isBuffer(rawBody) ? rawBody.toString("utf8") : String(rawBody ?? "");
  const expectedDigest = crypto
    .createHmac("sha256", normalizedSecret)
    .update(`${normalizedTimestamp}${payloadText}`)
    .digest();

  const actualBuffer = Buffer.from(normalizedSignature, "hex");
  const expectedBuffer = Buffer.from(expectedDigest);
  if (expectedBuffer.length !== actualBuffer.length) {
    return false;
  }
  return crypto.timingSafeEqual(expectedBuffer, actualBuffer);
}

module.exports = {
  createPaymentIntent,
  confirmPaymentIntent,
  retrievePaymentIntent,
  verifyWebhookSignature,
  isConfigured,
};
