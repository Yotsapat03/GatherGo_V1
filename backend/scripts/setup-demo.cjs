require("dotenv").config();

const path = require("path");
const { spawn } = require("child_process");

const scripts = [
  { name: "db:migrate", file: "apply-migrations.cjs" },
  { name: "db:preflight", file: "db-preflight.cjs" },
  { name: "db:seed-demo", file: "seed-demo.cjs" },
];

function runScript(step) {
  return new Promise((resolve, reject) => {
    const scriptPath = path.join(__dirname, step.file);
    const child = spawn(process.execPath, [scriptPath], {
      stdio: "inherit",
      env: process.env,
    });

    child.on("error", reject);
    child.on("exit", (code) => {
      if (code === 0) {
        resolve();
        return;
      }
      reject(new Error(`${step.name} failed with exit code ${code}`));
    });
  });
}

async function main() {
  console.log("Starting GatherGo demo setup");
  for (const step of scripts) {
    console.log(`\n==> Running ${step.name}`);
    await runScript(step);
  }
  console.log("\nGatherGo demo setup complete");
}

main().catch((error) => {
  console.error("setup-demo failed:", error.message);
  process.exitCode = 1;
});
