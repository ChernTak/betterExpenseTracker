const { Pool, types } = require('pg');

// pg returns NUMERIC/DECIMAL columns (amount, monthly_limit, current_spend,
// utilization_pct, ...) as strings by default to avoid float precision loss.
// The API and Flutter client both expect these as JSON numbers, so parse
// them here once rather than at every call site.
types.setTypeParser(types.builtins.NUMERIC, (value) => (value === null ? null : parseFloat(value)));

// pg's default DATE parser builds a JS Date at LOCAL midnight (e.g.
// '2026-07-01' becomes 2026-06-30T16:00Z on this UTC+8 host). That's fine
// for code that immediately normalizes it (forecaster.js's toDateOnly), but
// anything that serializes the Date directly (res.json, or new Date(x)
// followed by getUTC*()) silently reads back the PREVIOUS calendar day.
// Confirmed this actually breaking two places: income edit round-trips
// (income_history_screen.dart re-sending the already-shifted date) and
// expense.service.js's own budget-month lookup for expenses near a month
// boundary. Returning the raw 'YYYY-MM-DD' string instead sidesteps the
// whole category of bug — a date-only string has no timezone to shift.
types.setTypeParser(types.builtins.DATE, (value) => value);

const pool = new Pool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  port: process.env.DB_PORT,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME
})

pool.query('SELECT NOW()', (err) => {
  if (err) console.error('Database connection failed:', err.message);
  else console.log('Database connected');
});

module.exports = pool;