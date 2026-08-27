const db = require('../config/db');

// Shared reference data (not user-specific) — see 040_high_risk_locations.sql
// and database/seeds/seed_high_risk_locations.js for how rows get populated.
exports.listAll = () => {
  return db.query('SELECT * FROM high_risk_locations ORDER BY name');
};

exports.getById = (locationId) => {
  return db.query('SELECT * FROM high_risk_locations WHERE location_id = $1', [locationId]);
};
