-- FR1.7 — administrator account management (view, deactivate, delete).
-- is_active is intentionally separate from is_locked (001_users.sql):
-- is_locked is a temporary, self-service lockout after 5 failed login
-- attempts that auto-clears after 30 minutes (FR1.4). is_active is an
-- explicit administrative action (PDPA data-deletion compliance / abuse
-- mitigation, see stakeholder analysis) that never auto-expires and can
-- only be changed by an admin.
ALTER TABLE users ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE users ADD COLUMN deactivated_at TIMESTAMP;

CREATE INDEX idx_users_is_active ON users(is_active);
CREATE INDEX idx_users_role ON users(role);
