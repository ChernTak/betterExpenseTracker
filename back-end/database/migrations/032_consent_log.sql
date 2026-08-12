-- PDPA Notice & Choice principle — location_consent on users is a single
-- boolean that only reflects the current state. This table appends every
-- change so "when did this user grant/withdraw consent" is answerable,
-- which the boolean alone can't provide.
CREATE TABLE consent_log (
  consent_id    SERIAL PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  consent_type  VARCHAR(50) NOT NULL,
  granted       BOOLEAN NOT NULL,
  changed_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_consent_log_user ON consent_log(user_id);
