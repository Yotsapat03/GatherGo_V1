require('dotenv').config();
const { pool } = require('./db.js');

(async () => {
  try {
    const needed = [
      'qr_url',
      'qr_payment_method',
      'distance_per_lap',
      'number_of_laps',
      'total_distance',
    ];

    const check = await pool.query(
      `
      SELECT column_name
      FROM information_schema.columns
      WHERE table_name='events'
        AND column_name = ANY($1::text[])
      ORDER BY ordinal_position
      `,
      [needed]
    );

    if (check.rows.length === needed.length) {
      console.log('Migration already applied:');
      check.rows.forEach((r) => console.log('  - ' + r.column_name));
      process.exit(0);
    }

    console.log('Running migration...');

    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS qr_url TEXT;`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS qr_payment_method VARCHAR(50);`);
    await pool.query(`CREATE INDEX IF NOT EXISTS idx_events_qr_url ON events(qr_url);`);

    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS distance_per_lap NUMERIC(12, 3);`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS number_of_laps INTEGER;`);
    await pool.query(`ALTER TABLE events ADD COLUMN IF NOT EXISTS total_distance NUMERIC(12, 3);`);

    console.log('Migration applied successfully');

    const verify = await pool.query(
      `
      SELECT column_name, data_type
      FROM information_schema.columns
      WHERE table_name='events'
        AND column_name = ANY($1::text[])
      ORDER BY ordinal_position
      `,
      [needed]
    );

    console.log('Columns verified:');
    verify.rows.forEach((r) => console.log(`  - ${r.column_name} (${r.data_type})`));
  } catch (e) {
    console.error('Migration error:', e.message);
  } finally {
    pool.end();
  }
})();

