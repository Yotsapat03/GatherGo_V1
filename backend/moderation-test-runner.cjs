require("dotenv").config();

const { analyzeSpotChatMessage } = require("./moderation/analyze.js");

function thai(text) {
  return text;
}

const TEST_CASES = [
  {
    id: "th_allow_basic",
    language: "th",
    text: thai("\u0E40\u0E08\u0E2D\u0E01\u0E31\u0E19\u0E15\u0E35\u0E2B\u0E49\u0E32\u0E17\u0E35\u0E48\u0E2A\u0E27\u0E19\u0E25\u0E38\u0E21 \u0E27\u0E34\u0E48\u0E07 easy 5k"),
    expectedAction: "allow",
    expectedCategories: [],
  },
  {
    id: "th_warn_spaced_profanity",
    language: "th",
    text: thai("\u0E04 \u0E27 \u0E22"),
    expectedAction: "warn",
    expectedCategories: ["profanity"],
  },
  {
    id: "th_warn_translit_profanity",
    language: "th",
    text: "kuay",
    expectedAction: "warn",
    expectedCategories: ["profanity"],
  },
  {
    id: "th_warn_translit_hee_spaced",
    language: "th",
    text: "h e e",
    expectedAction: "warn",
    expectedCategories: ["profanity"],
  },
  {
    id: "th_warn_translit_kee_spaced",
    language: "th",
    text: "k E E",
    expectedAction: "warn",
    expectedCategories: ["profanity"],
  },
  {
    id: "th_warn_mixedscript_hee",
    language: "th",
    text: "ห E e",
    expectedAction: "warn",
    expectedCategories: ["profanity"],
  },
  {
    id: "th_warn_mixedscript_kuay",
    language: "th",
    text: "ค u a y",
    expectedAction: "warn",
    expectedCategories: ["profanity"],
  },
  {
    id: "th_warn_translit_hia",
    language: "th",
    text: "h i a",
    expectedAction: "warn",
    expectedCategories: ["profanity"],
  },
  {
    id: "th_block_mixed_language_doktong",
    language: "th",
    text: "E dok tong",
    expectedAction: "block",
    expectedCategories: ["targeted_abuse"],
  },
  {
    id: "th_block_mixed_language_dokthong_spaced",
    language: "th",
    text: "ee d o k t h o n g",
    expectedAction: "block",
    expectedCategories: ["targeted_abuse"],
  },
  {
    id: "th_block_translit_yed",
    language: "th",
    text: "y e d",
    expectedAction: "block",
    expectedCategories: ["sexual_harassment"],
  },
  {
    id: "th_block_translit_ngian",
    language: "th",
    text: "n g i a n",
    expectedAction: "block",
    expectedCategories: ["sexual_ambiguous"],
  },
  {
    id: "th_block_spaced_sexual",
    language: "th",
    text: thai("\u0E40 \u0E22 \u0E47 \u0E14 \u0E01\u0E31\u0E19\u0E44\u0E2B\u0E21"),
    expectedAction: "block",
    expectedCategories: ["sexual_harassment"],
  },
  {
    id: "en_allow_basic",
    language: "en",
    text: "Meet at the park at 6 am for a recovery run",
    expectedAction: "allow",
    expectedCategories: [],
  },
  {
    id: "en_warn_obfuscated_profanity",
    language: "en",
    text: "f u c k this pace",
    expectedAction: "warn",
    expectedCategories: ["profanity"],
  },
  {
    id: "en_block_obfuscated_sexual",
    language: "en",
    text: "pu55y",
    expectedAction: "block",
    expectedCategories: ["sexual_ambiguous"],
  },
  {
    id: "en_block_dropped_letter_pssy",
    language: "en",
    text: "pssy",
    expectedAction: "block",
    expectedCategories: ["sexual_ambiguous"],
  },
  {
    id: "en_block_underscored_p_ssy",
    language: "en",
    text: "p_ssy",
    expectedAction: "block",
    expectedCategories: ["sexual_ambiguous"],
  },
  {
    id: "en_allow_boom_boom",
    language: "en",
    text: "Boom Boom",
    expectedAction: "allow",
    expectedCategories: [],
  },
  {
    id: "en_allow_bob_name",
    language: "en",
    text: "Bob",
    expectedAction: "allow",
    expectedCategories: [],
  },
  {
    id: "en_block_boob_single_word",
    language: "en",
    text: "Boob",
    expectedAction: "block",
    expectedCategories: ["sexual_ambiguous"],
  },
  {
    id: "en_block_slur_variant_nigga",
    language: "en",
    text: "nigga",
    expectedAction: "block",
    expectedCategories: ["hate_speech"],
  },
  {
    id: "en_block_slur_variant_niggre",
    language: "en",
    text: "niggre",
    expectedAction: "block",
    expectedCategories: ["hate_speech"],
  },
  {
    id: "en_block_self_harm_slang_kys",
    language: "en",
    text: "kys",
    expectedAction: "block",
    expectedCategories: ["threat"],
  },
  {
    id: "en_block_xenophobic_country_stereotype",
    language: "en",
    text: "your country eat meaw",
    expectedAction: "block",
    expectedCategories: ["hate_speech"],
  },
  {
    id: "en_block_transphobic_country_stereotype",
    language: "en",
    text: "ladyboy country",
    expectedAction: "block",
    expectedCategories: ["hate_speech"],
  },
  {
    id: "en_block_room_special_thing_bait",
    language: "en",
    text: "Can u go to my room we will have spacial thing together",
    expectedAction: "block",
    expectedCategories: ["sexual_harassment"],
  },
  {
    id: "en_block_click_link_evaluate_bait",
    language: "en",
    text: "Can u click this link to nevaluate my running projectb thank u so much",
    expectedAction: "block",
    expectedCategories: ["scam_risk"],
  },
  {
    id: "en_block_simple_click_link_bait",
    language: "en",
    text: "Can u send click this link",
    expectedAction: "block",
    expectedCategories: ["scam_risk"],
  },
  {
    id: "en_block_identity_card_bait",
    language: "en",
    text: "Send ur ID card for me",
    expectedAction: "block",
    expectedCategories: ["scam_risk"],
  },
  {
    id: "en_block_driving_license_bait",
    language: "en",
    text: "Send ur driving license",
    expectedAction: "block",
    expectedCategories: ["scam_risk"],
  },
  {
    id: "en_block_passport_pic_bait",
    language: "en",
    text: "Can I have ur passport pic",
    expectedAction: "block",
    expectedCategories: ["scam_risk"],
  },
  {
    id: "th_block_knowledge_slang_horny",
    language: "th",
    text: thai("\u0E40\u0E07\u0E35\u0E48\u0E22\u0E19"),
    expectedAction: "block",
    expectedCategories: ["sexual_ambiguous"],
  },
  {
    id: "th_block_knowledge_offplatform_payment_bait",
    language: "th",
    text: thai("\u0E17\u0E31\u0E01\u0E44\u0E25\u0E19\u0E4C\u0E21\u0E32 \u0E08\u0E48\u0E32\u0E22\u0E19\u0E2D\u0E01\u0E41\u0E2D\u0E1B"),
    expectedAction: "block",
    expectedCategories: ["scam_risk"],
  },
  {
    id: "zh_allow_basic",
    language: "zh",
    text: "\u660E\u5929\u65E9\u4E0A\u516D\u70B9\u4E00\u8D77\u8DD1\u6B65\uFF0C\u5728\u516C\u56ED\u95E8\u53E3\u89C1",
    expectedAction: "allow",
    expectedCategories: [],
  },
  {
    id: "zh_warn_translit_cao",
    language: "zh",
    text: "c a o",
    expectedAction: "warn",
    expectedCategories: ["profanity"],
  },
  {
    id: "zh_block_translit_qusi",
    language: "zh",
    text: "q u s i",
    expectedAction: "block",
    expectedCategories: ["threat"],
  },
  {
    id: "zh_block_translit_yuepao",
    language: "zh",
    text: "y u e p a o",
    expectedAction: "block",
    expectedCategories: ["sexual_harassment"],
  },
  {
    id: "zh_block_mixedscript_kaifang",
    language: "zh",
    text: "k a i 房",
    expectedAction: "block",
    expectedCategories: ["sexual_harassment"],
  },
  {
    id: "zh_block_sexual",
    language: "zh",
    text: "\u7EA6\u70AE",
    expectedAction: "block",
    expectedCategories: ["sexual_harassment"],
  },
  {
    id: "zh_block_threat",
    language: "zh",
    text: "\u53BB\u6B7B",
    expectedAction: "block",
    expectedCategories: ["threat"],
  },
];

