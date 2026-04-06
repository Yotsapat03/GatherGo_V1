require("dotenv").config();

const { analyzeSpotChatMessage } = require("./moderation/analyze.js");

const TEST_CASES = [
  {
    id: "allow_basic_coordination",
    text: "Meet at the park at 6 am for a recovery run",
    expectedDecisionAction: "allow",
    expectedPreflightAction: "allow",
    expectedCategories: [],
  },
  {
    id: "warn_non_hateful_profanity",
    text: "f u c k this pace",
    expectedDecisionAction: "censor_and_warn",
    expectedPreflightAction: "warn",
    expectedCategories: ["profanity"],
  },
  {
    id: "block_hate_slur",
    text: "pajeet",
    expectedDecisionAction: "block_and_report",
    expectedPreflightAction: "block",
    expectedCategories: ["hate_speech"],
  },
  {
    id: "block_hate_slur_jap",
    text: "jap",
    expectedDecisionAction: "block_and_report",
    expectedPreflightAction: "block",
    expectedCategories: ["hate_speech"],
  },
  {
    id: "block_obfuscated_slur",
    text: "n i g g a get out",
    expectedDecisionAction: "block_and_report",
    expectedPreflightAction: "block",
    expectedCategories: ["hate_speech"],
  },
  {
    id: "block_mixed_language_thai_abuse",
    text: "E dok tong",
    expectedDecisionAction: "block_and_report",
    expectedPreflightAction: "block",
    expectedCategories: ["targeted_abuse"],
  },
  {
    id: "review_quoted_evidence",
    text: 'user reported: "i hate all muslims"',
    expectedDecisionAction: "allow",
    expectedPreflightAction: "review",
    expectedCategories: [],
    expectNeedsHumanReview: true,
  },
  {
    id: "review_body_shaming",
    text: "you are so fat and ugly",
    expectedDecisionAction: "allow",
    expectedPreflightAction: "review",
    expectedCategories: [],
    expectNeedsHumanReview: true,
  },
  {
    id: "block_sexual_obfuscation",
    text: "P_Ssy",
    expectedDecisionAction: "block_and_flag",
    expectedPreflightAction: "block",
    expectedCategories: ["sexual_ambiguous"],
  },
];

function mapPreflightAction(result) {
  if (result?.decision?.action === "allow" && result?.needs_human_review === true) {
    return "review";
  }
  if (result?.decision?.action === "allow") return "allow";
  if (result?.decision?.action === "censor_and_warn") return "warn";
  return "block";
}

function hasExpectedCategories(actualCategories, expectedCategories) {
  return expectedCategories.every((category) => actualCategories.includes(category));
}

async function runCase(testCase) {
  const result = await analyzeSpotChatMessage(testCase.text);
  const actualDecisionAction = result?.decision?.action ?? "unknown";
  const actualPreflightAction = mapPreflightAction(result);
  const actualCategories = Array.isArray(result?.categories) ? result.categories : [];
  const actualNeedsHumanReview = result?.needs_human_review === true;
  const passed =
    actualDecisionAction === testCase.expectedDecisionAction &&
    actualPreflightAction === testCase.expectedPreflightAction &&
    hasExpectedCategories(actualCategories, testCase.expectedCategories) &&
    (testCase.expectNeedsHumanReview == null ||
      actualNeedsHumanReview === testCase.expectNeedsHumanReview);

  return {
    ...testCase,
    passed,
    actualDecisionAction,
    actualPreflightAction,
    actualCategories,
    actualNeedsHumanReview,
    safetyAction: result?.safety?.action ?? null,
    normalized: result?.normalized_message ?? "",
  };
}

async function main() {
  const results = [];
  for (const testCase of TEST_CASES) {
    results.push(await runCase(testCase));
  }

  const failed = results.filter((result) => !result.passed);
  for (const result of results) {
    console.log(
      `[${result.passed ? "PASS" : "FAIL"}] ${result.id} decision=${result.actualDecisionAction} preflight=${result.actualPreflightAction} categories=${result.actualCategories.join(",") || "-"} review=${result.actualNeedsHumanReview}`
    );

    if (!result.passed) {
      console.log(`  text=${JSON.stringify(result.text)}`);
      console.log(`  normalized=${JSON.stringify(result.normalized)}`);
      console.log(`  expected_decision=${result.expectedDecisionAction}`);
      console.log(`  expected_preflight=${result.expectedPreflightAction}`);
      console.log(`  expected_categories=${result.expectedCategories.join(",") || "-"}`);
      console.log(`  safety_action=${result.safetyAction}`);
    }
  }

  console.log(`Summary: ${results.length - failed.length}/${results.length} passed`);
  if (failed.length > 0) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error("chat-moderation-regression-runner failed:", error?.message ?? error);
  process.exitCode = 1;
});
