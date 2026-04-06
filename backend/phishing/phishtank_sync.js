const {
  normalizeUrl: normalizeScanUrl,
  getDomainFromUrl,
  hashUrl,
} = require("./scan.js");

const DEFAULT_PHISHTANK_USER_AGENT = "phishtank/gathergo-demo-sync";
const PHISHTANK_SOURCE_NAME = "phishtank";

function getPhishTankAppKey() {
  return String(process.env.PHISHTANK_APP_KEY ?? "").trim();
}

function getPhishTankUserAgent() {
  return (
    String(process.env.PHISHTANK_USER_AGENT ?? "").trim() ||
    DEFAULT_PHISHTANK_USER_AGENT
  );
}

function buildPhishTankFeedUrl() {
  const appKey = getPhishTankAppKey();
  if (appKey) {
    return `http://data.phishtank.com/data/${encodeURIComponent(appKey)}/online-valid.json`;
  }
  return "http://data.phishtank.com/data/online-valid.json";
}

function normalizeUrl(url) {
  return normalizeScanUrl(url);
}

function extractDomain(url) {
  return getDomainFromUrl(url);
}

function buildUrlHash(normalizedUrl) {
  return hashUrl(normalizedUrl);
}

function parseBooleanLike(value) {
  if (typeof value === "boolean") return value;
  const normalized = String(value ?? "").trim().toLowerCase();
  return normalized === "true" || normalized === "yes" || normalized === "1";
}

