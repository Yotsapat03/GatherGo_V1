require("dotenv").config();

const { moderateText } = require("./moderation/openaiModeration.js");

async function main() {
  const result = await moderateText(
    "Scan this qr-code and pay first using this external link."
  );
  console.log(JSON.stringify(result, null, 2));
}

main().catch((error) => {
  console.error("test-moderation failed:", error?.message ?? error);
  process.exitCode = 1;
});
