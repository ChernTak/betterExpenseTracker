CREATE TABLE user_sessions (
  session_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES users(user_id) ON DELETE CASCADE,
  jwt_jti             VARCHAR(255) NOT NULL UNIQUE,
  device_info         TEXT,
  ip_address          INET,
  issued_at           TIMESTAMP NOT NULL DEFAULT NOW(),
  expires_at          TIMESTAMP NOT NULL,
  revoked             BOOLEAN NOT NULL DEFAULT FALSE,
  revoked_at          TIMESTAMP
);

CREATE INDEX idx_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_sessions_jwt_jti ON user_sessions(jwt_jti);