function parseTimestamp(value) {
  const input = String(value ?? "").trim();
  if (!input) return null;
  const parsed = new Date(input);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function normalizeVerificationStatus(record) {
  const verified = parseBooleanLike(record?.verified);
  if (verified) return "verified";
  const online = parseBooleanLike(record?.online);
  return online ? "unverified" : "inactive";
}

function computeConfidenceScore(record) {
  const verified = parseBooleanLike(record?.verified);
  const online = parseBooleanLike(record?.online);
  if (verified && online) return 1;
  if (verified) return 0.95;
  if (online) return 0.7;
  return 0.45;
}

function buildSourceRef(record) {
  const phishId = String(record?.phish_id ?? "").trim();
  return phishId ? `phishtank:${phishId}` : null;
}

function mapPhishTankRecord(record, feedId) {
  const rawUrl = String(record?.url ?? "").trim();
  const normalizedUrl = normalizeUrl(rawUrl);
  if (!normalizedUrl) {
    return null;
  }

  // Keep URL shaping consistent with the live chat scanner so feed data and
  // runtime scans compare the same normalized values.
  const domain = extractDomain(normalizedUrl);
  const urlHash = buildUrlHash(normalizedUrl);
  const submissionTime = parseTimestamp(record?.submission_time);
  const verificationTime = parseTimestamp(record?.verification_time);
  const now = new Date();
  const sourceRef = buildSourceRef(record);

  return {
    feed_id: feedId ?? null,
    indicator_type: "url",
    raw_url: rawUrl,
    normalized_url: normalizedUrl,
    domain,
    url_hash: urlHash,
    verification_status: normalizeVerificationStatus(record),
    confidence_score: computeConfidenceScore(record),
    first_seen_at: submissionTime ?? verificationTime ?? now,
    last_seen_at: verificationTime ?? submissionTime ?? now,
    is_active: parseBooleanLike(record?.online),
    source_ref: sourceRef,
    phish_detail_url: String(record?.phish_detail_url ?? "").trim() || null,
    target: String(record?.target ?? "").trim() || null,
  };
}

function toComparableTimestamp(value) {
  if (!value) return null;
  const parsed = value instanceof Date ? value : new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed.toISOString();
}

function indicatorHasChanges(existing, nextRecord) {
  return (
    Number(existing.feed_id ?? 0) !== Number(nextRecord.feed_id ?? 0) ||
    String(existing.indicator_type ?? "") !== String(nextRecord.indicator_type ?? "") ||
    String(existing.raw_url ?? "") !== String(nextRecord.raw_url ?? "") ||
    String(existing.normalized_url ?? "") !== String(nextRecord.normalized_url ?? "") ||
    String(existing.domain ?? "") !== String(nextRecord.domain ?? "") ||
    String(existing.url_hash ?? "") !== String(nextRecord.url_hash ?? "") ||
    String(existing.verification_status ?? "") !== String(nextRecord.verification_status ?? "") ||
    Number(existing.confidence_score ?? 0) !== Number(nextRecord.confidence_score ?? 0) ||
    toComparableTimestamp(existing.first_seen_at) !==
      toComparableTimestamp(nextRecord.first_seen_at) ||
    toComparableTimestamp(existing.last_seen_at) !==
      toComparableTimestamp(nextRecord.last_seen_at) ||
    Boolean(existing.is_active) !== Boolean(nextRecord.is_active) ||
    String(existing.source_ref ?? "") !== String(nextRecord.source_ref ?? "") ||
    String(existing.source_name ?? "") !== PHISHTANK_SOURCE_NAME ||
    String(existing.source_ref_url ?? "") !== String(nextRecord.phish_detail_url ?? "") ||
    String(existing.target_name ?? "") !== String(nextRecord.target ?? "")
  );
}

async function ensurePhishingSyncTables(client) {
  await client.query(`
    CREATE TABLE IF NOT EXISTS public.phishing_feeds (
      id BIGSERIAL PRIMARY KEY,
      source_name TEXT NOT NULL,
      feed_url TEXT,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      last_synced_at TIMESTAMPTZ NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await client.query(
    `ALTER TABLE public.phishing_feeds ADD COLUMN IF NOT EXISTS source_name TEXT`
  );
  await client.query(
    `ALTER TABLE public.phishing_feeds ADD COLUMN IF NOT EXISTS feed_url TEXT`
  );
  await client.query(
    `ALTER TABLE public.phishing_feeds ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE`
  );
  await client.query(
    `ALTER TABLE public.phishing_feeds ADD COLUMN IF NOT EXISTS last_synced_at TIMESTAMPTZ NULL`
  );
  await client.query(
    `ALTER TABLE public.phishing_feeds ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
  );
  await client.query(
    `ALTER TABLE public.phishing_feeds ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
  );
  await client.query(
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_phishing_feeds_source_name_unique ON public.phishing_feeds (source_name)`
  );

  await client.query(`
    CREATE TABLE IF NOT EXISTS public.phishing_indicators (
      id BIGSERIAL PRIMARY KEY,
      feed_id BIGINT NULL REFERENCES public.phishing_feeds(id) ON DELETE SET NULL,
      indicator_type TEXT NOT NULL DEFAULT 'url',
      raw_url TEXT,
      normalized_url TEXT,
      domain TEXT,
      url_hash TEXT,
      verification_status TEXT NOT NULL DEFAULT 'unverified',
      confidence_score DOUBLE PRECISION NOT NULL DEFAULT 0,
      first_seen_at TIMESTAMPTZ NULL,
      last_seen_at TIMESTAMPTZ NULL,
      is_active BOOLEAN NOT NULL DEFAULT TRUE,
      source_ref TEXT NULL,
      source_name TEXT NULL,
      source_ref_url TEXT NULL,
      target_name TEXT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS feed_id BIGINT NULL REFERENCES public.phishing_feeds(id) ON DELETE SET NULL`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS indicator_type TEXT NOT NULL DEFAULT 'url'`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS raw_url TEXT`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS normalized_url TEXT`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS domain TEXT`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS url_hash TEXT`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS verification_status TEXT NOT NULL DEFAULT 'unverified'`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS confidence_score DOUBLE PRECISION NOT NULL DEFAULT 0`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS first_seen_at TIMESTAMPTZ NULL`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS last_seen_at TIMESTAMPTZ NULL`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS source_ref TEXT NULL`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS source_name TEXT NULL`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS source_ref_url TEXT NULL`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS target_name TEXT NULL`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
  );
  await client.query(
    `ALTER TABLE public.phishing_indicators ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()`
  );
  await client.query(
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_phishing_indicators_source_ref_unique ON public.phishing_indicators (source_ref) WHERE source_ref IS NOT NULL`
  );
  await client.query(
    `CREATE UNIQUE INDEX IF NOT EXISTS idx_phishing_indicators_normalized_url_unique ON public.phishing_indicators (normalized_url) WHERE normalized_url IS NOT NULL`
  );
  await client.query(
    `CREATE INDEX IF NOT EXISTS idx_phishing_indicators_domain ON public.phishing_indicators (domain)`
  );
  await client.query(
    `CREATE INDEX IF NOT EXISTS idx_phishing_indicators_url_hash ON public.phishing_indicators (url_hash)`
  );
}

async function ensurePhishingFeedRow(client, feedUrl, { dryRun = false } = {}) {
  if (dryRun) {
    const existing = await client.query(
      `
      SELECT id, source_name, feed_url, last_synced_at
      FROM public.phishing_feeds
      WHERE source_name = $1
      LIMIT 1
      `,
      [PHISHTANK_SOURCE_NAME]
    );
    return existing.rows[0] ?? {
      id: null,
      source_name: PHISHTANK_SOURCE_NAME,
      feed_url: feedUrl,
      last_synced_at: null,
    };
  }

  const upserted = await client.query(
    `
    INSERT INTO public.phishing_feeds
      (source_name, feed_url, is_active, created_at, updated_at)
    VALUES
      ($1, $2, TRUE, NOW(), NOW())
    ON CONFLICT (source_name)
    DO UPDATE SET
      feed_url = EXCLUDED.feed_url,
      is_active = TRUE,
      updated_at = NOW()
    RETURNING id, source_name, feed_url, last_synced_at
    `,
    [PHISHTANK_SOURCE_NAME, feedUrl]
  );
  return upserted.rows[0] ?? null;
}

async function findExistingIndicator(client, mappedRecord) {
  const result = await client.query(
    `
    SELECT
      id,
      feed_id,
      indicator_type,
      raw_url,
      normalized_url,
      domain,
      url_hash,
      verification_status,
      confidence_score,
      first_seen_at,
      last_seen_at,
      is_active,
      source_ref,
      source_name,
      source_ref_url,
      target_name
    FROM public.phishing_indicators
    WHERE
      ($1::text IS NOT NULL AND source_ref = $1)
      OR ($2::text IS NOT NULL AND normalized_url = $2)
    ORDER BY
      CASE WHEN source_ref = $1 THEN 0 ELSE 1 END,
      id DESC
    LIMIT 1
    `,
    [mappedRecord.source_ref, mappedRecord.normalized_url]
  );
  return result.rows[0] ?? null;
}

async function insertIndicator(client, mappedRecord) {
  await client.query(
    `
    INSERT INTO public.phishing_indicators
      (
        feed_id,
        indicator_type,
        raw_url,
        normalized_url,
        domain,
        url_hash,
        verification_status,
        confidence_score,
        first_seen_at,
        last_seen_at,
        is_active,
        source_ref,
        source_name,
        source_ref_url,
        target_name,
        created_at,
        updated_at
      )
    VALUES
      ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, NOW(), NOW())
    `,
    [
      mappedRecord.feed_id,
      mappedRecord.indicator_type,
      mappedRecord.raw_url,
      mappedRecord.normalized_url,
      mappedRecord.domain,
      mappedRecord.url_hash,
      mappedRecord.verification_status,
      mappedRecord.confidence_score,
      mappedRecord.first_seen_at,
      mappedRecord.last_seen_at,
      mappedRecord.is_active,
      mappedRecord.source_ref,
      PHISHTANK_SOURCE_NAME,
      mappedRecord.phish_detail_url,
      mappedRecord.target,
    ]
  );
}

async function updateIndicator(client, indicatorId, mappedRecord) {
  await client.query(
    `
    UPDATE public.phishing_indicators
    SET
      feed_id = $2,
      indicator_type = $3,
      raw_url = $4,
      normalized_url = $5,
      domain = $6,
      url_hash = $7,
      verification_status = $8,
      confidence_score = $9,
      first_seen_at = $10,
      last_seen_at = $11,
      is_active = $12,
      source_ref = $13,
      source_name = $14,
      source_ref_url = $15,
      target_name = $16,
      updated_at = NOW()
    WHERE id = $1
    `,
    [
      indicatorId,
      mappedRecord.feed_id,
      mappedRecord.indicator_type,
      mappedRecord.raw_url,
      mappedRecord.normalized_url,
      mappedRecord.domain,
      mappedRecord.url_hash,
      mappedRecord.verification_status,
      mappedRecord.confidence_score,
      mappedRecord.first_seen_at,
      mappedRecord.last_seen_at,
      mappedRecord.is_active,
      mappedRecord.source_ref,
      PHISHTANK_SOURCE_NAME,
      mappedRecord.phish_detail_url,
      mappedRecord.target,
    ]
  );
}

async function downloadPhishTankFeed({
  feedUrl = buildPhishTankFeedUrl(),
  userAgent = getPhishTankUserAgent(),
} = {}) {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30000);

  console.log("[phishtank] feed_url:", feedUrl);
  try {
    const response = await fetch(feedUrl, {
      method: "GET",
      headers: {
        "User-Agent": userAgent,
        Accept: "application/json",
      },
      signal: controller.signal,
    });

    if (!response.ok) {
      const bodyPreview = (await response.text()).slice(0, 300);
      throw new Error(
        `PhishTank feed request failed: HTTP ${response.status} ${response.statusText}${
          bodyPreview ? ` - ${bodyPreview}` : ""
        }`
      );
    }

    const payload = await response.json();
    if (!Array.isArray(payload)) {
      throw new Error("PhishTank feed payload is not a JSON array");
    }

    return payload;
  } finally {
    clearTimeout(timeout);
  }
}

