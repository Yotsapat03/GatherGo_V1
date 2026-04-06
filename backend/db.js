// db.cjs
const { Pool } = require("pg");

// ✅ ใช้ DATABASE_URL เป็นหลัก (เหมาะกับ deploy)
// ✅ มี fallback สำหรับรันบนเครื่องตอน dev
const connectionString =
  process.env.DATABASE_URL ||
  "postgresql://postgres:YOUR_PASSWORD@localhost:5432/run_event_db2";

const pool = new Pool({ connectionString });

module.exports = { pool };