-- PDPA accountability — every admin action taken against a user record
-- (view, deactivate, reactivate, request/cancel deletion, purge, export)
-- is recorded here. target_email is a snapshot, not just a join to
-- users.email: once a user is purged (see admin_user_deletion_request
-- below), target_user_id goes NULL but the audit trail must still say
-- whose data was affected — erasure must not erase the evidence of
-- having handled the erasure request.
CREATE TABLE admin_audit_log (
  audit_id        SERIAL PRIMARY KEY,
  admin_id        UUID REFERENCES users(user_id) ON DELETE SET NULL,
  action          VARCHAR(50) NOT NULL,
  target_user_id  UUID REFERENCES users(user_id) ON DELETE SET NULL,
  target_email    VARCHAR(255),
  details         JSONB,
  created_at      TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_admin_audit_log_target_user ON admin_audit_log(target_user_id);
CREATE INDEX idx_admin_audit_log_admin ON admin_audit_log(admin_id);
CREATE INDEX idx_admin_audit_log_created_at ON admin_audit_log(created_at);