async function syncPhishTankFeed(client, options = {}) {
  const dryRun = options.dryRun === true;
  const feedUrl = options.feedUrl || buildPhishTankFeedUrl();
  const userAgent = options.userAgent || getPhishTankUserAgent();

  const summary = {
    source: PHISHTANK_SOURCE_NAME,
    dry_run: dryRun,
    feed_url: feedUrl,
    user_agent: userAgent,
    fetched: 0,
    inserted: 0,
    updated: 0,
    skipped: 0,
    failed: 0,
  };

  // Download the hourly JSON feed once, then upsert rows into our local
  // indicator table so chat lookups stay fast and simple.
  const records = await downloadPhishTankFeed({ feedUrl, userAgent });
  summary.fetched = records.length;
  console.log("[phishtank] records_fetched:", summary.fetched);

  await ensurePhishingSyncTables(client);

  if (!dryRun) {
    await client.query("BEGIN");
  }

  try {
    const feedRow = await ensurePhishingFeedRow(client, feedUrl, { dryRun });
    const feedId = feedRow?.id ?? null;

    for (const record of records) {
      try {
        const mapped = mapPhishTankRecord(record, feedId);
        if (!mapped) {
          summary.skipped += 1;
          continue;
        }

        const existing = await findExistingIndicator(client, mapped);
        if (!existing) {
          if (!dryRun) {
            await insertIndicator(client, mapped);
          }
          summary.inserted += 1;
          continue;
        }

        if (!indicatorHasChanges(existing, mapped)) {
          summary.skipped += 1;
          continue;
        }

        if (!dryRun) {
          await updateIndicator(client, existing.id, mapped);
        }
        summary.updated += 1;
      } catch (recordError) {
        summary.failed += 1;
        console.error(
          "[phishtank] record_sync_failed:",
          recordError?.message ?? recordError
        );
      }
    }

    if (!dryRun && feedId != null) {
      await client.query(
        `
        UPDATE public.phishing_feeds
        SET last_synced_at = NOW(), updated_at = NOW()
        WHERE id = $1
        `,
        [feedId]
      );
    }

    if (!dryRun) {
      await client.query("COMMIT");
    }

    console.log(
      "[phishtank] sync_success:",
      JSON.stringify({
        fetched: summary.fetched,
        inserted: summary.inserted,
        updated: summary.updated,
        skipped: summary.skipped,
        failed: summary.failed,
        dry_run: summary.dry_run,
      })
    );

    return summary;
  } catch (error) {
    if (!dryRun) {
      try {
        await client.query("ROLLBACK");
      } catch (_) {}
    }
    console.error("[phishtank] sync_failed:", error?.message ?? error);
    throw error;
  }
}

module.exports = {
  PHISHTANK_SOURCE_NAME,
  buildPhishTankFeedUrl,
  buildUrlHash,
  downloadPhishTankFeed,
  ensurePhishingSyncTables,
  extractDomain,
  getPhishTankAppKey,
  getPhishTankUserAgent,
  mapPhishTankRecord,
  normalizeUrl,
  syncPhishTankFeed,
};