function normalizeAction(decisionAction) {
  if (decisionAction === "allow") return "allow";
  if (decisionAction === "censor_and_warn") return "warn";
  return "block";
}

function hasExpectedCategories(actualCategories, expectedCategories) {
  return expectedCategories.every((category) => actualCategories.includes(category));
}

async function runCase(testCase) {
  const result = await analyzeSpotChatMessage(testCase.text);
  const actualAction = normalizeAction(result?.decision?.action);
  const actualCategories = Array.isArray(result?.categories) ? result.categories : [];
  const passed =
    actualAction === testCase.expectedAction &&
    hasExpectedCategories(actualCategories, testCase.expectedCategories);

  return {
    ...testCase,
    passed,
    actualAction,
    actualCategories,
    normalized: result?.normalized_message ?? "",
    decisionAction: result?.decision?.action ?? "unknown",
  };
}

async function main() {
  const results = [];
  for (const testCase of TEST_CASES) {
    results.push(await runCase(testCase));
  }

  const failed = results.filter((result) => !result.passed);
  for (const result of results) {
    const status = result.passed ? "PASS" : "FAIL";
    console.log(
      `[${status}] ${result.id} (${result.language}) expected=${result.expectedAction} actual=${result.actualAction} categories=${result.actualCategories.join(",") || "-"}`
    );
    if (!result.passed) {
      console.log(`  text=${JSON.stringify(result.text)}`);
      console.log(`  normalized=${JSON.stringify(result.normalized)}`);
      console.log(`  expected_categories=${result.expectedCategories.join(",") || "-"}`);
      console.log(`  decision_action=${result.decisionAction}`);
    }
  }

  console.log("");
  console.log(`Summary: ${results.length - failed.length}/${results.length} passed`);

  if (failed.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error("moderation-test-runner failed:", error?.message ?? error);
  process.exitCode = 1;
});
