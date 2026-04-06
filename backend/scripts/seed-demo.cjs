require("dotenv").config();

const bcrypt = require("bcryptjs");
const { pool } = require("../db.js");

const DEMO_ADMIN_EMAIL = String(process.env.DEMO_ADMIN_EMAIL ?? "admin.demo@gathergo.local").trim().toLowerCase();
const DEMO_ADMIN_PASSWORD = String(process.env.DEMO_ADMIN_PASSWORD ?? "Admin123!").trim();
const DEMO_USER_PASSWORD = String(process.env.DEMO_USER_PASSWORD ?? "Runner123!").trim();
const DEMO_BOOKING_STATUS = "confirmed";
const DEMO_PAYMENT_STATUS = "paid";

async function getTableColumnSet(tableName) {
  const q = await pool.query(
    `
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = $1
    `,
    [tableName]
  );
  return new Set(q.rows.map((row) => String(row.column_name)));
}

async function getColumnEnumLabels(tableName, columnName) {
  const q = await pool.query(
    `
    SELECT e.enumlabel
    FROM pg_type t
    JOIN pg_enum e ON e.enumtypid = t.oid
    JOIN pg_attribute a ON a.atttypid = t.oid
    JOIN pg_class c ON c.oid = a.attrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = $1
      AND a.attname = $2
    ORDER BY e.enumsortorder
    `,
    [tableName, columnName]
  );
  return q.rows.map((row) => String(row.enumlabel));
}

async function pickEnumSafe(tableName, columnName, incomingValue) {
  const labels = await getColumnEnumLabels(tableName, columnName);
  if (!labels || labels.length === 0) return incomingValue ?? null;
  if (incomingValue && labels.includes(incomingValue)) return incomingValue;
  return labels[0];
}

async function upsertAdminUser({ email, password, firstName, lastName }) {
  const passwordHash = await bcrypt.hash(password, 10);
  const columns = await getTableColumnSet("admin_users");
  const existingQ = await pool.query(
    `SELECT id FROM public.admin_users WHERE LOWER(email) = $1 LIMIT 1`,
    [email]
  );

  if (existingQ.rowCount > 0) {
    const values = [existingQ.rows[0].id];
    const sets = [];
    let paramIndex = 2;

    if (columns.has("password_hash")) {
      sets.push(`password_hash = $${paramIndex++}`);
      values.push(passwordHash);
    }
    if (columns.has("first_name")) {
      sets.push(`first_name = $${paramIndex++}`);
      values.push(firstName);
    }
    if (columns.has("last_name")) {
      sets.push(`last_name = $${paramIndex++}`);
      values.push(lastName);
    }
    if (columns.has("status")) {
      sets.push(`status = 'active'`);
    }
    if (columns.has("updated_at")) {
      sets.push(`updated_at = NOW()`);
    }

    const updatedQ = await pool.query(
      `
      UPDATE public.admin_users
      SET ${sets.join(", ")}
      WHERE id = $1
      RETURNING id, email
      `,
      values
    );
    return updatedQ.rows[0];
  }

  const fieldNames = ["email"];
  const placeholders = ["$1"];
  const values = [email];
  let paramIndex = 2;

  if (columns.has("password_hash")) {
    fieldNames.push("password_hash");
    placeholders.push(`$${paramIndex++}`);
    values.push(passwordHash);
  }
  if (columns.has("first_name")) {
    fieldNames.push("first_name");
    placeholders.push(`$${paramIndex++}`);
    values.push(firstName);
  }
  if (columns.has("last_name")) {
    fieldNames.push("last_name");
    placeholders.push(`$${paramIndex++}`);
    values.push(lastName);
  }
  if (columns.has("status")) {
    fieldNames.push("status");
    placeholders.push(`$${paramIndex++}`);
    values.push("active");
  }
  if (columns.has("created_at")) {
    fieldNames.push("created_at");
    placeholders.push("NOW()");
  }
  if (columns.has("updated_at")) {
    fieldNames.push("updated_at");
    placeholders.push("NOW()");
  }

  const insertedQ = await pool.query(
    `
    INSERT INTO public.admin_users (${fieldNames.join(", ")})
    VALUES (${placeholders.join(", ")})
    RETURNING id, email
    `,
    values
  );
  return insertedQ.rows[0];
}

