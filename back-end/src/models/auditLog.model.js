const db = require('../config/db');

// target_email is stamped at insert so the row still identifies whose data was touched even after a purge nulls target_user_id.
exports.insert = ({ adminId, action, targetUserId, targetEmail, details }) => {
  const query = `
    INSERT INTO admin_audit_log (admin_id, action, target_user_id, target_email, details)
    VALUES ($1, $2, $3, $4, $5)
    RETURNING *
  `;
  return db.query(query, [adminId, action, targetUserId || null, targetEmail || null, JSON.stringify(details || {})]);
};

exports.findRecent = (limit) => {
  const query = `
    SELECT audit_id, admin_id, action, target_user_id, target_email, details, created_at
    FROM admin_audit_log
    ORDER BY created_at DESC
    LIMIT $1
  `;
  return db.query(query, [limit]);
};

exports.findForUser = (targetUserId) => {
  const query = `
    SELECT audit_id, admin_id, action, target_user_id, target_email, details, created_at
    FROM admin_audit_log
    WHERE target_user_id = $1
    ORDER BY created_at DESC
  `;
  return db.query(query, [targetUserId]);
};
