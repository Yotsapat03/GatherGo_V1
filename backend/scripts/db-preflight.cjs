require("dotenv").config();

const { pool } = require("../db.js");

const REQUIRED_TABLES = [
  "users",
  "admin_users",
  "organizations",
  "events",
  "event_media",
  "bookings",
  "participants",
  "payments",
  "receipts",
  "spot_events",
  "spot_event_members",
  "spot_event_bookings",
  "chat_moderation_logs",
  "chat_moderation_queue",
  "audit_logs",
];

async function findMissingTables(tableNames) {
  const q = await pool.query(
    `
    SELECT tablename
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename = ANY($1::text[])
    `,
    [tableNames]
  );
  const existing = new Set(q.rows.map((row) => String(row.tablename)));
  return tableNames.filter((name) => !existing.has(name));
}

async function main() {
  const missingRequired = await findMissingTables(REQUIRED_TABLES);

  console.log("DB preflight");
  console.log(`- DATABASE_URL configured: ${Boolean(String(process.env.DATABASE_URL ?? "").trim())}`);
  console.log(`- Missing required tables: ${missingRequired.length}`);
  for (const name of missingRequired) {
    console.log(`  * ${name}`);
  }

  if (missingRequired.length > 0) {
    console.log("");
    console.log("Run `npm run db:migrate` before seeding demo data.");
    process.exitCode = 1;
    return;
  }
}

main()
  .catch((error) => {
    console.error("db-preflight failed:", error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