async function upsertUser({
  email,
  password,
  name,
  phone,
  address,
  firstName,
  lastName,
}) {
  const emailNorm = String(email).trim().toLowerCase();
  const passwordHash = await bcrypt.hash(password, 10);
  const columns = await getTableColumnSet("users");
  const existingQ = await pool.query(
    `SELECT id FROM public.users WHERE LOWER(email) = $1 LIMIT 1`,
    [emailNorm]
  );

  if (existingQ.rowCount > 0) {
    const values = [existingQ.rows[0].id];
    const sets = [];
    let paramIndex = 2;

    const optionalAssignments = [
      ["name", name],
      ["phone", phone],
      ["address", address],
      ["password_hash", passwordHash],
      ["first_name", firstName],
      ["last_name", lastName],
    ];

    for (const [columnName, value] of optionalAssignments) {
      if (!columns.has(columnName)) continue;
      sets.push(`${columnName} = $${paramIndex++}`);
      values.push(value);
    }
    if (columns.has("status")) {
      sets.push(`status = 'active'`);
    }
    if (columns.has("updated_at")) {
      sets.push(`updated_at = NOW()`);
    }

    const updatedQ = await pool.query(
      `
      UPDATE public.users
      SET ${sets.join(", ")}
      WHERE id = $1
      RETURNING id, email, name
      `,
      values
    );
    return updatedQ.rows[0];
  }

  const fieldNames = [];
  const placeholders = [];
  const values = [];
  let paramIndex = 1;

  const optionalInsertFields = [
    ["name", name],
    ["email", emailNorm],
    ["phone", phone],
    ["address", address],
    ["password_hash", passwordHash],
    ["first_name", firstName],
    ["last_name", lastName],
  ];

  for (const [columnName, value] of optionalInsertFields) {
    if (!columns.has(columnName)) continue;
    fieldNames.push(columnName);
    placeholders.push(`$${paramIndex++}`);
    values.push(value);
  }
  if (columns.has("status")) {
    fieldNames.push("status");
    placeholders.push(`$${paramIndex++}`);
    values.push("active");
  }
  if (columns.has("created_at")) {
    fieldNames.push("created_at");
    placeholders.push("NOW()");
  }
  if (columns.has("updated_at")) {
    fieldNames.push("updated_at");
    placeholders.push("NOW()");
  }

  const insertedQ = await pool.query(
    `
    INSERT INTO public.users (${fieldNames.join(", ")})
    VALUES (${placeholders.join(", ")})
    RETURNING id, email, name
    `,
    values
  );
  return insertedQ.rows[0];
}

