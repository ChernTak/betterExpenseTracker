CREATE TABLE users (
  user_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email              VARCHAR(255) UNIQUE NOT NULL,
  username           VARCHAR(50) NOT NULL,
  password_hash      VARCHAR(255) NOT NULL,
  mobile_number      VARCHAR(20),
  profile_picture    TEXT,
  monthly_income     NUMERIC(12, 2) CHECK (monthly_income >= 0) DEFAULT 0,
  fail_count         SMALLINT NOT NULL DEFAULT 0 CHECK (fail_count >= 0),
  is_locked          BOOLEAN NOT NULL DEFAULT FALSE,
  role               user_role NOT NULL DEFAULT 'user',
  fcm_token          TEXT,
  preferred_currency VARCHAR(3) NOT NULL DEFAULT 'MYR',
  timezone           VARCHAR(50) NOT NULL DEFAULT 'Asia/Kuala_Lumpur',
  location_consent   BOOLEAN NOT NULL DEFAULT FALSE,
  locked_until       TIMESTAMP,
  created_at         TIMESTAMP DEFAULT NOW(),
  updated_at         TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);