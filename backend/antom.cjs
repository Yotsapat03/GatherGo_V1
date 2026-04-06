const crypto = require("crypto");
const https = require("https");

function getBaseUrl() {
  return String(
    process.env.ANTOM_BASE_URL ?? "https://open-sea-global.alipay.com"
  ).trim();
}

function getClientId() {
  return String(process.env.ANTOM_CLIENT_ID ?? "").trim();
}

function getPrivateKey() {
  return String(process.env.ANTOM_PRIVATE_KEY ?? "").trim();
}

function getPublicKey() {
  return String(process.env.ANTOM_PUBLIC_KEY ?? "").trim();
}

function getKeyVersion() {
  return String(process.env.ANTOM_KEY_VERSION ?? "1").trim() || "1";
}

function isConfigured() {
  return Boolean(getClientId() && getPrivateKey() && getPublicKey());
}

function buildContentToSign(method, path, clientId, requestTime, bodyText) {
  return `${String(method ?? "POST").toUpperCase()} ${path}\n${clientId}.${requestTime}.${bodyText}`;
}

function buildSignatureHeader(signatureBase64) {
  return `algorithm=RSA256,keyVersion=${getKeyVersion()},signature=${encodeURIComponent(
    signatureBase64
  )}`;
}

function parseSignatureHeader(rawHeader) {
  const raw = String(rawHeader ?? "").trim();
  if (!raw) return null;
  const parts = raw.split(",");
  const out = {};
  for (const part of parts) {
    const idx = part.indexOf("=");
    if (idx <= 0) continue;
    const key = part.slice(0, idx).trim().toLowerCase();
    const value = part.slice(idx + 1).trim();
    out[key] = value;
  }
  if (!out.signature) return null;
  try {
    out.signature = decodeURIComponent(out.signature);
  } catch (_) {}
  return out;
}

function signContent(content) {
  const signer = crypto.createSign("RSA-SHA256");
  signer.update(content, "utf8");
  signer.end();
  return signer.sign(getPrivateKey(), "base64");
}

function verifySignature({ method = "POST", path, clientId, requestTime, rawBody, signature, publicKey }) {
  const parsed = parseSignatureHeader(signature);
  if (!parsed?.signature || !path || !clientId || !requestTime || !publicKey) {
    return false;
  }
  const bodyText = Buffer.isBuffer(rawBody)
    ? rawBody.toString("utf8")
    : String(rawBody ?? "");
  const verifier = crypto.createVerify("RSA-SHA256");
  verifier.update(
    buildContentToSign(method, path, clientId, requestTime, bodyText),
    "utf8"
  );
  verifier.end();
  try {
    return verifier.verify(publicKey, parsed.signature, "base64");
  } catch (_) {
    return false;
  }
}

function requestJson(method, path, { body = null, timeoutMs = 15000 } = {}) {
  const url = new URL(path, getBaseUrl());
  const bodyText = body == null ? "" : JSON.stringify(body);
  const requestTime = new Date().toISOString();
  const clientId = getClientId();
  const signature = signContent(
    buildContentToSign(method, `${url.pathname}${url.search}`, clientId, requestTime, bodyText)
  );

  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        protocol: url.protocol,
        hostname: url.hostname,
        port: url.port || undefined,
        path: `${url.pathname}${url.search}`,
        method,
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json; charset=UTF-8",
          "Content-Length": Buffer.byteLength(bodyText),
          "client-id": clientId,
          "Request-Time": requestTime,
          Signature: buildSignatureHeader(signature),
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
            parsed?.result?.resultMessage ||
              parsed?.resultMessage ||
              parsed?.message ||
              `Antom API request failed (${res.statusCode})`
          );
          err.status = res.statusCode;
          err.response = parsed;
          err.rawBody = rawBody;
          reject(err);
        });
      }
    );

    req.setTimeout(timeoutMs, () => {
      req.destroy(new Error(`Antom API timeout after ${timeoutMs}ms`));
    });
    req.on("error", reject);
    req.write(bodyText);
    req.end();
  });
}

async function pay(payload) {
  const response = await requestJson("POST", "/ams/api/v1/payments/pay", {
    body: payload,
  });
  return response.data;
}

async function inquiryPayment(payload) {
  const response = await requestJson(
    "POST",
    "/ams/api/v1/payments/inquiryPayment",
    { body: payload }
  );
  return response.data;
}

module.exports = {
  getBaseUrl,
  isConfigured,
  pay,
  inquiryPayment,
  verifySignature,
};