async function ensureDemoSpot(ownerUserId, memberUserId) {
  const title = "Demo Morning Spot";
  const spotColumns = await getTableColumnSet("spot_events");
  const memberColumns = await getTableColumnSet("spot_event_members");
  const bookingColumns = await getTableColumnSet("spot_event_bookings");
  let ownerBookingReference = null;
  let memberBookingReference = null;
  const existingQ = await pool.query(
    `
    SELECT id
    FROM public.spot_events
    WHERE title = $1
      AND created_by_user_id = $2
    LIMIT 1
    `,
    [title, ownerUserId]
  );

  let spotId = existingQ.rows[0]?.id ?? null;
  if (!spotId) {
    const fieldNames = [];
    const placeholders = [];
    const values = [];
    let paramIndex = 1;
    const insertValues = {
      title,
      description: "Demo spot for repository setup verification",
      location: "Lumpini Park",
      province: "Bangkok",
      district: "Pathum Wan",
      event_date: "2026-05-01",
      event_time: "06:00",
      km_per_round: 5,
      round_count: 1,
      max_people: 10,
      status: "open",
      created_by_user_id: ownerUserId,
      creator_role: "user",
    };

    for (const [columnName, value] of Object.entries(insertValues)) {
      if (!spotColumns.has(columnName)) continue;
      fieldNames.push(columnName);
      placeholders.push(`$${paramIndex++}`);
      values.push(value);
    }
    if (spotColumns.has("created_at")) {
      fieldNames.push("created_at");
      placeholders.push("NOW()");
    }
    if (spotColumns.has("updated_at")) {
      fieldNames.push("updated_at");
      placeholders.push("NOW()");
    }

    const insertedQ = await pool.query(
      `
      INSERT INTO public.spot_events (${fieldNames.join(", ")})
      VALUES (${placeholders.join(", ")})
      RETURNING id
      `,
      values
    );
    spotId = insertedQ.rows[0]?.id ?? null;
  }

  if (!spotId) return null;

  ownerBookingReference = `SB-${String(spotId).padStart(6, "0")}-01`;
  memberBookingReference = `SB-${String(spotId).padStart(6, "0")}-02`;

  const memberFieldNames = [];
  const memberNowFields = [];
  if (memberColumns.has("spot_event_id")) memberFieldNames.push("spot_event_id");
  if (memberColumns.has("user_id")) memberFieldNames.push("user_id");
  if (memberColumns.has("joined_at")) {
    memberFieldNames.push("joined_at");
    memberNowFields.push("joined_at");
  }
  if (memberColumns.has("created_at")) {
    memberFieldNames.push("created_at");
    memberNowFields.push("created_at");
  }
  if (memberColumns.has("updated_at")) {
    memberFieldNames.push("updated_at");
    memberNowFields.push("updated_at");
  }

  const buildSpotMemberParams = (userId) => {
    const values = [];
    let paramIndex = 1;
    const placeholders = memberFieldNames.map((field) => {
      if (memberNowFields.includes(field)) return "NOW()";
      values.push(field === "spot_event_id" ? spotId : userId);
      return `$${paramIndex++}`;
    });
    return { values, placeholders };
  };

  for (const userId of [ownerUserId, memberUserId]) {
    const { values, placeholders } = buildSpotMemberParams(userId);
    await pool.query(
      `
      INSERT INTO public.spot_event_members (${memberFieldNames.join(", ")})
      VALUES (${placeholders.join(", ")})
      ON CONFLICT (spot_event_id, user_id) DO NOTHING
      `,
      values
    );
  }

  const bookingFieldNames = [];
  const bookingNowFields = [];
  if (bookingColumns.has("spot_event_id")) bookingFieldNames.push("spot_event_id");
  if (bookingColumns.has("user_id")) bookingFieldNames.push("user_id");
  if (bookingColumns.has("booking_reference")) bookingFieldNames.push("booking_reference");
  if (bookingColumns.has("status")) bookingFieldNames.push("status");
  if (bookingColumns.has("created_at")) {
    bookingFieldNames.push("created_at");
    bookingNowFields.push("created_at");
  }
  if (bookingColumns.has("updated_at")) {
    bookingFieldNames.push("updated_at");
    bookingNowFields.push("updated_at");
  }

  const buildSpotBookingParams = (userId, bookingReference) => {
    const values = [];
    let paramIndex = 1;
    const placeholders = bookingFieldNames.map((field) => {
      if (bookingNowFields.includes(field)) return "NOW()";
      if (field === "spot_event_id") {
        values.push(spotId);
      } else if (field === "user_id") {
        values.push(userId);
      } else if (field === "booking_reference") {
        values.push(bookingReference);
      } else if (field === "status") {
        values.push("booked");
      }
      return `$${paramIndex++}`;
    });
    return { values, placeholders };
  };

  for (const [userId, bookingReference] of [
    [ownerUserId, ownerBookingReference],
    [memberUserId, memberBookingReference],
  ]) {
    const { values, placeholders } = buildSpotBookingParams(userId, bookingReference);
    await pool.query(
      `
      INSERT INTO public.spot_event_bookings (${bookingFieldNames.join(", ")})
      VALUES (${placeholders.join(", ")})
      ON CONFLICT (spot_event_id, user_id) DO NOTHING
      `,
      values
    );
  }

  return spotId;
}

