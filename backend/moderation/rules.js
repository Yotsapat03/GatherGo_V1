const SEVERITY_SCORES = {
  low: 1,
  medium: 2,
  high: 3,
  critical: 4,
};

const RULES = [
  {
    id: "thai_profanity_core",
    category: "profanity",
    severity: "medium",
    type: "keyword",
    values: ["à¸„à¸§à¸¢", "à¹€à¸«à¸µà¹‰à¸¢", "à¸ªà¸±à¸ª", "à¸«à¸µ", "à¹€à¸¢à¹‡à¸”", "à¸”à¸­à¸", "à¹€à¸§à¸£"],
  },
  {
    id: "thai_profanity_unicode_core",
    category: "profanity",
    severity: "medium",
    type: "keyword",
    values: [
      "\u0E04\u0E27\u0E22",
      "\u0E40\u0E2B\u0E35\u0E49\u0E22",
      "\u0E2A\u0E31\u0E2A",
      "\u0E2B\u0E35",
      "\u0E40\u0E22\u0E47\u0E14",
    ],
  },
  {
    id: "english_profanity_core",
    category: "profanity",
    severity: "medium",
    type: "keyword",
    values: ["fuck", "shit", "bitch", "asshole", "bastard", "damn", "motherfucker"],
  },
  {
    id: "thai_translit_profanity_kee",
    category: "profanity",
    severity: "medium",
    type: "regex",
    pattern: /\bk[\W_]*e[\W_]*e\b/giu,
  },
  {
    id: "profanity_directed_english",
    category: "profanity",
    severity: "medium",
    type: "regex",
    pattern: /\b(fuck you|fuck off|stfu|shut the fuck up|you('re| are)? (such )?(a )?(bitch|asshole|piece of shit))\b/giu,
  },
  {
    id: "targeted_abuse_english",
    category: "targeted_abuse",
    severity: "high",
    type: "regex",
    pattern: /\b(go to hell|screw you|you('re| are)? (such )?(a )?(moron|idiot|loser|dickhead))\b/giu,
  },
  {
    id: "targeted_abuse_thai",
    category: "targeted_abuse",
    severity: "high",
    type: "regex",
    pattern: /(à¸¡à¸¶à¸‡|à¹à¸|à¸„à¸¸à¸“)\s*(à¸„à¸§à¸¢|à¹€à¸«à¸µà¹‰à¸¢|à¸ªà¸±à¸ª|à¸«à¸µ)|(à¹„à¸›à¸¥à¸‡à¸™à¸£à¸)|(à¸­à¸µà¹€à¸«à¸µà¹‰à¸¢|à¹„à¸­à¹‰à¸ªà¸±à¸ª|à¹€à¸¢à¹‡à¸”à¹à¸¡à¹ˆ)/gu,
  },
  {
    id: "targeted_abuse_thai_unicode_keywords",
    category: "targeted_abuse",
    severity: "high",
    type: "keyword",
    values: [
      "\u0E14\u0E2D\u0E01\u0E17\u0E2D\u0E07",
      "\u0E2D\u0E35\u0E14\u0E2D\u0E01\u0E17\u0E2D\u0E07",
    ],
  },
  {
    id: "targeted_abuse_chinese",
    category: "targeted_abuse",
    severity: "high",
    type: "regex",
    pattern: /(æ“ä½ |æ»šå¼€|ä½ .*(å‚»é€¼|ç¬¨è›‹|åºŸç‰©)|ä»–å¦ˆçš„ä½ )/gu,
  },
  {
    id: "chinese_profanity_core",
    category: "profanity",
    severity: "medium",
    type: "keyword",
    values: ["æ“", "å¦ˆçš„", "å‚»é€¼", "ç¬¨è›‹", "åºŸç‰©"],
  },
  {
    id: "hate_speech_slurs",
    category: "hate_speech",
    severity: "high",
    type: "keyword",
    values: ["nigger", "chink", "æ”¯é‚£", "à¸à¸°à¸«à¸£à¸µà¹ˆ", "à¹„à¸­à¹‰à¸¥à¸²à¸§"],
  },
  {
    id: "hate_speech_phrases",
    category: "hate_speech",
    severity: "high",
    type: "regex",
    pattern: /\b(go back to your country|dirty chinese|hate (gay|black|asian) people|your country\b.{0,24}\beat\s+(cat|cats|dog|dogs|meow|meaw)|ladyboy country|country of ladyboys)\b/giu,
  },
  {
    id: "sexual_harassment_keywords",
    category: "sexual_harassment",
    severity: "critical",
    type: "keyword",
    values: ["send nudes", "show boobs", "à¸‚à¸­à¹€à¸¢à¹‡à¸”", "à¸ˆà¸±à¸šà¸™à¸¡", "çº¦ç‚®", "å¼€æˆ¿", "é™ªç¡"],
  },
  {
    id: "sexual_harassment_unicode_keywords",
    category: "sexual_harassment",
    severity: "critical",
    type: "keyword",
    values: [
      "\u0E40\u0E22\u0E47\u0E14",
      "\u0E02\u0E2D\u0E21\u0E35\u0E40\u0E0B\u0E47\u0E01\u0E0B\u0E4C",
      "\u7EA6\u70AE",
      "\u5F00\u623F",
      "\u966A\u7761",
    ],
  },
  {
    id: "sexual_harassment_regex",
    category: "sexual_harassment",
    severity: "critical",
    type: "regex",
    pattern: /\b(send (me )?(nudes|your body)|want to have sex|sleep with me|show me your boobs)\b|à¸„à¸·à¸™à¸™à¸µà¹‰à¹„à¸›à¹€à¸­à¸²à¸à¸±à¸™|à¸‚à¸­à¸¡à¸µà¹€à¸‹à¹‡à¸à¸‹à¹Œ/giu,
  },
  {
    id: "sexual_harassment_room_invite_bait",
    category: "sexual_harassment",
    severity: "critical",
    type: "regex",
    pattern: /\b(go|come)\s+(to|into)\s+my\s+room\b.{0,48}\b(special|spacial|private|intimate|naughty)\s+(thing|things|time)\b|\bwe\s+will\s+have\b.{0,24}\b(special|spacial|private|sexual|intimate)\s+(thing|things|time)\b/giu,
  },
  {
    id: "sexual_ambiguous_english",
    category: "sexual_ambiguous",
    severity: "medium",
    type: "regex",
    pattern: /\b(sexy|so horny|hot body|turn me on|you look so hot|private tonight|pussy|dick|cock|blowjob|handjob|boob(?:s|ie|ies)?)\b/giu,
  },
  {
    id: "sexual_ambiguous_thai_chinese",
    category: "sexual_ambiguous",
    severity: "medium",
    type: "regex",
    pattern: /(à¸«à¸¸à¹ˆà¸™à¸”à¸µ|à¹€à¸‹à¹‡à¸à¸‹à¸µà¹ˆ|à¸‚à¸­à¸”à¸¹à¸«à¸™à¹ˆà¸­à¸¢|ä½ å¥½éªš|å¥½æ€§æ„Ÿ|æƒ³çœ‹ä½ )/gu,
  },
  {
    id: "threat_english",
    category: "threat",
    severity: "critical",
    type: "regex",
    pattern: /\b(i(?:'| wi)?ll (hurt|kill|beat) you|go die|i(?:'m| am) going to hurt you|watch your back|i will find you)\b/giu,
  },
  {
    id: "threat_thai",
    category: "threat",
    severity: "critical",
    type: "regex",
    pattern: /(à¹„à¸›à¸•à¸²à¸¢|à¸à¸¹à¸ˆà¸°à¸—à¸³à¸£à¹‰à¸²à¸¢à¸¡à¸¶à¸‡|à¸ˆà¸°à¸•à¸šà¹à¸•à¸|à¸ˆà¸°à¸†à¹ˆà¸²à¸¡à¸¶à¸‡)/gu,
  },
  {
    id: "threat_chinese",
    category: "threat",
    severity: "critical",
    type: "regex",
    pattern: /(åŽ»æ­»|æˆ‘è¦æ‰“ä½ |æˆ‘è¦æ€äº†ä½ |æˆ‘ä¼šä¼¤å®³ä½ )/gu,
  },
  {
    id: "threat_unicode_thai_chinese",
    category: "threat",
    severity: "critical",
    type: "regex",
    pattern: /(\u0E44\u0E1B\u0E15\u0E32\u0E22|\u0E08\u0E30\u0E06\u0E48\u0E32|\u53BB\u6B7B|\u6211\u8981\u6253\u4F60|\u6211\u8981\u6740\u4E86\u4F60)/gu,
  },
  {
    id: "scam_transfer_phrases",
    category: "scam_risk",
    severity: "high",
    type: "regex",
    pattern: /\b(transfer (the )?money|pay (me|outside the app)|deposit first|send promptpay|bank transfer only|crypto only)\b|à¹‚à¸­à¸™à¸¡à¸²à¸à¹ˆà¸­à¸™|à¹‚à¸­à¸™à¹€à¸‡à¸´à¸™à¸¡à¸²à¸à¹ˆà¸­à¸™|à¸ˆà¹ˆà¸²à¸¢à¸™à¸­à¸à¹à¸­à¸›|à¸¡à¸±à¸”à¸ˆà¸³à¸à¹ˆà¸­à¸™/giu,
  },
  {
    id: "scam_suspicious_links",
    category: "scam_risk",
    severity: "medium",
    type: "regex",
    pattern: /\b(https?:\/\/|www\.|bit\.ly|tinyurl\.com|t\.me\/|lin\.ee\/|line\.me\/|wa\.me\/|wechat\.com|weixin)\S*/giu,
  },
  {
    id: "scam_click_link_evaluate_bait",
    category: "scam_risk",
    severity: "high",
    type: "regex",
    pattern: /\b(click|open|tap)\b.{0,12}\b(link|url|site|website)\b.{0,48}\b(n?evaluate|review|check|verify)\b|\b(n?evaluate|review|check|verify)\b.{0,32}\b(project|account|website|site|performance)\b.{0,24}\b(link|url)\b/giu,
  },
  {
    id: "scam_off_platform_contact",
    category: "scam_risk",
    severity: "medium",
    type: "regex",
    pattern: /\b(add|dm|contact|message|text)\s+(me\s+)?(on\s+)?(line|telegram|wechat|weixin)\b|à¹à¸­à¸”à¹„à¸¥à¸™à¹Œ|à¸—à¸±à¸à¹„à¸¥à¸™à¹Œ|à¸„à¸¸à¸¢à¹ƒà¸™à¹„à¸¥à¸™à¹Œ|à¹à¸­à¸”à¹„à¸­à¸”à¸µà¹„à¸¥à¸™à¹Œ|åŠ æˆ‘å¾®ä¿¡|åŠ ç”µæŠ¥/giu,
    allowlist: [/\b(finish line|line up|line break)\b/giu],
  },
  {
    id: "scam_phone_bait",
    category: "scam_risk",
    severity: "medium",
    type: "regex",
    pattern: /\b(line id|telegram id|wechat id|phone number|call me|whatsapp)\b|à¹€à¸šà¸­à¸£à¹Œà¹‚à¸—à¸£|à¹„à¸­à¸”à¸µà¹„à¸¥à¸™à¹Œ|à¹€à¸šà¸­à¸£à¹Œà¸•à¸´à¸”à¸•à¹ˆà¸­|å¾®ä¿¡å·/giu,
  },
  {
    id: "scam_phone_number",
    category: "scam_risk",
    severity: "low",
    type: "regex",
    pattern: /(?:\+?\d[\d\s-]{7,}\d)/gu,
  },
  {
    id: "scam_identity_document_bait",
    category: "scam_risk",
    severity: "high",
    type: "regex",
    pattern: /\b(send|share|give)\s+(me\s+)?((your|ur|u)\s+)?(passport|passport pic|passport photo|id card|driving license|driver'?s license)\b|\bcan\s+i\s+have\s+((your|ur|u)\s+)?(passport|passport pic|passport photo|id card|driving license|driver'?s license)\b/giu,
  },
  {
    id: "scam_personal_data",
    category: "scam_risk",
    severity: "high",
    type: "regex",
    pattern: /\b(send (me )?(your )?(passport|id card|bank account|otp|verification code|credit card|card number)|share (your )?(passport|id card|bank account|otp|verification code))\b|à¸‚à¸­à¸ªà¸³à¹€à¸™à¸²à¸šà¸±à¸•à¸£|à¸‚à¸­à¹€à¸¥à¸‚à¸šà¸±à¸à¸Šà¸µ|à¸‚à¸­à¸£à¸«à¸±à¸ª otp|èº«ä»½è¯|é“¶è¡Œè´¦å·|éªŒè¯ç /giu,
  },
];

function getSeverityScore(severity) {
  return SEVERITY_SCORES[severity] ?? 0;
}

function hasAllowlistMatch(text, allowlist = []) {
  return allowlist.some((pattern) => {
    pattern.lastIndex = 0;
    return pattern.test(text);
  });
}

function evaluateRule(text, rule) {
  if (hasAllowlistMatch(text, rule.allowlist)) return [];

  if (rule.type === "keyword") {
    return rule.values
      .filter((value) => text.includes(value))
      .map((value) => ({
        rule_id: rule.id,
        category: rule.category,
        severity: rule.severity,
        severity_score: getSeverityScore(rule.severity),
        match_type: "keyword",
        matched_value: value,
      }));
  }

  if (rule.type === "regex") {
    rule.pattern.lastIndex = 0;
    const matches = [...text.matchAll(rule.pattern)];
    return matches.map((match) => ({
      rule_id: rule.id,
      category: rule.category,
      severity: rule.severity,
      severity_score: getSeverityScore(rule.severity),
      match_type: "regex",
      matched_value: match[0],
    }));
  }

  return [];
}

function getHighestSeverityLabel(hits) {
  let best = "none";
  let bestScore = 0;
  for (const hit of hits) {
    const score = hit.severity_score ?? getSeverityScore(hit.severity);
    if (score > bestScore) {
      bestScore = score;
      best = hit.severity;
    }
  }
  return best;
}

function analyzeRuleBasedModeration(normalizedText) {
  const hits = uniqueHits([
    ...RULES.flatMap((rule) => evaluateRule(normalizedText, rule)),
    ...detectRuleHits(normalizedText),
  ]);
  const directCategories = new Set();
  const categoryScores = {};

  for (const hit of hits) {
    const nextScore = Math.max(categoryScores[hit.category] ?? 0, hit.severity_score);
    categoryScores[hit.category] = nextScore;
    if (hit.category !== "scam_risk") {
      directCategories.add(hit.category);
    }
  }

  const scamHits = hits.filter((hit) => hit.category === "scam_risk");
  const strongScamSignal = scamHits.some((hit) => hit.severity_score >= SEVERITY_SCORES.high);
  const combinedScamSignals = new Set(scamHits.map((hit) => hit.rule_id)).size >= 2;
  const hasFinalScamRisk = strongScamSignal || combinedScamSignals;
  if (hasFinalScamRisk) {
    directCategories.add("scam_risk");
  }

  const needsAiReview =
    !hasFinalScamRisk &&
    (
      scamHits.length > 0 ||
      directCategories.has("profanity") ||
      directCategories.has("sexual_ambiguous")
    );
  const aiReasons = [];
  if (!hasFinalScamRisk && scamHits.length > 0) {
    aiReasons.push("ambiguous_scam_signal");
  }
  if (directCategories.has("profanity")) {
    aiReasons.push("profanity_context_check");
  }
  if (directCategories.has("sexual_ambiguous")) {
    aiReasons.push("sexual_context_check");
  }

  return {
    hits,
    categories: Array.from(directCategories),
    category_scores: categoryScores,
    severity: getHighestSeverityLabel(hits),
    needs_ai_review: needsAiReview,
    ai_reasons: aiReasons,
  };
}

function buildRuleHit(label, category, severity, matchedValue, description) {
  return {
    label,
    rule_id: label,
    category,
    severity,
    severity_score: getSeverityScore(severity),
    match_type: "custom_rule",
    matched_value: matchedValue,
    description,
  };
}

function uniqueHits(hits) {
  const seen = new Set();
  return hits.filter((hit) => {
    const key = [
      hit.label,
      hit.category,
      hit.severity,
      String(hit.matched_value ?? "").trim(),
    ].join("|");
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function hasPhrase(text, phrase) {
  return text.includes(phrase);
}

function hasWord(text, word) {
  return new RegExp(`\\b${word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "u").test(text);
}

function detectRuleHits(normalizedText) {
  const text = String(normalizedText ?? "").trim().toLowerCase();
  if (!text) return [];

  const hits = [];
  const profanityWords = [
    "fuck",
    "bitch",
    "shit",
    "asshole",
    "motherfucker",
    "bastard",
  ];
  const hasQrCode = hasPhrase(text, "qr code");
  const hasScan = hasWord(text, "scan");
  const hasVerify = hasWord(text, "verify") || hasWord(text, "verification");
  const hasEvaluate = hasWord(text, "evaluate");
  const hasPerformance = hasWord(text, "performance");

  for (const word of profanityWords) {
    if (!hasWord(text, word)) continue;
    hits.push(
      buildRuleHit(
        `profanity_${word}`,
        "profanity",
        "medium",
        word,
        "Direct profanity should be censored in chat."
      )
    );
  }

  if (hasQrCode && hasScan) {
    hits.push(
      buildRuleHit(
        "scam_qr_scan",
        "scam_risk",
        "medium",
        "qr code + scan",
        "QR scan request can indicate scam or social engineering."
      )
    );
  }
  if (hasQrCode && hasVerify) {
    hits.push(
      buildRuleHit(
        "scam_qr_verify",
        "scam_risk",
        "medium",
        "qr code + verify",
        "QR verification phrasing can indicate account takeover bait."
      )
    );
  }
  if (hasQrCode && hasEvaluate) {
    hits.push(
      buildRuleHit(
        "scam_qr_evaluate",
        "scam_risk",
        "medium",
        "qr code + evaluate",
        "QR evaluation phrasing can indicate scam bait."
      )
    );
  }
  if (hasQrCode && hasPerformance) {
    hits.push(
      buildRuleHit(
        "scam_qr_performance",
        "scam_risk",
        "medium",
        "qr code + performance",
        "QR performance-check phrasing can indicate social engineering."
      )
    );
  }

  if (hasWord(text, "click") && hasWord(text, "link")) {
    hits.push(
      buildRuleHit(
        "scam_click_link",
        "scam_risk",
        "high",
        "click + link",
        "Requests to click external links are risky in chat."
      )
    );
  }

  if (/\b(line|telegram|whatsapp)\b/u.test(text)) {
    const match = text.match(/\b(line|telegram|whatsapp)\b/u);
    hits.push(
      buildRuleHit(
        "move_off_platform_contact",
        "scam_risk",
        "medium",
        match?.[0] ?? "off-platform contact",
        "Moving users off-platform is a scam/social-engineering risk."
      )
    );
  }
  if (hasPhrase(text, "dm me")) {
    hits.push(
      buildRuleHit(
        "move_off_platform_dm_me",
        "scam_risk",
        "medium",
        "dm me",
        "Direct-message bait can be used to avoid platform moderation."
      )
    );
  }
  if (hasPhrase(text, "direct message me")) {
    hits.push(
      buildRuleHit(
        "move_off_platform_direct_message_me",
        "scam_risk",
        "medium",
        "direct message me",
        "Requests to move to direct messages can indicate risky behavior."
      )
    );
  }

  if (hasWord(text, "transfer")) {
    hits.push(
      buildRuleHit(
        "payment_transfer",
        "scam_risk",
        "high",
        "transfer",
        "Transfer requests are a common payment-risk signal."
      )
    );
  }
  if (hasPhrase(text, "pay first")) {
    hits.push(
      buildRuleHit(
        "payment_pay_first",
        "scam_risk",
        "high",
        "pay first",
        "Pay-first instructions are a common scam signal."
      )
    );
  }
  if (hasPhrase(text, "send money")) {
    hits.push(
      buildRuleHit(
        "payment_send_money",
        "scam_risk",
        "high",
        "send money",
        "Send-money instructions are a strong payment-risk signal."
      )
    );
  }
  if (hasPhrase(text, "deposit first")) {
    hits.push(
      buildRuleHit(
        "payment_deposit_first",
        "scam_risk",
        "high",
        "deposit first",
        "Deposit-first instructions are a strong scam signal."
      )
    );
  }

  if (hasWord(text, "verify") && hasWord(text, "account")) {
    hits.push(
      buildRuleHit(
        "persuasion_account_verification",
        "scam_risk",
        "medium",
        "verify account",
        "Account verification bait can indicate phishing or takeover attempts."
      )
    );
  }
  if (hasWord(text, "performance") && (hasWord(text, "check") || hasWord(text, "evaluate"))) {
    hits.push(
      buildRuleHit(
        "persuasion_performance_check",
        "scam_risk",
        "medium",
        "performance check",
        "Performance-check bait is a known social-engineering pattern."
      )
    );
  }
  if ((hasWord(text, "claim") || hasWord(text, "redeem")) && hasWord(text, "reward")) {
    hits.push(
      buildRuleHit(
        "persuasion_reward_claim",
        "scam_risk",
        "medium",
        "claim reward",
        "Reward-claim phrasing often appears in scam messages."
      )
    );
  }

  if (hasPhrase(text, "fuck you") || hasPhrase(text, "shut the fuck up")) {
    hits.push(
      buildRuleHit(
        "profanity_directed_phrase",
        "profanity",
        "medium",
        hasPhrase(text, "fuck you") ? "fuck you" : "shut the fuck up",
        "Directed profanity should be censored in chat."
      )
    );
  }
  if (/\b(i will hurt you|go die|watch your back)\b/u.test(text)) {
    const match = text.match(/\b(i will hurt you|go die|watch your back)\b/u);
    hits.push(
      buildRuleHit(
        "abuse_threat_phrase",
        "threat",
        "critical",
        match?.[0] ?? "threat",
        "Threatening language is not allowed."
      )
    );
  }

  return uniqueHits(hits);
}

module.exports = {
  RULES,
  SEVERITY_SCORES,
  analyzeRuleBasedModeration,
  detectRuleHits,
  getSeverityScore,
};

