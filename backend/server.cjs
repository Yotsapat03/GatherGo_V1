require("dotenv").config();

const express = require("express");
const cors = require("cors");
const bcrypt = require("bcryptjs");

const { pool } = require("./db.js");
const { analyzeSpotChatMessage } = require("./moderation/analyze.js");
const { scanSpotChatMessageUrls } = require("./phishing/scan.js");
const { syncPhishTankFeed } = require("./phishing/phishtank_sync.js");
const {
  detectVocabularyLanguage,
  ensureModerationVocabularySeed,
  normalizeVocabularyTerm,
} = require("./moderation/vocabulary.js");
const { normalizeModerationText } = require("./moderation/normalizer.js");

let _eventDistanceColumnsReadyPromise = null;
async function ensureEventDistanceColumns() {
  if (_eventDistanceColumnsReadyPromise) return _eventDistanceColumnsReadyPromise;

  _eventDistanceColumnsReadyPromise = (async () => {
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS distance_per_lap NUMERIC(12, 3)`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS number_of_laps INTEGER`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS total_distance NUMERIC(12, 3)`);
  })().catch((e) => {
    _eventDistanceColumnsReadyPromise = null;
    throw e;
  });

  return _eventDistanceColumnsReadyPromise;
}

let _eventLocationColumnsReadyPromise = null;
async function ensureEventLocationColumns() {
  if (_eventLocationColumnsReadyPromise) return _eventLocationColumnsReadyPromise;

  _eventLocationColumnsReadyPromise = (async () => {
    await pool.query(`ALTER TABLE public.events ADD COLUMN IF NOT EXISTS location_name TEXT`);
    await pool.query(`ALTER TABLE public.events ADD COLUMN IF NOT EXISTS location_lat DOUBLE PRECISION`);
    await pool.query(`ALTER TABLE public.events ADD COLUMN IF NOT EXISTS location_lng DOUBLE PRECISION`);
    await pool.query(`ALTER TABLE public.events ADD COLUMN IF NOT EXISTS location_link TEXT`);
    await pool.query(`ALTER TABLE public.events ADD COLUMN IF NOT EXISTS meeting_point_note TEXT`);
    await pool.query(`ALTER TABLE public.events ADD COLUMN IF NOT EXISTS district TEXT`);
  })().catch((e) => {
    _eventLocationColumnsReadyPromise = null;
    throw e;
  });

  return _eventLocationColumnsReadyPromise;
}

let _paymentSlipColumnReadyPromise = null;
async function ensurePaymentSlipColumn() {
  if (_paymentSlipColumnReadyPromise) return _paymentSlipColumnReadyPromise;

  _paymentSlipColumnReadyPromise = (async () => {
    await pool.query(`ALTER TABLE payments ADD COLUMN IF NOT EXISTS slip_url TEXT`);
  })().catch((e) => {
    _paymentSlipColumnReadyPromise = null;
    throw e;
  });

  return _paymentSlipColumnReadyPromise;
}

let _paymentSeparationColumnsReadyPromise = null;
async function ensurePaymentSeparationColumns() {
  if (_paymentSeparationColumnsReadyPromise) return _paymentSeparationColumnsReadyPromise;

  _paymentSeparationColumnsReadyPromise = (async () => {
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS payment_mode TEXT DEFAULT 'manual_qr'`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS manual_promptpay_qr_url TEXT`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS manual_alipay_qr_url TEXT`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS enable_promptpay BOOLEAN NOT NULL DEFAULT TRUE`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS enable_alipay BOOLEAN NOT NULL DEFAULT FALSE`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS stripe_enabled BOOLEAN NOT NULL DEFAULT FALSE`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS base_currency TEXT`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS base_amount NUMERIC(12, 2)`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS exchange_rate_thb_per_cny NUMERIC(12, 6)`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS promptpay_amount_thb NUMERIC(12, 2)`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS alipay_amount_cny NUMERIC(12, 2)`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS fx_locked_at TIMESTAMPTZ`);

    await pool.query(`ALTER TABLE payments ADD COLUMN IF NOT EXISTS payment_method_type TEXT`);
    await pool.query(`ALTER TABLE payments ADD COLUMN IF NOT EXISTS provider_payment_intent_id TEXT`);
    await pool.query(`ALTER TABLE payments ADD COLUMN IF NOT EXISTS provider_charge_id TEXT`);
    await pool.query(`ALTER TABLE payments ADD COLUMN IF NOT EXISTS raw_gateway_payload JSONB`);
    await pool.query(`ALTER TABLE payments ADD COLUMN IF NOT EXISTS currency TEXT`);
    await pool.query(`ALTER TABLE payments ADD COLUMN IF NOT EXISTS provider_txn_id TEXT`);
    await pool.query(`ALTER TABLE payments ADD COLUMN IF NOT EXISTS fx_rate_used NUMERIC(12, 6)`);
    await pool.query(`ALTER TABLE payments ADD COLUMN IF NOT EXISTS failure_code TEXT`);
    await pool.query(`ALTER TABLE payments ADD COLUMN IF NOT EXISTS failure_reason TEXT`);
    await pool.query(`
      CREATE TABLE IF NOT EXISTS airwallex_webhook_events (
        id BIGSERIAL PRIMARY KEY,
        airwallex_event_id TEXT NOT NULL UNIQUE,
        event_type TEXT NOT NULL,
        payload_json JSONB NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        processed_at TIMESTAMPTZ
      )
    `);
    await pool.query(`
      CREATE TABLE IF NOT EXISTS antom_webhook_events (
        id BIGSERIAL PRIMARY KEY,
        antom_notify_id TEXT NOT NULL UNIQUE,
        event_type TEXT NOT NULL,
        payload_json JSONB NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        processed_at TIMESTAMPTZ
      )
    `);
  })().catch((e) => {
    _paymentSeparationColumnsReadyPromise = null;
    throw e;
  });

  return _paymentSeparationColumnsReadyPromise;
}

let _userAuthColumnsReadyPromise = null;
async function ensureUserAuthColumns() {
  if (_userAuthColumnsReadyPromise) return _userAuthColumnsReadyPromise;

  _userAuthColumnsReadyPromise = (async () => {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.users (
        id BIGSERIAL PRIMARY KEY,
        name TEXT NOT NULL DEFAULT 'User',
        email TEXT NOT NULL,
        phone TEXT NOT NULL DEFAULT '-',
        address TEXT NOT NULL DEFAULT '-',
        address_house_no TEXT,
        address_floor TEXT,
        address_building TEXT,
        address_road TEXT,
        address_subdistrict TEXT,
        address_district TEXT,
        address_province TEXT,
        address_postal_code TEXT,
        birth_year INTEGER,
        gender TEXT,
        occupation TEXT,
        name_i18n JSONB,
        gender_i18n JSONB,
        occupation_i18n JSONB,
        address_i18n JSONB,
        password_hash TEXT NOT NULL,
        first_name TEXT,
        last_name TEXT,
        status TEXT NOT NULL DEFAULT 'active',
        role_id INTEGER,
        last_login_at TIMESTAMPTZ,
        profile_image_url TEXT,
        national_id_image_url TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);

    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS name TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS phone TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_house_no TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_floor TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_building TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_road TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_subdistrict TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_district TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_province TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_postal_code TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS birth_year INTEGER`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS gender TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS occupation TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS name_i18n JSONB`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS gender_i18n JSONB`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS occupation_i18n JSONB`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS address_i18n JSONB`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS first_name TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS last_name TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'active'`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS role_id INTEGER`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS profile_image_url TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS national_id_image_url TEXT`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`ALTER TABLE public.users ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    try {
      await pool.query(`CREATE UNIQUE INDEX IF NOT EXISTS users_email_lower_unique_idx ON public.users (LOWER(email))`);
    } catch (idxErr) {
      // Keep auth usable even if existing duplicate emails prevent index creation.
      if (idxErr?.code === "23505") {
        console.warn("users email unique index skipped due to existing duplicate emails");
      } else {
        throw idxErr;
      }
    }
  })().catch((e) => {
    _userAuthColumnsReadyPromise = null;
    throw e;
  });

  return _userAuthColumnsReadyPromise;
}

let _businessReferenceColumnsReadyPromise = null;
async function ensureBusinessReferenceColumns() {
  if (_businessReferenceColumnsReadyPromise) return _businessReferenceColumnsReadyPromise;

  _businessReferenceColumnsReadyPromise = (async () => {
    await pool.query(`ALTER TABLE public.events ADD COLUMN IF NOT EXISTS display_code TEXT`);
    await pool.query(`ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS booking_reference TEXT`);
    await pool.query(`ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ`);
    await pool.query(`ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS completed_distance_km NUMERIC(12, 3)`);
    await pool.query(`ALTER TABLE public.payments ADD COLUMN IF NOT EXISTS payment_reference TEXT`);

    const spotTableQ = await pool.query(`SELECT to_regclass('public.spot_events') AS regclass`);
    const hasSpotEventsTable = !!spotTableQ.rows[0]?.regclass;
    if (hasSpotEventsTable) {
      await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS display_code TEXT`);
    }

    await pool.query(`
      UPDATE public.events
      SET display_code = CONCAT(
        CASE
          WHEN UPPER(COALESCE(type::text, 'BIG_EVENT')) = 'SPOT' THEN 'SP'
          ELSE 'EV'
        END,
        LPAD(id::text, 6, '0')
      )
      WHERE COALESCE(TRIM(display_code), '') = ''
    `);

    if (hasSpotEventsTable) {
      await pool.query(`
        UPDATE public.spot_events
        SET display_code = CONCAT('SP', LPAD(id::text, 6, '0'))
        WHERE COALESCE(TRIM(display_code), '') = ''
      `);
    }

    await pool.query(`
      UPDATE public.bookings
      SET booking_reference = CONCAT(
        'BK-',
        TO_CHAR(COALESCE(created_at, NOW()) AT TIME ZONE 'UTC', 'YYYYMMDD'),
        '-',
        LPAD(id::text, 6, '0')
      )
      WHERE COALESCE(TRIM(booking_reference), '') = ''
    `);

    await pool.query(`
      UPDATE public.payments
      SET payment_reference = CONCAT(
        'PAY-',
        TO_CHAR(COALESCE(created_at, NOW()) AT TIME ZONE 'UTC', 'YYYYMMDD'),
        '-',
        LPAD(id::text, 6, '0')
      )
      WHERE COALESCE(TRIM(payment_reference), '') = ''
    `);

    await pool.query(`CREATE UNIQUE INDEX IF NOT EXISTS idx_events_display_code_unique ON public.events (display_code)`);
    await pool.query(`CREATE UNIQUE INDEX IF NOT EXISTS idx_bookings_booking_reference_unique ON public.bookings (booking_reference)`);
    await pool.query(`CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_payment_reference_unique ON public.payments (payment_reference)`);
    if (hasSpotEventsTable) {
      await pool.query(`CREATE UNIQUE INDEX IF NOT EXISTS idx_spot_events_display_code_unique ON public.spot_events (display_code)`);
    }
  })().catch((e) => {
    _businessReferenceColumnsReadyPromise = null;
    throw e;
  });

  return _businessReferenceColumnsReadyPromise;
}

let _bigEventShirtSizeColumnsReadyPromise = null;
async function ensureBigEventShirtSizeColumns() {
  if (_bigEventShirtSizeColumnsReadyPromise) {
    return _bigEventShirtSizeColumnsReadyPromise;
  }

  _bigEventShirtSizeColumnsReadyPromise = (async () => {
    await pool.query(`ALTER TABLE public.bookings ADD COLUMN IF NOT EXISTS shirt_size TEXT`);
    await pool.query(`ALTER TABLE public.participants ADD COLUMN IF NOT EXISTS shirt_size TEXT`);
  })().catch((e) => {
    _bigEventShirtSizeColumnsReadyPromise = null;
    throw e;
  });

  return _bigEventShirtSizeColumnsReadyPromise;
}

function normalizeI18nPayload(rawValue, fallbackValue) {
  const safeFallback = String(fallbackValue ?? "").trim();
  if (!rawValue) {
    return {
      th: safeFallback,
      en: safeFallback,
      zh: safeFallback,
    };
  }

  try {
    const parsed =
      typeof rawValue === "string" ? JSON.parse(rawValue) : rawValue;
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      throw new Error("invalid");
    }
    return {
      th: String(parsed.th ?? safeFallback).trim() || safeFallback,
      en: String(parsed.en ?? safeFallback).trim() || safeFallback,
      zh: String(parsed.zh ?? safeFallback).trim() || safeFallback,
    };
  } catch (_) {
    return {
      th: safeFallback,
      en: safeFallback,
      zh: safeFallback,
    };
  }
}

let _adminContentI18nColumnsReadyPromise = null;
async function ensureAdminContentI18nColumns() {
  if (_adminContentI18nColumnsReadyPromise) {
    return _adminContentI18nColumnsReadyPromise;
  }

  _adminContentI18nColumnsReadyPromise = (async () => {
    await pool.query(
      `ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS name_i18n JSONB`
    );
    await pool.query(
      `ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS description_i18n JSONB`
    );
    await pool.query(
      `ALTER TABLE public.organizations ADD COLUMN IF NOT EXISTS address_i18n JSONB`
    );

    await pool.query(
      `ALTER TABLE public.events ADD COLUMN IF NOT EXISTS title_i18n JSONB`
    );
    await pool.query(
      `ALTER TABLE public.events ADD COLUMN IF NOT EXISTS description_i18n JSONB`
    );
    await pool.query(
      `ALTER TABLE public.events ADD COLUMN IF NOT EXISTS meeting_point_i18n JSONB`
    );
    await pool.query(
      `ALTER TABLE public.events ADD COLUMN IF NOT EXISTS location_name_i18n JSONB`
    );
    await pool.query(
      `ALTER TABLE public.events ADD COLUMN IF NOT EXISTS meeting_point_note_i18n JSONB`
    );
  })().catch((e) => {
    _adminContentI18nColumnsReadyPromise = null;
    throw e;
  });

  return _adminContentI18nColumnsReadyPromise;
}


// ✅ DEBUG: ดูว่า backend ต่อ database ไหนอยู่
pool
  .query("select current_database() as db, current_schema() as schema")
  .then((r) => console.log("🔥 Connected:", r.rows[0]))
  .catch((e) => console.error("DB check error:", e));

ensureEventDistanceColumns()
  .then(() => console.log("events distance columns ready"))
  .catch((e) => console.error("events distance columns migration error:", e));

ensurePaymentSlipColumn()
  .then(() => console.log("payments slip_url column ready"))
  .catch((e) => console.error("payments slip_url migration error:", e));

ensurePaymentSeparationColumns()
  .then(() => console.log("payment separation columns ready"))
  .catch((e) => console.error("payment separation migration error:", e));

ensureUserAuthColumns()
  .then(() => console.log("users auth columns ready"))
  .catch((e) => console.error("users auth migration error:", e));

ensureBusinessReferenceColumns()
  .then(() => console.log("business reference columns ready"))
  .catch((e) => console.error("business reference migration error:", e));

let _spotSubsystemReadyPromise = null;

const OPENAI_LLM_MODERATION_INPUT_USD_PER_1M =
  Number(process.env.OPENAI_LLM_MODERATION_INPUT_USD_PER_1M ?? 0.25) || 0.25;
const OPENAI_LLM_MODERATION_OUTPUT_USD_PER_1M =
  Number(process.env.OPENAI_LLM_MODERATION_OUTPUT_USD_PER_1M ?? 2.0) || 2.0;

ensureSpotSubsystemTables()
  .then(async () => {
    await ensureModerationVocabularySeed();
    await ensureBusinessReferenceColumns();
    console.log("spot subsystem tables ready");
  })
  .catch((e) => console.error("spot subsystem migration error:", e));

// ✅ DEBUG: ดูว่า table users ใน DB นี้มี column อะไรบ้าง
pool
  .query(`
    select column_name
    from information_schema.columns
    where table_schema='public' and table_name='users'
    order by ordinal_position
  `)
  .then((r) => console.log("🔥 users columns:", r.rows.map((x) => x.column_name)))
  .catch((e) => console.error("users columns error:", e));


// ✅ upload
const path = require("path");
const fs = require("fs");
const multer = require("multer");

// ✅ Stripe
const Stripe = require("stripe");
const stripeSecretKey = String(process.env.STRIPE_SECRET_KEY ?? "").trim();
const stripeWebhookSecret = String(process.env.STRIPE_WEBHOOK_SECRET ?? "").trim();
const stripe = stripeSecretKey ? new Stripe(stripeSecretKey) : null;
const airwallex = require("./airwallex.cjs");
const antom = require("./antom.cjs");

const app = express();

if (stripe) {
  console.log("[payments] Stripe integration enabled");
} else {
  console.warn("[payments] Stripe integration disabled: STRIPE_SECRET_KEY is not configured");
}

function stripeUnavailableResponse(res) {
  return res.status(503).json({
    message: "Stripe integration is not configured on this server",
  });
}

// ✅ Enhanced CORS for Flutter Web + Admin Dashboard
const allowedOrigins = new Set([
  'http://localhost:3000',
  'http://127.0.0.1:3000',
  'http://localhost:8080',
  'http://localhost:5000',
  'http://localhost',
  'http://10.0.2.2:3000',
]);

function isAllowedOrigin(origin) {
  if (!origin) return true; // curl/Postman or same-origin requests without Origin header
  if (allowedOrigins.has(origin)) return true;

  // Allow Flutter web/dev origins like http://localhost:9426 or http://127.0.0.1:12345
  return /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/i.test(origin);
}

const corsOptions = {
  origin(origin, callback) {
    if (isAllowedOrigin(origin)) return callback(null, true);
    return callback(new Error(`CORS blocked for origin: ${origin}`));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Accept', 'Authorization', 'x-user-id', 'x-userid', 'userid', 'x-admin-id', 'admin_id'],
};
app.use(cors(corsOptions));
app.options(/.*/, cors(corsOptions));

// Avoid stale GET data in browser/proxy caches during admin operations.
app.use("/api", (req, res, next) => {
  res.setHeader("Cache-Control", "no-store, no-cache, must-revalidate, proxy-revalidate");
  res.setHeader("Pragma", "no-cache");
  res.setHeader("Expires", "0");
  next();
});

/**
 * =====================================================
 * ✅ Enum helpers (กันพัง enum แบบชัวร์: ใช้ค่าแรกของ enum)
 * =====================================================
 */
async function getColumnEnumLabels(client, tableName, columnName, schemaName = "public") {
  const tRes = await client.query(
    `
    SELECT udt_name
    FROM information_schema.columns
    WHERE table_schema = $1
      AND table_name = $2
      AND column_name = $3
    `,
    [schemaName, tableName, columnName]
  );

  if (tRes.rowCount === 0) throw new Error(`Column not found: ${schemaName}.${tableName}.${columnName}`);

  const udtName = tRes.rows[0].udt_name;

  const eRes = await client.query(
    `
    SELECT e.enumlabel
    FROM pg_type t
    JOIN pg_enum e ON t.oid = e.enumtypid
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = $1
      AND t.typname = $2
    ORDER BY e.enumsortorder ASC
    `,
    [schemaName, udtName]
  );

  return eRes.rows.map((r) => r.enumlabel);
}

async function pickEnumSafe(client, tableName, columnName, incomingValue, schemaName = "public") {
  const labels = await getColumnEnumLabels(client, tableName, columnName, schemaName);

  if (!labels || labels.length === 0) return incomingValue ?? null;
  if (incomingValue && labels.includes(incomingValue)) return incomingValue;

  return labels[0];
}

function makeReceiptNo(paymentId) {
  const d = new Date();
  const year = d.getUTCFullYear();
  return `RCPT-${year}-${String(paymentId).padStart(6, "0")}`;
}

function makeReceiptViewPath(receiptNo) {
  return `/api/receipts/${encodeURIComponent(String(receiptNo ?? "").trim())}/view`;
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function formatReceiptDate(value) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return "-";
  return new Intl.DateTimeFormat("en-GB", {
    year: "numeric",
    month: "short",
    day: "2-digit",
  }).format(date);
}

function formatReceiptDateTime(value) {
  const date = value ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return "-";
  return new Intl.DateTimeFormat("en-GB", {
    year: "numeric",
    month: "short",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function formatReceiptAmount(amount, currency) {
  const parsed = Number(amount ?? 0);
  if (!Number.isFinite(parsed)) return `0.00 ${String(currency ?? "THB").toUpperCase()}`;
  return `${parsed.toFixed(2)} ${String(currency ?? "THB").toUpperCase()}`;
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email || "").trim());
}

function splitNameParts(fullName) {
  const parts = String(fullName || "").trim().split(/\s+/).filter(Boolean);
  if (parts.length === 0) return { firstName: "User", lastName: "" };
  const firstName = parts.shift();
  return { firstName, lastName: parts.join(" ") };
}

function getRequestUserId(req, { allowQuery = true, allowBody = true } = {}) {
  const rawCandidates = [
    req.headers?.["x-user-id"],
    req.headers?.["x-userid"],
    req.headers?.["userid"],
    allowQuery ? req.query?.user_id : undefined,
    allowBody ? req.body?.user_id : undefined,
  ]
    .map((v) => (v == null ? "" : String(v).trim()))
    .filter((v) => v.length > 0);

  if (rawCandidates.length === 0) {
    return { ok: false, message: "user_id is required" };
  }

  const parsed = rawCandidates.map((v) => Number(v));
  const hasInvalid = parsed.some(
    (n) => !Number.isFinite(n) || !Number.isInteger(n) || n <= 0
  );
  if (hasInvalid) {
    return { ok: false, message: "Invalid user_id" };
  }

  const first = parsed[0];
  const mismatch = parsed.some((n) => n !== first);
  if (mismatch) {
    return { ok: false, message: "Conflicting user_id values" };
  }

  return { ok: true, userId: first };
}

function getRequestAdminId(req, { allowQuery = true, allowBody = true } = {}) {
  const rawCandidates = [
    req.headers?.["x-admin-id"],
    allowQuery ? req.query?.admin_id : undefined,
    allowBody ? req.body?.admin_id : undefined,
  ]
    .map((v) => (v == null ? "" : String(v).trim()))
    .filter((v) => v.length > 0);

  if (rawCandidates.length === 0) {
    return { ok: false, message: "admin_id is required" };
  }

  const parsed = rawCandidates.map((v) => Number(v));
  const hasInvalid = parsed.some(
    (n) => !Number.isFinite(n) || !Number.isInteger(n) || n <= 0
  );
  if (hasInvalid) {
    return { ok: false, message: "Invalid admin_id" };
  }

  const first = parsed[0];
  const mismatch = parsed.some((n) => n !== first);
  if (mismatch) {
    return { ok: false, message: "Conflicting admin_id values" };
  }

  return { ok: true, adminId: first };
}

async function requireActiveAdmin(req, res, { allowQuery = true, allowBody = true } = {}) {
  const parsed = getRequestAdminId(req, { allowQuery, allowBody });
  if (!parsed.ok) {
    res.status(400).json({ message: parsed.message });
    return null;
  }

  const hasAdminUsersTableQ = await pool.query(
    `SELECT to_regclass('public.admin_users') AS regclass`
  );
  if (!hasAdminUsersTableQ.rows[0]?.regclass) {
    res.status(503).json({ message: "Admin user store unavailable" });
    return null;
  }

  const adminQ = await pool.query(
    `
    SELECT id, email, status
    FROM public.admin_users
    WHERE id = $1
    LIMIT 1
    `,
    [parsed.adminId]
  );

  if (adminQ.rowCount === 0) {
    res.status(401).json({ message: "Invalid admin session" });
    return null;
  }

  const admin = adminQ.rows[0];
  if (admin.status && admin.status !== "active") {
    res.status(403).json({ message: "Admin account not active" });
    return null;
  }

  return { adminId: parsed.adminId, admin };
}

async function tryGetActiveAdmin(req, { allowQuery = true, allowBody = true } = {}) {
  const parsed = getRequestAdminId(req, { allowQuery, allowBody });
  if (!parsed.ok) return null;

  const hasAdminUsersTableQ = await pool.query(
    `SELECT to_regclass('public.admin_users') AS regclass`
  );
  if (!hasAdminUsersTableQ.rows[0]?.regclass) {
    return null;
  }

  const adminQ = await pool.query(
    `
    SELECT id, email, status
    FROM public.admin_users
    WHERE id = $1
    LIMIT 1
    `,
    [parsed.adminId]
  );

  if (adminQ.rowCount === 0) return null;

  const admin = adminQ.rows[0];
  if (admin.status && admin.status !== "active") {
    return null;
  }

  return { adminId: parsed.adminId, admin };
}

function parseUserLookupId(rawValue) {
  const raw = String(rawValue ?? "").trim();
  if (!raw) return null;

  if (/^\d+$/.test(raw)) {
    const parsed = Number(raw);
    return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
  }

  const match = /^US0*(\d+)$/i.exec(raw);
  if (!match) return null;

  const parsed = Number(match[1]);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : null;
}

function makeDisplayCode(prefix, id, width = 4) {
  const parsed = Number(id);
  if (!Number.isInteger(parsed) || parsed <= 0) return "-";
  return `${prefix}${String(parsed).padStart(width, "0")}`;
}

async function tableExists(client, qualifiedTableName) {
  const q = await client.query(
    `SELECT to_regclass($1) AS regclass`,
    [qualifiedTableName]
  );
  return !!q.rows[0]?.regclass;
}

async function columnExists(client, tableName, columnName, schemaName = "public") {
  const q = await client.query(
    `
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = $1
      AND table_name = $2
      AND column_name = $3
    LIMIT 1
    `,
    [schemaName, tableName, columnName]
  );
  return q.rowCount > 0;
}

function parseNullableKm(value) {
  if (value == null) return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function resolveCompletedSpotDistanceValue(distanceValue, kmPerRound, roundCount) {
  const explicitDistance = parseNullableKm(distanceValue);
  if (explicitDistance != null && explicitDistance > 0) {
    return explicitDistance;
  }

  const fallbackDistance =
    Number(kmPerRound ?? 0) * Number(roundCount ?? 0);
  return Number.isFinite(fallbackDistance) ? fallbackDistance : 0;
}

// Prefer activity aggregates derived from explicit completion records only.
async function loadUserDistanceStats(client, userIds) {
  await ensureSpotSubsystemTables();
  await ensureEventDistanceColumns();

  const uniqueUserIds = Array.from(
    new Set(
      (Array.isArray(userIds) ? userIds : [])
        .map((value) => Number(value))
        .filter((value) => Number.isInteger(value) && value > 0)
    )
  );

  const statsByUserId = new Map(
    uniqueUserIds.map((userId) => [
      userId,
      {
        userId,
        totalKm: null,
        joinedCount: 0,
        postCount: 0,
        completedCount: 0,
      },
    ])
  );

  if (uniqueUserIds.length === 0) {
    return statsByUserId;
  }

  const aggregateQ = await client.query(
    `
    WITH requested_users AS (
      SELECT DISTINCT UNNEST($1::bigint[])::bigint AS user_id
    ),
    created_spots AS (
      SELECT
        se.created_by_user_id AS user_id,
        COUNT(*)::int AS post_count,
        COALESCE(
          SUM(
            CASE
              WHEN COALESCE(se.owner_completed_distance_km, 0) > 0
                THEN se.owner_completed_distance_km
              ELSE COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)
            END
          ),
          0
        )::numeric AS created_spot_km
      FROM public.spot_events se
      WHERE se.creator_role = 'user'
        AND se.created_by_user_id = ANY($1::bigint[])
        AND se.owner_completed_at IS NOT NULL
      GROUP BY se.created_by_user_id
    ),
    joined_spots AS (
      SELECT
        sem.user_id,
        COUNT(*)::int AS joined_spot_count,
        COALESCE(
          SUM(
            COALESCE(
              sem.completed_distance_km,
              COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)
            )
          ),
          0
        )::numeric AS joined_spot_km
      FROM public.spot_event_members sem
      JOIN public.spot_events se ON se.id = sem.spot_event_id
      WHERE sem.user_id = ANY($1::bigint[])
        AND sem.completed_at IS NOT NULL
        AND NOT (
          se.creator_role = 'user'
          AND se.created_by_user_id = sem.user_id
        )
      GROUP BY sem.user_id
    ),
    joined_big_events AS (
      SELECT
        b.user_id,
        COUNT(*)::int AS joined_big_event_count,
        COALESCE(SUM(COALESCE(b.completed_distance_km, e.total_distance, 0)), 0)::numeric AS joined_big_event_km
      FROM public.bookings b
      JOIN public.events e ON e.id = b.event_id
      WHERE b.user_id = ANY($1::bigint[])
        AND UPPER(COALESCE(e.type::text, '')) = 'BIG_EVENT'
        AND b.completed_at IS NOT NULL
      GROUP BY b.user_id
    )
    SELECT
      ru.user_id,
      COALESCE(cs.post_count, 0)::int AS post_count,
      (
        COALESCE(js.joined_spot_count, 0)
        + COALESCE(jbe.joined_big_event_count, 0)
      )::int AS joined_count,
      (
        COALESCE(cs.created_spot_km, 0)
        + COALESCE(js.joined_spot_km, 0)
        + COALESCE(jbe.joined_big_event_km, 0)
      )::numeric AS aggregate_total_km
    FROM requested_users ru
    LEFT JOIN created_spots cs ON cs.user_id = ru.user_id
    LEFT JOIN joined_spots js ON js.user_id = ru.user_id
    LEFT JOIN joined_big_events jbe ON jbe.user_id = ru.user_id
    `,
    [uniqueUserIds]
  );

  for (const row of aggregateQ.rows) {
    const userId = Number(row.user_id);
    const current = statsByUserId.get(userId);
    if (!current) continue;

    current.postCount = Number(row.post_count ?? 0);
    current.joinedCount = Number(row.joined_count ?? 0);
    current.completedCount = current.postCount + current.joinedCount;
    current.totalKm = parseNullableKm(row.aggregate_total_km);
    statsByUserId.set(userId, current);
  }

  return statsByUserId;
}

function formatReferenceDate(value) {
  const date = value ? new Date(value) : new Date();
  if (Number.isNaN(date.getTime())) {
    return new Date().toISOString().slice(0, 10).replaceAll("-", "");
  }
  return date.toISOString().slice(0, 10).replaceAll("-", "");
}

function makeEventDisplayCode(type, id) {
  const prefix = String(type ?? "").trim().toUpperCase() === "SPOT" ? "SP" : "EV";
  return makeDisplayCode(prefix, id, 6);
}

function makeBusinessReference(prefix, id, createdAt) {
  const parsed = Number(id);
  if (!Number.isInteger(parsed) || parsed <= 0) return null;
  return `${prefix}-${formatReferenceDate(createdAt)}-${String(parsed).padStart(6, "0")}`;
}

function makeSpotBookingReference(id, createdAt) {
  return makeBusinessReference("SPBK", id, createdAt);
}

function buildSpotChatKey(row) {
  const spotId = Number(row?.id ?? row?.spot_event_id ?? row?.spotId);
  if (Number.isInteger(spotId) && spotId > 0) {
    return `spot:${spotId}`;
  }
  const title = String(row?.title ?? "").trim().toLowerCase();
  const date = String(row?.event_date ?? row?.date ?? "").trim().toLowerCase();
  const time = String(row?.event_time ?? row?.time ?? "").trim().toLowerCase();
  const location = String(row?.location ?? "").trim().toLowerCase();
  return `${title}|${date}|${time}|${location}`;
}

function parseSpotIdFromChatKey(spotKey) {
  const text = String(spotKey ?? "").trim().toLowerCase();
  const match = /^spot:(\d+)$/.exec(text);
  if (!match) return null;
  const spotId = Number(match[1]);
  return Number.isInteger(spotId) && spotId > 0 ? spotId : null;
}

let chatsTableColumnsCache = null;

function parseSpotEventEndAt(row) {
  const rawDate = String(row?.event_date ?? row?.date ?? "").trim();
  const rawTime = String(row?.event_time ?? row?.time ?? "").trim();
  if (!rawDate) return null;

  const normalizedTime = rawTime || "23:59:59";
  let isoLike = rawDate;

  if (/^\d{2}\/\d{2}\/\d{4}$/.test(rawDate)) {
    const [day, month, year] = rawDate.split("/");
    isoLike = `${year}-${month}-${day}`;
  }

  const combined = rawDate.includes("T") ? rawDate : `${isoLike}T${normalizedTime}`;
  const parsed = new Date(combined);
  if (!Number.isNaN(parsed.getTime())) {
    return new Date(parsed.getTime() + 24 * 60 * 60 * 1000);
  }

  const fallback = new Date(rawDate);
  return Number.isNaN(fallback.getTime())
    ? null
    : new Date(fallback.getTime() + 24 * 60 * 60 * 1000);
}

async function getChatsTableColumns(client) {
  if (chatsTableColumnsCache) {
    return chatsTableColumnsCache;
  }

  const q = await client.query(
    `
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'chats'
    `
  );
  chatsTableColumnsCache = new Set(q.rows.map((row) => String(row.column_name ?? "").trim()));
  return chatsTableColumnsCache;
}

async function syncSpotChatClosureRow(client, { spotId, spotKey, closedAt }) {
  const columns = await getChatsTableColumns(client);
  if (!columns.has("is_closed") || !columns.has("closed_at")) {
    return null;
  }

  const params = [closedAt];
  const identifiers = [];

  if (Number.isInteger(Number(spotId)) && Number(spotId) > 0) {
    if (columns.has("spot_event_id")) {
      params.push(Number(spotId));
      identifiers.push(`spot_event_id = $${params.length}`);
    }
    if (columns.has("event_id")) {
      params.push(Number(spotId));
      identifiers.push(`event_id = $${params.length}`);
    }
  }

  const normalizedSpotKey = String(spotKey ?? "").trim();
  if (normalizedSpotKey) {
    if (columns.has("spot_key")) {
      params.push(normalizedSpotKey);
      identifiers.push(`spot_key = $${params.length}`);
    }
    if (columns.has("room_key")) {
      params.push(normalizedSpotKey);
      identifiers.push(`room_key = $${params.length}`);
    }
  }

  if (identifiers.length === 0) {
    return null;
  }

  const updateSet = [
    `is_closed = TRUE`,
    `closed_at = COALESCE(closed_at, $1)`,
  ];
  if (columns.has("updated_at")) {
    updateSet.push(`updated_at = NOW()`);
  }

  const q = await client.query(
    `
    UPDATE public.chats
    SET ${updateSet.join(", ")}
    WHERE (${identifiers.join(" OR ")})
    RETURNING id, is_closed, closed_at
    `,
    params
  );

  return q.rows[0] ?? null;
}

async function ensureSpotChatLifecycleState(client, context) {
  if (!context?.id) {
    return context;
  }

  const endAt = parseSpotEventEndAt(context);
  const isAlreadyClosed = ["closed", "cancelled", "canceled"].includes(
    String(context.status ?? "").trim().toLowerCase()
  );
  const hasEnded = endAt instanceof Date && !Number.isNaN(endAt.getTime()) && endAt.getTime() <= Date.now();

  let nextStatus = String(context.status ?? "");
  let chatClosed = context.chat_closed === true;
  let chatClosedAt = context.chat_closed_at ?? null;

  if (hasEnded) {
    const closedAt = new Date();

    if (!isAlreadyClosed) {
      const closedSpotStatus = await pickEnumSafe(client, "spot_events", "status", "closed");
      const closedQ = await client.query(
        `
        UPDATE public.spot_events
        SET status = $2, updated_at = NOW()
        WHERE id = $1
          AND LOWER(COALESCE(status, '')) NOT IN ('closed', 'cancelled', 'canceled')
        RETURNING status, updated_at
        `,
        [context.id, closedSpotStatus]
      );

      if (closedQ.rowCount > 0) {
        nextStatus = String(closedQ.rows[0].status ?? closedSpotStatus ?? "closed");
        chatClosedAt = closedQ.rows[0].updated_at ?? closedAt.toISOString();
      }
    }

    try {
      const chatRow = await syncSpotChatClosureRow(client, {
        spotId: context.id,
        spotKey: context.spot_key,
        closedAt,
      });
      if (chatRow?.closed_at) {
        chatClosedAt = chatRow.closed_at;
      }
    } catch (chatSyncErr) {
      console.error("Sync spot chat closure row error:", chatSyncErr);
    }

    try {
      await createOrReuseSpotChatRoomAlert(client, {
        spotKey: context.spot_key,
        spotEventId: context.id,
        alertType: "room_closed_event_ended",
        message: "This Spot chat was closed because the event has already ended.",
        triggeredByUserId: null,
        sourceQueueId: null,
        sourceLogId: null,
        expiresAt: null,
      });
    } catch (alertErr) {
      console.error("Create ended-spot room alert error:", alertErr);
    }

    chatClosed = true;
    nextStatus = nextStatus || "closed";
  }

  return {
    ...context,
    status: nextStatus,
    spot_end_at: endAt ? endAt.toISOString() : null,
    chat_closed: chatClosed,
    chat_closed_at: chatClosedAt,
    chat_closed_reason: chatClosed ? "event_ended" : null,
  };
}

function diffSpotEditableFields(beforeRow, afterRow) {
  const fields = [
    ["title", "spot name"],
    ["description", "description"],
    ["location", "location"],
    ["location_link", "location note"],
    ["event_date", "date"],
    ["event_time", "time"],
    ["km_per_round", "km per round"],
    ["round_count", "round"],
    ["max_people", "max participants"],
  ];

  return fields
    .filter(([key]) => String(beforeRow?.[key] ?? "").trim() !== String(afterRow?.[key] ?? "").trim())
    .map(([, label]) => label);
}

function buildSpotUpdatedAlertMessage(changedFields) {
  if (!Array.isArray(changedFields) || changedFields.length === 0) {
    return "Spot details were updated by the host.";
  }
  if (changedFields.length === 1) {
    return `Spot ${changedFields[0]} was changed by the host.`;
  }
  if (changedFields.length === 2) {
    return `Spot ${changedFields[0]} and ${changedFields[1]} were changed by the host.`;
  }
  return `Spot details were changed by the host: ${changedFields.join(", ")}.`;
}

function escapeRegex(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function buildCensoredChatMessage(rawMessage, moderation) {
  let visible = String(rawMessage ?? "");
  const matches = new Set(
    []
      .concat(moderation?.rule_hits ?? [])
      .concat(moderation?.vocabulary_hits ?? [])
      .map((hit) => String(hit?.matched_value ?? "").trim())
      .filter(Boolean)
  );

  for (const match of matches) {
    const isLatinLike = /^[a-z0-9\s'"-]+$/iu.test(match);
    const pattern = isLatinLike
      ? new RegExp(`\\b${escapeRegex(match)}\\b`, "giu")
      : new RegExp(escapeRegex(match), "gu");
    visible = visible.replace(pattern, (segment) => "*".repeat(Math.max(3, segment.length)));
  }

  if (visible.trim() === String(rawMessage ?? "").trim()) {
    return "[Message censored for inappropriate language]";
  }
  return visible;
}

async function loadSpotChatContextByKey(client, spotKey, userId) {
  const stableSpotId = parseSpotIdFromChatKey(spotKey);
  if (stableSpotId != null) {
    const byIdQ = await client.query(
      `
      SELECT
        se.id,
        se.status,
        se.event_date,
        se.event_time,
        se.created_by_user_id,
        se.creator_role,
        EXISTS (
          SELECT 1
          FROM public.spot_event_members sem
          WHERE sem.spot_event_id = se.id
            AND sem.user_id = $2
        ) AS is_member
      FROM public.spot_events se
      WHERE se.id = $1
      LIMIT 1
      `,
      [stableSpotId, userId ?? 0]
    );
    const row = byIdQ.rows[0] ?? null;
    if (!row) return null;
    return ensureSpotChatLifecycleState(client, {
      id: Number(row.id),
      spot_key: buildSpotChatKey({ id: row.id }),
      status: String(row.status ?? ""),
      event_date: String(row.event_date ?? ""),
      event_time: String(row.event_time ?? ""),
      created_by_user_id: row.created_by_user_id == null ? null : Number(row.created_by_user_id),
      creator_role: String(row.creator_role ?? "user").toLowerCase(),
      is_owner: Number(row.created_by_user_id) === Number(userId) && String(row.creator_role ?? "user").toLowerCase() === "user",
      is_member: row.is_member === true,
    });
  }

  const q = await client.query(
    `
    SELECT
      se.id,
      se.status,
      se.event_date,
      se.event_time,
      se.created_by_user_id,
      se.creator_role,
      EXISTS (
        SELECT 1
        FROM public.spot_event_members sem
        WHERE sem.spot_event_id = se.id
          AND sem.user_id = $2
      ) AS is_member
    FROM public.spot_events se
    WHERE LOWER(CONCAT_WS('|',
      TRIM(COALESCE(se.title, '')),
      TRIM(COALESCE(se.event_date, '')),
      TRIM(COALESCE(se.event_time, '')),
      TRIM(COALESCE(se.location, ''))
    )) = $1
    ORDER BY se.id DESC
    LIMIT 1
    `,
    [String(spotKey ?? "").trim().toLowerCase(), userId ?? 0]
  );

  const row = q.rows[0] ?? null;
  if (!row) return null;

  return ensureSpotChatLifecycleState(client, {
    id: Number(row.id),
    spot_key: buildSpotChatKey({ id: row.id }),
    status: String(row.status ?? ""),
    event_date: String(row.event_date ?? ""),
    event_time: String(row.event_time ?? ""),
    created_by_user_id: row.created_by_user_id == null ? null : Number(row.created_by_user_id),
    creator_role: String(row.creator_role ?? "user").toLowerCase(),
    is_owner: Number(row.created_by_user_id) === Number(userId) && String(row.creator_role ?? "user").toLowerCase() === "user",
    is_member: row.is_member === true,
  });
}

function normalizeJsonbValue(value) {
  if (value === undefined) return null;
  if (value === null) return null;
  if (Array.isArray(value)) {
    return value.map((item) => normalizeJsonbValue(item));
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  if (typeof value === "bigint") {
    return value.toString();
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value)
        .filter(([, entryValue]) => entryValue !== undefined)
        .map(([key, entryValue]) => [key, normalizeJsonbValue(entryValue)])
    );
  }
  return value;
}

function toJsonbParam(value, fallback) {
  const normalized = normalizeJsonbValue(value);
  if (normalized == null) {
    return fallback == null ? null : JSON.stringify(normalizeJsonbValue(fallback));
  }
  return JSON.stringify(normalized);
}

async function ensureSpotSubsystemTables() {
  if (_spotSubsystemReadyPromise) return _spotSubsystemReadyPromise;

  _spotSubsystemReadyPromise = (async () => {
    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.spot_events (
        id BIGSERIAL PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        location TEXT NOT NULL DEFAULT '',
        location_link TEXT,
        province TEXT,
        district TEXT,
        event_date TEXT NOT NULL DEFAULT '',
        event_time TEXT NOT NULL DEFAULT '',
        km_per_round NUMERIC(12, 3) NOT NULL DEFAULT 0,
        round_count INTEGER NOT NULL DEFAULT 0,
        max_people INTEGER NOT NULL DEFAULT 0,
        image_base64 TEXT,
        image_url TEXT,
        status TEXT NOT NULL DEFAULT 'completed',
        created_by_user_id BIGINT,
        creator_role TEXT NOT NULL DEFAULT 'user',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS description TEXT NOT NULL DEFAULT ''`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS location TEXT NOT NULL DEFAULT ''`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS location_link TEXT`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS province TEXT`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS district TEXT`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS event_date TEXT NOT NULL DEFAULT ''`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS event_time TEXT NOT NULL DEFAULT ''`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS km_per_round NUMERIC(12, 3) NOT NULL DEFAULT 0`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS round_count INTEGER NOT NULL DEFAULT 0`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS max_people INTEGER NOT NULL DEFAULT 0`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS image_base64 TEXT`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS image_url TEXT`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'completed'`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS created_by_user_id BIGINT`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS creator_role TEXT NOT NULL DEFAULT 'user'`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS location_lat DOUBLE PRECISION`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS location_lng DOUBLE PRECISION`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS owner_completed_at TIMESTAMPTZ`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS owner_completed_distance_km NUMERIC(12, 3)`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`ALTER TABLE public.spot_events ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_events_created_at ON public.spot_events (created_at DESC)`);
    console.log("spot_events location coordinate columns ensured");

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.spot_event_media (
        id BIGSERIAL PRIMARY KEY,
        spot_event_id BIGINT NOT NULL REFERENCES public.spot_events(id) ON DELETE CASCADE,
        kind TEXT NOT NULL DEFAULT 'gallery',
        file_url TEXT NOT NULL,
        alt_text TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_event_media_spot_id ON public.spot_event_media (spot_event_id, kind, sort_order, id)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.spot_event_members (
        id BIGSERIAL PRIMARY KEY,
        spot_event_id BIGINT NOT NULL REFERENCES public.spot_events(id) ON DELETE CASCADE,
        user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
        joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE (spot_event_id, user_id)
      )
    `);
    await pool.query(`ALTER TABLE public.spot_event_members ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ`);
    await pool.query(`ALTER TABLE public.spot_event_members ADD COLUMN IF NOT EXISTS completed_distance_km NUMERIC(12, 3)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_event_members_user_id ON public.spot_event_members (user_id, joined_at DESC)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.spot_event_bookings (
        id BIGSERIAL PRIMARY KEY,
        spot_event_id BIGINT NOT NULL REFERENCES public.spot_events(id) ON DELETE CASCADE,
        user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
        booking_reference TEXT,
        status TEXT NOT NULL DEFAULT 'booked',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE (spot_event_id, user_id)
      )
    `);
    await pool.query(`ALTER TABLE public.spot_event_bookings ADD COLUMN IF NOT EXISTS booking_reference TEXT`);
    await pool.query(`ALTER TABLE public.spot_event_bookings ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'booked'`);
    await pool.query(`ALTER TABLE public.spot_event_bookings ADD COLUMN IF NOT EXISTS completed_at TIMESTAMPTZ`);
    await pool.query(`ALTER TABLE public.spot_event_bookings ADD COLUMN IF NOT EXISTS completed_distance_km NUMERIC(12, 3)`);
    await pool.query(`ALTER TABLE public.spot_event_bookings ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`ALTER TABLE public.spot_event_bookings ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`
      UPDATE public.spot_event_bookings
      SET booking_reference = CONCAT(
        'SPBK-',
        TO_CHAR(COALESCE(created_at, NOW()) AT TIME ZONE 'UTC', 'YYYYMMDD'),
        '-',
        LPAD(id::text, 6, '0')
      )
      WHERE COALESCE(TRIM(booking_reference), '') = ''
    `);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_event_bookings_user_id ON public.spot_event_bookings (user_id, created_at DESC)`);
    await pool.query(`CREATE UNIQUE INDEX IF NOT EXISTS idx_spot_event_bookings_reference_unique ON public.spot_event_bookings (booking_reference)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.spot_chat_messages (
        id BIGSERIAL PRIMARY KEY,
        spot_key TEXT NOT NULL,
        spot_event_id BIGINT REFERENCES public.spot_events(id) ON DELETE SET NULL,
        user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
        sender_name TEXT NOT NULL DEFAULT 'User',
        message TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await pool.query(`ALTER TABLE public.spot_chat_messages ADD COLUMN IF NOT EXISTS spot_event_id BIGINT REFERENCES public.spot_events(id) ON DELETE SET NULL`);
    await pool.query(`ALTER TABLE public.spot_chat_messages ADD COLUMN IF NOT EXISTS sender_name TEXT NOT NULL DEFAULT 'User'`);
    await pool.query(`ALTER TABLE public.spot_chat_messages ADD COLUMN IF NOT EXISTS client_message_key TEXT`);
    await pool.query(`ALTER TABLE public.spot_chat_messages ADD COLUMN IF NOT EXISTS contains_url BOOLEAN NOT NULL DEFAULT FALSE`);
    await pool.query(`ALTER TABLE public.spot_chat_messages ADD COLUMN IF NOT EXISTS moderation_status TEXT NOT NULL DEFAULT 'visible'`);
    await pool.query(`ALTER TABLE public.spot_chat_messages ADD COLUMN IF NOT EXISTS risk_level TEXT NOT NULL DEFAULT 'safe'`);
    await pool.query(`ALTER TABLE public.spot_chat_messages ADD COLUMN IF NOT EXISTS phishing_scan_status TEXT NOT NULL DEFAULT 'not_scanned'`);
    await pool.query(`ALTER TABLE public.spot_chat_messages ADD COLUMN IF NOT EXISTS phishing_scan_reason TEXT`);
    await pool.query(`ALTER TABLE public.spot_chat_messages ADD COLUMN IF NOT EXISTS final_safety_source TEXT NOT NULL DEFAULT 'safe'`);
    await pool.query(`ALTER TABLE public.spot_chat_messages ADD COLUMN IF NOT EXISTS decision_priority INTEGER NOT NULL DEFAULT 0`);
    await pool.query(`ALTER TABLE public.spot_chat_messages ADD COLUMN IF NOT EXISTS blocked_at TIMESTAMPTZ`);
    await pool.query(`ALTER TABLE public.spot_chat_messages ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_chat_messages_spot_key_created_at ON public.spot_chat_messages (spot_key, created_at ASC, id ASC)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_chat_messages_client_message_key ON public.spot_chat_messages (client_message_key)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.spot_chat_room_alerts (
        id BIGSERIAL PRIMARY KEY,
        spot_key TEXT NOT NULL,
        spot_event_id BIGINT NULL REFERENCES public.spot_events(id) ON DELETE SET NULL,
        alert_type TEXT NOT NULL,
        message TEXT NOT NULL,
        triggered_by_user_id BIGINT NULL REFERENCES public.users(id) ON DELETE SET NULL,
        source_queue_id BIGINT NULL,
        source_log_id BIGINT NULL,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        expires_at TIMESTAMPTZ NULL
      )
    `);
    await pool.query(`ALTER TABLE public.spot_chat_room_alerts ADD COLUMN IF NOT EXISTS spot_event_id BIGINT NULL REFERENCES public.spot_events(id) ON DELETE SET NULL`);
    await pool.query(`ALTER TABLE public.spot_chat_room_alerts ADD COLUMN IF NOT EXISTS alert_type TEXT`);
    await pool.query(`ALTER TABLE public.spot_chat_room_alerts ADD COLUMN IF NOT EXISTS message TEXT`);
    await pool.query(`ALTER TABLE public.spot_chat_room_alerts ADD COLUMN IF NOT EXISTS triggered_by_user_id BIGINT NULL REFERENCES public.users(id) ON DELETE SET NULL`);
    await pool.query(`ALTER TABLE public.spot_chat_room_alerts ADD COLUMN IF NOT EXISTS source_queue_id BIGINT NULL`);
    await pool.query(`ALTER TABLE public.spot_chat_room_alerts ADD COLUMN IF NOT EXISTS source_log_id BIGINT NULL`);
    await pool.query(`ALTER TABLE public.spot_chat_room_alerts ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE`);
    await pool.query(`ALTER TABLE public.spot_chat_room_alerts ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`ALTER TABLE public.spot_chat_room_alerts ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ NULL`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_chat_room_alerts_spot_key_created_at ON public.spot_chat_room_alerts (spot_key, created_at DESC)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_chat_room_alerts_active ON public.spot_chat_room_alerts (spot_key, is_active, created_at DESC)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.audit_logs (
        id BIGSERIAL PRIMARY KEY,
        admin_user_id BIGINT NULL,
        user_id BIGINT NULL REFERENCES public.users(id) ON DELETE SET NULL,
        actor_type TEXT NOT NULL DEFAULT 'system',
        action TEXT NOT NULL,
        entity_table TEXT NULL,
        entity_id BIGINT NULL,
        metadata_json JSONB NOT NULL DEFAULT '{}'::JSONB,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await pool.query(`ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS admin_user_id BIGINT NULL`);
    await pool.query(`ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS user_id BIGINT NULL REFERENCES public.users(id) ON DELETE SET NULL`);
    await pool.query(`ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS actor_type TEXT NOT NULL DEFAULT 'system'`);
    await pool.query(`ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS action TEXT NOT NULL DEFAULT 'UNKNOWN'`);
    await pool.query(`ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS entity_table TEXT NULL`);
    await pool.query(`ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS entity_id BIGINT NULL`);
    await pool.query(`ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS metadata_json JSONB NOT NULL DEFAULT '{}'::JSONB`);
    await pool.query(`ALTER TABLE public.audit_logs ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs (created_at DESC)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_audit_logs_action_created_at ON public.audit_logs (action, created_at DESC)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_audit_logs_admin_created_at ON public.audit_logs (admin_user_id, created_at DESC)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.chat_moderation_logs (
        id BIGSERIAL PRIMARY KEY,
        message_id BIGINT NULL REFERENCES public.spot_chat_messages(id) ON DELETE SET NULL,
        user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
        spot_key TEXT NOT NULL,
        spot_event_id BIGINT NULL REFERENCES public.spot_events(id) ON DELETE SET NULL,
        raw_message TEXT NOT NULL,
        normalized_message TEXT NOT NULL,
        detected_categories JSONB NOT NULL DEFAULT '[]'::JSONB,
        severity TEXT NOT NULL DEFAULT 'none',
        action_taken TEXT NOT NULL,
        rule_hits JSONB NOT NULL DEFAULT '[]'::JSONB,
        ai_result_json JSONB NULL,
        ai_used BOOLEAN NOT NULL DEFAULT FALSE,
        ai_confidence DOUBLE PRECISION NULL,
        suspension_required BOOLEAN NOT NULL DEFAULT FALSE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS message_id BIGINT NULL REFERENCES public.spot_chat_messages(id) ON DELETE SET NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS user_id BIGINT REFERENCES public.users(id) ON DELETE CASCADE`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS spot_key TEXT`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS spot_event_id BIGINT REFERENCES public.spot_events(id) ON DELETE SET NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS raw_message TEXT`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS normalized_message TEXT`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS detected_categories JSONB NOT NULL DEFAULT '[]'::JSONB`);
    await pool.query(`
      ALTER TABLE public.chat_moderation_logs
      ALTER COLUMN detected_categories TYPE JSONB
      USING CASE
        WHEN detected_categories IS NULL THEN '[]'::JSONB
        ELSE to_jsonb(detected_categories)
      END
    `);
    await pool.query(`
      ALTER TABLE public.chat_moderation_logs
      ALTER COLUMN detected_categories SET DEFAULT '[]'::JSONB
    `);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS severity TEXT NOT NULL DEFAULT 'none'`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS action_taken TEXT NOT NULL DEFAULT 'allow'`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS rule_hits JSONB NOT NULL DEFAULT '[]'::JSONB`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS ai_result_json JSONB NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS ai_used BOOLEAN NOT NULL DEFAULT FALSE`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS ai_confidence DOUBLE PRECISION NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS suspension_required BOOLEAN NOT NULL DEFAULT FALSE`);
    await pool.query(`ALTER TABLE public.chat_moderation_logs ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_chat_moderation_logs_spot_key_created_at ON public.chat_moderation_logs (spot_key, created_at DESC)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_chat_moderation_logs_user_id_created_at ON public.chat_moderation_logs (user_id, created_at DESC)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_chat_moderation_logs_action_created_at ON public.chat_moderation_logs (action_taken, created_at DESC)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.chat_moderation_preview_logs (
        id BIGSERIAL PRIMARY KEY,
        raw_message TEXT NOT NULL,
        normalized_message TEXT NOT NULL,
        detected_categories JSONB NOT NULL DEFAULT '[]'::JSONB,
        severity TEXT NOT NULL DEFAULT 'none',
        action_taken TEXT NOT NULL DEFAULT 'allow',
        rule_hits JSONB NOT NULL DEFAULT '[]'::JSONB,
        ai_result_json JSONB NULL,
        ai_used BOOLEAN NOT NULL DEFAULT FALSE,
        ai_confidence DOUBLE PRECISION NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await pool.query(`ALTER TABLE public.chat_moderation_preview_logs ADD COLUMN IF NOT EXISTS raw_message TEXT`);
    await pool.query(`ALTER TABLE public.chat_moderation_preview_logs ADD COLUMN IF NOT EXISTS normalized_message TEXT`);
    await pool.query(`ALTER TABLE public.chat_moderation_preview_logs ADD COLUMN IF NOT EXISTS detected_categories JSONB NOT NULL DEFAULT '[]'::JSONB`);
    await pool.query(`ALTER TABLE public.chat_moderation_preview_logs ADD COLUMN IF NOT EXISTS severity TEXT NOT NULL DEFAULT 'none'`);
    await pool.query(`ALTER TABLE public.chat_moderation_preview_logs ADD COLUMN IF NOT EXISTS action_taken TEXT NOT NULL DEFAULT 'allow'`);
    await pool.query(`ALTER TABLE public.chat_moderation_preview_logs ADD COLUMN IF NOT EXISTS rule_hits JSONB NOT NULL DEFAULT '[]'::JSONB`);
    await pool.query(`ALTER TABLE public.chat_moderation_preview_logs ADD COLUMN IF NOT EXISTS ai_result_json JSONB NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_preview_logs ADD COLUMN IF NOT EXISTS ai_used BOOLEAN NOT NULL DEFAULT FALSE`);
    await pool.query(`ALTER TABLE public.chat_moderation_preview_logs ADD COLUMN IF NOT EXISTS ai_confidence DOUBLE PRECISION NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_preview_logs ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_chat_moderation_preview_logs_created_at ON public.chat_moderation_preview_logs (created_at DESC)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_chat_moderation_preview_logs_action_created_at ON public.chat_moderation_preview_logs (action_taken, created_at DESC)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.chat_moderation_learning_queue (
        id BIGSERIAL PRIMARY KEY,
        source_type TEXT NOT NULL DEFAULT 'manual',
        moderation_queue_id BIGINT NULL REFERENCES public.chat_moderation_queue(id) ON DELETE SET NULL,
        moderation_log_id BIGINT NULL REFERENCES public.chat_moderation_logs(id) ON DELETE SET NULL,
        preview_log_id BIGINT NULL REFERENCES public.chat_moderation_preview_logs(id) ON DELETE SET NULL,
        raw_message TEXT NOT NULL,
        normalized_message TEXT NOT NULL,
        current_categories JSONB NOT NULL DEFAULT '[]'::JSONB,
        suggested_action TEXT NOT NULL DEFAULT 'review',
        suggested_categories JSONB NOT NULL DEFAULT '[]'::JSONB,
        candidate_terms JSONB NOT NULL DEFAULT '[]'::JSONB,
        admin_note TEXT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_by_admin_id BIGINT NULL,
        reviewed_by_admin_id BIGINT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        reviewed_at TIMESTAMPTZ NULL,
        applied_at TIMESTAMPTZ NULL
      )
    `);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS source_type TEXT NOT NULL DEFAULT 'manual'`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS moderation_queue_id BIGINT NULL REFERENCES public.chat_moderation_queue(id) ON DELETE SET NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS moderation_log_id BIGINT NULL REFERENCES public.chat_moderation_logs(id) ON DELETE SET NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS preview_log_id BIGINT NULL REFERENCES public.chat_moderation_preview_logs(id) ON DELETE SET NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS raw_message TEXT`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS normalized_message TEXT`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS current_categories JSONB NOT NULL DEFAULT '[]'::JSONB`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS suggested_action TEXT NOT NULL DEFAULT 'review'`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS suggested_categories JSONB NOT NULL DEFAULT '[]'::JSONB`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS candidate_terms JSONB NOT NULL DEFAULT '[]'::JSONB`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS admin_note TEXT NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending'`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS created_by_admin_id BIGINT NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS reviewed_by_admin_id BIGINT NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_learning_queue ADD COLUMN IF NOT EXISTS applied_at TIMESTAMPTZ NULL`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_chat_moderation_learning_queue_status_created_at ON public.chat_moderation_learning_queue (status, created_at DESC)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_chat_moderation_learning_queue_source_created_at ON public.chat_moderation_learning_queue (source_type, created_at DESC)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.chat_moderation_queue (
        id BIGSERIAL PRIMARY KEY,
        moderation_log_id BIGINT NOT NULL REFERENCES public.chat_moderation_logs(id) ON DELETE CASCADE,
        user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
        spot_key TEXT NOT NULL,
        spot_event_id BIGINT NULL REFERENCES public.spot_events(id) ON DELETE SET NULL,
        queue_status TEXT NOT NULL DEFAULT 'open',
        priority TEXT NOT NULL DEFAULT 'normal',
        alert_room BOOLEAN NOT NULL DEFAULT FALSE,
        suspension_required BOOLEAN NOT NULL DEFAULT FALSE,
        review_payload JSONB NOT NULL DEFAULT '{}'::JSONB,
        reviewed_by_admin_id BIGINT NULL,
        reviewed_at TIMESTAMPTZ NULL,
        review_note TEXT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS moderation_log_id BIGINT REFERENCES public.chat_moderation_logs(id) ON DELETE CASCADE`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS user_id BIGINT REFERENCES public.users(id) ON DELETE CASCADE`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS spot_key TEXT`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS spot_event_id BIGINT REFERENCES public.spot_events(id) ON DELETE SET NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS queue_status TEXT NOT NULL DEFAULT 'open'`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS priority TEXT NOT NULL DEFAULT 'normal'`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS alert_room BOOLEAN NOT NULL DEFAULT FALSE`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS suspension_required BOOLEAN NOT NULL DEFAULT FALSE`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS review_payload JSONB NOT NULL DEFAULT '{}'::JSONB`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS reviewed_by_admin_id BIGINT`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS review_note TEXT NULL`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`ALTER TABLE public.chat_moderation_queue ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_chat_moderation_queue_status_created_at ON public.chat_moderation_queue (queue_status, created_at DESC)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_chat_moderation_queue_spot_key_created_at ON public.chat_moderation_queue (spot_key, created_at DESC)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.moderation_vocabulary (
        id BIGSERIAL PRIMARY KEY,
        term TEXT NOT NULL,
        normalized_term TEXT NOT NULL,
        language TEXT NOT NULL DEFAULT 'mixed',
        category TEXT NOT NULL,
        severity TEXT NOT NULL DEFAULT 'medium',
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        source TEXT NOT NULL DEFAULT 'seed',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await pool.query(`ALTER TABLE public.moderation_vocabulary ADD COLUMN IF NOT EXISTS term TEXT`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary ADD COLUMN IF NOT EXISTS normalized_term TEXT`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'mixed'`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'profanity'`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary ADD COLUMN IF NOT EXISTS severity TEXT NOT NULL DEFAULT 'medium'`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'seed'`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`CREATE UNIQUE INDEX IF NOT EXISTS idx_moderation_vocabulary_unique_term ON public.moderation_vocabulary (normalized_term, category, language)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_moderation_vocabulary_active ON public.moderation_vocabulary (is_active, updated_at DESC)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.moderation_vocabulary_suggestions (
        id BIGSERIAL PRIMARY KEY,
        raw_message TEXT NOT NULL,
        suggested_term TEXT NOT NULL,
        normalized_term TEXT NOT NULL,
        language TEXT NOT NULL DEFAULT 'mixed',
        category TEXT NOT NULL,
        confidence DOUBLE PRECISION NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        reviewed_at TIMESTAMPTZ NULL,
        reviewed_by_admin_id BIGINT NULL
      )
    `);
    await pool.query(`ALTER TABLE public.moderation_vocabulary_suggestions ADD COLUMN IF NOT EXISTS raw_message TEXT`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary_suggestions ADD COLUMN IF NOT EXISTS suggested_term TEXT`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary_suggestions ADD COLUMN IF NOT EXISTS normalized_term TEXT`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary_suggestions ADD COLUMN IF NOT EXISTS language TEXT NOT NULL DEFAULT 'mixed'`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary_suggestions ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'profanity'`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary_suggestions ADD COLUMN IF NOT EXISTS confidence DOUBLE PRECISION NOT NULL DEFAULT 0`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary_suggestions ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'pending'`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary_suggestions ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary_suggestions ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ NULL`);
    await pool.query(`ALTER TABLE public.moderation_vocabulary_suggestions ADD COLUMN IF NOT EXISTS reviewed_by_admin_id BIGINT NULL`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_moderation_vocab_suggestions_status_created_at ON public.moderation_vocabulary_suggestions (status, created_at DESC)`);
    await pool.query(`CREATE UNIQUE INDEX IF NOT EXISTS idx_moderation_vocab_suggestions_pending_unique ON public.moderation_vocabulary_suggestions (normalized_term, category, status)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.spot_chat_user_reports (
        id BIGSERIAL PRIMARY KEY,
        reporter_user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
        reported_user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
        spot_key TEXT NOT NULL,
        message_id BIGINT NULL REFERENCES public.spot_chat_messages(id) ON DELETE SET NULL,
        reason_code TEXT NOT NULL DEFAULT 'INAPPROPRIATE_LANGUAGE',
        note TEXT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await pool.query(`ALTER TABLE public.spot_chat_user_reports ADD COLUMN IF NOT EXISTS reporter_user_id BIGINT REFERENCES public.users(id) ON DELETE CASCADE`);
    await pool.query(`ALTER TABLE public.spot_chat_user_reports ADD COLUMN IF NOT EXISTS reported_user_id BIGINT REFERENCES public.users(id) ON DELETE CASCADE`);
    await pool.query(`ALTER TABLE public.spot_chat_user_reports ADD COLUMN IF NOT EXISTS spot_key TEXT`);
    await pool.query(`ALTER TABLE public.spot_chat_user_reports ADD COLUMN IF NOT EXISTS message_id BIGINT NULL REFERENCES public.spot_chat_messages(id) ON DELETE SET NULL`);
    await pool.query(`ALTER TABLE public.spot_chat_user_reports ADD COLUMN IF NOT EXISTS reason_code TEXT NOT NULL DEFAULT 'INAPPROPRIATE_LANGUAGE'`);
    await pool.query(`ALTER TABLE public.spot_chat_user_reports ADD COLUMN IF NOT EXISTS note TEXT NULL`);
    await pool.query(`ALTER TABLE public.spot_chat_user_reports ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_chat_user_reports_spot_key_created_at ON public.spot_chat_user_reports (spot_key, created_at DESC)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_chat_user_reports_reporter_created_at ON public.spot_chat_user_reports (reporter_user_id, created_at DESC)`);

    await pool.query(`
      CREATE TABLE IF NOT EXISTS public.spot_leave_feedback (
        id BIGSERIAL PRIMARY KEY,
        event_id BIGINT NOT NULL,
        leaver_user_id BIGINT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
        reason_code VARCHAR(64) NOT NULL,
        reason_text TEXT NOT NULL,
        report_detail_text TEXT NULL,
        category VARCHAR(32) NOT NULL,
        reported_target_type VARCHAR(16) NOT NULL,
        reported_target_user_id BIGINT NULL REFERENCES public.users(id) ON DELETE SET NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
      )
    `);
    await pool.query(`ALTER TABLE public.spot_leave_feedback ADD COLUMN IF NOT EXISTS report_detail_text TEXT NULL`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_leave_feedback_event_id ON public.spot_leave_feedback(event_id)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_leave_feedback_leaver ON public.spot_leave_feedback(leaver_user_id)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_leave_feedback_category ON public.spot_leave_feedback(category)`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_spot_leave_feedback_target ON public.spot_leave_feedback(reported_target_user_id)`);

    await ensureModerationVocabularySeed();
  })().catch((e) => {
    _spotSubsystemReadyPromise = null;
    throw e;
  });

  return _spotSubsystemReadyPromise;
}

async function insertChatModerationLog(client, payload) {
  const q = await client.query(
    `
    INSERT INTO public.chat_moderation_logs
      (
        message_id,
        user_id,
        spot_key,
        spot_event_id,
        raw_message,
        normalized_message,
        detected_categories,
        severity,
        action_taken,
        rule_hits,
        ai_result_json,
        ai_used,
        ai_confidence,
        suspension_required,
        created_at
      )
    VALUES
      ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10::jsonb, $11::jsonb, $12, $13, $14, NOW())
    RETURNING id
    `,
    [
      payload.messageId ?? null,
      payload.userId,
      payload.spotKey,
      payload.spotEventId ?? null,
      payload.rawMessage,
      payload.normalizedMessage,
      toJsonbParam(payload.detectedCategories, []),
      payload.severity ?? "none",
      payload.actionTaken,
      toJsonbParam(payload.ruleHits, []),
      toJsonbParam(payload.aiResultJson, null),
      Boolean(payload.aiUsed),
      payload.aiConfidence == null ? null : Number(payload.aiConfidence),
      Boolean(payload.suspensionRequired),
    ]
  );

  return q.rows[0]?.id ?? null;
}

async function insertChatModerationPreviewLog(payload) {
  const q = await pool.query(
    `
    INSERT INTO public.chat_moderation_preview_logs
      (
        raw_message,
        normalized_message,
        detected_categories,
        severity,
        action_taken,
        rule_hits,
        ai_result_json,
        ai_used,
        ai_confidence,
        created_at
      )
    VALUES
      ($1, $2, $3::jsonb, $4, $5, $6::jsonb, $7::jsonb, $8, $9, NOW())
    RETURNING id
    `,
    [
      payload.rawMessage,
      payload.normalizedMessage,
      toJsonbParam(payload.detectedCategories, []),
      payload.severity ?? "none",
      payload.actionTaken ?? "allow",
      toJsonbParam(payload.ruleHits, []),
      toJsonbParam(payload.aiResultJson, null),
      Boolean(payload.aiUsed),
      payload.aiConfidence == null ? null : Number(payload.aiConfidence),
    ]
  );

  return q.rows[0]?.id ?? null;
}

async function insertSpotChatUrlScanLog(client, payload) {
  await client.query(
    `
    INSERT INTO public.chat_message_url_scans
      (
        chat_message_id,
        scanned_url,
        normalized_url,
        matched_indicator_id,
        source_name,
        result,
        confidence_score,
        detection_method,
        reason,
        scanned_at
      )
    VALUES
      ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
    `,
    [
      payload.chatMessageId,
      payload.scannedUrl,
      payload.normalizedUrl,
      payload.matchedIndicatorId,
      payload.sourceName,
      payload.result,
      payload.confidenceScore,
      payload.detectionMethod,
      payload.reason,
    ]
  );
}

function sanitizeLearningQueueStringList(values) {
  if (!Array.isArray(values)) return [];
  return Array.from(
    new Set(
      values
        .map((value) => String(value ?? "").trim())
        .filter(Boolean)
        .slice(0, 20)
    )
  );
}

function parseLearningQueueDelimitedList(value) {
  if (Array.isArray(value)) {
    return sanitizeLearningQueueStringList(value);
  }

  const text = String(value ?? "").trim();
  if (!text) return [];
  const delimiter = text.includes("|") ? "|" : ",";
  return sanitizeLearningQueueStringList(
    text.split(delimiter).map((item) => item.trim())
  );
}

function parseSimpleCsvLine(line) {
  const cells = [];
  let current = "";
  let inQuotes = false;

  for (let index = 0; index < line.length; index += 1) {
    const char = line[index];
    const next = line[index + 1];

    if (char === '"') {
      if (inQuotes && next === '"') {
        current += '"';
        index += 1;
      } else {
        inQuotes = !inQuotes;
      }
      continue;
    }

    if (char === "," && !inQuotes) {
      cells.push(current.trim());
      current = "";
      continue;
    }

    current += char;
  }

  cells.push(current.trim());
  return cells;
}

function parseLearningQueueImportEntries({ format, content, defaultSuggestedAction, defaultSuggestedCategories, defaultAdminNote }) {
  const normalizedFormat = String(format ?? "json").trim().toLowerCase();
  const sourceText = String(content ?? "").trim();
  if (!sourceText) {
    throw new Error("Import content is required");
  }

  const entries = [];
  if (normalizedFormat === "json") {
    const parsed = JSON.parse(sourceText);
    if (!Array.isArray(parsed)) {
      throw new Error("JSON import must be an array");
    }

    for (const item of parsed) {
      if (typeof item === "string") {
        const rawMessage = item.trim();
        if (!rawMessage) continue;
        entries.push({
          rawMessage,
          suggestedAction: defaultSuggestedAction,
          suggestedCategories: defaultSuggestedCategories,
          candidateTerms: [rawMessage],
          adminNote: defaultAdminNote,
          currentCategories: [],
        });
        continue;
      }

      if (!item || typeof item !== "object") continue;
      const rawMessage = String(
        item.raw_message ?? item.rawMessage ?? item.text ?? item.term ?? item.phrase ?? item.message ?? ""
      ).trim();
      if (!rawMessage) continue;

      const candidateTerms = parseLearningQueueDelimitedList(
        item.candidate_terms ?? item.candidateTerms
      );
      entries.push({
        rawMessage,
        suggestedAction: String(item.suggested_action ?? item.suggestedAction ?? defaultSuggestedAction ?? "review")
          .trim()
          .toLowerCase(),
        suggestedCategories: parseLearningQueueDelimitedList(
          item.suggested_categories ?? item.suggestedCategories ?? defaultSuggestedCategories
        ),
        candidateTerms: candidateTerms.length > 0 ? candidateTerms : [rawMessage],
        adminNote: String(item.admin_note ?? item.adminNote ?? defaultAdminNote ?? "").trim() || null,
        currentCategories: parseLearningQueueDelimitedList(
          item.current_categories ?? item.currentCategories
        ),
      });
    }
  } else if (normalizedFormat === "csv") {
    const lines = sourceText
      .split(/\r?\n/gu)
      .map((line) => line.trim())
      .filter(Boolean);
    if (lines.length < 2) {
      throw new Error("CSV import needs a header row and at least one data row");
    }

    const headers = parseSimpleCsvLine(lines[0]).map((header) => header.trim().toLowerCase());
    for (const line of lines.slice(1)) {
      const cells = parseSimpleCsvLine(line);
      const row = {};
      headers.forEach((header, index) => {
        row[header] = cells[index] ?? "";
      });

      const rawMessage = String(
        row.raw_message ?? row.rawmessage ?? row.text ?? row.term ?? row.phrase ?? row.message ?? ""
      ).trim();
      if (!rawMessage) continue;

      const candidateTerms = parseLearningQueueDelimitedList(
        row.candidate_terms ?? row.candidateterms ?? row.terms
      );
      entries.push({
        rawMessage,
        suggestedAction: String(
          row.suggested_action ?? row.suggestedaction ?? defaultSuggestedAction ?? "review"
        )
          .trim()
          .toLowerCase(),
        suggestedCategories: parseLearningQueueDelimitedList(
          row.suggested_categories ?? row.suggestedcategories ?? row.categories ?? defaultSuggestedCategories
        ),
        candidateTerms: candidateTerms.length > 0 ? candidateTerms : [rawMessage],
        adminNote: String(row.admin_note ?? row.adminnote ?? defaultAdminNote ?? "").trim() || null,
        currentCategories: parseLearningQueueDelimitedList(
          row.current_categories ?? row.currentcategories
        ),
      });
    }
  } else {
    throw new Error("Unsupported import format");
  }

  return entries.slice(0, 200);
}

async function insertModerationLearningQueueItem(client, payload) {
  const q = await client.query(
    `
    INSERT INTO public.chat_moderation_learning_queue
      (
        source_type,
        moderation_queue_id,
        moderation_log_id,
        preview_log_id,
        raw_message,
        normalized_message,
        current_categories,
        suggested_action,
        suggested_categories,
        candidate_terms,
        admin_note,
        status,
        created_by_admin_id,
        created_at
      )
    VALUES
      ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9::jsonb, $10::jsonb, $11, 'pending', $12, NOW())
    RETURNING *
    `,
    [
      payload.sourceType ?? "manual",
      payload.moderationQueueId ?? null,
      payload.moderationLogId ?? null,
      payload.previewLogId ?? null,
      payload.rawMessage,
      payload.normalizedMessage,
      toJsonbParam(payload.currentCategories, []),
      payload.suggestedAction ?? "review",
      toJsonbParam(payload.suggestedCategories, []),
      toJsonbParam(payload.candidateTerms, []),
      payload.adminNote ?? null,
      payload.createdByAdminId ?? null,
    ]
  );

  return q.rows[0] ?? null;
}

function extractOpenAIReasonedUsage(openaiReasoned) {
  const usage = openaiReasoned?.usage ?? null;
  const inputTokens = Number(usage?.input_tokens ?? 0) || 0;
  const outputTokens = Number(usage?.output_tokens ?? 0) || 0;
  const totalTokens = Number(usage?.total_tokens ?? inputTokens + outputTokens) || 0;

  return {
    input_tokens: inputTokens,
    output_tokens: outputTokens,
    total_tokens: totalTokens,
  };
}

function estimateOpenAIReasonedCostUsd(openaiReasoned) {
  const usage = extractOpenAIReasonedUsage(openaiReasoned);
  const inputCost = (usage.input_tokens / 1000000) * OPENAI_LLM_MODERATION_INPUT_USD_PER_1M;
  const outputCost = (usage.output_tokens / 1000000) * OPENAI_LLM_MODERATION_OUTPUT_USD_PER_1M;
  const total = inputCost + outputCost;

  return {
    input_tokens: usage.input_tokens,
    output_tokens: usage.output_tokens,
    total_tokens: usage.total_tokens,
    estimated_cost_usd: Number(total.toFixed(8)),
    pricing: {
      input_usd_per_1m_tokens: OPENAI_LLM_MODERATION_INPUT_USD_PER_1M,
      output_usd_per_1m_tokens: OPENAI_LLM_MODERATION_OUTPUT_USD_PER_1M,
    },
  };
}

function buildStoredOpenAIReasonedResult(openaiReasoned) {
  if (!openaiReasoned || typeof openaiReasoned !== "object") {
    return openaiReasoned ?? null;
  }

  return {
    ...openaiReasoned,
    cost_estimate: estimateOpenAIReasonedCostUsd(openaiReasoned),
  };
}

function isSpotChatPhishingAlertRequired(scanResult) {
  const riskLevel = String(scanResult?.riskLevel ?? "").toLowerCase();
  const source = String(scanResult?.finalSafetySource ?? "").toLowerCase();
  return (
    (riskLevel === "suspicious" || riskLevel === "phishing") &&
    (source === "phishing_indicator" || source === "ai_scam_suspicion")
  );
}

function buildSpotChatAiScamSuspicionOutcome({ moderation, phishingScanResult }) {
  const signalSplit = moderation?.signal_split ?? {};
  const phishingCategories = Array.isArray(signalSplit.phishingOwnedCategories)
    ? signalSplit.phishingOwnedCategories
    : [];
  const phishingAiReasons = Array.isArray(signalSplit.phishingOwnedAiReasons)
    ? signalSplit.phishingOwnedAiReasons
    : [];
  const hasStrongKnownPhishing = String(phishingScanResult?.riskLevel ?? "").toLowerCase() === "phishing";

  if (hasStrongKnownPhishing) {
    return {
      action: "known_phishing_block",
      shouldWarn: false,
      riskLevel: "phishing",
      moderationStatus: "blocked",
      phishingScanStatus: "scanned",
      phishingScanReason: phishingScanResult?.phishingScanReason ?? "Matched known phishing detection.",
      finalSafetySource: "phishing_indicator",
    };
  }

  if (phishingCategories.length === 0 && phishingAiReasons.length === 0) {
    return {
      action: "ignore",
      shouldWarn: false,
      riskLevel: "safe",
      moderationStatus: "visible",
      phishingScanStatus: phishingScanResult?.phishingScanStatus ?? "not_scanned",
      phishingScanReason: phishingScanResult?.phishingScanReason ?? null,
      finalSafetySource: "safe",
    };
  }

  return {
    action: "suspicious_warning",
    shouldWarn: true,
    blocked: false,
    riskLevel: "suspicious",
    moderationStatus: "warning",
    phishingScanStatus: "scanned",
    phishingScanReason:
      "AI detected suspicious scam-like or obfuscated phishing behavior without a known phishing match.",
    finalSafetySource: "ai_scam_suspicion",
  };
}

function getSpotChatDecisionPriority({ finalSafetySource, finalMessageState }) {
  const source = String(finalSafetySource ?? "safe").toLowerCase();
  const state = String(finalMessageState ?? "visible").toLowerCase();

  if (source === "language_moderation" && state === "blocked") return 100;
  if (source === "phishing_indicator" && state === "blocked") return 90;
  if (source === "phishing_indicator" && state === "warning") return 90;
  if (source === "ai_scam_suspicion" && state === "warning") return 50;
  return 0;
}

function buildSpotChatFinalDecision({ moderation, phishingScanResult, aiScamOutcome }) {
  const candidates = [];

  if (moderation?.decision?.save_message === false) {
    candidates.push({
      finalMessageState: "blocked",
      finalSafetySource: "language_moderation",
      moderationStatus: "blocked",
      riskLevel: "safe",
      phishingScanStatus: phishingScanResult?.phishingScanStatus ?? "not_scanned",
      phishingScanReason: phishingScanResult?.phishingScanReason ?? null,
      blockedAt: null,
    });
  }

  if (String(phishingScanResult?.riskLevel ?? "").toLowerCase() === "phishing") {
    candidates.push({
      finalMessageState: "blocked",
      finalSafetySource: "phishing_indicator",
      moderationStatus: "blocked",
      riskLevel: "phishing",
      phishingScanStatus: "scanned",
      phishingScanReason:
        phishingScanResult?.phishingScanReason ?? "Matched known phishing detection.",
      blockedAt: phishingScanResult?.blockedAt ?? new Date(),
    });
  } else if (String(phishingScanResult?.riskLevel ?? "").toLowerCase() === "suspicious") {
    candidates.push({
      finalMessageState: "warning",
      finalSafetySource: "phishing_indicator",
      moderationStatus: "warning",
      riskLevel: "suspicious",
      phishingScanStatus: "scanned",
      phishingScanReason:
        phishingScanResult?.phishingScanReason ?? "Matched suspicious phishing detection.",
      blockedAt: null,
    });
  }

  if (aiScamOutcome?.shouldWarn === true) {
    candidates.push({
      finalMessageState: "warning",
      finalSafetySource: "ai_scam_suspicion",
      moderationStatus: aiScamOutcome.moderationStatus ?? "warning",
      riskLevel: aiScamOutcome.riskLevel ?? "suspicious",
      phishingScanStatus: aiScamOutcome.phishingScanStatus ?? "scanned",
      phishingScanReason: aiScamOutcome.phishingScanReason ?? null,
      blockedAt: null,
    });
  }

  const bestCandidate =
    candidates
      .map((candidate) => ({
        ...candidate,
        decisionPriority: getSpotChatDecisionPriority(candidate),
      }))
      .sort((a, b) => b.decisionPriority - a.decisionPriority)[0] ?? null;

  if (bestCandidate) {
    return {
      blocked: bestCandidate.finalMessageState === "blocked",
      warning: bestCandidate.finalMessageState === "warning",
      finalMessageState: bestCandidate.finalMessageState,
      finalSafetySource: bestCandidate.finalSafetySource,
      decisionPriority: bestCandidate.decisionPriority,
      moderationStatus: bestCandidate.moderationStatus,
      riskLevel: bestCandidate.riskLevel,
      phishingScanStatus: bestCandidate.phishingScanStatus,
      phishingScanReason: bestCandidate.phishingScanReason,
      blockedAt: bestCandidate.blockedAt,
    };
  }

  return {
    blocked: false,
    warning: false,
    finalMessageState: "visible",
    finalSafetySource: "safe",
    decisionPriority: 0,
    moderationStatus: "visible",
    riskLevel: "safe",
    phishingScanStatus:
      phishingScanResult?.containsUrl === true
        ? phishingScanResult?.phishingScanStatus ?? "scanned"
        : "not_scanned",
    phishingScanReason: phishingScanResult?.phishingScanReason ?? null,
    blockedAt: null,
  };
}

async function insertChatModerationQueueItem(client, payload) {
  const q = await client.query(
    `
    INSERT INTO public.chat_moderation_queue
      (
        moderation_log_id,
        user_id,
        spot_key,
        spot_event_id,
        queue_status,
        priority,
        alert_room,
        suspension_required,
        review_payload,
        created_at,
        updated_at
      )
    VALUES
      ($1, $2, $3, $4, 'pending', $5, $6, $7, $8::jsonb, NOW(), NOW())
    RETURNING id
    `,
    [
      payload.moderationLogId,
      payload.userId,
      payload.spotKey,
      payload.spotEventId ?? null,
      payload.priority ?? "normal",
      Boolean(payload.alertRoom),
      Boolean(payload.suspensionRequired),
      toJsonbParam(payload.reviewPayload, {}),
    ]
  );

  return q.rows[0] ?? null;
}

async function createOrReuseSpotChatRoomAlert(client, payload) {
  const recentQ = await client.query(
    `
    SELECT id, spot_key, alert_type, message, created_at, expires_at, is_active
    FROM public.spot_chat_room_alerts
    WHERE spot_key = $1
      AND alert_type = $2
      AND message = $3
      AND is_active = TRUE
      AND (expires_at IS NULL OR expires_at > NOW())
      AND created_at >= NOW() - INTERVAL '15 minutes'
    ORDER BY created_at DESC, id DESC
    LIMIT 1
    `,
    [payload.spotKey, payload.alertType, payload.message]
  );
  if (recentQ.rowCount > 0) {
    return recentQ.rows[0];
  }

  const inserted = await client.query(
    `
    INSERT INTO public.spot_chat_room_alerts
      (
        spot_key,
        spot_event_id,
        alert_type,
        message,
        triggered_by_user_id,
        source_queue_id,
        source_log_id,
        is_active,
        created_at,
        expires_at
      )
    VALUES
      ($1, $2, $3, $4, $5, $6, $7, TRUE, NOW(), $8)
    RETURNING id, spot_key, alert_type, message, created_at, expires_at, is_active
    `,
    [
      payload.spotKey,
      payload.spotEventId ?? null,
      payload.alertType,
      payload.message,
      payload.triggeredByUserId ?? null,
      payload.sourceQueueId ?? null,
      payload.sourceLogId ?? null,
      payload.expiresAt ?? null,
    ]
  );

  return inserted.rows[0] ?? null;
}

async function insertAuditLog(client, payload) {
  await client.query(
    `
    INSERT INTO public.audit_logs
      (
        admin_user_id,
        user_id,
        actor_type,
        action,
        entity_table,
        entity_id,
        metadata_json,
        created_at
      )
    VALUES
      ($1, $2, $3, $4, $5, $6, $7::jsonb, NOW())
    `,
    [
      payload.adminUserId ?? null,
      payload.userId ?? null,
      payload.actorType ?? "system",
      payload.action,
      payload.entityTable ?? null,
      payload.entityId ?? null,
      toJsonbParam(payload.metadata, {}),
    ]
  );
}

async function ensureEventDisplayCode(client, { tableName = "events", entityId, type }) {
  const q = await client.query(
    `
    SELECT id, display_code, created_at
    FROM public.${tableName}
    WHERE id = $1
    LIMIT 1
    `,
    [entityId]
  );
  if (q.rowCount === 0) return null;

  const existing = String(q.rows[0].display_code ?? "").trim();
  if (existing) return existing;

  const nextDisplayCode = makeEventDisplayCode(type, q.rows[0].id);
  await client.query(
    `
    UPDATE public.${tableName}
    SET display_code = $2
    WHERE id = $1
      AND COALESCE(TRIM(display_code), '') = ''
    `,
    [entityId, nextDisplayCode]
  );
  return nextDisplayCode;
}

async function ensureBookingReference(client, bookingId) {
  const q = await client.query(
    `
    SELECT id, booking_reference, created_at
    FROM public.bookings
    WHERE id = $1
    LIMIT 1
    `,
    [bookingId]
  );
  if (q.rowCount === 0) return null;

  const existing = String(q.rows[0].booking_reference ?? "").trim();
  if (existing) return existing;

  const reference = makeBusinessReference("BK", q.rows[0].id, q.rows[0].created_at);
  await client.query(
    `
    UPDATE public.bookings
    SET booking_reference = $2
    WHERE id = $1
      AND COALESCE(TRIM(booking_reference), '') = ''
    `,
    [bookingId, reference]
  );
  return reference;
}

async function ensurePaymentReference(client, paymentId) {
  const q = await client.query(
    `
    SELECT id, payment_reference, created_at
    FROM public.payments
    WHERE id = $1
    LIMIT 1
    `,
    [paymentId]
  );
  if (q.rowCount === 0) return null;

  const existing = String(q.rows[0].payment_reference ?? "").trim();
  if (existing) return existing;

  const reference = makeBusinessReference("PAY", q.rows[0].id, q.rows[0].created_at);
  await client.query(
    `
    UPDATE public.payments
    SET payment_reference = $2
    WHERE id = $1
      AND COALESCE(TRIM(payment_reference), '') = ''
    `,
    [paymentId, reference]
  );
  return reference;
}

async function ensureSpotBookingReference(client, spotBookingId) {
  const q = await client.query(
    `
    SELECT id, booking_reference, created_at
    FROM public.spot_event_bookings
    WHERE id = $1
    LIMIT 1
    `,
    [spotBookingId]
  );
  if (q.rowCount === 0) return null;

  const existing = String(q.rows[0].booking_reference ?? "").trim();
  if (existing) return existing;

  const reference = makeSpotBookingReference(q.rows[0].id, q.rows[0].created_at);
  await client.query(
    `
    UPDATE public.spot_event_bookings
    SET booking_reference = $2
    WHERE id = $1
      AND COALESCE(TRIM(booking_reference), '') = ''
    `,
    [spotBookingId, reference]
  );
  return reference;
}

async function applySpotChatSevereModerationConsequences(client, payload) {
  const context = payload.spotContext ?? null;
  if (!context?.id) {
    return {
      sender_removed: false,
      room_closed: false,
      spot_event_id: null,
    };
  }

  if (context.is_owner) {
    await client.query(
      `
      UPDATE public.spot_events
      SET status = 'closed', updated_at = NOW()
      WHERE id = $1
      `,
      [context.id]
    );

    const closureAlert = await createOrReuseSpotChatRoomAlert(client, {
      spotKey: payload.spotKey,
      spotEventId: context.id,
      alertType: "room_closed_moderation",
      message: "This Spot chat was closed due to a serious safety violation and has been sent to admin review.",
      triggeredByUserId: payload.userId,
      sourceQueueId: payload.moderationQueueId ?? null,
      sourceLogId: payload.moderationLogId,
      expiresAt: null,
    });

    await insertAuditLog(client, {
      userId: payload.userId,
      actorType: "system",
      action: "SPOT_CHAT_OWNER_ROOM_CLOSED_FOR_MODERATION",
      entityTable: "spot_events",
      entityId: context.id,
      metadata: {
        moderation_log_id: payload.moderationLogId,
        moderation_queue_id: payload.moderationQueueId ?? null,
        spot_key: payload.spotKey,
        spot_event_id: context.id,
        category: payload.primaryCategory,
        action: payload.action,
        alert_id: closureAlert?.id ?? null,
      },
    });

    return {
      sender_removed: true,
      room_closed: true,
      spot_event_id: context.id,
      room_alert: closureAlert ?? null,
    };
  }

  const removed = await client.query(
    `
    DELETE FROM public.spot_event_members
    WHERE spot_event_id = $1
      AND user_id = $2
    RETURNING id
    `,
    [context.id, payload.userId]
  );

  await insertAuditLog(client, {
    userId: payload.userId,
    actorType: "system",
    action: "SPOT_CHAT_USER_REMOVED_FROM_ROOM_FOR_MODERATION",
    entityTable: "spot_event_members",
    entityId: removed.rows[0]?.id ?? null,
    metadata: {
      moderation_log_id: payload.moderationLogId,
      moderation_queue_id: payload.moderationQueueId ?? null,
      spot_key: payload.spotKey,
      spot_event_id: context.id,
      category: payload.primaryCategory,
      action: payload.action,
    },
  });

  return {
    sender_removed: removed.rowCount > 0,
    room_closed: false,
    spot_event_id: context.id,
  };
}

async function createModerationVocabularySuggestions(client, payload) {
  const confidence = Number(payload.confidence ?? 0);
  if (!Number.isFinite(confidence) || confidence < 0.85) {
    return [];
  }

  const insertedRows = [];
  for (const rawTerm of payload.suggestedTerms ?? []) {
    const normalizedTerm = normalizeVocabularyTerm(rawTerm);
    if (!normalizedTerm || normalizedTerm.length < 3) continue;

    const existsQ = await client.query(
      `
      SELECT 1
      FROM public.moderation_vocabulary
      WHERE normalized_term = $1
        AND category = $2
        AND is_active = TRUE
      LIMIT 1
      `,
      [normalizedTerm, payload.category]
    );
    if (existsQ.rowCount > 0) continue;

    const suggestionQ = await client.query(
      `
      INSERT INTO public.moderation_vocabulary_suggestions
        (
          raw_message,
          suggested_term,
          normalized_term,
          language,
          category,
          confidence,
          status,
          created_at
        )
      VALUES
        ($1, $2, $3, $4, $5, $6, 'pending', NOW())
      ON CONFLICT (normalized_term, category, status)
      DO NOTHING
      RETURNING id, suggested_term, normalized_term, category
      `,
      [
        payload.rawMessage,
        rawTerm,
        normalizedTerm,
        detectVocabularyLanguage(rawTerm),
        payload.category,
        confidence,
      ]
    );

    const inserted = suggestionQ.rows[0] ?? null;
    if (!inserted) continue;
    insertedRows.push(inserted);

    try {
      await insertAuditLog(client, {
        userId: payload.userId ?? null,
        actorType: "system",
        action: "SPOT_CHAT_VOCAB_SUGGESTION_CREATED",
        entityTable: "moderation_vocabulary_suggestions",
        entityId: inserted.id,
        metadata: {
          spot_key: payload.spotKey,
          category: payload.category,
          normalized_term: inserted.normalized_term,
          confidence,
        },
      });
    } catch (auditErr) {
      console.error("Insert moderation vocabulary suggestion audit error:", auditErr);
    }
  }

  return insertedRows;
}

async function loadModerationQueueItem(client, queueId) {
  const q = await client.query(
    `
    SELECT
      q.id,
      q.moderation_log_id,
      q.user_id,
      q.spot_key,
      q.spot_event_id,
      q.queue_status,
      q.priority,
      q.alert_room,
      q.suspension_required,
      q.review_payload,
      q.reviewed_by_admin_id,
      q.reviewed_at,
      q.review_note,
      q.created_at,
      q.updated_at,
      l.message_id,
      l.raw_message,
      l.normalized_message,
      l.detected_categories,
      l.severity,
      l.action_taken,
      l.rule_hits,
      l.ai_used,
      l.ai_confidence,
      l.ai_result_json
    FROM public.chat_moderation_queue q
    JOIN public.chat_moderation_logs l ON l.id = q.moderation_log_id
    WHERE q.id = $1
    LIMIT 1
    `,
    [queueId]
  );

  return q.rows[0] ?? null;
}

async function updateModerationQueueReview(client, {
  queueId,
  queueStatus,
  adminId,
  reviewNote,
}) {
  const q = await client.query(
    `
    UPDATE public.chat_moderation_queue
    SET
      queue_status = $2,
      reviewed_by_admin_id = $3,
      reviewed_at = NOW(),
      review_note = COALESCE($4, review_note),
      updated_at = NOW()
    WHERE id = $1
    RETURNING
      id,
      moderation_log_id,
      user_id,
      spot_key,
      spot_event_id,
      queue_status,
      priority,
      alert_room,
      suspension_required,
      review_payload,
      reviewed_by_admin_id,
      reviewed_at,
      review_note,
      created_at,
      updated_at
    `,
    [queueId, queueStatus, adminId, reviewNote ?? null]
  );

  return q.rows[0] ?? null;
}

function sanitizeModerationStringList(value) {
  if (Array.isArray(value)) {
    return value
      .map((item) => String(item ?? "").trim())
      .filter(Boolean);
  }
  return [];
}

function buildStoredModerationDecision(action, {
  severity = "none",
  primaryCategory = null,
} = {}) {
  switch (String(action ?? "").trim().toLowerCase()) {
    case "censor_and_warn":
      return {
        action: "censor_and_warn",
        severity: severity === "none" ? "medium" : severity,
        primary_category: primaryCategory,
        save_message: true,
        enqueue_admin_review: false,
        suspension_required: false,
        alert_room: false,
        remove_from_room: false,
        close_room_if_owner: false,
        visible_message_mode: "censored",
      };
    case "block_and_flag":
      return {
        action: "block_and_flag",
        severity: severity === "none" ? "medium" : severity,
        primary_category: primaryCategory,
        save_message: false,
        enqueue_admin_review: false,
        suspension_required: false,
        alert_room: false,
        remove_from_room: false,
        close_room_if_owner: false,
        visible_message_mode: "raw",
      };
    case "block_and_alert_room":
      return {
        action: "block_and_alert_room",
        severity: severity === "none" ? "high" : severity,
        primary_category: primaryCategory,
        save_message: false,
        enqueue_admin_review: false,
        suspension_required: false,
        alert_room: true,
        remove_from_room: false,
        close_room_if_owner: false,
        visible_message_mode: "raw",
      };
    case "block_remove_and_report":
      return {
        action: "block_remove_and_report",
        severity: severity === "none" ? "critical" : severity,
        primary_category: primaryCategory,
        save_message: false,
        enqueue_admin_review: false,
        suspension_required: true,
        alert_room: false,
        remove_from_room: true,
        close_room_if_owner: true,
        visible_message_mode: "raw",
      };
    case "block_and_report":
      return {
        action: "block_and_report",
        severity: severity === "none" ? "high" : severity,
        primary_category: primaryCategory,
        save_message: false,
        enqueue_admin_review: false,
        suspension_required: false,
        alert_room: false,
        remove_from_room: false,
        close_room_if_owner: false,
        visible_message_mode: "raw",
      };
    default:
      return {
        action: "allow",
        severity: "none",
        primary_category: null,
        save_message: true,
        enqueue_admin_review: false,
        suspension_required: false,
        alert_room: false,
        remove_from_room: false,
        close_room_if_owner: false,
        visible_message_mode: "raw",
      };
  }
}

async function loadReviewedModerationMemory(queryable, normalizedMessage) {
  const normalized = normalizeModerationText(normalizedMessage).normalized;
  if (!normalized) return null;

  const q = await queryable.query(
    `
    SELECT
      q.id AS queue_id,
      q.queue_status,
      q.reviewed_at,
      q.review_note,
      l.action_taken,
      l.detected_categories,
      l.severity
    FROM public.chat_moderation_queue q
    JOIN public.chat_moderation_logs l ON l.id = q.moderation_log_id
    WHERE l.normalized_message = $1
      AND q.queue_status IN ('confirmed', 'dismissed', 'suspended')
    ORDER BY q.reviewed_at DESC NULLS LAST, q.id DESC
    LIMIT 1
    `,
    [normalized]
  );

  if (q.rowCount === 0) return null;
  const row = q.rows[0];
  return {
    queueId: Number(row.queue_id ?? 0),
    queueStatus: String(row.queue_status ?? "").trim().toLowerCase(),
    reviewedAt: row.reviewed_at ?? null,
    reviewNote: String(row.review_note ?? "").trim() || null,
    actionTaken: String(row.action_taken ?? "").trim().toLowerCase() || "allow",
    detectedCategories: sanitizeModerationStringList(row.detected_categories),
    severity: String(row.severity ?? "").trim().toLowerCase() || "none",
  };
}

async function applyReviewedModerationMemory(queryable, moderation) {
  const memory = await loadReviewedModerationMemory(
    queryable,
    moderation?.normalized_message
  ).catch(() => null);
  if (!memory) return moderation;

  const rememberedCategories =
    memory.detectedCategories.length > 0
      ? memory.detectedCategories
      : sanitizeModerationStringList(moderation?.categories);
  const primaryCategory = rememberedCategories[0] ?? null;
  const decision =
    memory.queueStatus === "dismissed"
      ? buildStoredModerationDecision("allow")
      : buildStoredModerationDecision(memory.actionTaken, {
          severity: memory.severity,
          primaryCategory,
        });

  return {
    ...moderation,
    categories: rememberedCategories,
    decision,
    needs_human_review: false,
    reviewed_memory: {
      queue_id: memory.queueId,
      queue_status: memory.queueStatus,
      reviewed_at: memory.reviewedAt,
      review_note: memory.reviewNote,
      applied: true,
    },
  };
}

function extractAutoLearnTermsFromQueueItem(queueItem) {
  const terms = new Map();
  const addTerm = (value) => {
    const raw = String(value ?? "").trim();
    const normalized = normalizeVocabularyTerm(raw);
    if (!normalized || normalized.length < 2) return;
    if (!terms.has(normalized)) {
      terms.set(normalized, raw);
    }
  };

  addTerm(queueItem?.raw_message);

  for (const hit of Array.isArray(queueItem?.rule_hits) ? queueItem.rule_hits : []) {
    addTerm(hit?.matched_value);
  }

  const aiSuggestedGroups = [
    queueItem?.ai_result_json?.gemini?.result?.suggested_terms,
    queueItem?.ai_result_json?.openai_reasoned?.result?.suggested_terms,
    queueItem?.ai_result_json?.openai_reasoned?.suggested_terms,
  ];
  for (const group of aiSuggestedGroups) {
    for (const value of Array.isArray(group) ? group : []) {
      addTerm(value);
    }
  }

  return Array.from(terms.values()).slice(0, 12);
}

async function applyConfirmedQueueItemToVocabulary(client, queueItem) {
  const categories = sanitizeModerationStringList(queueItem?.detected_categories);
  const primaryCategory = categories[0] ?? null;
  if (!primaryCategory) return [];

  const terms = extractAutoLearnTermsFromQueueItem(queueItem);
  const appliedTerms = [];

  for (const rawTerm of terms) {
    const normalizedTerm = normalizeVocabularyTerm(rawTerm);
    if (!normalizedTerm || normalizedTerm.length < 2) continue;
    const language = detectVocabularyLanguage(rawTerm);
    await client.query(
      `
      INSERT INTO public.moderation_vocabulary
        (term, normalized_term, language, category, severity, is_active, source, created_at, updated_at)
      VALUES
        ($1, $2, $3, $4, $5, TRUE, 'admin_confirmed', NOW(), NOW())
      ON CONFLICT (normalized_term, category, language)
      DO UPDATE SET
        term = EXCLUDED.term,
        severity = EXCLUDED.severity,
        is_active = TRUE,
        source = 'admin_confirmed',
        updated_at = NOW()
      `,
      [
        rawTerm,
        normalizedTerm,
        language,
        primaryCategory,
        String(queueItem?.severity ?? "").trim().toLowerCase() || "medium",
      ]
    );
    appliedTerms.push(normalizedTerm);
  }

  return appliedTerms;
}

function normalizeSpotProvince(rawProvince, rawLocation) {
  const province = canonicalizeProvinceName(rawProvince);
  if (province) return province;

  const location = String(rawLocation ?? "").trim();
  if (!location || looksLikeCoordinateText(location)) return "";

  const parts = location.split(",").map((part) => part.trim()).filter(Boolean);
  return parts.length > 1 ? canonicalizeProvinceName(parts[parts.length - 1]) : "";
}

function canonicalizeProvinceName(rawValue) {
  const province = String(rawValue ?? "").trim();
  if (!province) return "";

  const normalized = province
    .toLowerCase()
    .replace(/^province\s+/i, "")
    .replace(/^จังหวัด/, "")
    .replace(/\s+/g, " ")
    .trim();

  if (
    normalized === "bangkok" ||
    normalized === "krung thep maha nakhon" ||
    normalized === "krungthepmahanakhon" ||
    normalized === "กรุงเทพมหานคร"
  ) {
    return "Bangkok";
  }

  return province;
}

function normalizeSpotDistrict(rawDistrict, rawLocation, rawProvince) {
  const district = String(rawDistrict ?? "").trim();
  if (district) return district;

  const location = String(rawLocation ?? "").trim();
  if (!location || looksLikeCoordinateText(location)) return "";

  const province = normalizeSpotProvince(rawProvince, rawLocation);
  const parts = location
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean);

  if (parts.length >= 3) {
    return parts[parts.length - 2];
  }

  if (parts.length === 2 && province && parts[1].toLowerCase() === province.toLowerCase()) {
    return parts[0];
  }

  return "";
}

function normalizeSpotNumber(rawValue, fallback = 0) {
  const value = Number(rawValue);
  if (!Number.isFinite(value)) return fallback;
  return value;
}

function normalizeSpotInt(rawValue, fallback = 0) {
  const value = Number(rawValue);
  if (!Number.isFinite(value)) return fallback;
  return Math.max(0, Math.trunc(value));
}

function normalizeSpotCoordinate(rawValue, { min, max, fieldName }) {
  if (rawValue == null) return null;
  const valueText = String(rawValue).trim();
  if (!valueText) return null;

  const value = Number(valueText);
  if (!Number.isFinite(value)) {
    throw new Error(`${fieldName} must be a valid number`);
  }
  if (value < min || value > max) {
    throw new Error(`${fieldName} must be between ${min} and ${max}`);
  }
  return value;
}

function isBlankText(value) {
  return String(value ?? "").trim() === "";
}

function looksLikeCoordinateText(value) {
  const text = String(value ?? "").trim();
  if (!text) return false;
  if (/lat|lng|latitude|longitude/i.test(text)) return true;
  return /^-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?$/.test(text);
}

function containsThaiCharacters(value) {
  return /[\u0E00-\u0E7F]/.test(String(value ?? "").trim());
}

function normalizeHumanReadableLocation(value) {
  const text = String(value ?? "").trim();
  if (!text || looksLikeCoordinateText(text)) return "";
  return text;
}

function getAddressComponent(components, types) {
  if (!Array.isArray(components) || components.length === 0) return "";
  for (const component of components) {
    if (!component || !Array.isArray(component.types)) continue;
    if (types.some((type) => component.types.includes(type))) {
      const longValue = String(component.long_name ?? "").trim();
      const shortValue = String(component.short_name ?? "").trim();
      const preferredValue =
        (!containsThaiCharacters(longValue) && longValue) ||
        (!containsThaiCharacters(shortValue) && shortValue) ||
        longValue ||
        shortValue;
      if (preferredValue) return preferredValue;
    }
  }
  return "";
}

async function reverseGeocodeCoordinates(latitude, longitude) {
  const apiKey = String(process.env.GOOGLE_MAPS_API_KEY ?? "").trim();
  if (!apiKey) return null;
  if (!Number.isFinite(latitude) || !Number.isFinite(longitude)) return null;

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);

  try {
    const url = new URL("https://maps.googleapis.com/maps/api/geocode/json");
    url.searchParams.set("latlng", `${latitude},${longitude}`);
    url.searchParams.set("key", apiKey);
    url.searchParams.set("language", "en");

    const response = await fetch(url, {
      method: "GET",
      signal: controller.signal,
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    const payload = await response.json();
    if (payload?.status !== "OK" || !Array.isArray(payload.results) || payload.results.length === 0) {
      return null;
    }

    const result = payload.results[0] ?? {};
    const components = Array.isArray(result.address_components)
      ? result.address_components
      : [];

    const province = getAddressComponent(components, ["administrative_area_level_1"]);
    const district =
      getAddressComponent(components, ["locality"]) ||
      getAddressComponent(components, ["sublocality_level_1"]) ||
      getAddressComponent(components, ["sublocality"]) ||
      getAddressComponent(components, ["administrative_area_level_2"]) ||
      getAddressComponent(components, ["administrative_area_level_3"]);

    const formattedAddress = String(result.formatted_address ?? "").trim();

    return {
      province,
      district,
      formattedAddress,
    };
  } finally {
    clearTimeout(timeout);
  }
}

async function enrichSpotLocationFields({
  location,
  province,
  district,
  locationLat,
  locationLng,
}) {
  let nextLocation = normalizeHumanReadableLocation(location);
  let nextProvince = String(province ?? "").trim();
  let nextDistrict = String(district ?? "").trim();

  try {
    const reverse = await reverseGeocodeCoordinates(locationLat, locationLng);
    if (reverse) {
      nextProvince = reverse.province || nextProvince;
      nextDistrict = reverse.district || nextDistrict;
      if (isBlankText(nextLocation) &&
          !isBlankText(reverse.formattedAddress)) {
        nextLocation = normalizeHumanReadableLocation(reverse.formattedAddress);
      }
    }
  } catch (geoErr) {
    console.warn("Spot reverse geocoding skipped:", geoErr?.message || geoErr);
  }

  return {
    location: normalizeHumanReadableLocation(nextLocation),
    province: normalizeSpotProvince(nextProvince, nextLocation),
    district: normalizeSpotDistrict(nextDistrict, nextLocation, nextProvince),
  };
}

async function enrichEventLocationFields({
  meetingPoint,
  locationName,
  city,
  province,
  district,
  latitude,
  longitude,
}) {
  let nextLocationName = normalizeHumanReadableLocation(locationName);
  let nextCity = String(city ?? "").trim();
  let nextProvince = String(province ?? "").trim();
  let nextDistrict = String(district ?? "").trim();

  try {
    const reverse = await reverseGeocodeCoordinates(latitude, longitude);
    if (reverse) {
      nextProvince = reverse.province || nextProvince;
      nextDistrict = reverse.district || nextDistrict;
      nextCity = reverse.district || nextCity;
      if ((isBlankText(nextLocationName) ||
          nextLocationName === String(meetingPoint ?? "").trim()) &&
          !isBlankText(reverse.formattedAddress)) {
        nextLocationName = normalizeHumanReadableLocation(reverse.formattedAddress);
      }
    }
  } catch (geoErr) {
    console.warn("Event reverse geocoding skipped:", geoErr?.message || geoErr);
  }

  return {
    locationName:
      normalizeHumanReadableLocation(nextLocationName) ||
      normalizeHumanReadableLocation(meetingPoint),
    city: nextCity,
    province: nextProvince,
    district: nextDistrict,
  };
}

function getSpotLeaveReasonMeta(reasonCode, creatorUserId, customReasonText = null) {
  const code = String(reasonCode ?? "").trim().toUpperCase();
  const customText = String(customReasonText ?? "").trim();
  const map = {
    SCHEDULE_CONFLICT: {
      reason_text: "Schedule conflict",
      category: "NON_BEHAVIOR",
      reported_target_type: "none",
      reported_target_user_id: null,
    },
    LOCATION_TOO_FAR: {
      reason_text: "Location too far",
      category: "NON_BEHAVIOR",
      reported_target_type: "none",
      reported_target_user_id: null,
    },
    NO_LONGER_INTERESTED: {
      reason_text: "No longer interested",
      category: "NON_BEHAVIOR",
      reported_target_type: "none",
      reported_target_user_id: null,
    },
    HEALTH_INJURY: {
      reason_text: "Health / injury",
      category: "NON_BEHAVIOR",
      reported_target_type: "none",
      reported_target_user_id: null,
    },
    FOUND_ANOTHER_ACTIVITY: {
      reason_text: "Found another activity",
      category: "NON_BEHAVIOR",
      reported_target_type: "none",
      reported_target_user_id: null,
    },
    HOST_PROBLEM_PARTICIPANTS: {
      reason_text: "Host/problem with participants",
      report_detail_text: customText || null,
      category: "BEHAVIOR_SAFETY",
      reported_target_type: "participant",
      reported_target_user_id: null,
    },
    SAFETY_CONCERN: {
      reason_text: "Safety concern",
      report_detail_text: customText || null,
      category: "BEHAVIOR_SAFETY",
      reported_target_type: "none",
      reported_target_user_id: null,
    },
    OTHER: {
      reason_text: customText || "Other",
      report_detail_text: customText || null,
      category: "NON_BEHAVIOR",
      reported_target_type: "none",
      reported_target_user_id: null,
    },
    CHANGE_MIND_OTHER_ACTIVITY: {
      reason_text: "I changed my mind to join another activity",
      category: "NON_BEHAVIOR",
      reported_target_type: "none",
      reported_target_user_id: null,
    },
    NOT_AVAILABLE: {
      reason_text: "I am not available",
      category: "NON_BEHAVIOR",
      reported_target_type: "none",
      reported_target_user_id: null,
    },
    CREATOR_UNDESIRABLE_BEHAVIOR: {
      reason_text: "The spot creator has undesirable behavior",
      report_detail_text: customText || null,
      category: "BEHAVIOR_SAFETY",
      reported_target_type: "creator",
      reported_target_user_id: creatorUserId ?? null,
    },
    PARTICIPANT_UNDESIRABLE_BEHAVIOR: {
      reason_text: "Other participants have undesirable behavior",
      report_detail_text: customText || null,
      category: "BEHAVIOR_SAFETY",
      reported_target_type: "participant",
      reported_target_user_id: null,
    },
    DONT_TRUST_ACTIVITY: {
      reason_text: "I do not trust this activity",
      report_detail_text: customText || null,
      category: "BEHAVIOR_SAFETY",
      reported_target_type: "none",
      reported_target_user_id: null,
    },
    UNSAFE_LOCATION: {
      reason_text: "The location feels unsafe / secluded",
      report_detail_text: customText || null,
      category: "BEHAVIOR_SAFETY",
      reported_target_type: "none",
      reported_target_user_id: null,
    },
  };

  return map[code] || null;
}

async function listSpotRows(client, { userId = null, onlyJoined = false, spotId = null } = {}) {
  const params = [userId];
  const filters = [];

  if (spotId != null) {
    params.push(spotId);
    filters.push(`se.id = $${params.length}`);
  }

  if (onlyJoined) {
    filters.push(`$1::bigint IS NOT NULL`);
    filters.push(`
      EXISTS (
        SELECT 1
        FROM public.spot_event_members sem_only
        WHERE sem_only.spot_event_id = se.id
          AND sem_only.user_id = $1
      )
    `);
  }

  const whereClause = filters.length > 0 ? `WHERE ${filters.join(" AND ")}` : "";
  const q = await client.query(
    `
    SELECT
      se.id,
      COALESCE(NULLIF(TRIM(se.display_code), ''), CONCAT('SP', LPAD(se.id::text, 6, '0'))) AS display_code,
      se.title,
      se.description,
      se.location,
      se.location_link,
      se.location_lat,
      se.location_lng,
      se.province,
      se.district,
      se.event_date,
      se.event_time,
      se.km_per_round,
      se.round_count,
      (COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0))::numeric AS total_distance,
      se.max_people,
      se.image_base64,
      COALESCE(
        (
          SELECT sem.file_url
          FROM public.spot_event_media sem
          WHERE sem.spot_event_id = se.id
            AND sem.kind = 'cover'
          ORDER BY sem.sort_order ASC NULLS LAST, sem.id DESC
          LIMIT 1
        ),
        (
          SELECT sem.file_url
          FROM public.spot_event_media sem
          WHERE sem.spot_event_id = se.id
            AND sem.kind = 'gallery'
          ORDER BY sem.sort_order ASC NULLS LAST, sem.id ASC
          LIMIT 1
        ),
        se.image_url
      ) AS image_url,
      se.status,
      se.created_by_user_id,
      se.creator_role,
      se.created_at,
      se.updated_at,
      se.owner_completed_at,
      se.owner_completed_distance_km,
      COALESCE(member_counts.joined_count, 0) AS joined_count,
      (
        SELECT sem_self.completed_at
        FROM public.spot_event_members sem_self
        WHERE sem_self.spot_event_id = se.id
          AND sem_self.user_id = $1
        ORDER BY sem_self.id DESC
        LIMIT 1
      ) AS completed_at,
      (
        SELECT sem_self.completed_distance_km
        FROM public.spot_event_members sem_self
        WHERE sem_self.spot_event_id = se.id
          AND sem_self.user_id = $1
        ORDER BY sem_self.id DESC
        LIMIT 1
      ) AS completed_distance_km,
      EXISTS (
        SELECT 1
        FROM public.spot_event_bookings seb_self
        WHERE seb_self.spot_event_id = se.id
          AND seb_self.user_id = $1
      ) AS is_booked,
      (
        SELECT seb_self.booking_reference
        FROM public.spot_event_bookings seb_self
        WHERE seb_self.spot_event_id = se.id
          AND seb_self.user_id = $1
        ORDER BY seb_self.id DESC
        LIMIT 1
      ) AS booking_reference,
      EXISTS (
        SELECT 1
        FROM public.spot_event_members sem_self
        WHERE sem_self.spot_event_id = se.id
          AND sem_self.user_id = $1
      ) AS is_joined,
      COALESCE(
        NULLIF(TRIM(COALESCE(u.name, '')), ''),
        NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''),
        NULLIF(TRIM(COALESCE(u.email, '')), ''),
        NULLIF(TRIM(COALESCE(au.email, '')), ''),
        CASE WHEN se.creator_role = 'admin' THEN 'Admin' ELSE 'User' END
      ) AS creator_name
    FROM public.spot_events se
    LEFT JOIN (
      SELECT spot_event_id, COUNT(*)::int AS joined_count
      FROM public.spot_event_members
      GROUP BY spot_event_id
    ) member_counts
      ON member_counts.spot_event_id = se.id
    LEFT JOIN public.users u
      ON se.creator_role = 'user'
     AND u.id = se.created_by_user_id
    LEFT JOIN public.admin_users au
      ON se.creator_role = 'admin'
     AND au.id = se.created_by_user_id
    ${whereClause}
    ORDER BY se.created_at DESC, se.id DESC
    `,
    params
  );

  const rows = [];
  for (const row of q.rows) {
      let nextRow = {
      ...row,
      province: normalizeSpotProvince(row.province, row.location),
      district: normalizeSpotDistrict(row.district, row.location, row.province),
      spot_key: buildSpotChatKey(row),
    };

    const hasCoordinates =
      Number.isFinite(Number(row.location_lat)) && Number.isFinite(Number(row.location_lng));
    const needsGeocode =
      hasCoordinates &&
      (isBlankText(nextRow.province) ||
        isBlankText(nextRow.district) ||
        isBlankText(nextRow.location) ||
        looksLikeCoordinateText(nextRow.location));

    if (needsGeocode) {
      const enriched = await enrichSpotLocationFields({
        location: nextRow.location,
        province: nextRow.province,
        district: nextRow.district,
        locationLat: Number(row.location_lat),
        locationLng: Number(row.location_lng),
      }).catch((geoErr) => {
        console.warn("Spot read geocoding skipped:", geoErr?.message || geoErr);
        return null;
      });

      if (enriched) {
        nextRow = {
          ...nextRow,
          location: enriched.location,
          province: enriched.province,
          district: enriched.district,
        };

        const prevLocation = String(row.location ?? "").trim();
        const prevProvince = String(row.province ?? "").trim();
        const prevDistrict = String(row.district ?? "").trim();
        const nextLocation = String(enriched.location ?? "").trim();
        const nextProvince = String(enriched.province ?? "").trim();
        const nextDistrict = String(enriched.district ?? "").trim();

        if (
          prevLocation !== nextLocation ||
          prevProvince !== nextProvince ||
          prevDistrict !== nextDistrict
        ) {
          await client.query(
            `
            UPDATE public.spot_events
            SET
              location = CASE
                WHEN COALESCE(TRIM(location), '') = ''
                  OR location ~* '(lat|lng|latitude|longitude)'
                THEN $1
                ELSE location
              END,
              province = CASE
                WHEN COALESCE(TRIM(province), '') = '' THEN $2
                ELSE province
              END,
              district = CASE
                WHEN COALESCE(TRIM(district), '') = '' THEN $3
                ELSE district
              END,
              updated_at = NOW()
            WHERE id = $4
            `,
            [nextLocation || null, nextProvince || null, nextDistrict || null, row.id]
          );
        }
      }
    }

    rows.push(nextRow);
  }

  return rows;
}

function toAbsoluteUrl(req, rawValue) {
  const value = String(rawValue ?? "").trim();
  if (!value) return null;
  if (/^https?:\/\//i.test(value)) return value;
  const base = `${req.protocol}://${req.get("host")}`;
  return value.startsWith("/") ? `${base}${value}` : `${base}/${value}`;
}

function normalizeMethodType(rawValue) {
  const value = String(rawValue ?? "").trim().toUpperCase();
  if (value === "PROMPTPAY") return "PROMPTPAY";
  if (value === "ALIPAY") return "ALIPAY";
  return value || null;
}

function normalizeProvider(rawValue) {
  const value = String(rawValue ?? "").trim().toUpperCase();
  if (value === "STRIPE") return "STRIPE";
  if (value === "AIRWALLEX_ALIPAY") return "AIRWALLEX_ALIPAY";
  if (value === "MANUAL") return "MANUAL";
  if (value === "MANUAL_QR") return "MANUAL_QR";
  return value || null;
}

function isAirwallexEnabled() {
  return airwallex.isConfigured();
}

function isAntomEnabled() {
  return antom.isConfigured();
}

function getConfiguredAlipayProvider() {
  const explicitProvider = String(process.env.ALIPAY_PROVIDER ?? "").trim().toLowerCase();
  if (explicitProvider === "airwallex") return "airwallex";
  if (explicitProvider === "antom") return "antom";
  if (isAirwallexEnabled()) return "airwallex";
  if (isAntomEnabled()) return "antom";
  return null;
}

function getAutomaticAlipayProviderKey() {
  const configuredProvider = getConfiguredAlipayProvider();
  if (configuredProvider === "antom") return "antom_alipay";
  if (configuredProvider === "airwallex") return "airwallex_alipay";
  return null;
}

function getAutomaticAlipayProviderLabel() {
  const providerKey = getAutomaticAlipayProviderKey();
  if (providerKey === "antom_alipay") return "Antom";
  if (providerKey === "airwallex_alipay") return "Airwallex";
  return null;
}

function getAirwallexAlipayCapabilityStatus() {
  const rawValue = String(process.env.AIRWALLEX_ALIPAY_ENABLED ?? "").trim().toLowerCase();
  const capabilityFlagEnabled = ["1", "true", "yes", "on"].includes(rawValue);
  const airwallexConfigured = isAirwallexEnabled();
  const configuredProvider = getConfiguredAlipayProvider();

  if (!airwallexConfigured) {
    return {
      available: false,
      reason: "airwallex_not_configured",
      airwallexConfigured,
      capabilityFlagEnabled,
      providerKey: getAutomaticAlipayProviderKey(),
      providerLabel: getAutomaticAlipayProviderLabel(),
      configuredProvider,
    };
  }
  if (!capabilityFlagEnabled) {
    return {
      available: false,
      reason: "env_flag_off",
      airwallexConfigured,
      capabilityFlagEnabled,
      providerKey: getAutomaticAlipayProviderKey(),
      providerLabel: getAutomaticAlipayProviderLabel(),
      configuredProvider,
    };
  }

  return {
    available: true,
    reason: null,
    airwallexConfigured,
    capabilityFlagEnabled,
    providerKey: getAutomaticAlipayProviderKey(),
    providerLabel: getAutomaticAlipayProviderLabel(),
    configuredProvider,
  };
}

function getAntomAlipayCapabilityStatus() {
  const rawValue = String(process.env.ANTOM_ALIPAY_ENABLED ?? "").trim().toLowerCase();
  const capabilityFlagEnabled = ["1", "true", "yes", "on"].includes(rawValue);
  const antomConfigured = isAntomEnabled();
  const configuredProvider = getConfiguredAlipayProvider();

  if (!antomConfigured) {
    return {
      available: false,
      reason: "antom_not_configured",
      antomConfigured,
      capabilityFlagEnabled,
      providerKey: getAutomaticAlipayProviderKey(),
      providerLabel: getAutomaticAlipayProviderLabel(),
      configuredProvider,
    };
  }
  if (!capabilityFlagEnabled) {
    return {
      available: false,
      reason: "env_flag_off",
      antomConfigured,
      capabilityFlagEnabled,
      providerKey: getAutomaticAlipayProviderKey(),
      providerLabel: getAutomaticAlipayProviderLabel(),
      configuredProvider,
    };
  }

  return {
    available: true,
    reason: null,
    antomConfigured,
    capabilityFlagEnabled,
    providerKey: getAutomaticAlipayProviderKey(),
    providerLabel: getAutomaticAlipayProviderLabel(),
    configuredProvider,
  };
}

function getSelectedAlipayCapabilityStatus() {
  const configuredProvider = getConfiguredAlipayProvider();
  if (configuredProvider === "antom") {
    return getAntomAlipayCapabilityStatus();
  }
  return getAirwallexAlipayCapabilityStatus();
}

function isAirwallexAlipayEnabled() {
  return getSelectedAlipayCapabilityStatus().available;
}

function getAutomaticAlipayAvailability(eventRow) {
  if (!eventRow?.enable_alipay) {
    return { available: false, reason: "event_not_enabled" };
  }
  if (!isStripeBranchAllowed(eventRow)) {
    return { available: false, reason: "payment_mode_not_supported" };
  }
  if (!eventRow?.stripe_enabled) {
    return { available: false, reason: "provider_payments_disabled" };
  }

  const capability = getSelectedAlipayCapabilityStatus();
  if (!capability.available) {
    return {
      available: false,
      reason: capability.reason,
      airwallexConfigured: capability.airwallexConfigured,
      capabilityFlagEnabled: capability.capabilityFlagEnabled,
      providerKey: capability.providerKey,
      providerLabel: capability.providerLabel,
    };
  }

  return {
    available: true,
    reason: null,
    airwallexConfigured: capability.airwallexConfigured,
    capabilityFlagEnabled: capability.capabilityFlagEnabled,
    providerKey: capability.providerKey,
    providerLabel: capability.providerLabel,
  };
}

const PROVIDER_PENDING_TIMEOUT_MINUTES = 15;

function normalizeLocalPaymentStatus(rawValue) {
  return String(rawValue ?? "").trim().toLowerCase();
}

function isPendingLikeLocalPaymentStatus(rawValue) {
  return [
    "pending",
    "processing",
    "requires_action",
    "requires_payment_method",
    "awaiting_provider",
  ].includes(normalizeLocalPaymentStatus(rawValue));
}

function isTerminalLocalPaymentStatus(rawValue) {
  return [
    "paid",
    "completed",
    "success",
    "succeeded",
    "done",
    "failed",
    "cancelled",
    "canceled",
    "expired",
  ].includes(normalizeLocalPaymentStatus(rawValue));
}

function getPaymentAgeMinutes(paymentRow, now = new Date()) {
  const createdAt = paymentRow?.created_at ? new Date(paymentRow.created_at) : null;
  if (!createdAt || Number.isNaN(createdAt.getTime())) return 0;
  return Math.max(0, (now.getTime() - createdAt.getTime()) / 60000);
}

function hasProviderPaymentTimedOut(paymentRow, timeoutMinutes = PROVIDER_PENDING_TIMEOUT_MINUTES) {
  const provider = String(paymentRow?.provider ?? "").trim().toLowerCase();
  if (provider !== "airwallex_alipay") return false;
  if (!isPendingLikeLocalPaymentStatus(paymentRow?.status)) return false;
  return getPaymentAgeMinutes(paymentRow) >= timeoutMinutes;
}

function isTimedOutPaymentRow(paymentRow) {
  return (
    hasProviderPaymentTimedOut(paymentRow) ||
    String(paymentRow?.failure_code ?? "").trim().toLowerCase() === "payment_timeout"
  );
}

function normalizeAirwallexIntentStatus(rawValue) {
  return String(rawValue ?? "").trim().toUpperCase();
}

function mapAirwallexIntentStatusToLocal(rawValue) {
  const status = normalizeAirwallexIntentStatus(rawValue);
  if (status === "SUCCEEDED") return "paid";
  if (status === "FAILED") return "failed";
  if (status === "EXPIRED") return "cancelled";
  if (["CANCELLED", "CANCELED"].includes(status)) return "cancelled";
  if ([
    "REQUIRES_PAYMENT_METHOD",
    "REQUIRES_CUSTOMER_ACTION",
    "PENDING",
    "PENDING_CAPTURE",
    "REQUIRES_CAPTURE",
  ].includes(status)) {
    return "pending";
  }
  return "pending";
}

function buildAirwallexReturnUrl(req, paymentId) {
  const configured =
    String(process.env.ALIPAY_RETURN_URL ?? "").trim() ||
    String(process.env.AIRWALLEX_RETURN_URL ?? "").trim() ||
    `${req.protocol}://${req.get("host")}/payment/alipay-return`;
  try {
    const url = new URL(configured);
    if (!url.searchParams.has("payment_id") && Number.isFinite(Number(paymentId)) && Number(paymentId) > 0) {
      url.searchParams.set("payment_id", String(paymentId));
    }
    return url.toString();
  } catch (_) {
    return configured;
  }
}

function extractAirwallexErrorMessage(payload, fallback = "Airwallex payment failed") {
  const candidates = [
    payload?.message,
    payload?.error?.message,
    payload?.latest_payment_attempt?.error?.message,
    payload?.latest_payment_attempt?.failure_reason,
    payload?.failure_reason,
    payload?.status_reason,
  ];
  for (const candidate of candidates) {
    const text = String(candidate ?? "").trim();
    if (text) return text;
  }
  return fallback;
}

function extractAntomErrorMessage(payload, fallback = "Antom payment failed") {
  const candidates = [
    payload?.result?.resultMessage,
    payload?.resultMessage,
    payload?.message,
    payload?.paymentResult?.resultMessage,
  ];
  for (const candidate of candidates) {
    const text = String(candidate ?? "").trim();
    if (text) return text;
  }
  return fallback;
}

function extractAirwallexErrorCode(payload) {
  const candidates = [
    payload?.code,
    payload?.error?.code,
    payload?.latest_payment_attempt?.error?.code,
    payload?.latest_payment_attempt?.failure_code,
    payload?.failure_code,
    payload?.status_code,
  ];
  for (const candidate of candidates) {
    const text = String(candidate ?? "").trim();
    if (text) return text;
  }
  return null;
}

function extractAntomErrorCode(payload) {
  const candidates = [
    payload?.result?.resultCode,
    payload?.resultCode,
    payload?.paymentResult?.resultCode,
  ];
  for (const candidate of candidates) {
    const text = String(candidate ?? "").trim();
    if (text) return text;
  }
  return null;
}

function isAirwallexAlipayNotEnabledError(payload) {
  return String(extractAirwallexErrorCode(payload) ?? "").trim().toLowerCase() === "payment_method_not_allowed";
}

function isAntomAlipayNotEnabledError(payload) {
  return String(extractAntomErrorCode(payload) ?? "").trim().toUpperCase() === "ACCESS_DENIED";
}

function mapAirwallexAppError(payload, fallbackMessage) {
  const providerCode = extractAirwallexErrorCode(payload);
  if (isAirwallexAlipayNotEnabledError(payload)) {
    return {
      httpStatus: 409,
      code: "airwallex_alipay_not_enabled",
      providerCode,
      message: "Alipay is not enabled on this Airwallex account yet.",
    };
  }
  return {
    httpStatus: 500,
    code: "airwallex_payment_error",
    providerCode,
    message: extractAirwallexErrorMessage(payload, fallbackMessage),
  };
}

function mapAntomAppError(payload, fallbackMessage) {
  const providerCode = extractAntomErrorCode(payload);
  if (isAntomAlipayNotEnabledError(payload)) {
    return {
      httpStatus: 409,
      code: "antom_alipay_not_enabled",
      providerCode,
      message: "Alipay is not enabled on this Antom account yet.",
    };
  }
  return {
    httpStatus: 500,
    code: "antom_payment_error",
    providerCode,
    message: extractAntomErrorMessage(payload, fallbackMessage),
  };
}

function getAirwallexNextActionUrl(payload) {
  const candidates = [
    payload?.next_action?.url,
    payload?.next_action?.redirect_url,
    payload?.payment_method?.next_action?.url,
    payload?.payment_method_options?.alipaycn?.qr_code_url,
  ];
  for (const candidate of candidates) {
    const text = String(candidate ?? "").trim();
    if (text) return text;
  }
  return null;
}

function getAntomNextActionUrl(payload) {
  const candidates = [
    payload?.normalUrl,
    payload?.paymentRedirectUrl,
    payload?.paymentActionForm?.paymentRedirectUrl,
    payload?.paymentActionForm?.redirectUrl,
    payload?.paymentActionForm?.url,
  ];
  for (const candidate of candidates) {
    const text = String(candidate ?? "").trim();
    if (text) return text;
  }
  return null;
}

function getAntomQrUrl(payload) {
  const candidates = [
    payload?.paymentActionForm?.qrCodeUrl,
    payload?.paymentActionForm?.codeValue,
    payload?.qrCodeUrl,
  ];
  for (const candidate of candidates) {
    const text = String(candidate ?? "").trim();
    if (text) return text;
  }
  return null;
}

function getAirwallexQrUrl(payload) {
  const candidates = [
    payload?.payment_method_options?.alipaycn?.qr_code_url,
    payload?.next_action?.qr_code_url,
  ];
  for (const candidate of candidates) {
    const text = String(candidate ?? "").trim();
    if (text) return text;
  }
  return null;
}

function parseGatewayPayload(rawValue) {
  if (!rawValue) return null;
  if (typeof rawValue === "object") return rawValue;
  try {
    return JSON.parse(String(rawValue));
  } catch (_) {
    return null;
  }
}

function buildAirwallexHostedPaymentResponse(req, paymentRow, gatewayPayload = null, overrides = {}) {
  const payload = gatewayPayload ?? parseGatewayPayload(paymentRow?.raw_gateway_payload) ?? {};
  const checkoutUrl = getAirwallexNextActionUrl(payload);
  const qrUrl = getAirwallexQrUrl(payload);
  return {
    ok: true,
    payment_id: paymentRow?.id ?? null,
    booking_id: paymentRow?.booking_id ?? null,
    booking_reference: paymentRow?.booking_reference ?? null,
    payment_reference: paymentRow?.payment_reference ?? null,
    amount: Number(paymentRow?.amount ?? 0),
    currency: String(paymentRow?.currency ?? "CNY").toUpperCase(),
    fx_rate_used: paymentRow?.fx_rate_used == null ? null : Number(paymentRow.fx_rate_used),
    payment_method_type: "alipay",
    provider: getAutomaticAlipayProviderKey() || "airwallex_alipay",
    provider_label: getAutomaticAlipayProviderLabel() || "Airwallex",
    provider_payment_intent_id:
      String(paymentRow?.provider_payment_intent_id ?? payload?.id ?? "").trim() || null,
    provider_txn_id:
      String(
        paymentRow?.provider_txn_id ??
        payload?.latest_payment_attempt?.id ??
        payload?.merchant_order_id ??
        ""
      ).trim() || null,
    status: paymentRow?.status ?? "pending",
    next_action: payload?.next_action ?? null,
    checkout_url: checkoutUrl,
    redirect_url: checkoutUrl,
    qr_url: qrUrl,
    return_url: buildAirwallexReturnUrl(req, paymentRow?.id),
    reused_existing_payment: overrides.reused_existing_payment === true,
    timed_out: isTimedOutPaymentRow(paymentRow),
    ...overrides,
  };
}

function buildAntomHostedPaymentResponse(req, paymentRow, gatewayPayload = null, overrides = {}) {
  const payload = gatewayPayload ?? parseGatewayPayload(paymentRow?.raw_gateway_payload) ?? {};
  const checkoutUrl = getAntomNextActionUrl(payload);
  const qrUrl = getAntomQrUrl(payload);
  return {
    ok: true,
    payment_id: paymentRow?.id ?? null,
    booking_id: paymentRow?.booking_id ?? null,
    booking_reference: paymentRow?.booking_reference ?? null,
    payment_reference: paymentRow?.payment_reference ?? null,
    amount: Number(paymentRow?.amount ?? 0),
    currency: String(paymentRow?.currency ?? "CNY").toUpperCase(),
    fx_rate_used: paymentRow?.fx_rate_used == null ? null : Number(paymentRow.fx_rate_used),
    payment_method_type: "alipay",
    provider: "antom_alipay",
    provider_label: "Antom",
    provider_payment_intent_id:
      String(
        paymentRow?.provider_payment_intent_id ??
        payload?.paymentId ??
        payload?.paymentRequestId ??
        ""
      ).trim() || null,
    provider_txn_id:
      String(
        paymentRow?.provider_txn_id ??
        payload?.paymentId ??
        payload?.paymentRequestId ??
        ""
      ).trim() || null,
    status: paymentRow?.status ?? "pending",
    next_action: payload?.paymentActionForm ?? null,
    checkout_url: checkoutUrl,
    redirect_url: checkoutUrl,
    qr_url: qrUrl,
    return_url: buildAirwallexReturnUrl(req, paymentRow?.id),
    reused_existing_payment: overrides.reused_existing_payment === true,
    timed_out: false,
    ...overrides,
  };
}

async function expireTimedOutAirwallexPayment(client, paymentRow, reason = null) {
  if (!hasProviderPaymentTimedOut(paymentRow)) {
    return {
      status: paymentRow?.status ?? null,
      changed: false,
      timedOut: false,
    };
  }
  const cancelledStatus = await pickEnumSafe(client, "payments", "status", "cancelled");
  const failureReason =
    reason ||
    `Payment session expired after ${PROVIDER_PENDING_TIMEOUT_MINUTES} minutes without completion.`;
  await client.query(
    `
    UPDATE payments
    SET
      status = $2,
      failure_code = COALESCE(NULLIF(TRIM(failure_code), ''), 'payment_timeout'),
      failure_reason = COALESCE(NULLIF(TRIM(failure_reason), ''), $3),
      updated_at = NOW()
    WHERE id = $1
      AND LOWER(COALESCE(status::text, '')) IN ('pending', 'processing', 'requires_action', 'requires_payment_method')
    `,
    [paymentRow.id, cancelledStatus, failureReason]
  );
  return {
    status: cancelledStatus,
    changed: true,
    timedOut: true,
  };
}

function getAirwallexEventType(payload) {
  return String(
    payload?.name ??
    payload?.type ??
    payload?.event_type ??
    ""
  ).trim();
}

const ALLOWED_AIRWALLEX_WEBHOOK_EVENT_TYPES = new Set([
  "payment_intent.created",
  "payment_intent.pending",
  "payment_intent.failed",
  "payment_intent.expired",
  "payment_intent.requires_customer_action",
  "payment_intent.requires_payment_method",
  "payment_intent.succeeded",
  "payment_intent.cancelled",
]);

function getAirwallexEventId(payload) {
  return String(payload?.id ?? payload?.event_id ?? "").trim();
}

function getAirwallexEventResource(payload) {
  if (payload?.data?.object && typeof payload.data.object === "object") return payload.data.object;
  if (payload?.data && typeof payload.data === "object") return payload.data;
  if (payload?.object && typeof payload.object === "object") return payload.object;
  return {};
}

function mapAntomPaymentStatusToLocal(rawValue) {
  const status = String(rawValue ?? "").trim().toUpperCase();
  if (status === "SUCCESS") return "paid";
  if (status === "FAIL") return "failed";
  if (status === "CANCELLED") return "cancelled";
  if (status === "PENDING") return "pending";
  if (status === "PROCESSING") return "pending";
  return "pending";
}

async function syncAntomPaymentRecord(client, paymentRow, payload) {
  const providerPaymentIntentId = String(
    payload?.paymentId ??
    payload?.paymentRequestId ??
    paymentRow?.provider_payment_intent_id ??
    ""
  ).trim() || null;
  const providerTxnId = String(
    payload?.paymentId ??
    payload?.paymentRequestId ??
    paymentRow?.provider_txn_id ??
    ""
  ).trim() || null;
  const mappedStatus = mapAntomPaymentStatusToLocal(payload?.paymentStatus);
  const failureCode = extractAntomErrorCode(payload);
  const failureReason = extractAntomErrorMessage(payload, "");
  const currentLocalStatus = normalizeLocalPaymentStatus(paymentRow?.status);

  if (mappedStatus === "paid" && currentLocalStatus === "paid") {
    await client.query(
      `
      UPDATE payments
      SET
        provider = 'antom_alipay',
        provider_payment_intent_id = COALESCE($2, provider_payment_intent_id),
        provider_txn_id = COALESCE($3, provider_txn_id, $2),
        raw_gateway_payload = COALESCE($4::jsonb, raw_gateway_payload),
        failure_code = NULL,
        failure_reason = NULL,
        paid_at = COALESCE(paid_at, NOW()),
        updated_at = NOW()
      WHERE id = $1
      `,
      [paymentRow.id, providerPaymentIntentId, providerTxnId, toJsonbParam(payload)]
    );
    await ensurePaymentReference(client, paymentRow.id);
    await ensureReceiptForPayment(client, {
      paymentId: paymentRow.id,
      amount: Number(paymentRow.amount ?? 0),
      currency: String(paymentRow.currency ?? "CNY").toUpperCase(),
    });
    return { status: "paid", changed: false };
  }

  if (["failed", "cancelled"].includes(mappedStatus) && currentLocalStatus === mappedStatus) {
    await client.query(
      `
      UPDATE payments
      SET
        provider = 'antom_alipay',
        provider_payment_intent_id = COALESCE($2, provider_payment_intent_id),
        provider_txn_id = COALESCE($3, provider_txn_id, $2),
        raw_gateway_payload = COALESCE($4::jsonb, raw_gateway_payload),
        failure_code = COALESCE($5, failure_code),
        failure_reason = COALESCE(NULLIF($6, ''), failure_reason),
        updated_at = NOW()
      WHERE id = $1
      `,
      [
        paymentRow.id,
        providerPaymentIntentId,
        providerTxnId,
        toJsonbParam(payload),
        failureCode,
        failureReason || null,
      ]
    );
    return { status: mappedStatus, changed: false };
  }

  if (mappedStatus === "paid") {
    const paidStatus = await pickEnumSafe(client, "payments", "status", "paid");
    const confirmedStatus = await pickEnumSafe(client, "bookings", "status", "confirmed");
    await client.query(
      `
      UPDATE payments
      SET
        status = $2,
        provider = 'antom_alipay',
        payment_method_type = COALESCE(payment_method_type, 'alipay'),
        provider_payment_intent_id = COALESCE($3, provider_payment_intent_id),
        provider_txn_id = COALESCE($4, provider_txn_id, $3),
        raw_gateway_payload = $5::jsonb,
        failure_code = NULL,
        failure_reason = NULL,
        paid_at = COALESCE(paid_at, NOW()),
        updated_at = NOW()
      WHERE id = $1
      `,
      [
        paymentRow.id,
        paidStatus,
        providerPaymentIntentId,
        providerTxnId,
        toJsonbParam(payload),
      ]
    );

    if (Number.isFinite(Number(paymentRow.booking_id)) && Number(paymentRow.booking_id) > 0) {
      await client.query(
        `
        UPDATE bookings
        SET status = $2, updated_at = NOW()
        WHERE id = $1
        `,
        [paymentRow.booking_id, confirmedStatus]
      );
      await ensureBookingReference(client, paymentRow.booking_id);
    }

    if (
      Number.isFinite(Number(paymentRow.event_id)) &&
      Number(paymentRow.event_id) > 0 &&
      Number.isFinite(Number(paymentRow.user_id)) &&
      Number(paymentRow.user_id) > 0
    ) {
      await ensureParticipantForBooking(client, {
        eventId: Number(paymentRow.event_id),
        userId: Number(paymentRow.user_id),
        bookingId: Number(paymentRow.booking_id),
      });
    }

    await ensureReceiptForPayment(client, {
      paymentId: paymentRow.id,
      amount: Number(paymentRow.amount ?? 0),
      currency: String(paymentRow.currency ?? "CNY").toUpperCase(),
    });
    return { status: paidStatus, changed: true };
  }

  if (mappedStatus === "failed" || mappedStatus === "cancelled") {
    const targetStatus = await pickEnumSafe(client, "payments", "status", mappedStatus);
    await client.query(
      `
      UPDATE payments
      SET
        status = $2,
        provider = 'antom_alipay',
        provider_payment_intent_id = COALESCE($3, provider_payment_intent_id),
        provider_txn_id = COALESCE($4, provider_txn_id, $3),
        raw_gateway_payload = $5::jsonb,
        failure_code = $6,
        failure_reason = $7,
        updated_at = NOW()
      WHERE id = $1
      `,
      [
        paymentRow.id,
        targetStatus,
        providerPaymentIntentId,
        providerTxnId,
        toJsonbParam(payload),
        failureCode,
        failureReason || null,
      ]
    );
    return { status: targetStatus, changed: true };
  }

  const pendingStatus = await pickEnumSafe(client, "payments", "status", "pending");
  await client.query(
    `
    UPDATE payments
    SET
      status = $2,
      provider = 'antom_alipay',
      provider_payment_intent_id = COALESCE($3, provider_payment_intent_id),
      provider_txn_id = COALESCE($4, provider_txn_id, $3),
      raw_gateway_payload = $5::jsonb,
      failure_code = NULL,
      failure_reason = NULL,
      updated_at = NOW()
    WHERE id = $1
    `,
    [
      paymentRow.id,
      pendingStatus,
      providerPaymentIntentId,
      providerTxnId,
      toJsonbParam(payload),
    ]
  );
  return { status: pendingStatus, changed: currentLocalStatus !== normalizeLocalPaymentStatus(pendingStatus) };
}

async function loadOwnedPaymentStatusRow(client, paymentId, userId) {
  const q = await client.query(
    `
    SELECT
      p.id,
      p.booking_id,
      b.booking_reference,
      p.event_id,
      COALESCE(p.user_id, b.user_id) AS user_id,
      COALESCE(p.amount, 0) AS amount,
      COALESCE(p.currency::text, b.currency::text, e.currency::text, 'THB') AS currency,
      COALESCE(p.fx_rate_used, e.exchange_rate_thb_per_cny) AS fx_rate_used,
      COALESCE(
        NULLIF(TRIM(p.payment_method_type::text), ''),
        NULLIF(TRIM(p.method_type::text), ''),
        UPPER(COALESCE(p.method::text, ''))
      ) AS method_type,
      COALESCE(p.provider::text, '') AS provider,
      p.status::text AS status,
      p.paid_at,
      p.payment_reference,
      p.provider_txn_id,
      p.provider_charge_id,
      p.provider_payment_intent_id,
      p.stripe_payment_intent_id,
      p.stripe_checkout_session_id,
      p.failure_code,
      p.failure_reason,
      p.created_at,
      p.raw_gateway_payload,
      COALESCE(r.pdf_url, to_jsonb(p)->>'receipt_url') AS receipt_url,
      to_jsonb(p)->>'slip_url' AS slip_url,
      r.receipt_no,
      r.issue_date AS receipt_issue_date,
      e.title AS event_title
    FROM payments p
    LEFT JOIN bookings b ON b.id = p.booking_id
    LEFT JOIN events e ON e.id = COALESCE(p.event_id, b.event_id)
    LEFT JOIN LATERAL (
      SELECT r1.receipt_no, r1.issue_date, r1.pdf_url
      FROM receipts r1
      WHERE r1.payment_id = p.id
      ORDER BY r1.issue_date DESC NULLS LAST, r1.id DESC
      LIMIT 1
    ) r ON TRUE
    WHERE p.id = $1
      AND COALESCE(p.user_id, b.user_id) = $2
    LIMIT 1
    `,
    [paymentId, userId]
  );
  return q.rows[0] ?? null;
}

function buildPaymentStatusResponse(req, row) {
  return {
    paymentId: row.id,
    id: row.id,
    booking_id: row.booking_id,
    booking_reference: row.booking_reference,
    event_id: row.event_id,
    user_id: row.user_id,
    event_title: row.event_title,
    amount: Number(row.amount ?? 0),
    currency: String(row.currency ?? "THB").toUpperCase(),
    fx_rate_used: row.fx_rate_used == null ? null : Number(row.fx_rate_used),
    method_type: normalizeMethodType(row.method_type) || String(row.method_type ?? ""),
    provider: normalizeProvider(row.provider) || String(row.provider ?? ""),
    payment_reference: row.payment_reference,
    provider_txn_id:
      row.provider_txn_id ||
      row.provider_charge_id ||
      row.provider_payment_intent_id ||
      row.stripe_payment_intent_id ||
      null,
    failure_code: row.failure_code || null,
    failure_reason: row.failure_reason || null,
    timed_out: isTimedOutPaymentRow(row),
    status: row.status,
    paid_at: row.paid_at,
    receipt_no: row.receipt_no,
    receipt_issue_date: row.receipt_issue_date,
    receipt_url: toAbsoluteUrl(req, row.receipt_url),
    slip_url: toAbsoluteUrl(req, row.slip_url),
  };
}

async function syncAirwallexPaymentRecord(client, paymentRow, intentPayload) {
  const providerPaymentIntentId = String(
    intentPayload?.id ??
    intentPayload?.payment_intent_id ??
    paymentRow?.provider_payment_intent_id ??
    ""
  ).trim() || null;
  const providerTxnId = String(
    intentPayload?.latest_payment_attempt?.id ??
    intentPayload?.latest_payment_attempt?.payment_attempt_id ??
    intentPayload?.merchant_order_id ??
    ""
  ).trim() || null;
  const mappedStatus = mapAirwallexIntentStatusToLocal(intentPayload?.status);
  const failureCode = extractAirwallexErrorCode(intentPayload);
  const failureReason = extractAirwallexErrorMessage(intentPayload, "");
  const currentLocalStatus = normalizeLocalPaymentStatus(paymentRow?.status);

  if (mappedStatus === "paid" && currentLocalStatus === "paid") {
    await client.query(
      `
      UPDATE payments
      SET
        provider = 'airwallex_alipay',
        provider_payment_intent_id = COALESCE($2, provider_payment_intent_id),
        provider_txn_id = COALESCE($3, provider_txn_id, $2),
        raw_gateway_payload = COALESCE($4::jsonb, raw_gateway_payload),
        failure_code = NULL,
        failure_reason = NULL,
        paid_at = COALESCE(paid_at, NOW()),
        updated_at = NOW()
      WHERE id = $1
      `,
      [
        paymentRow.id,
        providerPaymentIntentId,
        providerTxnId,
        toJsonbParam(intentPayload),
      ]
    );
    await ensurePaymentReference(client, paymentRow.id);
    await ensureReceiptForPayment(client, {
      paymentId: paymentRow.id,
      amount: Number(paymentRow.amount ?? 0),
      currency: String(paymentRow.currency ?? "CNY").toUpperCase(),
    });
    return { status: "paid", changed: false };
  }

  if (["failed", "cancelled"].includes(mappedStatus) && currentLocalStatus === mappedStatus) {
    await client.query(
      `
      UPDATE payments
      SET
        provider = 'airwallex_alipay',
        provider_payment_intent_id = COALESCE($2, provider_payment_intent_id),
        provider_txn_id = COALESCE($3, provider_txn_id, $2),
        raw_gateway_payload = COALESCE($4::jsonb, raw_gateway_payload),
        failure_code = COALESCE($5, failure_code),
        failure_reason = COALESCE(NULLIF($6, ''), failure_reason),
        updated_at = NOW()
      WHERE id = $1
      `,
      [
        paymentRow.id,
        providerPaymentIntentId,
        providerTxnId,
        toJsonbParam(intentPayload),
        failureCode,
        failureReason || null,
      ]
    );
    return { status: mappedStatus, changed: false };
  }

  if (mappedStatus === "paid") {
    const paidStatus = await pickEnumSafe(client, "payments", "status", "paid");
    const confirmedStatus = await pickEnumSafe(client, "bookings", "status", "confirmed");
    await client.query(
      `
      UPDATE payments
      SET
        status = $2,
        provider = 'airwallex_alipay',
        payment_method_type = COALESCE(payment_method_type, 'alipay'),
        provider_payment_intent_id = COALESCE($3, provider_payment_intent_id),
        provider_txn_id = COALESCE($4, provider_txn_id, $3),
        raw_gateway_payload = $5::jsonb,
        failure_code = NULL,
        failure_reason = NULL,
        paid_at = COALESCE(paid_at, NOW()),
        updated_at = NOW()
      WHERE id = $1
      `,
      [
        paymentRow.id,
        paidStatus,
        providerPaymentIntentId,
        providerTxnId,
        toJsonbParam(intentPayload),
      ]
    );

    if (Number.isFinite(Number(paymentRow.booking_id)) && Number(paymentRow.booking_id) > 0) {
      await client.query(
        `
        UPDATE bookings
        SET status = $2, updated_at = NOW()
        WHERE id = $1
        `,
        [paymentRow.booking_id, confirmedStatus]
      );
      await ensureBookingReference(client, paymentRow.booking_id);
    }

    if (
      Number.isFinite(Number(paymentRow.event_id)) &&
      Number(paymentRow.event_id) > 0 &&
      Number.isFinite(Number(paymentRow.user_id)) &&
      Number(paymentRow.user_id) > 0
    ) {
      await ensureParticipantForBooking(client, {
        eventId: Number(paymentRow.event_id),
        userId: Number(paymentRow.user_id),
        bookingId: Number(paymentRow.booking_id),
      });
    }

    await ensureReceiptForPayment(client, {
      paymentId: paymentRow.id,
      amount: Number(paymentRow.amount ?? 0),
      currency: String(paymentRow.currency ?? "CNY").toUpperCase(),
    });
    return { status: paidStatus, changed: true };
  }

  if (mappedStatus === "failed" || mappedStatus === "cancelled") {
    const targetStatus = await pickEnumSafe(client, "payments", "status", mappedStatus);
    await client.query(
      `
      UPDATE payments
      SET
        status = $2,
        provider = 'airwallex_alipay',
        provider_payment_intent_id = COALESCE($3, provider_payment_intent_id),
        provider_txn_id = COALESCE($4, provider_txn_id, $3),
        raw_gateway_payload = $5::jsonb,
        failure_code = $6,
        failure_reason = $7,
        updated_at = NOW()
      WHERE id = $1
      `,
      [
        paymentRow.id,
        targetStatus,
        providerPaymentIntentId,
        providerTxnId,
        toJsonbParam(intentPayload),
        failureCode,
        failureReason || null,
      ]
    );
    return { status: targetStatus, changed: true };
  }

  const pendingStatus = await pickEnumSafe(client, "payments", "status", "pending");
  await client.query(
    `
    UPDATE payments
    SET
      status = $2,
      provider = 'airwallex_alipay',
      provider_payment_intent_id = COALESCE($3, provider_payment_intent_id),
      provider_txn_id = COALESCE($4, provider_txn_id, $3),
      raw_gateway_payload = $5::jsonb,
      failure_code = NULL,
      failure_reason = NULL,
      updated_at = NOW()
    WHERE id = $1
    `,
    [
      paymentRow.id,
      pendingStatus,
      providerPaymentIntentId,
      providerTxnId,
      toJsonbParam(intentPayload),
    ]
  );
  return { status: pendingStatus, changed: currentLocalStatus !== normalizeLocalPaymentStatus(pendingStatus) };
}

function normalizePaymentMode(rawValue) {
  const value = String(rawValue ?? "").trim().toLowerCase();
  if (["manual_qr", "stripe_auto", "hybrid"].includes(value)) return value;
  return "manual_qr";
}

function normalizePaymentMethodKey(rawValue) {
  const value = String(rawValue ?? "").trim().toLowerCase();
  if (value === "promptpay") return "promptpay";
  return null;
}

function normalizeBaseCurrency(rawValue, fallback = "THB") {
  return "THB";
}

function roundMoney(value) {
  const parsed = Number(value ?? 0);
  if (!Number.isFinite(parsed)) return 0;
  return Math.round(parsed * 100) / 100;
}

function roundFx(value) {
  const parsed = Number(value ?? 0);
  if (!Number.isFinite(parsed)) return 0;
  return Math.round(parsed * 1000000) / 1000000;
}

function parseOptionalPositiveNumber(rawValue) {
  if (rawValue === undefined || rawValue === null || `${rawValue}`.trim() === "") {
    return null;
  }
  const parsed = Number(rawValue);
  if (!Number.isFinite(parsed) || parsed <= 0) return null;
  return parsed;
}

function deriveLockedEventPaymentConfig(rawInput, fallbackEventRow = null) {
  const rawPromptpayEnabled =
    rawInput?.promptpay_enabled ?? rawInput?.enable_promptpay;
  const promptpayEnabled =
    rawPromptpayEnabled === undefined
      ? !!(
          fallbackEventRow?.enable_promptpay ??
          fallbackEventRow?.promptpay_enabled ??
          true
        )
      : rawPromptpayEnabled !== false;

  const fallbackBaseAmount =
    parseOptionalPositiveNumber(
      fallbackEventRow?.base_amount ??
      fallbackEventRow?.promptpay_amount_thb ??
      fallbackEventRow?.fee
    );
  const baseAmount = parseOptionalPositiveNumber(rawInput?.base_amount ?? rawInput?.baseAmount);
  const resolvedBaseAmount = baseAmount ?? fallbackBaseAmount;
  if (resolvedBaseAmount == null) {
    return { ok: false, message: "base_amount must be greater than 0" };
  }

  const roundedBaseAmount = roundMoney(resolvedBaseAmount);
  const promptpayAmountThb = roundMoney(roundedBaseAmount);

  if (promptpayEnabled && !(promptpayAmountThb > 0)) {
    return { ok: false, message: "promptpay_amount_thb must be present and greater than 0" };
  }

  return {
    ok: true,
    value: {
      base_currency: "THB",
      base_amount: roundedBaseAmount,
      exchange_rate_thb_per_cny: 0,
      promptpay_enabled: promptpayEnabled,
      alipay_enabled: false,
      promptpay_amount_thb: promptpayAmountThb,
      alipay_amount_cny: null,
    },
  };
}

function getEventPaymentSummary(eventRow) {
  const derived = deriveLockedEventPaymentConfig({}, eventRow);
  const lockedValues = derived.ok ? derived.value : {
    base_currency: "THB",
    base_amount: roundMoney(eventRow?.base_amount ?? eventRow?.fee ?? 0),
    exchange_rate_thb_per_cny: 0,
    promptpay_enabled: !!(eventRow?.enable_promptpay ?? eventRow?.promptpay_enabled ?? true),
    alipay_enabled: false,
    promptpay_amount_thb: roundMoney(eventRow?.promptpay_amount_thb ?? eventRow?.fee ?? 0),
    alipay_amount_cny: null,
  };

  return {
    base_currency: lockedValues.base_currency,
    base_amount: lockedValues.base_amount,
    exchange_rate_thb_per_cny: lockedValues.exchange_rate_thb_per_cny,
    promptpay_enabled: !!(
      eventRow?.enable_promptpay ??
      eventRow?.promptpay_enabled ??
      lockedValues.promptpay_enabled
    ),
    alipay_enabled: false,
    promptpay_amount_thb: lockedValues.promptpay_amount_thb,
    alipay_amount_cny: lockedValues.alipay_amount_cny,
    fx_locked_at: eventRow?.fx_locked_at ?? null,
  };
}

function getManualQrForMethod(eventRow, methodType) {
  if (methodType === "PROMPTPAY") {
    return eventRow.manual_promptpay_qr_url ?? eventRow.qr_url ?? null;
  }
  if (methodType === "ALIPAY") {
    return eventRow.manual_alipay_qr_url ?? eventRow.alipay_qr_url ?? null;
  }
  return null;
}

function isStripeBranchAllowed(eventRow) {
  const paymentMode = normalizePaymentMode(eventRow.payment_mode);
  return paymentMode === "stripe_auto" || paymentMode === "hybrid";
}

function isAutomaticAlipayAllowed(eventRow) {
  return getAutomaticAlipayAvailability(eventRow).available;
}

function isManualBranchAllowed(eventRow) {
  const paymentMode = normalizePaymentMode(eventRow.payment_mode);
  return paymentMode === "manual_qr" || paymentMode === "hybrid";
}

function isSuccessfulPaymentStatus(rawValue) {
  const value = String(rawValue ?? "").trim().toLowerCase();
  return ["paid", "completed", "success", "succeeded", "done"].includes(value);
}

async function upsertEventPaymentMethod(client, { eventId, methodType, provider, qrImageUrl = null, isActive = true }) {
  await client.query(
    `
    INSERT INTO event_payment_methods
      (event_id, method_type, provider, qr_image_url, is_active, created_at, updated_at)
    VALUES
      ($1::bigint, $2::text, $3::text, $4::text, $5::boolean, NOW(), NOW())
    ON CONFLICT (event_id, method_type)
    DO UPDATE SET
      provider = EXCLUDED.provider,
      qr_image_url = EXCLUDED.qr_image_url,
      is_active = EXCLUDED.is_active,
      updated_at = NOW()
    `,
    [eventId, methodType, provider, qrImageUrl, isActive]
  );
}

async function loadEventPaymentMethods(client, eventId) {
  const eventQ = await client.query(
    `
    SELECT
      id,
      title,
      start_at,
      type,
      COALESCE(fee, 0)::numeric AS fee,
      COALESCE(currency, 'THB') AS currency,
      COALESCE(payment_mode, 'manual_qr') AS payment_mode,
      COALESCE(enable_promptpay, promptpay_enabled, TRUE) AS enable_promptpay,
      COALESCE(enable_alipay, alipay_enabled, FALSE) AS enable_alipay,
      COALESCE(stripe_enabled, FALSE) AS stripe_enabled,
      COALESCE(base_currency, currency, 'THB') AS base_currency,
      COALESCE(base_amount, fee, 0)::numeric AS base_amount,
      exchange_rate_thb_per_cny,
      COALESCE(promptpay_amount_thb, fee, 0)::numeric AS promptpay_amount_thb,
      alipay_amount_cny,
      fx_locked_at,
      manual_promptpay_qr_url,
      manual_alipay_qr_url,
      COALESCE(promptpay_enabled, TRUE) AS promptpay_enabled,
      COALESCE(alipay_enabled, FALSE) AS alipay_enabled,
      alipay_qr_url,
      qr_url
    FROM events
    WHERE id = $1
    LIMIT 1
    `,
    [eventId]
  );

  if (eventQ.rowCount === 0) return null;

  const eventRow = eventQ.rows[0];
  const methodQ = await client.query(
    `
    SELECT method_type, provider, qr_image_url, is_active
    FROM event_payment_methods
    WHERE event_id = $1
    ORDER BY id ASC
    `,
    [eventId]
  );

  const byType = new Map();
  for (const row of methodQ.rows) {
    byType.set(String(row.method_type ?? "").toUpperCase(), row);
  }

  const promptpayRow = byType.get("PROMPTPAY");
  const paymentMode = normalizePaymentMode(eventRow.payment_mode);
  const enablePromptpay = !!eventRow.enable_promptpay;
  const paymentSummary = getEventPaymentSummary(eventRow);

  return {
    event: {
      ...eventRow,
      payment_mode: paymentMode,
      enable_promptpay: enablePromptpay,
      enable_alipay: false,
      stripe_enabled: !!eventRow.stripe_enabled,
      automatic_alipay_available: false,
      automatic_alipay_unavailable_reason: null,
      automatic_alipay_provider: null,
      automatic_alipay_provider_label: null,
      airwallex_configured: false,
      airwallex_alipay_capability_enabled: false,
      ...paymentSummary,
    },
    methods: [
      {
        method_type: "PROMPTPAY",
        provider:
          paymentMode === "stripe_auto"
            ? "STRIPE"
            : paymentMode === "hybrid"
              ? "HYBRID"
              : "MANUAL_QR",
        qr_image_url:
          promptpayRow?.qr_image_url ?? getManualQrForMethod(eventRow, "PROMPTPAY"),
        is_active: promptpayRow?.is_active ?? enablePromptpay,
        manual_available: !!getManualQrForMethod(eventRow, "PROMPTPAY"),
        stripe_available: !!stripe && isStripeBranchAllowed(eventRow) && enablePromptpay,
        amount: paymentSummary.promptpay_amount_thb,
        currency: "THB",
        fx_rate_used: paymentSummary.exchange_rate_thb_per_cny,
      },
    ],
  };
}

async function ensureParticipantForBooking(client, { eventId, userId, bookingId }) {
  await ensureBigEventShirtSizeColumns();
  let shirtSize = null;
  if (Number.isFinite(Number(bookingId)) && Number(bookingId) > 0) {
    const bookingQ = await client.query(
      `
      SELECT shirt_size
      FROM bookings
      WHERE id = $1
      LIMIT 1
      `,
      [bookingId]
    );
    shirtSize = normalizeShirtSizeValue(bookingQ.rows[0]?.shirt_size);
  }
  const participantSource = await pickEnumSafe(client, "participants", "source", "payment");
  const participantStatus = await pickEnumSafe(client, "participants", "status", "joined");
  const existingQ = await client.query(
    `
    SELECT id
    FROM participants
    WHERE event_id = $1 AND user_id = $2
    LIMIT 1
    `,
    [eventId, userId]
  );

  if (existingQ.rowCount === 0) {
    await client.query(
      `
      INSERT INTO participants (event_id, user_id, booking_id, source, status, shirt_size, joined_at)
      VALUES ($1, $2, $3, $4, $5, $6, NOW())
      `,
      [eventId, userId, bookingId, participantSource, participantStatus, shirtSize]
    );
    return;
  }

  await client.query(
    `
    UPDATE participants
    SET booking_id = COALESCE(booking_id, $3),
        status = $4,
        shirt_size = COALESCE($5, shirt_size)
    WHERE event_id = $1 AND user_id = $2
    `,
    [eventId, userId, bookingId, participantStatus, shirtSize]
  );
}

async function ensureReceiptForPayment(client, { paymentId, amount, currency, receiptUrl = null }) {
  await ensurePaymentReference(client, paymentId);

  const existingQ = await client.query(
    `
    SELECT id, receipt_no, issue_date, pdf_url
    FROM receipts
    WHERE payment_id = $1
    LIMIT 1
    `,
    [paymentId]
  );

  if (existingQ.rowCount > 0) {
    const existingReceipt = existingQ.rows[0];
    const canonicalReceiptUrl =
      String(existingReceipt.pdf_url ?? "").trim() ||
      makeReceiptViewPath(existingReceipt.receipt_no);

    await client.query(
      `
      UPDATE receipts
      SET pdf_url = COALESCE(NULLIF(TRIM(pdf_url), ''), $2),
          issue_date = COALESCE(issue_date, CURRENT_DATE)
      WHERE id = $1
      `,
      [existingReceipt.id, canonicalReceiptUrl]
    );

    await client.query(
      `
      UPDATE payments
      SET receipt_url = $2, updated_at = NOW()
      WHERE id = $1
      `,
      [paymentId, canonicalReceiptUrl]
    );
    return existingQ.rows[0].id;
  }

  const receiptNo = makeReceiptNo(paymentId);
  const issueDate = new Date().toISOString().slice(0, 10);
  const canonicalReceiptUrl = makeReceiptViewPath(receiptNo);
  const ins = await client.query(
    `
    INSERT INTO receipts (payment_id, receipt_no, amount, currency, issue_date, pdf_url)
    VALUES ($1, $2, $3, $4, $5::date, $6)
    ON CONFLICT (receipt_no) DO UPDATE
    SET
      payment_id = COALESCE(receipts.payment_id, EXCLUDED.payment_id),
      amount = COALESCE(receipts.amount, EXCLUDED.amount),
      currency = COALESCE(receipts.currency, EXCLUDED.currency),
      issue_date = COALESCE(receipts.issue_date, EXCLUDED.issue_date),
      pdf_url = COALESCE(NULLIF(TRIM(receipts.pdf_url), ''), EXCLUDED.pdf_url)
    RETURNING id
    `,
    [paymentId, receiptNo, amount, currency, issueDate, canonicalReceiptUrl]
  );

  await insertAuditLog(client, {
    actorType: "system",
    action: "GENERATE_RECEIPT",
    entityTable: "receipts",
    entityId: ins.rows[0].id,
    metadata: {
      payment_id: paymentId,
      receipt_no: receiptNo,
      amount,
      currency,
      receipt_url: canonicalReceiptUrl,
    },
  });

  await client.query(
    `
    UPDATE payments
    SET receipt_url = $2, updated_at = NOW()
    WHERE id = $1
    `,
    [paymentId, canonicalReceiptUrl]
  );

  return ins.rows[0].id;
}

async function loadReusableAirwallexPendingPayment(client, bookingId, paymentMethodType) {
  const q = await client.query(
    `
    SELECT
      p.id,
      p.booking_id,
      b.booking_reference,
      p.event_id,
      COALESCE(p.user_id, b.user_id) AS user_id,
      COALESCE(p.amount, 0) AS amount,
      COALESCE(p.currency::text, b.currency::text, e.currency::text, 'CNY') AS currency,
      COALESCE(p.fx_rate_used, e.exchange_rate_thb_per_cny) AS fx_rate_used,
      p.status::text AS status,
      p.payment_reference,
      p.provider,
      p.provider_txn_id,
      p.provider_payment_intent_id,
      p.failure_code,
      p.failure_reason,
      p.created_at,
      p.raw_gateway_payload
    FROM payments p
    LEFT JOIN bookings b ON b.id = p.booking_id
    LEFT JOIN events e ON e.id = COALESCE(p.event_id, b.event_id)
    WHERE p.booking_id = $1
      AND LOWER(COALESCE(p.provider, '')) = 'airwallex_alipay'
      AND LOWER(COALESCE(p.payment_method_type, p.method_type, p.method::text, '')) = $2
      AND LOWER(COALESCE(p.status::text, '')) NOT IN ('paid', 'failed', 'cancelled', 'canceled', 'expired')
    ORDER BY p.created_at DESC NULLS LAST, p.id DESC
    LIMIT 1
    FOR UPDATE OF p
    `,
    [bookingId, paymentMethodType]
  );
  return q.rows[0] ?? null;
}

function renderReceiptHtml(receipt) {
  const supportLine = String(process.env.SUPPORT_EMAIL ?? process.env.SUPPORT_CONTACT ?? "").trim();
  const eventDateTime = receipt.event_start_at
    ? `${formatReceiptDate(receipt.event_start_at)} ${formatReceiptDateTime(receipt.event_start_at).split(", ").slice(-1)[0]}`
    : "-";

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(receipt.receipt_no)} | GatherGo Receipt</title>
  <style>
    :root {
      color-scheme: light;
      --ink: #111827;
      --muted: #6b7280;
      --line: #d1d5db;
      --panel: #ffffff;
      --bg: #f4f4f5;
      --accent: #0f172a;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: linear-gradient(180deg, #fafafa 0%, #f4f4f5 100%);
      color: var(--ink);
      font-family: "Segoe UI", Arial, sans-serif;
      padding: 24px;
    }
    .sheet {
      max-width: 860px;
      margin: 0 auto;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 18px;
      box-shadow: 0 18px 50px rgba(15, 23, 42, 0.08);
      overflow: hidden;
    }
    .header {
      padding: 28px 32px 20px;
      border-bottom: 1px solid var(--line);
      display: grid;
      grid-template-columns: 1.4fr 1fr;
      gap: 24px;
      align-items: end;
    }
    .brand {
      font-size: 26px;
      font-weight: 800;
      letter-spacing: 0.04em;
    }
    .title {
      margin-top: 8px;
      font-size: 13px;
      color: var(--muted);
      letter-spacing: 0.18em;
    }
    .meta {
      display: grid;
      gap: 8px;
      justify-items: end;
    }
    .meta strong {
      font-size: 14px;
      color: var(--muted);
      font-weight: 600;
    }
    .meta span {
      font-size: 15px;
      font-weight: 700;
    }
    .section {
      padding: 22px 32px;
      border-bottom: 1px solid var(--line);
    }
    .section:last-child { border-bottom: 0; }
    .section-title {
      font-size: 12px;
      letter-spacing: 0.14em;
      text-transform: uppercase;
      color: var(--muted);
      margin-bottom: 14px;
      font-weight: 700;
    }
    .grid {
      display: grid;
      grid-template-columns: repeat(2, minmax(0, 1fr));
      gap: 12px 28px;
    }
    .row {
      display: grid;
      gap: 4px;
      min-width: 0;
    }
    .label {
      font-size: 12px;
      color: var(--muted);
      text-transform: uppercase;
      letter-spacing: 0.08em;
    }
    .value {
      font-size: 15px;
      font-weight: 600;
      word-break: break-word;
    }
    .amount-box {
      display: flex;
      justify-content: space-between;
      align-items: end;
      gap: 16px;
      padding: 16px 18px;
      border: 1px solid var(--line);
      border-radius: 14px;
      background: #fafafa;
    }
    .amount-box .total {
      font-size: 28px;
      font-weight: 800;
      letter-spacing: -0.02em;
    }
    .footer {
      padding: 20px 32px 28px;
      color: var(--muted);
      font-size: 13px;
      line-height: 1.6;
    }
    @media print {
      body { background: #fff; padding: 0; }
      .sheet { box-shadow: none; border-radius: 0; max-width: none; }
    }
    @media (max-width: 720px) {
      body { padding: 12px; }
      .header, .section, .footer { padding-left: 18px; padding-right: 18px; }
      .header, .grid { grid-template-columns: 1fr; }
      .meta { justify-items: start; }
      .amount-box { flex-direction: column; align-items: start; }
    }
  </style>
</head>
<body>
  <main class="sheet">
    <section class="header">
      <div>
        <div class="brand">GatherGo</div>
        <div class="title">PAYMENT RECEIPT</div>
      </div>
      <div class="meta">
        <div><strong>Receipt No</strong><br /><span>${escapeHtml(receipt.receipt_no)}</span></div>
        <div><strong>Receipt Date</strong><br /><span>${escapeHtml(formatReceiptDate(receipt.receipt_issue_date))}</span></div>
      </div>
    </section>

    <section class="section">
      <div class="section-title">Customer</div>
      <div class="grid">
        <div class="row"><div class="label">User ID</div><div class="value">${escapeHtml(receipt.user_display_code)}</div></div>
        <div class="row"><div class="label">User Name</div><div class="value">${escapeHtml(receipt.user_name)}</div></div>
      </div>
    </section>

    <section class="section">
      <div class="section-title">Payment</div>
      <div class="grid">
        <div class="row"><div class="label">Booking Reference</div><div class="value">${escapeHtml(receipt.booking_reference)}</div></div>
        <div class="row"><div class="label">Payment Reference</div><div class="value">${escapeHtml(receipt.payment_reference)}</div></div>
        <div class="row"><div class="label">Provider</div><div class="value">${escapeHtml(receipt.provider)}</div></div>
        <div class="row"><div class="label">Provider Transaction ID</div><div class="value">${escapeHtml(receipt.provider_txn_id)}</div></div>
        <div class="row"><div class="label">Payment Method</div><div class="value">${escapeHtml(receipt.payment_method)}</div></div>
        <div class="row"><div class="label">Payment Status</div><div class="value">${escapeHtml(receipt.payment_status)}</div></div>
        <div class="row"><div class="label">Paid At</div><div class="value">${escapeHtml(formatReceiptDateTime(receipt.paid_at))}</div></div>
      </div>
    </section>

    <section class="section">
      <div class="section-title">Event</div>
      <div class="grid">
        <div class="row"><div class="label">Event Name</div><div class="value">${escapeHtml(receipt.event_title)}</div></div>
        <div class="row"><div class="label">Event Type</div><div class="value">${escapeHtml(receipt.event_type)}</div></div>
        <div class="row"><div class="label">Event Code</div><div class="value">${escapeHtml(receipt.event_display_code)}</div></div>
        <div class="row"><div class="label">Event Date / Time</div><div class="value">${escapeHtml(eventDateTime)}</div></div>
      </div>
    </section>

    <section class="section">
      <div class="section-title">Amount</div>
      <div class="amount-box">
        <div>
          <div class="label">Amount Paid</div>
          <div class="value">${escapeHtml(formatReceiptAmount(receipt.amount, receipt.currency))}</div>
        </div>
        <div>
          <div class="label">Total</div>
          <div class="total">${escapeHtml(formatReceiptAmount(receipt.amount, receipt.currency))}</div>
        </div>
      </div>
    </section>

    <footer class="footer">
      <div>Thank you for using GatherGo.</div>
      <div>This is a system-generated receipt.</div>
      ${supportLine ? `<div>Support: ${escapeHtml(supportLine)}</div>` : ""}
    </footer>
  </main>
</body>
</html>`;
}

async function ensurePendingBigEventBooking(client, { eventId, userId, amount, currency, shirtSize = null }) {
  await ensureBigEventShirtSizeColumns();
  const awaitingPaymentStatus = await pickEnumSafe(client, "bookings", "status", "awaiting_payment");
  const pendingStatus = await pickEnumSafe(client, "bookings", "status", "pending");
  const desiredStatus = awaitingPaymentStatus || pendingStatus;

  const existingQ = await client.query(
    `
    SELECT id, status
    FROM bookings
    WHERE user_id = $1
      AND event_id = $2
      AND LOWER(COALESCE(status::text, '')) NOT IN ('confirmed', 'paid', 'completed', 'cancelled', 'canceled')
    ORDER BY id DESC
    LIMIT 1
    `,
    [userId, eventId]
  );

  if (existingQ.rowCount > 0) {
    await client.query(
      `
      UPDATE bookings
      SET quantity = 1,
          total_amount = $2,
          currency = $3,
          status = $4,
          shirt_size = $5,
          updated_at = NOW()
      WHERE id = $1
      `,
      [existingQ.rows[0].id, amount, currency, desiredStatus, shirtSize]
    );
    await ensureBookingReference(client, existingQ.rows[0].id);
    return existingQ.rows[0].id;
  }

  const ins = await client.query(
    `
    INSERT INTO bookings (user_id, event_id, quantity, total_amount, currency, status, shirt_size, created_at, updated_at)
    VALUES ($1, $2, 1, $3, $4, $5, $6, NOW(), NOW())
    RETURNING id
    `,
    [userId, eventId, amount, currency, desiredStatus, shirtSize]
  );
  await ensureBookingReference(client, ins.rows[0].id);
  return ins.rows[0].id;
}

/**
 * =====================================================
 * ✅ Stripe Webhook (ต้องมาก่อน express.json())
 * =====================================================
 */
// Canonical Stripe PaymentIntent webhook path:
// stripe listen --forward-to http://localhost:3000/api/stripe/webhook
app.post("/api/stripe/webhook", express.raw({ type: "application/json" }), async (req, res) => {
  if (!stripe || !stripeWebhookSecret) {
    return res.status(503).send("Stripe webhook is not configured on this server");
  }
  const sig = req.headers["stripe-signature"];
  let evt;

  try {
    evt = stripe.webhooks.constructEvent(req.body, sig, stripeWebhookSecret);
  } catch (err) {
    console.log("Webhook signature verify failed:", err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  const client = await pool.connect();
  try {
    await ensureBusinessReferenceColumns();
    await client.query("BEGIN");

    const eventIns = await client.query(
      `
      INSERT INTO stripe_webhook_events
        (stripe_event_id, event_type, payload_json, created_at)
      VALUES
        ($1, $2, $3::jsonb, NOW())
      ON CONFLICT (stripe_event_id) DO NOTHING
      RETURNING id
      `,
      [evt.id, evt.type, JSON.stringify(evt)]
    );

    if (eventIns.rowCount === 0) {
      await client.query("COMMIT");
      return res.sendStatus(200);
    }

    if (![
      "payment_intent.succeeded",
      "payment_intent.payment_failed",
      "payment_intent.canceled",
      "checkout.session.completed",
    ].includes(evt.type)) {
      await client.query(
        `UPDATE stripe_webhook_events SET processed_at = NOW() WHERE stripe_event_id = $1`,
        [evt.id]
      );
      await client.query("COMMIT");
      return res.sendStatus(200);
    }

    if (evt.type === "checkout.session.completed") {
      const session = evt.data?.object ?? {};
      const paymentId = Number(session?.metadata?.payment_id);
      const checkoutSessionId = String(session?.id ?? "").trim();
      const providerPaymentIntentId = String(session?.payment_intent ?? "").trim() || null;
      const currency = String(session?.currency ?? "THB").toUpperCase();
      const amount = Number(session?.amount_total ?? 0) / 100;
      const chargeId =
        session?.payment_intent?.latest_charge != null
          ? String(session.payment_intent.latest_charge)
          : null;

      console.log("[stripe webhook] checkout.session.completed", {
        checkoutSessionId,
        paymentId: paymentId || null,
        providerPaymentIntentId,
        currency,
        amount,
      });

      if (!checkoutSessionId) {
        await client.query(
          `UPDATE stripe_webhook_events SET processed_at = NOW() WHERE stripe_event_id = $1`,
          [evt.id]
        );
        await client.query("COMMIT");
        return res.sendStatus(200);
      }

      const paymentQ = await client.query(
        `
        SELECT p.id, p.booking_id, p.user_id, p.event_id, p.amount, p.currency
        FROM payments p
        WHERE p.id = COALESCE(NULLIF($1::bigint, 0), p.id)
           OR p.stripe_checkout_session_id = $2
        ORDER BY p.id DESC
        LIMIT 1
        `,
        [paymentId || null, checkoutSessionId]
      );

      if (paymentQ.rowCount === 0) {
        console.log("[stripe webhook] checkout session payment not found", {
          checkoutSessionId,
          paymentId: paymentId || null,
        });
        await client.query(
          `UPDATE stripe_webhook_events SET processed_at = NOW() WHERE stripe_event_id = $1`,
          [evt.id]
        );
        await client.query("COMMIT");
        return res.sendStatus(200);
      }

      const payment = paymentQ.rows[0];
      console.log("[stripe webhook] checkout session matched payment", {
        checkoutSessionId,
        paymentDbId: payment.id,
        bookingId: payment.booking_id,
        eventId: payment.event_id,
        userId: payment.user_id,
      });
      const paidStatus = await pickEnumSafe(client, "payments", "status", "paid");
      const confirmedStatus = await pickEnumSafe(client, "bookings", "status", "confirmed");
      const paymentAmount = Number(payment.amount ?? amount ?? 0);
      const paymentCurrency = String(payment.currency ?? currency ?? "THB").toUpperCase();

      await client.query(
        `
        UPDATE payments
        SET
          status = $2,
          provider = 'stripe',
          payment_reference = COALESCE(NULLIF(TRIM(payment_reference), ''), $7),
          provider_txn_id = COALESCE(provider_txn_id, $4, $3, $8),
          provider_payment_intent_id = COALESCE($3, provider_payment_intent_id),
          stripe_payment_intent_id = COALESCE($3, stripe_payment_intent_id),
          paid_at = COALESCE(paid_at, NOW()),
          updated_at = NOW()
        WHERE id = $1
        `,
        [
          payment.id,
          paidStatus,
          providerPaymentIntentId,
          chargeId,
          null,
          null,
          makeBusinessReference("PAY", payment.id, new Date()),
          checkoutSessionId,
        ]
      );

      if (Number.isFinite(Number(payment.booking_id)) && Number(payment.booking_id) > 0) {
        await client.query(
          `
          UPDATE bookings
          SET status = $2, updated_at = NOW()
          WHERE id = $1
          `,
          [payment.booking_id, confirmedStatus]
        );
        await ensureBookingReference(client, payment.booking_id);
      }

      if (Number.isFinite(Number(payment.event_id)) && Number(payment.event_id) > 0 && Number.isFinite(Number(payment.user_id)) && Number(payment.user_id) > 0) {
        await ensureParticipantForBooking(client, {
          eventId: Number(payment.event_id),
          userId: Number(payment.user_id),
          bookingId: Number(payment.booking_id),
        });
      }

      await ensureReceiptForPayment(client, {
        paymentId: payment.id,
        amount: paymentAmount,
        currency: paymentCurrency,
      });

      console.log("[stripe webhook] checkout session marked paid", {
        checkoutSessionId,
        paymentDbId: payment.id,
        bookingId: payment.booking_id,
      });

      await client.query(
        `UPDATE stripe_webhook_events SET processed_at = NOW() WHERE stripe_event_id = $1`,
        [evt.id]
      );
      await client.query("COMMIT");
      return res.sendStatus(200);
    }

    const paymentIntent = evt.data?.object ?? {};
    const providerPaymentIntentId = String(paymentIntent?.id ?? "").trim();
    const metadataPaymentId = Number(paymentIntent?.metadata?.payment_id);
    const failureCode = String(paymentIntent?.last_payment_error?.code ?? "").trim() || null;
    const failureMessage =
      String(paymentIntent?.last_payment_error?.message ?? "").trim() || null;
    console.log("[stripe webhook] received", {
      type: evt.type,
      paymentIntentId: providerPaymentIntentId || null,
      paymentId: Number.isFinite(metadataPaymentId) && metadataPaymentId > 0 ? metadataPaymentId : null,
      failureCode,
    });
    if (!providerPaymentIntentId) {
      await client.query(
        `UPDATE stripe_webhook_events SET processed_at = NOW() WHERE stripe_event_id = $1`,
        [evt.id]
      );
      await client.query("COMMIT");
      return res.sendStatus(200);
    }

    const paymentQ = await client.query(
      `
      SELECT
        p.id,
        p.booking_id,
        p.user_id,
        p.event_id,
        p.amount,
        p.currency,
        p.status,
        p.payment_method_type,
        b.user_id AS booking_user_id,
        b.event_id AS booking_event_id
      FROM payments p
      LEFT JOIN bookings b ON b.id = p.booking_id
      WHERE ($2::bigint IS NOT NULL AND p.id = $2)
         OR p.provider_payment_intent_id = $1
         OR p.stripe_payment_intent_id = $1
      ORDER BY p.id DESC
      LIMIT 1
      `,
      [
        providerPaymentIntentId,
        Number.isFinite(metadataPaymentId) && metadataPaymentId > 0 ? metadataPaymentId : null,
      ]
    );

    if (paymentQ.rowCount === 0) {
      console.log("[stripe webhook] payment not found", {
        providerPaymentIntentId,
        paymentId: Number.isFinite(metadataPaymentId) && metadataPaymentId > 0 ? metadataPaymentId : null,
        type: evt.type,
      });
      await client.query(
        `UPDATE stripe_webhook_events SET processed_at = NOW() WHERE stripe_event_id = $1`,
        [evt.id]
      );
      await client.query("COMMIT");
      return res.sendStatus(200);
    }

    const payment = paymentQ.rows[0];
    const amount = Number(payment.amount ?? 0);
    const currency = String(payment.currency ?? "THB").toUpperCase();
    const chargeId =
      paymentIntent?.latest_charge != null ? String(paymentIntent.latest_charge) : null;
    const receiptUrl =
      paymentIntent?.charges?.data?.[0]?.receipt_url != null
        ? String(paymentIntent.charges.data[0].receipt_url)
        : null;
    const eventId = Number(payment.event_id ?? payment.booking_event_id);
    const userId = Number(payment.user_id ?? payment.booking_user_id);
    const bookingId = Number(payment.booking_id);

    if (evt.type === "payment_intent.succeeded") {
      const paidStatus = await pickEnumSafe(client, "payments", "status", "paid");
      const confirmedStatus = await pickEnumSafe(client, "bookings", "status", "confirmed");

      await client.query(
        `
        UPDATE payments
        SET
          status = $2,
          provider = 'stripe',
          payment_reference = COALESCE(NULLIF(TRIM(payment_reference), ''), $7),
          provider_txn_id = COALESCE(provider_txn_id, $4, $3),
          provider_payment_intent_id = COALESCE(provider_payment_intent_id, $3),
          stripe_payment_intent_id = COALESCE(stripe_payment_intent_id, $3),
          provider_charge_id = COALESCE(provider_charge_id, $4),
          stripe_charge_id = COALESCE(stripe_charge_id, $4),
          paid_at = COALESCE(paid_at, NOW()),
          raw_gateway_payload = $5::jsonb,
          receipt_url = COALESCE(receipt_url, $6),
          updated_at = NOW()
        WHERE id = $1
        `,
        [
          payment.id,
          paidStatus,
          providerPaymentIntentId,
          chargeId,
          JSON.stringify(paymentIntent),
          receiptUrl,
          makeBusinessReference("PAY", payment.id, new Date()),
        ]
      );

      if (Number.isFinite(bookingId) && bookingId > 0) {
        await client.query(
          `
          UPDATE bookings
          SET status = $2, updated_at = NOW()
          WHERE id = $1
          `,
          [bookingId, confirmedStatus]
        );
        await ensureBookingReference(client, bookingId);
      }

      if (Number.isFinite(eventId) && eventId > 0 && Number.isFinite(userId) && userId > 0) {
        await ensureParticipantForBooking(client, { eventId, userId, bookingId });
      }

      await ensureReceiptForPayment(client, {
        paymentId: payment.id,
        amount,
        currency,
        receiptUrl,
      });

      await insertAuditLog(client, {
        userId: Number.isFinite(userId) && userId > 0 ? userId : null,
        actorType: "system",
        action: "CONFIRM_PAYMENT",
        entityTable: "payments",
        entityId: payment.id,
        metadata: {
          booking_id: Number.isFinite(bookingId) && bookingId > 0 ? bookingId : null,
          booking_reference: Number.isFinite(bookingId) && bookingId > 0
            ? await ensureBookingReference(client, bookingId)
            : null,
          payment_reference: await ensurePaymentReference(client, payment.id),
          provider: "stripe",
          provider_txn_id: chargeId || providerPaymentIntentId,
          receipt_url: receiptUrl,
          new_values: {
            status: paidStatus,
            paid_at: new Date().toISOString(),
          },
        },
      });

      console.log("[stripe webhook] update", {
        type: evt.type,
        paymentId: payment.id,
        bookingId,
        eventId,
        userId,
        paymentStatus: paidStatus,
        bookingStatus: confirmedStatus,
      });
    } else {
      const targetStatus = await pickEnumSafe(
        client,
        "payments",
        "status",
        evt.type === "payment_intent.canceled" ? "cancelled" : "failed"
      );

      await client.query(
        `
        UPDATE payments
        SET
          status = $2,
          provider = 'stripe',
          payment_reference = COALESCE(NULLIF(TRIM(payment_reference), ''), $6),
          provider_txn_id = COALESCE(provider_txn_id, $4, $3),
          provider_payment_intent_id = COALESCE(provider_payment_intent_id, $3),
          stripe_payment_intent_id = COALESCE(stripe_payment_intent_id, $3),
          provider_charge_id = COALESCE(provider_charge_id, $4),
          stripe_charge_id = COALESCE(stripe_charge_id, $4),
          raw_gateway_payload = $5::jsonb,
          updated_at = NOW()
        WHERE id = $1
        `,
        [
          payment.id,
          targetStatus,
          providerPaymentIntentId,
          chargeId,
          JSON.stringify(paymentIntent),
          makeBusinessReference("PAY", payment.id, new Date()),
        ]
      );

      console.log("[stripe webhook] update", {
        type: evt.type,
        paymentId: payment.id,
        bookingId,
        paymentStatus: targetStatus,
        failureCode,
        failureMessage,
      });
    }

    await client.query(
      `UPDATE stripe_webhook_events SET processed_at = NOW() WHERE stripe_event_id = $1`,
      [evt.id]
    );
    await client.query("COMMIT");
    return res.sendStatus(200);
  } catch (err) {
    await client.query("ROLLBACK");
    console.error("Canonical Stripe webhook error:", err);
    return res.sendStatus(500);
  } finally {
    client.release();
  }
});

// Legacy Checkout webhook path kept for older flows. Use /api/stripe/webhook for PaymentIntent flows.
app.post("/api/webhooks/stripe", express.raw({ type: "application/json" }), async (req, res) => {
  if (!stripe || !stripeWebhookSecret) {
    return res.status(503).send("Stripe webhook is not configured on this server");
  }
  const sig = req.headers["stripe-signature"];
  let evt;

  try {
    evt = stripe.webhooks.constructEvent(req.body, sig, stripeWebhookSecret);
  } catch (err) {
    console.log("❌ Webhook signature verify failed:", err.message);
    return res.status(400).send(`Webhook Error: ${err.message}`);
  }

  console.log("✅ Stripe webhook verified:", evt.type);

  if (evt.type !== "checkout.session.completed") {
    return res.sendStatus(200);
  }

  const session = evt.data.object;

  try {
    const userId = Number(session?.metadata?.user_id);
    const eventId = Number(session?.metadata?.event_id);
    const quantity = session?.metadata?.quantity != null ? Number(session.metadata.quantity) : 1;

    const stripeSessionId = session?.id;
    const paymentIntentId = session?.payment_intent ?? null;

    const amountMinor = session?.amount_total != null ? Number(session.amount_total) : null;
    const currency = (session?.currency ?? "thb").toUpperCase();
    const totalAmount = amountMinor != null ? amountMinor / 100 : null;

    if (!userId || !eventId || !stripeSessionId) {
      console.log("⚠️ Missing metadata user_id/event_id or session.id");
      return res.sendStatus(200);
    }
    if (totalAmount == null) {
      console.log("⚠️ Missing amount_total");
      return res.sendStatus(200);
    }

    const providerTxnId = (paymentIntentId ?? stripeSessionId).toString();

    const client = await pool.connect();
    try {
      await client.query("BEGIN");

      const exist = await client.query(
        `
          SELECT id
          FROM payments
          WHERE provider = $1
            AND provider_txn_id = $2
          LIMIT 1
          `,
        ["stripe", providerTxnId]
      );

      if (exist.rowCount > 0) {
        await client.query("COMMIT");
        console.log("ℹ️ Duplicate webhook ignored:", { providerTxnId });
        return res.sendStatus(200);
      }

      const bookingStatus = await pickEnumSafe(client, "bookings", "status", "confirmed");
      const paymentStatus = await pickEnumSafe(client, "payments", "status", "paid");
      const paymentMethod = await pickEnumSafe(client, "payments", "method", session?.metadata?.payment_method);
      const participantSource = await pickEnumSafe(client, "participants", "source", session?.metadata?.participant_source);
      const participantStatus = await pickEnumSafe(client, "participants", "status", session?.metadata?.participant_status);
      const shirtSize = normalizeShirtSizeValue(session?.metadata?.shirt_size);

      const qty = Number.isFinite(quantity) && quantity > 0 ? quantity : 1;

      const bookQ = await client.query(
        `
          INSERT INTO bookings (user_id, event_id, quantity, total_amount, status, shirt_size)
          VALUES ($1, $2, $3, $4, $5, $6)
          RETURNING id
          `,
        [userId, eventId, qty, totalAmount, bookingStatus, shirtSize]
      );
      const bookingId = bookQ.rows[0].id;

      const payQ = await client.query(
        `
          INSERT INTO payments (booking_id, method, provider, provider_txn_id, amount, status, paid_at)
          VALUES ($1, $2, $3, $4, $5, $6, NOW())
          RETURNING id
          `,
        [bookingId, paymentMethod, "stripe", providerTxnId, totalAmount, paymentStatus]
      );
      const paymentId = payQ.rows[0].id;

      const pExist = await client.query(
        `
          SELECT id
          FROM participants
          WHERE event_id = $1 AND user_id = $2
          LIMIT 1
          `,
        [eventId, userId]
      );

      if (pExist.rowCount === 0) {
        await client.query(
          `
            INSERT INTO participants (event_id, user_id, booking_id, source, status, shirt_size, joined_at)
            VALUES ($1, $2, $3, $4, $5, $6, NOW())
            `,
          [eventId, userId, bookingId, participantSource, participantStatus, shirtSize]
        );
      } else {
        await client.query(
          `
            UPDATE participants
            SET booking_id = COALESCE(booking_id, $3),
                status = $4,
                shirt_size = COALESCE($5, shirt_size)
            WHERE event_id = $1 AND user_id = $2
            `,
          [eventId, userId, bookingId, participantStatus, shirtSize]
        );
      }

      await ensureReceiptForPayment(client, {
        paymentId,
        amount: totalAmount,
        currency,
      });

      await client.query("COMMIT");

      console.log("✅ Auto-confirm done:", { bookingId, paymentId, userId, eventId, providerTxnId });
      return res.sendStatus(200);
    } catch (dbErr) {
      await client.query("ROLLBACK");
      console.error("❌ Create booking DB error:");
      console.error(dbErr);
      console.error("DETAIL:", dbErr.message);
      return res.status(500).json({ message: "DB error", error: dbErr.message });
    } finally {
      client.release();
    }
  } catch (e) {
    console.error("❌ Webhook handler error:", e);
    return res.sendStatus(200);
  }
});

async function handleAirwallexWebhook(req, res) {
  const rawBody = Buffer.isBuffer(req.body) ? req.body : Buffer.from(req.body ?? "", "utf8");
  const eventIdForFallback = `awx-${Date.now()}`;
  const signatureVerified = airwallex.verifyWebhookSignature({
    timestamp: req.headers["x-timestamp"],
    signature: req.headers["x-signature"],
    rawBody,
    secret: process.env.ALIPAY_WEBHOOK_SECRET || process.env.AIRWALLEX_WEBHOOK_SECRET,
  });

  if (!signatureVerified) {
    console.log("[airwallex webhook] signature verification failed");
    return res.status(400).send("Webhook signature verification failed");
  }

  let payload = {};
  try {
    payload = JSON.parse(rawBody.toString("utf8") || "{}");
  } catch (_) {
    return res.status(400).send("Invalid webhook payload");
  }

  const eventId = getAirwallexEventId(payload) || eventIdForFallback;
  const eventType = getAirwallexEventType(payload) || "unknown";
  const resource = getAirwallexEventResource(payload);
  const providerPaymentIntentId = String(
    resource?.id ?? resource?.payment_intent_id ?? ""
  ).trim();
  const merchantOrderId = String(resource?.merchant_order_id ?? "").trim();

  const client = await pool.connect();
  try {
    await ensureBusinessReferenceColumns();
    await client.query("BEGIN");

    const ins = await client.query(
      `
      INSERT INTO airwallex_webhook_events
        (airwallex_event_id, event_type, payload_json, created_at)
      VALUES
        ($1, $2, $3::jsonb, NOW())
      ON CONFLICT (airwallex_event_id) DO NOTHING
      RETURNING id
      `,
      [eventId, eventType, toJsonbParam(payload, payload)]
    );

    if (ins.rowCount === 0) {
      await client.query("COMMIT");
      return res.sendStatus(200);
    }

    if (!ALLOWED_AIRWALLEX_WEBHOOK_EVENT_TYPES.has(eventType)) {
      await client.query(
        `UPDATE airwallex_webhook_events SET processed_at = NOW() WHERE airwallex_event_id = $1`,
        [eventId]
      );
      await client.query("COMMIT");
      return res.sendStatus(200);
    }

    const paymentQ = await client.query(
      `
      SELECT
        p.id,
        p.booking_id,
        p.user_id,
        p.event_id,
        p.amount,
        p.currency,
        p.payment_reference,
        p.provider_payment_intent_id
      FROM payments p
      WHERE LOWER(COALESCE(p.provider, '')) = 'airwallex_alipay'
        AND (
          p.provider_payment_intent_id = $1
          OR ($2 <> '' AND p.payment_reference = $2)
        )
      ORDER BY p.id DESC
      LIMIT 1
      `,
      [providerPaymentIntentId || null, merchantOrderId]
    );

    if (paymentQ.rowCount === 0) {
      console.log("[airwallex webhook] payment not found", {
        eventType,
        providerPaymentIntentId: providerPaymentIntentId || null,
        merchantOrderId: merchantOrderId || null,
      });
      await client.query(
        `UPDATE airwallex_webhook_events SET processed_at = NOW() WHERE airwallex_event_id = $1`,
        [eventId]
      );
      await client.query("COMMIT");
      return res.sendStatus(200);
    }

    const payment = paymentQ.rows[0];
    const syncResult = await syncAirwallexPaymentRecord(client, payment, resource);
    console.log("[airwallex webhook] update", {
      eventType,
      paymentId: payment.id,
      providerPaymentIntentId: providerPaymentIntentId || null,
      merchantOrderId: merchantOrderId || null,
      status: syncResult.status,
      changed: syncResult.changed,
    });

    await client.query(
      `UPDATE airwallex_webhook_events SET processed_at = NOW() WHERE airwallex_event_id = $1`,
      [eventId]
    );
    await client.query("COMMIT");
    return res.sendStatus(200);
  } catch (err) {
    await client.query("ROLLBACK");
    console.error("[airwallex webhook] error", err);
    return res.sendStatus(500);
  } finally {
    client.release();
  }
}

app.post("/api/airwallex/webhook", express.raw({ type: "application/json" }), handleAirwallexWebhook);
async function handleAntomWebhook(req, res) {
  const rawBody = Buffer.isBuffer(req.body) ? req.body : Buffer.from(req.body ?? "", "utf8");
  let payload = {};
  try {
    payload = JSON.parse(rawBody.toString("utf8") || "{}");
  } catch (_) {
    return res.status(400).send("Invalid webhook payload");
  }

  const signatureVerified = antom.verifySignature({
    method: req.method,
    path: req.originalUrl,
    clientId: req.headers["client-id"],
    requestTime: req.headers["request-time"],
    rawBody,
    signature: req.headers["signature"],
    publicKey: String(process.env.ANTOM_PUBLIC_KEY ?? "").trim(),
  });
  if (!signatureVerified) {
    return res.status(400).send("Webhook signature verification failed");
  }

  const notifyId = String(
    payload?.notifyId ?? payload?.paymentId ?? payload?.paymentRequestId ?? ""
  ).trim();
  const eventType = String(payload?.notifyType ?? "payment_result").trim() || "payment_result";
  const paymentKey = String(
    payload?.paymentId ?? payload?.paymentRequestId ?? ""
  ).trim();
  const merchantOrderId = String(payload?.referenceOrderId ?? "").trim();

  const client = await pool.connect();
  try {
    await ensureBusinessReferenceColumns();
    await client.query("BEGIN");

    const ins = await client.query(
      `
      INSERT INTO antom_webhook_events
        (antom_notify_id, event_type, payload_json, created_at)
      VALUES
        ($1, $2, $3::jsonb, NOW())
      ON CONFLICT (antom_notify_id) DO NOTHING
      RETURNING id
      `,
      [notifyId || `antom-${Date.now()}`, eventType, toJsonbParam(payload, payload)]
    );
    if (ins.rowCount === 0) {
      await client.query("COMMIT");
      return res.status(200).json({ result: { resultCode: "SUCCESS", resultMessage: "OK" } });
    }

    const paymentQ = await client.query(
      `
      SELECT
        p.id,
        p.booking_id,
        p.user_id,
        p.event_id,
        p.amount,
        p.currency,
        p.payment_reference,
        p.provider_payment_intent_id
      FROM payments p
      WHERE LOWER(COALESCE(p.provider, '')) = 'antom_alipay'
        AND (
          p.provider_payment_intent_id = $1
          OR ($2 <> '' AND p.payment_reference = $2)
        )
      ORDER BY p.id DESC
      LIMIT 1
      `,
      [paymentKey || null, merchantOrderId]
    );

    if (paymentQ.rowCount > 0) {
      await syncAntomPaymentRecord(client, paymentQ.rows[0], payload);
    }

    await client.query(
      `UPDATE antom_webhook_events SET processed_at = NOW() WHERE antom_notify_id = $1`,
      [notifyId || `antom-${Date.now()}`]
    );
    await client.query("COMMIT");
    return res.status(200).json({ result: { resultCode: "SUCCESS", resultMessage: "OK" } });
  } catch (err) {
    await client.query("ROLLBACK");
    console.error("[antom webhook] error", err);
    return res.status(500).json({ result: { resultCode: "FAIL", resultMessage: "ERROR" } });
  } finally {
    client.release();
  }
}

app.post("/api/alipay/webhook", express.raw({ type: "application/json" }), async (req, res) => {
  if (getConfiguredAlipayProvider() === "antom") {
    return handleAntomWebhook(req, res);
  }
  return handleAirwallexWebhook(req, res);
});

/**
 * =====================================================
 * ✅ JSON parser (routes อื่นค่อยใช้)
 * =====================================================
 */
app.use(express.json({ limit: "12mb" }));
app.use(express.urlencoded({ extended: true, limit: "12mb" }));

app.get("/api/receipts/:receiptNo/view", async (req, res) => {
  try {
    await ensureBusinessReferenceColumns();

    const receiptNo = String(req.params.receiptNo ?? "").trim();
    if (!receiptNo) {
      return res.status(400).json({ message: "Invalid receipt number" });
    }

    const receiptQ = await pool.query(
      `
      SELECT
        r.id,
        r.receipt_no,
        r.issue_date AS receipt_issue_date,
        r.amount,
        COALESCE(r.currency::text, p.currency::text, 'THB') AS currency,
        COALESCE(NULLIF(TRIM(b.booking_reference), ''), CONCAT('BK-', TO_CHAR(COALESCE(b.created_at, NOW()) AT TIME ZONE 'UTC', 'YYYYMMDD'), '-', LPAD(b.id::text, 6, '0'))) AS booking_reference,
        COALESCE(NULLIF(TRIM(p.payment_reference), ''), CONCAT('PAY-', TO_CHAR(COALESCE(p.created_at, NOW()) AT TIME ZONE 'UTC', 'YYYYMMDD'), '-', LPAD(p.id::text, 6, '0'))) AS payment_reference,
        COALESCE(NULLIF(TRIM(p.provider::text), ''), '-') AS provider,
        COALESCE(p.provider_txn_id, p.provider_charge_id, p.provider_payment_intent_id, p.stripe_payment_intent_id, '-') AS provider_txn_id,
        COALESCE(
          NULLIF(TRIM(p.payment_method_type::text), ''),
          NULLIF(TRIM(p.method_type::text), ''),
          NULLIF(TRIM(p.method::text), ''),
          '-'
        ) AS payment_method,
        COALESCE(NULLIF(TRIM(p.status::text), ''), 'paid') AS payment_status,
        p.paid_at,
        COALESCE(NULLIF(TRIM(e.title), ''), CONCAT('Event #', e.id::text)) AS event_title,
        CASE
          WHEN UPPER(COALESCE(e.type::text, 'BIG_EVENT')) = 'SPOT' THEN 'Spot'
          ELSE 'Big Event'
        END AS event_type,
        COALESCE(NULLIF(TRIM(e.display_code), ''), CONCAT('EV', LPAD(e.id::text, 6, '0'))) AS event_display_code,
        e.start_at AS event_start_at,
        CONCAT('US', LPAD(u.id::text, 4, '0')) AS user_display_code,
        COALESCE(
          NULLIF(TRIM(COALESCE(u.name, '')), ''),
          NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''),
          NULLIF(TRIM(COALESCE(u.email, '')), ''),
          CONCAT('User #', u.id::text)
        ) AS user_name
      FROM public.receipts r
      JOIN public.payments p ON p.id = r.payment_id
      LEFT JOIN public.bookings b ON b.id = p.booking_id
      LEFT JOIN public.users u ON u.id = COALESCE(p.user_id, b.user_id)
      LEFT JOIN public.events e ON e.id = COALESCE(p.event_id, b.event_id)
      WHERE r.receipt_no = $1
      LIMIT 1
      `,
      [receiptNo]
    );

    if (receiptQ.rowCount === 0) {
      return res.status(404).json({ message: "Receipt not found" });
    }

    res.setHeader("Content-Type", "text/html; charset=utf-8");
    return res.status(200).send(renderReceiptHtml(receiptQ.rows[0]));
  } catch (err) {
    console.error("Render receipt view error:", err);
    return res.status(500).json({ message: "Server error", error: String(err?.message ?? err) });
  }
});

app.get("/api/spots", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    await ensureBusinessReferenceColumns();

    const userParse = getRequestUserId(req, { allowQuery: false, allowBody: false });
    const userId = userParse.ok ? userParse.userId : null;
    const minKm = req.query?.min_km != null ? Number(req.query.min_km) : null;
    const maxKm = req.query?.max_km != null ? Number(req.query.max_km) : null;
    const provinceFilter = canonicalizeProvinceName(req.query?.province).toLowerCase();

    const client = await pool.connect();
    try {
      let rows = await listSpotRows(client, { userId });

      if (Number.isFinite(minKm)) {
        rows = rows.filter((row) => {
          const totalKm =
            normalizeSpotNumber(row.km_per_round) * normalizeSpotNumber(row.round_count);
          return totalKm >= minKm;
        });
      }

      if (Number.isFinite(maxKm)) {
        rows = rows.filter((row) => {
          const totalKm =
            normalizeSpotNumber(row.km_per_round) * normalizeSpotNumber(row.round_count);
          return totalKm <= maxKm;
        });
      }

      if (provinceFilter) {
        rows = rows.filter(
          (row) => canonicalizeProvinceName(row.province).toLowerCase() === provinceFilter
        );
      }

      return res.json(rows);
    } finally {
      client.release();
    }
  } catch (e) {
    console.error("List spots error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/spots/joined", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();

    const parsed = getRequestUserId(req);
    if (!parsed.ok) {
      return res.status(400).json({ message: parsed.message });
    }

    const client = await pool.connect();
    try {
      const rows = await listSpotRows(client, { userId: parsed.userId, onlyJoined: true });
      return res.json(rows);
    } finally {
      client.release();
    }
  } catch (e) {
    console.error("Joined spots error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/spots/mine", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();

    const parsed = getRequestUserId(req);
    if (!parsed.ok) {
      return res.status(400).json({ message: parsed.message });
    }

    const client = await pool.connect();
    try {
      const rows = await listSpotRows(client, { userId: parsed.userId });
      const mine = rows.filter(
        (row) =>
          Number(row.created_by_user_id) === parsed.userId &&
          String(row.creator_role ?? "user").toLowerCase() === "user"
      );
      return res.json(mine);
    } finally {
      client.release();
    }
  } catch (e) {
    console.error("My spots error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/spots/:id", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();

    const spotId = Number(req.params.id);
    if (!Number.isFinite(spotId) || spotId <= 0) {
      return res.status(400).json({ message: "Invalid spot id" });
    }

    const userParse = getRequestUserId(req, { allowBody: false });
    const userId = userParse.ok ? userParse.userId : null;

    const client = await pool.connect();
    try {
      const rows = await listSpotRows(client, { userId, spotId });
      if (rows.length === 0) {
        return res.status(404).json({ message: "Spot not found" });
      }
      return res.json(rows[0]);
    } finally {
      client.release();
    }
  } catch (e) {
    console.error("Get spot detail error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/spots/:id/members", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();
    await ensureUserAuthColumns();

    const spotId = Number(req.params.id);
    if (!Number.isFinite(spotId) || spotId <= 0) {
      return res.status(400).json({ message: "Invalid spot id" });
    }

    const spotQ = await client.query(
      `
      SELECT
        se.id,
        se.created_by_user_id,
        se.creator_role,
        u.profile_image_url AS creator_profile_image_url,
        u.address_district AS creator_district,
        u.address_province AS creator_province,
        COALESCE(u.status, 'active') AS creator_status,
        COALESCE(
          NULLIF(TRIM(COALESCE(u.name, '')), ''),
          NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''),
          NULLIF(TRIM(COALESCE(u.email, '')), ''),
          NULLIF(TRIM(COALESCE(au.email, '')), ''),
          CASE WHEN se.creator_role = 'admin' THEN 'Admin' ELSE 'User' END
        ) AS creator_name
      FROM public.spot_events se
      LEFT JOIN public.users u
        ON se.creator_role = 'user'
       AND u.id = se.created_by_user_id
      LEFT JOIN public.admin_users au
        ON se.creator_role = 'admin'
       AND au.id = se.created_by_user_id
      WHERE se.id = $1
      LIMIT 1
      `,
      [spotId]
    );

    if (spotQ.rowCount === 0) {
      return res.status(404).json({ message: "Spot not found" });
    }

    const spot = spotQ.rows[0];
    const membersQ = await client.query(
      `
      SELECT
        sem.user_id,
        sem.joined_at,
        u.profile_image_url,
        u.address_district AS district,
        u.address_province AS province,
        COALESCE(u.status, 'active') AS status,
        COALESCE(
          NULLIF(TRIM(COALESCE(u.name, '')), ''),
          NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''),
          NULLIF(TRIM(COALESCE(u.email, '')), ''),
          CONCAT('User #', sem.user_id::text)
        ) AS display_name
      FROM public.spot_event_members sem
      LEFT JOIN public.users u
        ON u.id = sem.user_id
      WHERE sem.spot_event_id = $1
      ORDER BY sem.joined_at ASC, sem.user_id ASC
      `,
      [spotId]
    );

    const members = [];
    const seenUserIds = new Set();
    const memberUserIds = [];

    if (String(spot.creator_role ?? "").toLowerCase() === "user" &&
        Number.isFinite(Number(spot.created_by_user_id))) {
      const hostUserId = Number(spot.created_by_user_id);
      seenUserIds.add(hostUserId);
      memberUserIds.push(hostUserId);
      members.push({
        user_id: hostUserId,
        display_name: String(spot.creator_name ?? `User #${hostUserId}`).trim(),
        role: "host",
        joined_at: null,
        profile_image_url: spot.creator_profile_image_url ?? null,
        district: spot.creator_district ?? "",
        province: spot.creator_province ?? "",
        status: spot.creator_status ?? "active",
      });
    }

    for (const row of membersQ.rows) {
      const userId = Number(row.user_id);
      if (seenUserIds.has(userId)) continue;
      seenUserIds.add(userId);
      memberUserIds.push(userId);
      members.push({
        user_id: userId,
        display_name: String(row.display_name ?? `User #${userId}`).trim(),
        role: "user",
        joined_at: row.joined_at,
        profile_image_url: row.profile_image_url ?? null,
        district: row.district ?? "",
        province: row.province ?? "",
        status: row.status ?? "active",
      });
    }

    const statsByUserId = await loadUserDistanceStats(client, memberUserIds);
    const enrichedMembers = members.map((member) => {
      const stats = statsByUserId.get(Number(member.user_id));
      return {
        ...member,
        total_km: stats?.totalKm ?? null,
        joined_count: stats?.joinedCount ?? 0,
        post_count: stats?.postCount ?? 0,
        completed_count: stats?.completedCount ?? ((stats?.joinedCount ?? 0) + (stats?.postCount ?? 0)),
      };
    });

    return res.json({
      spot_id: spotId,
      members: enrichedMembers,
      total: enrichedMembers.length,
    });
  } catch (e) {
    console.error("Get spot members error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.post("/api/spots", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();
    await ensureBusinessReferenceColumns();

    const adminParse = getRequestAdminId(req);
    const userParse = getRequestUserId(req);
    let creatorRole = null;
    let creatorId = null;

    if (adminParse.ok) {
      creatorRole = "admin";
      creatorId = adminParse.adminId;
    } else if (userParse.ok) {
      creatorRole = "user";
      creatorId = userParse.userId;
    } else {
      return res.status(400).json({ message: "admin_id is required" });
    }

    const title = String(req.body?.title ?? "").trim();
    if (!title) {
      return res.status(400).json({ message: "title is required" });
    }

    const description = String(req.body?.description ?? "").trim();
    let location = String(req.body?.location ?? "").trim();
    const locationLink = String(req.body?.location_link ?? "").trim();
    const locationLat = normalizeSpotCoordinate(
      req.body?.location_lat ?? req.body?.latitude,
      { min: -90, max: 90, fieldName: "location_lat" }
    );
    const locationLng = normalizeSpotCoordinate(
      req.body?.location_lng ?? req.body?.longitude,
      { min: -180, max: 180, fieldName: "location_lng" }
    );
    let province = normalizeSpotProvince(req.body?.province, location);
    let district = normalizeSpotDistrict(req.body?.district, location, province);
    const eventDate = String(req.body?.event_date ?? "").trim();
    const eventTime = String(req.body?.event_time ?? "").trim();
    const kmPerRound = normalizeSpotNumber(req.body?.km_per_round, 0);
    const roundCount = normalizeSpotInt(req.body?.round_count, 0);
    const maxPeople = normalizeSpotInt(req.body?.max_people, 0);
    const imageBase64 = String(req.body?.image_base64 ?? "").trim();
    const imageUrl = String(req.body?.image_url ?? "").trim();
    const status = String(req.body?.status ?? "completed").trim() || "completed";

    const resolvedLocation = await enrichSpotLocationFields({
      location,
      province,
      district,
      locationLat,
      locationLng,
    });
    location = resolvedLocation.location;
    province = resolvedLocation.province;
    district = resolvedLocation.district;

    const inserted = await client.query(
      `
      INSERT INTO public.spot_events
        (
          title,
          description,
          location,
          location_link,
          location_lat,
          location_lng,
          province,
          district,
          event_date,
          event_time,
          km_per_round,
          round_count,
          max_people,
          image_base64,
          image_url,
          status,
          created_by_user_id,
          creator_role,
          created_at,
          updated_at
        )
      VALUES
        ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, NOW(), NOW())
      RETURNING id
      `,
      [
        title,
        description,
        location,
        locationLink || null,
        locationLat,
        locationLng,
        province || null,
        district || null,
        eventDate,
        eventTime,
        kmPerRound,
        roundCount,
        maxPeople,
        imageBase64 || null,
        imageUrl || null,
        status,
        creatorId,
        creatorRole,
      ]
    );

    await ensureEventDisplayCode(client, {
      tableName: "spot_events",
      entityId: inserted.rows[0].id,
      type: "SPOT",
    });

    if (creatorRole === "admin") {
      await insertAuditLog(client, {
        adminUserId: creatorId,
        actorType: "admin",
        action: "SPOT_CREATED",
        entityTable: "spot_events",
        entityId: inserted.rows[0].id,
        metadata: {
          title,
          changed_fields: ["title", "description", "location", "event_date", "event_time", "status"],
          new_values: {
            title,
            description,
            location,
            event_date: eventDate,
            event_time: eventTime,
            status,
          },
        },
      });
    }

    const rows = await listSpotRows(client, { spotId: inserted.rows[0].id });
    return res.status(201).json(rows[0]);
  } catch (e) {
    console.error("Create spot error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.put("/api/spots/:id", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();

    const spotId = Number(req.params.id);
    if (!Number.isFinite(spotId) || spotId <= 0) {
      return res.status(400).json({ message: "Invalid spot id" });
    }

    const adminParse = getRequestAdminId(req);
    const userParse = getRequestUserId(req);
    let actorRole = null;
    let actorId = null;

    if (adminParse.ok) {
      actorRole = "admin";
      actorId = adminParse.adminId;
    } else if (userParse.ok) {
      actorRole = "user";
      actorId = userParse.userId;
    } else {
      return res.status(400).json({ message: "user_id is required" });
    }

    const existingQ = await client.query(
      `
      SELECT *
      FROM public.spot_events
      WHERE id = $1
      LIMIT 1
      `,
      [spotId]
    );
    if (existingQ.rowCount === 0) {
      return res.status(404).json({ message: "Spot not found" });
    }

    const existing = existingQ.rows[0];
    const ownerId = Number(existing.created_by_user_id);
    const ownerRole = String(existing.creator_role ?? "user").trim().toLowerCase();
    if (ownerRole !== actorRole || ownerId !== actorId) {
      return res.status(403).json({ message: "You can only edit your own spot" });
    }

    const title = String(req.body?.title ?? "").trim();
    if (!title) {
      return res.status(400).json({ message: "title is required" });
    }

    const description = String(req.body?.description ?? "").trim();
    let location = String(req.body?.location ?? "").trim();
    const locationLink = String(req.body?.location_link ?? "").trim();
    const locationLat = normalizeSpotCoordinate(
      req.body?.location_lat ?? req.body?.latitude,
      { min: -90, max: 90, fieldName: "location_lat" }
    );
    const locationLng = normalizeSpotCoordinate(
      req.body?.location_lng ?? req.body?.longitude,
      { min: -180, max: 180, fieldName: "location_lng" }
    );
    let province = normalizeSpotProvince(req.body?.province, location);
    let district = normalizeSpotDistrict(req.body?.district, location, province);
    const eventDate = String(req.body?.event_date ?? "").trim();
    const eventTime = String(req.body?.event_time ?? "").trim();
    const kmPerRound = normalizeSpotNumber(req.body?.km_per_round, 0);
    const roundCount = normalizeSpotInt(req.body?.round_count, 0);
    const maxPeople = normalizeSpotInt(req.body?.max_people, 0);
    const imageBase64 = String(req.body?.image_base64 ?? "").trim();
    const imageUrl = String(req.body?.image_url ?? "").trim();
    const status = String(req.body?.status ?? "completed").trim() || "completed";

    const resolvedLocation = await enrichSpotLocationFields({
      location,
      province,
      district,
      locationLat,
      locationLng,
    });
    location = resolvedLocation.location;
    province = resolvedLocation.province;
    district = resolvedLocation.district;

    await client.query(
      `
      UPDATE public.spot_events
      SET
        title = $2,
        description = $3,
        location = $4,
        location_link = $5,
        location_lat = $6,
        location_lng = $7,
        province = $8,
        district = $9,
        event_date = $10,
        event_time = $11,
        km_per_round = $12,
        round_count = $13,
        max_people = $14,
        image_base64 = $15,
        image_url = $16,
        status = $17,
        updated_at = NOW()
      WHERE id = $1
      `,
      [
        spotId,
        title,
        description,
        location,
        locationLink || null,
        locationLat,
        locationLng,
        province || null,
        district || null,
        eventDate,
        eventTime,
        kmPerRound,
        roundCount,
        maxPeople,
        imageBase64 || null,
        imageUrl || null,
        status,
      ]
    );

    const changedFields = diffSpotEditableFields(existing, {
      title,
      description,
      location,
      location_link: locationLink || null,
      event_date: eventDate,
      event_time: eventTime,
      km_per_round: kmPerRound,
      round_count: roundCount,
      max_people: maxPeople,
    });

    if (changedFields.length > 0) {
      const oldSpotKey = buildSpotChatKey(existing);
      const newSpotKey = buildSpotChatKey({
        id: spotId,
        title,
        event_date: eventDate,
        event_time: eventTime,
        location,
      });
      const alertMessage = buildSpotUpdatedAlertMessage(changedFields);

      await createOrReuseSpotChatRoomAlert(client, {
        spotKey: oldSpotKey,
        spotEventId: spotId,
        alertType: "spot_update_notice",
        message: alertMessage,
        triggeredByUserId: actorRole === "user" ? actorId : null,
        expiresAt: null,
      });

      if (newSpotKey !== oldSpotKey) {
        await createOrReuseSpotChatRoomAlert(client, {
          spotKey: newSpotKey,
          spotEventId: spotId,
          alertType: "spot_update_notice",
          message: alertMessage,
          triggeredByUserId: actorRole === "user" ? actorId : null,
          expiresAt: null,
        });
      }

      await insertAuditLog(client, {
        adminUserId: actorRole === "admin" ? actorId : null,
        userId: actorRole === "user" ? actorId : null,
        actorType: actorRole,
        action: "SPOT_UPDATED",
        entityTable: "spot_events",
        entityId: spotId,
        metadata: {
          display_code: String(existing.display_code ?? "").trim() || makeEventDisplayCode("SPOT", spotId),
          changed_fields: changedFields,
          old_values: Object.fromEntries(changedFields.map((field) => [field, existing[field] ?? null])),
          new_values: {
            title,
            description,
            location,
            location_link: locationLink || null,
            event_date: eventDate,
            event_time: eventTime,
            km_per_round: kmPerRound,
            round_count: roundCount,
            max_people: maxPeople,
            status,
          },
        },
      });
    }

    const rows = await listSpotRows(client, { userId: actorRole === "user" ? actorId : null, spotId });
    return res.json(rows[0]);
  } catch (e) {
    console.error("Update spot error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.get("/api/spots/:id/media", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();

    const spotId = Number(req.params.id);
    if (!Number.isFinite(spotId) || spotId <= 0) {
      return res.status(400).json({ message: "Invalid spot id" });
    }

    const q = await client.query(
      `
      SELECT id, spot_event_id, kind, file_url, alt_text, sort_order, created_at
      FROM public.spot_event_media
      WHERE spot_event_id = $1
      ORDER BY sort_order ASC, id ASC
      `,
      [spotId]
    );

    return res.json(
      q.rows.map((row) => ({
        ...row,
        file_url: toAbsoluteUrl(req, row.file_url),
      }))
    );
  } catch (e) {
    console.error("Get spot media error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.post("/api/spots/:id/gallery", async (req, res, next) => {
  upload.array("files", 10)(req, res, async (err) => {
    if (err) return next(err);
    const client = await pool.connect();
    try {
      await ensureSpotSubsystemTables();

      const spotId = Number(req.params.id);
      if (!Number.isFinite(spotId) || spotId <= 0) {
        return res.status(400).json({ message: "Invalid spot id" });
      }

      const adminParse = getRequestAdminId(req);
      const userParse = getRequestUserId(req);
      let actorRole = null;
      let actorId = null;

      if (adminParse.ok) {
        actorRole = "admin";
        actorId = adminParse.adminId;
      } else if (userParse.ok) {
        actorRole = "user";
        actorId = userParse.userId;
      } else {
        return res.status(400).json({ message: "user_id is required" });
      }

      const spotQ = await client.query(
        `SELECT id, created_by_user_id, creator_role FROM public.spot_events WHERE id = $1 LIMIT 1`,
        [spotId]
      );
      if (spotQ.rowCount === 0) {
        return res.status(404).json({ message: "Spot not found" });
      }

      const owner = spotQ.rows[0];
      if (String(owner.creator_role ?? "").trim().toLowerCase() !== actorRole ||
          Number(owner.created_by_user_id) !== actorId) {
        return res.status(403).json({ message: "You can only edit your own spot" });
      }

      const files = req.files ?? [];
      if (!Array.isArray(files) || files.length === 0) {
        return res.status(400).json({ message: "No files uploaded" });
      }

      const orderQ = await client.query(
        `SELECT COALESCE(MAX(sort_order), 0) AS max_order
         FROM public.spot_event_media
         WHERE spot_event_id = $1
           AND kind = 'gallery'`,
        [spotId]
      );
      let nextOrder = Number(orderQ.rows[0]?.max_order ?? 0);

      const rows = [];
      for (const f of files) {
        nextOrder += 1;
        const fileUrl = `${req.protocol}://${req.get("host")}/uploads/${f.filename}`;
        const inserted = await client.query(
          `insert into public.spot_event_media (spot_event_id, kind, file_url, alt_text, sort_order)
           values ($1, 'gallery', $2, $3, $4)
           returning id, spot_event_id, kind, file_url, alt_text, sort_order, created_at`,
          [spotId, fileUrl, "gallery", nextOrder]
        );
        rows.push({
          ...inserted.rows[0],
          file_url: toAbsoluteUrl(req, inserted.rows[0].file_url),
        });
      }

      return res.status(201).json(rows);
    } catch (e) {
      console.error("Upload spot gallery error:", e);
      return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
    } finally {
      client.release();
    }
  });
});

app.delete("/api/spots/:spotId/media/:mediaId", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();

    const spotId = Number(req.params.spotId);
    const mediaId = Number(req.params.mediaId);
    if (!Number.isFinite(spotId) || spotId <= 0 || !Number.isFinite(mediaId) || mediaId <= 0) {
      return res.status(400).json({ message: "Invalid spot/media id" });
    }

    const adminParse = getRequestAdminId(req, { allowBody: false });
    const userParse = getRequestUserId(req, { allowBody: false });
    let actorRole = null;
    let actorId = null;

    if (adminParse.ok) {
      actorRole = "admin";
      actorId = adminParse.adminId;
    } else if (userParse.ok) {
      actorRole = "user";
      actorId = userParse.userId;
    } else {
      return res.status(400).json({ message: "user_id is required" });
    }

    const ownerQ = await client.query(
      `SELECT id, created_by_user_id, creator_role FROM public.spot_events WHERE id = $1 LIMIT 1`,
      [spotId]
    );
    if (ownerQ.rowCount === 0) {
      return res.status(404).json({ message: "Spot not found" });
    }

    const owner = ownerQ.rows[0];
    if (String(owner.creator_role ?? "").trim().toLowerCase() !== actorRole ||
        Number(owner.created_by_user_id) !== actorId) {
      return res.status(403).json({ message: "You can only edit your own spot" });
    }

    const deleted = await client.query(
      `delete from public.spot_event_media
       where id = $1 and spot_event_id = $2
       returning id, spot_event_id, kind, file_url`,
      [mediaId, spotId]
    );
    if (deleted.rowCount === 0) {
      return res.status(404).json({ message: "Media not found" });
    }

    return res.json({ ok: true, media: deleted.rows[0] });
  } catch (e) {
    console.error("Delete spot media error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.post("/api/spots/:id/join", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();

    const spotId = Number(req.params.id);
    if (!Number.isFinite(spotId) || spotId <= 0) {
      return res.status(400).json({ message: "Invalid spot id" });
    }

    const parsed = getRequestUserId(req);
    if (!parsed.ok) {
      return res.status(400).json({ message: parsed.message });
    }

    const spotQ = await client.query(
      `
      SELECT id, max_people, created_by_user_id, creator_role
      FROM public.spot_events
      WHERE id = $1
      LIMIT 1
      `,
      [spotId]
    );
    if (spotQ.rowCount === 0) {
      return res.status(404).json({ message: "Spot not found" });
    }
    if (
      String(spotQ.rows[0]?.creator_role ?? "").trim().toLowerCase() === "user" &&
      Number(spotQ.rows[0]?.created_by_user_id) === parsed.userId
    ) {
      return res.status(409).json({
        message: "Spot creator cannot join their own spot",
      });
    }

    const countQ = await client.query(
      `SELECT COUNT(*)::int AS joined_count FROM public.spot_event_members WHERE spot_event_id = $1`,
      [spotId]
    );
    const joinedCount = Number(countQ.rows[0]?.joined_count ?? 0);
    const maxPeople = normalizeSpotInt(spotQ.rows[0]?.max_people, 0);

    await client.query(
      `
      INSERT INTO public.spot_event_members (spot_event_id, user_id, joined_at)
      VALUES ($1, $2, NOW())
      ON CONFLICT (spot_event_id, user_id) DO NOTHING
      `,
      [spotId, parsed.userId]
    );

    if (maxPeople > 0) {
      const recountQ = await client.query(
        `SELECT COUNT(*)::int AS joined_count FROM public.spot_event_members WHERE spot_event_id = $1`,
        [spotId]
      );
      if (Number(recountQ.rows[0]?.joined_count ?? 0) > maxPeople) {
        await client.query(
          `DELETE FROM public.spot_event_members WHERE spot_event_id = $1 AND user_id = $2`,
          [spotId, parsed.userId]
        );
        if (joinedCount >= maxPeople) {
          return res.status(409).json({ message: "Spot is full" });
        }
      }
    }

    const rows = await listSpotRows(client, { userId: parsed.userId, spotId });
    return res.status(201).json(rows[0] || { ok: true });
  } catch (e) {
    console.error("Join spot error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.post("/api/spots/:id/bookings", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();

    const spotId = Number(req.params.id);
    if (!Number.isFinite(spotId) || spotId <= 0) {
      return res.status(400).json({ message: "Invalid spot id" });
    }

    const parsed = getRequestUserId(req);
    if (!parsed.ok) {
      return res.status(400).json({ message: parsed.message });
    }

    const spotQ = await client.query(
      `
      SELECT id, max_people, title
      FROM public.spot_events
      WHERE id = $1
      LIMIT 1
      `,
      [spotId]
    );
    if (spotQ.rowCount === 0) {
      return res.status(404).json({ message: "Spot not found" });
    }

    const existingQ = await client.query(
      `
      SELECT id, booking_reference, status
      FROM public.spot_event_bookings
      WHERE spot_event_id = $1 AND user_id = $2
      LIMIT 1
      `,
      [spotId, parsed.userId]
    );

    if (existingQ.rowCount > 0) {
      const existingReference =
        await ensureSpotBookingReference(client, existingQ.rows[0].id);
      const rows = await listSpotRows(client, { userId: parsed.userId, spotId });
      return res.status(200).json({
        message: "Spot booking already exists",
        booking_id: existingQ.rows[0].id,
        booking_reference: existingReference,
        status: existingQ.rows[0].status ?? "booked",
        spot: rows[0] ?? null,
      });
    }

    const maxPeople = normalizeSpotInt(spotQ.rows[0]?.max_people, 0);
    if (maxPeople > 0) {
      const countQ = await client.query(
        `SELECT COUNT(*)::int AS booking_count FROM public.spot_event_bookings WHERE spot_event_id = $1`,
        [spotId]
      );
      const bookingCount = Number(countQ.rows[0]?.booking_count ?? 0);
      if (bookingCount >= maxPeople) {
        return res.status(409).json({ message: "Spot booking is full" });
      }
    }

    const bookingIns = await client.query(
      `
      INSERT INTO public.spot_event_bookings
        (spot_event_id, user_id, status, created_at, updated_at)
      VALUES
        ($1, $2, 'booked', NOW(), NOW())
      RETURNING id, status
      `,
      [spotId, parsed.userId]
    );

    const bookingReference = await ensureSpotBookingReference(
      client,
      bookingIns.rows[0].id
    );

    await insertAuditLog(client, {
      userId: parsed.userId,
      actorType: "user",
      action: "SPOT_BOOKING_CREATED",
      entityTable: "spot_event_bookings",
      entityId: bookingIns.rows[0].id,
      metadata: {
        spot_event_id: spotId,
        booking_reference: bookingReference,
        status: bookingIns.rows[0].status ?? "booked",
        title: spotQ.rows[0]?.title ?? null,
      },
    });

    const rows = await listSpotRows(client, { userId: parsed.userId, spotId });
    return res.status(201).json({
      message: "Spot booking created",
      booking_id: bookingIns.rows[0].id,
      booking_reference: bookingReference,
      status: bookingIns.rows[0].status ?? "booked",
      spot: rows[0] ?? null,
    });
  } catch (e) {
    console.error("Create spot booking error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.delete("/api/spots/:id/bookings", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();

    const spotId = Number(req.params.id);
    if (!Number.isFinite(spotId) || spotId <= 0) {
      return res.status(400).json({ message: "Invalid spot id" });
    }

    const parsed = getRequestUserId(req, { allowBody: false });
    if (!parsed.ok) {
      return res.status(400).json({ message: parsed.message });
    }

    const bookingQ = await client.query(
      `
      SELECT b.id, b.booking_reference, b.status, s.title
      FROM public.spot_event_bookings b
      JOIN public.spot_events s ON s.id = b.spot_event_id
      WHERE b.spot_event_id = $1 AND b.user_id = $2
      LIMIT 1
      `,
      [spotId, parsed.userId]
    );

    if (bookingQ.rowCount === 0) {
      const rows = await listSpotRows(client, { userId: parsed.userId, spotId });
      return res.status(200).json({
        message: "Spot booking already removed",
        cancelled: false,
        spot: rows[0] ?? null,
      });
    }

    await client.query(
      `
      DELETE FROM public.spot_event_bookings
      WHERE id = $1
      `,
      [bookingQ.rows[0].id]
    );

    await insertAuditLog(client, {
      userId: parsed.userId,
      actorType: "user",
      action: "SPOT_BOOKING_DELETED",
      entityTable: "spot_event_bookings",
      entityId: bookingQ.rows[0].id,
      metadata: {
        spot_event_id: spotId,
        booking_reference: bookingQ.rows[0].booking_reference ?? null,
        status: bookingQ.rows[0].status ?? "booked",
        title: bookingQ.rows[0]?.title ?? null,
      },
    });

    const rows = await listSpotRows(client, { userId: parsed.userId, spotId });
    return res.json({
      message: "Spot booking removed",
      cancelled: true,
      spot: rows[0] ?? null,
    });
  } catch (e) {
    console.error("Delete spot booking error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.delete("/api/spots/:id/join", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();

    const spotId = Number(req.params.id);
    if (!Number.isFinite(spotId) || spotId <= 0) {
      return res.status(400).json({ message: "Invalid spot id" });
    }

    const parsed = getRequestUserId(req, { allowBody: false });
    if (!parsed.ok) {
      return res.status(400).json({ message: parsed.message });
    }

    const deleted = await client.query(
      `
      DELETE FROM public.spot_event_members
      WHERE spot_event_id = $1 AND user_id = $2
      RETURNING id
      `,
      [spotId, parsed.userId]
    );

    if (deleted.rowCount === 0) {
      return res.status(404).json({ message: "Spot join not found" });
    }

    return res.json({ ok: true, left: true });
  } catch (e) {
    console.error("Leave spot via join delete error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.post("/api/spots/:id/leave", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();

    const spotId = Number(req.params.id);
    if (!Number.isFinite(spotId) || spotId <= 0) {
      return res.status(400).json({ message: "Invalid spot id" });
    }

    const parsed = getRequestUserId(req);
    if (!parsed.ok) {
      return res.status(400).json({ message: parsed.message });
    }

    const spotQ = await client.query(
      `
      SELECT id, created_by_user_id
      FROM public.spot_events
      WHERE id = $1
      LIMIT 1
      `,
      [spotId]
    );
    if (spotQ.rowCount === 0) {
      return res.status(404).json({ message: "Spot not found" });
    }

    const deleted = await client.query(
      `
      DELETE FROM public.spot_event_members
      WHERE spot_event_id = $1 AND user_id = $2
      RETURNING id
      `,
      [spotId, parsed.userId]
    );

    const reasonMeta = getSpotLeaveReasonMeta(
      req.body?.reason_code,
      spotQ.rows[0]?.created_by_user_id ?? null,
      req.body?.reason_text
    );
    if (reasonMeta) {
      try {
        await client.query(
          `
          INSERT INTO public.spot_leave_feedback
            (
              event_id,
              leaver_user_id,
              reason_code,
              reason_text,
              report_detail_text,
              category,
              reported_target_type,
              reported_target_user_id,
              created_at
            )
          VALUES
            ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
          `,
          [
            spotId,
            parsed.userId,
            String(req.body?.reason_code ?? "").trim().toUpperCase(),
            reasonMeta.reason_text,
            reasonMeta.report_detail_text ?? null,
            reasonMeta.category,
            reasonMeta.reported_target_type,
            reasonMeta.reported_target_user_id,
          ]
        );
      } catch (feedbackErr) {
        console.warn("Spot leave feedback skipped:", feedbackErr?.message || feedbackErr);
      }
    }

    return res.json({
      ok: true,
      left: deleted.rowCount > 0,
      already_left: deleted.rowCount === 0,
    });
  } catch (e) {
    console.error("Leave spot error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

async function handleSpotComplete(req, res) {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();

    const spotId = Number(req.params.id);
    if (!Number.isFinite(spotId) || spotId <= 0) {
      return res.status(400).json({ message: "Invalid spot id" });
    }

    const parsed = getRequestUserId(req);
    if (!parsed.ok) {
      return res.status(400).json({ message: parsed.message });
    }

    const spotQ = await client.query(
      `
      SELECT
        se.id,
        se.created_by_user_id,
        se.creator_role,
        se.km_per_round,
        se.round_count,
        se.owner_completed_at,
        se.owner_completed_distance_km
      FROM public.spot_events se
      WHERE se.id = $1
      LIMIT 1
      `,
      [spotId]
    );
    if (spotQ.rowCount === 0) {
      return res.status(404).json({ message: "Spot not found" });
    }

    const spot = spotQ.rows[0];
    const taskType = String(req.body?.task_type ?? "").trim().toLowerCase();
    const isOwnerCompletion =
      taskType === "spot_created" &&
      Number(spot.created_by_user_id) === Number(parsed.userId) &&
      String(spot.creator_role ?? "user").toLowerCase() === "user";

    const membershipQ = await client.query(
      `
      SELECT
        sem.id,
        sem.completed_at,
        sem.completed_distance_km,
        se.km_per_round,
        se.round_count
      FROM public.spot_event_members sem
      JOIN public.spot_events se ON se.id = sem.spot_event_id
      WHERE sem.spot_event_id = $1 AND sem.user_id = $2
      LIMIT 1
      `,
      [spotId, parsed.userId]
    );
    if (membershipQ.rowCount === 0) {
      if (!isOwnerCompletion) {
        return res.status(404).json({ message: "Spot membership not found" });
      }
    }

    const fallbackDistance =
      Number(membershipQ.rows[0]?.km_per_round ?? spot.km_per_round ?? 0) *
      Number(membershipQ.rows[0]?.round_count ?? spot.round_count ?? 0);
    const ownerComputedDistanceKm =
      Number(spot.km_per_round ?? 0) * Number(spot.round_count ?? 0);
    const requestedDistanceKm = parseNullableKm(req.body?.distance_km);
    const existingCompletedDistanceKm = parseNullableKm(
      isOwnerCompletion
        ? spot.owner_completed_distance_km
        : membershipQ.rows[0]?.completed_distance_km
    );
    const completedDistanceKm = isOwnerCompletion
      ? ownerComputedDistanceKm > 0
          ? ownerComputedDistanceKm
          : existingCompletedDistanceKm != null
              ? existingCompletedDistanceKm
              : fallbackDistance
      : requestedDistanceKm != null
          ? requestedDistanceKm
          : existingCompletedDistanceKm != null
              ? existingCompletedDistanceKm
              : fallbackDistance;
    if (completedDistanceKm < 0) {
      return res.status(400).json({ message: "distance_km must be non-negative" });
    }

    let completedAt = null;
    if (isOwnerCompletion && spot.owner_completed_at) {
      return res.json({
        ok: true,
        completed: true,
        already_completed: true,
        completion_scope: "spot_created",
        completed_at: spot.owner_completed_at,
        completed_distance_km: resolveCompletedSpotDistanceValue(
          existingCompletedDistanceKm,
          spot.km_per_round,
          spot.round_count
        ),
      });
    }
    if (!isOwnerCompletion && membershipQ.rows[0]?.completed_at) {
      return res.json({
        ok: true,
        completed: true,
        already_completed: true,
        completion_scope: "spot_joined",
        completed_at: membershipQ.rows[0].completed_at,
        completed_distance_km: resolveCompletedSpotDistanceValue(
          existingCompletedDistanceKm,
          membershipQ.rows[0]?.km_per_round,
          membershipQ.rows[0]?.round_count
        ),
      });
    }

    if (!isOwnerCompletion && membershipQ.rowCount > 0) {
      const updatedQ = await client.query(
        `
        UPDATE public.spot_event_members
        SET
          completed_at = COALESCE($3::timestamptz, NOW()),
          completed_distance_km = $4,
          joined_at = COALESCE(joined_at, NOW())
        WHERE spot_event_id = $1 AND user_id = $2
        RETURNING id, completed_at, completed_distance_km
        `,
        [
          spotId,
          parsed.userId,
          req.body?.completed_at ?? null,
          completedDistanceKm,
        ]
      );
      completedAt = updatedQ.rows[0]?.completed_at ?? null;

      await client.query(
        `
        UPDATE public.spot_event_bookings
        SET
          status = 'completed',
          completed_at = COALESCE($3::timestamptz, NOW()),
          completed_distance_km = $4,
          updated_at = NOW()
        WHERE spot_event_id = $1 AND user_id = $2
        `,
        [
          spotId,
          parsed.userId,
          req.body?.completed_at ?? null,
          completedDistanceKm,
        ]
      );
    }

    if (isOwnerCompletion) {
      const ownerQ = await client.query(
        `
        UPDATE public.spot_events
        SET
          owner_completed_at = COALESCE($3::timestamptz, NOW()),
          owner_completed_distance_km = $4,
          updated_at = NOW()
        WHERE id = $1 AND created_by_user_id = $2
        RETURNING owner_completed_at, owner_completed_distance_km
        `,
        [
          spotId,
          parsed.userId,
          req.body?.completed_at ?? null,
          completedDistanceKm,
        ]
      );
      completedAt = ownerQ.rows[0]?.owner_completed_at ?? completedAt;
    }

    return res.json({
      ok: true,
      completed: true,
      completion_scope: isOwnerCompletion ? "spot_created" : "spot_joined",
      completed_at: completedAt,
      completed_distance_km: Number(completedDistanceKm),
    });
  } catch (e) {
    console.error("Complete spot error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
}

app.post("/api/spots/:id/complete", handleSpotComplete);
app.patch("/api/spots/:id/complete", handleSpotComplete);

app.delete("/api/spots/:id", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();

    const spotId = Number(req.params.id);
    if (!Number.isFinite(spotId) || spotId <= 0) {
      return res.status(400).json({ message: "Invalid spot id" });
    }

    const adminParse = getRequestAdminId(req, { allowBody: false });
    const userParse = getRequestUserId(req, { allowBody: false });

    const spotQ = await client.query(
      `
      SELECT id, created_by_user_id, creator_role
      FROM public.spot_events
      WHERE id = $1
      LIMIT 1
      `,
      [spotId]
    );
    if (spotQ.rowCount === 0) {
      return res.status(404).json({ message: "Spot not found" });
    }

    const spot = spotQ.rows[0];
    const canDelete =
      (adminParse.ok &&
        spot.creator_role === "admin" &&
        Number(spot.created_by_user_id) === adminParse.adminId) ||
      (userParse.ok &&
        spot.creator_role === "user" &&
        Number(spot.created_by_user_id) === userParse.userId);

    if (!canDelete) {
      return res.status(403).json({ message: "Not allowed to delete this spot" });
    }

    await client.query(`DELETE FROM public.spot_events WHERE id = $1`, [spotId]);
    return res.json({ ok: true, deleted_spot_id: spotId });
  } catch (e) {
    console.error("Delete spot error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.get("/api/spot-chat/messages", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();

    const spotKey = String(req.query?.spot_key ?? "").trim();
    if (!spotKey) {
      return res.status(400).json({ message: "spot_key is required" });
    }

    const spotContext = await loadSpotChatContextByKey(pool, spotKey, null);
    const spotEventId = spotContext?.id ?? parseSpotIdFromChatKey(spotKey);

    const q = await pool.query(
      `
      SELECT
        m.id,
        m.spot_key,
        m.user_id,
        m.sender_name,
        m.client_message_key,
        m.message,
        m.contains_url,
        m.moderation_status,
        m.risk_level,
        m.phishing_scan_status,
        m.phishing_scan_reason,
        m.final_safety_source,
        m.decision_priority,
        m.blocked_at,
        m.created_at,
        COALESCE(l.action_taken = 'censor_and_warn', FALSE) AS flagged_visible,
        CASE
          WHEN l.action_taken = 'censor_and_warn'
          THEN 'This message was censored for inappropriate language.'
          ELSE NULL
        END AS visible_warning
      FROM public.spot_chat_messages m
      LEFT JOIN LATERAL (
        SELECT action_taken
        FROM public.chat_moderation_logs l
        WHERE l.message_id = m.id
        ORDER BY l.id DESC
        LIMIT 1
      ) l ON TRUE
      WHERE m.spot_key = $1
         OR ($2::bigint IS NOT NULL AND m.spot_event_id = $2)
      ORDER BY m.created_at ASC, m.id ASC
      `,
      [spotKey, spotEventId]
    );

    return res.json(q.rows);
  } catch (e) {
    console.error("Load spot chat messages error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.post("/api/moderate/chat-message", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const text = String(req.body?.text ?? "").trim();
    if (!text) {
      return res.status(400).json({ message: "text is required" });
    }

    const analyzedResult = await analyzeSpotChatMessage(text);
    const result = await applyReviewedModerationMemory(pool, analyzedResult);
    const action =
      result.decision.action === "allow" &&
      result.needs_human_review === true
        ? "review"
        : result.decision.action === "allow"
        ? "allow"
        : result.decision.action === "censor_and_warn"
          ? "warn"
          : "block";

    const reasons = [
      ...(Array.isArray(result.categories)
        ? result.categories.map((category) => `category:${category}`)
        : []),
      ...(Array.isArray(result.rule_hits)
        ? result.rule_hits
            .map((hit) => String(hit?.rule_id ?? hit?.label ?? "").trim())
            .filter(Boolean)
            .map((label) => `rule:${label}`)
        : []),
      ...(Array.isArray(result.ai_reasons)
        ? result.ai_reasons
            .map((reason) => String(reason ?? "").trim())
            .filter(Boolean)
            .map((reason) => `ai:${reason}`)
        : []),
      ...(result.reviewed_memory?.applied === true
        ? [
            `memory:${String(result.reviewed_memory.queue_status ?? "reviewed").trim() || "reviewed"}`,
          ]
        : []),
    ];

    const userMessage =
      action === "block"
        ? "This message was blocked by moderation policy."
        : action === "review"
          ? "This message may need moderation review. Continue with caution."
        : action === "warn"
          ? "This message may violate chat guidelines. Please confirm before sending."
          : null;

    try {
      await insertChatModerationPreviewLog({
        rawMessage: result.raw_message,
        normalizedMessage: result.normalized_message,
        detectedCategories: result.categories,
        severity: result.decision.severity,
        actionTaken: result.decision.action,
        ruleHits: result.rule_hits,
        aiResultJson: {
          gemini: result.ai,
          openai_reasoned: buildStoredOpenAIReasonedResult(result.openai_reasoned),
          openai: result.openai,
          safety: result.safety,
          knowledge: result.knowledge,
        },
        aiUsed: result.ai_used,
        aiConfidence: result.ai_confidence,
      });
    } catch (previewLogErr) {
      console.error("Insert moderation preview log error:", previewLogErr);
    }

    return res.json({
      action,
      reasons: Array.from(new Set(reasons)),
      userMessage,
      severity: result.decision.severity,
      categories: result.categories,
      moderation: {
        action: result.decision.action,
        primary_category: result.decision.primary_category,
        visible_message_mode: result.decision.visible_message_mode,
        ai_used: result.ai_used,
        ai_confidence: result.ai_confidence,
        needs_human_review: result.needs_human_review === true,
        reviewed_memory: result.reviewed_memory ?? null,
        safety: result.safety,
        knowledge: result.knowledge,
        openai_reasoned: buildStoredOpenAIReasonedResult(result.openai_reasoned),
      },
    });
  } catch (e) {
    console.error("Moderate chat message error:", e?.message ?? e);
    return res.status(500).json({ message: "Moderation error" });
  }
});

app.get("/api/spot-chat/room-alerts", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();

    const spotKey = String(req.query?.spot_key ?? "").trim();
    if (!spotKey) {
      return res.status(400).json({ message: "spot_key is required" });
    }

    const spotContext = await loadSpotChatContextByKey(pool, spotKey, null);
    const spotEventId = spotContext?.id ?? parseSpotIdFromChatKey(spotKey);

    const q = await pool.query(
      `
      SELECT
        a.id,
        a.spot_key,
        a.alert_type,
        a.message,
        a.created_at,
        l.message_id AS source_message_id
      FROM public.spot_chat_room_alerts a
      LEFT JOIN public.chat_moderation_logs l
        ON l.id = a.source_log_id
      WHERE (a.spot_key = $1 OR ($2::bigint IS NOT NULL AND a.spot_event_id = $2))
        AND a.is_active = TRUE
        AND (a.expires_at IS NULL OR a.expires_at > NOW())
      ORDER BY a.created_at ASC, a.id ASC
      `,
      [spotKey, spotEventId]
    );

    return res.json(q.rows);
  } catch (e) {
    console.error("Load spot chat room alerts error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/spot-chat/room-status", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();

    const spotKey = String(req.query?.spot_key ?? "").trim();
    if (!spotKey) {
      return res.status(400).json({ message: "spot_key is required" });
    }

    const parsed = getRequestUserId(req, { allowQuery: true, allowBody: false });
    const userId = parsed.ok ? parsed.userId : null;
    const spotContext = await loadSpotChatContextByKey(pool, spotKey, userId);

    return res.json({
      spot_id: spotContext?.id ?? parseSpotIdFromChatKey(spotKey),
      spot_key: spotContext?.spot_key ?? spotKey,
      status: spotContext?.status ?? null,
      room_closed: spotContext?.chat_closed === true,
      closed_at: spotContext?.chat_closed_at ?? null,
      reason_code: spotContext?.chat_closed_reason ?? null,
      user_message:
        spotContext?.chat_closed === true
          ? "This Spot chat room is closed because the event has already ended."
          : null,
    });
  } catch (e) {
    console.error("Load spot chat room status error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.post("/api/spot-chat/messages", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();

    const parsed = getRequestUserId(req);
    if (!parsed.ok) {
      return res.status(400).json({ message: parsed.message });
    }

    const spotKey = String(req.body?.spot_key ?? "").trim();
    const message = String(req.body?.message ?? "").trim();
    const clientMessageKey = String(
      req.body?.client_message_key ?? req.body?.clientMessageKey ?? ""
    ).trim();
    if (!spotKey || !message) {
      return res.status(400).json({ message: "spot_key and message are required" });
    }

    const senderQ = await client.query(
      `
      SELECT
        COALESCE(
          NULLIF(TRIM(COALESCE(name, '')), ''),
          NULLIF(TRIM(CONCAT_WS(' ', first_name, last_name)), ''),
          NULLIF(TRIM(COALESCE(email, '')), ''),
          'User'
        ) AS sender_name,
        COALESCE(status, 'active') AS status
      FROM public.users
      WHERE id = $1
      LIMIT 1
      `,
      [parsed.userId]
    );
    if (senderQ.rowCount === 0) {
      return res.status(404).json({ message: "User not found" });
    }

    if (senderQ.rows[0].status !== "active") {
      return res.status(403).json({ message: "Account not active" });
    }

    const spotContext = await loadSpotChatContextByKey(client, spotKey, parsed.userId);
    if (
      spotContext?.chat_closed === true ||
      (spotContext?.status && ["closed", "cancelled", "canceled"].includes(spotContext.status.toLowerCase()))
    ) {
      return res.status(403).json({
        message: "Spot chat room is closed",
        user_message:
          spotContext?.chat_closed_reason === "event_ended"
            ? "This Spot chat room is closed because the event has already ended."
            : "This Spot chat room is closed.",
        reason_code: spotContext?.chat_closed_reason ?? "chat_closed",
        room_closed: true,
        closed_at: spotContext?.chat_closed_at ?? null,
      });
    }
    if (spotContext && !spotContext.is_owner && !spotContext.is_member) {
      return res.status(403).json({
        message: "You are no longer allowed in this Spot chat room",
        user_message: "You are no longer allowed to send messages in this Spot chat room.",
      });
    }

    const analyzedModeration = await analyzeSpotChatMessage(message);
    const moderation = await applyReviewedModerationMemory(
      client,
      analyzedModeration
    );
    // Hybrid model:
    // moderation = abuse/profanity
    // phishing DB/rules = known phishing authority
    // AI scam layer = suspicious unknown phishing warning only
    const priority =
      moderation.decision.action === "block_remove_and_report"
        ? "urgent"
        : moderation.decision.action === "block_and_alert_room"
          ? "high"
          : moderation.decision.action === "block_and_report"
            ? "high"
            : moderation.decision.action === "block_and_flag"
              ? "medium"
            : "normal";

    await client.query("BEGIN");

    const visibleMessage = moderation.decision.action === "censor_and_warn"
      ? buildCensoredChatMessage(message, moderation)
      : message;

    let insertedMessage = null;
    let phishingScanResult = null;
    if (moderation.decision.save_message) {
      const inserted = await client.query(
        `
        INSERT INTO public.spot_chat_messages
          (
            spot_key,
            spot_event_id,
            user_id,
            sender_name,
            client_message_key,
            message,
            contains_url,
            moderation_status,
            risk_level,
            phishing_scan_status,
            phishing_scan_reason,
            final_safety_source,
            decision_priority,
            blocked_at,
            created_at
          )
        VALUES
          ($1, $2, $3, $4, $5, $6, FALSE, 'visible', 'safe', 'not_scanned', NULL, 'safe', 0, NULL, NOW())
        RETURNING
          id,
          spot_key,
          spot_event_id,
          user_id,
          sender_name,
          client_message_key,
          message,
          contains_url,
          moderation_status,
          risk_level,
          phishing_scan_status,
          phishing_scan_reason,
          final_safety_source,
          decision_priority,
          blocked_at,
          created_at
        `,
        [
          spotKey,
          spotContext?.id ?? null,
          parsed.userId,
          senderQ.rows[0].sender_name,
          clientMessageKey || null,
          visibleMessage,
        ]
      );
      insertedMessage = inserted.rows[0] ?? null;

      // Phishing scan is the source of truth for URL/scam safety in Spot chat.
      // Moderation may still log scam/url hints, but it does not block on those
      // hints alone. The saved row is updated with phishing-owned message state.
      phishingScanResult = await scanSpotChatMessageUrls(client, message);
      const aiScamOutcome = buildSpotChatAiScamSuspicionOutcome({
        moderation,
        phishingScanResult,
      });
      const finalSafety = buildSpotChatFinalDecision({
        moderation,
        phishingScanResult,
        aiScamOutcome,
      });
      const persistedDecisionPriority = Number.isFinite(finalSafety.decisionPriority)
        ? Number(finalSafety.decisionPriority)
        : getSpotChatDecisionPriority({
            finalSafetySource: finalSafety.finalSafetySource,
            finalMessageState: finalSafety.finalMessageState,
          });

      for (const scan of phishingScanResult.scans) {
        await insertSpotChatUrlScanLog(client, {
          chatMessageId: insertedMessage.id,
          scannedUrl: scan.scannedUrl,
          normalizedUrl: scan.normalizedUrl,
          matchedIndicatorId: scan.matchedIndicatorId,
          sourceName: scan.sourceName,
          result: scan.result,
          confidenceScore: scan.confidenceScore,
          detectionMethod: scan.detectionMethod,
          reason: scan.reason,
        });
      }

      const updated = await client.query(
        `
        UPDATE public.spot_chat_messages
        SET
          contains_url = $2,
          moderation_status = $3,
          risk_level = $4,
          phishing_scan_status = $5,
          phishing_scan_reason = $6,
          final_safety_source = $7,
          decision_priority = $8,
          blocked_at = $9
        WHERE id = $1
        RETURNING
          id,
          spot_key,
          spot_event_id,
          user_id,
          sender_name,
          client_message_key,
          message,
          contains_url,
          moderation_status,
          risk_level,
          phishing_scan_status,
          phishing_scan_reason,
          final_safety_source,
          decision_priority,
          blocked_at,
          created_at
        `,
        [
          insertedMessage.id,
          phishingScanResult.containsUrl,
          finalSafety.moderationStatus,
          finalSafety.riskLevel,
          finalSafety.phishingScanStatus,
          finalSafety.phishingScanReason,
          finalSafety.finalSafetySource,
          persistedDecisionPriority,
          finalSafety.blockedAt,
        ]
      );
      insertedMessage = updated.rows[0] ?? insertedMessage;
      insertedMessage = {
        ...insertedMessage,
        decision_priority: Number(
          updated.rows[0]?.decision_priority ?? persistedDecisionPriority
        ),
      };
      phishingScanResult = {
        ...phishingScanResult,
        moderationStatus: finalSafety.moderationStatus,
        riskLevel: finalSafety.riskLevel,
        phishingScanStatus: finalSafety.phishingScanStatus,
        phishingScanReason: finalSafety.phishingScanReason,
        finalSafetySource: finalSafety.finalSafetySource,
        finalMessageState: finalSafety.finalMessageState,
        decisionPriority: persistedDecisionPriority,
        blockedAt: finalSafety.blockedAt,
      };
    }

    const moderationLogId = await insertChatModerationLog(client, {
      messageId: insertedMessage?.id ?? null,
      userId: parsed.userId,
      spotKey,
      spotEventId: spotContext?.id ?? null,
      rawMessage: message,
      normalizedMessage: moderation.normalized_message,
      detectedCategories: moderation.categories,
      severity: moderation.decision.severity,
      actionTaken: moderation.decision.action,
      ruleHits: moderation.rule_hits,
      aiResultJson: {
        gemini: moderation.ai,
        openai_reasoned: buildStoredOpenAIReasonedResult(moderation.openai_reasoned),
        openai: moderation.openai,
        safety: moderation.safety,
        knowledge: moderation.knowledge,
      },
      aiUsed: moderation.ai_used,
      aiConfidence: moderation.ai_confidence,
      suspensionRequired: moderation.decision.suspension_required,
    });

    let moderationQueueItem = null;
    if (moderation.decision.enqueue_admin_review) {
      moderationQueueItem = await insertChatModerationQueueItem(client, {
        moderationLogId,
        userId: parsed.userId,
        spotKey,
        spotEventId: spotContext?.id ?? null,
        priority,
        alertRoom: moderation.decision.alert_room,
        suspensionRequired: moderation.decision.suspension_required,
        reviewPayload: {
          action: moderation.decision.action,
          categories: moderation.categories,
          severity: moderation.decision.severity,
          primary_category: moderation.decision.primary_category,
          visible_message_mode: moderation.decision.visible_message_mode,
          ai_used: moderation.ai_used,
          ai_confidence: moderation.ai_confidence,
          ai_requested: moderation.ai_reasons,
          signal_split: moderation.signal_split,
          phishing_delegated: moderation.phishing_delegated === true,
          gemini: moderation.ai,
          openai_reasoned: buildStoredOpenAIReasonedResult(moderation.openai_reasoned),
          openai: moderation.openai,
          safety: moderation.safety,
          knowledge: moderation.knowledge,
        },
      });
    }

    let roomAlert = null;
    if (isSpotChatPhishingAlertRequired(phishingScanResult)) {
      try {
        const roomAlertExistingBefore = await client.query(
          `
          SELECT id
          FROM public.spot_chat_room_alerts
          WHERE spot_key = $1
            AND alert_type = 'scam_warning'
            AND message = $2
            AND is_active = TRUE
            AND (expires_at IS NULL OR expires_at > NOW())
            AND created_at >= NOW() - INTERVAL '15 minutes'
          ORDER BY created_at DESC, id DESC
          LIMIT 1
          `,
          [
            spotKey,
            "Warning: A potentially fraudulent message was detected. Do not transfer money or share personal information.",
          ]
        );
        roomAlert = await createOrReuseSpotChatRoomAlert(client, {
          spotKey,
          spotEventId: spotContext?.id ?? null,
          alertType: "scam_warning",
          message:
            "Warning: A potentially fraudulent message was detected. Do not transfer money or share personal information.",
          triggeredByUserId: parsed.userId,
          sourceQueueId: moderationQueueItem?.id ?? null,
          sourceLogId: moderationLogId,
          expiresAt: null,
        });
        await insertAuditLog(client, {
          userId: parsed.userId,
          actorType: "system",
          action: roomAlertExistingBefore.rowCount > 0
            ? "SPOT_CHAT_ROOM_ALERT_REUSED"
            : "SPOT_CHAT_ROOM_ALERT_CREATED",
          entityTable: "spot_chat_room_alerts",
          entityId: roomAlert?.id ?? null,
          metadata: {
            moderation_log_id: moderationLogId,
            moderation_queue_id: moderationQueueItem?.id ?? null,
            spot_key: spotKey,
            phishing_risk_level: phishingScanResult?.riskLevel ?? null,
            phishing_scan_status: phishingScanResult?.phishingScanStatus ?? null,
            alert_type: roomAlert?.alert_type ?? "scam_warning",
          },
        });
      } catch (roomAlertErr) {
        console.error("Create spot chat room alert error:", roomAlertErr);
      }
    }

    if (!moderation.decision.save_message && moderation.ai_used) {
      try {
        await insertAuditLog(client, {
          userId: parsed.userId,
          actorType: "system",
          action: "SPOT_CHAT_GEMINI_USED_FOR_BLOCKED_CASE",
          entityTable: "chat_moderation_logs",
          entityId: moderationLogId,
          metadata: {
            spot_key: spotKey,
            severity: moderation.decision.severity,
            categories: moderation.categories,
            signal_split: moderation.signal_split,
            ai_confidence: moderation.ai_confidence,
            final_action: moderation.decision.action,
          },
        });
      } catch (auditErr) {
        console.error("Insert Gemini moderation audit error:", auditErr);
      }
    }

    const suggestionCategory = moderation.ai.result?.categories?.[0] ?? null;
    if (moderation.ai_used && suggestionCategory) {
      try {
        await createModerationVocabularySuggestions(client, {
          userId: parsed.userId,
          spotKey,
          rawMessage: moderation.raw_message,
          category: suggestionCategory,
          confidence: moderation.ai_confidence,
          suggestedTerms: moderation.ai_suggested_terms,
        });
      } catch (suggestionErr) {
        console.error("Create moderation vocabulary suggestion error:", suggestionErr);
      }
    }

    let severeOutcome = null;
    if (moderation.decision.remove_from_room) {
      severeOutcome = await applySpotChatSevereModerationConsequences(client, {
        userId: parsed.userId,
        spotKey,
        spotContext,
        moderationLogId,
        moderationQueueId: moderationQueueItem?.id ?? null,
        primaryCategory: moderation.decision.primary_category,
        action: moderation.decision.action,
      });
    }

    await client.query("COMMIT");

    if (!moderation.decision.save_message) {
      const isScamAlert = moderation.decision.alert_room;
      const severeRemoval = moderation.decision.remove_from_room;
      return res.status(403).json({
        message: "Message blocked by moderation policy",
        blocked: true,
        moderation_triggered: true,
        reason_code: moderation.decision.primary_category || "policy_blocked",
        room_alert_required: isScamAlert,
        popup_type: "blocked",
        room_alert: roomAlert
          ? {
              id: roomAlert.id,
              alert_type: roomAlert.alert_type,
              message: roomAlert.message,
              created_at: roomAlert.created_at,
            }
          : null,
        user_message: isScamAlert
          ? "Your message was blocked because it appears suspicious."
          : severeRemoval
            ? "Your message was blocked because it contains inappropriate or harmful language. You have been removed from this chat room."
            : "Your message was blocked because it contains inappropriate or harmful language.",
        moderation: {
          action: moderation.decision.action,
          categories: moderation.categories,
          severity: moderation.decision.severity,
          room_alert_required: moderation.decision.alert_room,
          suspension_required: moderation.decision.suspension_required,
          signal_split: moderation.signal_split,
          phishing_delegated: moderation.phishing_delegated === true,
          sender_removed_from_room: severeOutcome?.sender_removed === true,
          room_closed: severeOutcome?.room_closed === true,
          needs_admin_review: true,
          ai_used: moderation.ai_used,
          knowledge: moderation.knowledge,
          openai_reasoned: buildStoredOpenAIReasonedResult(moderation.openai_reasoned),
        },
        safety: {
          final_message_state: "blocked",
          final_safety_source: "language_moderation",
          decision_priority: 100,
          risk_level: "safe",
          moderation_status: "blocked",
          phishing_scan_status: "not_scanned",
          phishing_scan_reason: null,
        },
      });
    }

    return res.status(201).json({
      ...insertedMessage,
      moderation_triggered: moderation.decision.action !== "allow",
      phishing_triggered:
        String(insertedMessage?.final_safety_source ?? "safe") !== "safe",
      popup_type: moderation.decision.action === "censor_and_warn" ? "warning" : null,
      user_message: moderation.decision.action === "censor_and_warn"
        ? "You used inappropriate language. Please be respectful."
        : null,
      moderation: {
        action: moderation.decision.action,
        categories: moderation.categories,
        severity: moderation.decision.severity,
        flagged: moderation.decision.action === "censor_and_warn",
        visible_message_mode: moderation.decision.visible_message_mode,
        signal_split: moderation.signal_split,
        phishing_delegated: moderation.phishing_delegated === true,
        ai_used: moderation.ai_used,
        ai_confidence: moderation.ai_confidence,
        knowledge: moderation.knowledge,
        openai_reasoned: buildStoredOpenAIReasonedResult(moderation.openai_reasoned),
      },
      safety: {
        final_message_state:
          insertedMessage?.moderation_status === "blocked"
            ? "blocked"
            : insertedMessage?.moderation_status === "warning"
              ? "warning"
              : "visible",
        final_safety_source: insertedMessage?.final_safety_source ?? "safe",
        decision_priority: Number(insertedMessage?.decision_priority ?? 0),
        risk_level: insertedMessage?.risk_level ?? "safe",
        moderation_status: insertedMessage?.moderation_status ?? "visible",
        phishing_scan_status: insertedMessage?.phishing_scan_status ?? "not_scanned",
        phishing_scan_reason: insertedMessage?.phishing_scan_reason ?? null,
      },
    });
  } catch (e) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {}
    console.error("Send spot chat message error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.post("/api/spot-chat/report-user", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();

    const parsed = getRequestUserId(req);
    if (!parsed.ok) {
      return res.status(400).json({ message: parsed.message });
    }

    const reportedUserId = Number(req.body?.reported_user_id);
    const messageId = req.body?.message_id == null ? null : Number(req.body.message_id);
    const spotKey = String(req.body?.spot_key ?? "").trim();
    const reasonCode = String(req.body?.reason_code ?? "INAPPROPRIATE_LANGUAGE").trim() || "INAPPROPRIATE_LANGUAGE";
    const note = String(req.body?.note ?? "").trim();

    if (!Number.isInteger(reportedUserId) || reportedUserId <= 0 || !spotKey) {
      return res.status(400).json({ message: "reported_user_id and spot_key are required" });
    }
    if (reportedUserId === parsed.userId) {
      return res.status(400).json({ message: "Cannot report yourself" });
    }

    const reportQ = await client.query(
      `
      INSERT INTO public.spot_chat_user_reports
        (reporter_user_id, reported_user_id, spot_key, message_id, reason_code, note, created_at)
      VALUES
        ($1, $2, $3, $4, $5, $6, NOW())
      RETURNING id, reporter_user_id, reported_user_id, spot_key, message_id, reason_code, note, created_at
      `,
      [
        parsed.userId,
        reportedUserId,
        spotKey,
        Number.isInteger(messageId) && messageId > 0 ? messageId : null,
        reasonCode,
        note || null,
      ]
    );

    try {
      await insertAuditLog(client, {
        userId: parsed.userId,
        actorType: "user",
        action: "SPOT_CHAT_USER_REPORTED",
        entityTable: "spot_chat_user_reports",
        entityId: reportQ.rows[0]?.id ?? null,
        metadata: {
          reported_user_id: reportedUserId,
          spot_key: spotKey,
          message_id: Number.isInteger(messageId) && messageId > 0 ? messageId : null,
          reason_code: reasonCode,
        },
      });
    } catch (auditErr) {
      console.error("Insert spot chat report audit error:", auditErr);
    }

    return res.status(201).json({
      ok: true,
      user_message: "Report submitted. Thank you.",
      report: reportQ.rows[0] ?? null,
    });
  } catch (e) {
    console.error("Spot chat report user error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.post("/api/security/feeds/phishtank/sync", async (req, res) => {
  const client = await pool.connect();
  try {
    const dryRunQuery = String(req.query?.dry_run ?? req.query?.dryRun ?? "")
      .trim()
      .toLowerCase();
    const dryRunBody = String(req.body?.dry_run ?? req.body?.dryRun ?? "")
      .trim()
      .toLowerCase();
    const dryRun =
      dryRunQuery === "true" ||
      dryRunQuery === "1" ||
      dryRunBody === "true" ||
      dryRunBody === "1";

    // This route refreshes local phishing indicators from PhishTank so the
    // Spot chat URL scan can rely on database lookups instead of sample data.
    const summary = await syncPhishTankFeed(client, { dryRun });
    return res.json({
      ok: true,
      source: "phishtank",
      ...summary,
    });
  } catch (e) {
    console.error("PhishTank sync route error:", e);
    return res.status(500).json({
      ok: false,
      source: "phishtank",
      message: "PhishTank sync failed",
      error: String(e?.message ?? e),
    });
  } finally {
    client.release();
  }
});

app.get("/api/security/stats", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();

    const statsQ = await pool.query(
      `
      WITH message_stats AS (
        SELECT
          COUNT(*)::bigint AS total_messages,
          COUNT(*) FILTER (WHERE phishing_scan_status = 'scanned')::bigint AS total_scanned,
          COUNT(*) FILTER (WHERE risk_level = 'phishing')::bigint AS phishing_detected,
          COUNT(*) FILTER (WHERE risk_level = 'suspicious')::bigint AS suspicious_detected,
          COUNT(*) FILTER (WHERE final_safety_source = 'language_moderation' AND moderation_status = 'blocked')::bigint AS moderation_blocked,
          COUNT(*) FILTER (WHERE final_safety_source = 'safe')::bigint AS safe_messages
        FROM public.spot_chat_messages
      ),
      url_scan_stats AS (
        SELECT
          COUNT(*)::bigint AS total_url_scans,
          COUNT(*) FILTER (WHERE result = 'phishing')::bigint AS phishing_url_scans,
          COUNT(*) FILTER (WHERE result = 'suspicious')::bigint AS suspicious_url_scans
        FROM public.chat_message_url_scans
      )
      SELECT
        ms.total_messages,
        ms.total_scanned,
        ms.phishing_detected,
        ms.suspicious_detected,
        ms.moderation_blocked,
        ms.safe_messages,
        us.total_url_scans,
        us.phishing_url_scans,
        us.suspicious_url_scans
      FROM message_stats ms
      CROSS JOIN url_scan_stats us
      `
    );

    return res.json(statsQ.rows[0] ?? {
      total_messages: 0,
      total_scanned: 0,
      phishing_detected: 0,
      suspicious_detected: 0,
      moderation_blocked: 0,
      safe_messages: 0,
      total_url_scans: 0,
      phishing_url_scans: 0,
      suspicious_url_scans: 0,
    });
  } catch (e) {
    console.error("Load security stats error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/spot-chat/moderation-queue", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const queueStatus = String(req.query?.status ?? "pending").trim().toLowerCase() || "pending";
    const rawLimit = Number(req.query?.limit ?? 100);
    const limit = Number.isInteger(rawLimit) && rawLimit > 0 ? Math.min(rawLimit, 200) : 100;
    let whereSql = "";
    let params = [];

    if (queueStatus !== "all") {
      if (queueStatus === "pending") {
        whereSql = "WHERE q.queue_status IN ('pending', 'open')";
      } else {
        whereSql = "WHERE q.queue_status = $1";
        params.push(queueStatus);
      }
    }

    params.push(limit);

    const q = await pool.query(
      `
      SELECT
        q.id,
        q.queue_status,
        q.priority,
        q.alert_room,
        q.suspension_required,
        q.review_payload,
        q.reviewed_by_admin_id,
        q.reviewed_at,
        q.review_note,
        q.created_at,
        l.id AS moderation_log_id,
        l.message_id,
        l.user_id,
        l.spot_key,
        l.spot_event_id,
        l.raw_message,
        l.normalized_message,
        l.detected_categories,
        l.severity,
        l.action_taken,
        l.rule_hits,
        l.ai_used,
        l.ai_confidence,
        l.ai_result_json
      FROM public.chat_moderation_queue q
      JOIN public.chat_moderation_logs l ON l.id = q.moderation_log_id
      ${whereSql}
      ORDER BY q.created_at DESC, q.id DESC
      LIMIT $${params.length}
      `,
      params
    );

    return res.json(q.rows);
  } catch (e) {
    console.error("Load spot chat moderation queue error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.patch("/api/admin/spot-chat/moderation-queue/:id/dismiss", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowQuery: false, allowBody: true });
    if (!adminCtx) return;

    const queueId = Number(req.params.id);
    if (!Number.isInteger(queueId) || queueId <= 0) {
      return res.status(400).json({ message: "Invalid moderation queue id" });
    }

    const existing = await loadModerationQueueItem(client, queueId);
    if (!existing) {
      return res.status(404).json({ message: "Moderation queue item not found" });
    }

    if (String(existing.queue_status || "").toLowerCase() === "suspended") {
      return res.status(409).json({ message: "Suspended cases cannot be dismissed" });
    }

    const updated = await updateModerationQueueReview(client, {
      queueId,
      queueStatus: "dismissed",
      adminId: adminCtx.adminId,
      reviewNote: String(req.body?.review_note ?? "").trim() || null,
    });
    await insertAuditLog(client, {
      adminUserId: adminCtx.adminId,
      actorType: "admin",
      action: "SPOT_CHAT_QUEUE_DISMISSED",
      entityTable: "chat_moderation_queue",
      entityId: queueId,
      metadata: {
        moderation_queue_id: queueId,
        target_user_id: existing.user_id,
        spot_key: existing.spot_key,
        detected_categories: existing.detected_categories,
        final_action: existing.action_taken,
        severity: existing.severity,
        review_note: String(req.body?.review_note ?? "").trim() || null,
      },
    });

    return res.json({ ok: true, item: updated });
  } catch (e) {
    console.error("Dismiss moderation queue item error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.patch("/api/admin/spot-chat/moderation-queue/:id/confirm", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowQuery: false, allowBody: true });
    if (!adminCtx) return;

    const queueId = Number(req.params.id);
    if (!Number.isInteger(queueId) || queueId <= 0) {
      return res.status(400).json({ message: "Invalid moderation queue id" });
    }

    const existing = await loadModerationQueueItem(client, queueId);
    if (!existing) {
      return res.status(404).json({ message: "Moderation queue item not found" });
    }

    if (String(existing.queue_status || "").toLowerCase() === "suspended") {
      return res.status(409).json({ message: "Suspended cases are already finalized" });
    }

    const updated = await updateModerationQueueReview(client, {
      queueId,
      queueStatus: "confirmed",
      adminId: adminCtx.adminId,
      reviewNote: String(req.body?.review_note ?? "").trim() || null,
    });
    let autoLearnedTerms = [];
    try {
      autoLearnedTerms = await applyConfirmedQueueItemToVocabulary(client, existing);
    } catch (autoLearnErr) {
      console.error("Apply confirmed moderation vocabulary error:", autoLearnErr);
    }
    await insertAuditLog(client, {
      adminUserId: adminCtx.adminId,
      actorType: "admin",
      action: "SPOT_CHAT_QUEUE_CONFIRMED",
      entityTable: "chat_moderation_queue",
      entityId: queueId,
      metadata: {
        moderation_queue_id: queueId,
        target_user_id: existing.user_id,
        spot_key: existing.spot_key,
        detected_categories: existing.detected_categories,
        final_action: existing.action_taken,
        severity: existing.severity,
        auto_learned_terms: autoLearnedTerms,
        review_note: String(req.body?.review_note ?? "").trim() || null,
      },
    });

    return res.json({ ok: true, item: updated, auto_learned_terms: autoLearnedTerms });
  } catch (e) {
    console.error("Confirm moderation queue item error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.patch("/api/admin/spot-chat/moderation-queue/:id/suspend-user", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();
    await ensureUserAuthColumns();
    const adminCtx = await requireActiveAdmin(req, res, { allowQuery: false, allowBody: true });
    if (!adminCtx) return;

    const queueId = Number(req.params.id);
    if (!Number.isInteger(queueId) || queueId <= 0) {
      return res.status(400).json({ message: "Invalid moderation queue id" });
    }

    const existing = await loadModerationQueueItem(client, queueId);
    if (!existing) {
      return res.status(404).json({ message: "Moderation queue item not found" });
    }

    await client.query("BEGIN");

    await client.query(
      `
      UPDATE public.users
      SET status = 'suspended', updated_at = NOW()
      WHERE id = $1
      `,
      [existing.user_id]
    );

    const updated = await updateModerationQueueReview(client, {
      queueId,
      queueStatus: "suspended",
      adminId: adminCtx.adminId,
      reviewNote: String(req.body?.review_note ?? "").trim() || null,
    });

    await insertAuditLog(client, {
      adminUserId: adminCtx.adminId,
      actorType: "admin",
      action: "SPOT_CHAT_QUEUE_SUSPEND_USER",
      entityTable: "chat_moderation_queue",
      entityId: queueId,
      metadata: {
        moderation_queue_id: queueId,
        target_user_id: existing.user_id,
        spot_key: existing.spot_key,
        detected_categories: existing.detected_categories,
        final_action: existing.action_taken,
        severity: existing.severity,
        review_note: String(req.body?.review_note ?? "").trim() || null,
      },
    });
    await insertAuditLog(client, {
      adminUserId: adminCtx.adminId,
      userId: existing.user_id,
      actorType: "admin",
      action: "USER_SUSPENDED_FOR_MODERATION",
      entityTable: "users",
      entityId: existing.user_id,
      metadata: {
        moderation_queue_id: queueId,
        spot_key: existing.spot_key,
        detected_categories: existing.detected_categories,
        severity: existing.severity,
      },
    });

    await client.query("COMMIT");
    return res.json({ ok: true, item: updated, user_status: "suspended" });
  } catch (e) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {}
    console.error("Suspend user from moderation queue error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.get("/api/admin/spot-chat/learning-queue", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const status = String(req.query?.status ?? "pending").trim().toLowerCase();
    const params = [];
    let whereSql = "";
    if (status !== "all") {
      params.push(status);
      whereSql = `WHERE lq.status = $${params.length}`;
    }

    const q = await pool.query(
      `
      SELECT
        lq.*,
        q.user_id,
        q.spot_key,
        q.queue_status
      FROM public.chat_moderation_learning_queue lq
      LEFT JOIN public.chat_moderation_queue q ON q.id = lq.moderation_queue_id
      ${whereSql}
      ORDER BY lq.created_at DESC, lq.id DESC
      LIMIT 200
      `,
      params
    );

    return res.json(q.rows);
  } catch (e) {
    console.error("Load moderation learning queue error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.post("/api/admin/spot-chat/learning-queue", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowQuery: false, allowBody: true });
    if (!adminCtx) return;

    const sourceType = String(req.body?.source_type ?? "manual").trim().toLowerCase() || "manual";
    const suggestedAction = String(req.body?.suggested_action ?? "review").trim().toLowerCase() || "review";
    const allowedActions = new Set(["allow", "review", "block"]);
    if (!allowedActions.has(suggestedAction)) {
      return res.status(400).json({ message: "Invalid suggested_action" });
    }

    const moderationQueueId = Number(req.body?.moderation_queue_id);
    let queueItem = null;
    if (Number.isInteger(moderationQueueId) && moderationQueueId > 0) {
      queueItem = await loadModerationQueueItem(client, moderationQueueId);
      if (!queueItem) {
        return res.status(404).json({ message: "Moderation queue item not found" });
      }
    }

    const rawMessage = String(req.body?.raw_message ?? queueItem?.raw_message ?? "").trim();
    if (!rawMessage) {
      return res.status(400).json({ message: "raw_message is required" });
    }

    const normalizedMessage = String(
      req.body?.normalized_message ?? queueItem?.normalized_message ?? rawMessage
    ).trim();
    const currentCategories = sanitizeLearningQueueStringList(
      Array.isArray(req.body?.current_categories)
        ? req.body.current_categories
        : queueItem?.detected_categories ?? []
    );
    const suggestedCategories = sanitizeLearningQueueStringList(req.body?.suggested_categories);
    const candidateTerms = sanitizeLearningQueueStringList(req.body?.candidate_terms);
    const adminNote = String(req.body?.admin_note ?? "").trim() || null;

    await client.query("BEGIN");
    const inserted = await insertModerationLearningQueueItem(client, {
      sourceType,
      moderationQueueId: queueItem?.id ?? null,
      moderationLogId: queueItem?.moderation_log_id ?? null,
      previewLogId: Number.isInteger(Number(req.body?.preview_log_id))
        ? Number(req.body.preview_log_id)
        : null,
      rawMessage,
      normalizedMessage,
      currentCategories,
      suggestedAction,
      suggestedCategories,
      candidateTerms,
      adminNote,
      createdByAdminId: adminCtx.adminId,
    });

    await insertAuditLog(client, {
      adminUserId: adminCtx.adminId,
      actorType: "admin",
      action: "SPOT_CHAT_LEARNING_QUEUE_CREATED",
      entityTable: "chat_moderation_learning_queue",
      entityId: inserted?.id ?? null,
      metadata: {
        source_type: sourceType,
        moderation_queue_id: queueItem?.id ?? null,
        moderation_log_id: queueItem?.moderation_log_id ?? null,
        suggested_action: suggestedAction,
        suggested_categories: suggestedCategories,
        candidate_terms: candidateTerms,
      },
    });

    await client.query("COMMIT");
    return res.status(201).json(inserted ?? null);
  } catch (e) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {}
    console.error("Create moderation learning queue item error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.post("/api/admin/spot-chat/learning-queue/import", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowQuery: false, allowBody: true });
    if (!adminCtx) return;

    const defaultSuggestedAction = String(req.body?.default_suggested_action ?? "review")
      .trim()
      .toLowerCase();
    if (!new Set(["allow", "review", "block"]).has(defaultSuggestedAction)) {
      return res.status(400).json({ message: "Invalid default_suggested_action" });
    }

    const defaultSuggestedCategories = sanitizeLearningQueueStringList(
      req.body?.default_suggested_categories
    );
    const defaultAdminNote = String(req.body?.default_admin_note ?? "").trim() || null;
    const importEntries = parseLearningQueueImportEntries({
      format: req.body?.format,
      content: req.body?.content,
      defaultSuggestedAction,
      defaultSuggestedCategories,
      defaultAdminNote,
    });

    if (importEntries.length === 0) {
      return res.status(400).json({ message: "No valid learning entries found in import content" });
    }

    await client.query("BEGIN");
    const insertedItems = [];
    for (const entry of importEntries) {
      const normalizedMessage = normalizeModerationText(entry.rawMessage).normalized;
      const suggestedCategories =
        entry.suggestedCategories.length > 0
          ? entry.suggestedCategories
          : defaultSuggestedCategories;
      const candidateTerms =
        entry.candidateTerms.length > 0
          ? entry.candidateTerms
          : [entry.rawMessage];

      const inserted = await insertModerationLearningQueueItem(client, {
        sourceType: "external_import",
        moderationQueueId: null,
        moderationLogId: null,
        previewLogId: null,
        rawMessage: entry.rawMessage,
        normalizedMessage,
        currentCategories: entry.currentCategories ?? [],
        suggestedAction: entry.suggestedAction || defaultSuggestedAction,
        suggestedCategories,
        candidateTerms,
        adminNote: entry.adminNote ?? defaultAdminNote,
        createdByAdminId: adminCtx.adminId,
      });
      insertedItems.push(inserted);
    }

    await insertAuditLog(client, {
      adminUserId: adminCtx.adminId,
      actorType: "admin",
      action: "SPOT_CHAT_LEARNING_QUEUE_IMPORTED",
      entityTable: "chat_moderation_learning_queue",
      entityId: null,
      metadata: {
        format: String(req.body?.format ?? "json").trim().toLowerCase() || "json",
        imported_count: insertedItems.length,
        default_suggested_action: defaultSuggestedAction,
        default_suggested_categories: defaultSuggestedCategories,
      },
    });

    await client.query("COMMIT");
    return res.status(201).json({
      imported_count: insertedItems.length,
      items: insertedItems,
    });
  } catch (e) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {}
    console.error("Import moderation learning queue items error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.patch("/api/admin/spot-chat/learning-queue/:id/apply", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowQuery: false, allowBody: true });
    if (!adminCtx) return;

    const learningId = Number(req.params.id);
    if (!Number.isInteger(learningId) || learningId <= 0) {
      return res.status(400).json({ message: "Invalid learning queue id" });
    }

    await client.query("BEGIN");
    const existingQ = await client.query(
      `SELECT * FROM public.chat_moderation_learning_queue WHERE id = $1 LIMIT 1`,
      [learningId]
    );
    if (existingQ.rowCount === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ message: "Learning queue item not found" });
    }
    const existing = existingQ.rows[0];
    if (String(existing.status ?? "").toLowerCase() === "applied") {
      await client.query("ROLLBACK");
      return res.status(409).json({ message: "Learning queue item already applied" });
    }

    const candidateTerms = sanitizeLearningQueueStringList(existing.candidate_terms);
    const categories = sanitizeLearningQueueStringList(existing.suggested_categories);
    const primaryCategory = categories[0] || "profanity";
    const appliedTerms = [];

    for (const rawTerm of candidateTerms) {
      const normalizedTerm = normalizeVocabularyTerm(rawTerm);
      if (!normalizedTerm || normalizedTerm.length < 2) continue;
      const language = detectVocabularyLanguage(rawTerm);
      await client.query(
        `
        INSERT INTO public.moderation_vocabulary
          (term, normalized_term, language, category, severity, is_active, source, created_at, updated_at)
        VALUES
          ($1, $2, $3, $4, 'medium', TRUE, 'learning_queue', NOW(), NOW())
        ON CONFLICT (normalized_term, category, language)
        DO UPDATE SET is_active = TRUE, updated_at = NOW()
        `,
        [rawTerm, normalizedTerm, language, primaryCategory]
      );
      appliedTerms.push(normalizedTerm);
    }

    const updatedQ = await client.query(
      `
      UPDATE public.chat_moderation_learning_queue
      SET
        status = 'applied',
        reviewed_by_admin_id = $2,
        reviewed_at = NOW(),
        applied_at = NOW(),
        admin_note = COALESCE($3, admin_note)
      WHERE id = $1
      RETURNING *
      `,
      [learningId, adminCtx.adminId, String(req.body?.admin_note ?? "").trim() || null]
    );

    await insertAuditLog(client, {
      adminUserId: adminCtx.adminId,
      actorType: "admin",
      action: "SPOT_CHAT_LEARNING_QUEUE_APPLIED",
      entityTable: "chat_moderation_learning_queue",
      entityId: learningId,
      metadata: {
        applied_terms: appliedTerms,
        suggested_categories: categories,
        suggested_action: existing.suggested_action,
      },
    });

    await client.query("COMMIT");
    return res.json(updatedQ.rows[0] ?? null);
  } catch (e) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {}
    console.error("Apply moderation learning queue item error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.patch("/api/admin/spot-chat/learning-queue/:id/reject", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowQuery: false, allowBody: true });
    if (!adminCtx) return;

    const learningId = Number(req.params.id);
    if (!Number.isInteger(learningId) || learningId <= 0) {
      return res.status(400).json({ message: "Invalid learning queue id" });
    }

    const updatedQ = await client.query(
      `
      UPDATE public.chat_moderation_learning_queue
      SET
        status = 'rejected',
        reviewed_by_admin_id = $2,
        reviewed_at = NOW(),
        admin_note = COALESCE($3, admin_note)
      WHERE id = $1
      RETURNING *
      `,
      [learningId, adminCtx.adminId, String(req.body?.admin_note ?? "").trim() || null]
    );
    if (updatedQ.rowCount === 0) {
      return res.status(404).json({ message: "Learning queue item not found" });
    }

    await insertAuditLog(client, {
      adminUserId: adminCtx.adminId,
      actorType: "admin",
      action: "SPOT_CHAT_LEARNING_QUEUE_REJECTED",
      entityTable: "chat_moderation_learning_queue",
      entityId: learningId,
      metadata: {
        suggested_categories: updatedQ.rows[0]?.suggested_categories ?? [],
        suggested_action: updatedQ.rows[0]?.suggested_action ?? null,
      },
    });

    return res.json(updatedQ.rows[0] ?? null);
  } catch (e) {
    console.error("Reject moderation learning queue item error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.get("/api/admin/spot-chat/moderation-vocabulary-suggestions", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const status = String(req.query?.status ?? "pending").trim() || "pending";
    const q = await pool.query(
      `
      SELECT id, raw_message, suggested_term, normalized_term, language, category, confidence, status, created_at, reviewed_at, reviewed_by_admin_id
      FROM public.moderation_vocabulary_suggestions
      WHERE ($1 = '' OR status = $1)
      ORDER BY created_at DESC, id DESC
      LIMIT 100
      `,
      [status === "all" ? "" : status]
    );

    return res.json(q.rows);
  } catch (e) {
    console.error("Load moderation vocabulary suggestions error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.patch("/api/admin/spot-chat/moderation-vocabulary-suggestions/:id/approve", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res);
    if (!adminCtx) return;

    const suggestionId = Number(req.params.id);
    if (!Number.isInteger(suggestionId) || suggestionId <= 0) {
      return res.status(400).json({ message: "Invalid suggestion id" });
    }

    await client.query("BEGIN");
    const existingQ = await client.query(
      `
      SELECT *
      FROM public.moderation_vocabulary_suggestions
      WHERE id = $1
      LIMIT 1
      `,
      [suggestionId]
    );
    if (existingQ.rowCount === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ message: "Suggestion not found" });
    }
    const existing = existingQ.rows[0];

    await client.query(
      `
      INSERT INTO public.moderation_vocabulary
        (term, normalized_term, language, category, severity, is_active, source, created_at, updated_at)
      VALUES
        ($1, $2, $3, $4, 'medium', TRUE, 'ai_suggested', NOW(), NOW())
      ON CONFLICT (normalized_term, category, language)
      DO UPDATE SET is_active = TRUE, updated_at = NOW()
      `,
      [
        existing.suggested_term,
        existing.normalized_term,
        existing.language,
        existing.category,
      ]
    );

    const updatedQ = await client.query(
      `
      UPDATE public.moderation_vocabulary_suggestions
      SET status = 'approved', reviewed_at = NOW(), reviewed_by_admin_id = $2
      WHERE id = $1
      RETURNING *
      `,
      [suggestionId, adminCtx.adminId]
    );

    await insertAuditLog(client, {
      adminUserId: adminCtx.adminId,
      actorType: "admin",
      action: "SPOT_CHAT_VOCAB_SUGGESTION_APPROVED",
      entityTable: "moderation_vocabulary_suggestions",
      entityId: suggestionId,
      metadata: {
        normalized_term: existing.normalized_term,
        category: existing.category,
      },
    });

    await client.query("COMMIT");
    return res.json(updatedQ.rows[0] ?? null);
  } catch (e) {
    try {
      await client.query("ROLLBACK");
    } catch (_) {}
    console.error("Approve moderation vocabulary suggestion error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.patch("/api/admin/spot-chat/moderation-vocabulary-suggestions/:id/reject", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res);
    if (!adminCtx) return;

    const suggestionId = Number(req.params.id);
    if (!Number.isInteger(suggestionId) || suggestionId <= 0) {
      return res.status(400).json({ message: "Invalid suggestion id" });
    }

    const updatedQ = await client.query(
      `
      UPDATE public.moderation_vocabulary_suggestions
      SET status = 'rejected', reviewed_at = NOW(), reviewed_by_admin_id = $2
      WHERE id = $1
      RETURNING *
      `,
      [suggestionId, adminCtx.adminId]
    );
    if (updatedQ.rowCount === 0) {
      return res.status(404).json({ message: "Suggestion not found" });
    }

    await insertAuditLog(client, {
      adminUserId: adminCtx.adminId,
      actorType: "admin",
      action: "SPOT_CHAT_VOCAB_SUGGESTION_REJECTED",
      entityTable: "moderation_vocabulary_suggestions",
      entityId: suggestionId,
      metadata: {
        normalized_term: updatedQ.rows[0]?.normalized_term ?? null,
        category: updatedQ.rows[0]?.category ?? null,
      },
    });

    return res.json(updatedQ.rows[0] ?? null);
  } catch (e) {
    console.error("Reject moderation vocabulary suggestion error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.get("/api/admin/event-report/registrations", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const summaryQ = await pool.query(
      `
      WITH bangkok_now AS (
        SELECT NOW() AT TIME ZONE 'Asia/Bangkok' AS ts
      ),
      booking_today AS (
        SELECT COUNT(*)::int AS total
        FROM public.bookings b, bangkok_now bn
        WHERE (b.created_at AT TIME ZONE 'Asia/Bangkok')::date = bn.ts::date
      ),
      spot_join_today AS (
        SELECT COUNT(*)::int AS total
        FROM public.spot_event_members sem, bangkok_now bn
        WHERE (sem.joined_at AT TIME ZONE 'Asia/Bangkok')::date = bn.ts::date
      )
      SELECT
        (SELECT COUNT(*)::int FROM public.users) AS total_users_excluding_admin,
        ((SELECT total FROM booking_today) + (SELECT total FROM spot_join_today))
          AS total_registrations_today_bangkok,
        (
          (SELECT COUNT(*)::int FROM public.events WHERE COALESCE(type::text, 'BIG_EVENT') = 'BIG_EVENT')
          +
          (SELECT COUNT(*)::int FROM public.spot_events)
        ) AS total_events,
        (SELECT COUNT(*)::int FROM public.spot_events) AS total_spot,
        (SELECT COUNT(*)::int FROM public.events WHERE COALESCE(type::text, 'BIG_EVENT') = 'BIG_EVENT')
          AS total_big_event
      `
    );

    const rowsQ = await pool.query(
      `
      SELECT
        e.id,
        COALESCE(NULLIF(TRIM(e.display_code), ''), CONCAT('EV', LPAD(e.id::text, 6, '0'))) AS display_code,
        e.title,
        e.start_at,
        e.created_at,
        'BIG_EVENT' AS type,
        COALESCE(e.status::text, '-') AS status,
        e.organization_id AS creator_id,
        'organization' AS creator_kind,
        COALESCE(o.name, CONCAT('Admin #', COALESCE(e.created_by::text, '-'))) AS creator_name,
        COALESCE(regs.registered_users, 0) AS registered_users
      FROM public.events e
      LEFT JOIN public.organizations o
        ON o.id = e.organization_id
      LEFT JOIN (
        SELECT event_id, COUNT(DISTINCT user_id)::int AS registered_users
        FROM public.bookings
        GROUP BY event_id
      ) regs
        ON regs.event_id = e.id
      WHERE COALESCE(e.type::text, 'BIG_EVENT') = 'BIG_EVENT'

      UNION ALL

      SELECT
        se.id,
        COALESCE(NULLIF(TRIM(se.display_code), ''), CONCAT('SP', LPAD(se.id::text, 6, '0'))) AS display_code,
        se.title,
        CASE
          WHEN COALESCE(se.event_date, '') ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
          THEN to_timestamp(
            se.event_date || ' ' || COALESCE(NULLIF(se.event_time, ''), '00:00'),
            'DD/MM/YYYY HH24:MI'
          )
          ELSE se.created_at
        END AS start_at,
        se.created_at,
        'SPOT' AS type,
        COALESCE(se.status, '-') AS status,
        se.created_by_user_id AS creator_id,
        COALESCE(se.creator_role, 'user') AS creator_kind,
        COALESCE(
          NULLIF(TRIM(COALESCE(u.name, '')), ''),
          NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''),
          NULLIF(TRIM(COALESCE(u.email, '')), ''),
          NULLIF(TRIM(COALESCE(au.email, '')), ''),
          CASE WHEN se.creator_role = 'admin' THEN 'Admin' ELSE 'User' END
        ) AS creator_name,
        COALESCE(spot_regs.registered_users, 0) AS registered_users
      FROM public.spot_events se
      LEFT JOIN public.users u
        ON se.creator_role = 'user'
       AND u.id = se.created_by_user_id
      LEFT JOIN public.admin_users au
        ON se.creator_role = 'admin'
       AND au.id = se.created_by_user_id
      LEFT JOIN (
        SELECT spot_event_id, COUNT(*)::int AS registered_users
        FROM public.spot_event_members
        GROUP BY spot_event_id
      ) spot_regs
        ON spot_regs.spot_event_id = se.id

      ORDER BY start_at DESC NULLS LAST, created_at DESC NULLS LAST, id DESC
      `
    );

    return res.json({
      summary: summaryQ.rows[0] || {
        total_users_excluding_admin: 0,
        total_registrations_today_bangkok: 0,
        total_events: 0,
        total_spot: 0,
        total_big_event: 0,
      },
      rows: rowsQ.rows,
    });
  } catch (e) {
    console.error("Admin registrations report error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/event-report/payments", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    await ensurePaymentSeparationColumns();
    await ensureBusinessReferenceColumns();

    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const summaryQ = await pool.query(
      `
      WITH big_event_payments AS (
        SELECT
          e.id AS event_id,
          e.organization_id,
          b.id AS booking_id,
          p.id AS payment_id
        FROM public.events e
        LEFT JOIN public.bookings b ON b.event_id = e.id
        LEFT JOIN public.payments p ON p.booking_id = b.id
        WHERE COALESCE(e.type::text, 'BIG_EVENT') = 'BIG_EVENT'
      )
      SELECT
        COUNT(DISTINCT organization_id) FILTER (WHERE organization_id IS NOT NULL)::int AS total_company,
        COUNT(DISTINCT booking_id)::int AS total_registrations,
        COUNT(DISTINCT event_id)::int AS total_big_events
      FROM big_event_payments
      `
    );

    const rowsQ = await pool.query(
      `
      SELECT
        o.id AS organization_id,
        o.name AS organization_name,
        COALESCE(NULLIF(TRIM(o.email), ''), '-') AS organization_email,
        COALESCE(NULLIF(TRIM(o.phone), ''), '-') AS organization_phone,
        COALESCE(NULLIF(TRIM(o.address), ''), '-') AS organization_address,
        COUNT(DISTINCT e.id)::int AS number_of_events
      FROM public.organizations o
      LEFT JOIN public.events e
        ON e.organization_id = o.id
       AND COALESCE(e.type::text, 'BIG_EVENT') = 'BIG_EVENT'
      LEFT JOIN (
        SELECT
          b.event_id,
          COUNT(DISTINCT b.id)::int AS registrations_count
        FROM public.bookings b
        LEFT JOIN public.payments p
          ON p.booking_id = b.id
        GROUP BY b.event_id
      ) payments
        ON payments.event_id = e.id
      WHERE o.id IS NOT NULL
      GROUP BY o.id, o.name, o.email, o.phone, o.address
      ORDER BY o.name ASC, o.id ASC
      `
    );

    return res.json({
      summary: summaryQ.rows[0] || {
        total_company: 0,
        total_registrations: 0,
        total_big_events: 0,
      },
      rows: rowsQ.rows,
    });
  } catch (e) {
    console.error("Admin payment report error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/event-report/payments/companies/:organizationId/events", async (req, res) => {
  try {
    await ensurePaymentSeparationColumns();
    await ensureBusinessReferenceColumns();

    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const organizationId = Number(req.params.organizationId);
    if (!Number.isFinite(organizationId) || organizationId <= 0) {
      return res.status(400).json({ message: "Invalid organizationId" });
    }

    const q = await pool.query(
      `
      SELECT
        e.id,
        COALESCE(NULLIF(TRIM(e.display_code), ''), CONCAT('EV', LPAD(e.id::text, 6, '0'))) AS display_code,
        e.title,
        e.start_at,
        e.created_at,
        COALESCE(e.max_participants, 0)::int AS max_participants,
        COALESCE(e.fee, 0)::numeric AS fee,
        EXISTS (
          SELECT 1
          FROM public.event_media em
          WHERE em.event_id = e.id
            AND COALESCE(em.kind::text, '') = 'guaranteed'
            AND LOWER(COALESCE(em.item_type::text, '')) = 'shirt'
        ) AS has_shirt_size,
        COALESCE(
          COUNT(DISTINCT b.id),
          0
        )::int AS payment_count
      FROM public.events e
      LEFT JOIN public.bookings b
        ON b.event_id = e.id
      WHERE e.organization_id = $1
        AND COALESCE(e.type::text, 'BIG_EVENT') = 'BIG_EVENT'
      GROUP BY e.id, e.title, e.start_at, e.created_at, e.max_participants, e.fee
      ORDER BY e.start_at DESC NULLS LAST, e.created_at DESC NULLS LAST, e.id DESC
      `,
      [organizationId]
    );

    return res.json({
      rows: q.rows,
    });
  } catch (e) {
    console.error("Admin company payment events error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/event-report/payments/events/:eventId/users", async (req, res) => {
  try {
    await ensurePaymentSeparationColumns();
    await ensureUserAuthColumns();
    await ensureBusinessReferenceColumns();
    await ensureBigEventShirtSizeColumns();

    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const eventId = Number(req.params.eventId);
    if (!Number.isFinite(eventId) || eventId <= 0) {
      return res.status(400).json({ message: "Invalid eventId" });
    }

    const q = await pool.query(
      `
      SELECT
        b.id AS booking_id,
        COALESCE(NULLIF(TRIM(b.booking_reference), ''), CONCAT('BK-', TO_CHAR(COALESCE(b.created_at, NOW()) AT TIME ZONE 'UTC', 'YYYYMMDD'), '-', LPAD(b.id::text, 6, '0'))) AS booking_reference,
        b.user_id,
        CONCAT('US', LPAD(b.user_id::text, 4, '0')) AS user_display_code,
        COALESCE(
          NULLIF(TRIM(COALESCE(u.name, '')), ''),
          NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''),
          NULLIF(TRIM(COALESCE(u.email, '')), ''),
          CONCAT('User #', b.user_id::text)
        ) AS user_name,
        COALESCE(p.paid_at, b.created_at) AS action_at,
        COALESCE(
          NULLIF(TRIM(COALESCE(b.status::text, '')), ''),
          'pending'
        ) AS booking_status,
        NULLIF(TRIM(COALESCE(b.shirt_size, '')), '') AS shirt_size,
        COALESCE(p.amount, b.total_amount, 0)::numeric AS price,
        CASE
          WHEN p.id IS NULL THEN NULL
          ELSE COALESCE(
            NULLIF(TRIM(p.payment_reference), ''),
            CONCAT('PAY-', TO_CHAR(COALESCE(p.created_at, NOW()) AT TIME ZONE 'UTC', 'YYYYMMDD'), '-', LPAD(p.id::text, 6, '0'))
          )
        END AS payment_id,
        b.id AS booking_id,
        p.method AS payment_method,
        p.provider,
        COALESCE(p.provider_txn_id, p.provider_charge_id, p.provider_payment_intent_id, p.stripe_payment_intent_id) AS provider_txn_id,
        p.status AS payment_status,
        p.paid_at,
        r.receipt_url,
        r.receipt_no,
        r.issue_date AS receipt_issue_date
      FROM public.bookings b
      LEFT JOIN public.users u
        ON u.id = b.user_id
      LEFT JOIN LATERAL (
        SELECT p1.*
        FROM public.payments p1
        WHERE p1.booking_id = b.id
        ORDER BY p1.paid_at DESC NULLS LAST, p1.id DESC
        LIMIT 1
      ) p ON TRUE
      LEFT JOIN LATERAL (
        SELECT r1.receipt_no, r1.issue_date, r1.pdf_url AS receipt_url
        FROM public.receipts r1
        WHERE r1.payment_id = p.id
        ORDER BY r1.issue_date DESC NULLS LAST, r1.id DESC
        LIMIT 1
      ) r ON TRUE
      WHERE b.event_id = $1
      ORDER BY COALESCE(p.paid_at, b.created_at) DESC NULLS LAST, b.id DESC
      `,
      [eventId]
    );

    const host = `${req.protocol}://${req.get("host")}`;
    return res.json({
      rows: q.rows.map((row) => ({
        user_id: row.user_id,
        user_display_code: row.user_display_code,
        user_name: row.user_name,
        action_at: row.action_at,
        status: row.booking_status,
        booking_status: row.booking_status,
        shirt_size: row.shirt_size,
        price: Number(row.price ?? 0),
        payment_id: row.payment_id,
        booking_id: row.booking_reference,
        booking_reference: row.booking_reference,
        payment_method: row.payment_method,
        provider: row.provider,
        provider_txn_id: row.provider_txn_id,
        payment_status: row.payment_status,
        paid_at: row.paid_at,
        receipt_no: row.receipt_no,
        receipt_issue_date: row.receipt_issue_date,
        receipt_url: row.receipt_url
          ? (String(row.receipt_url).startsWith("http")
              ? row.receipt_url
              : `${host}${String(row.receipt_url).startsWith("/") ? "" : "/"}${row.receipt_url}`)
          : null,
      })),
    });
  } catch (e) {
    console.error("Admin event payment users error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/event-report/engagement", async (req, res) => {
  try {
    await ensureUserAuthColumns();

    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const groupBy = String(req.query?.group_by ?? "gender").trim().toLowerCase();
    const allowedGroups = new Set(["gender", "age", "occupation", "province"]);
    if (!allowedGroups.has(groupBy)) {
      return res.status(400).json({ message: "Invalid group_by" });
    }

    const nowBangkok = new Date(new Date().toLocaleString("en-US", { timeZone: "Asia/Bangkok" }));
    const month = Number(req.query?.month ?? (nowBangkok.getMonth() + 1));
    const year = Number(req.query?.year ?? nowBangkok.getFullYear());

    if (!Number.isInteger(month) || month < 1 || month > 12) {
      return res.status(400).json({ message: "Invalid month" });
    }
    if (!Number.isInteger(year) || year < 2000 || year > 2100) {
      return res.status(400).json({ message: "Invalid year" });
    }

    let metricSql = "COALESCE(NULLIF(TRIM(COALESCE(u.gender, '')), ''), 'Unknown')";
    if (groupBy === "occupation") {
      metricSql = "COALESCE(NULLIF(TRIM(COALESCE(u.occupation, '')), ''), 'Unknown')";
    } else if (groupBy === "province") {
      metricSql = "COALESCE(NULLIF(TRIM(COALESCE(u.address_province, '')), ''), 'Unknown')";
    } else if (groupBy === "age") {
      metricSql = `
        CASE
          WHEN COALESCE(u.birth_year, 0) <= 0 THEN 'Unknown'
          ELSE CASE
            WHEN EXTRACT(YEAR FROM (NOW() AT TIME ZONE 'Asia/Bangkok'))::int - u.birth_year <= 17 THEN '0-17'
            WHEN EXTRACT(YEAR FROM (NOW() AT TIME ZONE 'Asia/Bangkok'))::int - u.birth_year BETWEEN 18 AND 24 THEN '18-24'
            WHEN EXTRACT(YEAR FROM (NOW() AT TIME ZONE 'Asia/Bangkok'))::int - u.birth_year BETWEEN 25 AND 34 THEN '25-34'
            WHEN EXTRACT(YEAR FROM (NOW() AT TIME ZONE 'Asia/Bangkok'))::int - u.birth_year BETWEEN 35 AND 44 THEN '35-44'
            WHEN EXTRACT(YEAR FROM (NOW() AT TIME ZONE 'Asia/Bangkok'))::int - u.birth_year BETWEEN 45 AND 54 THEN '45-54'
            WHEN EXTRACT(YEAR FROM (NOW() AT TIME ZONE 'Asia/Bangkok'))::int - u.birth_year BETWEEN 55 AND 64 THEN '55-64'
            ELSE '65+'
          END
        END
      `;
    }

    const yearsQ = await pool.query(
      `
      SELECT DISTINCT EXTRACT(YEAR FROM (u.created_at AT TIME ZONE 'Asia/Bangkok'))::int AS year
      FROM public.users u
      WHERE u.created_at IS NOT NULL
      ORDER BY year DESC
      `
    );

    const rowsQ = await pool.query(
      `
      WITH filtered AS (
        SELECT
          ${metricSql} AS label
        FROM public.users u
        WHERE u.created_at IS NOT NULL
          AND EXTRACT(MONTH FROM (u.created_at AT TIME ZONE 'Asia/Bangkok'))::int = $1
          AND EXTRACT(YEAR FROM (u.created_at AT TIME ZONE 'Asia/Bangkok'))::int = $2
      )
      SELECT
        label,
        COUNT(*)::int AS total_users
      FROM filtered
      GROUP BY label
      ORDER BY total_users DESC, label ASC
      LIMIT 10
      `,
      [month, year]
    );

    const totalQ = await pool.query(
      `
      SELECT COUNT(*)::int AS total_users
      FROM public.users u
      WHERE u.created_at IS NOT NULL
        AND EXTRACT(MONTH FROM (u.created_at AT TIME ZONE 'Asia/Bangkok'))::int = $1
        AND EXTRACT(YEAR FROM (u.created_at AT TIME ZONE 'Asia/Bangkok'))::int = $2
      `,
      [month, year]
    );

    return res.json({
      group_by: groupBy,
      month,
      year,
      total_users: Number(totalQ.rows[0]?.total_users ?? 0),
      available_years: yearsQ.rows.map((row) => Number(row.year)).filter((value) => Number.isFinite(value)),
      rows: rowsQ.rows.map((row) => ({
        label: String(row.label ?? "Unknown"),
        total_users: Number(row.total_users ?? 0),
      })),
    });
  } catch (e) {
    console.error("Admin engagement report error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/reports/all-events/available-periods", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const q = await pool.query(
      `
      WITH periods AS (
        SELECT
          EXTRACT(YEAR FROM e.start_at)::int AS year,
          EXTRACT(MONTH FROM e.start_at)::int AS month
        FROM public.events e
        WHERE e.start_at IS NOT NULL
          AND COALESCE(e.type::text, 'BIG_EVENT') = 'BIG_EVENT'

        UNION ALL

        SELECT
          EXTRACT(YEAR FROM to_date(se.event_date, 'DD/MM/YYYY'))::int AS year,
          EXTRACT(MONTH FROM to_date(se.event_date, 'DD/MM/YYYY'))::int AS month
        FROM public.spot_events se
        WHERE COALESCE(se.event_date, '') ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
      )
      SELECT year, month
      FROM periods
      WHERE year IS NOT NULL
        AND month BETWEEN 1 AND 12
      ORDER BY year ASC, month ASC
      `
    );

    const monthsByYear = {};
    for (const row of q.rows) {
      const year = Number(row.year);
      const month = Number(row.month);
      if (!Number.isInteger(year) || !Number.isInteger(month)) continue;
      if (!monthsByYear[year]) monthsByYear[year] = [];
      if (!monthsByYear[year].includes(month)) monthsByYear[year].push(month);
    }

    const years = Object.keys(monthsByYear)
      .map((value) => Number(value))
      .filter((value) => Number.isInteger(value))
      .sort((a, b) => a - b);

    const nowBangkok = new Date(new Date().toLocaleString("en-US", { timeZone: "Asia/Bangkok" }));
    const fallbackYear = nowBangkok.getFullYear();
    const fallbackMonth = nowBangkok.getMonth() + 1;

    if (years.length === 0) {
      monthsByYear[fallbackYear] = [fallbackMonth];
    } else {
      for (const year of years) {
        monthsByYear[year].sort((a, b) => a - b);
      }
    }

    const finalYears = Object.keys(monthsByYear)
      .map((value) => Number(value))
      .filter((value) => Number.isInteger(value))
      .sort((a, b) => a - b);

    return res.json({
      minYear: finalYears[0] ?? fallbackYear,
      maxYear: finalYears[finalYears.length - 1] ?? fallbackYear,
      monthsByYear,
    });
  } catch (e) {
    console.error("Admin all-events available periods error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/reports/all-events/pie", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const year = Number(req.query?.year);
    const month = Number(req.query?.month);
    if (!Number.isInteger(year) || year < 2000 || year > 3000) {
      return res.status(400).json({ message: "Invalid year" });
    }
    if (!Number.isInteger(month) || month < 1 || month > 12) {
      return res.status(400).json({ message: "Invalid month" });
    }

    const q = await pool.query(
      `
      SELECT
        (
          SELECT COUNT(*)::int
          FROM public.events e
          WHERE COALESCE(e.type::text, 'BIG_EVENT') = 'BIG_EVENT'
            AND EXTRACT(YEAR FROM e.start_at)::int = $1
            AND EXTRACT(MONTH FROM e.start_at)::int = $2
        ) AS "bigEventCount",
        (
          SELECT COUNT(*)::int
          FROM public.spot_events se
          WHERE COALESCE(se.event_date, '') ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
            AND EXTRACT(YEAR FROM to_date(se.event_date, 'DD/MM/YYYY'))::int = $1
            AND EXTRACT(MONTH FROM to_date(se.event_date, 'DD/MM/YYYY'))::int = $2
        ) AS "spotCount"
      `,
      [year, month]
    );

    return res.json({
      year,
      month,
      bigEventCount: Number(q.rows[0]?.bigEventCount ?? 0),
      spotCount: Number(q.rows[0]?.spotCount ?? 0),
    });
  } catch (e) {
    console.error("Admin all-events pie report error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/spot-leave-feedback", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const q = await pool.query(
      `
      SELECT
        slf.id,
        slf.event_id,
        COALESCE(se.title, CONCAT('Spot #', slf.event_id::text)) AS event_title,
        slf.leaver_user_id,
        COALESCE(
          NULLIF(TRIM(COALESCE(lu.name, '')), ''),
          NULLIF(TRIM(CONCAT_WS(' ', lu.first_name, lu.last_name)), ''),
          NULLIF(TRIM(COALESCE(lu.email, '')), ''),
          CONCAT('User #', slf.leaver_user_id::text)
        ) AS leaver_user_name,
        slf.reason_code,
        slf.reason_text,
        NULLIF(TRIM(COALESCE(slf.report_detail_text, '')), '') AS report_detail_text,
        slf.category,
        slf.reported_target_type,
        slf.reported_target_user_id,
        COALESCE(
          NULLIF(TRIM(COALESCE(tu.name, '')), ''),
          NULLIF(TRIM(CONCAT_WS(' ', tu.first_name, tu.last_name)), ''),
          NULLIF(TRIM(COALESCE(tu.email, '')), ''),
          NULL
        ) AS reported_target_user_name,
        slf.created_at
      FROM public.spot_leave_feedback slf
      LEFT JOIN public.spot_events se
        ON se.id = slf.event_id
      LEFT JOIN public.users lu
        ON lu.id = slf.leaver_user_id
      LEFT JOIN public.users tu
        ON tu.id = slf.reported_target_user_id
      WHERE COALESCE(slf.category, '') = 'BEHAVIOR_SAFETY'
      ORDER BY slf.created_at DESC, slf.id DESC
      `
    );

    return res.json(q.rows);
  } catch (e) {
    console.error("Admin spot leave feedback report error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.post("/api/admin/location-backfill", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    await ensureEventDistanceColumns();

    const adminCtx = await requireActiveAdmin(req, res, {
      allowQuery: false,
      allowBody: true,
    });
    if (!adminCtx) return;

    const entity = String(req.body?.entity ?? "all").trim().toLowerCase();
    if (!["spots", "events", "all"].includes(entity)) {
      return res.status(400).json({
        message: 'Invalid entity. Use "spots", "events", or "all".',
      });
    }

    const requestedLimit = Number(req.body?.limit ?? 25);
    const limit = Number.isFinite(requestedLimit)
      ? Math.max(1, Math.min(200, Math.trunc(requestedLimit)))
      : 25;

    console.info("Admin location backfill started", {
      adminId: adminCtx.admin.id,
      entity,
      limit,
    });

    const result = {
      entity,
      limit,
      processed: 0,
      updated: 0,
      skipped: 0,
      spots: { scanned: 0, processed: 0, updated: 0, skipped: 0 },
      events: { scanned: 0, processed: 0, updated: 0, skipped: 0 },
    };

    if (entity === "all" || entity === "spots") {
      const spotRows = await pool.query(
        `
        SELECT id, location, province, district, location_lat, location_lng
        FROM public.spot_events
        WHERE location_lat IS NOT NULL
          AND location_lng IS NOT NULL
          AND (
            COALESCE(TRIM(province), '') = ''
            OR COALESCE(TRIM(district), '') = ''
            OR COALESCE(TRIM(location), '') = ''
            OR TRIM(COALESCE(location, '')) = '-'
            OR COALESCE(province, '') ~* '(lat|lng|latitude|longitude)'
            OR COALESCE(district, '') ~* '(lat|lng|latitude|longitude)'
            OR COALESCE(location, '') ~* '(lat|lng|latitude|longitude)'
            OR COALESCE(province, '') ~ '[ก-๙]'
            OR COALESCE(district, '') ~ '[ก-๙]'
            OR COALESCE(TRIM(province), '') ~ '^-?[0-9]+(\.[0-9]+)?\s*,\s*-?[0-9]+(\.[0-9]+)?$'
            OR COALESCE(TRIM(district), '') ~ '^-?[0-9]+(\.[0-9]+)?\s*,\s*-?[0-9]+(\.[0-9]+)?$'
            OR COALESCE(TRIM(location), '') ~ '^-?[0-9]+(\.[0-9]+)?\s*,\s*-?[0-9]+(\.[0-9]+)?$'
          )
        ORDER BY id ASC
        LIMIT $1
        `,
        [limit]
      );

      result.spots.scanned = spotRows.rowCount;
      console.info("Admin location backfill spot candidates", {
        scanned: result.spots.scanned,
        limit,
      });
      for (const row of spotRows.rows) {
        result.spots.processed += 1;
        const reverse = await reverseGeocodeCoordinates(
          Number(row.location_lat),
          Number(row.location_lng)
        ).catch((geoErr) => {
          console.warn("Spot backfill geocoding skipped:", geoErr?.message || geoErr);
          return null;
        });
        if (!reverse) {
          result.spots.skipped += 1;
          continue;
        }

        const invalidProvince =
          isBlankText(row.province) ||
          looksLikeCoordinateText(row.province) ||
          containsThaiCharacters(row.province);
        const invalidDistrict =
          isBlankText(row.district) ||
          looksLikeCoordinateText(row.district) ||
          containsThaiCharacters(row.district);
        const invalidLocation =
          isBlankText(row.location) ||
          String(row.location ?? "").trim() === "-" ||
          looksLikeCoordinateText(row.location);

        const nextProvince = invalidProvince
          ? (reverse.province || normalizeSpotProvince(row.province, row.location))
          : String(row.province ?? "").trim();
        const nextDistrict = invalidDistrict
          ? (reverse.district || normalizeSpotDistrict(row.district, row.location, nextProvince))
          : String(row.district ?? "").trim();
        const nextLocation = invalidLocation
          ? normalizeHumanReadableLocation(reverse.formattedAddress)
          : normalizeHumanReadableLocation(row.location);

        if (nextProvince === String(row.province ?? "").trim() &&
            nextDistrict === String(row.district ?? "").trim() &&
            nextLocation === normalizeHumanReadableLocation(row.location)) {
          result.spots.skipped += 1;
          continue;
        }

        await pool.query(
          `
          UPDATE public.spot_events
          SET
            location = CASE
              WHEN COALESCE(TRIM(location), '') = ''
                OR TRIM(COALESCE(location, '')) = '-'
                OR location ~* '(lat|lng|latitude|longitude)'
                OR COALESCE(TRIM(location), '') ~ '^-?[0-9]+(\.[0-9]+)?\s*,\s*-?[0-9]+(\.[0-9]+)?$'
              THEN $1
              ELSE location
            END,
            province = CASE
              WHEN COALESCE(TRIM(province), '') = ''
                OR province ~* '(lat|lng|latitude|longitude)'
                OR province ~ '[ก-๙]'
                OR COALESCE(TRIM(province), '') ~ '^-?[0-9]+(\.[0-9]+)?\s*,\s*-?[0-9]+(\.[0-9]+)?$'
              THEN $2
              ELSE province
            END,
            district = CASE
              WHEN COALESCE(TRIM(district), '') = ''
                OR district ~* '(lat|lng|latitude|longitude)'
                OR district ~ '[ก-๙]'
                OR COALESCE(TRIM(district), '') ~ '^-?[0-9]+(\.[0-9]+)?\s*,\s*-?[0-9]+(\.[0-9]+)?$'
              THEN $3
              ELSE district
            END,
            updated_at = NOW()
          WHERE id = $4
          `,
          [nextLocation || null, nextProvince || null, nextDistrict || null, row.id]
        );
        result.spots.updated += 1;
      }
    }

    if (entity === "all" || entity === "events") {
      const eventRows = await pool.query(
        `
        SELECT id, meeting_point, location_name, city, province, district, location_lat, location_lng
        FROM public.events
        WHERE location_lat IS NOT NULL
          AND location_lng IS NOT NULL
          AND (
            COALESCE(TRIM(province), '') = ''
            OR COALESCE(TRIM(district), '') = ''
            OR COALESCE(TRIM(location_name), '') = ''
          )
        ORDER BY id ASC
        LIMIT $1
        `,
        [limit]
      );

      result.events.scanned = eventRows.rowCount;
      for (const row of eventRows.rows) {
        result.events.processed += 1;
        const reverse = await reverseGeocodeCoordinates(
          Number(row.location_lat),
          Number(row.location_lng)
        ).catch((geoErr) => {
          console.warn("Event backfill geocoding skipped:", geoErr?.message || geoErr);
          return null;
        });
        if (!reverse) {
          result.events.skipped += 1;
          continue;
        }

        const nextProvince = isBlankText(row.province)
          ? reverse.province
          : String(row.province ?? "").trim();
        const nextLocationName = isBlankText(row.location_name)
          ? (reverse.formattedAddress || String(row.meeting_point ?? "").trim())
          : String(row.location_name ?? "").trim();
        const nextCity = isBlankText(row.city)
          ? reverse.district
          : String(row.city ?? "").trim();
        const nextDistrict = isBlankText(row.district)
          ? reverse.district
          : String(row.district ?? "").trim();

        if (nextProvince === String(row.province ?? "").trim() &&
            nextDistrict === String(row.district ?? "").trim() &&
            nextLocationName === String(row.location_name ?? "").trim() &&
            nextCity === String(row.city ?? "").trim()) {
          result.events.skipped += 1;
          continue;
        }

        await pool.query(
          `
          UPDATE public.events
          SET
            province = CASE
              WHEN COALESCE(TRIM(province), '') = '' THEN $1
              ELSE province
            END,
            district = CASE
              WHEN COALESCE(TRIM(district), '') = '' THEN $2
              ELSE district
            END,
            location_name = CASE
              WHEN COALESCE(TRIM(location_name), '') = '' THEN $3
              ELSE location_name
            END,
            city = CASE
              WHEN COALESCE(TRIM(city), '') = '' THEN $4
              ELSE city
            END,
            updated_at = NOW()
          WHERE id = $5
          `,
          [
            nextProvince || null,
            nextDistrict || null,
            nextLocationName || null,
            nextCity || null,
            row.id,
          ]
        );
        result.events.updated += 1;
      }
    }

    result.processed = result.spots.processed + result.events.processed;
    result.updated = result.spots.updated + result.events.updated;
    result.skipped = result.spots.skipped + result.events.skipped;

    console.info("Admin location backfill finished", result);
    return res.json(result);
  } catch (e) {
    console.error("Admin location backfill error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/audit-logs/admin", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const q = String(req.query?.q ?? "").trim().toLowerCase();
    const hasAdminUsersTableQ = await pool.query(
      `SELECT to_regclass('public.admin_users') AS regclass`
    );
    if (!hasAdminUsersTableQ.rows[0]?.regclass) {
      return res.json([]);
    }

    const logsQ = await pool.query(
      `
      SELECT *
      FROM (
        SELECT
          (au.id * 10 + 1)::bigint AS id,
          au.id AS actor_id,
          COALESCE(NULLIF(TRIM(au.email), ''), CONCAT('Admin #', au.id::text)) AS actor_name,
          COALESCE(NULLIF(TRIM(au.email), ''), '-') AS actor_email,
          CONCAT('AM', LPAD(au.id::text, 4, '0')) AS actor_code,
          'ACCOUNT_CREATED' AS action,
          au.created_at,
          'admin_user'::text AS entity_type,
          au.id AS entity_id,
          '{}'::jsonb AS metadata_json,
          NULL::text AS entity_name,
          NULL::text AS ip_address
        FROM public.admin_users au
        WHERE au.created_at IS NOT NULL

        UNION ALL

        SELECT
          (900000000000 + al.id)::bigint AS id,
          COALESCE(
            al.admin_user_id,
            CASE
              WHEN COALESCE(al.metadata_json->>'admin_user_id', '') ~ '^[0-9]+$'
                THEN (al.metadata_json->>'admin_user_id')::bigint
              WHEN COALESCE(al.metadata_json->>'admin_id', '') ~ '^[0-9]+$'
                THEN (al.metadata_json->>'admin_id')::bigint
              WHEN COALESCE(al.metadata_json->>'adminId', '') ~ '^[0-9]+$'
                THEN (al.metadata_json->>'adminId')::bigint
              ELSE NULL
            END
          ) AS actor_id,
          COALESCE(
            NULLIF(TRIM(au.email), ''),
            NULLIF(TRIM(al.metadata_json->>'admin_name'), ''),
            NULLIF(TRIM(al.metadata_json->>'admin_email'), ''),
            CONCAT(
              'Admin #',
              COALESCE(
                al.admin_user_id::text,
                al.metadata_json->>'admin_user_id',
                al.metadata_json->>'admin_id',
                al.metadata_json->>'adminId',
                '?'
              )
            )
          ) AS actor_name,
          COALESCE(
            NULLIF(TRIM(au.email), ''),
            NULLIF(TRIM(al.metadata_json->>'admin_email'), ''),
            NULLIF(TRIM(al.metadata_json->>'email'), ''),
            '-'
          ) AS actor_email,
          CASE
            WHEN COALESCE(
              al.admin_user_id,
              CASE
                WHEN COALESCE(al.metadata_json->>'admin_user_id', '') ~ '^[0-9]+$'
                  THEN (al.metadata_json->>'admin_user_id')::bigint
                WHEN COALESCE(al.metadata_json->>'admin_id', '') ~ '^[0-9]+$'
                  THEN (al.metadata_json->>'admin_id')::bigint
                WHEN COALESCE(al.metadata_json->>'adminId', '') ~ '^[0-9]+$'
                  THEN (al.metadata_json->>'adminId')::bigint
                ELSE NULL
              END
            ) IS NOT NULL
              THEN CONCAT(
                'AM',
                LPAD(
                  COALESCE(
                    al.admin_user_id::text,
                    al.metadata_json->>'admin_user_id',
                    al.metadata_json->>'admin_id',
                    al.metadata_json->>'adminId'
                  ),
                  4,
                  '0'
                )
              )
            ELSE 'SYSTEM'
          END AS actor_code,
          al.action AS action,
          al.created_at,
          COALESCE(al.entity_table, 'audit_log')::text AS entity_type,
          al.entity_id AS entity_id,
          al.metadata_json AS metadata_json,
          COALESCE(
            NULLIF(TRIM(ev.title), ''),
            NULLIF(TRIM(org.name), ''),
            NULLIF(TRIM(al.metadata_json->>'title'), ''),
            NULLIF(TRIM(al.metadata_json->>'event_title'), ''),
            NULLIF(TRIM(al.metadata_json->>'organization_name'), '')
          )::text AS entity_name,
          NULL::text AS ip_address
        FROM public.audit_logs al
        LEFT JOIN public.admin_users au ON au.id = COALESCE(
          al.admin_user_id,
          CASE
            WHEN COALESCE(al.metadata_json->>'admin_user_id', '') ~ '^[0-9]+$'
              THEN (al.metadata_json->>'admin_user_id')::bigint
            WHEN COALESCE(al.metadata_json->>'admin_id', '') ~ '^[0-9]+$'
              THEN (al.metadata_json->>'admin_id')::bigint
            WHEN COALESCE(al.metadata_json->>'adminId', '') ~ '^[0-9]+$'
              THEN (al.metadata_json->>'adminId')::bigint
            ELSE NULL
          END
        )
        LEFT JOIN public.events ev
          ON COALESCE(al.entity_table, '') = 'events'
         AND ev.id = al.entity_id
        LEFT JOIN public.organizations org
          ON COALESCE(al.entity_table, '') = 'organizations'
         AND org.id = al.entity_id
        WHERE al.admin_user_id IS NOT NULL
           OR COALESCE(al.actor_type, '') = 'admin'
           OR COALESCE(al.metadata_json->>'admin_user_id', '') <> ''
           OR COALESCE(al.metadata_json->>'admin_id', '') <> ''
           OR COALESCE(al.metadata_json->>'adminId', '') <> ''

        UNION ALL

        SELECT
          (au.id * 10 + 2)::bigint AS id,
          au.id AS actor_id,
          COALESCE(NULLIF(TRIM(au.email), ''), CONCAT('Admin #', au.id::text)) AS actor_name,
          COALESCE(NULLIF(TRIM(au.email), ''), '-') AS actor_email,
          CONCAT('AM', LPAD(au.id::text, 4, '0')) AS actor_code,
          'LOGIN' AS action,
          au.last_login_at AS created_at,
          'admin_user'::text AS entity_type,
          au.id AS entity_id,
          '{}'::jsonb AS metadata_json,
          NULL::text AS entity_name,
          NULL::text AS ip_address
        FROM public.admin_users au
        WHERE au.last_login_at IS NOT NULL
      ) logs
      ORDER BY created_at DESC, id DESC
      LIMIT 300
      `
    );

    const rows = logsQ.rows.filter((row) => {
      if (!q) return true;
      const haystack = [
        row.actor_name,
        row.actor_code,
        row.action,
        row.entity_type,
        row.entity_id,
      ]
        .join(" ")
        .toLowerCase();
      return haystack.includes(q);
    });

    return res.json(rows);
  } catch (e) {
    console.error("Admin audit logs error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/audit-logs/users", async (req, res) => {
  try {
    await ensureUserAuthColumns();
    await ensureSpotSubsystemTables();

    const q = String(req.query?.q ?? "").trim().toLowerCase();
    const logsQ = await pool.query(
      `
      SELECT *
      FROM (
        SELECT
          (u.id * 10 + 1)::bigint AS id,
          u.id AS actor_id,
          COALESCE(
            NULLIF(TRIM(COALESCE(u.name, '')), ''),
            NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''),
            NULLIF(TRIM(COALESCE(u.email, '')), ''),
            CONCAT('User #', u.id::text)
          ) AS actor_name,
          CONCAT('US', LPAD(u.id::text, 4, '0')) AS actor_code,
          'REGISTER' AS action,
          u.created_at,
          'user'::text AS entity_type,
          u.id AS entity_id,
          NULL::text AS ip_address
        FROM public.users u
        WHERE u.created_at IS NOT NULL

        UNION ALL

        SELECT
          (800000000000 + al.id)::bigint AS id,
          al.user_id AS actor_id,
          COALESCE(
            NULLIF(TRIM(COALESCE(u.name, '')), ''),
            NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''),
            NULLIF(TRIM(COALESCE(u.email, '')), ''),
            CONCAT('User #', al.user_id::text)
          ) AS actor_name,
          CONCAT('US', LPAD(al.user_id::text, 4, '0')) AS actor_code,
          al.action AS action,
          al.created_at,
          COALESCE(al.entity_table, 'audit_log')::text AS entity_type,
          al.entity_id AS entity_id,
          NULL::text AS ip_address
        FROM public.audit_logs al
        JOIN public.users u ON u.id = al.user_id
        WHERE al.user_id IS NOT NULL

        UNION ALL

        SELECT
          (u.id * 10 + 2)::bigint AS id,
          u.id AS actor_id,
          COALESCE(
            NULLIF(TRIM(COALESCE(u.name, '')), ''),
            NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''),
            NULLIF(TRIM(COALESCE(u.email, '')), ''),
            CONCAT('User #', u.id::text)
          ) AS actor_name,
          CONCAT('US', LPAD(u.id::text, 4, '0')) AS actor_code,
          'LOGIN' AS action,
          u.last_login_at AS created_at,
          'user'::text AS entity_type,
          u.id AS entity_id,
          NULL::text AS ip_address
        FROM public.users u
        WHERE u.last_login_at IS NOT NULL
      ) logs
      ORDER BY created_at DESC, id DESC
      LIMIT 500
      `
    );

    const rows = logsQ.rows.filter((row) => {
      if (!q) return true;
      const haystack = [
        row.actor_name,
        row.actor_code,
        row.action,
        row.entity_type,
        row.entity_id,
      ]
        .join(" ")
        .toLowerCase();
      return haystack.includes(q);
    });

    return res.json(rows);
  } catch (e) {
    console.error("User audit logs error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/spot-chat/moderation-report-summary", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const summaryQ = await pool.query(
      `
      WITH moderation AS (
        SELECT *
        FROM public.chat_moderation_logs
      ),
      queue AS (
        SELECT *
        FROM public.chat_moderation_queue
      ),
      alerts AS (
        SELECT *
        FROM public.spot_chat_room_alerts
        WHERE is_active = TRUE
      )
      SELECT
        COALESCE((SELECT COUNT(*)::int FROM moderation), 0) AS total_moderated_messages,
        COALESCE((SELECT COUNT(*)::int FROM moderation WHERE action_taken = 'censor_and_warn'), 0) AS total_flagged_messages,
        COALESCE((SELECT COUNT(*)::int FROM moderation WHERE action_taken IN ('block_and_flag', 'block_and_report', 'block_remove_and_report', 'block_and_alert_room')), 0) AS total_blocked_messages,
        COALESCE((SELECT COUNT(*)::int FROM moderation WHERE detected_categories ? 'profanity'), 0) AS total_profanity_cases,
        COALESCE((SELECT COUNT(*)::int FROM moderation WHERE detected_categories ? 'hate_speech'), 0) AS total_hate_speech_cases,
        COALESCE((SELECT COUNT(*)::int FROM moderation WHERE detected_categories ? 'sexual_harassment'), 0) AS total_sexual_harassment_cases,
        COALESCE((SELECT COUNT(*)::int FROM moderation WHERE detected_categories ? 'scam_risk'), 0) AS total_scam_risk_cases,
        COALESCE((SELECT COUNT(*)::int FROM alerts WHERE alert_type = 'scam_warning'), 0) AS total_room_alerts_created,
        COALESCE((SELECT COUNT(*)::int FROM queue WHERE queue_status = 'dismissed'), 0) AS total_admin_dismissed,
        COALESCE((SELECT COUNT(*)::int FROM queue WHERE queue_status = 'confirmed'), 0) AS total_admin_confirmed,
        COALESCE((SELECT COUNT(*)::int FROM queue WHERE queue_status = 'suspended'), 0) AS total_users_suspended_for_moderation,
        COALESCE((SELECT COUNT(*)::int FROM moderation WHERE ai_used = TRUE), 0) AS total_ai_used_cases,
        COALESCE((SELECT COUNT(*)::int FROM moderation WHERE ai_result_json->'openai_reasoned'->>'attempted' = 'true'), 0) AS total_openai_reasoned_attempts,
        COALESCE((SELECT COUNT(*)::int FROM moderation WHERE ai_result_json->'openai_reasoned'->>'used' = 'true'), 0) AS total_openai_reasoned_used,
        COALESCE((SELECT SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'input_tokens')::bigint, 0))::bigint FROM moderation), 0) AS total_openai_reasoned_input_tokens,
        COALESCE((SELECT SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'output_tokens')::bigint, 0))::bigint FROM moderation), 0) AS total_openai_reasoned_output_tokens,
        COALESCE((SELECT SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'total_tokens')::bigint, 0))::bigint FROM moderation), 0) AS total_openai_reasoned_total_tokens,
        COALESCE((SELECT ROUND(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'estimated_cost_usd')::numeric, 0)), 8) FROM moderation), 0) AS total_openai_reasoned_estimated_cost_usd
      `
    );

    return res.json(summaryQ.rows[0] || {});
  } catch (e) {
    console.error("Spot chat moderation report summary error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/spot-chat/moderation-audit-feed", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;
    const rawLimit = Number(req.query?.limit ?? 20);
    const limit = Number.isInteger(rawLimit) && rawLimit > 0
      ? Math.min(rawLimit, 100)
      : 20;

    const q = await pool.query(
      `
      SELECT
        al.id,
        al.action,
        al.actor_type,
        al.admin_user_id,
        al.user_id,
        al.entity_table,
        al.entity_id,
        al.metadata_json,
        al.created_at
      FROM public.audit_logs al
      WHERE al.action LIKE 'SPOT_CHAT_%'
         OR al.action = 'USER_SUSPENDED_FOR_MODERATION'
      ORDER BY al.created_at DESC, al.id DESC
      LIMIT $1
      `,
      [limit]
    );

    return res.json(q.rows);
  } catch (e) {
    console.error("Spot chat moderation audit feed error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/spot-chat/openai-reasoned-usage", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const overviewQ = await pool.query(
      `
      WITH base AS (
        SELECT
          'spot_chat'::text AS source,
          created_at,
          COALESCE((ai_result_json->'openai_reasoned'->>'attempted') = 'true', FALSE) AS attempted,
          COALESCE((ai_result_json->'openai_reasoned'->>'used') = 'true', FALSE) AS used,
          COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'input_tokens')::bigint, 0) AS input_tokens,
          COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'output_tokens')::bigint, 0) AS output_tokens,
          COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'total_tokens')::bigint, 0) AS total_tokens,
          COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'estimated_cost_usd')::numeric, 0) AS estimated_cost_usd
        FROM public.chat_moderation_logs
        UNION ALL
        SELECT
          'preview'::text AS source,
          created_at,
          COALESCE((ai_result_json->'openai_reasoned'->>'attempted') = 'true', FALSE) AS attempted,
          COALESCE((ai_result_json->'openai_reasoned'->>'used') = 'true', FALSE) AS used,
          COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'input_tokens')::bigint, 0) AS input_tokens,
          COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'output_tokens')::bigint, 0) AS output_tokens,
          COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'total_tokens')::bigint, 0) AS total_tokens,
          COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'estimated_cost_usd')::numeric, 0) AS estimated_cost_usd
        FROM public.chat_moderation_preview_logs
      )
      SELECT
        bucket,
        source,
        COUNT(*) FILTER (WHERE attempted) ::int AS attempts,
        COUNT(*) FILTER (WHERE used) ::int AS used,
        COALESCE(SUM(input_tokens), 0)::bigint AS input_tokens,
        COALESCE(SUM(output_tokens), 0)::bigint AS output_tokens,
        COALESCE(SUM(total_tokens), 0)::bigint AS total_tokens,
        COALESCE(ROUND(SUM(estimated_cost_usd), 8), 0) AS estimated_cost_usd
      FROM (
        SELECT 'today'::text AS bucket, * FROM base WHERE created_at >= date_trunc('day', NOW())
        UNION ALL
        SELECT 'month'::text AS bucket, * FROM base WHERE created_at >= date_trunc('month', NOW())
        UNION ALL
        SELECT 'all_time'::text AS bucket, * FROM base
      ) scoped
      GROUP BY bucket, source
      `
    );

    const dailyQ = await pool.query(
      `
      WITH buckets AS (
        SELECT generate_series(
          date_trunc('day', NOW() - INTERVAL '29 days'),
          date_trunc('day', NOW()),
          INTERVAL '1 day'
        ) AS bucket_date
      ),
      aggregated AS (
        SELECT
          'spot_chat'::text AS source,
          date_trunc('day', created_at) AS bucket_date,
          COUNT(*) FILTER (WHERE ai_result_json->'openai_reasoned'->>'attempted' = 'true')::int AS attempts,
          COUNT(*) FILTER (WHERE ai_result_json->'openai_reasoned'->>'used' = 'true')::int AS used,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'input_tokens')::bigint, 0)), 0)::bigint AS input_tokens,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'output_tokens')::bigint, 0)), 0)::bigint AS output_tokens,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'total_tokens')::bigint, 0)), 0)::bigint AS total_tokens,
          COALESCE(ROUND(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'estimated_cost_usd')::numeric, 0)), 8), 0) AS estimated_cost_usd
        FROM public.chat_moderation_logs
        WHERE created_at >= NOW() - INTERVAL '29 days'
        GROUP BY 1, 2
        UNION ALL
        SELECT
          'preview'::text AS source,
          date_trunc('day', created_at) AS bucket_date,
          COUNT(*) FILTER (WHERE ai_result_json->'openai_reasoned'->>'attempted' = 'true')::int AS attempts,
          COUNT(*) FILTER (WHERE ai_result_json->'openai_reasoned'->>'used' = 'true')::int AS used,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'input_tokens')::bigint, 0)), 0)::bigint AS input_tokens,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'output_tokens')::bigint, 0)), 0)::bigint AS output_tokens,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'total_tokens')::bigint, 0)), 0)::bigint AS total_tokens,
          COALESCE(ROUND(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'estimated_cost_usd')::numeric, 0)), 8), 0) AS estimated_cost_usd
        FROM public.chat_moderation_preview_logs
        WHERE created_at >= NOW() - INTERVAL '29 days'
        GROUP BY 1, 2
      )
      SELECT
        sources.source AS source,
        to_char(b.bucket_date AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS date,
        COALESCE(a.attempts, 0) AS attempts,
        COALESCE(a.used, 0) AS used,
        COALESCE(a.input_tokens, 0) AS input_tokens,
        COALESCE(a.output_tokens, 0) AS output_tokens,
        COALESCE(a.total_tokens, 0) AS total_tokens,
        COALESCE(a.estimated_cost_usd, 0) AS estimated_cost_usd
      FROM buckets b
      CROSS JOIN (VALUES ('spot_chat'::text), ('preview'::text)) sources(source)
      LEFT JOIN aggregated a ON a.bucket_date = b.bucket_date AND a.source = sources.source
      ORDER BY b.bucket_date ASC, sources.source ASC
      `
    );

    const monthlyQ = await pool.query(
      `
      WITH buckets AS (
        SELECT generate_series(
          date_trunc('month', NOW() - INTERVAL '11 months'),
          date_trunc('month', NOW()),
          INTERVAL '1 month'
        ) AS bucket_date
      ),
      aggregated AS (
        SELECT
          'spot_chat'::text AS source,
          date_trunc('month', created_at) AS bucket_date,
          COUNT(*) FILTER (WHERE ai_result_json->'openai_reasoned'->>'attempted' = 'true')::int AS attempts,
          COUNT(*) FILTER (WHERE ai_result_json->'openai_reasoned'->>'used' = 'true')::int AS used,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'input_tokens')::bigint, 0)), 0)::bigint AS input_tokens,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'output_tokens')::bigint, 0)), 0)::bigint AS output_tokens,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'total_tokens')::bigint, 0)), 0)::bigint AS total_tokens,
          COALESCE(ROUND(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'estimated_cost_usd')::numeric, 0)), 8), 0) AS estimated_cost_usd
        FROM public.chat_moderation_logs
        WHERE created_at >= date_trunc('month', NOW() - INTERVAL '11 months')
        GROUP BY 1, 2
        UNION ALL
        SELECT
          'preview'::text AS source,
          date_trunc('month', created_at) AS bucket_date,
          COUNT(*) FILTER (WHERE ai_result_json->'openai_reasoned'->>'attempted' = 'true')::int AS attempts,
          COUNT(*) FILTER (WHERE ai_result_json->'openai_reasoned'->>'used' = 'true')::int AS used,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'input_tokens')::bigint, 0)), 0)::bigint AS input_tokens,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'output_tokens')::bigint, 0)), 0)::bigint AS output_tokens,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'total_tokens')::bigint, 0)), 0)::bigint AS total_tokens,
          COALESCE(ROUND(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'estimated_cost_usd')::numeric, 0)), 8), 0) AS estimated_cost_usd
        FROM public.chat_moderation_preview_logs
        WHERE created_at >= date_trunc('month', NOW() - INTERVAL '11 months')
        GROUP BY 1, 2
      )
      SELECT
        sources.source AS source,
        to_char(b.bucket_date AT TIME ZONE 'UTC', 'YYYY-MM') AS month,
        COALESCE(a.attempts, 0) AS attempts,
        COALESCE(a.used, 0) AS used,
        COALESCE(a.input_tokens, 0) AS input_tokens,
        COALESCE(a.output_tokens, 0) AS output_tokens,
        COALESCE(a.total_tokens, 0) AS total_tokens,
        COALESCE(a.estimated_cost_usd, 0) AS estimated_cost_usd
      FROM buckets b
      CROSS JOIN (VALUES ('spot_chat'::text), ('preview'::text)) sources(source)
      LEFT JOIN aggregated a ON a.bucket_date = b.bucket_date AND a.source = sources.source
      ORDER BY b.bucket_date ASC, sources.source ASC
      `
    );

    function emptyUsageRow() {
      return {
        attempts: 0,
        used: 0,
        input_tokens: 0,
        output_tokens: 0,
        total_tokens: 0,
        estimated_cost_usd: 0,
      };
    }

    const overview = {
      today: { total: emptyUsageRow(), spot_chat: emptyUsageRow(), preview: emptyUsageRow() },
      month: { total: emptyUsageRow(), spot_chat: emptyUsageRow(), preview: emptyUsageRow() },
      all_time: { total: emptyUsageRow(), spot_chat: emptyUsageRow(), preview: emptyUsageRow() },
    };

    for (const row of overviewQ.rows) {
      const bucket = row.bucket;
      const source = row.source;
      const normalized = {
        attempts: Number(row.attempts ?? 0),
        used: Number(row.used ?? 0),
        input_tokens: Number(row.input_tokens ?? 0),
        output_tokens: Number(row.output_tokens ?? 0),
        total_tokens: Number(row.total_tokens ?? 0),
        estimated_cost_usd: Number(row.estimated_cost_usd ?? 0),
      };
      overview[bucket][source] = normalized;
      overview[bucket].total = {
        attempts: overview[bucket].spot_chat.attempts + overview[bucket].preview.attempts,
        used: overview[bucket].spot_chat.used + overview[bucket].preview.used,
        input_tokens: overview[bucket].spot_chat.input_tokens + overview[bucket].preview.input_tokens,
        output_tokens: overview[bucket].spot_chat.output_tokens + overview[bucket].preview.output_tokens,
        total_tokens: overview[bucket].spot_chat.total_tokens + overview[bucket].preview.total_tokens,
        estimated_cost_usd: Number(
          (overview[bucket].spot_chat.estimated_cost_usd + overview[bucket].preview.estimated_cost_usd).toFixed(8)
        ),
      };
    }

    return res.json({
      pricing: {
        input_usd_per_1m_tokens: OPENAI_LLM_MODERATION_INPUT_USD_PER_1M,
        output_usd_per_1m_tokens: OPENAI_LLM_MODERATION_OUTPUT_USD_PER_1M,
      },
      overview,
      daily: dailyQ.rows.map((row) => ({
        source: row.source,
        date: row.date,
        attempts: Number(row.attempts ?? 0),
        used: Number(row.used ?? 0),
        input_tokens: Number(row.input_tokens ?? 0),
        output_tokens: Number(row.output_tokens ?? 0),
        total_tokens: Number(row.total_tokens ?? 0),
        estimated_cost_usd: Number(row.estimated_cost_usd ?? 0),
      })),
      monthly: monthlyQ.rows.map((row) => ({
        source: row.source,
        month: row.month,
        attempts: Number(row.attempts ?? 0),
        used: Number(row.used ?? 0),
        input_tokens: Number(row.input_tokens ?? 0),
        output_tokens: Number(row.output_tokens ?? 0),
        total_tokens: Number(row.total_tokens ?? 0),
        estimated_cost_usd: Number(row.estimated_cost_usd ?? 0),
      })),
    });
  } catch (e) {
    console.error("OpenAI reasoned moderation usage report error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/spot-chat/moderation-report-trends", async (req, res) => {
  try {
    await ensureSpotSubsystemTables();
    const adminCtx = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminCtx) return;

    const range = String(req.query?.range ?? "30d").trim().toLowerCase();
    const bucket = String(req.query?.bucket ?? "day").trim().toLowerCase();

    const rangeDaysMap = {
      "7d": 7,
      "30d": 30,
      "90d": 90,
    };
    const bucketIntervalMap = {
      day: "1 day",
      week: "1 week",
    };

    const rangeDays = rangeDaysMap[range];
    if (!rangeDays) {
      return res.status(400).json({ message: "Invalid range. Use 7d, 30d, or 90d" });
    }
    if (!bucketIntervalMap[bucket]) {
      return res.status(400).json({ message: "Invalid bucket. Use day or week" });
    }

    const bucketExpr = bucket === "week"
      ? "date_trunc('week', created_at)"
      : "date_trunc('day', created_at)";
    const stepInterval = bucketIntervalMap[bucket];

    const trendsQ = await pool.query(
      `
      WITH bounds AS (
        SELECT
          date_trunc($2::text, NOW()) AS bucket_end,
          date_trunc($2::text, NOW() - ($1::text || ' days')::interval) AS bucket_start
      ),
      buckets AS (
        SELECT generate_series(
          (SELECT bucket_start FROM bounds),
          (SELECT bucket_end FROM bounds),
          $3::interval
        ) AS bucket_date
      ),
      aggregated AS (
        SELECT
          ${bucketExpr} AS bucket_date,
          COUNT(*)::int AS total_moderated,
          COUNT(*) FILTER (WHERE action_taken = 'censor_and_warn')::int AS flagged,
          COUNT(*) FILTER (
            WHERE action_taken IN ('block_and_flag', 'block_and_report', 'block_remove_and_report', 'block_and_alert_room')
          )::int AS blocked,
          COUNT(*) FILTER (WHERE detected_categories ? 'profanity')::int AS profanity,
          COUNT(*) FILTER (WHERE detected_categories ? 'hate_speech')::int AS hate_speech,
          COUNT(*) FILTER (WHERE detected_categories ? 'sexual_harassment')::int AS sexual_harassment,
          COUNT(*) FILTER (WHERE detected_categories ? 'scam_risk')::int AS scam_risk,
          COUNT(*) FILTER (WHERE ai_used = TRUE)::int AS ai_used,
          COUNT(*) FILTER (WHERE ai_result_json->'openai_reasoned'->>'attempted' = 'true')::int AS openai_reasoned_attempts,
          COUNT(*) FILTER (WHERE ai_result_json->'openai_reasoned'->>'used' = 'true')::int AS openai_reasoned_used,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'input_tokens')::bigint, 0)), 0)::bigint AS openai_reasoned_input_tokens,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'output_tokens')::bigint, 0)), 0)::bigint AS openai_reasoned_output_tokens,
          COALESCE(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'total_tokens')::bigint, 0)), 0)::bigint AS openai_reasoned_total_tokens,
          COALESCE(ROUND(SUM(COALESCE((ai_result_json->'openai_reasoned'->'cost_estimate'->>'estimated_cost_usd')::numeric, 0)), 8), 0) AS openai_reasoned_estimated_cost_usd
        FROM public.chat_moderation_logs
        WHERE created_at >= NOW() - ($1::text || ' days')::interval
        GROUP BY 1
      )
      SELECT
        to_char(b.bucket_date AT TIME ZONE 'UTC', 'YYYY-MM-DD') AS date,
        COALESCE(a.total_moderated, 0) AS total_moderated,
        COALESCE(a.flagged, 0) AS flagged,
        COALESCE(a.blocked, 0) AS blocked,
        COALESCE(a.profanity, 0) AS profanity,
        COALESCE(a.hate_speech, 0) AS hate_speech,
        COALESCE(a.sexual_harassment, 0) AS sexual_harassment,
        COALESCE(a.scam_risk, 0) AS scam_risk,
        COALESCE(a.ai_used, 0) AS ai_used,
        COALESCE(a.openai_reasoned_attempts, 0) AS openai_reasoned_attempts,
        COALESCE(a.openai_reasoned_used, 0) AS openai_reasoned_used,
        COALESCE(a.openai_reasoned_input_tokens, 0) AS openai_reasoned_input_tokens,
        COALESCE(a.openai_reasoned_output_tokens, 0) AS openai_reasoned_output_tokens,
        COALESCE(a.openai_reasoned_total_tokens, 0) AS openai_reasoned_total_tokens,
        COALESCE(a.openai_reasoned_estimated_cost_usd, 0) AS openai_reasoned_estimated_cost_usd
      FROM buckets b
      LEFT JOIN aggregated a ON a.bucket_date = b.bucket_date
      ORDER BY b.bucket_date ASC
      `,
      [rangeDays, bucket, stepInterval]
    );

    return res.json({
      range,
      bucket,
      points: trendsQ.rows.map((row) => ({
        date: row.date,
        total_moderated: Number(row.total_moderated ?? 0),
        flagged: Number(row.flagged ?? 0),
        blocked: Number(row.blocked ?? 0),
        profanity: Number(row.profanity ?? 0),
        hate_speech: Number(row.hate_speech ?? 0),
        sexual_harassment: Number(row.sexual_harassment ?? 0),
        scam_risk: Number(row.scam_risk ?? 0),
        ai_used: Number(row.ai_used ?? 0),
        openai_reasoned_attempts: Number(row.openai_reasoned_attempts ?? 0),
        openai_reasoned_used: Number(row.openai_reasoned_used ?? 0),
        openai_reasoned_input_tokens: Number(row.openai_reasoned_input_tokens ?? 0),
        openai_reasoned_output_tokens: Number(row.openai_reasoned_output_tokens ?? 0),
        openai_reasoned_total_tokens: Number(row.openai_reasoned_total_tokens ?? 0),
        openai_reasoned_estimated_cost_usd: Number(row.openai_reasoned_estimated_cost_usd ?? 0),
      })),
    });
  } catch (e) {
    console.error("Spot chat moderation trends error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/users", async (req, res) => {
  try {
    await ensureUserAuthColumns();
    await ensureSpotSubsystemTables();

    const adminAuth = await requireActiveAdmin(req, res, { allowBody: false });
    if (!adminAuth) return;

    const listQ = await pool.query(
      `
      WITH problem_reports AS (
        SELECT
          slf.reported_target_user_id AS user_id,
          COUNT(*)::int AS problem_count
        FROM public.spot_leave_feedback slf
        GROUP BY slf.reported_target_user_id
      ),
      company_events AS (
        SELECT
          b.user_id,
          COUNT(*)::int AS company_event_count
        FROM public.bookings b
        JOIN public.events e ON e.id = b.event_id
        WHERE UPPER(COALESCE(e.type::text, '')) = 'BIG_EVENT'
        GROUP BY b.user_id
      )
      SELECT
        u.id,
        CONCAT('US', LPAD(u.id::text, 4, '0')) AS user_code,
        COALESCE(
          NULLIF(TRIM(COALESCE(u.name, '')), ''),
          NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''),
          NULLIF(TRIM(COALESCE(u.email, '')), ''),
          CONCAT('User #', u.id::text)
        ) AS name,
        COALESCE(u.email, '-') AS email,
        COALESCE(u.created_at, NOW()) AS registered_at,
        COALESCE(u.status, 'active') AS status,
        COALESCE(pr.problem_count, 0) AS problem_count,
        COALESCE(ce.company_event_count, 0) AS company_event_count
      FROM public.users u
      LEFT JOIN problem_reports pr ON pr.user_id = u.id
      LEFT JOIN company_events ce ON ce.user_id = u.id
      ORDER BY registered_at DESC, u.id DESC
      `
    );

    return res.json(
      listQ.rows.map((row) => ({
        id: row.id,
        user_id: row.id,
        user_code: row.user_code,
        name: row.name,
        email: row.email,
        registered_at: row.registered_at,
        status: row.status,
        problem_count: row.problem_count,
        company_event_count: row.company_event_count,
      }))
    );
  } catch (e) {
    console.error("Admin users list error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

app.get("/api/admin/users/:id", async (req, res) => {
  try {
    await ensureUserAuthColumns();
    await ensureSpotSubsystemTables();
    await ensureBusinessReferenceColumns();

    const userId = parseUserLookupId(req.params.id);
    if (!userId) {
      return res.status(400).json({ message: "Invalid user id" });
    }

    const detailQ = await pool.query(
      `
      WITH user_base AS (
        SELECT
          u.id,
          COALESCE(
            NULLIF(TRIM(COALESCE(u.name, '')), ''),
            NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''),
            NULLIF(TRIM(COALESCE(u.email, '')), ''),
            CONCAT('User #', u.id::text)
          ) AS name,
          COALESCE(u.email, '-') AS email,
          COALESCE(NULLIF(TRIM(COALESCE(u.phone, '')), ''), '-') AS phone,
          COALESCE(NULLIF(TRIM(COALESCE(u.address, '')), ''), '-') AS address,
          COALESCE(NULLIF(TRIM(COALESCE(u.address_house_no, '')), ''), '') AS address_house_no,
          COALESCE(NULLIF(TRIM(COALESCE(u.address_floor, '')), ''), '') AS address_floor,
          COALESCE(NULLIF(TRIM(COALESCE(u.address_building, '')), ''), '') AS address_building,
          COALESCE(NULLIF(TRIM(COALESCE(u.address_road, '')), ''), '') AS address_road,
          COALESCE(NULLIF(TRIM(COALESCE(u.address_subdistrict, '')), ''), '') AS address_subdistrict,
          COALESCE(NULLIF(TRIM(COALESCE(u.address_district, '')), ''), '') AS address_district,
          COALESCE(NULLIF(TRIM(COALESCE(u.address_province, '')), ''), '') AS address_province,
          COALESCE(NULLIF(TRIM(COALESCE(u.address_postal_code, '')), ''), '') AS address_postal_code,
          COALESCE(u.status, 'active') AS status,
          COALESCE(u.last_login_at, u.updated_at, u.created_at, NOW()) AS last_active_at
        FROM public.users u
        WHERE u.id = $1
      ),
      created_spots AS (
        SELECT
          se.created_by_user_id AS user_id,
          COUNT(*)::int AS post_count,
          COALESCE(
            SUM(
              CASE
                WHEN COALESCE(se.owner_completed_distance_km, 0) > 0
                  THEN se.owner_completed_distance_km
                ELSE COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)
              END
            ),
            0
          )::numeric AS created_spot_km
        FROM public.spot_events se
        WHERE se.creator_role = 'user'
          AND se.created_by_user_id = $1
          AND se.owner_completed_at IS NOT NULL
        GROUP BY se.created_by_user_id
      ),
      joined_spots AS (
        SELECT
          sem.user_id,
          COUNT(*)::int AS joined_spot_count,
          COALESCE(
            SUM(
              COALESCE(
                sem.completed_distance_km,
                COALESCE(se.km_per_round, 0) * COALESCE(se.round_count, 0)
              )
            ),
            0
          )::numeric AS joined_spot_km
        FROM public.spot_event_members sem
        JOIN public.spot_events se ON se.id = sem.spot_event_id
        WHERE sem.user_id = $1
          AND sem.completed_at IS NOT NULL
          AND NOT (
            se.creator_role = 'user'
            AND se.created_by_user_id = sem.user_id
          )
        GROUP BY sem.user_id
      ),
      joined_big_events AS (
        SELECT
          b.user_id,
          COUNT(*)::int AS joined_big_event_count,
          COALESCE(SUM(COALESCE(b.completed_distance_km, e.total_distance, 0)), 0)::numeric AS joined_big_event_km
        FROM public.bookings b
        JOIN public.events e ON e.id = b.event_id
        WHERE b.user_id = $1
          AND UPPER(COALESCE(e.type::text, '')) = 'BIG_EVENT'
          AND b.completed_at IS NOT NULL
        GROUP BY b.user_id
      ),
      problem_reports AS (
        SELECT
          slf.reported_target_user_id AS user_id,
          COUNT(*)::int AS problem_count
        FROM public.spot_leave_feedback slf
        WHERE slf.reported_target_user_id = $1
        GROUP BY slf.reported_target_user_id
      )
      SELECT
        ub.id AS user_id,
        ub.id,
        ub.name,
        ub.email,
        ub.phone,
        ub.last_active_at,
        ub.address,
        COALESCE(cs.post_count, 0) AS post_count,
        COALESCE(js.joined_spot_count, 0) AS joined_spot_count,
        COALESCE(jbe.joined_big_event_count, 0) AS joined_big_event_count,
        (COALESCE(js.joined_spot_count, 0) + COALESCE(jbe.joined_big_event_count, 0)) AS joined_count,
        COALESCE(pr.problem_count, 0) AS problem_count,
        (
          COALESCE(cs.created_spot_km, 0)
          + COALESCE(js.joined_spot_km, 0)
          + COALESCE(jbe.joined_big_event_km, 0)
        )::numeric AS total_km,
        ub.status
      FROM user_base ub
      LEFT JOIN created_spots cs ON cs.user_id = ub.id
      LEFT JOIN joined_spots js ON js.user_id = ub.id
      LEFT JOIN joined_big_events jbe ON jbe.user_id = ub.id
      LEFT JOIN problem_reports pr ON pr.user_id = ub.id
      LIMIT 1
      `,
      [userId]
    );

    if (detailQ.rowCount === 0) {
      return res.status(404).json({ message: "User not found" });
    }

    const row = detailQ.rows[0];
    const createdEventsQ = await pool.query(
      `
      SELECT
        'SPOT'::text AS item_type,
        se.id AS item_id,
        se.title,
        se.description,
        se.location AS location_text,
        se.event_date AS date_text,
        se.event_time AS time_text,
        se.status,
        se.image_base64,
        se.image_url,
        se.created_at AS sort_at
      FROM public.spot_events se
      WHERE se.creator_role = 'user'
        AND se.created_by_user_id = $1
      ORDER BY se.created_at DESC, se.id DESC
      LIMIT 20
      `,
      [userId]
    );

    const joinedEventsQ = await pool.query(
      `
      SELECT *
      FROM (
        SELECT
          'SPOT'::text AS item_type,
          se.id AS item_id,
          se.title,
          se.description,
          se.location AS location_text,
          se.event_date AS date_text,
          se.event_time AS time_text,
          se.status,
          se.image_base64,
          se.image_url,
          to_timestamp(
            se.event_date || ' ' || COALESCE(NULLIF(se.event_time, ''), '00:00'),
            'DD/MM/YYYY HH24:MI'
          ) AS sort_at
        FROM public.spot_event_members sem
        JOIN public.spot_events se ON se.id = sem.spot_event_id
        WHERE sem.user_id = $1
          AND sem.completed_at IS NOT NULL
          AND NOT (
            se.creator_role = 'user'
            AND se.created_by_user_id = sem.user_id
          )

        UNION ALL

        SELECT
          'BIG_EVENT'::text AS item_type,
          e.id AS item_id,
          e.title,
          e.description,
          COALESCE(NULLIF(TRIM(e.meeting_point), ''), NULLIF(TRIM(e.city), ''), NULLIF(TRIM(e.province), ''), '-') AS location_text,
          TO_CHAR(e.start_at AT TIME ZONE 'Asia/Bangkok', 'DD/MM/YYYY') AS date_text,
          TO_CHAR(e.start_at AT TIME ZONE 'Asia/Bangkok', 'HH24:MI') AS time_text,
          COALESCE(b.status::text, e.status::text, 'joined') AS status,
          ''::text AS image_base64,
          COALESCE(
            (
              SELECT em.file_url
              FROM public.event_media em
              WHERE em.event_id = e.id AND em.kind = 'cover'
              ORDER BY em.sort_order ASC NULLS LAST, em.id DESC
              LIMIT 1
            ),
            (
              SELECT em.file_url
              FROM public.event_media em
              WHERE em.event_id = e.id AND em.kind = 'gallery'
              ORDER BY em.sort_order ASC NULLS LAST, em.id ASC
              LIMIT 1
            )
          ) AS image_url,
          e.start_at AS sort_at
        FROM public.bookings b
        JOIN public.events e ON e.id = b.event_id
        WHERE b.user_id = $1
          AND UPPER(COALESCE(e.type::text, '')) = 'BIG_EVENT'
          AND b.completed_at IS NOT NULL
      ) items
      ORDER BY sort_at DESC NULLS LAST, item_id DESC
      LIMIT 20
      `,
      [userId]
    );

    const mapUserActivityItem = (activityRow) => ({
      type: String(activityRow.item_type ?? "").toUpperCase(),
      id: Number(activityRow.item_id ?? 0),
      title: String(activityRow.title ?? "-"),
      description: String(activityRow.description ?? "").trim(),
      location: String(activityRow.location_text ?? "").trim(),
      date: String(activityRow.date_text ?? "").trim(),
      time: String(activityRow.time_text ?? "").trim(),
      status: String(activityRow.status ?? "").trim(),
      image_base64: String(activityRow.image_base64 ?? "").trim(),
      image_url: toAbsoluteUrl(req, activityRow.image_url),
    });

    return res.json({
      user_id: row.user_id,
      id: row.id,
      display_code: makeDisplayCode("US", row.id),
      name: row.name,
      email: row.email,
      phone: row.phone,
      last_active_at: row.last_active_at,
      address: row.address,
      address_house_no: row.address_house_no,
      address_floor: row.address_floor,
      address_building: row.address_building,
      address_road: row.address_road,
      address_subdistrict: row.address_subdistrict,
      address_district: row.address_district,
      address_province: row.address_province,
      address_postal_code: row.address_postal_code,
      post_count: Number(row.post_count ?? 0),
      joined_spot_count: Number(row.joined_spot_count ?? 0),
      joined_big_event_count: Number(row.joined_big_event_count ?? 0),
      joined_count: Number(row.joined_count ?? 0),
      created_events: createdEventsQ.rows.map(mapUserActivityItem),
      joined_events: joinedEventsQ.rows.map(mapUserActivityItem),
      problem_count: Number(row.problem_count ?? 0),
      total_km: Number(row.total_km ?? 0),
      status: row.status,
    });
  } catch (e) {
    console.error("Admin user detail error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  }
});

async function handleAdminUserStatusUpdate(req, res, forcedStatus = null) {
  const client = await pool.connect();
  try {
    await ensureUserAuthColumns();
    const adminCtx = await requireActiveAdmin(req, res, {
      allowQuery: false,
      allowBody: true,
    });
    if (!adminCtx) return;

    const userId = parseUserLookupId(req.params.id);
    if (!userId) {
      return res.status(400).json({ message: "Invalid user id" });
    }

    const nextStatus = String(forcedStatus ?? req.body?.status ?? "")
      .trim()
      .toLowerCase();
    if (!["active", "suspended", "deleted"].includes(nextStatus)) {
      return res.status(400).json({ message: "Invalid status" });
    }

    const existingQ = await client.query(
      `
      SELECT id, email, status
      FROM public.users
      WHERE id = $1
      LIMIT 1
      `,
      [userId]
    );
    if (existingQ.rowCount === 0) {
      return res.status(404).json({ message: "User not found" });
    }

    const existing = existingQ.rows[0];
    const previousStatus = String(existing.status || "active").toLowerCase();
    if (previousStatus === "deleted" && nextStatus !== "deleted") {
      return res.status(400).json({
        message: "Deleted users cannot be restored. Please create a new account.",
      });
    }

    const updatedQ = await client.query(
      `
      UPDATE public.users
      SET status = $2, updated_at = NOW()
      WHERE id = $1
      RETURNING id, email, status, updated_at
      `,
      [userId, nextStatus]
    );

    await insertAuditLog(client, {
      adminUserId: adminCtx.adminId,
      userId,
      actorType: "admin",
      action: nextStatus === "active"
        ? "USER_RESTORED"
        : nextStatus === "suspended"
          ? "USER_SUSPENDED"
          : "USER_DELETED",
      entityTable: "users",
      entityId: userId,
      metadata: {
        previous_status: previousStatus,
        new_status: nextStatus,
        target_user_email: existing.email ?? null,
      },
    });

    return res.json({
      ok: true,
      user: updatedQ.rows[0],
      previous_status: previousStatus,
      status: nextStatus,
    });
  } catch (e) {
    console.error("Admin update user status error:", e);
    return res.status(500).json({
      message: "Server error",
      error: String(e?.message ?? e),
    });
  } finally {
    client.release();
  }
}

app.patch("/api/admin/users/:id", async (req, res) => {
  return handleAdminUserStatusUpdate(req, res);
});

app.patch("/api/admin/users/:id/status", async (req, res) => {
  return handleAdminUserStatusUpdate(req, res);
});

app.delete("/api/admin/users/:id", async (req, res) => {
  if (!req.body || typeof req.body !== "object") {
    req.body = {};
  }
  if (!req.body.admin_id && req.query?.admin_id) {
    req.body.admin_id = req.query.admin_id;
  }
  return handleAdminUserStatusUpdate(req, res, "deleted");
});

app.get("/api/big-events/:id/payment-methods", async (req, res) => {
  try {
    await ensureBusinessReferenceColumns();
    const eventId = Number(req.params.id);
    if (!Number.isFinite(eventId) || eventId <= 0) {
      return res.status(400).json({ message: "Invalid event id" });
    }

    const client = await pool.connect();
    try {
      const payload = await loadEventPaymentMethods(client, eventId);
      if (!payload) {
        return res.status(404).json({ message: "Event not found" });
      }
      const rewardRows = await listEventRewardMediaRows(client, eventId);
      const rewardGroups = buildEventRewardGroups(req, rewardRows);
      const hasGuaranteedShirt = rewardGroups.guaranteed_items.some(
        (item) => String(item?.item_type ?? "").trim().toLowerCase() === BIG_EVENT_SHIRT_ITEM_TYPE
      );

      return res.json({
        event: {
          id: payload.event.id,
          title: payload.event.title,
          start_at: payload.event.start_at,
          fee: Number(payload.event.fee ?? 0),
          currency: String(payload.event.currency ?? "THB").toUpperCase(),
          payment_mode: payload.event.payment_mode,
          enable_promptpay: !!payload.event.enable_promptpay,
          enable_alipay: !!payload.event.enable_alipay,
          stripe_enabled: !!payload.event.stripe_enabled,
          automatic_alipay_available: !!payload.event.automatic_alipay_available,
          automatic_alipay_unavailable_reason: payload.event.automatic_alipay_unavailable_reason ?? null,
          automatic_alipay_provider: payload.event.automatic_alipay_available
            ? payload.event.automatic_alipay_provider ?? null
            : null,
          automatic_alipay_provider_label: payload.event.automatic_alipay_available
            ? payload.event.automatic_alipay_provider_label ?? null
            : null,
          airwallex_configured: !!payload.event.airwallex_configured,
          airwallex_alipay_capability_enabled: !!payload.event.airwallex_alipay_capability_enabled,
          base_currency: payload.event.base_currency,
          base_amount: Number(payload.event.base_amount ?? 0),
          exchange_rate_thb_per_cny: Number(payload.event.exchange_rate_thb_per_cny ?? 0),
          promptpay_amount_thb: Number(payload.event.promptpay_amount_thb ?? payload.event.fee ?? 0),
          alipay_amount_cny: payload.event.alipay_amount_cny == null ? null : Number(payload.event.alipay_amount_cny),
          fx_locked_at: payload.event.fx_locked_at,
          manual_promptpay_qr_url: toAbsoluteUrl(req, payload.event.manual_promptpay_qr_url),
          manual_alipay_qr_url: toAbsoluteUrl(req, payload.event.manual_alipay_qr_url),
          guaranteed_items: rewardGroups.guaranteed_items,
          competition_reward_items: rewardGroups.competition_reward_items,
          requires_shirt_size: hasGuaranteedShirt,
          shirt_size_options: hasGuaranteedShirt ? BIG_EVENT_ALLOWED_SHIRT_SIZES : [],
        },
        methods: payload.methods
          .filter((m) => {
            if (!m.is_active) return false;
            if (String(m.method_type ?? "").toUpperCase() !== "ALIPAY") return true;
            return !!payload.event.automatic_alipay_available;
          })
          .map((m) => ({
            method_type: m.method_type,
            provider: m.provider,
            is_active: !!m.is_active,
            qr_image_url: toAbsoluteUrl(req, m.qr_image_url),
            manual_available: !!m.manual_available,
            stripe_available: !!m.stripe_available,
            amount: Number(m.amount ?? 0),
            currency: String(m.currency ?? payload.event.currency ?? "THB").toUpperCase(),
            fx_rate_used: Number(m.fx_rate_used ?? payload.event.exchange_rate_thb_per_cny ?? 0),
          })),
      });
    } finally {
      client.release();
    }
  } catch (err) {
    console.error("Load user payment methods error:", err);
    return res.status(500).json({ message: "Server error", error: String(err?.message ?? err) });
  }
});

app.get("/api/admin/big-events/:id/payment-methods", async (req, res) => {
  try {
    const adminCtx = await requireActiveAdmin(req, res, { allowQuery: false, allowBody: false });
    if (!adminCtx) return;

    const eventId = Number(req.params.id);
    if (!Number.isFinite(eventId) || eventId <= 0) {
      return res.status(400).json({ message: "Invalid event id" });
    }

    const client = await pool.connect();
    try {
      const payload = await loadEventPaymentMethods(client, eventId);
      if (!payload) {
        return res.status(404).json({ message: "Event not found" });
      }

      return res.json({
        event: {
          id: payload.event.id,
          title: payload.event.title,
          start_at: payload.event.start_at,
          fee: Number(payload.event.fee ?? 0),
          currency: String(payload.event.currency ?? "THB").toUpperCase(),
          payment_mode: payload.event.payment_mode,
          enable_promptpay: !!payload.event.enable_promptpay,
          enable_alipay: !!payload.event.enable_alipay,
          stripe_enabled: !!payload.event.stripe_enabled,
          automatic_alipay_available: !!payload.event.automatic_alipay_available,
          automatic_alipay_unavailable_reason: payload.event.automatic_alipay_unavailable_reason ?? null,
          automatic_alipay_provider: payload.event.automatic_alipay_provider ?? null,
          automatic_alipay_provider_label: payload.event.automatic_alipay_provider_label ?? null,
          airwallex_configured: !!payload.event.airwallex_configured,
          airwallex_alipay_capability_enabled: !!payload.event.airwallex_alipay_capability_enabled,
          base_currency: payload.event.base_currency,
          base_amount: Number(payload.event.base_amount ?? 0),
          exchange_rate_thb_per_cny: Number(payload.event.exchange_rate_thb_per_cny ?? 0),
          promptpay_amount_thb: Number(payload.event.promptpay_amount_thb ?? payload.event.fee ?? 0),
          alipay_amount_cny: payload.event.alipay_amount_cny == null ? null : Number(payload.event.alipay_amount_cny),
          fx_locked_at: payload.event.fx_locked_at,
          manual_promptpay_qr_url: toAbsoluteUrl(req, payload.event.manual_promptpay_qr_url),
          manual_alipay_qr_url: toAbsoluteUrl(req, payload.event.manual_alipay_qr_url),
        },
        methods: payload.methods.map((m) => ({
          method_type: m.method_type,
          provider: m.provider,
          is_active: !!m.is_active,
          qr_image_url: toAbsoluteUrl(req, m.qr_image_url),
          manual_available: !!m.manual_available,
          stripe_available: !!m.stripe_available,
          amount: Number(m.amount ?? 0),
          currency: String(m.currency ?? payload.event.currency ?? "THB").toUpperCase(),
          fx_rate_used: Number(m.fx_rate_used ?? payload.event.exchange_rate_thb_per_cny ?? 0),
        })),
      });
    } finally {
      client.release();
    }
  } catch (err) {
    console.error("Load admin payment methods error:", err);
    return res.status(500).json({ message: "Server error", error: String(err?.message ?? err) });
  }
});

app.put("/api/admin/big-events/:id/payment-methods", async (req, res) => {
  const client = await pool.connect();
  try {
    const adminCtx = await requireActiveAdmin(req, res, { allowQuery: false, allowBody: false });
    if (!adminCtx) return;

    const eventId = Number(req.params.id);
    if (!Number.isFinite(eventId) || eventId <= 0) {
      return res.status(400).json({ message: "Invalid event id" });
    }

    const paymentMode = normalizePaymentMode(req.body?.payment_mode);
    const promptpayEnabled = req.body?.enable_promptpay !== false && req.body?.promptpay_enabled !== false;
    const stripeEnabled = req.body?.stripe_enabled === true || paymentMode !== "manual_qr";
    const manualPromptpayQrUrl =
      String(req.body?.manual_promptpay_qr_url ?? "").trim() || null;
    const lockedConfigResult = deriveLockedEventPaymentConfig({
      base_amount: req.body?.base_amount,
      promptpay_enabled: promptpayEnabled,
    });

    if (!lockedConfigResult.ok) {
      return res.status(400).json({ message: lockedConfigResult.message });
    }
    if (promptpayEnabled && (paymentMode === "manual_qr" || paymentMode === "hybrid") && !manualPromptpayQrUrl) {
      return res.status(400).json({ message: "PromptPay QR is required for Big Event payments" });
    }
    if (paymentMode === "stripe_auto" && !stripeEnabled) {
      return res.status(400).json({ message: "Stripe must be enabled for stripe_auto mode" });
    }
    const lockedConfig = lockedConfigResult.value;

    await client.query("BEGIN");

    const eventQ = await client.query(
      `
      UPDATE events
      SET
        payment_mode = $2::text,
        enable_promptpay = $3::boolean,
        enable_alipay = FALSE,
        stripe_enabled = $4::boolean,
        manual_promptpay_qr_url = $5::text,
        manual_alipay_qr_url = NULL,
        base_currency = 'THB',
        base_amount = $6,
        exchange_rate_thb_per_cny = 0,
        promptpay_amount_thb = $7,
        alipay_amount_cny = NULL,
        fx_locked_at = NOW(),
        fee = $7,
        currency = 'THB',
        promptpay_enabled = $3::boolean,
        alipay_enabled = FALSE,
        alipay_qr_url = NULL,
        qr_url = COALESCE($5::text, qr_url),
        updated_at = NOW()
      WHERE id = $1::bigint
      RETURNING id, title, start_at, fee, currency, payment_mode, enable_promptpay, enable_alipay,
        stripe_enabled, manual_promptpay_qr_url, manual_alipay_qr_url,
        base_currency, base_amount, exchange_rate_thb_per_cny, promptpay_amount_thb, alipay_amount_cny, fx_locked_at
      `,
      [
        eventId,
        paymentMode,
        promptpayEnabled,
        stripeEnabled,
        manualPromptpayQrUrl,
        lockedConfig.base_amount,
        lockedConfig.promptpay_amount_thb,
      ]
    );

    if (eventQ.rowCount === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ message: "Event not found" });
    }

    await upsertEventPaymentMethod(client, {
      eventId,
      methodType: "PROMPTPAY",
      provider: paymentMode === "stripe_auto" ? "STRIPE" : paymentMode === "hybrid" ? "HYBRID" : "MANUAL_QR",
      qrImageUrl: manualPromptpayQrUrl,
      isActive: promptpayEnabled,
    });

    await client.query("COMMIT");

    const eventRow = eventQ.rows[0];
    return res.json({
      event: {
        id: eventRow.id,
        title: eventRow.title,
        start_at: eventRow.start_at,
        fee: Number(eventRow.fee ?? 0),
        currency: String(eventRow.currency ?? "THB").toUpperCase(),
        payment_mode: eventRow.payment_mode,
        enable_promptpay: !!eventRow.enable_promptpay,
        enable_alipay: false,
        stripe_enabled: !!eventRow.stripe_enabled,
        base_currency: eventRow.base_currency,
        base_amount: Number(eventRow.base_amount ?? 0),
        exchange_rate_thb_per_cny: Number(eventRow.exchange_rate_thb_per_cny ?? 0),
        promptpay_amount_thb: Number(eventRow.promptpay_amount_thb ?? eventRow.fee ?? 0),
        alipay_amount_cny: null,
        fx_locked_at: eventRow.fx_locked_at,
        manual_promptpay_qr_url: toAbsoluteUrl(req, eventRow.manual_promptpay_qr_url),
        manual_alipay_qr_url: null,
      },
      methods: [
        {
          method_type: "PROMPTPAY",
          provider: paymentMode === "stripe_auto" ? "STRIPE" : paymentMode === "hybrid" ? "HYBRID" : "MANUAL_QR",
          is_active: !!eventRow.enable_promptpay,
          qr_image_url: toAbsoluteUrl(req, eventRow.manual_promptpay_qr_url),
          manual_available: !!eventRow.manual_promptpay_qr_url,
          stripe_available: !!stripe && paymentMode !== "manual_qr" && !!eventRow.enable_promptpay,
          amount: Number(eventRow.promptpay_amount_thb ?? eventRow.fee ?? 0),
          currency: "THB",
          fx_rate_used: Number(eventRow.exchange_rate_thb_per_cny ?? 0),
        },
      ],
    });
  } catch (err) {
    await client.query("ROLLBACK");
    console.error("Update admin payment methods error:", err);
    return res.status(500).json({ message: "Server error", error: String(err?.message ?? err) });
  } finally {
    client.release();
  }
});

app.post("/api/stripe/create-payment-intent", async (req, res) => {
  const client = await pool.connect();
  let txStarted = false;
  try {
    if (!stripe) {
      return stripeUnavailableResponse(res);
    }
    await ensureBusinessReferenceColumns();
    const userCtx = getRequestUserId(req, { allowQuery: false, allowBody: true });
    if (!userCtx.ok) {
      return res.status(400).json({ message: userCtx.message });
    }

    const eventId = Number(req.body?.event_id);
    const paymentMethodType = normalizePaymentMethodKey(req.body?.selected_payment_method_type);
    let shirtSize = null;
    console.log("[stripe create-payment-intent] request", {
      eventId,
      selected_payment_method_type: paymentMethodType,
      userId: userCtx.userId,
      shirt_size: shirtSize,
    });
    if (!Number.isFinite(eventId) || eventId <= 0) {
      return res.status(400).json({ message: "Invalid event_id" });
    }
    if (!paymentMethodType) {
      return res.status(400).json({ message: "selected_payment_method_type is required" });
    }

    const eventQ = await client.query(
      `
      SELECT
        id,
        type,
        title,
        COALESCE(fee, 0)::numeric AS fee,
        COALESCE(currency, 'THB') AS currency,
        COALESCE(payment_mode, 'manual_qr') AS payment_mode,
        COALESCE(enable_promptpay, promptpay_enabled, TRUE) AS enable_promptpay,
        COALESCE(enable_alipay, alipay_enabled, FALSE) AS enable_alipay,
        COALESCE(stripe_enabled, FALSE) AS stripe_enabled,
        COALESCE(base_currency, currency, 'THB') AS base_currency,
        COALESCE(base_amount, fee, 0)::numeric AS base_amount,
        exchange_rate_thb_per_cny,
        COALESCE(promptpay_amount_thb, fee, 0)::numeric AS promptpay_amount_thb,
        alipay_amount_cny,
        fx_locked_at
      FROM events
      WHERE id = $1
      LIMIT 1
      `,
      [eventId]
    );

    if (eventQ.rowCount === 0) {
      return res.status(404).json({ message: "Event not found" });
    }

    const eventRow = eventQ.rows[0];
    if (String(eventRow.type ?? "").toUpperCase() !== "BIG_EVENT") {
      return res.status(400).json({ message: "This event is not BIG_EVENT" });
    }
    shirtSize = await normalizeBigEventShirtSizeOrThrow(client, {
      eventId,
      shirtSize: req.body?.shirt_size,
    });
    if (!isStripeBranchAllowed(eventRow) || !eventRow.stripe_enabled) {
      return res.status(400).json({ message: "Stripe payment is not enabled for this event" });
    }
    if (paymentMethodType !== "promptpay") {
      return res.status(400).json({ message: "Only PromptPay is available for this event" });
    }
    if (!eventRow.enable_promptpay) {
      return res.status(400).json({ message: "PromptPay is not enabled for this event" });
    }

    const paymentSummary = getEventPaymentSummary(eventRow);

    const userQ = await client.query(
      `
      SELECT email
      FROM public.users
      WHERE id = $1
      LIMIT 1
      `,
      [userCtx.userId]
    );
    const userEmail = String(userQ.rows[0]?.email ?? "").trim();
    const promptpayEmail = userEmail || "test@example.com";

    const existingPaidQ = await client.query(
      `
      SELECT p.id
      FROM payments p
      JOIN bookings b ON b.id = p.booking_id
      WHERE b.user_id = $1
        AND b.event_id = $2
        AND (
          p.paid_at IS NOT NULL
          OR LOWER(COALESCE(p.status::text, '')) IN ('paid', 'completed', 'success', 'succeeded', 'done')
          OR LOWER(COALESCE(b.status::text, '')) IN ('confirmed', 'paid', 'completed', 'success')
        )
      ORDER BY p.id DESC
      LIMIT 1
      `,
      [userCtx.userId, eventId]
    );
    if (existingPaidQ.rowCount > 0) {
      return res.status(409).json({ message: "User already joined this event" });
    }

    await client.query("BEGIN");
    txStarted = true;

    const amount = Number(paymentSummary.promptpay_amount_thb ?? eventRow.fee ?? 0);
    const currency = "thb";
    const bookingId = await ensurePendingBigEventBooking(client, {
      eventId,
      userId: userCtx.userId,
      amount,
      currency: currency.toUpperCase(),
      shirtSize,
    });

    const pendingStatus = await pickEnumSafe(client, "payments", "status", "pending");
    const paymentMethodDbValue = await pickEnumSafe(client, "payments", "method", paymentMethodType);

    const existingPaymentQ = await client.query(
      `
      SELECT id, provider_payment_intent_id, stripe_checkout_session_id
      FROM payments
      WHERE booking_id = $1
        AND LOWER(COALESCE(provider, '')) = 'stripe'
        AND LOWER(COALESCE(payment_method_type, method_type, method::text, '')) = $2
        AND LOWER(COALESCE(status::text, '')) NOT IN ('paid', 'failed', 'cancelled', 'canceled')
      ORDER BY id DESC
      LIMIT 1
      `,
      [bookingId, paymentMethodType]
    );

    let paymentId = null;
    let paymentIntent = null;
    let checkoutSession = null;

    if (existingPaymentQ.rowCount > 0 && existingPaymentQ.rows[0].provider_payment_intent_id) {
      try {
        paymentIntent = await stripe.paymentIntents.retrieve(existingPaymentQ.rows[0].provider_payment_intent_id);
      } catch (_) {
        paymentIntent = null;
      }
      paymentId = existingPaymentQ.rows[0].id;
    }

    const shouldCreateFreshPromptpayIntent =
      !paymentIntent ||
      paymentIntent.status === "canceled" ||
      paymentIntent.status === "succeeded" ||
      !paymentIntent?.next_action?.promptpay_display_qr_code;

    if (paymentMethodType === "alipay") {
      const paymentMethodDbValue = await pickEnumSafe(client, "payments", "method", paymentMethodType);
      if (!paymentId && existingPaymentQ.rowCount > 0) {
        paymentId = existingPaymentQ.rows[0].id;
      }
      if (!paymentId) {
        const ins = await client.query(
          `
          INSERT INTO payments
            (booking_id, user_id, event_id, provider, payment_method_type, method_type, method,
             amount, currency, fx_rate_used, status, created_at, updated_at)
          VALUES
            ($1, $2, $3, 'stripe', $4, UPPER($4), $8, $5, $6, $7, $9, NOW(), NOW())
          RETURNING id
          `,
          [
            bookingId,
            userCtx.userId,
            eventId,
            paymentMethodType,
            amount,
            currency.toUpperCase(),
            paymentSummary.exchange_rate_thb_per_cny,
            paymentMethodDbValue,
            pendingStatus,
          ]
        );
        paymentId = ins.rows[0].id;
      } else {
        await client.query(
          `
          UPDATE payments
          SET
            user_id = $2,
            event_id = $3,
            provider = 'stripe',
            payment_method_type = $4,
            method_type = UPPER($4),
            method = $9,
            amount = $5,
            currency = $6,
            fx_rate_used = $7,
            status = $8,
            provider_payment_intent_id = NULL,
            stripe_payment_intent_id = NULL,
            provider_charge_id = NULL,
            stripe_charge_id = NULL,
            raw_gateway_payload = NULL,
            updated_at = NOW()
          WHERE id = $1
          `,
          [
            paymentId,
            userCtx.userId,
            eventId,
            paymentMethodType,
            amount,
            currency.toUpperCase(),
            paymentSummary.exchange_rate_thb_per_cny,
            pendingStatus,
            paymentMethodDbValue,
          ]
        );
      }

      const origin = `${req.protocol}://${req.get("host")}`;
      checkoutSession = await stripe.checkout.sessions.create({
        mode: "payment",
        payment_method_types: ["alipay"],
        customer_email: userEmail || undefined,
        line_items: [
          {
            quantity: 1,
            price_data: {
              currency,
              unit_amount: Math.round(amount * 100),
              product_data: {
                name: String(eventRow.title ?? `Event #${eventId}`),
              },
            },
          },
        ],
        metadata: {
          event_id: String(eventId),
          booking_id: String(bookingId),
          user_id: String(userCtx.userId),
          payment_id: String(paymentId),
          payment_method_type: paymentMethodType,
          shirt_size: shirtSize ?? "",
        },
        payment_intent_data: {
          metadata: {
            event_id: String(eventId),
            booking_id: String(bookingId),
            user_id: String(userCtx.userId),
            payment_id: String(paymentId),
            payment_method_type: paymentMethodType,
            shirt_size: shirtSize ?? "",
          },
        },
        success_url: `${origin}/paid-success`,
        cancel_url: `${origin}/paid-cancel`,
      });

      await client.query(
        `
        UPDATE payments
        SET stripe_checkout_session_id = $2, updated_at = NOW()
        WHERE id = $1
        `,
        [paymentId, checkoutSession.id]
      );
    } else if (shouldCreateFreshPromptpayIntent) {
      paymentIntent = await stripe.paymentIntents.create({
        amount: Math.round(amount * 100),
        currency,
        payment_method_types: [paymentMethodType],
        payment_method_data:
          paymentMethodType === "promptpay"
            ? {
                type: "promptpay",
                billing_details: {
                  email: promptpayEmail,
                },
              }
            : undefined,
        confirm: true,
        receipt_email: promptpayEmail,
        return_url: `${req.protocol}://${req.get("host")}/paid-success`,
        metadata: {
          event_id: String(eventId),
          booking_id: String(bookingId),
          user_id: String(userCtx.userId),
          payment_method_type: paymentMethodType,
          shirt_size: shirtSize ?? "",
        },
      });
    }

    const chargeId =
      paymentIntent?.latest_charge != null ? String(paymentIntent.latest_charge) : null;

    if (paymentMethodType !== "alipay" && paymentId) {
      await client.query(
        `
        UPDATE payments
        SET
          user_id = $2,
          event_id = $3,
          provider = 'stripe',
          payment_method_type = $4,
          method_type = UPPER($4),
          method = $12,
          provider_payment_intent_id = $5,
          stripe_payment_intent_id = $5,
          provider_charge_id = COALESCE($6, provider_charge_id),
          stripe_charge_id = COALESCE($6, stripe_charge_id),
          amount = $7,
          currency = $8,
          fx_rate_used = $9,
          status = $10,
          raw_gateway_payload = $11::jsonb,
          updated_at = NOW()
        WHERE id = $1
        `,
        [
          paymentId,
          userCtx.userId,
          eventId,
          paymentMethodType,
          paymentIntent.id,
          chargeId,
          amount,
          currency.toUpperCase(),
          paymentSummary.exchange_rate_thb_per_cny,
          pendingStatus,
          JSON.stringify(paymentIntent),
          paymentMethodDbValue,
        ]
      );
    } else if (paymentMethodType !== "alipay") {
      const ins = await client.query(
        `
        INSERT INTO payments
          (booking_id, user_id, event_id, provider, payment_method_type, method_type, method,
           provider_payment_intent_id, stripe_payment_intent_id, provider_charge_id, stripe_charge_id,
           amount, currency, fx_rate_used, status, raw_gateway_payload, created_at, updated_at)
        VALUES
          ($1, $2, $3, 'stripe', $4, UPPER($4), $12, $5, $5, $6, $6, $7, $8, $9, $10, $11::jsonb, NOW(), NOW())
        RETURNING id
        `,
        [
          bookingId,
          userCtx.userId,
          eventId,
          paymentMethodType,
          paymentIntent.id,
          chargeId,
          amount,
          currency.toUpperCase(),
          paymentSummary.exchange_rate_thb_per_cny,
          pendingStatus,
          JSON.stringify(paymentIntent),
          paymentMethodDbValue,
        ]
      );
      paymentId = ins.rows[0].id;
    }

    const bookingReference = await ensureBookingReference(client, bookingId);
    const paymentReference = await ensurePaymentReference(client, paymentId);

    await client.query("COMMIT");

    const nextAction = paymentIntent?.next_action ?? null;
    const hasPromptpayQr = !!paymentIntent?.next_action?.promptpay_display_qr_code;
    const checkoutUrl =
      paymentIntent?.next_action?.redirect_to_url?.url ??
      paymentIntent?.next_action?.promptpay_display_qr_code?.hosted_instructions_url ??
      null;
    const nextActionType = String(nextAction?.type ?? "");
    console.log("[stripe create-payment-intent] response", {
      eventId,
      bookingId,
      paymentMethodType,
      paymentIntentId: paymentIntent?.id ?? null,
      checkoutSessionId: checkoutSession?.id ?? null,
      paymentIntentStatus: paymentIntent?.status ?? null,
      hasPromptpayQr,
    });
    return res.status(201).json({
      ok: true,
      payment_id: paymentId,
      booking_id: bookingId,
      booking_reference: bookingReference,
      payment_reference: paymentReference,
      amount,
      currency: currency.toUpperCase(),
      fx_rate_used: paymentSummary.exchange_rate_thb_per_cny,
      payment_method_type: paymentMethodType,
      provider: "stripe",
      payment_intent_id: paymentIntent?.id ?? null,
      paymentIntentId: paymentIntent?.id ?? null,
      provider_payment_intent_id: paymentIntent?.id ?? null,
      client_secret: paymentIntent?.client_secret ?? null,
      status: paymentIntent?.status ?? "pending",
      next_action: nextAction,
      nextAction: nextAction,
      next_action_type: nextActionType,
      checkout_url: checkoutSession?.url ?? checkoutUrl,
      checkoutUrl: checkoutSession?.url ?? checkoutUrl,
      redirect_url: checkoutSession?.url ?? checkoutUrl,
      session_id: checkoutSession?.id ?? null,
      qrImage:
        paymentIntent?.next_action?.promptpay_display_qr_code?.image_url_png ?? null,
      qr_image_url:
        paymentIntent?.next_action?.promptpay_display_qr_code?.image_url_png ?? null,
      qr_svg_url:
        paymentIntent?.next_action?.promptpay_display_qr_code?.image_url_svg ?? null,
      qr_data: paymentIntent?.next_action?.promptpay_display_qr_code?.data ?? null,
    });
  } catch (err) {
    if (txStarted) {
      await client.query("ROLLBACK");
    }
    if (Number.isFinite(Number(err?.statusCode)) && Number(err.statusCode) >= 400) {
      return res.status(Number(err.statusCode)).json({
        message: err.message,
        error: err.message,
      });
    }
    console.error("Create Stripe payment intent error:", {
      message: err?.message ?? null,
      type: err?.type ?? null,
      code: err?.code ?? null,
      decline_code: err?.decline_code ?? null,
      raw_message: err?.raw?.message ?? null,
    });
    return res.status(500).json({
      message: err?.raw?.message || err?.message || "Stripe payment intent creation failed",
      error: String(err?.message ?? err),
    });
  } finally {
    client.release();
  }
});

async function handleAirwallexAlipayCreate(req, res, { eventIdOverride = null } = {}) {
  const client = await pool.connect();
  let txStarted = false;
  let paymentId = null;
  const alipayProviderKey = getAutomaticAlipayProviderKey() || "airwallex_alipay";
  const alipayProviderLabel = getAutomaticAlipayProviderLabel() || "Airwallex";
  try {
    await ensureBusinessReferenceColumns();
    const userCtx = getRequestUserId(req, { allowQuery: false, allowBody: true });
    if (!userCtx.ok) {
      return res.status(400).json({ message: userCtx.message });
    }
    if (!isAirwallexEnabled()) {
      return res.status(503).json({
        provider: alipayProviderKey,
        provider_label: alipayProviderLabel,
        message: `${alipayProviderLabel} is not configured on the server`,
      });
    }

    const eventId = Number(eventIdOverride ?? req.body?.event_id);
    const paymentMethodType = normalizePaymentMethodKey(req.body?.selected_payment_method_type);
    let shirtSize = null;
    const clientPlatform = String(req.body?.client_platform ?? "").trim().toLowerCase();
    const osType = String(req.body?.os_type ?? "").trim().toLowerCase();
    console.log("[airwallex create-payment] request", {
      eventId,
      selected_payment_method_type: paymentMethodType,
      userId: userCtx.userId,
      clientPlatform: clientPlatform || null,
      osType: osType || null,
    });

    if (!Number.isFinite(eventId) || eventId <= 0) {
      return res.status(400).json({ message: "Invalid event_id" });
    }
    if (paymentMethodType !== "alipay") {
      return res.status(400).json({ message: "Airwallex create route only supports Alipay" });
    }

    const eventQ = await client.query(
      `
      SELECT
        id,
        type,
        title,
        COALESCE(fee, 0)::numeric AS fee,
        COALESCE(currency, 'THB') AS currency,
        COALESCE(payment_mode, 'manual_qr') AS payment_mode,
        COALESCE(enable_promptpay, promptpay_enabled, TRUE) AS enable_promptpay,
        COALESCE(enable_alipay, alipay_enabled, FALSE) AS enable_alipay,
        COALESCE(stripe_enabled, FALSE) AS stripe_enabled,
        COALESCE(base_currency, currency, 'THB') AS base_currency,
        COALESCE(base_amount, fee, 0)::numeric AS base_amount,
        exchange_rate_thb_per_cny,
        COALESCE(promptpay_amount_thb, fee, 0)::numeric AS promptpay_amount_thb,
        alipay_amount_cny,
        fx_locked_at
      FROM events
      WHERE id = $1
      LIMIT 1
      `,
      [eventId]
    );

    if (eventQ.rowCount === 0) {
      return res.status(404).json({ message: "Event not found" });
    }

    const eventRow = eventQ.rows[0];
    if (String(eventRow.type ?? "").toUpperCase() !== "BIG_EVENT") {
      return res.status(400).json({ message: "This event is not BIG_EVENT" });
    }
    shirtSize = await normalizeBigEventShirtSizeOrThrow(client, {
      eventId,
      shirtSize: req.body?.shirt_size,
    });
    const automaticAlipayAvailability = getAutomaticAlipayAvailability(eventRow);
    if (!automaticAlipayAvailability.available) {
      console.warn("[airwallex create-payment] blocked by availability guard", {
        eventId,
        userId: userCtx.userId,
        paymentMethodType,
        reason: automaticAlipayAvailability.reason,
        airwallexConfigured:
          automaticAlipayAvailability.airwallexConfigured ?? isAirwallexEnabled(),
        airwallexAlipayCapabilityEnabled:
          automaticAlipayAvailability.capabilityFlagEnabled ??
          getAirwallexAlipayCapabilityStatus().capabilityFlagEnabled,
      });
      if (automaticAlipayAvailability.reason === "event_not_enabled") {
        return res.status(400).json({ message: "Alipay is not enabled for this event" });
      }
      if (
        automaticAlipayAvailability.reason === "payment_mode_not_supported" ||
        automaticAlipayAvailability.reason === "provider_payments_disabled"
      ) {
        return res.status(400).json({
          message: "Automatic Alipay is not enabled for this event",
        });
      }
      if (automaticAlipayAvailability.reason === "airwallex_not_configured") {
        return res.status(503).json({
          code: "airwallex_not_configured",
          provider: alipayProviderKey,
          provider_label: alipayProviderLabel,
          reason: automaticAlipayAvailability.reason,
          message: `${alipayProviderLabel} is not configured on the server`,
        });
      }
      return res.status(409).json({
        code: "airwallex_alipay_not_enabled",
        provider: alipayProviderKey,
        provider_label: alipayProviderLabel,
        reason: automaticAlipayAvailability.reason,
        message:
          `Alipay is not enabled on this ${alipayProviderLabel} account yet. Set AIRWALLEX_ALIPAY_ENABLED=true after ${alipayProviderLabel} enables it for this account.`,
      });
    }

    const paymentSummary = getEventPaymentSummary(eventRow);
    const amount = Number(paymentSummary.alipay_amount_cny ?? 0);
    const currency = "CNY";
    if (!(amount > 0)) {
      return res.status(400).json({ message: "Invalid Alipay amount for this event" });
    }

    const existingPaidQ = await client.query(
      `
      SELECT p.id
      FROM payments p
      JOIN bookings b ON b.id = p.booking_id
      WHERE b.user_id = $1
        AND b.event_id = $2
        AND (
          p.paid_at IS NOT NULL
          OR LOWER(COALESCE(p.status::text, '')) IN ('paid', 'completed', 'success', 'succeeded', 'done')
          OR LOWER(COALESCE(b.status::text, '')) IN ('confirmed', 'paid', 'completed', 'success')
        )
      ORDER BY p.id DESC
      LIMIT 1
      `,
      [userCtx.userId, eventId]
    );
    if (existingPaidQ.rowCount > 0) {
      return res.status(409).json({ message: "User already joined this event" });
    }

    await client.query("BEGIN");
    txStarted = true;

    const bookingId = await ensurePendingBigEventBooking(client, {
      eventId,
      userId: userCtx.userId,
      amount,
      currency,
      shirtSize,
    });
    await client.query(
      `
      SELECT id
      FROM bookings
      WHERE id = $1
      FOR UPDATE
      `,
      [bookingId]
    );
    const bookingReference = await ensureBookingReference(client, bookingId);
    const pendingStatus = await pickEnumSafe(client, "payments", "status", "pending");
    const paymentMethodDbValue = await pickEnumSafe(client, "payments", "method", paymentMethodType);

    let reusablePayment = await loadReusableAirwallexPendingPayment(
      client,
      bookingId,
      paymentMethodType
    );

    if (reusablePayment && hasProviderPaymentTimedOut(reusablePayment)) {
      await expireTimedOutAirwallexPayment(client, reusablePayment);
      reusablePayment = null;
    }

    if (reusablePayment?.provider_payment_intent_id) {
      try {
        const intent = await airwallex.retrievePaymentIntent(
          reusablePayment.provider_payment_intent_id
        );
        const syncResult = await syncAirwallexPaymentRecord(
          client,
          reusablePayment,
          intent
        );
        reusablePayment = {
          ...reusablePayment,
          status: syncResult.status,
          raw_gateway_payload: intent,
          provider_payment_intent_id:
            reusablePayment.provider_payment_intent_id || intent?.id || null,
          provider_txn_id:
            reusablePayment.provider_txn_id ||
            intent?.latest_payment_attempt?.id ||
            null,
        };
      } catch (syncErr) {
        if (hasProviderPaymentTimedOut(reusablePayment)) {
          await expireTimedOutAirwallexPayment(client, reusablePayment);
          reusablePayment = null;
        } else {
          console.warn("[airwallex create-payment] reuse sync warning", {
            bookingId,
            paymentId: reusablePayment.id,
            message: syncErr?.message ?? String(syncErr),
          });
        }
      }
    }

    if (
      reusablePayment &&
      isPendingLikeLocalPaymentStatus(reusablePayment.status) &&
      !hasProviderPaymentTimedOut(reusablePayment) &&
      (
        getAirwallexNextActionUrl(parseGatewayPayload(reusablePayment.raw_gateway_payload)) ||
        getAirwallexQrUrl(parseGatewayPayload(reusablePayment.raw_gateway_payload))
      )
    ) {
      await ensurePaymentReference(client, reusablePayment.id);
      await client.query("COMMIT");
      txStarted = false;
      return res.status(200).json(
        buildAirwallexHostedPaymentResponse(
          req,
          reusablePayment,
          parseGatewayPayload(reusablePayment.raw_gateway_payload),
          { reused_existing_payment: true }
        )
      );
    }

    if (reusablePayment && isSuccessfulPaymentStatus(reusablePayment.status)) {
      await client.query("ROLLBACK");
      txStarted = false;
      return res.status(409).json({ message: "User already joined this event" });
    }

    if (reusablePayment) {
      paymentId = reusablePayment.id;
      await client.query(
        `
        UPDATE payments
        SET
          user_id = $2,
          event_id = $3,
          provider = 'airwallex_alipay',
          payment_method_type = $4,
          method_type = UPPER($4),
          method = $9,
          amount = $5,
          currency = $6,
          fx_rate_used = $7,
          status = $8,
          provider_payment_intent_id = NULL,
          provider_charge_id = NULL,
          provider_txn_id = NULL,
          raw_gateway_payload = NULL,
          failure_code = NULL,
          failure_reason = NULL,
          paid_at = NULL,
          updated_at = NOW()
        WHERE id = $1
        `,
        [
          paymentId,
          userCtx.userId,
          eventId,
          paymentMethodType,
          amount,
          currency,
          paymentSummary.exchange_rate_thb_per_cny,
          pendingStatus,
          paymentMethodDbValue,
        ]
      );
    } else {
      const paymentIns = await client.query(
        `
        INSERT INTO payments
          (booking_id, user_id, event_id, provider, payment_method_type, method_type, method,
           amount, currency, fx_rate_used, status, created_at, updated_at)
        VALUES
          ($1, $2, $3, 'airwallex_alipay', $4, UPPER($4), $8, $5, $6, $7, $9, NOW(), NOW())
        RETURNING id
        `,
        [
          bookingId,
          userCtx.userId,
          eventId,
          paymentMethodType,
          amount,
          currency,
          paymentSummary.exchange_rate_thb_per_cny,
          paymentMethodDbValue,
          pendingStatus,
        ]
      );
      paymentId = paymentIns.rows[0].id;
    }

    const paymentReference = await ensurePaymentReference(client, paymentId);
    const returnUrl = buildAirwallexReturnUrl(req, paymentId);
    const requestSeed = Date.now();
    const createPayload = {
      request_id: `${paymentReference}-create-${requestSeed}`,
      amount: roundMoney(amount),
      currency,
      merchant_order_id: paymentReference,
      return_url: returnUrl,
    };
    const createdIntent = await airwallex.createPaymentIntent(createPayload);
    const providerPaymentIntentId = String(createdIntent?.id ?? "").trim();
    if (!providerPaymentIntentId) {
      throw new Error("Airwallex create payment intent did not return an id");
    }

    await client.query(
      `
      UPDATE payments
      SET
        provider = 'airwallex_alipay',
        provider_payment_intent_id = $2,
        provider_txn_id = COALESCE($3, provider_txn_id),
        raw_gateway_payload = $4::jsonb,
        updated_at = NOW()
      WHERE id = $1
      `,
      [
        paymentId,
        providerPaymentIntentId,
        String(createdIntent?.latest_payment_attempt?.id ?? createdIntent?.merchant_order_id ?? "").trim() || null,
        toJsonbParam(createdIntent),
      ]
    );

    const confirmPayload = {
      request_id: `${paymentReference}-confirm-${requestSeed}`,
      payment_method: {
        type: "alipaycn",
        alipaycn: {
          flow: clientPlatform === "web" ? "qrcode" : "mobile_web",
          ...(clientPlatform === "web"
            ? {}
            : { os_type: osType === "ios" ? "ios" : "android" }),
        },
      },
      return_url: returnUrl,
    };
    let confirmedIntent;
    try {
      confirmedIntent = await airwallex.confirmPaymentIntent(
        providerPaymentIntentId,
        confirmPayload
      );
    } catch (confirmErr) {
      if (isAirwallexAlipayNotEnabledError(confirmErr?.response)) {
        const failedStatus = await pickEnumSafe(client, "payments", "status", "failed");
        await client.query(
          `
          UPDATE payments
          SET
            status = $2,
            provider = 'airwallex_alipay',
            provider_payment_intent_id = COALESCE($3, provider_payment_intent_id),
            raw_gateway_payload = $4::jsonb,
            failure_code = $5,
            failure_reason = $6,
            updated_at = NOW()
          WHERE id = $1
          `,
          [
            paymentId,
            failedStatus,
            providerPaymentIntentId,
            toJsonbParam(confirmErr?.response ?? { message: confirmErr?.message ?? String(confirmErr) }),
            extractAirwallexErrorCode(confirmErr?.response),
            "Alipay is not enabled on this Airwallex account yet.",
          ]
        );
      }
      throw confirmErr;
    }
    const combinedIntent = {
      ...createdIntent,
      ...confirmedIntent,
      merchant_order_id: confirmedIntent?.merchant_order_id ?? createdIntent?.merchant_order_id ?? paymentReference,
      id: providerPaymentIntentId,
    };

    const localPaymentSnapshot = {
      id: paymentId,
      booking_id: bookingId,
      user_id: userCtx.userId,
      event_id: eventId,
      amount,
      currency,
    };
    const syncResult = await syncAirwallexPaymentRecord(
      client,
      localPaymentSnapshot,
      combinedIntent
    );
    const checkoutUrl = getAirwallexNextActionUrl(combinedIntent);
    const qrUrl = getAirwallexQrUrl(combinedIntent);

    await client.query("COMMIT");
    txStarted = false;

    if (!checkoutUrl && ["failed", "cancelled"].includes(String(syncResult.status ?? "").toLowerCase())) {
      return res.status(400).json({
        message: extractAirwallexErrorMessage(combinedIntent),
        payment_id: paymentId,
        booking_id: bookingId,
        provider: alipayProviderKey,
        provider_label: alipayProviderLabel,
        provider_payment_intent_id: providerPaymentIntentId,
        status: syncResult.status,
      });
    }

    console.log("[airwallex create-payment] response", {
      eventId,
      bookingId,
      paymentId,
      providerPaymentIntentId,
      status: combinedIntent?.status ?? localStatus,
      hasCheckoutUrl: !!checkoutUrl,
    });

    return res.status(201).json({
      ok: true,
      payment_id: paymentId,
      booking_id: bookingId,
      booking_reference: bookingReference,
      payment_reference: paymentReference,
      amount,
      currency,
      fx_rate_used: paymentSummary.exchange_rate_thb_per_cny,
      payment_method_type: paymentMethodType,
      provider: alipayProviderKey,
      provider_label: alipayProviderLabel,
      provider_payment_intent_id: providerPaymentIntentId,
      status: syncResult.status,
      next_action: confirmedIntent?.next_action ?? combinedIntent?.next_action ?? null,
      checkout_url: checkoutUrl,
      redirect_url: checkoutUrl,
      qr_url: qrUrl,
      return_url: returnUrl,
    });
  } catch (err) {
    if (txStarted && Number.isFinite(Number(paymentId)) && Number(paymentId) > 0) {
      try {
        const failedStatus = await pickEnumSafe(client, "payments", "status", "failed");
        const mappedError = mapAirwallexAppError(
          err?.response,
          err?.message || "Airwallex payment creation failed"
        );
        await client.query(
          `
          UPDATE payments
          SET
            status = $2,
            provider = 'airwallex_alipay',
            raw_gateway_payload = $3::jsonb,
            failure_code = $4,
            failure_reason = $5,
            updated_at = NOW()
          WHERE id = $1
          `,
          [
            paymentId,
            failedStatus,
            toJsonbParam(err?.response ?? { message: err?.message ?? String(err) }),
            mappedError.providerCode,
            mappedError.message,
          ]
        );
        await client.query("COMMIT");
        txStarted = false;
      } catch (commitErr) {
        await client.query("ROLLBACK");
        txStarted = false;
        console.error("[airwallex create-payment] rollback after failure", commitErr);
      }
    } else if (txStarted) {
      await client.query("ROLLBACK");
      txStarted = false;
    }
    if (Number.isFinite(Number(err?.statusCode)) && Number(err.statusCode) >= 400) {
      return res.status(Number(err.statusCode)).json({
        message: err.message,
        error: err.message,
      });
    }

    console.error("[airwallex create-payment] error", {
      message: err?.message ?? null,
      status: err?.status ?? null,
      response: err?.response ?? null,
    });
    const mappedError = mapAirwallexAppError(
      err?.response,
      err?.message || "Airwallex payment creation failed"
    );
    return res.status(mappedError.httpStatus).json({
      code: mappedError.code,
      provider_error_code: mappedError.providerCode,
      provider: alipayProviderKey,
      provider_label: alipayProviderLabel,
      payment_id: Number.isFinite(Number(paymentId)) && Number(paymentId) > 0 ? paymentId : null,
      status: isAirwallexAlipayNotEnabledError(err?.response) ? "failed" : null,
      message: mappedError.message,
      error: String(err?.message ?? err),
    });
  } finally {
    client.release();
  }
}

async function handleAntomAlipayCreate(req, res, { eventIdOverride = null } = {}) {
  const provider = "antom_alipay";
  const providerLabel = "Antom";
  const client = await pool.connect();
  let txStarted = false;
  let paymentId = null;
  try {
    await ensureBusinessReferenceColumns();
    const userCtx = getRequestUserId(req, { allowQuery: false, allowBody: true });
    if (!userCtx.ok) {
      return res.status(400).json({ message: userCtx.message });
    }
    if (!isAntomEnabled()) {
      return res.status(503).json({
        code: "antom_not_configured",
        provider,
        provider_label: providerLabel,
        message: `${providerLabel} is not configured on the server`,
      });
    }

    const eventId = Number(eventIdOverride ?? req.body?.event_id);
    const paymentMethodType = normalizePaymentMethodKey(req.body?.selected_payment_method_type);
    let shirtSize = null;
    if (!Number.isFinite(eventId) || eventId <= 0) {
      return res.status(400).json({ message: "Invalid event_id" });
    }
    if (paymentMethodType !== "alipay") {
      return res.status(400).json({ message: "Antom create route only supports Alipay" });
    }

    const eventQ = await client.query(
      `
      SELECT
        id,
        type,
        title,
        COALESCE(fee, 0)::numeric AS fee,
        COALESCE(currency, 'THB') AS currency,
        COALESCE(payment_mode, 'manual_qr') AS payment_mode,
        COALESCE(enable_promptpay, promptpay_enabled, TRUE) AS enable_promptpay,
        COALESCE(enable_alipay, alipay_enabled, FALSE) AS enable_alipay,
        COALESCE(stripe_enabled, FALSE) AS stripe_enabled,
        COALESCE(base_currency, currency, 'THB') AS base_currency,
        COALESCE(base_amount, fee, 0)::numeric AS base_amount,
        exchange_rate_thb_per_cny,
        COALESCE(promptpay_amount_thb, fee, 0)::numeric AS promptpay_amount_thb,
        alipay_amount_cny,
        fx_locked_at
      FROM events
      WHERE id = $1
      LIMIT 1
      `,
      [eventId]
    );
    if (eventQ.rowCount === 0) {
      return res.status(404).json({ message: "Event not found" });
    }
    const eventRow = eventQ.rows[0];
    if (String(eventRow.type ?? "").toUpperCase() !== "BIG_EVENT") {
      return res.status(400).json({ message: "This event is not BIG_EVENT" });
    }
    shirtSize = await normalizeBigEventShirtSizeOrThrow(client, {
      eventId,
      shirtSize: req.body?.shirt_size,
    });

    const automaticAlipayAvailability = getAutomaticAlipayAvailability(eventRow);
    if (!automaticAlipayAvailability.available) {
      if (automaticAlipayAvailability.reason === "event_not_enabled") {
        return res.status(400).json({ message: "Alipay is not enabled for this event" });
      }
      if (automaticAlipayAvailability.reason === "antom_not_configured") {
        return res.status(503).json({
          code: "antom_not_configured",
          provider,
          provider_label: providerLabel,
          reason: automaticAlipayAvailability.reason,
          message: `${providerLabel} is not configured on the server`,
        });
      }
      if (automaticAlipayAvailability.reason === "env_flag_off") {
        return res.status(409).json({
          code: "antom_alipay_not_enabled",
          provider,
          provider_label: providerLabel,
          reason: automaticAlipayAvailability.reason,
          message: "Antom Alipay is currently disabled at runtime.",
        });
      }
      return res.status(400).json({
        code: "automatic_alipay_unavailable",
        provider,
        provider_label: providerLabel,
        reason: automaticAlipayAvailability.reason,
        message: "Automatic Alipay is not enabled for this event",
      });
    }

    const paymentSummary = getEventPaymentSummary(eventRow);
    const amount = Number(paymentSummary.alipay_amount_cny ?? 0);
    const currency = "CNY";
    if (!(amount > 0)) {
      return res.status(400).json({ message: "Invalid Alipay amount for this event" });
    }

    await client.query("BEGIN");
    txStarted = true;
    const bookingId = await ensurePendingBigEventBooking(client, {
      eventId,
      userId: userCtx.userId,
      amount,
      currency,
      shirtSize,
    });
    const bookingReference = await ensureBookingReference(client, bookingId);
    const pendingStatus = await pickEnumSafe(client, "payments", "status", "pending");
    const paymentMethodDbValue = await pickEnumSafe(client, "payments", "method", paymentMethodType);

    const paymentIns = await client.query(
      `
      INSERT INTO payments
        (booking_id, user_id, event_id, provider, payment_method_type, method_type, method,
         amount, currency, fx_rate_used, status, created_at, updated_at)
      VALUES
        ($1, $2, $3, 'antom_alipay', $4, UPPER($4), $8, $5, $6, $7, $9, NOW(), NOW())
      RETURNING id
      `,
      [
        bookingId,
        userCtx.userId,
        eventId,
        paymentMethodType,
        amount,
        currency,
        paymentSummary.exchange_rate_thb_per_cny,
        paymentMethodDbValue,
        pendingStatus,
      ]
    );
    paymentId = paymentIns.rows[0].id;
    const paymentReference = await ensurePaymentReference(client, paymentId);

    const notifyUrl =
      String(process.env.ALIPAY_NOTIFY_URL ?? "").trim() ||
      `${req.protocol}://${req.get("host")}/api/alipay/webhook`;
    const redirectUrl = buildAirwallexReturnUrl(req, paymentId);
    const payload = {
      paymentRequestId: `${paymentReference}-antom-${Date.now()}`,
      paymentAmount: {
        value: roundMoney(amount).toFixed(2),
        currency,
      },
      paymentMethod: {
        paymentMethodType: "ALIPAY_CN",
      },
      order: {
        referenceOrderId: paymentReference,
        orderDescription: String(eventRow.title ?? `Event #${eventId}`),
        orderAmount: {
          value: roundMoney(amount).toFixed(2),
          currency,
        },
      },
      productCode: "CASHIER_PAYMENT",
      paymentNotifyUrl: notifyUrl,
      paymentRedirectUrl: redirectUrl,
    };
    const antomResponse = await antom.pay(payload);
    const providerPaymentIntentId = String(
      antomResponse?.paymentId ?? antomResponse?.paymentRequestId ?? payload.paymentRequestId
    ).trim();

    await client.query(
      `
      UPDATE payments
      SET
        provider = 'antom_alipay',
        provider_payment_intent_id = $2,
        provider_txn_id = COALESCE($3, provider_txn_id),
        raw_gateway_payload = $4::jsonb,
        updated_at = NOW()
      WHERE id = $1
      `,
      [
        paymentId,
        providerPaymentIntentId || null,
        String(antomResponse?.paymentId ?? antomResponse?.paymentRequestId ?? "").trim() || null,
        toJsonbParam(antomResponse),
      ]
    );

    await client.query("COMMIT");
    txStarted = false;

    return res.status(201).json({
      ...buildAntomHostedPaymentResponse(
        req,
        {
          id: paymentId,
          booking_id: bookingId,
          booking_reference: bookingReference,
          payment_reference: paymentReference,
          amount,
          currency,
          fx_rate_used: paymentSummary.exchange_rate_thb_per_cny,
          provider_payment_intent_id: providerPaymentIntentId || null,
          provider_txn_id: providerPaymentIntentId || null,
          status: pendingStatus,
          raw_gateway_payload: antomResponse,
        },
        antomResponse
      ),
    });
  } catch (err) {
    if (txStarted && Number.isFinite(Number(paymentId)) && Number(paymentId) > 0) {
      try {
        const failedStatus = await pickEnumSafe(client, "payments", "status", "failed");
        const mappedError = mapAntomAppError(
          err?.response,
          err?.message || "Antom payment creation failed"
        );
        await client.query(
          `
          UPDATE payments
          SET
            status = $2,
            provider = 'antom_alipay',
            raw_gateway_payload = $3::jsonb,
            failure_code = $4,
            failure_reason = $5,
            updated_at = NOW()
          WHERE id = $1
          `,
          [
            paymentId,
            failedStatus,
            toJsonbParam(err?.response ?? { message: err?.message ?? String(err) }),
            mappedError.providerCode,
            mappedError.message,
          ]
        );
        await client.query("COMMIT");
        txStarted = false;
      } catch (_) {
        await client.query("ROLLBACK");
        txStarted = false;
      }
    } else if (txStarted) {
      await client.query("ROLLBACK");
      txStarted = false;
    }
    if (Number.isFinite(Number(err?.statusCode)) && Number(err.statusCode) >= 400) {
      return res.status(Number(err.statusCode)).json({
        message: err.message,
        error: err.message,
      });
    }

    const mappedError = mapAntomAppError(
      err?.response,
      err?.message || "Antom payment creation failed"
    );
    return res.status(mappedError.httpStatus).json({
      code: mappedError.code,
      provider_error_code: mappedError.providerCode,
      provider,
      provider_label: providerLabel,
      payment_id: Number.isFinite(Number(paymentId)) && Number(paymentId) > 0 ? paymentId : null,
      message: mappedError.message,
      error: String(err?.message ?? err),
    });
  } finally {
    client.release();
  }
}

app.post("/api/payments/airwallex/create", async (req, res) => {
  return handleAirwallexAlipayCreate(req, res);
});

app.post("/api/payments/alipay/create", async (req, res) => {
  return res.status(410).json({
    message: "Alipay has been removed. Please use PromptPay.",
  });
});

async function handleAirwallexPaymentStatus(req, res) {
  const client = await pool.connect();
  try {
    await ensureBusinessReferenceColumns();
    const paymentId = Number(req.params.paymentId);
    const userCtx = getRequestUserId(req, { allowQuery: true, allowBody: false });
    if (!userCtx.ok) {
      return res.status(400).json({ error: userCtx.message, message: userCtx.message });
    }
    if (!Number.isFinite(paymentId) || paymentId <= 0) {
      return res.status(400).json({ message: "Invalid payment id" });
    }

    let row = await loadOwnedPaymentStatusRow(client, paymentId, userCtx.userId);
    if (!row) {
      return res.status(404).json({ message: "Payment not found" });
    }
    if (String(row.provider ?? "").trim().toLowerCase() !== "airwallex_alipay") {
      return res.status(400).json({ message: "Payment is not an Airwallex Alipay payment" });
    }

    const normalizedStatus = String(row.status ?? "").trim().toLowerCase();
    const providerPaymentIntentId = String(row.provider_payment_intent_id ?? "").trim();
    const shouldSync =
      !!providerPaymentIntentId &&
      !["paid", "completed", "success", "succeeded", "done", "failed", "cancelled", "canceled"].includes(normalizedStatus);

    console.log("[AIRWALLEX PAYMENT STATUS]", {
      paymentId,
      providerPaymentIntentId: providerPaymentIntentId || null,
      status: normalizedStatus,
      shouldSync,
    });

    if (shouldSync) {
      try {
        const intent = await airwallex.retrievePaymentIntent(providerPaymentIntentId);
        await client.query("BEGIN");
        const syncResult = await syncAirwallexPaymentRecord(client, row, intent);
        if (
          isPendingLikeLocalPaymentStatus(syncResult.status) &&
          hasProviderPaymentTimedOut(row)
        ) {
          await expireTimedOutAirwallexPayment(client, row);
        }
        await client.query("COMMIT");
      } catch (err) {
        try {
          await client.query("ROLLBACK");
        } catch (_) {}
        if (hasProviderPaymentTimedOut(row)) {
          await client.query("BEGIN");
          await expireTimedOutAirwallexPayment(client, row);
          await client.query("COMMIT");
        }
        console.error("[AIRWALLEX PAYMENT STATUS SYNC ERROR]", {
          paymentId,
          message: err?.message ?? null,
          status: err?.status ?? null,
          response: err?.response ?? null,
        });
      }
      row = await loadOwnedPaymentStatusRow(client, paymentId, userCtx.userId);
    } else if (hasProviderPaymentTimedOut(row)) {
      await client.query("BEGIN");
      await expireTimedOutAirwallexPayment(client, row);
      await client.query("COMMIT");
      row = await loadOwnedPaymentStatusRow(client, paymentId, userCtx.userId);
    }

    return res.json(buildPaymentStatusResponse(req, row));
  } catch (err) {
    console.error("[AIRWALLEX PAYMENT STATUS ERROR]", err);
    return res.status(500).json({ message: "Server error", error: String(err?.message ?? err) });
  } finally {
    client.release();
  }
}

app.get("/api/payments/airwallex/:paymentId/status", handleAirwallexPaymentStatus);
async function handleAntomPaymentStatus(req, res) {
  const client = await pool.connect();
  try {
    await ensureBusinessReferenceColumns();
    const paymentId = Number(req.params.paymentId);
    const userCtx = getRequestUserId(req, { allowQuery: true, allowBody: false });
    if (!userCtx.ok) {
      return res.status(400).json({ error: userCtx.message, message: userCtx.message });
    }
    if (!Number.isFinite(paymentId) || paymentId <= 0) {
      return res.status(400).json({ message: "Invalid payment id" });
    }

    let row = await loadOwnedPaymentStatusRow(client, paymentId, userCtx.userId);
    if (!row) {
      return res.status(404).json({ message: "Payment not found" });
    }
    if (String(row.provider ?? "").trim().toLowerCase() !== "antom_alipay") {
      return res.status(400).json({ message: "Payment is not an Antom Alipay payment" });
    }

    const normalizedStatus = String(row.status ?? "").trim().toLowerCase();
    const providerPaymentIntentId = String(row.provider_payment_intent_id ?? "").trim();
    const shouldSync =
      !!providerPaymentIntentId &&
      !["paid", "completed", "success", "succeeded", "done", "failed", "cancelled", "canceled"].includes(normalizedStatus);

    if (shouldSync) {
      try {
        const inquiryPayload = {
          paymentRequestId: providerPaymentIntentId,
        };
        const inquiry = await antom.inquiryPayment(inquiryPayload);
        await client.query("BEGIN");
        await syncAntomPaymentRecord(client, row, inquiry);
        await client.query("COMMIT");
      } catch (err) {
        try {
          await client.query("ROLLBACK");
        } catch (_) {}
        console.error("[ANTOM PAYMENT STATUS SYNC ERROR]", {
          paymentId,
          message: err?.message ?? null,
          status: err?.status ?? null,
          response: err?.response ?? null,
        });
      }
      row = await loadOwnedPaymentStatusRow(client, paymentId, userCtx.userId);
    }

    return res.json(buildPaymentStatusResponse(req, row));
  } catch (err) {
    console.error("[ANTOM PAYMENT STATUS ERROR]", err);
    return res.status(500).json({ message: "Server error", error: String(err?.message ?? err) });
  } finally {
    client.release();
  }
}

app.get("/api/payments/alipay/:paymentId/status", async (req, res) => {
  return res.status(410).json({
    message: "Alipay has been removed. Please use PromptPay.",
  });
});

function handleAlipayReturnPage(req, res) {
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  return res.status(200).send(`<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <title>GatherGo Payment Return</title>
    <style>
      body { font-family: Arial, sans-serif; margin: 0; background: #f5f7fb; color: #1f2937; }
      .card { max-width: 520px; margin: 72px auto; background: #fff; border-radius: 16px; padding: 24px; box-shadow: 0 12px 28px rgba(15, 23, 42, 0.08); }
      h1 { margin-top: 0; font-size: 24px; }
      p { line-height: 1.5; }
      a { color: #0b74de; }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>Payment Return Received</h1>
      <p>You can return to GatherGo now. If this tab does not close automatically, switch back to the app and refresh payment status.</p>
      <p><a href="/">Open GatherGo</a></p>
    </div>
    <script>
      try {
        if (window.opener && typeof window.opener.focus === 'function') {
          window.opener.focus();
        }
      } catch (_) {}
      setTimeout(function () {
        try { window.close(); } catch (_) {}
      }, 200);
    </script>
  </body>
</html>`);
}

app.get("/payment/airwallex-return", handleAlipayReturnPage);
app.get("/payment/alipay-return", handleAlipayReturnPage);

app.post("/api/big-events/:id/checkout/alipay", async (req, res) => {
  const eventId = Number(req.params.id);
  if (!Number.isFinite(eventId) || eventId <= 0) {
    return res.status(400).json({ message: "Invalid event id" });
  }
  return res.status(410).json({
    message: "Alipay has been removed. Please use PromptPay.",
  });
});

app.post("/api/big-events/:id/checkout/promptpay", async (req, res) => {
  const client = await pool.connect();
  try {
    if (!stripe) {
      return stripeUnavailableResponse(res);
    }
    await ensureBusinessReferenceColumns();
    const eventId = Number(req.params.id);
    const quantity = Number(req.body?.quantity);
    const qty = Number.isFinite(quantity) && quantity > 0 ? quantity : 1;
    const userCtx = getRequestUserId(req, { allowQuery: false, allowBody: true });
    if (!userCtx.ok) {
      return res.status(400).json({ message: userCtx.message });
    }
    const userId = userCtx.userId;
    const shirtSize = await normalizeBigEventShirtSizeOrThrow(client, {
      eventId,
      shirtSize: req.body?.shirt_size,
    });

    const payload = await loadEventPaymentMethods(client, eventId);
    if (!payload) {
      return res.status(404).json({ message: "Event not found" });
    }

    const promptpayMethod = payload.methods.find((m) => m.method_type === "PROMPTPAY");
    if (!promptpayMethod?.is_active) {
      return res.status(400).json({ message: "PromptPay is not enabled for this event" });
    }
    if (!isStripeBranchAllowed(payload.event)) {
      return res.status(400).json({ message: "Stripe payment is not enabled for this event" });
    }

    const promptpayAmount = Number(payload.event.promptpay_amount_thb ?? payload.event.fee ?? 0);
    const amount = promptpayAmount * qty;
    const currency = "thb";
    const bookingStatus = await pickEnumSafe(client, "bookings", "status", "pending");
    const paymentStatus = await pickEnumSafe(client, "payments", "status", "pending");

    await client.query("BEGIN");

    const existingPaidQ = await client.query(
      `
      SELECT p.id
      FROM payments p
      JOIN bookings b ON b.id = p.booking_id
      WHERE b.user_id = $1
        AND b.event_id = $2
        AND (
          p.paid_at IS NOT NULL
          OR LOWER(COALESCE(p.status::text, '')) IN ('paid', 'completed', 'success', 'succeeded', 'done')
          OR LOWER(COALESCE(b.status::text, '')) IN ('confirmed', 'paid', 'completed', 'success')
        )
      ORDER BY p.id DESC
      LIMIT 1
      `,
      [userId, eventId]
    );

    if (existingPaidQ.rowCount > 0) {
      await client.query("ROLLBACK");
      return res.status(409).json({ message: "User already joined this event" });
    }

    const bookingQ = await client.query(
      `
      INSERT INTO bookings (user_id, event_id, quantity, total_amount, currency, status, shirt_size, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
      RETURNING id
      `,
      [userId, eventId, qty, amount, currency.toUpperCase(), bookingStatus, shirtSize]
    );

    const bookingId = bookingQ.rows[0].id;
    const bookingReference = await ensureBookingReference(client, bookingId);
    const paymentQ = await client.query(
      `
      INSERT INTO payments
        (booking_id, user_id, event_id, method, method_type, provider, amount, currency, fx_rate_used, status, created_at, updated_at)
      VALUES
        ($1, $2, $3, 'promptpay', 'PROMPTPAY', 'STRIPE', $4, $5, $6, $7, NOW(), NOW())
      RETURNING id
      `,
      [bookingId, userId, eventId, amount, currency.toUpperCase(), Number(payload.event.exchange_rate_thb_per_cny ?? 0), paymentStatus]
    );

    const paymentId = paymentQ.rows[0].id;
    const paymentReference = await ensurePaymentReference(client, paymentId);
    const origin = `${req.protocol}://${req.get("host")}`;
    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["promptpay"],
      line_items: [
        {
          quantity: qty,
          price_data: {
            currency,
            unit_amount: Math.round(promptpayAmount * 100),
            product_data: { name: String(payload.event.title ?? `Event #${eventId}`) },
          },
        },
      ],
      metadata: {
        user_id: String(userId),
        event_id: String(eventId),
        booking_id: String(bookingId),
        payment_id: String(paymentId),
        quantity: String(qty),
        method_type: "PROMPTPAY",
        provider: "STRIPE",
        shirt_size: shirtSize ?? "",
      },
      success_url: `${origin}/paid-success`,
      cancel_url: `${origin}/paid-cancel`,
    });

    await client.query(
      `
      UPDATE payments
      SET stripe_checkout_session_id = $2, updated_at = NOW()
      WHERE id = $1
      `,
      [paymentId, session.id]
    );

    await client.query("COMMIT");
    return res.status(201).json({
      booking_id: bookingId,
      payment_id: paymentId,
      booking_reference: bookingReference,
      payment_reference: paymentReference,
      method_type: "PROMPTPAY",
      provider: "STRIPE",
      amount,
      currency: currency.toUpperCase(),
      status: paymentStatus,
      checkout_url: session.url,
      session_id: session.id,
    });
  } catch (err) {
    await client.query("ROLLBACK");
    if (Number.isFinite(Number(err?.statusCode)) && Number(err.statusCode) >= 400) {
      return res.status(Number(err.statusCode)).json({
        message: err.message,
        error: err.message,
      });
    }
    console.error("Create PromptPay checkout error:", err);
    return res.status(500).json({ message: "Server error", error: String(err?.message ?? err) });
  } finally {
    client.release();
  }
});

app.post("/api/payments/alipay/:paymentId/confirm", async (req, res) => {
  return res.status(410).json({
    message: "Alipay has been removed. Please use PromptPay.",
  });
});

app.post("/api/payments/alipay/:paymentId/confirm-legacy-disabled", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureBusinessReferenceColumns();
    const paymentId = Number(req.params.paymentId);
    const userCtx = getRequestUserId(req, { allowQuery: true, allowBody: true });
    if (!userCtx.ok) {
      return res.status(400).json({ message: userCtx.message, error: userCtx.message });
    }
    if (!Number.isFinite(paymentId) || paymentId <= 0) {
      return res.status(400).json({ message: "Invalid payment id" });
    }

    let row = await loadOwnedPaymentStatusRow(client, paymentId, userCtx.userId);
    if (!row) {
      return res.status(404).json({ message: "Payment not found" });
    }
    if (normalizeMethodType(row.method_type) !== "ALIPAY") {
      return res.status(400).json({ message: "Payment is not an Alipay payment" });
    }

    const provider = String(row.provider ?? "").trim().toLowerCase();
    if (provider === "airwallex_alipay") {
      if (hasProviderPaymentTimedOut(row)) {
        await client.query("BEGIN");
        await expireTimedOutAirwallexPayment(client, row);
        await client.query("COMMIT");
        row = await loadOwnedPaymentStatusRow(client, paymentId, userCtx.userId);
        return res.json(buildPaymentStatusResponse(req, row));
      }
      const providerPaymentIntentId = String(row.provider_payment_intent_id ?? "").trim();
      if (!providerPaymentIntentId) {
        return res.json(buildPaymentStatusResponse(req, row));
      }
      try {
        const intent = await airwallex.retrievePaymentIntent(providerPaymentIntentId);
        await client.query("BEGIN");
        const syncResult = await syncAirwallexPaymentRecord(client, row, intent);
        if (
          isPendingLikeLocalPaymentStatus(syncResult.status) &&
          hasProviderPaymentTimedOut(row)
        ) {
          await expireTimedOutAirwallexPayment(client, row);
        }
        await client.query("COMMIT");
      } catch (err) {
        try {
          await client.query("ROLLBACK");
        } catch (_) {}
        if (hasProviderPaymentTimedOut(row)) {
          await client.query("BEGIN");
          await expireTimedOutAirwallexPayment(client, row);
          await client.query("COMMIT");
          row = await loadOwnedPaymentStatusRow(client, paymentId, userCtx.userId);
          return res.json(buildPaymentStatusResponse(req, row));
        }
        console.error("[ALIPAY CONFIRM ERROR]", err);
        return res.status(500).json({
          message: "Could not confirm Alipay payment",
          error: String(err?.message ?? err),
        });
      }
      row = await loadOwnedPaymentStatusRow(client, paymentId, userCtx.userId);
      return res.json(buildPaymentStatusResponse(req, row));
    }

    return res.json(buildPaymentStatusResponse(req, row));
  } catch (err) {
    console.error("[ALIPAY CONFIRM ERROR]", err);
    return res.status(500).json({ message: "Server error", error: String(err?.message ?? err) });
  } finally {
    client.release();
  }
});

app.get("/api/payments/:paymentId", async (req, res) => {
  try {
    await ensureBusinessReferenceColumns();
    const paymentId = Number(req.params.paymentId);
    console.log("[PAYMENT STATUS]", paymentId);
    const userCtx = getRequestUserId(req, { allowQuery: true, allowBody: false });
    if (!userCtx.ok) {
      return res.status(400).json({ error: userCtx.message, message: userCtx.message });
    }
    const userId = userCtx.userId;

    if (!Number.isFinite(paymentId) || paymentId <= 0) {
      return res.status(400).json({ error: "invalid payment id", message: "Invalid payment id" });
    }

    const q = await pool.query(
      `
      SELECT
        p.id,
        p.booking_id,
        b.booking_reference,
        p.event_id,
        COALESCE(p.user_id, b.user_id) AS user_id,
        COALESCE(p.amount, 0) AS amount,
        COALESCE(p.currency::text, b.currency::text, e.currency::text, 'THB') AS currency,
        COALESCE(p.fx_rate_used, e.exchange_rate_thb_per_cny) AS fx_rate_used,
        COALESCE(
          NULLIF(TRIM(p.payment_method_type::text), ''),
          NULLIF(TRIM(p.method_type::text), ''),
          UPPER(COALESCE(p.method::text, ''))
        ) AS method_type,
        COALESCE(p.provider::text, '') AS provider,
        p.status::text AS status,
        p.paid_at,
        p.payment_reference,
        p.provider_txn_id,
        p.provider_charge_id,
        p.provider_payment_intent_id,
        p.stripe_payment_intent_id,
        p.stripe_checkout_session_id,
        p.failure_code,
        p.failure_reason,
        p.created_at,
        p.raw_gateway_payload,
        COALESCE(r.pdf_url, to_jsonb(p)->>'receipt_url') AS receipt_url,
        to_jsonb(p)->>'slip_url' AS slip_url,
        r.receipt_no,
        r.issue_date AS receipt_issue_date,
        e.title AS event_title
      FROM payments p
      LEFT JOIN bookings b ON b.id = p.booking_id
      LEFT JOIN events e ON e.id = COALESCE(p.event_id, b.event_id)
      LEFT JOIN LATERAL (
        SELECT r1.receipt_no, r1.issue_date, r1.pdf_url
        FROM receipts r1
        WHERE r1.payment_id = p.id
        ORDER BY r1.issue_date DESC NULLS LAST, r1.id DESC
        LIMIT 1
      ) r ON TRUE
      WHERE p.id = $1
        AND COALESCE(p.user_id, b.user_id) = $2
      LIMIT 1
      `,
      [paymentId, userId]
    );

    if (q.rowCount === 0) {
      return res.status(404).json({ error: "payment not found", message: "Payment not found" });
    }

    let row = q.rows[0];
    const provider = String(row.provider ?? "").trim().toLowerCase();
    const normalizedStatus = String(row.status ?? "").trim().toLowerCase();
    const stripeIntentId =
      String(
        row.provider_payment_intent_id ??
        row.stripe_payment_intent_id ??
        ""
      ).trim();
    const stripeCheckoutSessionId = String(row.stripe_checkout_session_id ?? "").trim();

    const shouldSyncStripeStatus =
      provider === "stripe" &&
      (stripeIntentId || stripeCheckoutSessionId) &&
      !["paid", "completed", "success", "succeeded", "done", "failed", "cancelled", "canceled"].includes(normalizedStatus);
    const shouldSyncAirwallexStatus =
      provider === "airwallex_alipay" &&
      stripeIntentId &&
      !["paid", "completed", "success", "succeeded", "done", "failed", "cancelled", "canceled"].includes(normalizedStatus);

    console.log("[PAYMENT STATUS] sync candidate", {
      paymentId,
      provider,
      status: normalizedStatus,
      stripeIntentId: stripeIntentId || null,
      stripeCheckoutSessionId: stripeCheckoutSessionId || null,
      shouldSyncStripeStatus,
    });

    if (shouldSyncStripeStatus && stripe) {
      try {
        let paymentIntent = null;
        let stripeStatus = "";
        let chargeId = null;
        let receiptUrl = null;

        if (stripeIntentId) {
          paymentIntent = await stripe.paymentIntents.retrieve(stripeIntentId);
          stripeStatus = String(paymentIntent?.status ?? "").trim().toLowerCase();
          chargeId =
            paymentIntent?.latest_charge != null
              ? String(paymentIntent.latest_charge)
              : null;
          receiptUrl = paymentIntent?.charges?.data?.[0]?.receipt_url ?? null;
        } else if (stripeCheckoutSessionId) {
          const session = await stripe.checkout.sessions.retrieve(
            stripeCheckoutSessionId,
            { expand: ["payment_intent"] }
          );
          console.log("[PAYMENT STATUS] checkout session retrieve", {
            paymentId,
            stripeCheckoutSessionId,
            sessionStatus: session?.status ?? null,
            paymentStatus: session?.payment_status ?? null,
          });
          paymentIntent = session?.payment_intent ?? null;
          stripeStatus =
            session?.payment_status === "paid" || session?.status === "complete"
              ? "succeeded"
              : String(session?.status ?? "").trim().toLowerCase();
          chargeId =
            paymentIntent?.latest_charge != null
              ? String(paymentIntent.latest_charge)
              : null;
        }

        if (stripeStatus === "succeeded") {
          const paidStatus = await pickEnumSafe(pool, "payments", "status", "paid");
          const confirmedStatus = await pickEnumSafe(pool, "bookings", "status", "confirmed");

          await pool.query(
            `
            UPDATE payments
            SET
              status = $2,
              provider = 'stripe',
              payment_reference = COALESCE(NULLIF(TRIM(payment_reference), ''), $8),
              provider_txn_id = COALESCE(provider_txn_id, $4, $3, $7),
              provider_payment_intent_id = COALESCE(provider_payment_intent_id, $3),
              stripe_payment_intent_id = COALESCE(stripe_payment_intent_id, $3),
              provider_charge_id = COALESCE(provider_charge_id, $4),
              stripe_charge_id = COALESCE(stripe_charge_id, $4),
              paid_at = COALESCE(paid_at, NOW()),
              receipt_url = COALESCE(receipt_url, $5),
              raw_gateway_payload = $6::jsonb,
              updated_at = NOW()
            WHERE id = $1
            `,
            [
              row.id,
              paidStatus,
              stripeIntentId,
              chargeId,
              receiptUrl,
              JSON.stringify(paymentIntent),
              stripeCheckoutSessionId || null,
              makeBusinessReference("PAY", row.id, row.paid_at ?? new Date()),
            ]
          );

          if (row.booking_id) {
            await pool.query(
              `
              UPDATE bookings
              SET status = $2, updated_at = NOW()
              WHERE id = $1
              `,
              [row.booking_id, confirmedStatus]
            );
          }

          await ensureReceiptForPayment(pool, {
            paymentId: row.id,
            amount: row.amount,
            currency: row.currency,
            receiptUrl,
          });
        } else if (["canceled", "cancelled", "payment_failed"].includes(stripeStatus)) {
          const failedStatus = await pickEnumSafe(
            pool,
            "payments",
            "status",
            stripeStatus === "canceled" || stripeStatus === "cancelled"
              ? "cancelled"
              : "failed"
          );

          await pool.query(
            `
            UPDATE payments
            SET
              status = $2,
              raw_gateway_payload = $3::jsonb,
              updated_at = NOW()
            WHERE id = $1
            `,
            [row.id, failedStatus, JSON.stringify(paymentIntent)]
          );
        }

        const refreshed = await pool.query(
          `
          SELECT
            p.id,
            p.booking_id,
            b.booking_reference,
            p.event_id,
            COALESCE(p.user_id, b.user_id) AS user_id,
            COALESCE(p.amount, 0) AS amount,
            COALESCE(p.currency::text, b.currency::text, e.currency::text, 'THB') AS currency,
            COALESCE(p.fx_rate_used, e.exchange_rate_thb_per_cny) AS fx_rate_used,
            COALESCE(
              NULLIF(TRIM(p.payment_method_type::text), ''),
              NULLIF(TRIM(p.method_type::text), ''),
              UPPER(COALESCE(p.method::text, ''))
            ) AS method_type,
            COALESCE(p.provider::text, '') AS provider,
            p.status::text AS status,
            p.paid_at,
            p.payment_reference,
            p.provider_txn_id,
            p.provider_charge_id,
            p.provider_payment_intent_id,
            p.stripe_payment_intent_id,
            p.failure_code,
            p.failure_reason,
            p.created_at,
            p.raw_gateway_payload,
            COALESCE(r.pdf_url, to_jsonb(p)->>'receipt_url') AS receipt_url,
            to_jsonb(p)->>'slip_url' AS slip_url,
            r.receipt_no,
            r.issue_date AS receipt_issue_date,
            e.title AS event_title
          FROM payments p
          LEFT JOIN bookings b ON b.id = p.booking_id
          LEFT JOIN events e ON e.id = COALESCE(p.event_id, b.event_id)
          LEFT JOIN LATERAL (
            SELECT r1.receipt_no, r1.issue_date, r1.pdf_url
            FROM receipts r1
            WHERE r1.payment_id = p.id
            ORDER BY r1.issue_date DESC NULLS LAST, r1.id DESC
            LIMIT 1
          ) r ON TRUE
          WHERE p.id = $1
            AND COALESCE(p.user_id, b.user_id) = $2
          LIMIT 1
          `,
          [paymentId, userId]
        );
        if (refreshed.rowCount > 0) {
          row = refreshed.rows[0];
        }
      } catch (stripeSyncErr) {
        console.error("[PAYMENT STATUS STRIPE SYNC ERROR]", stripeSyncErr);
      }
    } else if (shouldSyncAirwallexStatus) {
      try {
        const intent = await airwallex.retrievePaymentIntent(stripeIntentId);
        await pool.query("BEGIN");
        const syncResult = await syncAirwallexPaymentRecord(pool, row, intent);
        if (
          isPendingLikeLocalPaymentStatus(syncResult.status) &&
          hasProviderPaymentTimedOut(row)
        ) {
          await expireTimedOutAirwallexPayment(pool, row);
        }
        await pool.query("COMMIT");

        const refreshed = await pool.query(
          `
          SELECT
            p.id,
            p.booking_id,
            b.booking_reference,
            p.event_id,
            COALESCE(p.user_id, b.user_id) AS user_id,
            COALESCE(p.amount, 0) AS amount,
            COALESCE(p.currency::text, b.currency::text, e.currency::text, 'THB') AS currency,
            COALESCE(p.fx_rate_used, e.exchange_rate_thb_per_cny) AS fx_rate_used,
            COALESCE(
              NULLIF(TRIM(p.payment_method_type::text), ''),
              NULLIF(TRIM(p.method_type::text), ''),
              UPPER(COALESCE(p.method::text, ''))
            ) AS method_type,
            COALESCE(p.provider::text, '') AS provider,
            p.status::text AS status,
            p.paid_at,
            p.payment_reference,
            p.provider_txn_id,
            p.provider_charge_id,
            p.provider_payment_intent_id,
            p.stripe_payment_intent_id,
            p.failure_code,
            p.failure_reason,
            COALESCE(r.pdf_url, to_jsonb(p)->>'receipt_url') AS receipt_url,
            to_jsonb(p)->>'slip_url' AS slip_url,
            r.receipt_no,
            r.issue_date AS receipt_issue_date,
            e.title AS event_title
          FROM payments p
          LEFT JOIN bookings b ON b.id = p.booking_id
          LEFT JOIN events e ON e.id = COALESCE(p.event_id, b.event_id)
          LEFT JOIN LATERAL (
            SELECT r1.receipt_no, r1.issue_date, r1.pdf_url
            FROM receipts r1
            WHERE r1.payment_id = p.id
            ORDER BY r1.issue_date DESC NULLS LAST, r1.id DESC
            LIMIT 1
          ) r ON TRUE
          WHERE p.id = $1
            AND COALESCE(p.user_id, b.user_id) = $2
          LIMIT 1
          `,
          [paymentId, userId]
        );
        if (refreshed.rowCount > 0) {
          row = refreshed.rows[0];
        }
      } catch (airwallexSyncErr) {
        try {
          await pool.query("ROLLBACK");
        } catch (_) {}
        if (hasProviderPaymentTimedOut(row)) {
          await pool.query("BEGIN");
          await expireTimedOutAirwallexPayment(pool, row);
          await pool.query("COMMIT");
          const refreshedTimedOut = await loadOwnedPaymentStatusRow(
            pool,
            paymentId,
            userId
          );
          if (refreshedTimedOut) {
            row = refreshedTimedOut;
          }
        }
        console.error("[PAYMENT STATUS AIRWALLEX SYNC ERROR]", airwallexSyncErr);
      }
    } else if (hasProviderPaymentTimedOut(row)) {
      await pool.query("BEGIN");
      await expireTimedOutAirwallexPayment(pool, row);
      await pool.query("COMMIT");
      const refreshedTimedOut = await loadOwnedPaymentStatusRow(
        pool,
        paymentId,
        userId
      );
      if (refreshedTimedOut) {
        row = refreshedTimedOut;
      }
    }

    if (
      ["paid", "completed", "success", "succeeded", "done"].includes(
        normalizeLocalPaymentStatus(row.status)
      ) &&
      !String(row.receipt_no ?? "").trim()
    ) {
      await ensureReceiptForPayment(pool, {
        paymentId: row.id,
        amount: Number(row.amount ?? 0),
        currency: String(row.currency ?? "THB").toUpperCase(),
        receiptUrl: row.receipt_url ?? null,
      });

      const refreshedWithReceipt = await loadOwnedPaymentStatusRow(
        pool,
        paymentId,
        userId
      );
      if (refreshedWithReceipt) {
        row = refreshedWithReceipt;
      }
    }

    return res.json({
      paymentId: row.id,
      id: row.id,
      booking_id: row.booking_id,
      booking_reference: row.booking_reference,
      event_id: row.event_id,
      user_id: row.user_id,
      event_title: row.event_title,
      amount: Number(row.amount ?? 0),
      currency: String(row.currency ?? "THB").toUpperCase(),
      fx_rate_used: row.fx_rate_used == null ? null : Number(row.fx_rate_used),
      method_type: normalizeMethodType(row.method_type) || String(row.method_type ?? ""),
      provider: normalizeProvider(row.provider) || String(row.provider ?? ""),
      payment_reference: row.payment_reference,
      provider_txn_id:
        row.provider_txn_id ||
        row.provider_charge_id ||
        row.provider_payment_intent_id ||
        row.stripe_payment_intent_id ||
        null,
      failure_code: row.failure_code || null,
      failure_reason: row.failure_reason || null,
      timed_out: isTimedOutPaymentRow(row),
      status: row.status,
      paid_at: row.paid_at,
      receipt_no: row.receipt_no,
      receipt_issue_date: row.receipt_issue_date,
      receipt_url: toAbsoluteUrl(req, row.receipt_url),
      slip_url: toAbsoluteUrl(req, row.slip_url),
    });
  } catch (err) {
    console.error("[PAYMENT STATUS ERROR]", err);
    return res.status(500).json({ message: "Server error", error: String(err?.message ?? err) });
  }
});

/**
 * =====================================================
 * ✅ Create Booking for Big Event
 * POST /api/big-events/:id/bookings
 * body: { user_id, quantity }
 * return: { bookingId, amount, currency }
 * =====================================================
 */
app.post("/api/big-events/:id/bookings", async (req, res) => {
  try {
    const eventId = Number(req.params.id);
    const quantity = req.body?.quantity;
    const userCtx = getRequestUserId(req, { allowQuery: false, allowBody: true });
    if (!userCtx.ok) {
      return res.status(400).json({ message: userCtx.message });
    }
    const userId = userCtx.userId;

    const qty =
      Number.isFinite(Number(quantity)) && Number(quantity) > 0
        ? Number(quantity)
        : 1;
    let shirtSize = null;

    console.log("[join-big-event] request", { userId, eventId, quantity: qty });

    if (!Number.isFinite(eventId) || eventId <= 0) {
      return res.status(400).json({ message: "Invalid event id" });
    }

    if (!Number.isFinite(userId) || userId <= 0) {
      return res.status(400).json({ message: "Invalid user_id" });
    }

    // 1) อ่าน event + currency จาก DB
    const ev = await pool.query(
      `
      SELECT id, type, status,
             COALESCE(fee, 0)::numeric AS unit_price,
             currency
      FROM events
      WHERE id = $1
      LIMIT 1
      `,
      [eventId]
    );

    if (ev.rowCount === 0) {
      return res.status(404).json({ message: "Event not found" });
    }

    const e = ev.rows[0];

    if (String(e.type || "").toUpperCase() !== "BIG_EVENT") {
      return res.status(400).json({ message: "This event is not BIG_EVENT" });
    }

    if (String(e.status || "").toLowerCase() !== "published") {
      return res.status(400).json({ message: "Event is not published" });
    }

    shirtSize = await normalizeBigEventShirtSizeOrThrow(pool, {
      eventId,
      shirtSize: req.body?.shirt_size,
    });

    const unitPrice = Number(e.unit_price ?? 0);
    const currency = (e.currency ?? "THB").toString().toUpperCase();
    const amount = unitPrice * qty;

    const client = await pool.connect();

    try {
      await client.query("BEGIN");

      const dupQ = await client.query(
        `
        SELECT id, total_amount, currency, status
        FROM bookings
        WHERE user_id = $1
          AND event_id = $2
          AND LOWER(COALESCE(status::text, '')) NOT IN ('cancelled', 'canceled')
        ORDER BY id DESC
        LIMIT 1
        `,
        [userId, eventId]
      );

      if (dupQ.rowCount > 0) {
        if (shirtSize) {
          await client.query(
            `
            UPDATE bookings
            SET shirt_size = $2,
                updated_at = NOW()
            WHERE id = $1
            `,
            [dupQ.rows[0].id, shirtSize]
          );
        }
        await client.query("COMMIT");
        const existing = dupQ.rows[0];
        const bookingReference = await ensureBookingReference(pool, existing.id);
        console.log("[join-big-event] existing-booking", {
          userId,
          eventId,
          bookingId: existing.id,
          status: existing.status,
        });
        return res.status(200).json({
          message: "Booking already exists for this user and event",
          existing: true,
          bookingId: existing.id,
          booking_reference: bookingReference,
          amount: Number(existing.total_amount ?? amount),
          currency: (existing.currency ?? currency).toString().toUpperCase(),
          status: existing.status ?? null,
        });
      }

      const bookingStatus = await pickEnumSafe(
        client,
        "bookings",
        "status",
        "awaiting_payment"
      );

      const ins = await client.query(
        `
        INSERT INTO bookings
          (user_id, event_id, quantity, total_amount, currency, status, shirt_size, created_at, updated_at)
        VALUES
          ($1, $2, $3, $4, $5, $6, $7, NOW(), NOW())
        RETURNING id, total_amount, currency
        `,
        [userId, eventId, qty, amount, currency, bookingStatus, shirtSize]
      );

      const bookingReference = await ensureBookingReference(client, ins.rows[0].id);

      await client.query("COMMIT");
      console.log("[join-big-event] inserted", { userId, eventId, bookingId: ins.rows[0].id });

      return res.status(201).json({
        bookingId: ins.rows[0].id,
        booking_reference: bookingReference,
        amount: Number(ins.rows[0].total_amount),
        currency: ins.rows[0].currency,
        status: bookingStatus,
      });
    } catch (dbErr) {
      await client.query("ROLLBACK");

      console.error("❌ Create booking DB error:", dbErr);
      console.error("MESSAGE:", dbErr.message);
      console.error("DETAIL:", dbErr.detail);

      // ✅ ส่ง error detail กลับไปให้ Flutter เห็น จะได้แก้ตรงจุด
      return res.status(500).json({
        message: "DB error",
        error: dbErr.message,
        detail: dbErr.detail,
        constraint: dbErr.constraint,
        code: dbErr.code,
      });
    } finally {
      client.release();
    }
  } catch (e) {
    console.error("❌ POST /api/big-events/:id/bookings error:", e);
    return res.status(500).json({
      message: "Server error",
      error: String(e?.message ?? e),
    });
  }
});

/**
 * =====================================================
 * ✅ Simple pages for success/cancel (กัน 404)
 * =====================================================
 */
/**
 * =====================================================
 * Upload payment slip + mark payment/booking status
 * POST /api/bookings/:bookingId/payment-slip
 * form-data: file, payment_method?
 * =====================================================
 */
app.post("/api/bookings/:bookingId/payment-slip", async (req, res) => {
  try {
    await new Promise((resolve, reject) => {
      upload.single("file")(req, res, (err) => {
        if (err) return reject(err);
        resolve();
      });
    });
  } catch (uploadErr) {
    console.error("Payment slip upload middleware error:", uploadErr);
    return res.status(400).json({
      message: "Upload failed",
      error: uploadErr?.message || String(uploadErr),
    });
  }

  const bookingId = Number(req.params.bookingId);
  const userCtx = getRequestUserId(req, { allowQuery: false, allowBody: true });
  if (!userCtx.ok) {
    return res.status(400).json({ message: userCtx.message });
  }
  const userId = userCtx.userId;
  if (!Number.isFinite(bookingId) || bookingId <= 0) {
    return res.status(400).json({ message: "Invalid bookingId" });
  }
  if (!req.file) {
    return res.status(400).json({ message: "No file uploaded" });
  }

  try {
    await ensurePaymentSlipColumn();
    await ensureBusinessReferenceColumns();
    const client = await pool.connect();
    try {
      await client.query("BEGIN");

      const bookingQ = await client.query(
        `
        SELECT b.id, b.user_id, b.event_id, b.total_amount, b.currency, e.exchange_rate_thb_per_cny
        FROM bookings b
        LEFT JOIN events e ON e.id = b.event_id
        WHERE b.id = $1 AND b.user_id = $2
        LIMIT 1
        `,
        [bookingId, userId]
      );

      if (bookingQ.rowCount === 0) {
        await client.query("ROLLBACK");
        return res.status(404).json({ message: "Booking not found for this user" });
      }

      const booking = bookingQ.rows[0];
      const amount = Number(booking.total_amount ?? 0);
      const paymentMethodRaw = (req.body?.payment_method ?? "promptpay").toString().trim();
      const slipPath = `/uploads/${req.file.filename}`;

      const reviewStatus = await pickEnumSafe(client, "payments", "status", "awaiting_manual_review");
      const awaitingPaymentStatus = await pickEnumSafe(client, "bookings", "status", "awaiting_payment");
      const paymentMethod = await pickEnumSafe(client, "payments", "method", paymentMethodRaw);
      const paymentMethodType = normalizePaymentMethodKey(paymentMethodRaw) || "promptpay";

      const existingPaymentQ = await client.query(
        `
        SELECT id
        FROM payments
        WHERE booking_id = $1
        ORDER BY id DESC
        LIMIT 1
        `,
        [bookingId]
      );

      let paymentId;
      const providerTxnId = `SLIP-${bookingId}-${Date.now()}`;
      if (existingPaymentQ.rowCount > 0) {
        paymentId = existingPaymentQ.rows[0].id;
        await client.query(
          `
          UPDATE payments
          SET
            method = COALESCE($2, method),
            payment_method_type = COALESCE($3, payment_method_type),
            method_type = COALESCE(UPPER($3), method_type),
            amount = CASE WHEN amount IS NULL OR amount = 0 THEN $4 ELSE amount END,
            currency = COALESCE(currency, $8),
            fx_rate_used = COALESCE(fx_rate_used, $9),
            status = $5,
            paid_at = NULL,
            provider = 'manual_qr',
            provider_txn_id = COALESCE(provider_txn_id, $6),
            slip_url = $7,
            updated_at = NOW()
          WHERE id = $1
          `,
          [paymentId, paymentMethod, paymentMethodType, amount, reviewStatus, providerTxnId, slipPath, String(booking.currency ?? "THB").toUpperCase(), Number(booking.exchange_rate_thb_per_cny ?? 0)]
        );
      } else {
        const paymentIns = await client.query(
          `
          INSERT INTO payments
            (booking_id, method, method_type, payment_method_type, provider, provider_txn_id, amount, currency, fx_rate_used, status, paid_at, slip_url, created_at, updated_at)
          VALUES
            ($1, $2, UPPER($3), $3, 'manual_qr', $4, $5, $6, $7, $8, NULL, $9, NOW(), NOW())
          RETURNING id
          `,
          [bookingId, paymentMethod, paymentMethodType, providerTxnId, amount, String(booking.currency ?? "THB").toUpperCase(), Number(booking.exchange_rate_thb_per_cny ?? 0), reviewStatus, slipPath]
        );
        paymentId = paymentIns.rows[0].id;
      }

      const bookingReference = await ensureBookingReference(client, bookingId);
      const paymentReference = await ensurePaymentReference(client, paymentId);

      await client.query(
        `
        UPDATE bookings
        SET status = $2, updated_at = NOW()
        WHERE id = $1
        `,
        [bookingId, awaitingPaymentStatus]
      );

      await insertAuditLog(client, {
        userId: booking.user_id,
        actorType: "user",
        action: "PAYMENT_SLIP_UPLOADED",
        entityTable: "payments",
        entityId: paymentId,
        metadata: {
          booking_id: bookingId,
          booking_reference: bookingReference,
          payment_reference: paymentReference,
          payment_method_type: paymentMethodType,
          provider: "manual_qr",
          changed_fields: ["status", "provider_txn_id", "slip_url"],
          new_values: {
            status: reviewStatus ?? null,
            provider_txn_id: providerTxnId,
            slip_url: slipPath,
          },
        },
      });

      await client.query("COMMIT");

      const host = `${req.protocol}://${req.get("host")}`;
      return res.status(200).json({
        message: "Payment slip uploaded successfully",
        booking_id: bookingId,
        event_id: booking.event_id,
        user_id: booking.user_id,
        payment_id: paymentId,
        booking_reference: bookingReference,
        payment_reference: paymentReference,
        payment_status: reviewStatus ?? null,
        booking_status: awaitingPaymentStatus ?? null,
        slip_url: `${host}${slipPath}`,
      });
    } catch (dbErr) {
      await client.query("ROLLBACK");
      console.error("Upload payment slip DB error:", dbErr);
      return res.status(500).json({
        message: "DB error",
        error: dbErr.message,
      });
    } finally {
      client.release();
    }
  } catch (e) {
    console.error("Upload payment slip error:", e);
    return res.status(500).json({
      message: "Server error",
      error: String(e?.message ?? e),
    });
  }
});

/**
 * =====================================================
 * Get joined paid big events for user
 * GET /api/user/joined-events?user_id=<current_user_id>
 * =====================================================
 */
app.get("/api/user/joined-events", async (req, res) => {
  try {
    await ensureBusinessReferenceColumns();
    await ensureBigEventShirtSizeColumns();
    const userCtx = getRequestUserId(req, { allowQuery: true, allowBody: false });
    if (!userCtx.ok) {
      return res.status(400).json({ message: userCtx.message });
    }
    const userId = userCtx.userId;
    console.log("[joined-events] request", {
      userId,
      headerUserId: req.headers["x-user-id"] ?? null,
      queryUserId: req.query?.user_id ?? null,
    });

    const q = await pool.query(
      `
      SELECT
        e.id,
        e.title,
        e.description,
        e.start_at,
        e.meeting_point,
        e.city,
        e.province,
        e.display_code,
        e.distance_per_lap,
        e.number_of_laps,
        COALESCE(e.total_distance, 0) AS total_distance,
        e.updated_at AS event_updated_at,
        e.fee,
        o.name AS organization_name,
        b.id AS booking_id,
        b.booking_reference,
        b.status AS booking_status,
        b.shirt_size,
        b.completed_at,
        b.completed_distance_km,
        p.id AS payment_id,
        p.payment_reference,
        p.method AS payment_method,
        COALESCE(p.currency::text, b.currency::text, e.currency::text, 'THB') AS currency,
        COALESCE(
          NULLIF(TRIM(p.payment_method_type::text), ''),
          NULLIF(TRIM(p.method_type::text), ''),
          NULLIF(TRIM(p.method::text), '')
        ) AS payment_method_type,
        p.provider AS payment_provider,
        COALESCE(p.provider_txn_id, p.provider_charge_id, p.provider_payment_intent_id, p.stripe_payment_intent_id) AS provider_txn_id,
        p.status AS payment_status,
        p.paid_at,
        p.amount AS payment_amount,
        COALESCE(rc.pdf_url, to_jsonb(p)->>'receipt_url') AS receipt_url,
        p.slip_url,
        rc.receipt_no,
        rc.issue_date AS receipt_issue_date,
        COALESCE(
          (
            SELECT em.file_url
            FROM event_media em
            WHERE em.event_id = e.id AND em.kind = 'cover'
            ORDER BY em.sort_order ASC NULLS LAST, em.id DESC
            LIMIT 1
          ),
          (
            SELECT em.file_url
            FROM event_media em
            WHERE em.event_id = e.id AND em.kind = 'gallery'
            ORDER BY em.sort_order ASC NULLS LAST, em.id ASC
            LIMIT 1
          )
        ) AS cover_url,
        b.created_at AS booking_created_at
      FROM bookings b
      JOIN events e ON e.id = b.event_id
      LEFT JOIN organizations o ON o.id = e.organization_id
      LEFT JOIN LATERAL (
        SELECT p1.*
        FROM payments p1
        WHERE p1.booking_id = b.id
        ORDER BY p1.paid_at DESC NULLS LAST, p1.id DESC
        LIMIT 1
      ) p ON TRUE
      LEFT JOIN LATERAL (
        SELECT r1.receipt_no, r1.issue_date, r1.pdf_url
        FROM receipts r1
        WHERE r1.payment_id = p.id
        ORDER BY r1.issue_date DESC NULLS LAST, r1.id DESC
        LIMIT 1
      ) rc ON TRUE
      WHERE
        b.user_id = $1
        AND UPPER(COALESCE(e.type::text, '')) = 'BIG_EVENT'
        AND (
          p.paid_at IS NOT NULL
          OR LOWER(COALESCE(p.status::text, '')) IN ('paid', 'completed', 'success', 'succeeded', 'done')
          OR LOWER(COALESCE(b.status::text, '')) IN ('confirmed', 'paid', 'completed', 'success')
        )
      ORDER BY COALESCE(p.paid_at, b.created_at) DESC NULLS LAST, b.id DESC
      `,
      [userId]
    );

    for (const row of q.rows) {
      if (
        Number.isFinite(Number(row.payment_id)) &&
        Number(row.payment_id) > 0 &&
        ["paid", "completed", "success", "succeeded", "done"].includes(
          normalizeLocalPaymentStatus(row.payment_status)
        ) &&
        !String(row.receipt_no ?? "").trim()
      ) {
        await ensureReceiptForPayment(pool, {
          paymentId: Number(row.payment_id),
          amount: Number(row.payment_amount ?? 0),
          currency: String(row.currency ?? "THB").toUpperCase(),
          receiptUrl: row.receipt_url ?? null,
        });
      }
    }

    const refreshedQ = await pool.query(
      `
      SELECT
        e.id,
        e.title,
        e.description,
        e.start_at,
        e.meeting_point,
        e.city,
        e.province,
        e.display_code,
        e.distance_per_lap,
        e.number_of_laps,
        COALESCE(e.total_distance, 0) AS total_distance,
        e.updated_at AS event_updated_at,
        e.fee,
        o.name AS organization_name,
        b.id AS booking_id,
        b.booking_reference,
        b.status AS booking_status,
        b.shirt_size,
        b.completed_at,
        b.completed_distance_km,
        p.id AS payment_id,
        p.payment_reference,
        p.method AS payment_method,
        COALESCE(p.currency::text, b.currency::text, e.currency::text, 'THB') AS currency,
        COALESCE(
          NULLIF(TRIM(p.payment_method_type::text), ''),
          NULLIF(TRIM(p.method_type::text), ''),
          NULLIF(TRIM(p.method::text), '')
        ) AS payment_method_type,
        p.provider AS payment_provider,
        COALESCE(p.provider_txn_id, p.provider_charge_id, p.provider_payment_intent_id, p.stripe_payment_intent_id) AS provider_txn_id,
        p.status AS payment_status,
        p.paid_at,
        p.amount AS payment_amount,
        COALESCE(rc.pdf_url, to_jsonb(p)->>'receipt_url') AS receipt_url,
        p.slip_url,
        rc.receipt_no,
        rc.issue_date AS receipt_issue_date,
        COALESCE(
          (
            SELECT em.file_url
            FROM event_media em
            WHERE em.event_id = e.id AND em.kind = 'cover'
            ORDER BY em.sort_order ASC NULLS LAST, em.id DESC
            LIMIT 1
          ),
          (
            SELECT em.file_url
            FROM event_media em
            WHERE em.event_id = e.id AND em.kind = 'gallery'
            ORDER BY em.sort_order ASC NULLS LAST, em.id ASC
            LIMIT 1
          )
        ) AS cover_url,
        b.created_at AS booking_created_at
      FROM bookings b
      JOIN events e ON e.id = b.event_id
      LEFT JOIN organizations o ON o.id = e.organization_id
      LEFT JOIN LATERAL (
        SELECT p1.*
        FROM payments p1
        WHERE p1.booking_id = b.id
        ORDER BY p1.paid_at DESC NULLS LAST, p1.id DESC
        LIMIT 1
      ) p ON TRUE
      LEFT JOIN LATERAL (
        SELECT r1.receipt_no, r1.issue_date, r1.pdf_url
        FROM receipts r1
        WHERE r1.payment_id = p.id
        ORDER BY r1.issue_date DESC NULLS LAST, r1.id DESC
        LIMIT 1
      ) rc ON TRUE
      WHERE
        b.user_id = $1
        AND UPPER(COALESCE(e.type::text, '')) = 'BIG_EVENT'
        AND (
          p.paid_at IS NOT NULL
          OR LOWER(COALESCE(p.status::text, '')) IN ('paid', 'completed', 'success', 'succeeded', 'done')
          OR LOWER(COALESCE(b.status::text, '')) IN ('confirmed', 'paid', 'completed', 'success')
        )
      ORDER BY COALESCE(p.paid_at, b.created_at) DESC NULLS LAST, b.id DESC
      `,
      [userId]
    );

    console.log("[joined-events] result", { userId, rowCount: refreshedQ.rowCount });
    const host = `${req.protocol}://${req.get("host")}`;
    const rows = refreshedQ.rows.map((r) => ({
      ...r,
      status: "paid",
      cover_url: r.cover_url
        ? (r.cover_url.startsWith("http")
            ? r.cover_url
            : `${host}${r.cover_url.startsWith("/") ? "" : "/"}${r.cover_url}`)
        : null,
      slip_url: r.slip_url
        ? (r.slip_url.startsWith("http")
            ? r.slip_url
            : `${host}${r.slip_url.startsWith("/") ? "" : "/"}${r.slip_url}`)
        : null,
      receipt_url: r.receipt_url
        ? (r.receipt_url.startsWith("http")
            ? r.receipt_url
            : `${host}${r.receipt_url.startsWith("/") ? "" : "/"}${r.receipt_url}`)
        : null,
    }));

    return res.json(rows);
  } catch (e) {
    console.error("Get joined events error:", e);
    return res.status(500).json({
      message: "Server error",
      error: String(e?.message ?? e),
    });
  }
});

async function handleJoinedBigEventComplete(req, res) {
  const client = await pool.connect();
  try {
    await ensureBusinessReferenceColumns();
    await ensureSpotSubsystemTables();

    const bookingId = Number(req.params.bookingId);
    if (!Number.isFinite(bookingId) || bookingId <= 0) {
      return res.status(400).json({ message: "Invalid booking id" });
    }

    const userCtx = getRequestUserId(req, { allowQuery: false, allowBody: true });
    if (!userCtx.ok) {
      return res.status(400).json({ message: userCtx.message });
    }

    const bookingQ = await client.query(
      `
      SELECT b.id, b.user_id, b.event_id, e.total_distance, e.type
      FROM public.bookings b
      JOIN public.events e ON e.id = b.event_id
      WHERE b.id = $1
      LIMIT 1
      `,
      [bookingId]
    );
    if (bookingQ.rowCount === 0) {
      return res.status(404).json({ message: "Booking not found" });
    }

    const booking = bookingQ.rows[0];
    if (Number(booking.user_id) !== Number(userCtx.userId)) {
      return res.status(403).json({ message: "Forbidden" });
    }
    if (String(booking.type ?? "").toUpperCase() !== "BIG_EVENT") {
      return res.status(400).json({ message: "Booking is not a Big Event booking" });
    }

    const completedDistanceKm = Number(booking.total_distance ?? 0);
    if (completedDistanceKm < 0) {
      return res.status(400).json({ message: "distance_km must be non-negative" });
    }

    const updatedQ = await client.query(
      `
      UPDATE public.bookings
      SET
        completed_at = COALESCE($2::timestamptz, NOW()),
        completed_distance_km = $3,
        updated_at = NOW()
      WHERE id = $1
      RETURNING id, event_id, completed_at, completed_distance_km, status
      `,
      [bookingId, req.body?.completed_at ?? null, completedDistanceKm]
    );

    return res.json({
      ok: true,
      completed: true,
      booking_id: bookingId,
      event_id: Number(updatedQ.rows[0]?.event_id ?? booking.event_id),
      completed_at: updatedQ.rows[0]?.completed_at ?? null,
      completed_distance_km:
        Number(updatedQ.rows[0]?.completed_distance_km ?? completedDistanceKm),
      status: String(updatedQ.rows[0]?.status ?? "completed"),
    });
  } catch (e) {
    console.error("Complete joined big event error:", e);
    return res.status(500).json({
      message: "Server error",
      error: String(e?.message ?? e),
    });
  } finally {
    client.release();
  }
}

app.post("/api/user/joined-events/:bookingId/complete", handleJoinedBigEventComplete);
app.patch("/api/user/joined-events/:bookingId/complete", handleJoinedBigEventComplete);

app.get("/paid-success", (_, res) => {
  res.send("Payment success. You can close this page.");
});

app.get("/paid-cancel", (_, res) => {
  res.send("Payment cancelled. You can close this page.");
});
/**
 * =====================================================
 * ✅ Simple pages for success/cancel (กัน 404)
 * =====================================================
 */
app.get("/paid-success", (_, res) => {
  res.send("Payment success. You can close this page.");
});

app.get("/paid-cancel", (_, res) => {
  res.send("Payment cancelled. You can close this page.");
});

/**
 * =====================================================
 * ✅ Create Stripe Checkout Session
 * POST /api/stripe/checkout-session
 * =====================================================
 */
app.post("/api/stripe/checkout-session", async (req, res) => {
  try {
    if (!stripe) {
      return stripeUnavailableResponse(res);
    }
    const { event_id, quantity } = req.body ?? {};
    const userCtx = getRequestUserId(req, { allowQuery: false, allowBody: true });
    if (!userCtx.ok) {
      return res.status(400).json({ message: userCtx.message });
    }
    const userId = userCtx.userId;
    const eventId = Number(event_id);
    const qty = Number.isFinite(Number(quantity)) && Number(quantity) > 0 ? Number(quantity) : 1;

    if (!userId || !eventId) {
      return res.status(400).json({ message: "user_id and event_id required" });
    }

    const title = `Event #${eventId}`;
    const amountThb = 100;

    const session = await stripe.checkout.sessions.create({
      mode: "payment",
      payment_method_types: ["card"],
      line_items: [
        {
          quantity: qty,
          price_data: {
            currency: "thb",
            unit_amount: Math.round(amountThb * 100),
            product_data: { name: title },
          },
        },
      ],
      metadata: {
        user_id: String(userId),
        event_id: String(eventId),
        quantity: String(qty),
      },
      success_url: "http://localhost:3000/paid-success",
      cancel_url: "http://localhost:3000/paid-cancel",
    });

    return res.json({ checkout_url: session.url, session_id: session.id });
  } catch (e) {
    console.error("Create checkout session error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

/**
 * =====================================================
 * ✅ Upload setup (ONE TIME ONLY)
 * =====================================================
 */
const uploadDir = path.join(__dirname, "uploads");
if (!fs.existsSync(uploadDir)) fs.mkdirSync(uploadDir, { recursive: true });

const qrUploadDir = path.join(uploadDir, "qr");
if (!fs.existsSync(qrUploadDir)) fs.mkdirSync(qrUploadDir, { recursive: true });

const authUploadDir = path.join(uploadDir, "users");
if (!fs.existsSync(authUploadDir)) fs.mkdirSync(authUploadDir, { recursive: true });

app.use("/uploads", express.static(uploadDir));

const storage = multer.diskStorage({
  destination: (_, __, cb) => cb(null, uploadDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || ".png";
    const isOrg = (req.originalUrl || "").includes("/api/upload/org-image");
    const prefix = isOrg ? "org" : "event";
    cb(null, `${prefix}_${Date.now()}_${Math.random().toString(16).slice(2)}${ext}`);
  },
});

// ✅ สำคัญ: ต้องมีบรรทัดนี้ ไม่งั้น upload.* ใช้ไม่ได้
const upload = multer({ storage });

const qrStorage = multer.diskStorage({
  destination: (_, __, cb) => cb(null, qrUploadDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || ".png";
    const eventId = req.params.id || "unknown";
    cb(null, `qr_event_${eventId}_${Date.now()}${ext}`);
  },
});

const uploadQR = multer({
  storage: qrStorage,
  limits: { fileSize: 5 * 1024 * 1024 },
  fileFilter: (req, file, cb) => {
    const allowedMimes = new Set([
      "image/jpeg",
      "image/jpg",
      "image/png",
      "image/gif",
      "image/webp",
    ]);
    const allowedExts = new Set([".jpg", ".jpeg", ".png", ".gif", ".webp"]);

    const mime = (file.mimetype || "").toLowerCase();
    const ext = path.extname(file.originalname || "").toLowerCase();

    if (allowedMimes.has(mime) || allowedExts.has(ext)) {
      cb(null, true);
    } else {
      cb(new Error("Only image files allowed (jpg, jpeg, png, gif, webp)"));
    }
  },
});

const authStorage = multer.diskStorage({
  destination: (_, __, cb) => cb(null, authUploadDir),
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname) || ".png";
    const field = (file.fieldname || "file").toLowerCase();
    const prefix = field.includes("national") ? "national_id" : "profile";
    cb(null, `${prefix}_${Date.now()}_${Math.random().toString(16).slice(2)}${ext}`);
  },
});

const uploadAuthImages = multer({
  storage: authStorage,
  limits: { fileSize: 8 * 1024 * 1024 },
});

/**
 * =====================================================
 * ✅ Upload Organization Image
 * POST /api/upload/org-image  (form-data: file)
 * =====================================================
 */
app.post("/api/upload/org-image", upload.single("file"), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ message: "No file uploaded" });

    const fileUrl = `${req.protocol}://${req.get("host")}/uploads/${req.file.filename}`;
    return res.status(201).json({ image_url: fileUrl });
  } catch (e) {
    console.error("Upload org image error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

/**
 * =====================================================
 * ✅ Health
 * =====================================================
 */
app.get("/api/health", (_, res) => res.json({ ok: true }));

/**
 * =====================================================
 * ✅ Admin Login
 * =====================================================
 */
app.post("/api/admin/login", async (req, res) => {
  try {
    const { email, password } = req.body ?? {};

    if (typeof email !== "string" || typeof password !== "string" || !email.trim() || !password) {
      return res.status(400).json({ message: "email and password required" });
    }

    const emailNorm = email.trim().toLowerCase();
    const q = await pool.query(
      `
      SELECT id, email, password_hash, status, created_at, last_login_at
      FROM public.admin_users
      WHERE LOWER(email) = $1
      ORDER BY id DESC
      `,
      [emailNorm]
    );

    if (q.rowCount === 0) return res.status(401).json({ message: "Invalid credentials" });

    let admin = null;
    let matchedInactive = false;

    for (const candidate of q.rows) {
      const storedHash = String(candidate.password_hash || "");
      let ok = false;

      if (storedHash) {
        try {
          ok = await bcrypt.compare(password, storedHash);
        } catch (_) {
          ok = false;
        }
      }

      if (!ok) {
        const legacyCheck = await pool.query(
          `
          SELECT (password_hash = crypt($1, password_hash)) AS ok
          FROM public.admin_users
          WHERE id = $2
          LIMIT 1
          `,
          [password, candidate.id]
        );
        ok = legacyCheck.rowCount > 0 && legacyCheck.rows[0].ok === true;
      }

      // Compatibility: allow direct match for legacy plain-text rows.
      if (!ok && storedHash) {
        ok = storedHash === password;
      }

      if (!ok) continue;

      if (candidate.status && candidate.status !== "active") {
        matchedInactive = true;
        continue;
      }

      admin = candidate;
      break;
    }

    if (!admin) {
      if (matchedInactive) return res.status(403).json({ message: "Account not active" });
      return res.status(401).json({ message: "Invalid credentials" });
    }

    const updated = await pool.query(
      `
      UPDATE public.admin_users
      SET last_login_at = NOW()
      WHERE id = $1
      RETURNING id, email, status, created_at, last_login_at
      `,
      [admin.id]
    );

    await insertAuditLog(pool, {
      adminUserId: admin.id,
      actorType: "admin",
      action: "LOGIN",
      entityTable: "admin_users",
      entityId: admin.id,
      metadata: {
        admin_email: admin.email ?? null,
      },
    });

    return res.json({ admin: updated.rowCount > 0 ? updated.rows[0] : admin });
  } catch (e) {
    console.error("Login error:", e);
    return res.status(500).json({ message: "Server error" });
  }
});

app.post("/api/admin/logout", async (req, res) => {
  try {
    const adminCtx = await tryGetActiveAdmin(req, {
      allowQuery: true,
      allowBody: true,
    });

    if (!adminCtx) {
      return res.status(401).json({ message: "Admin authentication required" });
    }

    await insertAuditLog(pool, {
      adminUserId: adminCtx.adminId,
      actorType: "admin",
      action: "LOGOUT",
      entityTable: "admin_users",
      entityId: adminCtx.adminId,
      metadata: {
        admin_email: adminCtx.email ?? null,
      },
    });

    return res.json({ ok: true });
  } catch (e) {
    console.error("Admin logout error:", e);
    return res.status(500).json({ message: "Server error" });
  }
});

/**
 * =====================================================
 * ✅ Organizations APIs (รองรับ image_url)
 * =====================================================
 */
/**
 * =====================================================
 * User Auth: Signup (User only)
 * POST /api/auth/signup
 * Accepts multipart form-data (profileImage, nationalIdImage) or text URLs.
 * =====================================================
 */
app.post(
  "/api/auth/signup",
  uploadAuthImages.fields([
    { name: "profileImage", maxCount: 1 },
    { name: "nationalIdImage", maxCount: 1 },
  ]),
  async (req, res) => {
    try {
      await ensureUserAuthColumns();

      const name = (req.body?.name ?? "").toString().trim();
      const birthYearText = (req.body?.birthYear ?? "").toString().trim();
      const birthYear = Number.parseInt(birthYearText, 10);
      const gender = (req.body?.gender ?? "").toString().trim();
      const occupation = (req.body?.occupation ?? "").toString().trim();
      const email = (req.body?.email ?? "").toString().trim().toLowerCase();
      const phone = (req.body?.phone ?? "").toString().trim();
      const address = (req.body?.address ?? "").toString().trim();
      const addressHouseNo = (req.body?.addressHouseNo ?? "").toString().trim();
      const addressFloor = (req.body?.addressFloor ?? "").toString().trim();
      const addressBuilding = (req.body?.addressBuilding ?? "").toString().trim();
      const addressRoad = (req.body?.addressRoad ?? "").toString().trim();
      const addressSubdistrict = (req.body?.addressSubdistrict ?? "").toString().trim();
      const addressDistrict = (req.body?.addressDistrict ?? "").toString().trim();
      const addressProvince = (req.body?.addressProvince ?? "").toString().trim();
      const addressPostalCode = (req.body?.addressPostalCode ?? "").toString().trim();
      const nameI18nRaw = (req.body?.nameI18n ?? "").toString().trim();
      const genderI18nRaw = (req.body?.genderI18n ?? "").toString().trim();
      const occupationI18nRaw = (req.body?.occupationI18n ?? "").toString().trim();
      const addressI18nRaw = (req.body?.addressI18n ?? "").toString().trim();
      const password = (req.body?.password ?? "").toString();

      const profileFile = req.files?.profileImage?.[0];
      const nationalIdFile = req.files?.nationalIdImage?.[0];
      const host = `${req.protocol}://${req.get("host")}`;

      const profileImageUrl = profileFile
        ? `${host}/uploads/users/${profileFile.filename}`
        : (req.body?.profileImage ?? "").toString().trim();
      const nationalIdImageUrl = nationalIdFile
        ? `${host}/uploads/users/${nationalIdFile.filename}`
        : (req.body?.nationalIdImage ?? "").toString().trim();

      if (!name || !birthYearText || !gender || !occupation || !email || !phone || !address || !addressHouseNo || !addressFloor || !addressBuilding || !addressRoad || !addressSubdistrict || !addressDistrict || !addressProvince || !addressPostalCode || !password || !profileImageUrl || !nationalIdImageUrl) {
        return res.status(400).json({ message: "name, birthYear, gender, occupation, email, phone, address, addressHouseNo, addressFloor, addressBuilding, addressRoad, addressSubdistrict, addressDistrict, addressProvince, addressPostalCode, password, profileImage, nationalIdImage are required" });
      }

      const currentYear = new Date().getFullYear();
      if (!Number.isInteger(birthYear) || birthYear < 1900 || birthYear > currentYear) {
        return res.status(400).json({ message: "Invalid birthYear" });
      }

      if (!isValidEmail(email)) {
        return res.status(400).json({ message: "Invalid email format" });
      }

      if (password.length < 8) {
        return res.status(400).json({ message: "Password must be at least 8 characters" });
      }

      const existed = await pool.query(
        `SELECT id FROM public.users WHERE LOWER(email) = $1 LIMIT 1`,
        [email]
      );
      if (existed.rowCount > 0) {
        return res.status(409).json({ message: "Email already exists" });
      }

      const { firstName, lastName } = splitNameParts(name);
      const passwordHash = await bcrypt.hash(password, 10);
      const parseI18nPayload = (rawValue, fallbackValue) => {
        if (!rawValue) {
          return {
            th: fallbackValue,
            en: fallbackValue,
            zh: fallbackValue,
          };
        }
        try {
          const parsed = JSON.parse(rawValue);
          if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
            throw new Error("invalid");
          }
          return {
            th: String(parsed.th ?? fallbackValue).trim() || fallbackValue,
            en: String(parsed.en ?? fallbackValue).trim() || fallbackValue,
            zh: String(parsed.zh ?? fallbackValue).trim() || fallbackValue,
          };
        } catch (_) {
          return {
            th: fallbackValue,
            en: fallbackValue,
            zh: fallbackValue,
          };
        }
      };
      const nameI18n = parseI18nPayload(nameI18nRaw, name);
      const genderI18n = parseI18nPayload(genderI18nRaw, gender);
      const occupationI18n = parseI18nPayload(occupationI18nRaw, occupation);
      const addressI18n = parseI18nPayload(addressI18nRaw, address);

      const created = await pool.query(
        `
        INSERT INTO public.users
          (name, email, phone, address, address_house_no, address_floor, address_building, address_road, address_subdistrict, address_district, address_province, address_postal_code, birth_year, gender, occupation, name_i18n, gender_i18n, occupation_i18n, address_i18n, password_hash, profile_image_url, national_id_image_url, first_name, last_name, status, role_id, created_at, updated_at)
        VALUES
          ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16::jsonb, $17::jsonb, $18::jsonb, $19::jsonb, $20, $21, $22, $23, $24, 'active', $25, NOW(), NOW())
        RETURNING id, name, email
        `,
        [
          name,
          email,
          phone,
          address,
          addressHouseNo,
          addressFloor,
          addressBuilding,
          addressRoad,
          addressSubdistrict,
          addressDistrict,
          addressProvince,
          addressPostalCode,
          birthYear,
          gender,
          occupation,
          JSON.stringify(nameI18n),
          JSON.stringify(genderI18n),
          JSON.stringify(occupationI18n),
          JSON.stringify(addressI18n),
          passwordHash,
          profileImageUrl,
          nationalIdImageUrl,
          firstName,
          lastName,
          null,
        ]
      );

      return res.status(201).json({
        success: true,
        user: created.rows[0],
      });
    } catch (e) {
      if (e?.code === "23505") {
        return res.status(409).json({ message: "Email already exists" });
      }
      console.error("Auth signup error:", e);
      return res.status(500).json({
        message: "Server error",
        error: String(e?.message ?? e),
      });
    }
  }
);

/**
 * =====================================================
 * User Auth: Login
 * POST /api/auth/login
 * =====================================================
 */
app.post("/api/auth/login", async (req, res) => {
  try {
    await ensureUserAuthColumns();

    const email = (req.body?.email ?? "").toString().trim().toLowerCase();
    const password = (req.body?.password ?? "").toString();

    if (!email || !password) {
      return res.status(400).json({ message: "email and password required" });
    }

    const q = await pool.query(
      `
      SELECT id, name, email, password_hash, status
      FROM public.users
      WHERE LOWER(email) = $1
      ORDER BY id DESC
      `,
      [email]
    );

    if (q.rowCount === 0) {
      return res.status(401).json({ message: "Invalid credentials" });
    }

    let row = null;
    let matchedInactiveStatus = "";

    for (const candidate of q.rows) {
      const storedHash = String(candidate.password_hash || "");
      let ok = false;

      // Primary verifier for hashes created by bcrypt/bcryptjs.
      if (storedHash) {
        try {
          ok = await bcrypt.compare(password, storedHash);
        } catch (_) {
          ok = false;
        }
      }

      // Legacy verifier for rows created via PostgreSQL crypt(...).
      if (!ok) {
        const legacyCheck = await pool.query(
          `
          SELECT (password_hash = crypt($1, password_hash)) AS ok
          FROM public.users
          WHERE id = $2
          LIMIT 1
          `,
          [password, candidate.id]
        );
        ok = legacyCheck.rowCount > 0 && legacyCheck.rows[0].ok === true;
      }

      // Compatibility: allow direct match for legacy plain-text rows.
      if (!ok && storedHash) {
        ok = storedHash === password;
      }

      if (!ok) continue;

      if (candidate.status && candidate.status !== "active") {
        matchedInactiveStatus = String(candidate.status || "").toLowerCase();
        continue;
      }

      row = candidate;
      break;
    }

    if (!row) {
      if (matchedInactiveStatus) {
        return res.status(403).json({
          message:
            matchedInactiveStatus === "deleted"
              ? "Account deleted by admin"
              : "Account not active",
          status: matchedInactiveStatus,
        });
      }
      return res.status(401).json({ message: "Invalid credentials" });
    }

    await pool.query(
      `
      UPDATE public.users
      SET last_login_at = NOW(), updated_at = NOW()
      WHERE id = $1
      `,
      [row.id]
    );

    return res.json({
      success: true,
      user: {
        id: row.id,
        name: row.name || "User",
        email: row.email,
      },
    });
  } catch (e) {
    console.error("Auth login error:", e);
    return res.status(500).json({
      message: "Server error",
      error: String(e?.message ?? e),
    });
  }
});

app.get("/api/users/me", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureUserAuthColumns();
    const userCtx = getRequestUserId(req, { allowQuery: true, allowBody: false });
    if (!userCtx.ok) {
      return res.status(400).json({ message: userCtx.message });
    }

    const q = await client.query(
      `
      SELECT
        id,
        COALESCE(name, CONCAT_WS(' ', first_name, last_name), 'User') AS name,
        first_name,
        last_name,
        email,
        phone,
        address,
        address_house_no,
        address_floor,
        address_building,
        address_road,
        address_subdistrict,
        address_postal_code,
        address_province AS province,
        address_district AS district,
        profile_image_url,
        national_id_image_url,
        status,
        created_at,
        updated_at
      FROM public.users
      WHERE id = $1
      LIMIT 1
      `,
      [userCtx.userId]
    );

    if (q.rowCount === 0) {
      return res.status(404).json({ message: "User not found" });
    }

    const statsByUserId = await loadUserDistanceStats(client, [userCtx.userId]);
    const stats = statsByUserId.get(userCtx.userId);

    return res.json({
      user: {
        ...q.rows[0],
        total_km: stats?.totalKm ?? null,
        joined_count: stats?.joinedCount ?? 0,
        post_count: stats?.postCount ?? 0,
        completed_count: stats?.completedCount ?? ((stats?.joinedCount ?? 0) + (stats?.postCount ?? 0)),
      },
    });
  } catch (e) {
    console.error("Get current user profile error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.get("/api/users/:id", async (req, res) => {
  const client = await pool.connect();
  try {
    await ensureUserAuthColumns();
    const requestedUserId = Number(req.params.id);
    const userCtx = getRequestUserId(req, { allowQuery: true, allowBody: false });
    if (!userCtx.ok) {
      return res.status(400).json({ message: userCtx.message });
    }
    if (!Number.isFinite(requestedUserId) || requestedUserId <= 0) {
      return res.status(400).json({ message: "Invalid user id" });
    }
    const isSelf = requestedUserId === userCtx.userId;

    const q = await client.query(
      `
      SELECT
        id,
        COALESCE(name, CONCAT_WS(' ', first_name, last_name), 'User') AS name,
        first_name,
        last_name,
        email,
        phone,
        address,
        address_house_no,
        address_floor,
        address_building,
        address_road,
        address_subdistrict,
        address_postal_code,
        address_province AS province,
        address_district AS district,
        profile_image_url,
        national_id_image_url,
        status,
        created_at,
        updated_at
      FROM public.users
      WHERE id = $1
      LIMIT 1
      `,
      [requestedUserId]
    );

    if (q.rowCount === 0) {
      return res.status(404).json({ message: "User not found" });
    }

    const statsByUserId = await loadUserDistanceStats(client, [requestedUserId]);
    const stats = statsByUserId.get(requestedUserId);
    const row = q.rows[0];

    if (isSelf) {
      return res.json({
        ...row,
        total_km: stats?.totalKm ?? null,
        joined_count: stats?.joinedCount ?? 0,
        post_count: stats?.postCount ?? 0,
        completed_count: stats?.completedCount ?? ((stats?.joinedCount ?? 0) + (stats?.postCount ?? 0)),
      });
    }

    return res.json({
      id: row.id,
      name: row.name,
      first_name: row.first_name,
      last_name: row.last_name,
      district: row.district,
      province: row.province,
      profile_image_url: row.profile_image_url,
      status: row.status,
      total_km: stats?.totalKm ?? null,
      joined_count: stats?.joinedCount ?? 0,
      post_count: stats?.postCount ?? 0,
      completed_count: stats?.completedCount ?? ((stats?.joinedCount ?? 0) + (stats?.postCount ?? 0)),
    });
  } catch (e) {
    console.error("Get user profile by id error:", e);
    return res.status(500).json({ message: "Server error", error: String(e?.message ?? e) });
  } finally {
    client.release();
  }
});

app.get("/api/organizations", async (req, res) => {
  try {
    await ensureEventLocationColumns();
    await ensureAdminContentI18nColumns();
    const q = await pool.query(
      `select id, name, description, phone, email, address, image_url, name_i18n, description_i18n, address_i18n, created_at
       from organizations
       where deleted_at is null
       order by id desc`
    );

    return res.json(q.rows);
  } catch (e) {
    console.error("Get organizations error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});


app.get("/api/organizations/:id", async (req, res) => {
  try {
    await ensureAdminContentI18nColumns();
    const id = Number(req.params.id);
    if (!id) return res.status(400).json({ message: "Invalid organization id" });

    const q = await pool.query(
      `select id, name, description, phone, email, address, image_url, name_i18n, description_i18n, address_i18n, created_at
       from organizations
       where id = $1`,
      [id]
    );

    if (q.rowCount === 0) return res.status(404).json({ message: "Organization not found" });
    return res.json(q.rows[0]);
  } catch (e) {
    console.error("Get organization error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

app.get("/api/organizations/:id/events", async (req, res) => {
  try {
    await ensureAdminContentI18nColumns();
    const orgId = Number(req.params.id);
    if (!orgId) return res.status(400).json({ message: "Invalid organization id" });

    const q = await pool.query(
      `
      SELECT
        e.*,
        o.name AS organization_name,
        o.name_i18n AS organization_name_i18n,
        COALESCE(
          (
            SELECT em.file_url
            FROM event_media em
            WHERE em.event_id = e.id AND em.kind = 'cover'
            ORDER BY em.sort_order ASC NULLS LAST, em.id DESC
            LIMIT 1
          ),
          (
            SELECT em.file_url
            FROM event_media em
            WHERE em.event_id = e.id AND em.kind = 'gallery'
            ORDER BY em.sort_order ASC NULLS LAST, em.id ASC
            LIMIT 1
          )
        ) AS cover_url
      FROM events e
      LEFT JOIN organizations o ON o.id = e.organization_id
      WHERE e.organization_id = $1
      ORDER BY e.updated_at DESC NULLS LAST, e.id DESC
      `,
      [orgId]
    );

    const host = `${req.protocol}://${req.get("host")}`;
    const rows = q.rows.map((r) => ({
      ...r,
      cover_url: r.cover_url
        ? (r.cover_url.startsWith("http")
            ? r.cover_url
            : `${host}${r.cover_url.startsWith("/") ? "" : "/"}${r.cover_url}`)
        : null,
      qr_url: r.qr_url
        ? (r.qr_url.startsWith("http")
            ? r.qr_url
            : `${host}${r.qr_url.startsWith("/") ? "" : "/"}${r.qr_url}`)
        : null,
    }));

    return res.json(rows);
  } catch (e) {
    console.error("Get organization events error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

app.post("/api/organizations", async (req, res) => {
  try {
    await ensureAdminContentI18nColumns();
    const adminCtx = await tryGetActiveAdmin(req, { allowQuery: true, allowBody: false });
    const {
      name,
      description,
      phone,
      email,
      address,
      image_url,
      name_i18n,
      description_i18n,
      address_i18n,
    } = req.body ?? {};

    if (typeof name !== "string" || !name.trim()) {
      return res.status(400).json({ message: "name required" });
    }

    const nameI18n = normalizeI18nPayload(name_i18n, name.trim());
    const descriptionI18n = normalizeI18nPayload(
      description_i18n,
      typeof description === "string" ? description.trim() : ""
    );
    const addressI18n = normalizeI18nPayload(
      address_i18n,
      typeof address === "string" ? address.trim() : ""
    );

    const q = await pool.query(
      `insert into organizations (name, description, phone, email, address, image_url, name_i18n, description_i18n, address_i18n)
       values ($1, $2, $3, $4, $5, $6, $7::jsonb, $8::jsonb, $9::jsonb)
       returning id, name, description, phone, email, address, image_url, name_i18n, description_i18n, address_i18n, created_at`,
      [
        name.trim(),
        typeof description === "string" ? description.trim() : null,
        typeof phone === "string" ? phone.trim() : null,
        typeof email === "string" ? email.trim().toLowerCase() : null,
        typeof address === "string" ? address.trim() : null,
        typeof image_url === "string" ? image_url.trim() : null,
        JSON.stringify(nameI18n),
        JSON.stringify(descriptionI18n),
        JSON.stringify(addressI18n),
      ]
    );

    if (adminCtx) {
      await insertAuditLog(pool, {
        adminUserId: adminCtx.adminId,
        actorType: "admin",
        action: "ORGANIZATION_CREATED",
        entityTable: "organizations",
        entityId: q.rows[0]?.id ?? null,
        metadata: {
          organization_name: q.rows[0]?.name ?? name.trim(),
          organization_email: q.rows[0]?.email ?? null,
          changed_fields: ["name", "description", "phone", "email", "address"],
          new_values: {
            name: q.rows[0]?.name ?? name.trim(),
            description: q.rows[0]?.description ?? description ?? null,
            phone: q.rows[0]?.phone ?? phone ?? null,
            email: q.rows[0]?.email ?? email ?? null,
            address: q.rows[0]?.address ?? address ?? null,
          },
        },
      });
    }

    return res.status(201).json(q.rows[0]);
  } catch (e) {
    console.error("Create organization error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

app.put("/api/organizations/:id", async (req, res) => {
  try {
    await ensureAdminContentI18nColumns();
    const adminCtx = await tryGetActiveAdmin(req, { allowQuery: true, allowBody: false });
    const id = Number(req.params.id);
    if (!id) return res.status(400).json({ message: "Invalid organization id" });

    const {
      name,
      description,
      phone,
      email,
      address,
      image_url,
      name_i18n,
      description_i18n,
      address_i18n,
    } = req.body ?? {};
    if (typeof name !== "string" || !name.trim()) {
      return res.status(400).json({ message: "name required" });
    }

    const existingQ = await pool.query(
      `select id, name, description, phone, email, address, image_url, name_i18n, description_i18n, address_i18n
       from organizations
       where id=$1
       limit 1`,
      [id]
    );
    if (existingQ.rowCount === 0) {
      return res.status(404).json({ message: "Organization not found" });
    }
    const old = existingQ.rows[0];
    const nameI18n = normalizeI18nPayload(name_i18n, name.trim());
    const descriptionI18n = normalizeI18nPayload(
      description_i18n,
      typeof description === "string" ? description.trim() : ""
    );
    const addressI18n = normalizeI18nPayload(
      address_i18n,
      typeof address === "string" ? address.trim() : ""
    );

    const q = await pool.query(
      `update organizations
       set name=$1, description=$2, phone=$3, email=$4, address=$5, image_url=$6,
           name_i18n=$7::jsonb, description_i18n=$8::jsonb, address_i18n=$9::jsonb
       where id=$10
       returning id, name, description, phone, email, address, image_url, name_i18n, description_i18n, address_i18n, created_at`,
      [
        name.trim(),
        typeof description === "string" ? description.trim() : null,
        typeof phone === "string" ? phone.trim() : null,
        typeof email === "string" ? email.trim().toLowerCase() : null,
        typeof address === "string" ? address.trim() : null,
        typeof image_url === "string" ? image_url.trim() : null,
        JSON.stringify(nameI18n),
        JSON.stringify(descriptionI18n),
        JSON.stringify(addressI18n),
        id,
      ]
    );

    if (q.rowCount === 0) return res.status(404).json({ message: "Organization not found" });

    const changedFields = [];
    if ((q.rows[0]?.name ?? null) !== (old.name ?? null)) changedFields.push("name");
    if ((q.rows[0]?.description ?? null) !== (old.description ?? null)) changedFields.push("description");
    if ((q.rows[0]?.phone ?? null) !== (old.phone ?? null)) changedFields.push("phone");
    if ((q.rows[0]?.email ?? null) !== (old.email ?? null)) changedFields.push("email");
    if ((q.rows[0]?.address ?? null) !== (old.address ?? null)) changedFields.push("address");

    if (adminCtx) {
      await insertAuditLog(pool, {
        adminUserId: adminCtx.adminId,
        actorType: "admin",
        action: "ORGANIZATION_UPDATED",
        entityTable: "organizations",
        entityId: id,
        metadata: {
          organization_name: q.rows[0]?.name ?? name.trim(),
          organization_email: q.rows[0]?.email ?? null,
          changed_fields: changedFields,
          old_values: Object.fromEntries(changedFields.map((field) => [field, old[field] ?? null])),
          new_values: Object.fromEntries(changedFields.map((field) => [field, q.rows[0]?.[field] ?? null])),
        },
      });
    }

    return res.json(q.rows[0]);
  } catch (e) {
    console.error("Update organization error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

app.delete("/api/admin/organizations/:id", async (req, res) => {
  try {
    const adminCtx = await tryGetActiveAdmin(req, { allowQuery: true, allowBody: false });
    const id = Number(req.params.id);
    if (!id) return res.status(400).json({ message: "Invalid organization id" });

    const q = await pool.query(
      `UPDATE organizations
       SET deleted_at = NOW()
       WHERE id = $1 AND deleted_at IS NULL
       RETURNING id, name, email`,
      [id]
    );

    if (q.rowCount === 0) return res.status(404).json({ message: "Organization not found" });

    if (adminCtx) {
      await insertAuditLog(pool, {
        adminUserId: adminCtx.adminId,
        actorType: "admin",
        action: "ORGANIZATION_DELETED",
        entityTable: "organizations",
        entityId: id,
        metadata: {
          organization_name: q.rows[0]?.name ?? null,
          organization_email: q.rows[0]?.email ?? null,
        },
      });
    }

    return res.json({ ok: true, id: q.rows[0].id });
  } catch (e) {
    console.error("Admin soft delete organization error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});


/**
 * =====================================================
 * ✅ Events APIs + Media (ของเดิม)
 * =====================================================
 */
const EVENT_REWARD_SECTION_KIND = {
  guaranteed: "guaranteed_reward",
  competition: "competition_reward",
};
const BIG_EVENT_SHIRT_ITEM_TYPE = "shirt";
const BIG_EVENT_ALLOWED_SHIRT_SIZES = ["XS", "S", "M", "L", "XL"];

function normalizeEventRewardSection(rawSection) {
  const normalized = String(rawSection ?? "")
    .trim()
    .toLowerCase();
  if (normalized === "guaranteed") {
    return {
      section: "guaranteed",
      kind: EVENT_REWARD_SECTION_KIND.guaranteed,
      responseKey: "guaranteed_items",
    };
  }
  if (normalized === "competition") {
    return {
      section: "competition",
      kind: EVENT_REWARD_SECTION_KIND.competition,
      responseKey: "competition_reward_items",
    };
  }
  return null;
}

function toAbsoluteEventMediaUrl(req, rawUrl) {
  return toAbsoluteUrl(req, rawUrl);
}

function normalizeShirtSizeValue(rawValue) {
  const normalized = String(rawValue ?? "").trim().toUpperCase();
  if (!normalized) return null;
  return BIG_EVENT_ALLOWED_SHIRT_SIZES.includes(normalized) ? normalized : null;
}

async function eventHasGuaranteedShirtReward(db, eventId) {
  const checkQ = await db.query(
    `
    SELECT 1
    FROM event_media
    WHERE event_id = $1
      AND kind::text = $2
      AND LOWER(COALESCE(item_type, '')) = $3
    LIMIT 1
    `,
    [eventId, EVENT_REWARD_SECTION_KIND.guaranteed, BIG_EVENT_SHIRT_ITEM_TYPE]
  );
  return checkQ.rowCount > 0;
}

async function normalizeBigEventShirtSizeOrThrow(db, { eventId, shirtSize }) {
  const normalized = normalizeShirtSizeValue(shirtSize);
  const requiresShirtSize = await eventHasGuaranteedShirtReward(db, eventId);
  if (!requiresShirtSize) {
    return null;
  }
  if (!normalized) {
    const err = new Error(
      `shirt_size is required. Allowed values: ${BIG_EVENT_ALLOWED_SHIRT_SIZES.join(", ")}`
    );
    err.statusCode = 400;
    throw err;
  }
  return normalized;
}

function serializeEventRewardMediaRow(req, row) {
  const kind = String(row?.kind ?? "").trim().toLowerCase();
  const section =
    kind === EVENT_REWARD_SECTION_KIND.competition ? "competition" : "guaranteed";
  return {
    id: Number(row?.id ?? 0),
    event_id: Number(row?.event_id ?? row?.eventId ?? 0),
    kind,
    section,
    image_url: toAbsoluteEventMediaUrl(req, row?.file_url ?? row?.fileUrl),
    item_type: String(row?.item_type ?? row?.itemType ?? "").trim(),
    caption: String(row?.alt_text ?? row?.altText ?? "").trim(),
    sort_order: Number(row?.sort_order ?? row?.sortOrder ?? 0),
    created_at: row?.created_at ?? row?.createdAt ?? null,
  };
}

async function listEventRewardMediaRows(db, eventId) {
  const { rows } = await db.query(
    `
    SELECT id, event_id, kind, file_url, item_type, alt_text, sort_order, created_at
    FROM event_media
    WHERE event_id = $1
      AND kind::text = ANY($2::text[])
    ORDER BY kind ASC, sort_order ASC NULLS LAST, id ASC
    `,
    [
      eventId,
      [
        EVENT_REWARD_SECTION_KIND.guaranteed,
        EVENT_REWARD_SECTION_KIND.competition,
      ],
    ]
  );
  return rows;
}

function buildEventRewardGroups(req, rows) {
  const guaranteedItems = [];
  const competitionRewardItems = [];

  for (const row of rows) {
    const serialized = serializeEventRewardMediaRow(req, row);
    if (serialized.kind === EVENT_REWARD_SECTION_KIND.competition) {
      competitionRewardItems.push(serialized);
    } else {
      guaranteedItems.push(serialized);
    }
  }

  return {
    guaranteed_items: guaranteedItems,
    competition_reward_items: competitionRewardItems,
  };
}

async function buildEventDetailResponse(req, row, db = pool) {
  const rewardRows = await listEventRewardMediaRows(db, Number(row?.id ?? 0));
  return {
    ...row,
    cover_url: row?.cover_url
      ? toAbsoluteEventMediaUrl(req, row.cover_url)
      : null,
    qr_url: row?.qr_url ? toAbsoluteEventMediaUrl(req, row.qr_url) : null,
    ...buildEventRewardGroups(req, rewardRows),
  };
}

app.post("/api/events", async (req, res) => {
  try {
    const adminCtx = await tryGetActiveAdmin(req, { allowQuery: true, allowBody: false });
    await ensureEventDistanceColumns();
    await ensureEventLocationColumns();
    await ensureBusinessReferenceColumns();
    await ensureAdminContentI18nColumns();
    const b = req.body ?? {};

    const organizationId = Number(b.organization_id);
    if (!organizationId) return res.status(400).json({ message: "Invalid organization_id" });

    const type = typeof b.type === "string" && ["SPOT", "BIG_EVENT"].includes(b.type) ? b.type : "BIG_EVENT";

    const description = typeof b.description === "string" ? b.description.trim() : "";
    const meetingPoint = typeof b.meeting_point === "string" ? b.meeting_point.trim() : "";
    let locationName = typeof b.location_name === "string" ? b.location_name.trim() : meetingPoint;
    const locationLink = typeof b.location_link === "string" ? b.location_link.trim() : null;
    const meetingPointNote = typeof b.meeting_point_note === "string" ? b.meeting_point_note.trim() : null;
    const title = typeof b.title === "string" && b.title.trim() ? b.title.trim() : null;
    const titleI18n = normalizeI18nPayload(b.title_i18n, title ?? description);
    const descriptionI18n = normalizeI18nPayload(b.description_i18n, description);
    const meetingPointI18n = normalizeI18nPayload(b.meeting_point_i18n, meetingPoint);
    let locationNameI18n = normalizeI18nPayload(
      b.location_name_i18n,
      locationName || meetingPoint
    );
    const meetingPointNoteI18n = normalizeI18nPayload(
      b.meeting_point_note_i18n,
      meetingPointNote ?? ""
    );

    if (!description) return res.status(400).json({ message: "description required" });
    if (!meetingPoint) return res.status(400).json({ message: "meeting_point required" });

    const startAt = b.start_at;
    if (!startAt) return res.status(400).json({ message: "start_at required" });

    const createdBy = b.created_by != null ? Number(b.created_by) : null;
    const fee = b.fee != null ? Number(b.fee) : 0;
      if (!Number.isFinite(fee) || fee < 0) {
        return res.status(400).json({ message: "Invalid fee" });
      }
    const maxParticipants = b.max_participants != null ? Number(b.max_participants) : null;
    let city = typeof b.city === "string" ? b.city.trim() : null;
    let province = typeof b.province === "string" ? b.province.trim() : null;
    let district = typeof b.district === "string" ? b.district.trim() : null;
    const latitudeRaw = b.location_lat != null ? b.location_lat : b.latitude;
    const longitudeRaw = b.location_lng != null ? b.location_lng : b.longitude;
    const latitude = latitudeRaw != null ? Number(latitudeRaw) : null;
    const longitude = longitudeRaw != null ? Number(longitudeRaw) : null;

    const resolvedLocation = await enrichEventLocationFields({
      meetingPoint,
      locationName,
      city,
      province,
      district,
      latitude,
      longitude,
    });
    locationName = resolvedLocation.locationName;
    locationNameI18n = normalizeI18nPayload(
      b.location_name_i18n,
      locationName || meetingPoint
    );
    city = resolvedLocation.city || city;
    province = resolvedLocation.province || province;
    district = resolvedLocation.district || district;

    const visibility = typeof b.visibility === "string" ? b.visibility : "public";
    const status = typeof b.status === "string" && ["draft", "published", "closed", "cancelled"].includes(b.status)
      ? b.status
      : "draft";

    const endAt = b.end_at ?? null;

    const hasDistancePerLap = b.distance_per_lap !== undefined && b.distance_per_lap !== null && `${b.distance_per_lap}`.trim() !== "";
    const hasNumberOfLaps = b.number_of_laps !== undefined && b.number_of_laps !== null && `${b.number_of_laps}`.trim() !== "";

    if (hasDistancePerLap !== hasNumberOfLaps) {
      return res.status(400).json({
        message: "distance_per_lap and number_of_laps must be provided together",
      });
    }

    let distancePerLap = null;
    let numberOfLaps = null;
    let totalDistance = null;
    const hasPaymentConfigInput = [
      "base_currency",
      "base_amount",
      "exchange_rate_thb_per_cny",
      "enable_promptpay",
      "promptpay_enabled",
      "enable_alipay",
      "alipay_enabled",
    ].some((key) => Object.prototype.hasOwnProperty.call(b, key));
    let lockedPaymentConfig = null;

    if (hasDistancePerLap && hasNumberOfLaps) {
      distancePerLap = Number(b.distance_per_lap);
      numberOfLaps = Number(b.number_of_laps);

      if (!Number.isFinite(distancePerLap) || distancePerLap <= 0) {
        return res.status(400).json({ message: "Invalid distance_per_lap" });
      }
      if (!Number.isInteger(numberOfLaps) || numberOfLaps <= 0) {
        return res.status(400).json({ message: "Invalid number_of_laps" });
      }

      totalDistance = distancePerLap * numberOfLaps;
    }

    if (type === "BIG_EVENT" && hasPaymentConfigInput) {
      const paymentConfigResult = deriveLockedEventPaymentConfig(b);
      if (!paymentConfigResult.ok) {
        return res.status(400).json({ message: paymentConfigResult.message });
      }
      lockedPaymentConfig = paymentConfigResult.value;
    }

    const q = await pool.query(
      `
      insert into events
        (type, created_by, title, description, meeting_point, location_name, meeting_point_note, location_link,
        title_i18n, description_i18n, meeting_point_i18n, location_name_i18n, meeting_point_note_i18n,
        city, province, district, latitude, longitude, location_lat, location_lng,
        start_at, end_at, max_participants, visibility, status, organization_id, fee,
        distance_per_lap, number_of_laps, total_distance,
        base_currency, base_amount, exchange_rate_thb_per_cny,
        promptpay_enabled, alipay_enabled, enable_promptpay, enable_alipay,
        promptpay_amount_thb, alipay_amount_cny, fx_locked_at, currency)
      values
        ($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10::jsonb,$11::jsonb,$12::jsonb,$13::jsonb,$14,$15,$16,$17,$18,$19,$20,
        $21,$22,$23,$24,$25,$26,$27,$28,$29,$30,$31,$32,$33,$34,$35,$36,$37,$38,$39,$40,$41)
      returning *
            `,
      [
        type,
        createdBy,
        title,
        description,
        meetingPoint,
        locationName || meetingPoint,
        meetingPointNote,
        locationLink,
        JSON.stringify(titleI18n),
        JSON.stringify(descriptionI18n),
        JSON.stringify(meetingPointI18n),
        JSON.stringify(locationNameI18n),
        JSON.stringify(meetingPointNoteI18n),
        city,
        province,
        district,
        latitude,
        longitude,
        latitude,
        longitude,
        startAt,
        endAt,
        maxParticipants,
        visibility,
        status,
        organizationId,
        fee,
        distancePerLap,
        numberOfLaps,
        totalDistance,
        lockedPaymentConfig?.base_currency ?? null,
        lockedPaymentConfig?.base_amount ?? null,
        lockedPaymentConfig?.exchange_rate_thb_per_cny ?? null,
        lockedPaymentConfig?.promptpay_enabled ?? true,
        lockedPaymentConfig?.alipay_enabled ?? false,
        lockedPaymentConfig?.promptpay_enabled ?? true,
        lockedPaymentConfig?.alipay_enabled ?? false,
        lockedPaymentConfig?.promptpay_amount_thb ?? fee,
        lockedPaymentConfig?.alipay_amount_cny ?? null,
        lockedPaymentConfig ? new Date().toISOString() : null,
        lockedPaymentConfig ? "THB" : null,
      ]
    );

    const displayCode = await ensureEventDisplayCode(pool, {
      tableName: "events",
      entityId: q.rows[0].id,
      type,
    });

    if (adminCtx) {
      await insertAuditLog(pool, {
        adminUserId: adminCtx.adminId,
        actorType: "admin",
        action: type === "SPOT" ? "SPOT_CREATED" : "BIG_EVENT_CREATED",
        entityTable: "events",
        entityId: q.rows[0]?.id ?? null,
        metadata: {
          event_type: type,
          display_code: displayCode,
          title: q.rows[0]?.title ?? title ?? null,
          organization_id: organizationId,
          changed_fields: ["title", "description", "meeting_point", "start_at", "status"],
          new_values: {
            title: q.rows[0]?.title ?? title ?? null,
            description: q.rows[0]?.description ?? description ?? null,
            meeting_point: q.rows[0]?.meeting_point ?? meetingPoint ?? null,
            start_at: q.rows[0]?.start_at ?? startAt ?? null,
            status: q.rows[0]?.status ?? status ?? null,
          },
        },
      });
    }

    return res.status(201).json(
      await buildEventDetailResponse(
        req,
        {
          ...q.rows[0],
          display_code: displayCode,
        },
        pool
      )
    );
  } catch (e) {
    console.error("Create event error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});


app.get("/api/big-events", async (req, res) => {
  try {
    const userParse = getRequestUserId(req, { allowQuery: true, allowBody: false });
    const currentUserId = userParse.ok ? userParse.userId : null;
    console.log("[big-events] list", {
      userId: currentUserId,
      hideJoined: !!currentUserId,
    });
    const q = await pool.query(`
      SELECT
        e.*,
        o.name AS organization_name,
        COALESCE(
          (
            SELECT em.file_url
            FROM event_media em
            WHERE em.event_id = e.id AND em.kind = 'cover'
            ORDER BY em.sort_order ASC NULLS LAST, em.id DESC
            LIMIT 1
          ),
          (
            SELECT em.file_url
            FROM event_media em
            WHERE em.event_id = e.id AND em.kind = 'gallery'
            ORDER BY em.sort_order ASC NULLS LAST, em.id ASC
            LIMIT 1
          )
        ) AS cover_url
      FROM events e
      LEFT JOIN organizations o ON o.id = e.organization_id
      WHERE e.status = 'published'
        AND e.type = 'BIG_EVENT'
        AND (
          $1::int IS NULL
          OR NOT EXISTS (
            SELECT 1
            FROM bookings b
            LEFT JOIN payments p ON p.booking_id = b.id
            LEFT JOIN participants pt
              ON pt.booking_id = b.id
             AND pt.event_id = b.event_id
             AND pt.user_id = b.user_id
            WHERE b.user_id = $1
              AND b.event_id = e.id
              AND (
                LOWER(COALESCE(b.status::text, '')) IN ('confirmed', 'paid', 'completed', 'success')
                OR LOWER(COALESCE(p.status::text, '')) IN ('paid', 'completed', 'success', 'succeeded')
                OR LOWER(COALESCE(pt.status::text, '')) IN ('joined', 'completed', 'success')
              )
          )
        )
      ORDER BY e.updated_at DESC NULLS LAST, e.id DESC
      LIMIT 50;
    `, [currentUserId]);

    // ✅ ใช้ host จริงตาม request (แก้ปัญหา emulator/web)
    const host = `${req.protocol}://${req.get("host")}`;

    const rows = q.rows.map((r) => ({
      ...r,
      cover_url: r.cover_url
        ? (r.cover_url.startsWith("http")
            ? r.cover_url
            : `${host}${r.cover_url.startsWith("/") ? "" : "/"}${r.cover_url}`)
        : null,
      qr_url: r.qr_url
        ? (r.qr_url.startsWith("http")
            ? r.qr_url
            : `${host}${r.qr_url.startsWith("/") ? "" : "/"}${r.qr_url}`)
        : null,
      qr_payment_method: r.qr_payment_method ?? null,
    }));

    res.json(rows);
  } catch (err) {
    console.error("GET /api/big-events error:", err);
    res.status(500).json({ message: "server error" });
  }
});

app.post("/api/events/:id/cover", upload.single("file"), async (req, res) => {
  try {
    const eventId = Number(req.params.id);
    if (!eventId) return res.status(400).json({ message: "Invalid event id" });
    if (!req.file) return res.status(400).json({ message: "No file uploaded" });

    // ✅ เก็บใน DB เป็น path (ปลอดภัยกว่า)
    const filePath = `/uploads/${req.file.filename}`;

    await pool.query("delete from event_media where event_id=$1 and kind='cover'", [eventId]);

    const inserted = await pool.query(
      `insert into event_media (event_id, kind, file_url, alt_text, sort_order)
       values ($1, 'cover', $2, $3, 0)
       returning *`,
      [eventId, filePath, "cover"]
    );

    // ✅ ส่งกลับเป็น URL เต็มให้ frontend ใช้ได้ทันที
    const fullUrl = `${req.protocol}://${req.get("host")}${filePath}`;

    return res.status(201).json({
      ...inserted.rows[0],
      full_url: fullUrl,
    });
  } catch (e) {
    console.error("Upload cover error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

app.post("/api/admin/big-events/:id/alipay-qr", uploadQR.single("file"), async (req, res) => {
  return res.status(410).json({
    message: "Alipay has been removed. Please upload PromptPay QR only.",
  });
});

app.post("/api/admin/events/:id/qr", uploadQR.single("file"), async (req, res) => {
  const client = await pool.connect();
  try {
    const adminCtx = await requireActiveAdmin(req, res, { allowQuery: false, allowBody: false });
    if (!adminCtx) return;

    const eventId = parseInt(req.params.id, 10);

    if (!eventId || Number.isNaN(eventId)) {
      return res.status(400).json({ message: "Invalid event ID" });
    }

    if (!req.file) {
      return res.status(400).json({ message: "No file uploaded" });
    }

    const qrUrl = `/uploads/qr/${req.file.filename}`;
    const paymentMethod = "promptpay";
    const methodType = "PROMPTPAY";

    await client.query("BEGIN");

    const updateRes = await client.query(
      `
      UPDATE events
      SET 
        qr_url = CASE WHEN $2::text = 'promptpay' THEN $1::text ELSE qr_url END,
        qr_payment_method = $2::text,
        manual_promptpay_qr_url = CASE WHEN $2::text = 'promptpay' THEN $1::text ELSE manual_promptpay_qr_url END,
        manual_alipay_qr_url = manual_alipay_qr_url,
        alipay_qr_url = alipay_qr_url,
        updated_at = NOW()
      WHERE id = $3::bigint
      RETURNING 
        id, 
        title, 
        qr_url, 
        qr_payment_method,
        manual_promptpay_qr_url,
        manual_alipay_qr_url,
        updated_at
      `,
      [qrUrl, paymentMethod, eventId]
    );

    if (updateRes.rowCount === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ message: "Event not found" });
    }

    await upsertEventPaymentMethod(client, {
      eventId,
      methodType,
      provider: "MANUAL_QR",
      qrImageUrl: qrUrl,
      isActive: true,
    });

    await client.query("COMMIT");

    const updatedEvent = updateRes.rows[0];

    console.log("✅ QR code uploaded:", { eventId, qrUrl, paymentMethod });

    return res.status(200).json({
      message: "QR code uploaded successfully",
      id: updatedEvent.id,
      title: updatedEvent.title,
      qr_url: toAbsoluteUrl(req, qrUrl),
      qr_payment_method: updatedEvent.qr_payment_method,
      manual_promptpay_qr_url: toAbsoluteUrl(req, updatedEvent.manual_promptpay_qr_url),
      manual_alipay_qr_url: null,
      updated_at: updatedEvent.updated_at,
    });
  } catch (err) {
    await client.query("ROLLBACK");
    console.error("❌ QR upload error:", err);
    return res.status(500).json({
      message: "Server error",
      error: err.message,
    });
  } finally {
    client.release();
  }
});

app.post("/api/events/:id/gallery", upload.array("files", 10), async (req, res) => {
  try {
    const eventId = Number(req.params.id);
    if (!eventId) return res.status(400).json({ message: "Invalid event id" });

    const files = req.files ?? [];
    if (!Array.isArray(files) || files.length === 0) {
      return res.status(400).json({ message: "No files uploaded" });
    }

    const rows = [];
    for (let i = 0; i < files.length; i++) {
      const f = files[i];
      const fileUrl = `${req.protocol}://${req.get("host")}/uploads/${f.filename}`;

      const inserted = await pool.query(
        `insert into event_media (event_id, kind, file_url, alt_text, sort_order)
         values ($1, 'gallery', $2, $3, $4)
         returning *`,
        [eventId, fileUrl, "gallery", i + 1]
      );
      rows.push(inserted.rows[0]);
    }

    return res.status(201).json(rows);
  } catch (e) {
    console.error("Upload gallery error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

app.post("/api/events/:id/rewards/:section", upload.array("files", 10), async (req, res) => {
  const client = await pool.connect();
  try {
    const adminCtx = await requireActiveAdmin(req, res, {
      allowQuery: false,
      allowBody: false,
    });
    if (!adminCtx) return;

    const eventId = Number(req.params.id);
    if (!eventId) {
      return res.status(400).json({ message: "Invalid event id" });
    }

    const rewardSection = normalizeEventRewardSection(req.params.section);
    if (!rewardSection) {
      return res.status(400).json({ message: "Invalid reward section" });
    }

    const files = Array.isArray(req.files) ? req.files : [];
    if (files.length === 0) {
      return res.status(400).json({ message: "No reward files uploaded" });
    }

    let captions = [];
    let itemTypes = [];
    let sortOrders = [];
    try {
      captions = JSON.parse(String(req.body?.captions_json ?? "[]"));
      itemTypes = JSON.parse(String(req.body?.item_types_json ?? "[]"));
      sortOrders = JSON.parse(String(req.body?.sort_orders_json ?? "[]"));
    } catch (_) {
      return res.status(400).json({ message: "Invalid reward metadata payload" });
    }

    if (!Array.isArray(captions) || !Array.isArray(itemTypes) || !Array.isArray(sortOrders)) {
      return res.status(400).json({ message: "Invalid reward metadata payload" });
    }

    await client.query("BEGIN");

    const eventQ = await client.query(
      "SELECT id, type FROM events WHERE id = $1 LIMIT 1",
      [eventId]
    );
    if (eventQ.rowCount === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ message: "Event not found" });
    }
    if (String(eventQ.rows[0].type ?? "").toUpperCase() !== "BIG_EVENT") {
      await client.query("ROLLBACK");
      return res.status(400).json({ message: "Rewards are supported for BIG_EVENT only" });
    }

    const countQ = await client.query(
      `
      SELECT COUNT(*)::int AS item_count
      FROM event_media
      WHERE event_id = $1
        AND kind::text = $2
      `,
      [eventId, rewardSection.kind]
    );
    const existingCount = Number(countQ.rows[0]?.item_count ?? 0);
    if (existingCount + files.length > 10) {
      await client.query("ROLLBACK");
      return res.status(400).json({
        message: `Maximum 10 ${rewardSection.section} reward images are allowed`,
      });
    }

    const insertedRows = [];
    for (let i = 0; i < files.length; i++) {
      const file = files[i];
      const fileUrl = `${req.protocol}://${req.get("host")}/uploads/${file.filename}`;
      const caption = String(captions[i] ?? "").trim();
      const itemType = String(itemTypes[i] ?? "").trim().toLowerCase();
      const requestedSortOrder = Number(sortOrders[i]);
      const sortOrder =
        Number.isFinite(requestedSortOrder) && requestedSortOrder > 0
          ? Math.trunc(requestedSortOrder)
          : existingCount + i + 1;
      if (!itemType) {
        await client.query("ROLLBACK");
        return res.status(400).json({ message: "Reward item type is required" });
      }

      const inserted = await client.query(
        `
        INSERT INTO event_media (event_id, kind, file_url, item_type, alt_text, sort_order)
        VALUES ($1, $2, $3, $4, $5, $6)
        RETURNING id, event_id, kind, file_url, item_type, alt_text, sort_order, created_at
        `,
        [eventId, rewardSection.kind, fileUrl, itemType, caption, sortOrder]
      );
      insertedRows.push(inserted.rows[0]);
    }

    await client.query("COMMIT");
    return res.status(201).json({
      section: rewardSection.section,
      items: insertedRows.map((row) => serializeEventRewardMediaRow(req, row)),
    });
  } catch (e) {
    await client.query("ROLLBACK");
    console.error("Upload event rewards error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  } finally {
    client.release();
  }
});

app.put("/api/events/:id/rewards/:section", async (req, res) => {
  const client = await pool.connect();
  try {
    const adminCtx = await requireActiveAdmin(req, res, {
      allowQuery: false,
      allowBody: false,
    });
    if (!adminCtx) return;

    const eventId = Number(req.params.id);
    if (!eventId) {
      return res.status(400).json({ message: "Invalid event id" });
    }

    const rewardSection = normalizeEventRewardSection(req.params.section);
    if (!rewardSection) {
      return res.status(400).json({ message: "Invalid reward section" });
    }

    const items = Array.isArray(req.body?.items) ? req.body.items : null;
    if (!items) {
      return res.status(400).json({ message: "items array is required" });
    }
    if (items.length > 10) {
      return res.status(400).json({
        message: `Maximum 10 ${rewardSection.section} reward images are allowed`,
      });
    }

    await client.query("BEGIN");

    const eventQ = await client.query(
      "SELECT id, type FROM events WHERE id = $1 LIMIT 1",
      [eventId]
    );
    if (eventQ.rowCount === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ message: "Event not found" });
    }
    if (String(eventQ.rows[0].type ?? "").toUpperCase() !== "BIG_EVENT") {
      await client.query("ROLLBACK");
      return res.status(400).json({ message: "Rewards are supported for BIG_EVENT only" });
    }

    const existingRowsQ = await client.query(
      `
      SELECT id
      FROM event_media
      WHERE event_id = $1
        AND kind::text = $2
      `,
      [eventId, rewardSection.kind]
    );
    const existingIds = new Set(existingRowsQ.rows.map((row) => Number(row.id)));

    for (let index = 0; index < items.length; index++) {
      const item = items[index];
      const mediaId = Number(item?.id);
      if (!existingIds.has(mediaId)) {
        await client.query("ROLLBACK");
        return res.status(400).json({ message: "Invalid reward item id" });
      }

      const requestedSortOrder = Number(item?.sort_order);
      const itemType = String(item?.item_type ?? item?.itemType ?? "").trim().toLowerCase();
      const sortOrder =
        Number.isFinite(requestedSortOrder) && requestedSortOrder > 0
          ? Math.trunc(requestedSortOrder)
          : index + 1;
      if (!itemType) {
        await client.query("ROLLBACK");
        return res.status(400).json({ message: "Reward item type is required" });
      }

      await client.query(
        `
        UPDATE event_media
        SET alt_text = $1,
            item_type = $2,
            sort_order = $3
        WHERE id = $4
          AND event_id = $5
          AND kind::text = $6
        `,
        [
          String(item?.caption ?? "").trim(),
          itemType,
          sortOrder,
          mediaId,
          eventId,
          rewardSection.kind,
        ]
      );
    }

    await client.query("COMMIT");
    const rewardRows = await listEventRewardMediaRows(client, eventId);
    const grouped = buildEventRewardGroups(req, rewardRows);
    return res.json({
      section: rewardSection.section,
      [rewardSection.responseKey]: grouped[rewardSection.responseKey],
    });
  } catch (e) {
    await client.query("ROLLBACK");
    console.error("Update event rewards error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  } finally {
    client.release();
  }
});

app.get("/api/events/:id", async (req, res) => {
  const id = Number(req.params.id);

  try {
    await ensureAdminContentI18nColumns();
    const { rows } = await pool.query(
      `SELECT
         e.*,
         COALESCE(
           (SELECT file_url
              FROM event_media
             WHERE event_id = e.id AND kind = 'cover'
             ORDER BY sort_order ASC NULLS LAST, id DESC
             LIMIT 1),
           (SELECT file_url
              FROM event_media
             WHERE event_id = e.id AND kind = 'gallery'
             ORDER BY sort_order ASC NULLS LAST, id ASC
             LIMIT 1)
         ) AS cover_url
       FROM events e
       WHERE e.id = $1
       LIMIT 1`,
      [id]
    );

    if (rows.length === 0) return res.status(404).json({ message: "Not found" });
    const row = rows[0];
    return res.json(await buildEventDetailResponse(req, row, pool));
  } catch (e) {
    console.error("Get event detail error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

app.put("/api/events/:id", async (req, res) => {
  const id = Number(req.params.id);
  if (!id) return res.status(400).json({ message: "Invalid event id" });

  try {
    const adminCtx = await tryGetActiveAdmin(req, { allowQuery: true, allowBody: false });
    await ensureEventDistanceColumns();
    await ensureEventLocationColumns();
    await ensureBusinessReferenceColumns();
    await ensureAdminContentI18nColumns();
    const b = req.body ?? {};

    const oldQ = await pool.query("select * from events where id=$1 limit 1", [id]);
    if (oldQ.rowCount === 0) return res.status(404).json({ message: "Event not found" });
    const old = oldQ.rows[0];

    const title = typeof b.title === "string" && b.title.trim() ? b.title.trim() : old.title;
    const description = typeof b.description === "string" ? b.description.trim() : old.description;
    const meetingPoint = typeof b.meeting_point === "string" ? b.meeting_point.trim() : old.meeting_point;
    let locationName = typeof b.location_name === "string"
      ? b.location_name.trim()
      : (old.location_name ?? meetingPoint);
    const meetingPointNote = typeof b.meeting_point_note === "string"
      ? b.meeting_point_note.trim()
      : old.meeting_point_note;
    const locationLink = typeof b.location_link === "string"
      ? b.location_link.trim()
      : old.location_link;
    const titleI18n = normalizeI18nPayload(
      b.title_i18n,
      title ?? description
    );
    const descriptionI18n = normalizeI18nPayload(
      b.description_i18n,
      description
    );
    const meetingPointI18n = normalizeI18nPayload(
      b.meeting_point_i18n,
      meetingPoint
    );
    let locationNameI18n = normalizeI18nPayload(
      b.location_name_i18n,
      locationName || meetingPoint
    );
    const meetingPointNoteI18n = normalizeI18nPayload(
      b.meeting_point_note_i18n,
      meetingPointNote ?? ""
    );

    if (!description) return res.status(400).json({ message: "description required" });
    if (!meetingPoint) return res.status(400).json({ message: "meeting_point required" });

    const startAt = b.start_at ?? old.start_at;
    if (!startAt) return res.status(400).json({ message: "start_at required" });

    const maxParticipants = b.max_participants != null ? Number(b.max_participants) : old.max_participants;
    let city = typeof b.city === "string" ? b.city.trim() : old.city;
    let province = typeof b.province === "string" ? b.province.trim() : old.province;
    let district = typeof b.district === "string" ? b.district.trim() : old.district;
    const latitudeRaw = b.location_lat !== undefined ? b.location_lat : (b.latitude !== undefined ? b.latitude : old.location_lat ?? old.latitude);
    const longitudeRaw = b.location_lng !== undefined ? b.location_lng : (b.longitude !== undefined ? b.longitude : old.location_lng ?? old.longitude);
    const latitude = latitudeRaw == null || `${latitudeRaw}`.trim() === "" ? null : Number(latitudeRaw);
    const longitude = longitudeRaw == null || `${longitudeRaw}`.trim() === "" ? null : Number(longitudeRaw);

    const resolvedLocation = await enrichEventLocationFields({
      meetingPoint,
      locationName,
      city,
      province,
      district,
      latitude,
      longitude,
    });
    locationName = resolvedLocation.locationName;
    locationNameI18n = normalizeI18nPayload(
      b.location_name_i18n,
      locationName || meetingPoint
    );
    city = resolvedLocation.city || city;
    province = resolvedLocation.province || province;
    district = resolvedLocation.district || district;

    const status = typeof b.status === "string" && ["draft", "published", "closed", "cancelled"].includes(b.status)
      ? b.status
      : old.status;

    const endAt = b.end_at !== undefined ? b.end_at : old.end_at;

    const hasDistancePerLap = b.distance_per_lap !== undefined;
    const hasNumberOfLaps = b.number_of_laps !== undefined;
    if (hasDistancePerLap !== hasNumberOfLaps) {
      return res.status(400).json({
        message: "distance_per_lap and number_of_laps must be updated together",
      });
    }

    let distancePerLap = old.distance_per_lap;
    let numberOfLaps = old.number_of_laps;
    let totalDistance = old.total_distance;
    const hasPaymentConfigInput = [
      "base_currency",
      "base_amount",
      "exchange_rate_thb_per_cny",
      "enable_promptpay",
      "promptpay_enabled",
      "enable_alipay",
      "alipay_enabled",
    ].some((key) => Object.prototype.hasOwnProperty.call(b, key));
    let lockedPaymentConfig = null;

    if (hasDistancePerLap && hasNumberOfLaps) {
      const rawDistance = b.distance_per_lap;
      const rawLaps = b.number_of_laps;

      const clearingDistance = rawDistance === null || `${rawDistance}`.trim() === "";
      const clearingLaps = rawLaps === null || `${rawLaps}`.trim() === "";

      if (clearingDistance && clearingLaps) {
        distancePerLap = null;
        numberOfLaps = null;
        totalDistance = old.total_distance;
      } else {
        distancePerLap = Number(rawDistance);
        numberOfLaps = Number(rawLaps);
        if (!Number.isFinite(distancePerLap) || distancePerLap <= 0) {
          return res.status(400).json({ message: "Invalid distance_per_lap" });
        }
        if (!Number.isInteger(numberOfLaps) || numberOfLaps <= 0) {
          return res.status(400).json({ message: "Invalid number_of_laps" });
        }
        totalDistance = distancePerLap * numberOfLaps;
      }
    }

    if (String(old.type ?? "BIG_EVENT").toUpperCase() === "BIG_EVENT" && hasPaymentConfigInput) {
      const paymentConfigResult = deriveLockedEventPaymentConfig(b, old);
      if (!paymentConfigResult.ok) {
        return res.status(400).json({ message: paymentConfigResult.message });
      }
      lockedPaymentConfig = paymentConfigResult.value;
    }

    const q = await pool.query(
      `
      update events
      set
        title=$1,
        description=$2,
        meeting_point=$3,
        location_name=$4,
        meeting_point_note=$5,
        location_link=$6,
        title_i18n=$7::jsonb,
        description_i18n=$8::jsonb,
        meeting_point_i18n=$9::jsonb,
        location_name_i18n=$10::jsonb,
        meeting_point_note_i18n=$11::jsonb,
        city=$12,
        province=$13,
        district=$14,
        latitude=$15,
        longitude=$16,
        location_lat=$17,
        location_lng=$18,
        start_at=$19,
        end_at=$20,
        max_participants=$21,
        status=$22,
        distance_per_lap=$23,
        number_of_laps=$24,
        total_distance=$25,
        base_currency=$26,
        base_amount=$27,
        exchange_rate_thb_per_cny=$28,
        promptpay_enabled=$29,
        alipay_enabled=$30,
        enable_promptpay=$31,
        enable_alipay=$32,
        promptpay_amount_thb=$33,
        alipay_amount_cny=$34,
        fx_locked_at=$35,
        fee=$36,
        currency=$37,
        updated_at=now()
      where id=$38
      returning *
      `,
      [
        title,
        description,
        meetingPoint,
        locationName || meetingPoint,
        meetingPointNote,
        locationLink,
        JSON.stringify(titleI18n),
        JSON.stringify(descriptionI18n),
        JSON.stringify(meetingPointI18n),
        JSON.stringify(locationNameI18n),
        JSON.stringify(meetingPointNoteI18n),
        city,
        province,
        district,
        latitude,
        longitude,
        latitude,
        longitude,
        startAt,
        endAt,
        maxParticipants,
        status,
        distancePerLap,
        numberOfLaps,
        totalDistance,
        lockedPaymentConfig?.base_currency ?? old.base_currency,
        lockedPaymentConfig?.base_amount ?? old.base_amount,
        lockedPaymentConfig?.exchange_rate_thb_per_cny ?? old.exchange_rate_thb_per_cny,
        lockedPaymentConfig?.promptpay_enabled ?? old.promptpay_enabled ?? true,
        lockedPaymentConfig?.alipay_enabled ?? old.alipay_enabled ?? false,
        lockedPaymentConfig?.promptpay_enabled ?? old.enable_promptpay ?? true,
        lockedPaymentConfig?.alipay_enabled ?? old.enable_alipay ?? false,
        lockedPaymentConfig?.promptpay_amount_thb ?? old.promptpay_amount_thb ?? old.fee,
        lockedPaymentConfig?.alipay_amount_cny ?? old.alipay_amount_cny,
        lockedPaymentConfig ? new Date().toISOString() : old.fx_locked_at,
        lockedPaymentConfig?.promptpay_amount_thb ?? old.fee,
        lockedPaymentConfig ? "THB" : old.currency,
        id,
      ]
    );

    const displayCode =
      String(q.rows[0]?.display_code ?? "").trim() ||
      await ensureEventDisplayCode(pool, {
        tableName: "events",
        entityId: id,
        type: old.type,
      });

    const changedFields = [];
    if (title !== old.title) changedFields.push("title");
    if (description !== old.description) changedFields.push("description");
    if (meetingPoint !== old.meeting_point) changedFields.push("meeting_point");
    if ((locationName || meetingPoint) !== (old.location_name ?? old.meeting_point)) changedFields.push("location_name");
    if (city !== old.city) changedFields.push("city");
    if (province !== old.province) changedFields.push("province");
    if (district !== old.district) changedFields.push("district");
    if (String(startAt ?? "") !== String(old.start_at ?? "")) changedFields.push("start_at");
    if (String(endAt ?? "") !== String(old.end_at ?? "")) changedFields.push("end_at");
    if (Number(maxParticipants ?? 0) !== Number(old.max_participants ?? 0)) changedFields.push("max_participants");
    if (status !== old.status) changedFields.push("status");
    if (Number(distancePerLap ?? 0) !== Number(old.distance_per_lap ?? 0)) changedFields.push("distance_per_lap");
    if (Number(numberOfLaps ?? 0) !== Number(old.number_of_laps ?? 0)) changedFields.push("number_of_laps");
    if (Number(totalDistance ?? 0) !== Number(old.total_distance ?? 0)) changedFields.push("total_distance");

    if (adminCtx) {
      await insertAuditLog(pool, {
        adminUserId: adminCtx.adminId,
        actorType: "admin",
        action: String(old.type || "").toUpperCase() === "SPOT"
          ? "SPOT_UPDATED"
          : "BIG_EVENT_UPDATED",
        entityTable: "events",
        entityId: id,
        metadata: {
          display_code: displayCode,
          event_type: old.type ?? null,
          title: q.rows[0]?.title ?? title ?? old.title ?? null,
          organization_id: q.rows[0]?.organization_id ?? old.organization_id ?? null,
          changed_fields: changedFields,
          old_values: Object.fromEntries(changedFields.map((field) => [field, old[field] ?? null])),
          new_values: Object.fromEntries(changedFields.map((field) => [field, q.rows[0]?.[field] ?? null])),
        },
      });
    }

    return res.json(
      await buildEventDetailResponse(
        req,
        {
          ...q.rows[0],
          display_code: displayCode,
        },
        pool
      )
    );
  } catch (e) {
    console.error("Update event error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

const deleteEventById = async (req, res) => {
  const id = Number(req.params.id);
  if (!id) return res.status(400).json({ message: "Invalid event id" });

  const client = await pool.connect();
  try {
    const adminCtx = await tryGetActiveAdmin(req, { allowQuery: true, allowBody: false });
    await client.query("BEGIN");

    const eventQ = await client.query(
      "select id, type, title, organization_id from events where id=$1 limit 1",
      [id]
    );
    if (eventQ.rowCount === 0) {
      await client.query("ROLLBACK");
      return res.status(404).json({ message: "Event not found" });
    }

    const mediaQ = await client.query(
      "select file_url from event_media where event_id=$1",
      [id]
    );

    const bookingIdsQ = await client.query(
      "select id from bookings where event_id=$1",
      [id]
    );
    const bookingIds = bookingIdsQ.rows.map((r) => r.id);

    await client.query("delete from participants where event_id=$1", [id]);

    if (bookingIds.length > 0) {
      await client.query(
        `
        delete from receipts
        where payment_id in (
          select id from payments where booking_id = any($1::int[])
        )
        `,
        [bookingIds]
      );

      await client.query(
        "delete from payments where booking_id = any($1::int[])",
        [bookingIds]
      );
    }

    if (bookingIds.length > 0) {
      await client.query("delete from bookings where id = any($1::int[])", [bookingIds]);
    }

    await client.query("delete from event_media where event_id=$1", [id]);
    await client.query("delete from events where id=$1", [id]);

    if (adminCtx) {
      await insertAuditLog(client, {
        adminUserId: adminCtx.adminId,
        actorType: "admin",
        action: String(eventQ.rows[0]?.type || "").toUpperCase() === "SPOT"
          ? "SPOT_DELETED"
          : "BIG_EVENT_DELETED",
        entityTable: "events",
        entityId: id,
        metadata: {
          event_type: eventQ.rows[0]?.type ?? null,
          title: eventQ.rows[0]?.title ?? null,
          organization_id: eventQ.rows[0]?.organization_id ?? null,
        },
      });
    }

    await client.query("COMMIT");

    // Best effort cleanup files from disk after DB commit.
    for (const row of mediaQ.rows) {
      const raw = (row.file_url || "").toString().trim();
      if (!raw) continue;

      let pathname = raw;
      if (raw.startsWith("http://") || raw.startsWith("https://")) {
        try {
          pathname = new URL(raw).pathname;
        } catch (_) {
          pathname = raw;
        }
      }

      if (!pathname.startsWith("/uploads/")) continue;
      const abs = path.join(__dirname, pathname.replace(/^\//, ""));

      try {
        if (fs.existsSync(abs)) fs.unlinkSync(abs);
      } catch (fileErr) {
        console.warn("Delete media file warning:", abs, fileErr?.message || fileErr);
      }
    }

    return res.status(200).json({
      ok: true,
      deleted_event_id: id,
      deleted_bookings: bookingIds.length,
      deleted_media: mediaQ.rowCount,
    });
  } catch (e) {
    await client.query("ROLLBACK");
    console.error("Delete event error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  } finally {
    client.release();
  }
};

app.delete("/api/events/:id", deleteEventById);
app.delete("/api/admin/events/:id", deleteEventById);

app.get("/api/events/:id/media", async (req, res) => {
  try {
    const eventId = Number(req.params.id);
    if (!eventId) return res.status(400).json({ message: "Invalid event id" });

    const q = await pool.query(
      `select * from event_media
       where event_id = $1
       order by kind asc, sort_order asc, id asc`,
      [eventId]
    );

    return res.json(q.rows);
  } catch (e) {
    console.error("Get media error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

app.delete("/api/events/:eventId/media/:mediaId", async (req, res) => {
  try {
    const eventId = Number(req.params.eventId);
    const mediaId = Number(req.params.mediaId);
    if (!eventId || !mediaId) {
      return res.status(400).json({ message: "Invalid event/media id" });
    }

    const deleted = await pool.query(
      `delete from event_media
       where id = $1 and event_id = $2
       returning id, event_id, kind, file_url`,
      [mediaId, eventId]
    );

    if (deleted.rowCount === 0) {
      return res.status(404).json({ message: "Media not found" });
    }

    return res.json({ ok: true, media: deleted.rows[0] });
  } catch (e) {
    console.error("Delete media error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

/**
 * =====================================================
 * ✅ Admin: Payment report by Event
 * GET /api/admin/events/:eventId/payments
 * =====================================================
 */
app.get("/api/admin/events/:eventId/payments", async (req, res) => {
  try {
    const adminCtx = await requireActiveAdmin(req, res, { allowQuery: false, allowBody: false });
    if (!adminCtx) return;

    const eventId = Number(req.params.eventId);
    if (!eventId) return res.status(400).json({ message: "Invalid eventId" });

    const q = await pool.query(
      `
      SELECT
        b.id AS booking_id,
        b.user_id,
        b.event_id,
        b.quantity,
        b.total_amount,
        b.status AS booking_status,
        b.created_at AS booking_created_at,

        p.id AS payment_id,
        p.method AS payment_method,
        p.provider,
        p.provider_txn_id,
        p.amount AS payment_amount,
        p.status AS payment_status,
        p.paid_at

      FROM bookings b
      LEFT JOIN payments p ON p.booking_id = b.id
      WHERE b.event_id = $1
      ORDER BY COALESCE(p.paid_at, b.created_at) DESC NULLS LAST, b.id DESC
      `,
      [eventId]
    );

    const rows = q.rows.map((r) => ({
      booking_id: r.booking_id,
      user_id: r.user_id,
      event_id: r.event_id,
      quantity: r.quantity,
      total_amount: r.total_amount,
      booking_status: r.booking_status,
      booking_created_at: r.booking_created_at,
      paid: !!r.paid_at || !!r.payment_id,
      payment: r.payment_id
        ? {
            id: r.payment_id,
            method: r.payment_method,
            provider: r.provider,
            provider_txn_id: r.provider_txn_id,
            amount: r.payment_amount,
            status: r.payment_status,
            paid_at: r.paid_at,
          }
        : null,
    }));

    return res.json(rows);
  } catch (e) {
    console.error("Admin payments report error:", e);
    return res.status(500).json({ message: "Server error", error: String(e) });
  }
});

// ✅ User Register (run_event_db2) - NO "name" column used in DB
app.post("/api/register", async (req, res) => {
  try {
    const { email, password, first_name, last_name, name } = req.body ?? {};

    if (
      typeof email !== "string" ||
      typeof password !== "string" ||
      !email.trim() ||
      !password
    ) {
      return res.status(400).json({ message: "email and password required" });
    }

    const emailNorm = email.trim().toLowerCase();

    // รองรับส่ง name เดียว -> split เป็น first/last
    let fn = typeof first_name === "string" ? first_name.trim() : "";
    let ln = typeof last_name === "string" ? last_name.trim() : "";

    if (!fn && !ln && typeof name === "string" && name.trim()) {
      const parts = name.trim().split(/\s+/);
      fn = parts.shift() ?? "";
      ln = parts.join(" ");
    }

    // เช็คซ้ำ
    const existed = await pool.query(
      `select id from public.users where lower(email) = $1 limit 1`,
      [emailNorm]
    );
    if (existed.rowCount > 0) {
      return res.status(409).json({ message: "Email already exists" });
    }

    // roles ของคุณ runner = 4 (จากรูป)
    const RUNNER_ROLE_ID = 4; // จากตาราง roles ของคุณ runner = 4

    const created = await pool.query(
      `
      insert into public.users
        (email, password_hash, first_name, last_name, status, role_id, last_login_at, created_at, updated_at)
      values
        ($1, crypt($2, gen_salt('bf')), $3, $4, 'active', $5, null, now(), now())
      returning
        id, email, first_name, last_name, status, role_id, last_login_at, created_at, updated_at
      `,
      [emailNorm, password, fn || null, ln || null, RUNNER_ROLE_ID]
    );


    return res.status(201).json({ message: "Register success", user: created.rows[0] });
  } catch (e) {
    console.error("User register error:", e);
    return res.status(500).json({
      message: "Server error",
      error: e?.message || String(e),
      stack: e?.stack || null,
    });
  }
});

// ✅ User Login (run_event_db2) - uses password_hash + returns first_name/last_name
app.post("/api/login", async (req, res) => {
  try {
    const { email, password } = req.body ?? {};

    if (
      typeof email !== "string" ||
      typeof password !== "string" ||
      !email.trim() ||
      !password
    ) {
      return res.status(400).json({ message: "email and password required" });
    }

    const emailNorm = email.trim().toLowerCase();

    const q = await pool.query(
      `
      update public.users
      set last_login_at = now(), updated_at = now()
      where lower(email) = $1
        and password_hash = crypt($2, password_hash)
      returning id, email, first_name, last_name, status, role_id, created_at, last_login_at, updated_at
      `,
      [emailNorm, password]
    );

    if (q.rowCount === 0) return res.status(401).json({ message: "Invalid credentials" });

    const user = q.rows[0];
    if (user.status !== "active") {
      return res.status(403).json({
        message:
          user.status === "deleted"
            ? "Account deleted by admin"
            : "Account not active",
        status: String(user.status || "inactive").toLowerCase(),
      });
    }

    return res.json({ user });
  } catch (e) {
    console.error("User login error:", e);
    return res.status(500).json({
      message: "Server error",
      error: e?.message || String(e),
      stack: e?.stack || null,
    });
  }
});



app.use((err, req, res, next) => {
  if (err instanceof multer.MulterError) {
    console.error("❌ Multer Error:", err);
    return res.status(400).json({ message: `File upload error: ${err.message}` });
  } else if (err) {
    console.error("❌ Upload Error:", err);
    return res.status(400).json({ message: err.message || "Upload failed" });
  }
  next();
});

const PORT = Number(process.env.PORT) || 3000;
app.listen(PORT, "0.0.0.0", () => {
  console.log("API running on port", PORT);
});