async function ensureDemoOrganization() {
  const name = "GatherGo Demo Org";
  const columns = await getTableColumnSet("organizations");
  const existingQ = await pool.query(
    `SELECT id FROM public.organizations WHERE name = $1 LIMIT 1`,
    [name]
  );
  if (existingQ.rowCount > 0) return existingQ.rows[0].id;

  const fieldNames = [];
  const placeholders = [];
  const values = [];
  let paramIndex = 1;

  if (columns.has("name")) {
    fieldNames.push("name");
    placeholders.push(`$${paramIndex++}`);
    values.push(name);
  }
  if (columns.has("created_at")) {
    fieldNames.push("created_at");
    placeholders.push("NOW()");
  }
  if (columns.has("updated_at")) {
    fieldNames.push("updated_at");
    placeholders.push("NOW()");
  }

  const insertedQ = await pool.query(
    `
    INSERT INTO public.organizations (${fieldNames.join(", ")})
    VALUES (${placeholders.join(", ")})
    RETURNING id
    `,
    values
  );
  return insertedQ.rows[0]?.id ?? null;
}

async function ensureDemoBigEvent({ organizationId, userId }) {
  if (!organizationId || !userId) return null;

  const title = "Demo Big Event";
  const columns = await getTableColumnSet("events");
  const existingQ = await pool.query(
    `
    SELECT id
    FROM public.events
    WHERE title = $1
      AND organization_id = $2
    LIMIT 1
    `,
    [title, organizationId]
  );
  if (existingQ.rowCount > 0) return existingQ.rows[0].id;

  const eventValues = {
    type: "BIG_EVENT",
    created_by: userId,
    title,
    description: "Demo big event for local repository review",
    meeting_point: "Benjakitti Park",
    location_name: "Benjakitti Park",
    city: "Bangkok",
    province: "Bangkok",
    district: "Khlong Toei",
    max_participants: 100,
    visibility: "public",
    status: "published",
    organization_id: organizationId,
    fee: 300,
    currency: "THB",
    payment_mode: "manual_qr",
    enable_promptpay: true,
    enable_alipay: false,
    promptpay_enabled: true,
    alipay_enabled: false,
    promptpay_amount_thb: 300,
  };

  const fieldNames = [];
  const placeholders = [];
  const values = [];
  let paramIndex = 1;

  for (const [columnName, value] of Object.entries(eventValues)) {
    if (!columns.has(columnName)) continue;
    fieldNames.push(columnName);
    placeholders.push(`$${paramIndex++}`);
    values.push(value);
  }
  if (columns.has("start_at")) {
    fieldNames.push("start_at");
    placeholders.push("NOW() + INTERVAL '7 days'");
  }
  if (columns.has("end_at")) {
    fieldNames.push("end_at");
    placeholders.push("NOW() + INTERVAL '7 days 4 hours'");
  }
  if (columns.has("created_at")) {
    fieldNames.push("created_at");
    placeholders.push("NOW()");
  }
  if (columns.has("updated_at")) {
    fieldNames.push("updated_at");
    placeholders.push("NOW()");
  }

  const insertedQ = await pool.query(
    `
    INSERT INTO public.events (${fieldNames.join(", ")})
    VALUES (${placeholders.join(", ")})
    RETURNING id
    `,
    values
  );
  return insertedQ.rows[0]?.id ?? null;
}

function buildBookingReference(bookingId) {
  return `BK-${String(bookingId).padStart(6, "0")}`;
}

function buildPaymentReference(paymentId) {
  return `PAY-${String(paymentId).padStart(6, "0")}`;
}

function buildReceiptNumber(paymentId) {
  return `RC-${String(paymentId).padStart(6, "0")}`;
}

