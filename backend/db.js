const { Pool } = require("pg");

const connectionString = String(process.env.DATABASE_URL ?? "").trim();

if (!connectionString) {
  throw new Error(
    "DATABASE_URL is required. Copy backend/.env.example to backend/.env and set DATABASE_URL before starting the backend."
  );
}

const pool = new Pool({ connectionString });

module.exports = { pool };
