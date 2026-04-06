require("dotenv").config();

const { analyzeMessage } = require("./moderation/safety/analyzer.js");
const { TEST_CASES } = require("./moderation/safety/tests.js");

function includesAll(actual, expected) {
  return expected.every((item) => actual.includes(item));
}

async function main() {
  let passed = 0;

  for (const testCase of TEST_CASES) {
    const result = analyzeMessage(testCase.message, { test_case_id: testCase.id });
    const ok =
      result.action === testCase.expectedAction &&
      includesAll(result.categories, testCase.expectedCategories);

    if (ok) {
      passed += 1;
    }

    console.log(
      `[${ok ? "PASS" : "FAIL"}] ${testCase.id} expected=${testCase.expectedAction} actual=${result.action} categories=${result.categories.join(",")}`
    );

    if (!ok) {
      console.log(JSON.stringify(result, null, 2));
    }
  }

  console.log(`Summary: ${passed}/${TEST_CASES.length} passed`);
  if (passed !== TEST_CASES.length) {
    process.exitCode = 1;
  }
}

main().catch((error) => {
  console.error("moderation-safety-test-runner failed:", error?.message ?? error);
  process.exitCode = 1;
});