async function ensureDemoBooking({ eventId, userId, shirtSize = "M" }) {
  if (!eventId || !userId) return null;
  const columns = await getTableColumnSet("bookings");

  const existingQ = await pool.query(
    `
    SELECT id
    FROM public.bookings
    WHERE event_id = $1
      AND user_id = $2
    LIMIT 1
    `,
    [eventId, userId]
  );

  let bookingId = existingQ.rows[0]?.id ?? null;
  if (!bookingId) {
    const fieldNames = [];
    const placeholders = [];
    const values = [];
    let paramIndex = 1;
    const insertValues = {
      user_id: userId,
      event_id: eventId,
      quantity: 1,
      total_amount: 300,
      currency: "THB",
      status: DEMO_BOOKING_STATUS,
      shirt_size: shirtSize,
    };
    for (const [columnName, value] of Object.entries(insertValues)) {
      if (!columns.has(columnName)) continue;
      fieldNames.push(columnName);
      placeholders.push(`$${paramIndex++}`);
      values.push(value);
    }
    if (columns.has("created_at")) {
      fieldNames.push("created_at");
      placeholders.push("NOW()");
    }
    if (columns.has("updated_at")) {
      fieldNames.push("updated_at");
      placeholders.push("NOW()");
    }

    const insertedQ = await pool.query(
      `
      INSERT INTO public.bookings (${fieldNames.join(", ")})
      VALUES (${placeholders.join(", ")})
      RETURNING id
      `,
      values
    );
    bookingId = insertedQ.rows[0]?.id ?? null;
  }

  if (!bookingId) return null;

  await pool.query(
    `
    UPDATE public.bookings
    SET
      status = $2,
      shirt_size = $3,
      booking_reference = COALESCE(NULLIF(TRIM(booking_reference), ''), $4),
      updated_at = NOW()
    WHERE id = $1
    `,
    [bookingId, DEMO_BOOKING_STATUS, shirtSize, buildBookingReference(bookingId)]
  );

  return bookingId;
}

async function ensureDemoParticipant({ eventId, userId, bookingId, shirtSize = "M" }) {
  if (!eventId || !userId) return null;
  const columns = await getTableColumnSet("participants");
  const participantSource = columns.has("source")
    ? await pickEnumSafe("participants", "source", "booking")
    : null;
  const participantStatus = columns.has("status")
    ? await pickEnumSafe("participants", "status", "joined")
    : null;
  const existingQ = await pool.query(
    `
    SELECT id
    FROM public.participants
    WHERE event_id = $1
      AND user_id = $2
    LIMIT 1
    `,
    [eventId, userId]
  );

  if (existingQ.rowCount === 0) {
    const fieldNames = [];
    const placeholders = [];
    const values = [];
    let paramIndex = 1;
    const insertValues = {
      event_id: eventId,
      user_id: userId,
      booking_id: bookingId,
      source: participantSource,
      status: participantStatus,
      shirt_size: shirtSize,
    };
    for (const [columnName, value] of Object.entries(insertValues)) {
      if (!columns.has(columnName)) continue;
      fieldNames.push(columnName);
      placeholders.push(`$${paramIndex++}`);
      values.push(value);
    }
    if (columns.has("joined_at")) {
      fieldNames.push("joined_at");
      placeholders.push("NOW()");
    }
    if (columns.has("created_at")) {
      fieldNames.push("created_at");
      placeholders.push("NOW()");
    }
    if (columns.has("updated_at")) {
      fieldNames.push("updated_at");
      placeholders.push("NOW()");
    }

    await pool.query(
      `
      INSERT INTO public.participants (${fieldNames.join(", ")})
      VALUES (${placeholders.join(", ")})
      `,
      values
    );
    return;
  }

  const participantId = existingQ.rows[0].id;
  const values = [participantId];
  const sets = [];
  let paramIndex = 2;
  const updateValues = {
    booking_id: bookingId,
    source: participantSource,
    status: participantStatus,
    shirt_size: shirtSize,
  };
  for (const [columnName, value] of Object.entries(updateValues)) {
    if (!columns.has(columnName)) continue;
    sets.push(`${columnName} = COALESCE(${columnName}, $${paramIndex++})`);
    values.push(value);
  }
  if (columns.has("updated_at")) {
    sets.push("updated_at = NOW()");
  }

  if (sets.length === 0) return;

  await pool.query(
    `
    UPDATE public.participants
    SET ${sets.join(", ")}
    WHERE id = $1
    `,
    values
  );
}

