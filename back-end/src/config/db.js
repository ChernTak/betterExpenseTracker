const { Pool, types } = require('pg');

// pg returns NUMERIC/DECIMAL columns (amount, monthly_limit, current_spend,
// utilization_pct, ...) as strings by default to avoid float precision loss.
// The API and Flutter client both expect these as JSON numbers, so parse
// them here once rather than at every call site.
types.setTypeParser(types.builtins.NUMERIC, (value) => (value === null ? null : parseFloat(value)));

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