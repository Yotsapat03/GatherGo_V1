const PROTECTED_CLASSES = {
  race: ["black", "white", "asian", "latino", "arab", "jewish", "indian"],
  ethnicity: ["ethnic", "immigrant", "tribe", "minority"],
  nationality: ["american", "chinese", "russian", "thai", "burmese", "japanese"],
  religion: ["muslim", "christian", "jew", "hindu", "buddhist", "atheist"],
  sex_gender: ["woman", "women", "man", "men", "female", "male", "trans", "transgender", "ladyboy"],
  sexual_orientation: ["gay", "lesbian", "bi", "bisexual", "queer"],
  disability: ["disabled", "autistic", "retarded", "blind", "deaf", "wheelchair"],
};

const PROTECTED_CLASS_LOOKUP = Object.entries(PROTECTED_CLASSES).flatMap(([group, terms]) =>
  terms.map((term) => ({ term, group }))
);

const TARGETING_TERMS = [
  "you",
  "your",
  "those",
  "these",
  "people",
  "they",
  "them",
];

const REPORTING_MARKERS = [
  "reported",
  "reporting",
  "report",
  "mod",
  "moderation",
  "admin review",
  "evidence",
  "screenshot",
  "quoted",
];

const EDUCATIONAL_MARKERS = [
  "history",
  "historical",
  "academic",
  "research",
  "discussion",
  "policy",
  "training",
  "example",
];

const QUOTE_MARKERS = ['"', "'", "`"];

const RECLAIMING_MARKERS = [
  "i am",
  "i'm",
  "we are",
  "we're",
  "as a",
];

const HARSH_INSULTS = [
  "filthy",
  "disgusting",
  "gross",
  "trash",
  "vermin",
  "animal",
  "parasite",
  "subhuman",
];

const BODY_TRAIT_TERMS = [
  "fat",
  "ugly",
  "skinny",
  "short",
  "bald",
  "wrinkled",
  "disgusting face",
  "big nose",
  "whale",
  "pig",
];