async function ensureDemoPayment({ eventId, bookingId, amount = 300 }) {
  if (!bookingId) return null;
  const columns = await getTableColumnSet("payments");

  const existingQ = await pool.query(
    `
    SELECT id
    FROM public.payments
    WHERE booking_id = $1
    LIMIT 1
    `,
    [bookingId]
  );

  let paymentId = existingQ.rows[0]?.id ?? null;
  if (!paymentId) {
    const fieldNames = [];
    const placeholders = [];
    const values = [];
    let paramIndex = 1;
    const insertValues = {
      booking_id: bookingId,
      event_id: eventId,
      method: "promptpay",
      method_type: "PROMPTPAY",
      payment_method_type: "promptpay",
      provider: "manual_qr",
      provider_txn_id: `DEMO-TXN-${bookingId}`,
      amount,
      currency: "THB",
      status: DEMO_PAYMENT_STATUS,
    };
    for (const [columnName, value] of Object.entries(insertValues)) {
      if (!columns.has(columnName)) continue;
      fieldNames.push(columnName);
      placeholders.push(`$${paramIndex++}`);
      values.push(value);
    }
    if (columns.has("paid_at")) {
      fieldNames.push("paid_at");
      placeholders.push("NOW()");
    }
    if (columns.has("created_at")) {
      fieldNames.push("created_at");
      placeholders.push("NOW()");
    }
    if (columns.has("updated_at")) {
      fieldNames.push("updated_at");
      placeholders.push("NOW()");
    }

    const insertedQ = await pool.query(
      `
      INSERT INTO public.payments (${fieldNames.join(", ")})
      VALUES (${placeholders.join(", ")})
      RETURNING id
      `,
      values
    );
    paymentId = insertedQ.rows[0]?.id ?? null;
  }

  if (!paymentId) return null;

  await pool.query(
    `
    UPDATE public.payments
    SET
      event_id = COALESCE(event_id, $2),
      method = COALESCE(method, 'promptpay'),
      method_type = COALESCE(method_type, 'PROMPTPAY'),
      payment_method_type = COALESCE(payment_method_type, 'promptpay'),
      provider = COALESCE(provider, 'manual_qr'),
      provider_txn_id = COALESCE(provider_txn_id, $3),
      amount = CASE WHEN amount IS NULL OR amount = 0 THEN $4 ELSE amount END,
      currency = COALESCE(currency, 'THB'),
      status = $5,
      paid_at = COALESCE(paid_at, NOW()),
      payment_reference = COALESCE(NULLIF(TRIM(payment_reference), ''), $6),
      updated_at = NOW()
    WHERE id = $1
    `,
    [
      paymentId,
      eventId,
      `DEMO-TXN-${paymentId}`,
      amount,
      DEMO_PAYMENT_STATUS,
      buildPaymentReference(paymentId),
    ]
  );

  return paymentId;
}

async function ensureDemoReceipt({ paymentId, amount = 300 }) {
  if (!paymentId) return null;
  const columns = await getTableColumnSet("receipts");

  const receiptNo = buildReceiptNumber(paymentId);
  const existingQ = await pool.query(
    `
    SELECT id
    FROM public.receipts
    WHERE payment_id = $1
       OR receipt_no = $2
    LIMIT 1
    `,
    [paymentId, receiptNo]
  );

  let receiptId = existingQ.rows[0]?.id ?? null;
  if (!receiptId) {
    const fieldNames = [];
    const placeholders = [];
    const values = [];
    let paramIndex = 1;
    const insertValues = {
      payment_id: paymentId,
      receipt_no: receiptNo,
      amount,
      currency: "THB",
      pdf_url: `/api/receipts/${receiptNo}/view`,
    };
    for (const [columnName, value] of Object.entries(insertValues)) {
      if (!columns.has(columnName)) continue;
      fieldNames.push(columnName);
      placeholders.push(`$${paramIndex++}`);
      values.push(value);
    }
    if (columns.has("issue_date")) {
      fieldNames.push("issue_date");
      placeholders.push("NOW()");
    }
    if (columns.has("created_at")) {
      fieldNames.push("created_at");
      placeholders.push("NOW()");
    }
    if (columns.has("updated_at")) {
      fieldNames.push("updated_at");
      placeholders.push("NOW()");
    }

    const insertedQ = await pool.query(
      `
      INSERT INTO public.receipts (${fieldNames.join(", ")})
      VALUES (${placeholders.join(", ")})
      RETURNING id
      `,
      values
    );
    receiptId = insertedQ.rows[0]?.id ?? null;
  }

  if (!receiptId) return null;

  await pool.query(
    `
    UPDATE public.receipts
    SET
      payment_id = COALESCE(payment_id, $2),
      amount = CASE WHEN amount IS NULL OR amount = 0 THEN $3 ELSE amount END,
      currency = COALESCE(currency, 'THB'),
      issue_date = COALESCE(issue_date, NOW()),
      pdf_url = COALESCE(NULLIF(TRIM(pdf_url), ''), $4),
      updated_at = NOW()
    WHERE id = $1
    `,
    [receiptId, paymentId, amount, `/api/receipts/${receiptNo}/view`]
  );

  await pool.query(
    `
    UPDATE public.payments
    SET receipt_url = COALESCE(NULLIF(TRIM(receipt_url), ''), $2),
        updated_at = NOW()
    WHERE id = $1
    `,
    [paymentId, `/api/receipts/${receiptNo}/view`]
  );

  return receiptId;
}

