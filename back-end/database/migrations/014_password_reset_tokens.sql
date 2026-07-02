CREATE TABLE password_reset_tokens (
  token_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  token_hash          VARCHAR(255) NOT NULL UNIQUE,
  expires_at          TIMESTAMP NOT NULL,
  used                BOOLEAN NOT NULL DEFAULT FALSE,
  created_at          TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_password_reset_user_id ON password_reset_tokens(user_id);
CREATE INDEX idx_password_reset_token_hash ON password_reset_tokens(token_hash);