const EXCLUSIONARY_PATTERNS = [
  /\b(don't want|do not want|keep|kick|ban|remove)\b.{0,24}\b(out|away|them|those people)\b/iu,
  /\b(should not be here|do not belong|aren't welcome|not welcome)\b/iu,
];

const VIOLENCE_PATTERNS = [
  /\b(kill|beat|shoot|burn|lynch|hurt|attack)\b/iu,
  /\b(go die|wipe out|exterminate)\b/iu,
];

const DIRECT_HATE_PATTERNS = [
  /\b(i hate|we hate|hate all)\b/iu,
  /\b(all)\b.{0,12}\b(are|should be)\b.{0,20}\b(trash|animals|filthy|disgusting)\b/iu,
];

const XENOPHOBIC_STEREOTYPE_PATTERNS = [
  /\byour country\b.{0,24}\beat\s+(cat|cats|dog|dogs|meow|meaw)\b/iu,
  /\b(go back to your country)\b/iu,
  /\b(ladyboy country|country of ladyboys)\b/iu,
];

const CONTROLLED_SLUR_PATTERNS = [
  { id: "controlled_racial_slur_n_word", pattern: /\bn[i1!]?gg(?:er|a)\b/iu, protected_class: "race" },
  { id: "controlled_nationality_slur_jap", pattern: /\bjap\b/iu, protected_class: "nationality" },
  { id: "controlled_ethnic_slur_kike", pattern: /\bkike\b/iu, protected_class: "religion" },
  { id: "controlled_ethnic_slur_spic", pattern: /\bspic\b/iu, protected_class: "ethnicity" },
  { id: "controlled_ethnic_slur_pajeet", pattern: /\bpajeet\b/iu, protected_class: "nationality" },
  { id: "controlled_gender_slur_tranny", pattern: /\btranny\b/iu, protected_class: "sex_gender" },
  { id: "controlled_gender_slur_ladyboy", pattern: /\bladyboy(s)?\b/iu, protected_class: "sex_gender" },
];

function getProtectedReferences(text) {
  const refs = [];
  for (const entry of PROTECTED_CLASS_LOOKUP) {
    const pattern = new RegExp(
      `\\b${entry.term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?:s)?\\b`,
      "iu"
    );
    if (pattern.test(text)) {
      refs.push(entry);
    }
  }
  return refs;
}

function inferContext(text) {
  const lower = text.toLowerCase();
  const containsQuote = QUOTE_MARKERS.some((marker) => lower.includes(marker));
  const isReporting = REPORTING_MARKERS.some((marker) => lower.includes(marker));
  const isEducational = EDUCATIONAL_MARKERS.some((marker) => lower.includes(marker));
  const isReclaimed = RECLAIMING_MARKERS.some((marker) => lower.includes(marker));

  return {
    contains_quote: containsQuote,
    is_reporting: isReporting,
    is_educational: isEducational,
    is_reclaimed: isReclaimed,
  };
}

function matchControlledSlurs(text) {
  const matches = [];
  for (const entry of CONTROLLED_SLUR_PATTERNS) {
    const found = text.match(entry.pattern);
    if (found) {
      matches.push({
        id: entry.id,
        category: "hate_speech",
        protected_class: entry.protected_class,
        severity: "high",
        matched_text: found[0],
        rationale: "Matched a controlled slur pattern.",
      });
    }
  }
  return matches;
}

function matchTargetedProtectedAttacks(text, protectedRefs) {
  const matches = [];
  if (protectedRefs.length === 0) {
    return matches;
  }

  const hasTargeting = TARGETING_TERMS.some((term) => new RegExp(`\\b${term}\\b`, "iu").test(text));
  const hasHarshInsult = HARSH_INSULTS.some((term) => new RegExp(`\\b${term}\\b`, "iu").test(text));
  const hasDirectHate = DIRECT_HATE_PATTERNS.some((pattern) => pattern.test(text));
  const hasExclusion = EXCLUSIONARY_PATTERNS.some((pattern) => pattern.test(text));
  const hasViolence = VIOLENCE_PATTERNS.some((pattern) => pattern.test(text));

  for (const ref of protectedRefs) {
    const generalizedInsultPattern = new RegExp(
      `\\b(?:all\\s+)?${ref.term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?:s)?\\b.{0,16}\\b(?:are|is|should be)\\b.{0,18}\\b(trash|worthless|animals|filthy|disgusting|subhuman|parasites?)\\b`,
      "iu"
    );
    const exclusionPattern = new RegExp(
      `\\b(?:all\\s+)?${ref.term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}(?:s)?\\b.{0,18}\\b(should be banned|do not belong|not welcome|should leave|get out)\\b`,
      "iu"
    );

    if (hasViolence) {
      matches.push({
        id: `violent_attack:${ref.term}`,
        category: "threat",
        protected_class: ref.group,
        severity: "critical",
        matched_text: ref.term,
        rationale: "Detected violent language near a protected-class reference.",
      });
    }

    if (hasDirectHate || (hasHarshInsult && hasTargeting)) {
      matches.push({
        id: `hate_attack:${ref.term}`,
        category: "protected_class_attack",
        protected_class: ref.group,
        severity: hasDirectHate ? "high" : "medium",
        matched_text: ref.term,
        rationale: "Detected insulting or hateful language directed at a protected class.",
      });
    }

    if (generalizedInsultPattern.test(text)) {
      matches.push({
        id: `group_generalization:${ref.term}`,
        category: "protected_class_attack",
        protected_class: ref.group,
        severity: "high",
        matched_text: ref.term,
        rationale: "Detected generalized insulting language about a protected class.",
      });
    }

    if (hasExclusion || exclusionPattern.test(text)) {
      matches.push({
        id: `exclusionary_attack:${ref.term}`,
        category: "dehumanization",
        protected_class: ref.group,
        severity: "high",
        matched_text: ref.term,
        rationale: "Detected exclusionary language aimed at a protected class.",
      });
    }
  }

  return matches;
}

function matchTargetedAbuse(text) {
  const abusivePattern =
    /\b(you are|you're|you|your)\b.{0,18}\b(idiot|moron|loser|trash|stupid|worthless)\b/iu;
  const matched = text.match(abusivePattern);
  const matches = [];

  if (matched) {
    matches.push({
      id: "targeted_abuse_basic",
      category: "targeted_abuse",
      protected_class: null,
      severity: "medium",
      matched_text: matched[0],
      rationale: "Detected targeted abusive insult aimed at a person.",
    });
  }

  const bodyShamingPattern =
    /\b(you are|you're|your|look at you|so)\b.{0,20}\b(fat|ugly|skinny|short|bald|whale|pig)\b/iu;
  const bodyShamingMatch = text.match(bodyShamingPattern);
  if (bodyShamingMatch) {
    matches.push({
      id: "targeted_body_shaming",
      category: "targeted_abuse",
      protected_class: null,
      severity: "medium",
      matched_text: bodyShamingMatch[0],
      rationale: "Detected targeted body-shaming language aimed at a person.",
    });
  }

  const generalizedBodyShamingPattern =
    /\b(that|this|such a)\b.{0,12}\b(whale|pig|ugly face|disgusting face|big nose)\b/iu;
  const generalizedBodyShamingMatch = text.match(generalizedBodyShamingPattern);
  if (generalizedBodyShamingMatch) {
    matches.push({
      id: "generalized_body_shaming",
      category: "harassment",
      protected_class: null,
      severity: "medium",
      matched_text: generalizedBodyShamingMatch[0],
      rationale: "Detected harassing body-shaming language.",
    });
  }

  return matches;
}

function matchXenophobicStereotypes(text) {
  const matches = [];

  for (const pattern of XENOPHOBIC_STEREOTYPE_PATTERNS) {
    const matched = text.match(pattern);
    if (!matched) continue;
    matches.push({
      id: "xenophobic_stereotype",
      category: "protected_class_attack",
      protected_class: "nationality",
      severity: "high",
      matched_text: matched[0],
      rationale:
        "Detected xenophobic nationality stereotype or exclusionary country-based attack.",
    });
  }

  return matches;
}

function matchNonProtectedHarassment(text) {
  const matched = text.match(/\b(shut up|go away|leave me alone|creep|pervert)\b/iu);
  const matches = [];
  if (matched) {
    matches.push({
      id: "harassment_basic",
      category: "harassment",
      protected_class: null,
      severity: "medium",
      matched_text: matched[0],
      rationale: "Detected hostile harassment without protected-class language.",
    });
  }

  const bodyTraitPattern = new RegExp(`\\b(${BODY_TRAIT_TERMS.map((term) => term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join("|")})\\b`, "iu");
  const bodyTraitMatch = text.match(bodyTraitPattern);
  if (bodyTraitMatch && /\b(look|body|face|nose|hair|weight|size)\b/iu.test(text)) {
    matches.push({
      id: "harassment_body_trait",
      category: "harassment",
      protected_class: null,
      severity: "medium",
      matched_text: bodyTraitMatch[0],
      rationale: "Detected body-focused harassment.",
    });
  }

  return matches;
}

function matchContextualProtectedDiscussion(text, protectedRefs, context) {
  if (!protectedRefs.length) return [];
  if (!context.is_reporting && !context.is_educational && !context.contains_quote) {
    return [];
  }

  return protectedRefs.map((ref) => ({
    id: `contextual_protected_discussion:${ref.term}`,
    category: "protected_class_attack",
    protected_class: ref.group,
    severity: "medium",
    matched_text: ref.term,
    rationale: "Detected protected-class reference inside a discussion, report, or quoted evidence context.",
  }));
}

function analyzeRules(normalized) {
  const text = normalized.normalized_text;
  const protectedRefs = getProtectedReferences(text);
  const context = inferContext(text);

  const matched_rules = [
    ...matchControlledSlurs(text),
    ...matchTargetedProtectedAttacks(text, protectedRefs),
    ...matchXenophobicStereotypes(text),
    ...matchTargetedAbuse(text),
    ...matchNonProtectedHarassment(text),
    ...matchContextualProtectedDiscussion(text, protectedRefs, context),
  ];

  return {
    context,
    protected_references: protectedRefs,
    matched_rules,
  };
}

module.exports = {
  PROTECTED_CLASSES,
  analyzeRules,
  inferContext,
};