async function main() {
  const admin = await upsertAdminUser({
    email: DEMO_ADMIN_EMAIL,
    password: DEMO_ADMIN_PASSWORD,
    firstName: "Demo",
    lastName: "Admin",
  });

  const userA = await upsertUser({
    email: "runner.one@gathergo.local",
    password: DEMO_USER_PASSWORD,
    name: "Runner One",
    phone: "0800000001",
    address: "Bangkok",
    firstName: "Runner",
    lastName: "One",
  });

  const userB = await upsertUser({
    email: "runner.two@gathergo.local",
    password: DEMO_USER_PASSWORD,
    name: "Runner Two",
    phone: "0800000002",
    address: "Bangkok",
    firstName: "Runner",
    lastName: "Two",
  });

  const hasSpotEventsTableQ = await pool.query(
    `SELECT to_regclass('public.spot_events') AS regclass`
  );
  let demoSpotId = null;
  let demoOrgId = null;
  let demoBigEventId = null;
  let demoBookingId = null;
  let demoPaymentId = null;
  let demoReceiptId = null;
  if (hasSpotEventsTableQ.rows[0]?.regclass) {
    demoSpotId = await ensureDemoSpot(userA.id, userB.id);
  }

  const hasEventTableQ = await pool.query(
    `SELECT to_regclass('public.events') AS regclass`
  );
  const hasOrganizationTableQ = await pool.query(
    `SELECT to_regclass('public.organizations') AS regclass`
  );
  if (hasEventTableQ.rows[0]?.regclass && hasOrganizationTableQ.rows[0]?.regclass) {
    demoOrgId = await ensureDemoOrganization();
    demoBigEventId = await ensureDemoBigEvent({
      organizationId: demoOrgId,
      userId: userA.id,
    });
    if (demoBigEventId) {
      demoBookingId = await ensureDemoBooking({
        eventId: demoBigEventId,
        userId: userB.id,
        shirtSize: "M",
      });
      await ensureDemoParticipant({
        eventId: demoBigEventId,
        userId: userB.id,
        bookingId: demoBookingId,
        shirtSize: "M",
      });
      demoPaymentId = await ensureDemoPayment({
        eventId: demoBigEventId,
        bookingId: demoBookingId,
        amount: 300,
      });
      demoReceiptId = await ensureDemoReceipt({
        paymentId: demoPaymentId,
        amount: 300,
      });
    }
  }

  console.log("Demo seed ready");
  console.log(`- Admin: ${admin.email} / ${DEMO_ADMIN_PASSWORD}`);
  console.log(`- User A: ${userA.email} / ${DEMO_USER_PASSWORD}`);
  console.log(`- User B: ${userB.email} / ${DEMO_USER_PASSWORD}`);
  if (demoSpotId) {
    console.log(`- Demo spot id: ${demoSpotId}`);
  }
  if (demoOrgId) {
    console.log(`- Demo organization id: ${demoOrgId}`);
  }
  if (demoBigEventId) {
    console.log(`- Demo big event id: ${demoBigEventId}`);
  }
  if (demoBookingId) {
    console.log(`- Demo booking id: ${demoBookingId}`);
  }
  if (demoPaymentId) {
    console.log(`- Demo payment id: ${demoPaymentId}`);
  }
  if (demoReceiptId) {
    console.log(`- Demo receipt id: ${demoReceiptId}`);
  }
}

main()
  .catch((error) => {
    console.error("seed-demo failed:", error.message);
    process.exitCode = 1;
  })
  .finally(async () => {
    await pool.end();
  });
