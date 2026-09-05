const { Pool, types } = require('pg');

// pg returns NUMERIC columns as strings; parse to floats so clients get JSON numbers.
types.setTypeParser(types.builtins.NUMERIC, (value) => (value === null ? null : parseFloat(value)));

// pg's default DATE parser builds a JS Date at local midnight, which silently shifts to the previous day on serialize in UTC+8; return the raw 'YYYY-MM-DD' string instead to avoid the whole bug class.
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