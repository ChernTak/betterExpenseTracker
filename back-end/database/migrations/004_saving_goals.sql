CREATE TABLE saving_goals (
  goal_id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID REFERENCES users(user_id) ON DELETE CASCADE,
  goal_name          VARCHAR(255) NOT NULL,
  target_amount      NUMERIC(12, 2) CHECK (target_amount > 0) NOT NULL,
  current_saved      NUMERIC(12, 2) CHECK (current_saved >= 0) NOT NULL DEFAULT 0,
  deadline_date      DATE,
  status             goal_status NOT NULL DEFAULT 'active',
  priority           SMALLINT NOT NULL DEFAULT 1,
  icon               VARCHAR(50),
  notes              TEXT,
  created_at         TIMESTAMP DEFAULT NOW(),
  updated_at         TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_saving_goals_user_id ON saving_goals(user_id);