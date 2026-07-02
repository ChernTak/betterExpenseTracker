const db = require('../config/db');

exports.createToken = (userId, tokenHash, expiresAt) => {
  const query = `
    INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
    VALUES ($1, $2, $3)
    RETURNING token_id
  `;
  return db.query(query, [userId, tokenHash, expiresAt]);
};

exports.findValidToken = (tokenHash) => {
  const query = `
    SELECT * FROM password_reset_tokens
    WHERE token_hash = $1 AND used = FALSE AND expires_at > NOW()
  `;
  return db.query(query, [tokenHash]);
};

exports.markUsed = (tokenId) => {
  return db.query('UPDATE password_reset_tokens SET used = TRUE WHERE token_id = $1', [tokenId]);
};
