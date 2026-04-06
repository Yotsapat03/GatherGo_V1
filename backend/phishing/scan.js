const crypto = require("crypto");

function extractUrls(text) {
  const input = String(text ?? "");
  const matches = input.match(/((https?:\/\/)|(www\.))[^\s]+/gi) ?? [];
  return Array.from(new Set(matches.map((item) => item.trim()).filter(Boolean)));
}

function normalizeUrl(rawUrl) {
  const input = String(rawUrl ?? "").trim();
  if (!input) return null;

  const candidate = /^www\./i.test(input) ? `https://${input}` : input;
  try {
    const url = new URL(candidate);
    const protocol = url.protocol.toLowerCase();
    const hostname = url.hostname.toLowerCase();
    const pathname = url.pathname === "/" ? "" : url.pathname.replace(/\/+$/, "");
    const search = url.search ?? "";
    return `${protocol}//${hostname}${pathname}${search}`;
  } catch (_) {
    return null;
  }
}

function getDomainFromUrl(normalizedUrl) {
  if (!normalizedUrl) return null;
  try {
    return new URL(normalizedUrl).hostname.toLowerCase();
  } catch (_) {
    return null;
  }
}

function hashUrl(normalizedUrl) {
  if (!normalizedUrl) return null;
  return crypto.createHash("sha256").update(normalizedUrl).digest("hex");
}

function classifyFromRuleScore(riskScore) {
  if (riskScore >= 70) return "phishing";
  if (riskScore >= 30) return "suspicious";
  return "safe";
}

function tryMatchRule(rule, normalizedUrl, domain, messageText) {
  const value = String(rule?.rule_value ?? "").trim();
  if (!value) return false;

  const urlText = String(normalizedUrl ?? "");
  const domainText = String(domain ?? "");
  const message = String(messageText ?? "");
  const ruleType = String(rule?.rule_type ?? "").trim().toLowerCase();

  const regexTypes = new Set(["domain_pattern", "url_pattern", "keyword_pattern", "regex"]);
  if (regexTypes.has(ruleType)) {
    try {
      const pattern = new RegExp(value, "i");
      if (ruleType === "domain_pattern") return pattern.test(domainText);
      if (ruleType === "url_pattern") return pattern.test(urlText);
      return pattern.test(message) || pattern.test(urlText);
    } catch (_) {
      // Fall through to substring matching below if the rule value is not valid regex.
    }
  }

  const normalizedValue = value.toLowerCase();
  if (ruleType === "domain_pattern") {
    return domainText.toLowerCase().includes(normalizedValue);
  }
  if (ruleType === "url_pattern") {
    return urlText.toLowerCase().includes(normalizedValue);
  }
  return (
    message.toLowerCase().includes(normalizedValue) ||
    urlText.toLowerCase().includes(normalizedValue)
  );
}

async function findIndicatorMatch(client, normalizedUrl, domain, urlHash) {
  const result = await client.query(
    `
    SELECT
      id,
      feed_id,
      normalized_url,
      domain,
      url_hash,
      verification_status,
      confidence_score,
      source_ref
    FROM public.phishing_indicators
    WHERE is_active = TRUE
      AND (
        ($1::text IS NOT NULL AND normalized_url = $1)
        OR ($2::text IS NOT NULL AND domain = $2)
        OR ($3::text IS NOT NULL AND url_hash = $3)
      )
    ORDER BY confidence_score DESC, id DESC
    LIMIT 1
    `,
    [normalizedUrl, domain, urlHash]
  );
  return result.rows[0] ?? null;
}

async function findRuleMatch(client, normalizedUrl, domain, messageText) {
  const result = await client.query(
    `
    SELECT id, rule_name, rule_type, rule_value, risk_score
    FROM public.phishing_detection_rules
    WHERE is_active = TRUE
    ORDER BY risk_score DESC, id DESC
    `
  );

  for (const row of result.rows) {
    if (tryMatchRule(row, normalizedUrl, domain, messageText)) {
      return row;
    }
  }

  return null;
}

async function scanSpotChatMessageUrls(client, messageText) {
  const extractedUrls = extractUrls(messageText);
  if (extractedUrls.length === 0) {
    return {
      containsUrl: false,
      moderationStatus: "visible",
      riskLevel: "safe",
      phishingScanStatus: "not_scanned",
      phishingScanReason: null,
      decisionSource: null,
      blockedAt: null,
      scans: [],
    };
  }

  const scans = [];
  let overallRisk = "safe";
  let overallModerationStatus = "visible";
  let overallReason = null;
  let overallSource = null;

  for (const rawUrl of extractedUrls) {
    const normalizedUrl = normalizeUrl(rawUrl);
    const domain = getDomainFromUrl(normalizedUrl);
    const urlHash = hashUrl(normalizedUrl);

    const indicator = await findIndicatorMatch(client, normalizedUrl, domain, urlHash);
    if (indicator) {
      const result =
        String(indicator.verification_status ?? "").toLowerCase() === "verified"
          ? "phishing"
          : "suspicious";
      const reason =
        result === "phishing"
          ? "Matched a known phishing indicator."
          : "Matched a suspicious URL indicator.";

      scans.push({
        scannedUrl: rawUrl,
        normalizedUrl,
        matchedIndicatorId: indicator.id,
        sourceName: "phishing_indicators",
        result,
        confidenceScore: Number(indicator.confidence_score ?? 1),
        detectionMethod: "indicator_match",
        reason,
      });

      if (result === "phishing") {
        overallRisk = "phishing";
        overallModerationStatus = "blocked";
        overallReason = reason;
        overallSource = "phishing_indicator";
      } else if (overallRisk !== "phishing") {
        overallRisk = "suspicious";
        overallModerationStatus = "warning";
        overallReason = reason;
        overallSource = "phishing_indicator";
      }
      continue;
    }

    const rule = await findRuleMatch(client, normalizedUrl, domain, messageText);
    if (rule) {
      const result = classifyFromRuleScore(Number(rule.risk_score ?? 0));
      const reason = `Matched phishing detection rule: ${rule.rule_name}`;
      scans.push({
        scannedUrl: rawUrl,
        normalizedUrl,
        matchedIndicatorId: null,
        sourceName: rule.rule_name,
        result,
        confidenceScore: Math.min(1, Math.max(0.2, Number(rule.risk_score ?? 0) / 100)),
        detectionMethod: "rule_match",
        reason,
      });

      if (result === "phishing") {
        overallRisk = "phishing";
        overallModerationStatus = "blocked";
        overallReason = reason;
        overallSource = "phishing_indicator";
      } else if (result === "suspicious" && overallRisk !== "phishing") {
        overallRisk = "suspicious";
        overallModerationStatus = "warning";
        overallReason = reason;
        overallSource = "phishing_indicator";
      }
      continue;
    }

    scans.push({
      scannedUrl: rawUrl,
      normalizedUrl,
      matchedIndicatorId: null,
      sourceName: null,
      result: "safe",
      confidenceScore: 0,
      detectionMethod: "no_match",
      reason: "No phishing indicators or rules matched.",
    });
  }

  return {
    containsUrl: true,
    moderationStatus: overallModerationStatus,
    riskLevel: overallRisk,
    phishingScanStatus: "scanned",
    phishingScanReason: overallReason,
    decisionSource: overallSource,
    blockedAt: overallRisk === "phishing" ? new Date() : null,
    scans,
  };
}

module.exports = {
  extractUrls,
  getDomainFromUrl,
  hashUrl,
  normalizeUrl,
  scanSpotChatMessageUrls,
};
