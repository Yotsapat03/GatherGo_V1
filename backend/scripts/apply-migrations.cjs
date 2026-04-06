require("dotenv").config();

const fs = require("fs");
const path = require("path");
const { pool } = require("../db.js");

const MIGRATIONS_DIR = path.join(__dirname, "..", "migrations");

function compareMigrationNames(left, right) {
  const leftMatch = String(left).match(/^(\d+)_/);
  const rightMatch = String(right).match(/^(\d+)_/);
  const leftNumber = leftMatch ? Number(leftMatch[1]) : Number.MAX_SAFE_INTEGER;
  const rightNumber = rightMatch ? Number(rightMatch[1]) : Number.MAX_SAFE_INTEGER;
  if (leftNumber !== rightNumber) return leftNumber - rightNumber;
  return String(left).localeCompare(String(right));
}

async function ensureSchemaMigrationsTable() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS public.schema_migrations (
      id BIGSERIAL PRIMARY KEY,
      filename TEXT NOT NULL UNIQUE,
      applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

async function getAppliedMigrationSet() {
  const q = await pool.query(`SELECT filename FROM public.schema_migrations`);
  return new Set(q.rows.map((row) => String(row.filename)));
}

async function applyMigration(filename) {
  const fullPath = path.join(MIGRATIONS_DIR, filename);
  const sql = fs.readFileSync(fullPath, "utf8").trim();
  if (!sql) {
    console.log(`- skip empty migration: ${filename}`);
    return;
  }

  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    await client.query(sql);
    await client.query(
      `INSERT INTO public.schema_migrations (filename) VALUES ($1)`,
      [filename]
    );
    await client.query("COMMIT");
    console.log(`+ applied: ${filename}`);
  } catch (error) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {}
    throw new Error(`${filename}: ${error.message}`);
  } finally {
    client.release();
  }
}

async function main() {
  await ensureSchemaMigrationsTable();
  const applied = await getAppliedMigrationSet();
  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((name) => name.toLowerCase().endsWith(".sql"))
    .sort(compareMigrationNames);

  let appliedCount = 0;
  for (const filename of files) {
    if (applied.has(filename)) {
      console.log(`= already applied: ${filename}`);
      continue;
    }
    await applyMigration(filename);
    appliedCount += 1;
  }

  console.log(`Done. Newly applied migrations: ${appliedCount}`);
}

main()
  .catch((error) => {
    console.error("apply-migrations failed:", error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
